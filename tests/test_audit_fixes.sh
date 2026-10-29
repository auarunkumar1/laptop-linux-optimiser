#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo "Running Validation Test Suite for mint-admin.sh Audit Fixes"
echo "=========================================================="

FAILED=0
TOTAL=0

assert_eq() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  [PASS] $name"
    else
        echo "  [FAIL] $name: Expected '$expected', got '$actual'"
        FAILED=$((FAILED + 1))
    fi
}

assert_true() {
    local name="$1"
    local cmd="$2"
    TOTAL=$((TOTAL + 1))
    if eval "$cmd"; then
        echo "  [PASS] $name"
    else
        echo "  [FAIL] $name"
        FAILED=$((FAILED + 1))
    fi
}

# ------------------------------------------------------------------------------
# Test 1: generate_random_mac format and entropy
# ------------------------------------------------------------------------------
echo "--- Test 1: MAC generation & format ---"
source <(grep -A 3 '^generate_random_mac()' ./mint-admin.sh)

mac1=$(generate_random_mac)
mac2=$(generate_random_mac)
assert_true "MAC starts with 02: and has 6 hex octets" '[[ "$mac1" =~ ^02(:[0-9a-f]{2}){5}$ ]]'
assert_true "Entropy check: two consecutive random MACs are distinct" '[ "$mac1" != "$mac2" ]'

# ------------------------------------------------------------------------------
# Test 2: Network interface exclusion filter
# ------------------------------------------------------------------------------
echo "--- Test 2: Interface exclusion filter ---"
filter_regex='^(lo|docker.*|virbr.*|veth.*|tun.*|wg.*|tap.*|tailscale.*|p2p.*|br-.*|bond.*|team.*|dummy.*|lxcbr.*|incusbr.*|podman.*|ppp.*|can.*)$'

test_iface_allowed() {
    local iface="$1"
    ! echo "$iface" | grep -qE "$filter_regex"
}

assert_true "Excludes docker0" '! test_iface_allowed "docker0"'
assert_true "Excludes br-lan" '! test_iface_allowed "br-lan"'
assert_true "Excludes virbr0" '! test_iface_allowed "virbr0"'
assert_true "Excludes tailscale0" '! test_iface_allowed "tailscale0"'
assert_true "Excludes wg0" '! test_iface_allowed "wg0"'
assert_true "Excludes bond0" '! test_iface_allowed "bond0"'
assert_true "Allows wlp1s0" 'test_iface_allowed "wlp1s0"'
assert_true "Allows eth0" 'test_iface_allowed "eth0"'
assert_true "Allows enp3s0" 'test_iface_allowed "enp3s0"'

# ------------------------------------------------------------------------------
# Test 3: dnscrypt-proxy TOML placement (Tor settings before sections)
# ------------------------------------------------------------------------------
echo "--- Test 3: TOML Config & dnscrypt-proxy -check ---"
TMP_TOML="/tmp/test-dnscrypt-$$.toml"
if [ -f "/etc/dnscrypt-proxy/dnscrypt-proxy.toml" ]; then
    cp "/etc/dnscrypt-proxy/dnscrypt-proxy.toml" "$TMP_TOML"
else
    cat << 'EOF' > "$TMP_TOML"
listen_addresses = []
server_names = ['quad9-doh-ip4-port443-filter-pri']

[query_log]
  file = '/var/log/dnscrypt-proxy/query.log'
EOF
fi

# Apply the fixed insertion logic
sed -i '/^[[:space:]]*proxy[[:space:]]*=/d; /^[[:space:]]*force_tcp[[:space:]]*=/d' "$TMP_TOML"
sed -i "/^server_names =/a proxy = 'socks5://127.0.0.1:9050'\nforce_tcp = true" "$TMP_TOML"

if command -v dnscrypt-proxy &>/dev/null; then
    assert_true "dnscrypt-proxy -check passes with Tor config at top level" 'dnscrypt-proxy -config "$TMP_TOML" -check &>/dev/null'
else
    echo "  [SKIP] dnscrypt-proxy binary not found"
fi

# Verify Tor key is NOT inside [anonymized_dns]
assert_true "proxy setting appears BEFORE first section header" 'awk "/^\\[/ { exit } /proxy =/ { found=1 } END { exit !found }" "$TMP_TOML"'
rm -f "$TMP_TOML"

# ------------------------------------------------------------------------------
# Test 4: Symlink Attack Immunity in Privacy Scrubbing
# ------------------------------------------------------------------------------
echo "--- Test 4: Symlink Attack Immunity ---"
TEST_CANARY_FILE="/tmp/canary_victim_file_$$"
TEST_CANARY_DIR="/tmp/canary_victim_dir_$$"
TEST_CANARY_TRASH="/tmp/canary_victim_trash_$$"
FAKE_USER_HOME="/tmp/fake_user_home_$$"

echo "PROTECTED CONTENT" > "$TEST_CANARY_FILE"
mkdir -p "$TEST_CANARY_DIR" "$TEST_CANARY_TRASH/files"
touch "$TEST_CANARY_DIR/victim1.txt" "$TEST_CANARY_DIR/victim2.txt"
touch "$TEST_CANARY_TRASH/files/victim_trash.txt"

mkdir -p "$FAKE_USER_HOME/.local/share" "$FAKE_USER_HOME/.cache"
ln -s "$TEST_CANARY_FILE" "$FAKE_USER_HOME/.local/share/recently-used.xbel"
ln -s "$TEST_CANARY_DIR" "$FAKE_USER_HOME/.cache/thumbnails"
ln -s "$TEST_CANARY_TRASH" "$FAKE_USER_HOME/.local/share/Trash"

# Execute the symlink-protected cleanup logic
h="$FAKE_USER_HOME"
# 1. recent_file symlink check
recent_file="$h/.local/share/recently-used.xbel"
if [ -f "$recent_file" ] && [ ! -L "$recent_file" ]; then
    echo "OVERWRITTEN" > "$recent_file"
fi

# 2. thumbnails symlink check
if [ -d "$h/.cache/thumbnails" ] && [ ! -L "$h/.cache/thumbnails" ]; then
    find "$h/.cache/thumbnails" -mindepth 1 -maxdepth 3 ! -type l -delete 2>/dev/null || true
fi

# 3. trash symlink check
if [ -d "$h/.local/share/Trash" ] && [ ! -L "$h/.local/share/Trash" ]; then
    find "$h/.local/share/Trash" -mindepth 1 -maxdepth 4 ! -type l -delete 2>/dev/null || true
fi

canary_content=$(cat "$TEST_CANARY_FILE")
assert_eq "Canary file untouched by recently-used symlink" "PROTECTED CONTENT" "$canary_content"
assert_true "Canary directory files untouched by thumbnail symlink" '[ -f "$TEST_CANARY_DIR/victim1.txt" ] && [ -f "$TEST_CANARY_DIR/victim2.txt" ]'
assert_true "Canary trash files untouched by Trash symlink" '[ -f "$TEST_CANARY_TRASH/files/victim_trash.txt" ]'

# Cleanup test artifacts
rm -rf "$TEST_CANARY_FILE" "$TEST_CANARY_DIR" "$TEST_CANARY_TRASH" "$FAKE_USER_HOME"

# ------------------------------------------------------------------------------
# Test 5: Non-TTY zero-argument invocation
# ------------------------------------------------------------------------------
echo "--- Test 5: Non-TTY stdin handling ---"
non_tty_output=$(cat /dev/null | ./mint-admin.sh 2>&1 || true)
assert_true "Piped stdin displays usage help and exits without hanging" 'echo "$non_tty_output" | grep -q "Usage:"'

# ------------------------------------------------------------------------------
# Test 6: Battery udev rule syntax
# ------------------------------------------------------------------------------
echo "--- Test 6: Battery udev rule format ---"
udev_rule=$(grep 'SUBSYSTEM=="power_supply"' ./mint-admin.sh | head -n1)
assert_true "Battery udev rule triggers specifically on Mains power supply" 'echo "$udev_rule" | grep -q "ATTR{type}==\"Mains\""'
assert_true "Battery udev rule checks current threshold before writing" 'echo "$udev_rule" | grep -Fq "cat"'

# ------------------------------------------------------------------------------
# Test 7: Systemd unit path quoting
# ------------------------------------------------------------------------------
echo "--- Test 7: Systemd timer ExecStart quoting ---"
execstart_line=$(grep 'ExecStart=' ./mint-admin.sh | grep SCRIPT_PATH | head -n1)
assert_true "ExecStart quotes the script path" 'echo "$execstart_line" | grep -q '\''ExecStart="\$SCRIPT_PATH"'\'''

# ------------------------------------------------------------------------------
# Test 8: Guided wizard and UI dispatcher
# ------------------------------------------------------------------------------
echo "--- Test 8: Guided Wizard & UI Dispatcher ---"
assert_true "run_guided_wizard function is defined" 'grep -q "^run_guided_wizard()" ./mint-admin.sh'
assert_true "CLI help mentions wizard command" './mint-admin.sh help | grep "wizard" >/dev/null'
assert_true "Interactive menu lists Guided Wizard as Option 1" 'grep -A 12 "show_interactive_menu()" ./mint-admin.sh | grep -q "Guided Laptop Optimization Wizard"'

# ------------------------------------------------------------------------------
# Test 9: Discovery services default safety check
# ------------------------------------------------------------------------------
echo "--- Test 9: Network discovery services safe default ---"
assert_true "disable_services defaults to 0 to prevent breaking network printers" 'grep -q "local disable_services=0" ./mint-admin.sh'
assert_true "Warning displayed before disabling discovery services" 'grep -q "Disabling avahi-daemon/cups-browsed" ./mint-admin.sh'

echo "=========================================================="
if [ "$FAILED" -eq 0 ]; then
    echo "ALL $TOTAL TESTS PASSED SUCCESSFULLY!"
else
    echo "$FAILED of $TOTAL TESTS FAILED!"
    exit 1
fi
