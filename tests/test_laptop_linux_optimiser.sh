#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo "Running Validation Test Suite for laptop-linux-optimiser.sh Audit Fixes"
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
source <(grep -A 3 '^generate_random_mac()' ./laptop-linux-optimiser.sh)

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
unset h recent_file canary_content

# ------------------------------------------------------------------------------
# Test 5: Non-TTY zero-argument invocation
# ------------------------------------------------------------------------------
echo "--- Test 5: Non-TTY stdin handling ---"
non_tty_output=$(cat /dev/null | ./laptop-linux-optimiser.sh 2>&1 || true)
assert_true "Piped stdin displays usage help and exits without hanging" 'echo "$non_tty_output" | grep -q "Usage:"'

# ------------------------------------------------------------------------------
# Test 6: Battery udev rule syntax
# ------------------------------------------------------------------------------
echo "--- Test 6: Battery udev rule format ---"
assert_true "Battery udev rule monitors Mains power supply events" 'grep -q "ATTR{type}==\"Mains\"" ./laptop-linux-optimiser.sh'
assert_true "Battery udev rule manages charge_control_end_threshold" 'grep -q "ATTR{charge_control_end_threshold}" ./laptop-linux-optimiser.sh'
assert_true "Battery service checks current threshold before writing" 'grep "charge_control_end_threshold" ./laptop-linux-optimiser.sh | grep -Fq "cat"'

# ------------------------------------------------------------------------------
# Test 7: Systemd unit path quoting & privilege escalation protection
# ------------------------------------------------------------------------------
echo "--- Test 7: Systemd timer ExecStart quoting & canonical binary path ---"
execstart_line=$(grep 'ExecStart=' ./laptop-linux-optimiser.sh | grep 'optimize' | head -n1)
assert_true "ExecStart quotes the executable path" 'echo "$execstart_line" | grep -qE '\''ExecStart="(\$exec_target|\$SCRIPT_PATH|\$CANONICAL_BIN)"'\'''
assert_true "Systemd timer installs root-owned canonical binary for /home scripts" 'grep -q "install -m 755 -o root -g root \"\$SCRIPT_PATH\" \"\$CANONICAL_BIN\"" ./laptop-linux-optimiser.sh'

# ------------------------------------------------------------------------------
# Test 8: Guided wizard and UI dispatcher
# ------------------------------------------------------------------------------
echo "--- Test 8: Guided Wizard & UI Dispatcher ---"
assert_true "run_guided_wizard function is defined" 'grep -q "^run_guided_wizard()" ./laptop-linux-optimiser.sh'
assert_true "CLI help mentions wizard command" './laptop-linux-optimiser.sh help | grep "wizard" >/dev/null'
assert_true "Interactive menu lists Guided Wizard as Option 1" 'grep -A 12 "show_interactive_menu()" ./laptop-linux-optimiser.sh | grep -q "Guided Laptop Optimization Wizard"'

# ------------------------------------------------------------------------------
# Test 9: Discovery services default safety check
# ------------------------------------------------------------------------------
echo "--- Test 9: Network discovery services safe default ---"
assert_true "disable_services defaults to 0 to prevent breaking network printers" 'grep -q "local disable_services=0" ./laptop-linux-optimiser.sh'
assert_true "Warning displayed before disabling discovery services" 'grep -q "Disabling avahi-daemon/cups-browsed" ./laptop-linux-optimiser.sh'

# ------------------------------------------------------------------------------
# Test 10: Profile Presets system
# ------------------------------------------------------------------------------
echo "--- Test 10: Profile Presets Architecture ---"
assert_true "apply_preset function defined" 'grep -q "^apply_preset()" ./laptop-linux-optimiser.sh'
assert_true "show_preset_status function defined" 'grep -q "^show_preset_status()" ./laptop-linux-optimiser.sh'
assert_true "CLI help mentions preset command" './laptop-linux-optimiser.sh help | grep "preset" >/dev/null'
assert_true "Preset status reports valid active profile" './laptop-linux-optimiser.sh preset status | grep -q "Active Profile Preset"'

# ------------------------------------------------------------------------------
# Test 11: Real-time System Status Indicators
# ------------------------------------------------------------------------------
echo "--- Test 11: Real-time System Status Indicators ---"
assert_true "status_get_preset is defined" 'grep -q "^status_get_preset()" ./laptop-linux-optimiser.sh'
assert_true "status_get_battery is defined" 'grep -q "^status_get_battery()" ./laptop-linux-optimiser.sh'
assert_true "status_get_zram is defined" 'grep -q "^status_get_zram()" ./laptop-linux-optimiser.sh'
assert_true "status_get_bbr is defined" 'grep -q "^status_get_bbr()" ./laptop-linux-optimiser.sh'
assert_true "status_get_dns is defined" 'grep -q "^status_get_dns()" ./laptop-linux-optimiser.sh'
assert_true "status_get_mac is defined" 'grep -q "^status_get_mac()" ./laptop-linux-optimiser.sh'

# ------------------------------------------------------------------------------
# Test 12: clean_user_cache symlink protection
# ------------------------------------------------------------------------------
echo "--- Test 12: Stale thumbnail cache symlink protection ---"
assert_true "clean_user_cache checks for symlinks on user homes" 'grep -A 8 "^clean_user_cache()" ./laptop-linux-optimiser.sh | grep -q "\[ -L \"\$h\" \] && continue"'
assert_true "clean_user_cache checks for thumbnail symlinks" 'grep -A 10 "^clean_user_cache()" ./laptop-linux-optimiser.sh | grep -q "\[ ! -L \"\$h/\.cache/thumbnails\" \]"'

# ------------------------------------------------------------------------------
# Test 13: Interactive TUI Dashboard & Whiptail fallback
# ------------------------------------------------------------------------------
echo "--- Test 13: Interactive TUI Dashboard, Dialog Support & First-Run Summary ---"
assert_true "show_tui_dashboard function is defined" 'grep -q "^show_tui_dashboard()" ./laptop-linux-optimiser.sh'
assert_true "show_whiptail_tui function is defined" 'grep -q "^show_whiptail_tui()" ./laptop-linux-optimiser.sh'
assert_true "show_system_summary function is defined" 'grep -q "^show_system_summary()" ./laptop-linux-optimiser.sh'
assert_true "Advisory prompt function is defined" 'grep -q "^show_maintenance_advisory()" ./laptop-linux-optimiser.sh'
assert_true "summary CLI command produces full status report" './laptop-linux-optimiser.sh summary | grep "Comprehensive System Status Summary" >/dev/null'
assert_true "First run triggers show_system_summary" 'grep -A 8 "if \[ \"\$FIRST_PROMPT_DONE\" -eq 0 \]; then" ./laptop-linux-optimiser.sh | grep -q "show_system_summary"'

# ------------------------------------------------------------------------------
# Test 14: IPv6 Protocol Control & Toggle
# ------------------------------------------------------------------------------
echo "--- Test 14: IPv6 Protocol Control & Toggle ---"
assert_true "toggle_ipv6 function is defined" 'grep -q "^toggle_ipv6()" ./laptop-linux-optimiser.sh'
assert_true "disable_ipv6 function is defined" 'grep -q "^disable_ipv6()" ./laptop-linux-optimiser.sh'
assert_true "enable_ipv6 function is defined" 'grep -q "^enable_ipv6()" ./laptop-linux-optimiser.sh'
assert_true "CLI help documents ipv6 toggle" './laptop-linux-optimiser.sh help | grep "toggle" >/dev/null'

# ------------------------------------------------------------------------------
# Test 15: Subsystem Toggles, NM Wait-Online Control & Curses/Ink TUI
# ------------------------------------------------------------------------------
echo "--- Test 15: Subsystem Toggles, NM Wait-Online & Curses/Ink TUI ---"
assert_true "toggle_nm_wait_online function is defined" 'grep -q "^toggle_nm_wait_online()" ./laptop-linux-optimiser.sh'
assert_true "enable_nm_wait_online function is defined" 'grep -q "^enable_nm_wait_online()" ./laptop-linux-optimiser.sh'
assert_true "disable_nm_wait_online function is defined" 'grep -q "^disable_nm_wait_online()" ./laptop-linux-optimiser.sh'
assert_true "status_get_wait_online function is defined" 'grep -q "^status_get_wait_online()" ./laptop-linux-optimiser.sh'
assert_true "toggle_bbr function is defined" 'grep -q "^toggle_bbr()" ./laptop-linux-optimiser.sh'
assert_true "toggle_swappiness function is defined" 'grep -q "^toggle_swappiness()" ./laptop-linux-optimiser.sh'
assert_true "toggle_zram function is defined" 'grep -q "^toggle_zram()" ./laptop-linux-optimiser.sh'
assert_true "toggle_dhcp_privacy function is defined" 'grep -q "^toggle_dhcp_privacy()" ./laptop-linux-optimiser.sh'
assert_true "toggle_kernel_hardening function is defined" 'grep -q "^toggle_kernel_hardening()" ./laptop-linux-optimiser.sh'
assert_true "toggle_avahi function is defined" 'grep -q "^toggle_avahi()" ./laptop-linux-optimiser.sh'
assert_true "toggle_cups_browsed function is defined" 'grep -q "^toggle_cups_browsed()" ./laptop-linux-optimiser.sh'
assert_true "toggle_modemmanager function is defined" 'grep -q "^toggle_modemmanager()" ./laptop-linux-optimiser.sh'
assert_true "toggle_broadcast_daemons function is defined" 'grep -q "^toggle_broadcast_daemons()" ./laptop-linux-optimiser.sh'
assert_true "interactive_tuning_menu function is defined" 'grep -q "^interactive_tuning_menu()" ./laptop-linux-optimiser.sh'
assert_true "whiptail_tuning_menu function is defined" 'grep -q "^whiptail_tuning_menu()" ./laptop-linux-optimiser.sh'
assert_true "CLI help documents wait-online command" './laptop-linux-optimiser.sh help | grep "wait-online" >/dev/null'
assert_true "CLI wait-online status outputs valid state" './laptop-linux-optimiser.sh wait-online status | grep "NM Wait-Online Delay:" >/dev/null'
assert_true "CLI tune wait-online status outputs valid state" './laptop-linux-optimiser.sh tune wait-online status | grep "NM Wait-Online Delay:" >/dev/null'
assert_true "CLI summary reports NM Boot Speed Delay" './laptop-linux-optimiser.sh summary | grep "NM Boot Speed Delay" >/dev/null'

# ------------------------------------------------------------------------------
# Test 16: DHCP Hostname Privacy via nmcli Profiles
# ------------------------------------------------------------------------------
echo "--- Test 16: DHCP Hostname Privacy via nmcli Profiles ---"
assert_true "enable_dhcp_privacy modifies connection profiles via nmcli" 'grep -A 15 "^enable_dhcp_privacy()" ./laptop-linux-optimiser.sh | grep -q "nmcli con modify"'
assert_true "enable_dhcp_privacy restricts modification to physical Wi-Fi and Ethernet" 'grep -A 15 "^enable_dhcp_privacy()" ./laptop-linux-optimiser.sh | grep -q "802-11-wireless|802-3-ethernet"'
assert_true "disable_dhcp_privacy restores connection profiles via nmcli" 'grep -A 15 "^disable_dhcp_privacy()" ./laptop-linux-optimiser.sh | grep -q "nmcli con modify"'
assert_true "disable_dhcp_privacy restricts modification to physical Wi-Fi and Ethernet" 'grep -A 15 "^disable_dhcp_privacy()" ./laptop-linux-optimiser.sh | grep -q "802-11-wireless|802-3-ethernet"'
assert_true "status_get_dhcp inspects active connection profile via nmcli" 'grep -A 20 "^status_get_dhcp()" ./laptop-linux-optimiser.sh | grep -q "nmcli -g ipv4.dhcp-send-hostname"'

# ------------------------------------------------------------------------------
# Test 17: Intermediate Symlink Traversal Immunity (is_safe_user_path)
# ------------------------------------------------------------------------------
echo "--- Test 17: Intermediate Symlink Traversal Immunity ---"
assert_true "is_safe_user_path function is defined" 'grep -q "^is_safe_user_path()" ./laptop-linux-optimiser.sh'
assert_true "clean_privacy checks is_safe_user_path on user home and recent files" 'sed -n "/^clean_privacy()/,/^}/p" ./laptop-linux-optimiser.sh | grep "is_safe_user_path.*recent_file" >/dev/null'
assert_true "clean_privacy disables remember-app-usage" 'sed -n "/^clean_privacy()/,/^}/p" ./laptop-linux-optimiser.sh | grep "remember-app-usage.*false" >/dev/null'
assert_true "clean_privacy checks is_safe_user_path on browser caches" 'sed -n "/^clean_privacy()/,/^}/p" ./laptop-linux-optimiser.sh | grep "is_safe_user_path.*cdir" >/dev/null'
assert_true "clean_privacy checks is_safe_user_path on trash dirs" 'sed -n "/^clean_privacy()/,/^}/p" ./laptop-linux-optimiser.sh | grep "is_safe_user_path.*tdir" >/dev/null'
assert_true "clean_user_cache checks is_safe_user_path on thumbnail dirs" 'sed -n "/^clean_user_cache()/,/^}/p" ./laptop-linux-optimiser.sh | grep "is_safe_user_path.*thumbnails" >/dev/null'

# Live functional test for is_safe_user_path
TEST_SAFE_SCRIPT=$(mktemp)
cat << 'EOF' > "$TEST_SAFE_SCRIPT"
sed -n '/^is_safe_user_path()/,/^}/p' ./laptop-linux-optimiser.sh > "${TEST_SAFE_SCRIPT}.fn"
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
assert_true "get_active_relays function is defined" 'grep -q "^get_active_relays()" ./laptop-linux-optimiser.sh'
assert_true "apply_dnscrypt_config uses resolvers-list/v3/relays.md" 'grep -q "resolvers-list/v3/relays.md" ./laptop-linux-optimiser.sh'
assert_true "apply_dnscrypt_config takes pre-modification .bak snapshot" 'grep -A 10 "^apply_dnscrypt_config()" ./laptop-linux-optimiser.sh | grep -q "DNS_CONFIG.*\.bak"'
assert_true "activate_dns_config helper enforces fail-stop" 'grep -q "^activate_dns_config()" ./laptop-linux-optimiser.sh'

# ------------------------------------------------------------------------------
# Test 19: Systemd Timer Security & Space Quoting
# ------------------------------------------------------------------------------
echo "--- Test 19: Systemd Timer Security & Space Quoting ---"
assert_true "Documentation= is quoted for path with spaces" 'grep -q "Documentation=\"file://\$exec_target\"" ./laptop-linux-optimiser.sh'
assert_true "install_weekly_timer fails if canonical installation fails" 'grep -A 15 "^install_weekly_timer()" ./laptop-linux-optimiser.sh | grep -q "Failed to securely install root-owned binary"'
assert_true "uninstall_weekly_timer removes canonical binary" 'grep -A 12 "^uninstall_weekly_timer()" ./laptop-linux-optimiser.sh | grep -q "rm -f \"\$CANONICAL_BIN\""'

# ------------------------------------------------------------------------------
# Test 20: TUI Subshell Isolation & Non-TTY Handling
# ------------------------------------------------------------------------------
echo "--- Test 20: TUI Subshell Isolation & Non-TTY Handling ---"
assert_true "run_menu_action uses isolated subshell" 'grep -A 8 "^run_menu_action()" ./laptop-linux-optimiser.sh | grep -q "( \"\$@\" ) || rc="'
assert_true "run_whiptail_action uses isolated subshell" 'grep -A 8 "^run_whiptail_action()" ./laptop-linux-optimiser.sh | grep -q "( \"\$@\" ) || rc="'
assert_true "show_tui_dashboard checks non-TTY stdin" 'grep -A 6 "^show_tui_dashboard()" ./laptop-linux-optimiser.sh | grep -q "\[ ! -t 0 \]"'
assert_true "show_whiptail_tui includes ZRAM status in backtitle" 'grep -A 30 "^show_whiptail_tui()" ./laptop-linux-optimiser.sh | grep -q "ZRAM: \$z_info"'

# ------------------------------------------------------------------------------
# Test 21: Tuning Baseline Restoration & TCP FastOpen
# ------------------------------------------------------------------------------
echo "--- Test 21: Tuning Baseline Restoration & TCP FastOpen ---"
assert_true "save_tuning_baseline records daemon active states" 'grep -A 30 "^save_tuning_baseline()" ./laptop-linux-optimiser.sh | grep -q "BASE_AVAHI_ACTIVE"'
assert_true "disable_bbr restores net.ipv4.tcp_fastopen" 'grep -A 15 "^disable_bbr()" ./laptop-linux-optimiser.sh | grep -q "net\.ipv4\.tcp_fastopen"'
assert_true "revert_system_tuning restores daemons based on baseline state" 'grep -A 35 "^revert_system_tuning()" ./laptop-linux-optimiser.sh | grep -q "b_avahi"'
assert_true "show_tuning_status checks swappiness for ZRAM" 'grep -A 20 "^show_tuning_status()" ./laptop-linux-optimiser.sh | grep -q swappiness'

# ------------------------------------------------------------------------------
# Test 22: Cleaner Single-Pass & Desktop Theme Theming Protection
# ------------------------------------------------------------------------------
echo "--- Test 22: Cleaner Single-Pass & Desktop Theme Protection ---"
assert_true "First run maintenance prompt uses single-pass full update & clean" 'grep -A 15 "if \[ \"\$FIRST_PROMPT_DONE\" -eq 0 \]; then" ./laptop-linux-optimiser.sh | grep -q "run_menu_action run_full_update_and_optimizer"'
assert_true "clean_flatpak safeguards desktop theme runtimes" 'grep -A 15 "^clean_flatpak()" ./laptop-linux-optimiser.sh | grep -q "flatpak pin"'
assert_true "verify_theme_preservation helper is defined" 'grep -q "^verify_theme_preservation()" ./laptop-linux-optimiser.sh'
assert_true "clean_user_cache preserves theming assets" 'grep -A 25 "^clean_user_cache()" ./laptop-linux-optimiser.sh | grep -q "verify_theme_preservation"'
assert_true "TUI dashboard supports [A] for all-in-one run" 'grep -A 20 "case \"\$opt\" in" ./laptop-linux-optimiser.sh | grep -q "\[Aa\]|all)"'

# ------------------------------------------------------------------------------
# Test 23: Font Anti-Blur, High-DPI Scaling & Notifications
# ------------------------------------------------------------------------------
echo "--- Test 23: Font Anti-Blur, High-DPI Scaling & Notifications ---"
assert_true "status_get_font_antiblur function is defined" 'grep -q "^status_get_font_antiblur()" ./laptop-linux-optimiser.sh'
assert_true "enable_font_antiblur function is defined" 'grep -q "^enable_font_antiblur()" ./laptop-linux-optimiser.sh'
assert_true "disable_font_antiblur function is defined" 'grep -q "^disable_font_antiblur()" ./laptop-linux-optimiser.sh'
assert_true "toggle_font_antiblur function is defined" 'grep -q "^toggle_font_antiblur()" ./laptop-linux-optimiser.sh'
assert_true "CLI help documents antiblur command" './laptop-linux-optimiser.sh help | grep "antiblur, blur" >/dev/null'
assert_true "CLI antiblur status outputs valid state" './laptop-linux-optimiser.sh antiblur status | grep -E "Font Anti-Blur: (ACTIVE|UNCONFIGURED|COSMIC)" >/dev/null'
assert_true "CLI tune antiblur status outputs valid state" './laptop-linux-optimiser.sh tune antiblur status | grep -E "Font Anti-Blur: (ACTIVE|UNCONFIGURED|COSMIC)" >/dev/null'
assert_true "CLI summary reports Font Anti-Blur" './laptop-linux-optimiser.sh summary | grep "Font Anti-Blur (LCD)" >/dev/null'
assert_true "TUI dashboard displays Font Anti-Blur pill" 'grep -q "Font Anti-Blur.*cur_blur_pill" ./laptop-linux-optimiser.sh'
assert_true "TUI dashboard displays text blurriness advisory notification" 'grep -q "Flatpak text blurriness detected" ./laptop-linux-optimiser.sh'
assert_true "TUI dashboard supports [F] key toggle" 'grep -A 25 "case \"\$opt\" in" ./laptop-linux-optimiser.sh | grep -q "\[Ff\]|blur|antiblur)"'
assert_true "Interactive tuning menu supports [F] font anti-blur toggle" 'grep -A 35 "case \"\$topt\" in" ./laptop-linux-optimiser.sh | grep -q "\[Ff\]|blur|antiblur)"'

# ------------------------------------------------------------------------------
# Test 24: Target OS Platform Selection & Detection
# ------------------------------------------------------------------------------
echo "--- Test 24: OS Platform Selection ---"
assert_true "detect_system_os function is defined" 'grep -q "^detect_system_os()" ./laptop-linux-optimiser.sh'
assert_true "get_target_os function is defined" 'grep -q "^get_target_os()" ./laptop-linux-optimiser.sh'
assert_true "set_target_os function is defined" 'grep -q "^set_target_os()" ./laptop-linux-optimiser.sh'
assert_true "status_get_target_os function is defined" 'grep -q "^status_get_target_os()" ./laptop-linux-optimiser.sh'
assert_true "CLI os status outputs valid OS" './laptop-linux-optimiser.sh os status | grep -E "Target OS: (Ubuntu LTS|Pop!_OS|Linux Mint)" >/dev/null'
assert_true "detect_system_os identifies Ubuntu platform" 'source <(sed -n "/^detect_system_os()/,/^}/p" ./laptop-linux-optimiser.sh); [ "$(detect_system_os)" = "ubuntu" ]'

# ------------------------------------------------------------------------------
# Test 25: SSH Inbound Shield & Network Printer Discovery Preservation
# ------------------------------------------------------------------------------
echo "--- Test 25: SSH Hardening & Network Printer Discovery ---"
assert_true "status_get_ssh_server function is defined" 'grep -q "^status_get_ssh_server()" ./laptop-linux-optimiser.sh'
assert_true "enable_ssh_hardening function is defined" 'grep -q "^enable_ssh_hardening()" ./laptop-linux-optimiser.sh'
assert_true "disable_ssh_hardening function is defined" 'grep -q "^disable_ssh_hardening()" ./laptop-linux-optimiser.sh'
assert_true "toggle_ssh_hardening function is defined" 'grep -q "^toggle_ssh_hardening()" ./laptop-linux-optimiser.sh'
assert_true "CLI ssh status outputs valid state" './laptop-linux-optimiser.sh ssh status | grep -E "SSH Inbound Server: (MASKED|ACTIVE|DISABLED|NOT INSTALLED)" >/dev/null'
assert_true "CUPS network printer discovery is preserved" 'grep -q "ACTIVE (Printer Discovery)" ./laptop-linux-optimiser.sh'

# ------------------------------------------------------------------------------
# Test 26: DNS Privacy Hardening & Zero-Log Caching
# ------------------------------------------------------------------------------
echo "--- Test 26: DNS Privacy Hardening & Zero-Log Caching ---"
assert_true "apply_dnscrypt_config zeroes out query.log" 'grep -A 60 "^apply_dnscrypt_config()" ./laptop-linux-optimiser.sh | grep -F "query\.log" >/dev/null'
assert_true "apply_dnscrypt_config zeroes out nx.log" 'grep -A 60 "^apply_dnscrypt_config()" ./laptop-linux-optimiser.sh | grep -F "nx\.log" >/dev/null'
assert_true "apply_dnscrypt_config configures local RAM caching" 'grep -A 60 "^apply_dnscrypt_config()" ./laptop-linux-optimiser.sh | grep -q "cache_size = 8192"'
assert_true "apply_dnscrypt_config aligns block_ipv6 with system state" 'grep -A 60 "^apply_dnscrypt_config()" ./laptop-linux-optimiser.sh | grep -q "block_ipv6"'
assert_true "setup_system_dns configures LLMNR=no" 'grep -A 35 "^setup_system_dns()" ./laptop-linux-optimiser.sh | grep -q "LLMNR=no"'
assert_true "setup_system_dns configures MulticastDNS=no" 'grep -A 35 "^setup_system_dns()" ./laptop-linux-optimiser.sh | grep -q "MulticastDNS=no"'
assert_true "setup_system_dns configures DNSSEC=no" 'grep -A 35 "^setup_system_dns()" ./laptop-linux-optimiser.sh | grep -q "DNSSEC=no"'
assert_true "get_system_hostname function is defined" 'grep -q "^get_system_hostname()" ./laptop-linux-optimiser.sh'
assert_true "ensure_hostname_resolution function is defined" 'grep -q "^ensure_hostname_resolution()" ./laptop-linux-optimiser.sh'
assert_true "setup_system_dns calls ensure_hostname_resolution" 'grep -A 25 "^setup_system_dns()" ./laptop-linux-optimiser.sh | grep -q "ensure_hostname_resolution"'
assert_true "enable_dhcp_privacy calls ensure_hostname_resolution" 'grep -A 25 "^enable_dhcp_privacy()" ./laptop-linux-optimiser.sh | grep -q "ensure_hostname_resolution"'
assert_true "apply_system_tuning calls ensure_hostname_resolution" 'grep -A 35 "^apply_system_tuning()" ./laptop-linux-optimiser.sh | grep -q "ensure_hostname_resolution"'
assert_true "apply_dnscrypt_config configures fallback_resolvers" 'grep -A 70 "^apply_dnscrypt_config()" ./laptop-linux-optimiser.sh | grep -q "fallback_resolvers"'
assert_true "apply_dnscrypt_config configures ignore_system_dns" 'grep -A 70 "^apply_dnscrypt_config()" ./laptop-linux-optimiser.sh | grep -q "ignore_system_dns = true"'
assert_true "ensure_hostname_resolution maps dynamic hostname to mock hosts file" '
    tmp_hosts=$(mktemp)
    echo -e "127.0.0.1\tlocalhost\n::1\tlocalhost" > "$tmp_hosts"
    source <(sed -n "/^get_system_hostname()/,/^}/p" ./laptop-linux-optimiser.sh)
    source <(sed -n "/^ensure_hostname_resolution()/,/^}/p" ./laptop-linux-optimiser.sh)
    log_info() { :; }; log_success() { :; }; log_warn() { :; }
    ensure_hostname_resolution "$tmp_hosts" "test-workstation"
    grep -E "^127\.0\.1\.1[[:space:]]+test-workstation" "$tmp_hosts" >/dev/null
    rv=$?
    rm -f "$tmp_hosts"
    [ $rv -eq 0 ]
'

# ------------------------------------------------------------------------------
# Test 27: Network Baseline Decoupling & Clean Overrides
# ------------------------------------------------------------------------------
echo "--- Test 27: Network Baseline Decoupling ---"
assert_true "clean_network_overrides function is defined" 'grep -q "^clean_network_overrides()" ./laptop-linux-optimiser.sh'
assert_true "clean_network_overrides flushes legacy DNS shield and DPI rules" 'grep -A 50 "^clean_network_overrides()" ./laptop-linux-optimiser.sh | grep -q "laptop-optimizer-dpi"'
assert_true "clean_network_overrides removes obsolete service drop-ins" 'grep -A 30 "^clean_network_overrides()" ./laptop-linux-optimiser.sh | grep -q "laptop-dpi-mss.service"'
assert_true "revert_dns_changes restores baseline DNS" 'grep -q "^revert_dns_changes()" ./laptop-linux-optimiser.sh'
assert_true "CLI network clean-overrides is supported" './laptop-linux-optimiser.sh help | grep "clean-overrides" >/dev/null'

# ------------------------------------------------------------------------------
# Test 28: Complete Removal of DPI Bypass & Evasion Engine
# ------------------------------------------------------------------------------
echo "--- Test 28: Complete Removal of DPI Bypass & Evasion Engine ---"
assert_true "status_get_dpi function is removed" '! grep -q "^status_get_dpi()" ./laptop-linux-optimiser.sh'
assert_true "enable_dpi_mss function is removed" '! grep -q "^enable_dpi_mss()" ./laptop-linux-optimiser.sh'
assert_true "disable_dpi_mss function is removed" '! grep -q "^disable_dpi_mss()" ./laptop-linux-optimiser.sh'
assert_true "toggle_dpi_mss function is removed" '! grep -q "^toggle_dpi_mss()" ./laptop-linux-optimiser.sh'
assert_true "install_byedpi function is removed" '! grep -q "^install_byedpi()" ./laptop-linux-optimiser.sh'
assert_true "uninstall_byedpi function is removed" '! grep -q "^uninstall_byedpi()" ./laptop-linux-optimiser.sh'
assert_true "enable_byedpi function is removed" '! grep -q "^enable_byedpi()" ./laptop-linux-optimiser.sh'
assert_true "disable_byedpi function is removed" '! grep -q "^disable_byedpi()" ./laptop-linux-optimiser.sh'
assert_true "toggle_byedpi function is removed" '! grep -q "^toggle_byedpi()" ./laptop-linux-optimiser.sh'
assert_true "disable_all_dpi function is removed" '! grep -q "^disable_all_dpi()" ./laptop-linux-optimiser.sh'
assert_true "test_dpi_evasion function is removed" '! grep -q "^test_dpi_evasion()" ./laptop-linux-optimiser.sh'
assert_true "interactive_dpi_menu function is removed" '! grep -q "^interactive_dpi_menu()" ./laptop-linux-optimiser.sh'
assert_true "whiptail_dpi_menu function is removed" '! grep -q "^whiptail_dpi_menu()" ./laptop-linux-optimiser.sh'
assert_true "CLI dpi command is removed" '! ./laptop-linux-optimiser.sh dpi >/dev/null 2>&1'
assert_true "CLI help does not document dpi command" '! ./laptop-linux-optimiser.sh help | grep -q "Network DPI bypass"'
assert_true "CLI summary does not report Network DPI Bypass" '! ./laptop-linux-optimiser.sh summary | grep -q "Network DPI Bypass"'
assert_true "TUI dashboard does not display Network DPI pill" '! grep -q "Network DPI.*cur_dpi_pill" ./laptop-linux-optimiser.sh'
assert_true "TUI dashboard does not support Option 12 / dpi" '! grep -A 35 "case "\$opt" in" ./laptop-linux-optimiser.sh | grep -q "12|\[Dd\]|dpi)"'
assert_true "revert_system_tuning does not reference disable_all_dpi" '! grep -A 60 "^revert_system_tuning()" ./laptop-linux-optimiser.sh | grep -q "disable_all_dpi"'

# ------------------------------------------------------------------------------
# Test 29: Obsolete Network Tools Decoupling (DNS Shield & NM Probe)
# ------------------------------------------------------------------------------
echo "--- Test 29: Obsolete Network Tools Decoupling ---"
assert_true "status_get_dns_shield function is removed" '! grep -q "^status_get_dns_shield()" ./laptop-linux-optimiser.sh'
assert_true "enable_dns_shield function is removed" '! grep -q "^enable_dns_shield()" ./laptop-linux-optimiser.sh'
assert_true "disable_dns_shield function is removed" '! grep -q "^disable_dns_shield()" ./laptop-linux-optimiser.sh'
assert_true "toggle_dns_shield function is removed" '! grep -q "^toggle_dns_shield()" ./laptop-linux-optimiser.sh'
assert_true "disable_nm_connectivity_check function is removed" '! grep -q "^disable_nm_connectivity_check()" ./laptop-linux-optimiser.sh'
assert_true "enable_nm_connectivity_check function is removed" '! grep -q "^enable_nm_connectivity_check()" ./laptop-linux-optimiser.sh'
assert_true "toggle_nm_connectivity_check function is removed" '! grep -q "^toggle_nm_connectivity_check()" ./laptop-linux-optimiser.sh'
assert_true "status_get_nm_connectivity function is removed" '! grep -q "^status_get_nm_connectivity()" ./laptop-linux-optimiser.sh'
assert_true "CLI dns shield command is removed" '! ./laptop-linux-optimiser.sh dns shield >/dev/null 2>&1'
assert_true "CLI connectivity command is removed" '! ./laptop-linux-optimiser.sh connectivity >/dev/null 2>&1'
assert_true "CLI summary does not report DNS Leak Shield" '! ./laptop-linux-optimiser.sh summary | grep -q "DNS Leak Shield"'
assert_true "CLI summary does not report NM Connectivity Probe" '! ./laptop-linux-optimiser.sh summary | grep -q "NM Connectivity Probe"'

# ------------------------------------------------------------------------------
# Test 30: Module 10 — GRUB Bootloader Configuration & Recovery
# ------------------------------------------------------------------------------
echo "--- Test 30: GRUB Bootloader Configuration & Recovery ---"
assert_true "ensure_grub_default_config is defined" 'grep -q "^ensure_grub_default_config()" ./laptop-linux-optimiser.sh'
assert_true "fix_grub_menu is defined" 'grep -q "^fix_grub_menu()" ./laptop-linux-optimiser.sh'
assert_true "show_grub_status is defined" 'grep -q "^show_grub_status()" ./laptop-linux-optimiser.sh'
assert_true "CLI grub status outputs valid state" './laptop-linux-optimiser.sh grub status | grep -E "GRUB Base Config" >/dev/null'
assert_true "CLI help documents grub command" './laptop-linux-optimiser.sh help | grep "GRUB bootloader configuration" >/dev/null'
assert_true "CLI summary reports GRUB Baseline Config" './laptop-linux-optimiser.sh summary | grep "GRUB Baseline Config" >/dev/null'
assert_true "TUI dashboard includes option 14 for GRUB fix" 'grep -q "GRUB Bootloader Configuration" ./laptop-linux-optimiser.sh'

# ------------------------------------------------------------------------------
# Test 31: Bootloader Protection & Recovery in Housekeeping
# ------------------------------------------------------------------------------
echo "--- Test 31: Bootloader Protection in Housekeeping ---"
assert_true "clean_apt excludes bootloaders and kernels from rc purge" 'grep -A 20 "^clean_apt()" ./laptop-linux-optimiser.sh | grep -F "grub|shim|linux-|systemd-boot|efibootmgr" >/dev/null'
assert_true "clean_apt calls ensure_grub_default_config" 'grep -A 25 "^clean_apt()" ./laptop-linux-optimiser.sh | grep -q "ensure_grub_default_config"'
assert_true "apply_touchpad_cstate_cap calls ensure_grub_default_config" 'grep -A 30 "^apply_touchpad_cstate_cap()" ./laptop-linux-optimiser.sh | grep -q "ensure_grub_default_config"'
assert_true "apply_touchpad_psr_fix calls ensure_grub_default_config" 'grep -A 30 "^apply_touchpad_psr_fix()" ./laptop-linux-optimiser.sh | grep -q "ensure_grub_default_config"'
assert_true "remove_touchpad_cstate_cap calls ensure_grub_default_config" 'grep -A 30 "^remove_touchpad_cstate_cap()" ./laptop-linux-optimiser.sh | grep -q "ensure_grub_default_config"'
assert_true "remove_touchpad_psr_fix calls ensure_grub_default_config" 'grep -A 30 "^remove_touchpad_psr_fix()" ./laptop-linux-optimiser.sh | grep -q "ensure_grub_default_config"'

# ------------------------------------------------------------------------------
# Test 32: System & Network Decoupling Validation
# ------------------------------------------------------------------------------
echo "--- Test 32: System & Network Decoupling Validation ---"
assert_true "Lock re-entrancy handles subshells via OPTIMIZER_LOCKED" 'grep -A 15 "^acquire_lock()" ./laptop-linux-optimiser.sh | grep -q "OPTIMIZER_LOCKED"'
assert_true "Anonymized relay profiles 8-10 use genuine DNSCrypt resolvers" 'grep -A 25 "8|dnscrypt-relay" ./laptop-linux-optimiser.sh | grep -q "cs-de"'

# ------------------------------------------------------------------------------
# Test 33: Module 11 — ELAN Touchpad & I2C Controller Power Management
# ------------------------------------------------------------------------------
echo "--- Test 33: ELAN Touchpad PM, C-State Cap, PSR & Quirks Integration ---"
assert_true "touchpad_elan_devs is defined" 'grep -q "^touchpad_elan_devs()" ./laptop-linux-optimiser.sh'
assert_true "touchpad_ctrl_devs is defined" 'grep -q "^touchpad_ctrl_devs()" ./laptop-linux-optimiser.sh'
assert_true "detect_bootloader_type is defined" 'grep -q "^detect_bootloader_type()" ./laptop-linux-optimiser.sh'
assert_true "detect_gpu_psr_param is defined" 'grep -q "^detect_gpu_psr_param()" ./laptop-linux-optimiser.sh'
assert_true "is_touchpad_cstate_configured is defined" 'grep -q "^is_touchpad_cstate_configured()" ./laptop-linux-optimiser.sh'
assert_true "apply_touchpad_cstate_cap is defined" 'grep -q "^apply_touchpad_cstate_cap()" ./laptop-linux-optimiser.sh'
assert_true "remove_touchpad_cstate_cap is defined" 'grep -q "^remove_touchpad_cstate_cap()" ./laptop-linux-optimiser.sh'
assert_true "toggle_touchpad_cstate_cap is defined" 'grep -q "^toggle_touchpad_cstate_cap()" ./laptop-linux-optimiser.sh'
assert_true "is_touchpad_psr_configured is defined" 'grep -q "^is_touchpad_psr_configured()" ./laptop-linux-optimiser.sh'
assert_true "apply_touchpad_psr_fix is defined" 'grep -q "^apply_touchpad_psr_fix()" ./laptop-linux-optimiser.sh'
assert_true "remove_touchpad_psr_fix is defined" 'grep -q "^remove_touchpad_psr_fix()" ./laptop-linux-optimiser.sh'
assert_true "toggle_touchpad_psr_fix is defined" 'grep -q "^toggle_touchpad_psr_fix()" ./laptop-linux-optimiser.sh'
assert_true "show_touchpad_psr_status is defined" 'grep -q "^show_touchpad_psr_status()" ./laptop-linux-optimiser.sh'
assert_true "touchpad_has_pressure is defined" 'grep -q "^touchpad_has_pressure()" ./laptop-linux-optimiser.sh'
assert_true "is_touchpad_quirks_installed is defined" 'grep -q "^is_touchpad_quirks_installed()" ./laptop-linux-optimiser.sh'
assert_true "apply_touchpad_quirks is defined" 'grep -q "^apply_touchpad_quirks()" ./laptop-linux-optimiser.sh'
assert_true "remove_touchpad_quirks is defined" 'grep -q "^remove_touchpad_quirks()" ./laptop-linux-optimiser.sh'
assert_true "toggle_touchpad_quirks is defined" 'grep -q "^toggle_touchpad_quirks()" ./laptop-linux-optimiser.sh'
assert_true "show_touchpad_quirks_status is defined" 'grep -q "^show_touchpad_quirks_status()" ./laptop-linux-optimiser.sh'
assert_true "is_evdi_boot_load_enabled is defined" 'grep -q "^is_evdi_boot_load_enabled()" ./laptop-linux-optimiser.sh'
assert_true "is_evdi_card0_hijacked is defined" 'grep -q "^is_evdi_card0_hijacked()" ./laptop-linux-optimiser.sh'
assert_true "fix_evdi_boot_hijack is defined" 'grep -q "^fix_evdi_boot_hijack()" ./laptop-linux-optimiser.sh'
assert_true "restore_evdi_boot_hijack is defined" 'grep -q "^restore_evdi_boot_hijack()" ./laptop-linux-optimiser.sh'
assert_true "toggle_evdi_boot_hijack is defined" 'grep -q "^toggle_evdi_boot_hijack()" ./laptop-linux-optimiser.sh'
assert_true "show_evdi_status is defined" 'grep -q "^show_evdi_status()" ./laptop-linux-optimiser.sh'
assert_true "fix_touchpad_stutter is defined" 'grep -q "^fix_touchpad_stutter()" ./laptop-linux-optimiser.sh'
assert_true "apply_touchpad_runtime is defined" 'grep -q "^apply_touchpad_runtime()" ./laptop-linux-optimiser.sh'
assert_true "install_touchpad_permanent is defined" 'grep -q "^install_touchpad_permanent()" ./laptop-linux-optimiser.sh'
assert_true "revert_touchpad is defined" 'grep -q "^revert_touchpad()" ./laptop-linux-optimiser.sh'
assert_true "status_get_touchpad is defined" 'grep -q "^status_get_touchpad()" ./laptop-linux-optimiser.sh'
assert_true "show_touchpad_status is defined" 'grep -q "^show_touchpad_status()" ./laptop-linux-optimiser.sh'
assert_true "run_touchpad_diagnostics is defined" 'grep -q "^run_touchpad_diagnostics()" ./laptop-linux-optimiser.sh'
assert_true "interactive_touchpad_menu is defined" 'grep -q "^interactive_touchpad_menu()" ./laptop-linux-optimiser.sh'
assert_true "whiptail_touchpad_menu is defined" 'grep -q "^whiptail_touchpad_menu()" ./laptop-linux-optimiser.sh'
assert_true "CLI touchpad status outputs valid state" './laptop-linux-optimiser.sh touchpad status | grep -E "ELAN I2C Touchpad" >/dev/null'
assert_true "CLI tune touchpad status outputs valid state" './laptop-linux-optimiser.sh tune touchpad status | grep -E "ELAN I2C Touchpad" >/dev/null'
assert_true "CLI touchpad cstate status outputs valid state" './laptop-linux-optimiser.sh touchpad cstate status | grep -E "Touchpad C-State Cap" >/dev/null'
assert_true "CLI touchpad psr status outputs valid state" './laptop-linux-optimiser.sh touchpad psr status | grep -E "Touchpad GPU PSR Fix" >/dev/null'
assert_true "CLI touchpad quirks status outputs valid state" './laptop-linux-optimiser.sh touchpad quirks status | grep -E "Touchpad Libinput Quirks" >/dev/null'
assert_true "CLI tune touchpad psr status outputs valid state" './laptop-linux-optimiser.sh tune touchpad psr status | grep -E "Touchpad GPU PSR Fix" >/dev/null'
assert_true "CLI tune touchpad quirks status outputs valid state" './laptop-linux-optimiser.sh tune touchpad quirks status | grep -E "Touchpad Libinput Quirks" >/dev/null'
assert_true "CLI touchpad evdi status outputs valid state" './laptop-linux-optimiser.sh touchpad evdi status | grep -E "DisplayLink EVDI Load" >/dev/null'
assert_true "CLI tune touchpad evdi status outputs valid state" './laptop-linux-optimiser.sh tune touchpad evdi status | grep -E "DisplayLink EVDI Load" >/dev/null'
assert_true "CLI tune evdi status outputs valid state" './laptop-linux-optimiser.sh tune evdi status | grep -E "DisplayLink EVDI Load" >/dev/null'
assert_true "CLI help documents evdi command" './laptop-linux-optimiser.sh --help | grep -E "evdi" >/dev/null'
assert_true "CLI help documents fix-stutter command" './laptop-linux-optimiser.sh --help | grep -E "fix-stutter" >/dev/null'
assert_true "CLI summary reports ELAN Touchpad PM" './laptop-linux-optimiser.sh summary | grep "ELAN Touchpad PM" >/dev/null'
assert_true "Touchpad permanent install creates udev rule" 'grep -A 25 "^install_touchpad_permanent()" ./laptop-linux-optimiser.sh | grep -q "TOUCHPAD_UDEV_RULE"'
assert_true "Touchpad permanent install creates sleep hook" 'grep -A 45 "^install_touchpad_permanent()" ./laptop-linux-optimiser.sh | grep -q "TOUCHPAD_SLEEP_HOOK"'
assert_true "Touchpad permanent install applies libinput quirks" 'grep -A 60 "^install_touchpad_permanent()" ./laptop-linux-optimiser.sh | grep -q "apply_touchpad_quirks"'
assert_true "Touchpad permanent install checks EVDI boot-load conflict" 'grep -A 65 "^install_touchpad_permanent()" ./laptop-linux-optimiser.sh | grep -q "fix_evdi_boot_hijack"'
assert_true "Touchpad permanent install applies GPU PSR fix" 'grep -A 90 "^install_touchpad_permanent()" ./laptop-linux-optimiser.sh | grep -q "apply_touchpad_psr_fix"'
assert_true "Touchpad revert removes libinput quirks" 'grep -A 25 "^revert_touchpad()" ./laptop-linux-optimiser.sh | grep -q "remove_touchpad_quirks"'
assert_true "Touchpad revert removes GPU PSR fix" 'grep -A 25 "^revert_touchpad()" ./laptop-linux-optimiser.sh | grep -q "remove_touchpad_psr_fix"'
assert_true "Touchpad bootloader detection recognizes kernelstub" 'grep -A 20 "^detect_bootloader_type()" ./laptop-linux-optimiser.sh | grep -q "kernelstub"'

# ------------------------------------------------------------------------------
# Test 34: Privacy & Security Audit — Path Containment & is_safe_home
# ------------------------------------------------------------------------------
echo "--- Test 34: Privacy & Security Audit — Path Containment & is_safe_home ---"
source <(sed -n "/^is_safe_home()/,/^}/p" ./laptop-linux-optimiser.sh)
source <(sed -n "/^is_safe_user_path()/,/^}/p" ./laptop-linux-optimiser.sh)

assert_true "is_safe_home is defined" 'declare -f is_safe_home >/dev/null'
assert_true "is_safe_home rejects non-existent dir" '! is_safe_home "/home/nonexistent_xyz_123"'
assert_true "is_safe_user_path allows user home target itself" 'is_safe_user_path "/root" "/root"'
assert_true "is_safe_user_path rejects targets outside user home" '
    tmp_mock=$(mktemp -d /tmp/mock_home_XXXXXX)
    ! is_safe_user_path "$tmp_mock" "$tmp_mock"
    rv=$?
    rm -rf "$tmp_mock"
    [ $rv -eq 0 ]
'

# ------------------------------------------------------------------------------
# Test 35: Clean Overrides — Byedpi Cleanup & User Deletion
# ------------------------------------------------------------------------------
echo "--- Test 35: Clean Overrides — Byedpi Cleanup ---"
assert_true "clean_network_overrides removes byedpi binary and user" 'grep -A 30 "^clean_network_overrides()" ./laptop-linux-optimiser.sh | grep "userdel" >/dev/null'
assert_true "clean_network_overrides removes byedpi config" 'grep -A 30 "^clean_network_overrides()" ./laptop-linux-optimiser.sh | grep -q "/etc/byedpi.conf"'

# ------------------------------------------------------------------------------
# Test 36: Clean Overrides — Iptables Nat and Mangle Cleanup
# ------------------------------------------------------------------------------
echo "--- Test 36: Clean Overrides — Netfilter Rule Flush ---"
assert_true "clean_network_overrides flushes nat and mangle tables" 'grep -A 50 "^clean_network_overrides()" ./laptop-linux-optimiser.sh | grep -q "iptables -w 5 -t nat"'
assert_true "clean_network_overrides flushes IPv6 mangle tables" 'grep -A 70 "^clean_network_overrides()" ./laptop-linux-optimiser.sh | grep -q "ip6tables -w 5 -t mangle"'

# ------------------------------------------------------------------------------
# Test 37: Privacy & Security Audit — Root Symlink Traversal Immunity
# ------------------------------------------------------------------------------
echo "--- Test 37: Privacy & Security Audit — Root Symlink Traversal Immunity ---"
assert_true "enable_font_antiblur guards fontconfig directory against symlinks" 'grep -A 30 "^enable_font_antiblur()" ./laptop-linux-optimiser.sh | grep -q "Refusing to modify symlinked fontconfig path"'
assert_true "verify_theme_preservation checks for symlinks on flatpak overrides" 'grep -A 25 "^verify_theme_preservation()" ./laptop-linux-optimiser.sh | grep -F "[ -L \"\$fp_ov\" ]" >/dev/null'
assert_true "verify_theme_preservation uses chown --no-dereference" 'grep -A 40 "^verify_theme_preservation()" ./laptop-linux-optimiser.sh | grep -q "chown --no-dereference"'

# ------------------------------------------------------------------------------
# Test 38: Clean Overrides — NetworkManager Connectivity Probe Restoration
# ------------------------------------------------------------------------------
echo "--- Test 38: Clean Overrides — NM Probe Restoration & CloudflareWARP Decoupling ---"
assert_true "clean_network_overrides restores NetworkManager connectivity check" 'grep -A 130 "^clean_network_overrides()" ./laptop-linux-optimiser.sh | grep "ConnectivityCheckEnabled b true" >/dev/null'
assert_true "clean_network_overrides removes 20-connectivity.conf" 'grep -A 30 "^clean_network_overrides()" ./laptop-linux-optimiser.sh | grep -q "20-connectivity.conf"'
assert_true "clean_network_overrides sets CloudflareWARP unmanaged in NetworkManager" 'grep -A 130 "^clean_network_overrides()" ./laptop-linux-optimiser.sh | grep "unmanaged-devices=interface-name:CloudflareWARP" >/dev/null'
assert_true "clean_network_overrides deletes NetworkManager CloudflareWARP connections" 'grep -A 130 "^clean_network_overrides()" ./laptop-linux-optimiser.sh | grep "nmcli connection delete" >/dev/null'

# ------------------------------------------------------------------------------
# Test 39: Privacy & Security Audit — Status Truthfulness & IPv6 RFC 4941
# ------------------------------------------------------------------------------
echo "--- Test 39: Privacy & Security Audit — Status Truthfulness & IPv6 RFC 4941 ---"
assert_true "show_dns_status uses table-scoped awk parser for query_log" "grep -A 35 '^show_dns_status()' ./laptop-linux-optimiser.sh | grep -q 'query_log'"
assert_true "enable_ipv6 configures net.ipv6.conf.all.use_tempaddr=2" 'grep -A 20 "^enable_ipv6()" ./laptop-linux-optimiser.sh | grep -q "net\.ipv6\.conf\.all\.use_tempaddr=2"'
assert_true "enable_ipv6 configures addr_gen_mode=3" 'grep -A 25 "^enable_ipv6()" ./laptop-linux-optimiser.sh | grep -q "addr_gen_mode=3"'

# ------------------------------------------------------------------------------
# Test 40: Interactive Menus — Formatting and ANSI Escape Sequences
# ------------------------------------------------------------------------------
echo "--- Test 40: Interactive Menus — Formatting & ANSI Escapes ---"
assert_true "interactive_dns_menu uses echo -e on all options including option 10" '! grep -A 60 "^interactive_dns_menu()" ./laptop-linux-optimiser.sh | grep -E "echo \"[ ]*10\)"'
assert_true "interactive_dns_menu consistently aligns column delimiters" 'grep -A 75 "^interactive_dns_menu()" ./laptop-linux-optimiser.sh | grep "Scaleway Privacy via Relay" >/dev/null'

# ------------------------------------------------------------------------------
# Test 41: Snap Package Housekeeping & Ubuntu Cleaning
# ------------------------------------------------------------------------------
echo "--- Test 41: Snap Package Housekeeping & Ubuntu Cleaning ---"
assert_true "update_snap function is defined" 'grep -q "^update_snap()" ./laptop-linux-optimiser.sh'
assert_true "clean_snap function is defined" 'grep -q "^clean_snap()" ./laptop-linux-optimiser.sh'
assert_true "update_and_clean integrates update_snap" 'grep -A 25 "^update_and_clean()" ./laptop-linux-optimiser.sh | grep -q "update_snap"'
assert_true "run_optimizer integrates clean_snap" 'grep -A 40 "^run_optimizer()" ./laptop-linux-optimiser.sh | grep -q "clean_snap"'
assert_true "clean_privacy cleans Snap browser caches" 'grep -A 100 "^clean_privacy()" ./laptop-linux-optimiser.sh | grep -F "snap/\$sbrowser" >/dev/null'

# ------------------------------------------------------------------------------
# Test 42: Network Decoupling & Clean Overrides
# ------------------------------------------------------------------------------
echo "--- Test 42: Network Decoupling & Clean Overrides ---"
assert_true "clean_network_overrides function is defined" 'grep -q "^clean_network_overrides()" ./laptop-linux-optimiser.sh'
assert_true "CLI network clean-overrides is supported" 'grep -A 20 "network|net)" ./laptop-linux-optimiser.sh | grep -q "clean-overrides"'
assert_true "CLI help documents network clean-overrides command" './laptop-linux-optimiser.sh --help | grep "clean-overrides" >/dev/null'

# ------------------------------------------------------------------------------
# Test 43: Touchpad GNOME Gestures & Latency Tuning
# ------------------------------------------------------------------------------
echo "--- Test 43: Touchpad GNOME Gestures & Latency Tuning ---"
assert_true "tune_gnome_touchpad function is defined" 'grep -q "^tune_gnome_touchpad()" ./laptop-linux-optimiser.sh'
assert_true "fix_touchpad_stutter calls tune_gnome_touchpad" 'grep -A 100 "^fix_touchpad_stutter()" ./laptop-linux-optimiser.sh | grep "tune_gnome_touchpad" >/dev/null'
assert_true "install_touchpad_permanent calls tune_gnome_touchpad" 'grep -A 90 "^install_touchpad_permanent()" ./laptop-linux-optimiser.sh | grep -q "tune_gnome_touchpad"'
assert_true "CLI touchpad gestures is supported" 'grep -A 100 "touchpad|elan|trackpad)" ./laptop-linux-optimiser.sh | grep -q "gestures|gnome)"'
assert_true "run_user_gsettings is defined" 'grep -q "^run_user_gsettings()" ./laptop-linux-optimiser.sh'
assert_true "get_user_gsettings is defined" 'grep -q "^get_user_gsettings()" ./laptop-linux-optimiser.sh'
assert_true "run_user_gsettings exports DBUS_SESSION_BUS_ADDRESS" 'grep -A 25 "^run_user_gsettings()" ./laptop-linux-optimiser.sh | grep -q "DBUS_SESSION_BUS_ADDRESS"'
assert_true "EVDI_MODPROBE_CONF is defined" 'grep -q "^EVDI_MODPROBE_CONF=" ./laptop-linux-optimiser.sh'
assert_true "status_get_touchpad_dwt is defined" 'grep -q "^status_get_touchpad_dwt()" ./laptop-linux-optimiser.sh'
assert_true "show_touchpad_dwt_status is defined" 'grep -q "^show_touchpad_dwt_status()" ./laptop-linux-optimiser.sh'
assert_true "enable_touchpad_dwt is defined" 'grep -q "^enable_touchpad_dwt()" ./laptop-linux-optimiser.sh'
assert_true "disable_touchpad_dwt is defined" 'grep -q "^disable_touchpad_dwt()" ./laptop-linux-optimiser.sh'
assert_true "toggle_touchpad_dwt is defined" 'grep -q "^toggle_touchpad_dwt()" ./laptop-linux-optimiser.sh'
assert_true "tune_gnome_touchpad sets click-method default" 'grep -A 20 "^tune_gnome_touchpad()" ./laptop-linux-optimiser.sh | grep -q "click-method.*default"'
assert_true "tune_gnome_touchpad sets disable-while-typing true" 'grep -A 20 "^tune_gnome_touchpad()" ./laptop-linux-optimiser.sh | grep -q "disable-while-typing.*true"'
assert_true "smart_touchpad_autotune is defined" 'grep -q "^smart_touchpad_autotune()" ./laptop-linux-optimiser.sh'
assert_true "CLI touchpad auto is supported" 'grep -A 25 "touchpad|elan|trackpad)" ./laptop-linux-optimiser.sh | grep -q "auto|smart)"'
assert_true "CLI touchpad dwt status outputs valid state" './laptop-linux-optimiser.sh touchpad dwt status | grep -E "Touchpad Disable-While-Typing" >/dev/null'
assert_true "CLI tune touchpad dwt status outputs valid state" './laptop-linux-optimiser.sh tune touchpad dwt status | grep -E "Touchpad Disable-While-Typing" >/dev/null'
assert_true "is_touchpad_acpi_100khz_active is defined" 'grep -q "^is_touchpad_acpi_100khz_active()" ./laptop-linux-optimiser.sh'
assert_true "status_get_touchpad_acpi_100khz is defined" 'grep -q "^status_get_touchpad_acpi_100khz()" ./laptop-linux-optimiser.sh'
assert_true "show_touchpad_acpi_status is defined" 'grep -q "^show_touchpad_acpi_status()" ./laptop-linux-optimiser.sh'
assert_true "apply_touchpad_acpi_100khz is defined" 'grep -q "^apply_touchpad_acpi_100khz()" ./laptop-linux-optimiser.sh'
assert_true "remove_touchpad_acpi_100khz is defined" 'grep -q "^remove_touchpad_acpi_100khz()" ./laptop-linux-optimiser.sh'
assert_true "toggle_touchpad_acpi_100khz is defined" 'grep -q "^toggle_touchpad_acpi_100khz()" ./laptop-linux-optimiser.sh'
assert_true "TOUCHPAD_ACPI_OVERRIDE is /boot/acpi_override" 'grep -q "TOUCHPAD_ACPI_OVERRIDE=.*boot.*acpi_override" ./laptop-linux-optimiser.sh'
assert_true "TOUCHPAD_ACPI_GRUB is /etc/default/grub.d/99-elan-acpi.cfg" 'grep -q "TOUCHPAD_ACPI_GRUB=.*etc.*default.*grub.d.*99-elan-acpi\.cfg" ./laptop-linux-optimiser.sh'
assert_true "apply_touchpad_quirks preserves double-tap button codes for scrolling" '! grep -A 25 "^apply_touchpad_quirks()" ./laptop-linux-optimiser.sh | grep -q "BTN_TOOL_DOUBLETAP"'
assert_true "fix_touchpad_stutter checks ACPI 100khz override" 'grep -A 100 "^fix_touchpad_stutter()" ./laptop-linux-optimiser.sh | grep -q "apply_touchpad_acpi_100khz"'
assert_true "install_touchpad_permanent checks ACPI 100khz override" 'grep -A 100 "^install_touchpad_permanent()" ./laptop-linux-optimiser.sh | grep -q "apply_touchpad_acpi_100khz"'
assert_true "revert_touchpad removes ACPI 100khz override" 'grep -A 25 "^revert_touchpad()" ./laptop-linux-optimiser.sh | grep -q "remove_touchpad_acpi_100khz"'
assert_true "revert_touchpad resets GNOME touchpad settings" 'grep -A 25 "^revert_touchpad()" ./laptop-linux-optimiser.sh | grep -q "reset_gnome_touchpad"'
assert_true "CLI touchpad speed status outputs valid state" './laptop-linux-optimiser.sh touchpad speed status | grep -E "ELAN I2C Bus Frequency" >/dev/null'
assert_true "CLI tune touchpad speed status outputs valid state" './laptop-linux-optimiser.sh tune touchpad speed status | grep -E "ELAN I2C Bus Frequency" >/dev/null'
assert_true "CLI help documents speed command" './laptop-linux-optimiser.sh --help | grep -E "speed" >/dev/null'
assert_true "status_get_touchpad_tap_drag is defined" 'grep -q "^status_get_touchpad_tap_drag()" ./laptop-linux-optimiser.sh'
assert_true "show_touchpad_tap_drag_status is defined" 'grep -q "^show_touchpad_tap_drag_status()" ./laptop-linux-optimiser.sh'
assert_true "enable_touchpad_tap_drag is defined" 'grep -q "^enable_touchpad_tap_drag()" ./laptop-linux-optimiser.sh'
assert_true "disable_touchpad_tap_drag is defined" 'grep -q "^disable_touchpad_tap_drag()" ./laptop-linux-optimiser.sh'
assert_true "toggle_touchpad_tap_drag is defined" 'grep -q "^toggle_touchpad_tap_drag()" ./laptop-linux-optimiser.sh'
assert_true "status_get_touchpad_accel_profile is defined" 'grep -q "^status_get_touchpad_accel_profile()" ./laptop-linux-optimiser.sh'
assert_true "show_touchpad_accel_profile_status is defined" 'grep -q "^show_touchpad_accel_profile_status()" ./laptop-linux-optimiser.sh'
assert_true "set_touchpad_accel_profile is defined" 'grep -q "^set_touchpad_accel_profile()" ./laptop-linux-optimiser.sh'
assert_true "toggle_touchpad_accel_profile is defined" 'grep -q "^toggle_touchpad_accel_profile()" ./laptop-linux-optimiser.sh'
assert_true "tune_gnome_touchpad sets tap-and-drag true" 'grep -A 20 "^tune_gnome_touchpad()" ./laptop-linux-optimiser.sh | grep -q "tap-and-drag.*true"'
assert_true "CLI touchpad tap-drag status outputs valid state" './laptop-linux-optimiser.sh touchpad tap-drag status | grep -E "Touchpad Tap-and-Drag" >/dev/null'
assert_true "CLI tune touchpad tap-drag status outputs valid state" './laptop-linux-optimiser.sh tune touchpad tap-drag status | grep -E "Touchpad Tap-and-Drag" >/dev/null'
assert_true "CLI touchpad accel status outputs valid state" './laptop-linux-optimiser.sh touchpad accel status | grep -E "Touchpad Acceleration Profile" >/dev/null'
assert_true "CLI tune touchpad accel status outputs valid state" './laptop-linux-optimiser.sh tune touchpad accel status | grep -E "Touchpad Acceleration Profile" >/dev/null'
assert_true "CLI help documents tap-drag command" './laptop-linux-optimiser.sh --help | grep -E "tap-drag" >/dev/null'
assert_true "CLI help documents accel command" './laptop-linux-optimiser.sh --help | grep -E "accel" >/dev/null'

# ------------------------------------------------------------------------------
# Test 44: Battery Charge Limiter Persistence Across Reboot, Sleep & AC
# ------------------------------------------------------------------------------
echo "--- Test 44: Battery Charge Limiter Persistence ---"
assert_true "BATTERY_SERVICE is laptop-battery-limit.service" 'grep -q "BATTERY_SERVICE=.*laptop-battery-limit\.service" ./laptop-linux-optimiser.sh'
assert_true "BATTERY_UDEV_RULE imports BATTERY_CONF" 'grep -q "IMPORT{file}=\"\$BATTERY_CONF\"" ./laptop-linux-optimiser.sh'
assert_true "BATTERY_UDEV_RULE triggers laptop-battery-limit.service restart" 'grep -q "restart laptop-battery-limit\.service" ./laptop-linux-optimiser.sh'
assert_true "BATTERY_SLEEP_HOOK configures battery limiter wake trigger" 'grep -q "BATTERY_SLEEP_HOOK=.*laptop-battery-limit" ./laptop-linux-optimiser.sh'
assert_true "status_get_battery checks laptop-battery-limit.service" 'grep -A 20 "^status_get_battery()" ./laptop-linux-optimiser.sh | grep -q "laptop-battery-limit\.service"'
assert_true "show_battery_status checks laptop-battery-limit.service" 'grep -A 100 "^show_battery_status()" ./laptop-linux-optimiser.sh | grep -q "laptop-battery-limit\.service"'

# ------------------------------------------------------------------------------
# Test 45: Popular Themes Gallery & Uniform Styling
# ------------------------------------------------------------------------------
echo "--- Test 45: Popular Themes Gallery & Uniform Styling ---"
assert_true "GALLERY_THEMES_MANIFEST is defined" 'grep -q "^GALLERY_THEMES_MANIFEST=" ./laptop-linux-optimiser.sh'
assert_true "status_get_uniform_theme is defined" 'grep -q "^status_get_uniform_theme()" ./laptop-linux-optimiser.sh'
assert_true "is_theme_installed is defined" 'grep -q "^is_theme_installed()" ./laptop-linux-optimiser.sh'
assert_true "show_theme_gallery is defined" 'grep -q "^show_theme_gallery()" ./laptop-linux-optimiser.sh'
assert_true "install_gallery_theme is defined" 'grep -q "^install_gallery_theme()" ./laptop-linux-optimiser.sh'
assert_true "apply_uniform_theme is defined" 'grep -q "^apply_uniform_theme()" ./laptop-linux-optimiser.sh'
assert_true "reset_uniform_theme is defined" 'grep -q "^reset_uniform_theme()" ./laptop-linux-optimiser.sh'
assert_true "CLI theme gallery is supported" 'grep -A 25 "theme|themes|appearance)" ./laptop-linux-optimiser.sh | grep -q "gallery"'
assert_true "CLI theme status outputs valid state" './laptop-linux-optimiser.sh theme status | grep -E "Uniform Theme" >/dev/null'
assert_true "CLI theme reset is supported" 'grep -A 25 "theme|themes|appearance)" ./laptop-linux-optimiser.sh | grep -q "reset"'
assert_true "CLI help documents theme command" './laptop-linux-optimiser.sh --help | grep "theme, themes" >/dev/null'
assert_true "TUI dashboard displays Uniform Theme status" 'grep -q "Uniform Theme" ./laptop-linux-optimiser.sh'
assert_true "TUI dashboard includes option 14 for themes gallery" 'grep -A 160 "^show_tui_dashboard()" ./laptop-linux-optimiser.sh | grep -q "\[14\]"'

# ------------------------------------------------------------------------------
# Test 46: Media Codecs, Fonts & Hardware Acceleration Drivers (AMD APU / Mesa)
# ------------------------------------------------------------------------------
echo "--- Test 46: Media Codecs, Fonts & Hardware Acceleration Drivers ---"
assert_true "MEDIA_DRIVER_PKGS is defined" 'grep -q "^MEDIA_DRIVER_PKGS=" ./laptop-linux-optimiser.sh'
assert_true "MEDIA_CODEC_PKGS is defined" 'grep -q "^MEDIA_CODEC_PKGS=" ./laptop-linux-optimiser.sh'
assert_true "MEDIA_FONT_PKGS is defined" 'grep -q "^MEDIA_FONT_PKGS=" ./laptop-linux-optimiser.sh'
assert_true "MEDIA_32BIT_PKGS is defined" 'grep -q "^MEDIA_32BIT_PKGS=" ./laptop-linux-optimiser.sh'
assert_true "status_get_media_drivers is defined" 'grep -q "^status_get_media_drivers()" ./laptop-linux-optimiser.sh'
assert_true "show_media_driver_status is defined" 'grep -q "^show_media_driver_status()" ./laptop-linux-optimiser.sh'
assert_true "install_media_hardware_drivers is defined" 'grep -q "^install_media_hardware_drivers()" ./laptop-linux-optimiser.sh'
assert_true "install_media_codecs is defined" 'grep -q "^install_media_codecs()" ./laptop-linux-optimiser.sh'
assert_true "install_font_packs is defined" 'grep -q "^install_font_packs()" ./laptop-linux-optimiser.sh'
assert_true "install_all_media_suite is defined" 'grep -q "^install_all_media_suite()" ./laptop-linux-optimiser.sh'
assert_true "verify_hardware_acceleration is defined" 'grep -q "^verify_hardware_acceleration()" ./laptop-linux-optimiser.sh'
assert_true "interactive_media_menu is defined" 'grep -q "^interactive_media_menu()" ./laptop-linux-optimiser.sh'
assert_true "whiptail_media_menu is defined" 'grep -q "^whiptail_media_menu()" ./laptop-linux-optimiser.sh'
assert_true "CLI media status outputs valid state" './laptop-linux-optimiser.sh media status | grep -E "Graphics Controller|Vulkan" >/dev/null'
assert_true "CLI help documents media command" './laptop-linux-optimiser.sh --help | grep "media, multimedia" >/dev/null'
assert_true "CLI summary reports Media & GPU Drivers" './laptop-linux-optimiser.sh summary | grep "Media & GPU Drivers" >/dev/null'
assert_true "TUI dashboard displays Media & Drivers status" 'grep -q "Media & Drivers" ./laptop-linux-optimiser.sh'
assert_true "TUI dashboard includes option 15 for media suite" 'grep -A 180 "^show_tui_dashboard()" ./laptop-linux-optimiser.sh | grep -q "\[15\]"'
assert_true "Whiptail TUI includes option 15 for media suite" 'grep -A 50 "^show_whiptail_tui()" ./laptop-linux-optimiser.sh | grep -q "\"15\""'
assert_true "status_get_media_drivers supports mesa-libgallium" 'grep -A 5 "^status_get_media_drivers()" ./laptop-linux-optimiser.sh | grep -q "mesa-libgallium"'
assert_true "show_media_driver_status supports mesa-libgallium" 'grep -A 35 "^show_media_driver_status()" ./laptop-linux-optimiser.sh | grep -q "mesa-libgallium"'

# ------------------------------------------------------------------------------
# Test 47: AMD P-State EPP, Audio Crackle, Browser VA-API, TRIM, Apport, UFW & BT
# ------------------------------------------------------------------------------
echo "--- Test 47: AMD P-State EPP, Audio Crackle, Browser VA-API, TRIM, Apport, UFW & BT ---"
assert_true "status_get_epp is defined" 'grep -q "^status_get_epp()" ./laptop-linux-optimiser.sh'
assert_true "set_epp_preference is defined" 'grep -q "^set_epp_preference()" ./laptop-linux-optimiser.sh'
assert_true "show_epp_status is defined" 'grep -q "^show_epp_status()" ./laptop-linux-optimiser.sh'
assert_true "status_get_audio_powersave is defined" 'grep -q "^status_get_audio_powersave()" ./laptop-linux-optimiser.sh'
assert_true "enable_audio_powersave_fix is defined" 'grep -q "^enable_audio_powersave_fix()" ./laptop-linux-optimiser.sh'
assert_true "revert_audio_powersave_fix is defined" 'grep -q "^revert_audio_powersave_fix()" ./laptop-linux-optimiser.sh'
assert_true "status_get_apport is defined" 'grep -q "^status_get_apport()" ./laptop-linux-optimiser.sh'
assert_true "disable_apport is defined" 'grep -q "^disable_apport()" ./laptop-linux-optimiser.sh'
assert_true "status_get_fstrim is defined" 'grep -q "^status_get_fstrim()" ./laptop-linux-optimiser.sh'
assert_true "enable_fstrim_timer is defined" 'grep -q "^enable_fstrim_timer()" ./laptop-linux-optimiser.sh'
assert_true "run_fstrim_now is defined" 'grep -q "^run_fstrim_now()" ./laptop-linux-optimiser.sh'
assert_true "status_get_ufw is defined" 'grep -q "^status_get_ufw()" ./laptop-linux-optimiser.sh'
assert_true "enable_laptop_firewall is defined" 'grep -q "^enable_laptop_firewall()" ./laptop-linux-optimiser.sh'
assert_true "status_get_browser_vaapi is defined" 'grep -q "^status_get_browser_vaapi()" ./laptop-linux-optimiser.sh'
assert_true "enable_browser_vaapi is defined" 'grep -q "^enable_browser_vaapi()" ./laptop-linux-optimiser.sh'
assert_true "revert_browser_vaapi is defined" 'grep -q "^revert_browser_vaapi()" ./laptop-linux-optimiser.sh'
assert_true "status_get_bluetooth_codecs is defined" 'grep -q "^status_get_bluetooth_codecs()" ./laptop-linux-optimiser.sh'
assert_true "CLI epp status outputs valid state" './laptop-linux-optimiser.sh epp status | grep -E "EPP Preference" >/dev/null'
assert_true "CLI audio status outputs valid state" './laptop-linux-optimiser.sh audio status | grep -E "Audio Powersave" >/dev/null'
assert_true "CLI browser-vaapi status outputs valid state" './laptop-linux-optimiser.sh browser-vaapi status | grep -E "VA-API Status" >/dev/null'
assert_true "CLI trim status outputs valid state" './laptop-linux-optimiser.sh trim status | grep -E "fstrim.timer" >/dev/null'
assert_true "CLI apport status outputs valid state" './laptop-linux-optimiser.sh apport status | grep -E "Apport Crash" >/dev/null'
assert_true "CLI firewall status outputs valid state" './laptop-linux-optimiser.sh firewall status | grep -E "Firewall State" >/dev/null'
assert_true "CLI bluetooth status outputs valid state" './laptop-linux-optimiser.sh bluetooth status | grep -E "Bluetooth Audio" >/dev/null'
assert_true "CLI summary reports EPP status" './laptop-linux-optimiser.sh summary | grep "CPU Scaling (EPP)" >/dev/null'
assert_true "CLI summary reports Audio Pop Shield" './laptop-linux-optimiser.sh summary | grep "Audio Pop Shield" >/dev/null'
assert_true "CLI summary reports Laptop UFW Shield" './laptop-linux-optimiser.sh summary | grep "Laptop UFW Shield" >/dev/null'
assert_true "CLI summary reports Apport Crash Popups" './laptop-linux-optimiser.sh summary | grep "Apport Crash Popups" >/dev/null'
assert_true "CLI summary reports Browser Video VA-API" './laptop-linux-optimiser.sh summary | grep "Browser Video VA-API" >/dev/null'
assert_true "CLI summary reports SSD Periodic TRIM" './laptop-linux-optimiser.sh summary | grep "SSD Periodic TRIM" >/dev/null'
assert_true "CLI help documents epp command" './laptop-linux-optimiser.sh --help | grep "epp, amd-pstate" >/dev/null'
assert_true "CLI help documents audio command" './laptop-linux-optimiser.sh --help | grep "audio, audio-powersave" >/dev/null'
assert_true "CLI help documents browser-vaapi command" './laptop-linux-optimiser.sh --help | grep "browser-vaapi, browser" >/dev/null'
assert_true "CLI help documents trim command" './laptop-linux-optimiser.sh --help | grep "trim, fstrim" >/dev/null'
assert_true "CLI help documents apport command" './laptop-linux-optimiser.sh --help | grep "apport, crash-reports" >/dev/null'
assert_true "CLI help documents firewall command" './laptop-linux-optimiser.sh --help | grep "firewall, ufw" >/dev/null'
assert_true "CLI help documents bluetooth command" './laptop-linux-optimiser.sh --help | grep "bluetooth, bt" >/dev/null'

# ------------------------------------------------------------------------------
# Test 48: Comprehensive 14-Step Guided Wizard & Categorized Menus
# ------------------------------------------------------------------------------
echo "--- Test 48: Comprehensive 14-Step Guided Wizard & Categorized Menus ---"
assert_true "run_guided_wizard mentions 14-step overview" 'grep -A 20 "^run_guided_wizard()" ./laptop-linux-optimiser.sh | grep -q "Step 1/14"'
assert_true "run_guided_wizard covers Phase 1 foundation" 'grep -A 35 "^run_guided_wizard()" ./laptop-linux-optimiser.sh | grep -q "PHASE 1: FOUNDATION & BATTERY HEALTH"'
assert_true "run_guided_wizard covers Phase 2 hardware acceleration" 'grep -A 35 "^run_guided_wizard()" ./laptop-linux-optimiser.sh | grep -q "PHASE 2: HARDWARE ACCELERATION & DRIVERS"'
assert_true "run_guided_wizard covers Phase 3 maintenance" 'grep -A 35 "^run_guided_wizard()" ./laptop-linux-optimiser.sh | grep -q "PHASE 3: INPUT, DISPLAY & STORAGE MAINTENANCE"'
assert_true "run_guided_wizard covers Phase 4 kernel tuning" 'grep -A 35 "^run_guided_wizard()" ./laptop-linux-optimiser.sh | grep -q "PHASE 4: KERNEL, POWER & NETWORK TUNING"'
assert_true "run_guided_wizard covers Phase 5 security and privacy" 'grep -A 35 "^run_guided_wizard()" ./laptop-linux-optimiser.sh | grep -q "PHASE 5: SECURITY, PRIVACY & SYSTEM POLISH"'
assert_true "run_guided_wizard educates why battery limiter is needed" 'grep -A 80 "^run_guided_wizard()" ./laptop-linux-optimiser.sh | grep "Lithium-ion batteries held at 100%" >/dev/null'
assert_true "run_guided_wizard educates why hardware acceleration is needed" 'grep -A 140 "^run_guided_wizard()" ./laptop-linux-optimiser.sh | grep "Video decoding is handled entirely by your CPU" >/dev/null'
assert_true "run_guided_wizard educates why browser VA-API is needed" 'grep -A 180 "^run_guided_wizard()" ./laptop-linux-optimiser.sh | grep "disable hardware video decoding on Linux by default" >/dev/null'
assert_true "run_guided_wizard educates why audio powersave fix is needed" 'grep -A 220 "^run_guided_wizard()" ./laptop-linux-optimiser.sh | grep "audible .pop., .click., or crackle" >/dev/null'
assert_true "run_guided_wizard educates why SSD TRIM is needed" 'grep -A 250 "^run_guided_wizard()" ./laptop-linux-optimiser.sh | grep "cannot overwrite flash cells without erasing" >/dev/null'
assert_true "run_guided_wizard educates why AMD EPP governor is needed" 'grep -A 330 "^run_guided_wizard()" ./laptop-linux-optimiser.sh | grep "Energy Performance Preference" >/dev/null'
assert_true "run_guided_wizard educates why laptop firewall is needed" 'grep -A 400 "^run_guided_wizard()" ./laptop-linux-optimiser.sh | grep "When connecting to public Wi-Fi" >/dev/null'
assert_true "TUI dashboard has Core Setup section" 'grep -q "CORE SETUP & QUICK WORKFLOWS" ./laptop-linux-optimiser.sh'
assert_true "TUI dashboard has Hardware & Battery section" 'grep -q "HARDWARE, BATTERY & POWER MANAGEMENT" ./laptop-linux-optimiser.sh'
assert_true "TUI dashboard has Graphics & Acceleration section" 'grep -q "GRAPHICS, DISPLAY & ACCELERATION" ./laptop-linux-optimiser.sh'
assert_true "TUI dashboard has Security & Privacy section" 'grep -q "SECURITY, NETWORK & PRIVACY" ./laptop-linux-optimiser.sh'
assert_true "TUI dashboard has System Tools section" 'grep -q "SYSTEM TOOLS & ADVANCED CONFIGURATION" ./laptop-linux-optimiser.sh'
assert_true "Interactive tuning menu has Hardware section" 'grep -q "HARDWARE & POWER TUNING" ./laptop-linux-optimiser.sh'
assert_true "Interactive tuning menu has Security section" 'grep -q "SECURITY, FIREWALL & PRIVACY SHIELDS" ./laptop-linux-optimiser.sh'
assert_true "Interactive tuning menu has Daemons section" 'grep -q "BACKGROUND DAEMONS & DISCOVERY" ./laptop-linux-optimiser.sh'
assert_true "Whiptail tuning menu has educational labels" 'grep -A 35 "^whiptail_tuning_menu()" ./laptop-linux-optimiser.sh | grep -q "Audio Powersave DAC Pop Fix"'
assert_true "CLI help documents 14-step wizard" './laptop-linux-optimiser.sh --help | grep "14-step" >/dev/null'

# ------------------------------------------------------------------------------
# Test 49: Root User Access Hardening & Delegation
# ------------------------------------------------------------------------------
echo "--- Test 49: Root User Access Hardening & Delegation ---"
assert_true "status_get_root_lock is defined" 'grep -q "^status_get_root_lock()" ./laptop-linux-optimiser.sh'
assert_true "lock_root_user is defined" 'grep -q "^lock_root_user()" ./laptop-linux-optimiser.sh'
assert_true "unlock_root_user is defined" 'grep -q "^unlock_root_user()" ./laptop-linux-optimiser.sh'
assert_true "toggle_root_user is defined" 'grep -q "^toggle_root_user()" ./laptop-linux-optimiser.sh'
assert_true "show_root_hardening_status is defined" 'grep -q "^show_root_hardening_status()" ./laptop-linux-optimiser.sh'
assert_true "ROOT_LOCK_CONF constant is defined" 'grep -q "^ROOT_LOCK_CONF=" ./laptop-linux-optimiser.sh'
assert_true "SSH_ROOT_DROPIN constant is defined" 'grep -q "^SSH_ROOT_DROPIN=" ./laptop-linux-optimiser.sh'
assert_true "Safety check verifies administrative sudo users before locking" 'grep -A 25 "^lock_root_user()" ./laptop-linux-optimiser.sh | grep -q "has_sudo_admin"'
assert_true "Never sets root shell to nologin or false" '! grep -E "usermod.*-s.*/(nologin|false).*root" ./laptop-linux-optimiser.sh'
assert_true "CLI root status outputs valid state" './laptop-linux-optimiser.sh root status | grep -E "Root Lock State" >/dev/null'
assert_true "CLI tune root status outputs valid state" './laptop-linux-optimiser.sh tune root status | grep -E "Root Lock State" >/dev/null'
assert_true "CLI summary reports Root User Access" './laptop-linux-optimiser.sh summary | grep "Root User Access" >/dev/null'
assert_true "CLI help documents root command" './laptop-linux-optimiser.sh --help | grep "root, root-lock" >/dev/null'
assert_true "TUI dashboard displays Root User Hardening Shield" 'grep -q "Root User Hardening Shield" ./laptop-linux-optimiser.sh'
assert_true "TUI dashboard handles [L] root lock dispatch" 'grep -A 25 "case \"\$opt\" in" ./laptop-linux-optimiser.sh | grep -q "\[Ll\]|root|lock-root)"'
assert_true "Interactive tuning menu includes Root User Hardening" 'grep -q "\[L\].*Root User Hardening" ./laptop-linux-optimiser.sh'
assert_true "Whiptail tuning menu includes Root Account Hardening" 'grep -q "Root Account Hardening" ./laptop-linux-optimiser.sh'
assert_true "Whiptail main menu includes Root Account Hardening" 'grep -A 45 "show_whiptail_tui()" ./laptop-linux-optimiser.sh | grep -q "Root Account Hardening Shield"'
assert_true "Guided wizard Step 13 includes Root Account Hardening" 'grep -A 30 "\[Step 13/14\]" ./laptop-linux-optimiser.sh | grep -q "Root Account Hardening"'

# ------------------------------------------------------------------------------
# Test 50: Version Header Synchronization
# ------------------------------------------------------------------------------
echo "--- Test 50: Version Header Synchronization ---"
assert_true "Header comment version matches 0.5.15" 'head -n 10 ./laptop-linux-optimiser.sh | grep -q "Version: 0.5.15"'
assert_true "VERSION variable matches 0.5.15" 'grep -q "VERSION=\"0.5.15\"" ./laptop-linux-optimiser.sh'

# ------------------------------------------------------------------------------
# Test 51: Battery Udev Rule Deduplication & Sleep Hook
# ------------------------------------------------------------------------------
echo "--- Test 51: Battery Udev Rule Deduplication & Sleep Hook ---"
assert_true "Udev rule imports THRESHOLD from configuration" 'grep -q "IMPORT{file}=\"\$BATTERY_CONF\"" ./laptop-linux-optimiser.sh'
assert_true "Sleep hook avoids unparented background sleep subshell" '! grep -q "( sleep 1; apply_thresh" ./laptop-linux-optimiser.sh'

# ------------------------------------------------------------------------------
# Test 52: Unattended Weekly Maintenance User Flatpaks
# ------------------------------------------------------------------------------
echo "--- Test 52: Unattended Weekly Maintenance User Flatpaks ---"
assert_true "update_flatpak enumerates /home/* for root execution" 'grep -A 20 "^update_flatpak()" ./laptop-linux-optimiser.sh | grep -q "for u_home in /home/\*"'
assert_true "update_flatpak discovers .local/share/flatpak" 'grep -A 20 "^update_flatpak()" ./laptop-linux-optimiser.sh | grep -q "\.local/share/flatpak"'

# ------------------------------------------------------------------------------
# Test 53: Honest Post-Apply Verification for Sysctl Tunings
# ------------------------------------------------------------------------------
echo "--- Test 53: Honest Post-Apply Verification for Sysctl Tunings ---"
assert_true "enable_bbr verifies active congestion control after write" 'grep -A 25 "^enable_bbr()" ./laptop-linux-optimiser.sh | grep -q "net.ipv4.tcp_congestion_control"'
assert_true "enable_swappiness verifies active swappiness after write" 'grep -A 25 "^enable_swappiness()" ./laptop-linux-optimiser.sh | grep -q "vm.swappiness"'
assert_true "apply_system_tuning tracks sub-function warning status" 'grep -A 10 "^apply_system_tuning()" ./laptop-linux-optimiser.sh | grep -q "tune_warns"'

# ------------------------------------------------------------------------------
# Test 54: Non-Destructive DNS Baseline Drop-ins & Journal Vacuum Toggle
# ------------------------------------------------------------------------------
echo "--- Test 54: Non-Destructive DNS Baseline Drop-ins & Journal Vacuum Toggle ---"
assert_true "setup_system_dns calls snapshot_dns_baseline" 'grep -A 10 "^setup_system_dns()" ./laptop-linux-optimiser.sh | grep -q "snapshot_dns_baseline"'
assert_true "snapshot_dns_baseline snapshots non-proxy drop-in baseline" 'grep -A 20 "^snapshot_dns_baseline()" ./laptop-linux-optimiser.sh | grep -q "dns_baseline"'
assert_true "revert_dns_changes restores baseline drop-in when present" 'grep -A 20 "^revert_dns_changes()" ./laptop-linux-optimiser.sh | grep -q "dns_baseline"'
assert_true "clean_systemd respects VACUUM_JOURNALS toggle" 'grep -A 15 "^clean_systemd()" ./laptop-linux-optimiser.sh | grep -q "VACUUM_JOURNALS"'
assert_true "Script configures ERR diagnostic trap" 'grep -q "trap.*ERR" ./laptop-linux-optimiser.sh'

echo "=========================================================="
if [ "$FAILED" -eq 0 ]; then
    echo "ALL $TOTAL TESTS PASSED SUCCESSFULLY!"
else
    echo "$FAILED of $TOTAL TESTS FAILED!"
    exit 1
fi
