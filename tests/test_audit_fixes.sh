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
assert_true "Battery udev rule monitors Mains power supply events" 'grep -q "ATTR{type}==\"Mains\"" ./mint-admin.sh'
assert_true "Battery udev rule manages charge_control_end_threshold" 'grep -q "ATTR{charge_control_end_threshold}" ./mint-admin.sh'
assert_true "Battery service checks current threshold before writing" 'grep "charge_control_end_threshold" ./mint-admin.sh | grep -Fq "cat"'

# ------------------------------------------------------------------------------
# Test 7: Systemd unit path quoting & privilege escalation protection
# ------------------------------------------------------------------------------
echo "--- Test 7: Systemd timer ExecStart quoting & canonical binary path ---"
execstart_line=$(grep 'ExecStart=' ./mint-admin.sh | grep 'optimize' | head -n1)
assert_true "ExecStart quotes the executable path" 'echo "$execstart_line" | grep -qE '\''ExecStart="(\$exec_target|\$SCRIPT_PATH|\$CANONICAL_BIN)"'\'''
assert_true "Systemd timer installs root-owned canonical binary for /home scripts" 'grep -q "install -m 755 -o root -g root \"\$SCRIPT_PATH\" \"\$CANONICAL_BIN\"" ./mint-admin.sh'

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

# ------------------------------------------------------------------------------
# Test 10: Profile Presets system
# ------------------------------------------------------------------------------
echo "--- Test 10: Profile Presets Architecture ---"
assert_true "apply_preset function defined" 'grep -q "^apply_preset()" ./mint-admin.sh'
assert_true "show_preset_status function defined" 'grep -q "^show_preset_status()" ./mint-admin.sh'
assert_true "CLI help mentions preset command" './mint-admin.sh help | grep "preset" >/dev/null'
assert_true "Preset status reports valid active profile" './mint-admin.sh preset status | grep -q "Active Profile Preset"'

# ------------------------------------------------------------------------------
# Test 11: Real-time System Status Indicators
# ------------------------------------------------------------------------------
echo "--- Test 11: Real-time System Status Indicators ---"
assert_true "status_get_preset is defined" 'grep -q "^status_get_preset()" ./mint-admin.sh'
assert_true "status_get_battery is defined" 'grep -q "^status_get_battery()" ./mint-admin.sh'
assert_true "status_get_zram is defined" 'grep -q "^status_get_zram()" ./mint-admin.sh'
assert_true "status_get_bbr is defined" 'grep -q "^status_get_bbr()" ./mint-admin.sh'
assert_true "status_get_dns is defined" 'grep -q "^status_get_dns()" ./mint-admin.sh'
assert_true "status_get_mac is defined" 'grep -q "^status_get_mac()" ./mint-admin.sh'

# ------------------------------------------------------------------------------
# Test 12: clean_user_cache symlink protection
# ------------------------------------------------------------------------------
echo "--- Test 12: Stale thumbnail cache symlink protection ---"
assert_true "clean_user_cache checks for symlinks on user homes" 'grep -A 8 "^clean_user_cache()" ./mint-admin.sh | grep -q "\[ -L \"\$h\" \] && continue"'
assert_true "clean_user_cache checks for thumbnail symlinks" 'grep -A 10 "^clean_user_cache()" ./mint-admin.sh | grep -q "\[ ! -L \"\$h/\.cache/thumbnails\" \]"'

# ------------------------------------------------------------------------------
# Test 13: Interactive TUI Dashboard & Whiptail fallback
# ------------------------------------------------------------------------------
echo "--- Test 13: Interactive TUI Dashboard, Dialog Support & First-Run Summary ---"
assert_true "show_tui_dashboard function is defined" 'grep -q "^show_tui_dashboard()" ./mint-admin.sh'
assert_true "show_whiptail_tui function is defined" 'grep -q "^show_whiptail_tui()" ./mint-admin.sh'
assert_true "show_system_summary function is defined" 'grep -q "^show_system_summary()" ./mint-admin.sh'
assert_true "Advisory prompt function is defined" 'grep -q "^show_maintenance_advisory()" ./mint-admin.sh'
assert_true "summary CLI command produces full status report" './mint-admin.sh summary | grep "Comprehensive System Status Summary" >/dev/null'
assert_true "First run triggers show_system_summary" 'grep -A 8 "if \[ \"\$FIRST_PROMPT_DONE\" -eq 0 \]; then" ./mint-admin.sh | grep -q "show_system_summary"'

# ------------------------------------------------------------------------------
# Test 14: IPv6 Protocol Control & Toggle
# ------------------------------------------------------------------------------
echo "--- Test 14: IPv6 Protocol Control & Toggle ---"
assert_true "toggle_ipv6 function is defined" 'grep -q "^toggle_ipv6()" ./mint-admin.sh'
assert_true "disable_ipv6 function is defined" 'grep -q "^disable_ipv6()" ./mint-admin.sh'
assert_true "enable_ipv6 function is defined" 'grep -q "^enable_ipv6()" ./mint-admin.sh'
assert_true "CLI help documents ipv6 toggle" './mint-admin.sh help | grep "toggle" >/dev/null'

# ------------------------------------------------------------------------------
# Test 15: Subsystem Toggles, NM Wait-Online Control & Curses/Ink TUI
# ------------------------------------------------------------------------------
echo "--- Test 15: Subsystem Toggles, NM Wait-Online & Curses/Ink TUI ---"
assert_true "toggle_nm_wait_online function is defined" 'grep -q "^toggle_nm_wait_online()" ./mint-admin.sh'
assert_true "enable_nm_wait_online function is defined" 'grep -q "^enable_nm_wait_online()" ./mint-admin.sh'
assert_true "disable_nm_wait_online function is defined" 'grep -q "^disable_nm_wait_online()" ./mint-admin.sh'
assert_true "status_get_wait_online function is defined" 'grep -q "^status_get_wait_online()" ./mint-admin.sh'
assert_true "toggle_bbr function is defined" 'grep -q "^toggle_bbr()" ./mint-admin.sh'
assert_true "toggle_swappiness function is defined" 'grep -q "^toggle_swappiness()" ./mint-admin.sh'
assert_true "toggle_zram function is defined" 'grep -q "^toggle_zram()" ./mint-admin.sh'
assert_true "toggle_dhcp_privacy function is defined" 'grep -q "^toggle_dhcp_privacy()" ./mint-admin.sh'
assert_true "toggle_kernel_hardening function is defined" 'grep -q "^toggle_kernel_hardening()" ./mint-admin.sh'
assert_true "toggle_avahi function is defined" 'grep -q "^toggle_avahi()" ./mint-admin.sh'
assert_true "toggle_cups_browsed function is defined" 'grep -q "^toggle_cups_browsed()" ./mint-admin.sh'
assert_true "toggle_modemmanager function is defined" 'grep -q "^toggle_modemmanager()" ./mint-admin.sh'
assert_true "toggle_broadcast_daemons function is defined" 'grep -q "^toggle_broadcast_daemons()" ./mint-admin.sh'
assert_true "interactive_tuning_menu function is defined" 'grep -q "^interactive_tuning_menu()" ./mint-admin.sh'
assert_true "whiptail_tuning_menu function is defined" 'grep -q "^whiptail_tuning_menu()" ./mint-admin.sh'
assert_true "CLI help documents wait-online command" './mint-admin.sh help | grep "wait-online" >/dev/null'
assert_true "CLI wait-online status outputs valid state" './mint-admin.sh wait-online status | grep "NM Wait-Online Delay:" >/dev/null'
assert_true "CLI tune wait-online status outputs valid state" './mint-admin.sh tune wait-online status | grep "NM Wait-Online Delay:" >/dev/null'
assert_true "CLI summary reports NM Boot Speed Delay" './mint-admin.sh summary | grep "NM Boot Speed Delay" >/dev/null'

# ------------------------------------------------------------------------------
# Test 16: DHCP Hostname Privacy via nmcli Profiles
# ------------------------------------------------------------------------------
echo "--- Test 16: DHCP Hostname Privacy via nmcli Profiles ---"
assert_true "enable_dhcp_privacy modifies connection profiles via nmcli" 'grep -A 15 "^enable_dhcp_privacy()" ./mint-admin.sh | grep -q "nmcli con modify"'
assert_true "disable_dhcp_privacy restores connection profiles via nmcli" 'grep -A 15 "^disable_dhcp_privacy()" ./mint-admin.sh | grep -q "nmcli con modify"'
assert_true "status_get_dhcp inspects active connection profile via nmcli" 'grep -A 20 "^status_get_dhcp()" ./mint-admin.sh | grep -q "nmcli -g ipv4.dhcp-send-hostname"'

# ------------------------------------------------------------------------------
# Test 17: Intermediate Symlink Traversal Immunity (is_safe_user_path)
# ------------------------------------------------------------------------------
echo "--- Test 17: Intermediate Symlink Traversal Immunity ---"
assert_true "is_safe_user_path function is defined" 'grep -q "^is_safe_user_path()" ./mint-admin.sh'
assert_true "clean_privacy checks is_safe_user_path on user home and recent files" 'grep -A 50 "^clean_privacy()" ./mint-admin.sh | grep -q "is_safe_user_path \"\$h\""'
assert_true "clean_privacy checks is_safe_user_path on browser caches" 'grep -A 100 "^clean_privacy()" ./mint-admin.sh | grep -q "is_safe_user_path \"\$h\" \"\$cdir\""'
assert_true "clean_privacy checks is_safe_user_path on trash dirs" 'grep -A 140 "^clean_privacy()" ./mint-admin.sh | grep -q "is_safe_user_path \"\$h\" \"\$tdir\""'
assert_true "clean_user_cache checks is_safe_user_path on thumbnail dirs" 'grep -A 20 "^clean_user_cache()" ./mint-admin.sh | grep -q "is_safe_user_path \"\$h\" \"\$h/\.cache/thumbnails\""'

# Live functional test for is_safe_user_path
TEST_SAFE_SCRIPT=$(mktemp)
cat << 'EOF' > "$TEST_SAFE_SCRIPT"
sed -n '/^is_safe_user_path()/,/^}/p' ./mint-admin.sh > "${TEST_SAFE_SCRIPT}.fn"
source "${TEST_SAFE_SCRIPT}.fn"
THOME=$(mktemp -d /home/minty/test_home_XXXXXX)
TOUTSIDE=$(mktemp -d /tmp/outside_XXXXXX)
ln -s "$TOUTSIDE" "$THOME/.local"
mkdir -p "$TOUTSIDE/share/Trash/files"
if is_safe_user_path "$THOME" "$THOME/.local/share/Trash/files"; then
    res=1
else
    res=0
fi
rm -rf "$THOME" "$TOUTSIDE" "${TEST_SAFE_SCRIPT}.fn"
exit $res
EOF
assert_true "is_safe_user_path blocks intermediate symlink attacks" 'bash "$TEST_SAFE_SCRIPT"'
rm -f "$TEST_SAFE_SCRIPT"

# ------------------------------------------------------------------------------
# Test 18: DNS Anonymized Relays v3 & Fail-Stop Verification
# ------------------------------------------------------------------------------
echo "--- Test 18: DNS Anonymized Relays v3 & Error Handling ---"
assert_true "get_active_relays function is defined" 'grep -q "^get_active_relays()" ./mint-admin.sh'
assert_true "apply_dnscrypt_config uses resolvers-list/v3/relays.md" 'grep -q "resolvers-list/v3/relays.md" ./mint-admin.sh'
assert_true "apply_dnscrypt_config takes pre-modification .bak snapshot" 'grep -A 10 "^apply_dnscrypt_config()" ./mint-admin.sh | grep -q "DNS_CONFIG.*\.bak"'
assert_true "activate_dns_config helper enforces fail-stop" 'grep -q "^activate_dns_config()" ./mint-admin.sh'

# ------------------------------------------------------------------------------
# Test 19: Systemd Timer Security & Space Quoting
# ------------------------------------------------------------------------------
echo "--- Test 19: Systemd Timer Security & Space Quoting ---"
assert_true "Documentation= is quoted for path with spaces" 'grep -q "Documentation=\"file://\$exec_target\"" ./mint-admin.sh'
assert_true "install_weekly_timer fails if canonical installation fails" 'grep -A 15 "^install_weekly_timer()" ./mint-admin.sh | grep -q "Failed to securely install root-owned binary"'
assert_true "uninstall_weekly_timer removes canonical binary" 'grep -A 12 "^uninstall_weekly_timer()" ./mint-admin.sh | grep -q "rm -f \"\$CANONICAL_BIN\""'

# ------------------------------------------------------------------------------
# Test 20: TUI Subshell Isolation & Non-TTY Handling
# ------------------------------------------------------------------------------
echo "--- Test 20: TUI Subshell Isolation & Non-TTY Handling ---"
assert_true "run_menu_action uses isolated subshell" 'grep -A 8 "^run_menu_action()" ./mint-admin.sh | grep -q "( \"\$@\" ) || rc="'
assert_true "run_whiptail_action uses isolated subshell" 'grep -A 8 "^run_whiptail_action()" ./mint-admin.sh | grep -q "( \"\$@\" ) || rc="'
assert_true "show_tui_dashboard checks non-TTY stdin" 'grep -A 6 "^show_tui_dashboard()" ./mint-admin.sh | grep -q "\[ ! -t 0 \]"'
assert_true "show_whiptail_tui includes ZRAM status in backtitle" 'grep -A 30 "^show_whiptail_tui()" ./mint-admin.sh | grep -q "ZRAM: \$z_info"'

# ------------------------------------------------------------------------------
# Test 21: Tuning Baseline Restoration & TCP FastOpen
# ------------------------------------------------------------------------------
echo "--- Test 21: Tuning Baseline Restoration & TCP FastOpen ---"
assert_true "save_tuning_baseline records daemon active states" 'grep -A 30 "^save_tuning_baseline()" ./mint-admin.sh | grep -q "BASE_AVAHI_ACTIVE"'
assert_true "disable_bbr restores net.ipv4.tcp_fastopen" 'grep -A 15 "^disable_bbr()" ./mint-admin.sh | grep -q "net\.ipv4\.tcp_fastopen"'
assert_true "revert_system_tuning restores daemons based on baseline state" 'grep -A 35 "^revert_system_tuning()" ./mint-admin.sh | grep -q "b_avahi"'
assert_true "show_tuning_status strictly checks swappiness 100" 'grep -A 20 "^show_tuning_status()" ./mint-admin.sh | grep -q "\[ \"\$swappiness\" -eq 100 \]"'

echo "=========================================================="
if [ "$FAILED" -eq 0 ]; then
    echo "ALL $TOTAL TESTS PASSED SUCCESSFULLY!"
else
    echo "$FAILED of $TOTAL TESTS FAILED!"
    exit 1
fi
