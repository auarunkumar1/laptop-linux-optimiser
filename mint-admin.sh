#!/usr/bin/env bash
# ==============================================================================
# Laptop Linux Optimizer & Master Administration Suite (mint-admin)
# Version: 0.3.0
#
# Unified Laptop Optimization & Hardening Tool:
#   1. Battery Diagnostics & Persistent Charge Limiter (ASUS & Generic BAT*)
#   2. Encrypted DNS Manager (dnscrypt-proxy: DoH / Anonymized Relays / Tor)
#   3. System Optimizer & Housekeeping (APT, Flatpak, Journals, Temp caches)
#   4. Full Package Updates & Orphan/Cache Sweeper
#   5. Privacy & Anti-Tracking Scrub (Browsers, Activity, DNS logs, Thumbnails)
#   6. MAC Address Randomization & Hardware Spoofing (On-demand & Persistent)
#   7. Kernel & Performance Tuning (TCP BBR, ZRAM 50% with Swappiness 100)
#   8. Automated Background Maintenance Timers (systemd weekly timer)
# ==============================================================================

set -euo pipefail

VERSION="0.3.0"
SCRIPT_PATH="$(realpath "$0")"

# Colors & Formatting
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
CYAN='\e[36m'
MAGENTA='\e[35m'
BOLD='\e[1m'
DIM='\e[2m'
NC='\e[0m'

# File & Configuration Paths
BATTERY_CONF="/etc/asus-battery-limit.conf"
BATTERY_SERVICE="/etc/systemd/system/asus-battery-limit.service"
BATTERY_SLEEP_HOOK="/usr/lib/systemd/system-sleep/asus-battery-limit.sh"
[ ! -d "/usr/lib/systemd/system-sleep" ] && [ -d "/lib/systemd/system-sleep" ] && BATTERY_SLEEP_HOOK="/lib/systemd/system-sleep/asus-battery-limit.sh"
BATTERY_UDEV_RULE="/etc/udev/rules.d/99-asus-battery-charge-limit.rules"

DNS_CONFIG="/etc/dnscrypt-proxy/dnscrypt-proxy.toml"
DNS_BACKUP="/etc/dnscrypt-proxy/dnscrypt-proxy.toml.orig"
NM_DNS_DROPIN="/etc/NetworkManager/conf.d/00-dnscrypt.conf"
RESOLVED_DNS_DROPIN="/etc/systemd/resolved.conf.d/dnscrypt.conf"

NM_MAC_CONF="/etc/NetworkManager/conf.d/00-macrandomize.conf"

OPTIMIZER_SERVICE="/etc/systemd/system/mint-optimizer.service"
OPTIMIZER_TIMER="/etc/systemd/system/mint-optimizer.timer"

PERF_SYSCTL="/etc/sysctl.d/99-mint-admin-performance.conf"
PRIVACY_SYSCTL="/etc/sysctl.d/99-mint-admin-privacy.conf"
BBR_MODULE_CONF="/etc/modules-load.d/bbr.conf"
DHCP_PRIVACY_CONF="/etc/NetworkManager/conf.d/01-privacy-dhcp.conf"
ZRAM_CONF="/etc/default/zramswap"
IPV6_SYSCTL_CONF="/etc/sysctl.d/99-disable-ipv6.conf"
BASELINE_SYSCTL="/var/lib/mint-admin/tuning-baseline.env"
PROFILE_CONF="/etc/mint-admin-profile.conf"
CANONICAL_BIN="/usr/local/sbin/mint-admin"
LOCK_FILE="/var/run/mint-admin.lock"

# ------------------------------------------------------------------------------
# Helper Utilities
# ------------------------------------------------------------------------------

log_info()    { echo -e "${BLUE}[*]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
log_err()     { echo -e "${RED}[✗]${NC} $1"; }

check_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo -e "${RED}[-] Error: This operation requires root privileges.${NC}" >&2
        echo -e "${YELLOW}[-] Please run with sudo: sudo \"$0\" ${*:-}${NC}" >&2
        exit 1
    fi
    acquire_lock
}

acquire_lock() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        mkdir -p /var/run
        exec 200>"$LOCK_FILE"
        if ! flock -n 200; then
            log_err "Another instance of mint-admin is currently running."
            exit 1
        fi
    fi
}

is_safe_user_path() {
    local user_home="$1"
    local target="$2"

    [ -d "$user_home" ] || return 1
    [ -L "$user_home" ] && return 1

    local real_h
    real_h=$(realpath -q "$user_home") || return 1
    [[ "$real_h" == "/home/"* || "$real_h" == "/root" ]] || return 1

    local real_target
    real_target=$(realpath -mq "$target") || return 1
    [[ "$real_target" == "$real_h"/* ]] || return 1

    # Ensure no existing intermediate path component is a symlink
    local cur="$user_home"
    local rel="${target#$user_home/}"
    local part
    IFS='/' read -ra parts <<< "$rel"
    for part in "${parts[@]}"; do
        [ -z "$part" ] && continue
        cur="$cur/$part"
        if [ -L "$cur" ]; then
            return 1
        fi
    done

    return 0
}

format_kb() {
    local kb="${1:-0}"
    [[ "$kb" =~ ^-?[0-9]+$ ]] || kb=0
    if [ "$kb" -lt 0 ]; then
        echo "0 MB"
    elif [ "$kb" -ge 1048576 ]; then
        echo "$(( kb / 1048576 )) GB ($(( (kb % 1048576) / 1024 )) MB)"
    else
        echo "$(( kb / 1024 )) MB"
    fi
}

print_summary() {
    local avail_before="${1:-0}"
    [[ "$avail_before" =~ ^[0-9]+$ ]] || avail_before=0
    local avail_after
    avail_after=$(df -k / 2>/dev/null | awk 'END {print $4}')
    [[ "$avail_after" =~ ^[0-9]+$ ]] || avail_after=0
    local diff=$(( avail_after - avail_before ))

    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}                 Operation Summary${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo "Initial Free Space : $(format_kb "$avail_before")"
    echo "Current Free Space : $(format_kb "$avail_after")"
    if [ "$diff" -gt 0 ]; then
        echo -e "Space Reclaimed    : ${GREEN}+$(format_kb "$diff")${NC}"
    elif [ "$diff" -lt 0 ]; then
        echo -e "Net Space Used     : ${YELLOW}$(format_kb "$(( -diff ))")${NC} (new package data)"
    else
        echo "Space Reclaimed    : System was already lean and clean!"
    fi
    echo -e "${CYAN}========================================================${NC}"
}

# ==============================================================================
# MODULE 1: Battery Management & Charge Limiting
# ==============================================================================

find_battery_threshold_nodes() {
    local was_nullglob=0
    shopt -q nullglob && was_nullglob=1
    shopt -s nullglob
    local nodes=(/sys/class/power_supply/BAT*/charge_control_end_threshold)
    [ "$was_nullglob" -eq 0 ] && shopt -u nullglob
    for n in "${nodes[@]}"; do
        [ -f "$n" ] && printf '%s\n' "$n"
    done
}

show_battery_status() {
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}            Battery Diagnostics & Health Report${NC}"
    echo -e "${CYAN}========================================================${NC}"

    local found=0
    for bat in /sys/class/power_supply/BAT*; do
        [ -d "$bat" ] || continue
        found=1
        local name
        name=$(basename "$bat")

        echo -e "${BOLD}Battery Device :${NC} $name"
        [ -f "$bat/manufacturer" ] && echo "  - Manufacturer   : $(cat "$bat/manufacturer")"
        [ -f "$bat/model_name" ]   && echo "  - Model Name     : $(cat "$bat/model_name")"
        [ -f "$bat/status" ]       && echo "  - Charging State : $(cat "$bat/status")"
        [ -f "$bat/capacity" ]     && echo "  - Current Level  : $(cat "$bat/capacity")%"

        # Cycle Count
        if [ -f "$bat/cycle_count" ] && [ -s "$bat/cycle_count" ]; then
            local cycles
            cycles=$(cat "$bat/cycle_count")
            if [ "$cycles" -eq 0 ] 2>/dev/null; then
                echo "  - Cycle Count    : 0 (or not reported by hardware)"
            else
                echo "  - Cycle Count    : $cycles cycles"
            fi
        else
            echo "  - Cycle Count    : Not reported by hardware"
        fi

        # Charge limit threshold
        if [ -f "$bat/charge_control_end_threshold" ]; then
            local thresh
            thresh=$(cat "$bat/charge_control_end_threshold")
            echo -e "  - Charge Limit   : ${BOLD}${thresh}%${NC}"
        else
            echo "  - Charge Limit   : Not supported or fixed at 100%"
        fi

        # Health Calculation
        local full=0 design=0 is_energy=0
        if [ -f "$bat/energy_full" ] && [ -f "$bat/energy_full_design" ]; then
            full=$(cat "$bat/energy_full" 2>/dev/null || echo 0)
            design=$(cat "$bat/energy_full_design" 2>/dev/null || echo 0)
            is_energy=1
        elif [ -f "$bat/charge_full" ] && [ -f "$bat/charge_full_design" ]; then
            full=$(cat "$bat/charge_full" 2>/dev/null || echo 0)
            design=$(cat "$bat/charge_full_design" 2>/dev/null || echo 0)
            is_energy=0
        fi

        if [ "$design" -gt 0 ] 2>/dev/null; then
            local health full_cap design_cap
            health=$(awk "BEGIN {printf \"%.1f\", ($full / $design) * 100}")
            if [ "$is_energy" -eq 1 ]; then
                full_cap=$(awk "BEGIN {printf \"%.1f Wh\", $full / 1000000}")
                design_cap=$(awk "BEGIN {printf \"%.1f Wh\", $design / 1000000}")
            else
                local volts=0
                [ -f "$bat/voltage_min_design" ] && volts=$(cat "$bat/voltage_min_design" 2>/dev/null || echo 0)
                [ "$volts" -eq 0 ] 2>/dev/null && [ -f "$bat/voltage_now" ] && volts=$(cat "$bat/voltage_now" 2>/dev/null || echo 0)
                if [ "$volts" -gt 0 ] 2>/dev/null; then
                    full_cap=$(awk "BEGIN {printf \"%.1f Wh\", ($full * $volts) / 1000000000000}")
                    design_cap=$(awk "BEGIN {printf \"%.1f Wh\", ($design * $volts) / 1000000000000}")
                else
                    full_cap=$(awk "BEGIN {printf \"%.0f mAh\", $full / 1000}")
                    design_cap=$(awk "BEGIN {printf \"%.0f mAh\", $design / 1000}")
                fi
            fi
            echo -e "  - Battery Health : ${GREEN}${health}%${NC} ($full_cap / $design_cap)"
        fi
        echo "--------------------------------------------------------"
    done

    if [ "$found" -eq 0 ]; then
        log_warn "No battery found under /sys/class/power_supply/"
    fi

    # Daemon and conflict checks
    if systemctl is-active --quiet tlp.service 2>/dev/null; then
        echo -e "Power Daemon     : ${YELLOW}TLP ACTIVE${NC} (Check /etc/tlp.conf for threshold overrides)"
    elif systemctl is-active --quiet power-profiles-daemon.service 2>/dev/null; then
        echo -e "Power Daemon     : power-profiles-daemon (active)"
    elif systemctl is-active --quiet upower.service 2>/dev/null; then
        echo -e "Power Daemon     : upower (active)"
    fi

    # Persistence check
    if [ -f "$BATTERY_SERVICE" ] && systemctl is-enabled --quiet asus-battery-limit.service 2>/dev/null; then
        echo -e "Persistence      : ${GREEN}ENABLED${NC} (active across reboots, sleep & AC events)"
        [ -f "$BATTERY_CONF" ] && echo "Saved Setting    : $(cat "$BATTERY_CONF")"
        [ -f "$BATTERY_UDEV_RULE" ] && echo "AC / BAT Watcher : udev rule active (prevents AC & device resets)"
        [ -f "$BATTERY_SLEEP_HOOK" ] && echo "Sleep/Wake Watch : system-sleep hook active (prevents resume reset)"
    else
        echo -e "Persistence      : ${YELLOW}DISABLED${NC} (hardware threshold resets to 100% on reboot)"
        echo "                   (Run 'sudo $0 battery install <limit>' to persist)"
    fi
    echo -e "${CYAN}========================================================${NC}"
}

set_battery_threshold() {
    local val="$1"
    if ! [[ "$val" =~ ^[0-9]+$ ]] || [ "$val" -lt 20 ] || [ "$val" -gt 100 ]; then
        log_err "Invalid threshold: '$val'. Must be an integer between 20 and 100."
        echo "    Recommended: 60 (AC desk use), 80 (balanced lifespan), 100 (travel/maximum runtime)"
        exit 1
    fi

    check_root "battery" "set" "$val"

    local found_any=0
    while IFS= read -r node; do
        if [ -n "$node" ] && [ -f "$node" ]; then
            echo "$val" > "$node"
            found_any=1
        fi
    done < <(find_battery_threshold_nodes)

    if [ "$found_any" -eq 0 ]; then
        log_err "No supported battery threshold interface found in /sys/class/power_supply/"
        exit 1
    fi

    echo "THRESHOLD=$val" > "$BATTERY_CONF"
    chmod 644 "$BATTERY_CONF"

    # Synchronize persistent service and udev rule if already installed
    if [ -f "$BATTERY_UDEV_RULE" ]; then
        cat << EOF > "$BATTERY_UDEV_RULE"
# 1. Direct sysfs attribute assignment via udev on battery add/change
SUBSYSTEM=="power_supply", KERNEL=="BAT[0-9]*", ATTR{charge_control_end_threshold}="$val"
SUBSYSTEM=="power_supply", KERNEL=="BAT[0-9]*", TEST=="charge_control_end_threshold", IMPORT{file}="/etc/asus-battery-limit.conf", ATTR{charge_control_end_threshold}="\$env{THRESHOLD}"

# 2. Re-trigger persistence service on AC power state change (Mains)
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ACTION=="change", RUN+="/usr/bin/systemctl --no-block restart asus-battery-limit.service"
EOF
        udevadm control --reload-rules 2>/dev/null || true
    fi

    if [ -f "$BATTERY_SERVICE" ]; then
        systemctl restart asus-battery-limit.service 2>/dev/null || true
    fi

    log_success "Battery charge threshold set to ${val}%."
    if [ "$val" -eq 80 ]; then
        echo "  [Mode: Balanced] Excellent for everyday use and extends battery longevity."
    elif [ "$val" -eq 60 ]; then
        echo "  [Mode: Maximum Lifespan] Best if laptop is plugged into charger constantly."
    elif [ "$val" -eq 100 ]; then
        echo "  [Mode: Full Capacity] Recommended when traveling or needing maximum battery life."
    fi

    if [ ! -f "$BATTERY_SERVICE" ]; then
        echo ""
        log_warn "To make this ${val}% limit persist across reboots & sleep, run:"
        echo "    sudo $0 battery install $val"
    fi
}

install_battery_service() {
    local val="${1:-80}"
    if ! [[ "$val" =~ ^[0-9]+$ ]] || [ "$val" -lt 20 ] || [ "$val" -gt 100 ]; then
        log_err "Invalid threshold: '$val'. Must be an integer between 20 and 100."
        exit 1
    fi

    check_root "battery" "install" "$val"

    log_info "Configuring persistent battery charge limiter (target: ${val}%)..."

    echo "THRESHOLD=$val" > "$BATTERY_CONF"
    chmod 644 "$BATTERY_CONF"

    # 1. Systemd Service (Triggers on boot, resume from suspend, hibernate, and hybrid-sleep)
    cat << 'EOF' > "$BATTERY_SERVICE"
[Unit]
Description=ASUS Battery Charge Limit Persister
DefaultDependencies=no
After=local-fs.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'if [ -f /etc/asus-battery-limit.conf ]; then . /etc/asus-battery-limit.conf; else THRESHOLD=80; fi; for bat in /sys/class/power_supply/BAT*/charge_control_end_threshold; do [ -f "$bat" ] && [ "$(cat "$bat" 2>/dev/null)" != "$THRESHOLD" ] && echo "$THRESHOLD" > "$bat" 2>/dev/null || true; done'
RemainAfterExit=no

[Install]
WantedBy=multi-user.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
EOF
    chmod 644 "$BATTERY_SERVICE"

    # 2. System Sleep Hook (Runs immediately upon wake + delayed background check to counter delayed EC firmware resets)
    local sleep_dir
    sleep_dir="$(dirname "$BATTERY_SLEEP_HOOK")"
    if [ -d "$sleep_dir" ] || mkdir -p "$sleep_dir" 2>/dev/null; then
        cat << 'EOF' > "$BATTERY_SLEEP_HOOK"
#!/bin/sh
case "$1" in
    post)
        apply_thresh() {
            if [ -f /etc/asus-battery-limit.conf ]; then
                . /etc/asus-battery-limit.conf
            else
                THRESHOLD=80
            fi
            for bat in /sys/class/power_supply/BAT*/charge_control_end_threshold; do
                if [ -f "$bat" ]; then
                    [ "$(cat "$bat" 2>/dev/null)" != "$THRESHOLD" ] && echo "$THRESHOLD" > "$bat" 2>/dev/null || true
                fi
            done
        }
        apply_thresh
        ( sleep 1; apply_thresh; sleep 2; apply_thresh ) >/dev/null 2>&1 &
        ;;
esac
EOF
        chmod +x "$BATTERY_SLEEP_HOOK"
    fi

    # 3. Write udev rule (direct attribute assignment on battery add/change, and AC plug watcher)
    if [ -d "/etc/udev/rules.d" ]; then
        cat << EOF > "$BATTERY_UDEV_RULE"
# 1. Direct sysfs attribute assignment via udev on battery add/change
SUBSYSTEM=="power_supply", KERNEL=="BAT[0-9]*", ATTR{charge_control_end_threshold}="$val"
SUBSYSTEM=="power_supply", KERNEL=="BAT[0-9]*", TEST=="charge_control_end_threshold", IMPORT{file}="/etc/asus-battery-limit.conf", ATTR{charge_control_end_threshold}="\$env{THRESHOLD}"

# 2. Re-trigger persistence service on AC power state change (Mains)
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ACTION=="change", RUN+="/usr/bin/systemctl --no-block restart asus-battery-limit.service"
EOF
        udevadm control --reload-rules 2>/dev/null || true
    fi

    systemctl daemon-reload
    systemctl enable asus-battery-limit.service
    systemctl restart asus-battery-limit.service

    set_battery_threshold "$val"
    log_success "Persistent battery limiter active across reboots, sleep/wake, and AC plug events!"
}

uninstall_battery_service() {
    check_root "battery" "uninstall"

    log_info "Removing persistent battery charge limiter..."
    systemctl stop asus-battery-limit.service 2>/dev/null || true
    systemctl disable asus-battery-limit.service 2>/dev/null || true
    rm -f "$BATTERY_SERVICE" "$BATTERY_CONF" "$BATTERY_UDEV_RULE"
    rm -f /usr/lib/systemd/system-sleep/asus-battery-limit.sh /lib/systemd/system-sleep/asus-battery-limit.sh
    udevadm control --reload-rules 2>/dev/null || true
    systemctl daemon-reload

    while IFS= read -r node; do
        [ -n "$node" ] && [ -f "$node" ] && echo "100" > "$node" 2>/dev/null || true
    done < <(find_battery_threshold_nodes)
    log_success "Battery limiter uninstalled. Charge threshold restored to 100%."
}

# ==============================================================================
# MODULE 2: Encrypted DNS Manager (DoH / ODoH / Tor)
# ==============================================================================

check_dns_dependencies() {
    log_info "Verifying DNS dependencies..."
    if ! command -v dnscrypt-proxy &>/dev/null || ! command -v dig &>/dev/null; then
        apt-get update && apt-get install -y dnscrypt-proxy dnsutils
        log_success "dnscrypt-proxy & dnsutils installed."
    fi

    if [[ -f "$DNS_CONFIG" && ! -f "$DNS_BACKUP" ]]; then
        cp "$DNS_CONFIG" "$DNS_BACKUP"
        log_info "Original configuration backed up to $DNS_BACKUP"
    fi
}

get_active_relays() {
    local relays=()
    if [ -f "/var/cache/dnscrypt-proxy/relays.md" ]; then
        mapfile -t relays < <(grep -E '^## anon-cs-[a-z]+$' /var/cache/dnscrypt-proxy/relays.md | sed 's/^## //' | head -n 3)
    fi
    if [ ${#relays[@]} -eq 0 ]; then
        relays=('anon-cs-de' 'anon-cs-berlin' 'anon-cs-austria')
    fi
    local formatted=""
    for r in "${relays[@]}"; do
        [ -n "$formatted" ] && formatted="$formatted, "
        formatted="$formatted'$r'"
    done
    echo "[$formatted]"
}

check_tor_service() {
    log_info "Checking Tor service..."
    if ! command -v tor &>/dev/null; then
        if [ "${FORCE_YES:-0}" -ne 1 ] && [ -t 0 ]; then
            read -r -p "Tor is not installed. Install Tor package now? [y/N]: " tor_ans
            [[ "$tor_ans" =~ ^[Yy]$ ]] || { log_err "Tor installation declined."; return 1; }
        fi
        apt-get update && apt-get install -y tor
    fi
    systemctl enable --now tor
    if ! systemctl is-active --quiet tor; then
        log_err "Tor service failed to start or activate."
        return 1
    fi
    log_success "Tor is active on 127.0.0.1:9050."
}

apply_dnscrypt_config() {
    local servers="$1"
    local use_anonymized="$2"
    local use_tor="$3"

    log_info "Applying settings to $DNS_CONFIG..."

    # Pre-modification backup snapshot
    cp "$DNS_CONFIG" "${DNS_CONFIG}.bak"

    sed -i "s/^listen_addresses = .*/listen_addresses = []/" "$DNS_CONFIG"
    if grep -q "^server_names =" "$DNS_CONFIG"; then
        sed -i "s/^server_names = .*/server_names = $servers/" "$DNS_CONFIG"
    else
        sed -i "/^listen_addresses =/a server_names = $servers" "$DNS_CONFIG"
    fi

    # Always strip existing proxy and force_tcp settings before re-applying
    sed -i '/^[[:space:]]*proxy[[:space:]]*=/d; /^[[:space:]]*force_tcp[[:space:]]*=/d' "$DNS_CONFIG"

    if [[ "$use_tor" == "true" ]]; then
        log_info "Routing DNS queries through Tor Onion proxy (127.0.2.1 -> 127.0.0.1:9050)..."
        check_tor_service || { log_err "Tor service is required but unavailable."; cp "${DNS_CONFIG}.bak" "$DNS_CONFIG"; return 1; }
        sed -i "/^server_names =/a proxy = 'socks5://127.0.0.1:9050'\nforce_tcp = true" "$DNS_CONFIG"
        if ! grep -q "^proxy = 'socks5://127.0.0.1:9050'" "$DNS_CONFIG"; then
            log_err "Failed to inject Tor proxy configuration into $DNS_CONFIG."
            cp "${DNS_CONFIG}.bak" "$DNS_CONFIG"
            return 1
        fi
    fi

    if [[ "$use_anonymized" == "true" ]]; then
        log_info "Setting up Anonymized DNS relay routes..."
        if ! grep -q "sources.'relays'" "$DNS_CONFIG"; then
            cat << 'EOF' >> "$DNS_CONFIG"

[sources.'relays']
  url = 'https://download.dnscrypt.info/resolvers-list/v3/relays.md'
  cache_file = '/var/cache/dnscrypt-proxy/relays.md'
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  refresh_delay = 72
  prefix = ''
EOF
        else
            sed -i 's|/resolvers-list/v2/relays.md|/resolvers-list/v3/relays.md|' "$DNS_CONFIG"
        fi

        local active_relays
        active_relays=$(get_active_relays)
        sed -i '/^\[anonymized_dns\]/,/^\[/ { /^routes =/d }' "$DNS_CONFIG"
        if ! grep -q "^\[anonymized_dns\]" "$DNS_CONFIG"; then
            echo -e "\n[anonymized_dns]" >> "$DNS_CONFIG"
        fi
        sed -i "/^\[anonymized_dns\]/a routes = [{ server_name='*', via=$active_relays }]" "$DNS_CONFIG"
    else
        sed -i '/^routes = \[{ server_name='\''\*'\''/d' "$DNS_CONFIG"
    fi

    if ! dnscrypt-proxy -config "$DNS_CONFIG" -check &>/dev/null; then
        log_err "Configuration syntax test failed! Reverting $DNS_CONFIG..."
        cp "${DNS_CONFIG}.bak" "$DNS_CONFIG"
        return 1
    fi
    log_success "dnscrypt-proxy configuration syntax verified."
}

setup_system_dns() {
    log_info "Configuring system DNS drop-ins for 127.0.2.1..."

    mkdir -p /etc/NetworkManager/conf.d
    cat <<EOF > "$NM_DNS_DROPIN"
[global-dns]
searches=

[global-dns-domain-*]
servers=127.0.2.1
EOF

    if systemctl is-active systemd-resolved &>/dev/null; then
        mkdir -p /etc/systemd/resolved.conf.d
        cat <<EOF > "$RESOLVED_DNS_DROPIN"
[Resolve]
DNS=127.0.2.1
Domains=~.
FallbackDNS=
DNSSEC=no
ResolveUnicastSingleLabel=yes
EOF
    fi
    log_success "System DNS directed to local proxy (127.0.2.1)."
}

activate_dns_config() {
    local profile_desc="$1"
    if ! setup_system_dns; then
        log_err "Failed to configure system DNS drop-ins."
        return 1
    fi
    if ! restart_dns_services; then
        log_err "Failed to restart DNS services or verify resolution."
        return 1
    fi
    log_success "$profile_desc active."
}

restart_dns_services() {
    log_info "Restarting network and DNS services..."
    systemctl reset-failed dnscrypt-proxy.service 2>/dev/null || true
    systemctl unmask dnscrypt-proxy.service 2>/dev/null || true
    if systemctl list-unit-files dnscrypt-proxy.socket &>/dev/null; then
        systemctl reset-failed dnscrypt-proxy.socket 2>/dev/null || true
        systemctl unmask dnscrypt-proxy.socket 2>/dev/null || true
        systemctl enable dnscrypt-proxy.socket 2>/dev/null || true
        systemctl restart dnscrypt-proxy.socket 2>/dev/null || true
    fi
    systemctl enable dnscrypt-proxy.service 2>/dev/null || true
    systemctl restart dnscrypt-proxy.service

    if systemctl is-active systemd-resolved &>/dev/null; then
        systemctl restart systemd-resolved
    fi
    nmcli general reload 2>/dev/null || systemctl reload NetworkManager 2>/dev/null || systemctl restart NetworkManager 2>/dev/null

    log_info "Testing DNS resolution (waiting 3s)..."
    sleep 3

    local proxy_ip=""
    proxy_ip=$(dig @127.0.2.1 example.com +short 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
    if [ -n "$proxy_ip" ]; then
        log_success "Direct proxy resolution verified via 127.0.2.1 (example.com -> $proxy_ip)."
    else
        log_warn "Direct proxy query to 127.0.2.1 returned no valid A record yet."
    fi

    local sys_ip=""
    sys_ip=$(getent ahostsv4 example.com 2>/dev/null | awk '{print $1}' | head -n1 || true)
    if [ -n "$sys_ip" ]; then
        log_success "System-wide DNS resolution verified active (example.com -> $sys_ip)!"
    else
        sleep 2
        sys_ip=$(getent ahostsv4 example.com 2>/dev/null | awk '{print $1}' | head -n1 || true)
        if [ -n "$sys_ip" ]; then
            log_success "System-wide DNS resolution verified active (example.com -> $sys_ip)!"
        else
            log_warn "System resolver still settling or failing to resolve example.com."
        fi
    fi
}

revert_dns_changes() {
    check_root "dns" "revert"

    log_warn "Reverting to default system DHCP / NetworkManager DNS..."
    rm -f "$NM_DNS_DROPIN" "$RESOLVED_DNS_DROPIN"

    if [[ -f "$DNS_BACKUP" ]]; then
        cp "$DNS_BACKUP" "$DNS_CONFIG"
        log_info "Restored default $DNS_CONFIG"
    fi

    systemctl reset-failed dnscrypt-proxy.service dnscrypt-proxy.socket 2>/dev/null || true
    systemctl stop dnscrypt-proxy.service dnscrypt-proxy.socket 2>/dev/null || true
    systemctl disable dnscrypt-proxy.service dnscrypt-proxy.socket 2>/dev/null || true

    if systemctl is-active systemd-resolved &>/dev/null; then
        systemctl restart systemd-resolved
    fi
    nmcli general reload 2>/dev/null || systemctl reload NetworkManager 2>/dev/null || systemctl restart NetworkManager 2>/dev/null

    log_success "System restored to default DHCP DNS."
}

show_dns_status() {
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}               Encrypted DNS Status${NC}"
    echo -e "${CYAN}========================================================${NC}"

    if systemctl is-active --quiet dnscrypt-proxy.service 2>/dev/null; then
        echo -e "dnscrypt-proxy   : ${GREEN}ACTIVE & RUNNING${NC}"
        if [ -f "$DNS_CONFIG" ]; then
            local current_servers
            current_servers=$(grep -E '^server_names =' "$DNS_CONFIG" | cut -d= -f2- | tr -d ' ' || echo "Default")
            echo "Active Resolvers : $current_servers"
            if awk '/^\[/{exit} /proxy =/{found=1} END{exit !found}' "$DNS_CONFIG" 2>/dev/null; then
                echo -e "Tor Routing      : ${GREEN}ENABLED${NC}"
            else
                echo "Tor Routing      : DISABLED"
            fi
            if grep -q "routes = \[{ server_name='\*'" "$DNS_CONFIG" 2>/dev/null; then
                echo -e "Anonymized Relays: ${GREEN}ENABLED${NC}"
            else
                echo "Anonymized Relays: DISABLED"
            fi
        fi
    else
        echo -e "dnscrypt-proxy   : ${YELLOW}INACTIVE / DISABLED${NC} (System using standard DHCP DNS)"
    fi

    echo ""
    echo "Active System Resolvers:"
    if command -v resolvectl &>/dev/null; then
        resolvectl dns 2>/dev/null || true
    elif [ -f /etc/resolv.conf ]; then
        grep "nameserver" /etc/resolv.conf
    fi
    echo -e "${CYAN}========================================================${NC}"
}

apply_dns_profile() {
    local opt="$1"
    check_root "dns" "apply" "$opt"
    check_dns_dependencies

    case "$opt" in
        0|failover)
            apply_dnscrypt_config "['quad9-doh-ip4-port443-filter-pri', 'cloudflare', 'adguard-dns-doh']" "false" "false" && \
            activate_dns_config "Auto-Failover Pool (Quad9 + Cloudflare + AdGuard)"
            ;;
        1|cloudflare)
            apply_dnscrypt_config "['cloudflare', 'cloudflare-ipv6']" "false" "false" && \
            activate_dns_config "Cloudflare Anycast DoH"
            ;;
        2|google)
            apply_dnscrypt_config "['google', 'google-ipv6']" "false" "false" && \
            activate_dns_config "Google Public DNS"
            ;;
        3|quad9)
            apply_dnscrypt_config "['quad9-doh-ip4-port443-filter-pri', 'quad9-doh-ip6-port443-filter-pri']" "false" "false" && \
            activate_dns_config "Quad9 DoH (Swiss malware filter)"
            ;;
        4|adguard)
            apply_dnscrypt_config "['adguard-dns-doh', 'adguard-dns-doh-ipv6']" "false" "false" && \
            activate_dns_config "AdGuard Adblock DoH"
            ;;
        5|controld)
            apply_dnscrypt_config "['controld-block-malware-ad']" "false" "false" && \
            activate_dns_config "Control D Adblock DoH"
            ;;
        6|libredns)
            apply_dnscrypt_config "['libredns']" "false" "false" && \
            activate_dns_config "LibreDNS Standard"
            ;;
        7|libredns-adblock)
            apply_dnscrypt_config "['libredns-noads']" "false" "false" && \
            activate_dns_config "LibreDNS with Adblock"
            ;;
        8|cloudflare-odoh)
            apply_dnscrypt_config "['cloudflare']" "true" "false" && \
            activate_dns_config "Cloudflare via ODoH (Anonymized Relays)"
            ;;
        9|quad9-odoh)
            apply_dnscrypt_config "['quad9-doh-ip4-port443-filter-pri']" "true" "false" && \
            activate_dns_config "Quad9 via ODoH"
            ;;
        10|libredns-odoh)
            apply_dnscrypt_config "['libredns-noads']" "true" "false" && \
            activate_dns_config "LibreDNS via ODoH"
            ;;
        11|quad9-tor)
            check_tor_service && \
            apply_dnscrypt_config "['quad9-doh-ip4-port443-filter-pri']" "false" "true" && \
            activate_dns_config "Quad9 via Tor Onion routing"
            ;;
        12|libredns-tor)
            check_tor_service && \
            apply_dnscrypt_config "['libredns-noads']" "false" "true" && \
            activate_dns_config "LibreDNS Adblock via Tor"
            ;;
        13|cloudflare-tor)
            check_tor_service && \
            apply_dnscrypt_config "['cloudflare']" "false" "true" && \
            activate_dns_config "Cloudflare via Tor"
            ;;
        14|revert|dhcp)
            revert_dns_changes
            ;;
        *)
            log_err "Invalid DNS profile selection: '$opt'"
            exit 1
            ;;
    esac
}

interactive_dns_menu() {
    check_root "dns" "menu"
    clear 2>/dev/null || true
    echo -e "${CYAN}==========================================================================================${NC}"
    echo -e "${BOLD}              Laptop Linux Optimizer — Encrypted DNS Profile Manager                      ${NC}"
    echo -e "${CYAN}==========================================================================================${NC}"

    # Display current active resolver status at a glance
    if systemctl is-active dnscrypt-proxy.service &>/dev/null; then
        local cur_res="Default"
        [ -f "$DNS_CONFIG" ] && cur_res=$(grep -E '^server_names =' "$DNS_CONFIG" | cut -d= -f2- | tr -d " '" || echo "Default")
        echo -e "Current Active DNS : ${GREEN}ENCRYPTED (dnscrypt-proxy active: $cur_res)${NC}"
    else
        echo -e "Current Active DNS : ${YELLOW}Standard Unencrypted DHCP / NetworkManager DNS${NC}"
    fi
    echo ""

    echo -e "${CYAN}-- High Availability & Redundancy (Recommended for daily use) --${NC}"
    echo -e "  0) ${BOLD}Auto-Failover Pool (Recommended)${NC} | Quad9 + Cloudflare + AdGuard. Auto-switches during outages"
    echo ""
    echo -e "${CYAN}-- High-Speed Anycast (DoH) --${NC}"
    echo -e "  1) ${BOLD}Cloudflare Anycast${NC}               | Ultra-low latency (1.1.1.1); no client IP logging"
    echo -e "  2) ${BOLD}Google Public DNS${NC}                | Global capacity, near-100% infrastructure uptime"
    echo -e "  3) ${BOLD}Quad9 Swiss DNS${NC}                  | Swiss jurisdiction, strict privacy + real-time malware blocking"
    echo ""
    echo -e "${CYAN}-- Ad, Tracker & Malware Blocking (Privacy-First DoH) --${NC}"
    echo -e "  4) ${BOLD}AdGuard DNS${NC}                      | Dedicated DNS-level blocking of ads, web trackers & phishing"
    echo -e "  5) ${BOLD}Control D${NC}                        | Lightweight ad, tracker, and telemetry domain blocking"
    echo -e "  6) ${BOLD}LibreDNS Standard${NC}                | Community non-profit (zero logs, open-source)"
    echo -e "  7) ${BOLD}LibreDNS with Adblock${NC}            | Community non-profit with built-in ad & tracking blocker"
    echo ""
    echo -e "${CYAN}-- Anonymized Multi-Hop DNS Relays (Hides your home IP from the resolver) --${NC}"
    echo -e "  8) ${BOLD}Cloudflare via Multi-Hop Relay${NC}   | Fast resolution routed through independent relays"
    echo -e "  9) ${BOLD}Quad9 via Multi-Hop Relay${NC}        | Swiss malware protection + home IP decoupled via relays"
    echo -e " 10) ${BOLD}LibreDNS via Multi-Hop Relay${NC}     | Community adblock DNS + dual-layer relay anonymity"
    echo ""
    echo -e "${CYAN}-- Maximum Privacy (DNS Over 3-Hop Tor Circuits) --${NC}"
    echo -e " 11) ${BOLD}Quad9 via Tor Onion Circuit${NC}      | Malware filtering routed over 3-hop Tor circuits"
    echo -e " 12) ${BOLD}LibreDNS Adblock via Tor${NC}         | Ad-blocking over Tor; absolute zero IP leakage to resolver"
    echo -e " 13) ${BOLD}Cloudflare via Tor${NC}               | Fast anycast queries routed anonymously over Tor"
    echo ""
    echo -e "${CYAN}-- System Management --${NC}"
    echo -e " 14) ${BOLD}Revert to Default DHCP DNS${NC}       | Restores standard ISP / router DHCP DNS configuration"
    echo -e " 15) ${BOLD}Cancel / Return to Main Menu${NC}"
    echo -e "${CYAN}==========================================================================================${NC}"

    read -rp "Select DNS profile [0-14, default: 0 (Auto-Failover), 15 to Cancel]: " sel
    sel="${sel:-0}"

    case "$sel" in
        15|[Qq]|cancel|exit)
            log_info "DNS profile selection cancelled."
            return
            ;;
        0|1|2|3|4|5|6|7|8|9|10|11|12|13|14)
            apply_dns_profile "$sel"
            ;;
        cloudflare|google|quad9|adguard|controld|libredns|revert|dhcp|failover)
            apply_dns_profile "$sel"
            ;;
        *)
            log_warn "Invalid selection: '$sel'. Please choose an option from 0 to 14."
            sleep 1
            ;;
    esac
}

# ==============================================================================
# MODULE 3: MAC Address Randomization & Hardware Spoofing
# ==============================================================================

generate_random_mac() {
    printf '02:%s\n' "$(od -An -N5 -tx1 /dev/urandom | tr -s ' ' | sed 's/^ //; s/ /:/g')"
}

show_mac_status() {
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}               Network MAC Address Status${NC}"
    echo -e "${CYAN}========================================================${NC}"

    local nm_active=0 networkd_active=0
    systemctl is-active --quiet NetworkManager 2>/dev/null && nm_active=1
    systemctl is-active --quiet systemd-networkd 2>/dev/null && networkd_active=1

    if [ "$nm_active" -eq 1 ]; then
        if [ -f "$NM_MAC_CONF" ] && grep -q "wifi.cloned-mac-address=random" "$NM_MAC_CONF" 2>/dev/null; then
            echo -e "NetworkManager Auto-Randomization : ${GREEN}ENABLED (Persistent)${NC}"
        else
            echo -e "NetworkManager Auto-Randomization : ${YELLOW}DISABLED${NC}"
        fi
    elif [ "$networkd_active" -eq 1 ]; then
        echo -e "Network Daemon                    : systemd-networkd (Active)"
    else
        echo -e "Network Daemon                    : Generic Linux Networking"
    fi
    echo ""

    local interfaces
    interfaces=$(ip -o link | awk -F': ' '{print $2}' | grep -vE '^(lo|docker.*|virbr.*|veth.*|tun.*|wg.*|tap.*|tailscale.*|p2p.*|br-.*|bond.*|team.*|dummy.*|lxcbr.*|incusbr.*|podman.*|ppp.*|can.*)$' || true)

    if [ -z "$interfaces" ]; then
        log_warn "No physical network interfaces found."
        echo -e "${CYAN}========================================================${NC}"
        return
    fi

    printf "%-12s %-18s %-18s %-10s %s\n" "INTERFACE" "CURRENT MAC" "PERMANENT MAC" "STATE" "STATUS"
    printf "%-12s %-18s %-18s %-10s %s\n" "---------" "-----------" "-------------" "-----" "------"

    for iface in $interfaces; do
        local cur_mac perm_mac state status
        cur_mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null || echo "Unknown")
        state=$(ip -br link show "$iface" 2>/dev/null | awk '{print $2}')

        perm_mac="Unknown"
        if command -v ethtool &>/dev/null; then
            perm_mac=$(ethtool -P "$iface" 2>/dev/null | awk '{print $3}' || echo "Unknown")
        fi
        [ -z "$perm_mac" ] && perm_mac="Unknown"

        if [ "$perm_mac" != "Unknown" ] && [ "$cur_mac" != "$perm_mac" ]; then
            status="${GREEN}SPOOFED (Randomized)${NC}"
        elif [ "$perm_mac" != "Unknown" ] && [ "$cur_mac" = "$perm_mac" ]; then
            status="${YELLOW}REAL (Hardware)${NC}"
        else
            status="N/A"
        fi

        printf "%-12s %-18s %-18s %-10s " "$iface" "$cur_mac" "$perm_mac" "$state"
        echo -e "$status"
    done
    echo -e "${CYAN}========================================================${NC}"
}

randomize_mac() {
    check_root "mac" "randomize"

    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}            Network MAC Address Randomization${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    if [ ! -f "$NM_MAC_CONF" ]; then
        log_info "Creating NetworkManager MAC randomization configuration..."
        enable_mac_randomization
        echo ""
    fi

    local interfaces
    interfaces=$(ip -o link | awk -F': ' '{print $2}' | grep -vE '^(lo|docker.*|virbr.*|veth.*|tun.*|wg.*|tap.*|tailscale.*|p2p.*|br-.*|bond.*|team.*|dummy.*|lxcbr.*|incusbr.*|podman.*|ppp.*|can.*)$' || true)

    if [ -z "$interfaces" ]; then
        log_warn "No physical network interfaces found to randomize."
        return
    fi

    for iface in $interfaces; do
        local old_mac perm_mac
        old_mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null || echo "Unknown")
        perm_mac="Unknown"
        if command -v ethtool &>/dev/null; then
            perm_mac=$(ethtool -P "$iface" 2>/dev/null | awk '{print $3}' || echo "Unknown")
        fi

        echo -e "${BOLD}[*] Interface: $iface${NC}"
        echo "    - Permanent Hardware MAC : $perm_mac"
        echo "    - Current Active MAC     : $old_mac"

        local is_ssh=0
        if [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_CLIENT:-}" ]; then
            is_ssh=1
        fi
        local def_iface
        def_iface=$(ip route show default 2>/dev/null | awk '/default/ {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1 || true)
        if [ "$is_ssh" -eq 1 ] && [ "$iface" = "$def_iface" ]; then
            log_warn "Skipping MAC connection bounce on '$iface' (active SSH session detected)."
            continue
        fi

        local active_conn
        active_conn=$(nmcli -t -f DEVICE,NAME connection show --active 2>/dev/null | grep "^$iface:" | head -n1 | cut -d: -f2- || true)

        if [ -n "$active_conn" ]; then
            echo "    - Interface is connected via NetworkManager ($active_conn)."
            echo "    - Re-cycling connection to obtain fresh random cloned MAC..."
            nmcli connection down "$active_conn" >/dev/null 2>&1 || true
            sleep 1
            nmcli connection up "$active_conn" >/dev/null 2>&1 || true
        elif command -v nmcli &>/dev/null && nmcli -t -f DEVICE,STATE dev 2>/dev/null | grep -q "^$iface:connected"; then
            echo "    - Interface is connected via NetworkManager."
            echo "    - Re-cycling connection to obtain fresh random cloned MAC..."
            nmcli device disconnect "$iface" >/dev/null 2>&1 || true
            sleep 1
            nmcli device connect "$iface" >/dev/null 2>&1 || true
        else
            local new_mac
            new_mac=$(generate_random_mac)
            echo "    - Setting randomized MAC via ip link: $new_mac"
            local state
            state=$(ip -br link show "$iface" 2>/dev/null | awk '{print $2}')
            ip link set dev "$iface" down 2>/dev/null || true
            if ip link set dev "$iface" address "$new_mac" 2>/dev/null; then
                echo "    - Applied new MAC: $new_mac"
            else
                log_warn "Hardware driver rejected direct MAC change."
            fi
            if [ "$state" = "UP" ]; then
                ip link set dev "$iface" up 2>/dev/null || true
            fi
        fi

        local current_mac
        current_mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null || echo "Unknown")
        if [ "$current_mac" != "Unknown" ] && [ "$current_mac" != "$old_mac" ]; then
            echo -e "    ${GREEN}[+] Updated MAC Address  : $current_mac${NC}"
        else
            echo -e "    ${YELLOW}[!] Active MAC Address   : $current_mac (Unchanged)${NC}"
        fi
        echo ""
    done
    log_success "MAC randomization routine finished."
    echo -e "${CYAN}========================================================${NC}"
}

enable_mac_randomization() {
    check_root "mac" "enable"

    log_info "Enabling persistent MAC address randomization in NetworkManager..."
    cat << 'EOF' > "$NM_MAC_CONF"
[device]
# Randomize MAC address while scanning for Wi-Fi networks
wifi.scan-rand-mac-address=yes

[connection]
# Randomize MAC address when connecting to a Wi-Fi network
wifi.cloned-mac-address=random

# Randomize Ethernet connections as well
ethernet.cloned-mac-address=random
EOF
    chmod 644 "$NM_MAC_CONF"
    systemctl reload NetworkManager 2>/dev/null || systemctl restart NetworkManager 2>/dev/null || true
    log_success "Persistent MAC randomization enabled. NetworkManager will auto-assign random MACs on every connection and scan."
}

disable_mac_randomization() {
    check_root "mac" "disable"

    log_info "Disabling persistent MAC address randomization..."
    if [ -f "$NM_MAC_CONF" ]; then
        rm -f "$NM_MAC_CONF"
        systemctl reload NetworkManager 2>/dev/null || systemctl restart NetworkManager 2>/dev/null || true
        log_success "Persistent MAC randomization disabled."
    else
        log_warn "Persistent MAC randomization config was not present."
    fi
}

# ==============================================================================
# MODULE 4: Privacy Scrubbing & Anti-Tracking
# ==============================================================================

clean_privacy() {
    check_root "${1:-privacy}"

    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}       Linux Mint Privacy & Activity Scrubbing${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    local avail_before
    avail_before=$(df -k / 2>/dev/null | awk 'END {print $4}')
    [[ "$avail_before" =~ ^[0-9]+$ ]] || avail_before=0

    # 1. Flush DNS cache & Query Logs
    echo ">>> [1/6] Flushing DNS Resolver Caches & Query Logs..."
    if command -v resolvectl &>/dev/null; then
        resolvectl flush-caches 2>/dev/null && echo "  - systemd-resolved DNS cache flushed." || true
    elif command -v systemd-resolve &>/dev/null; then
        systemd-resolve --flush-caches 2>/dev/null && echo "  - systemd-resolve DNS cache flushed." || true
    fi
    if systemctl is-active --quiet dnsmasq 2>/dev/null; then
        systemctl restart dnsmasq 2>/dev/null && echo "  - dnsmasq cache flushed." || true
    fi
    if systemctl is-active --quiet nscd 2>/dev/null; then
        nscd -i hosts 2>/dev/null && echo "  - nscd hosts cache invalidated." || true
    fi
    if [ -f "/var/log/dnscrypt-proxy/query.log" ]; then
        : > "/var/log/dnscrypt-proxy/query.log" 2>/dev/null && echo "  - dnscrypt-proxy query.log purged." || true
    fi
    if [ -f "/var/log/dnscrypt-proxy/nx.log" ]; then
        : > "/var/log/dnscrypt-proxy/nx.log" 2>/dev/null && echo "  - dnscrypt-proxy nx.log purged." || true
    fi
    echo ""

    # 2. Reset Recent Documents & Activity History (Symlink Protected)
    echo ">>> [2/6] Clearing Recent Files & Activity History..."
    for h in /root /home/*; do
        [ -d "$h" ] || continue
        [ -L "$h" ] && continue
        is_safe_user_path "$h" "$h" || continue

        local recent_file="$h/.local/share/recently-used.xbel"
        if [ -f "$recent_file" ] && is_safe_user_path "$h" "$recent_file"; then
            local tmp_recent="${recent_file}.tmp.$$"
            echo '<?xml version="1.0" encoding="UTF-8"?><xbel version="1.0" xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks" xmlns:mime="http://www.freedesktop.org/standards/shared-mime-info"></xbel>' > "$tmp_recent"
            local owner
            owner=$(stat -c '%u:%g' "$h" 2>/dev/null || echo "0:0")
            chown --no-dereference "$owner" "$tmp_recent" 2>/dev/null || true
            chmod 600 "$tmp_recent" 2>/dev/null || true
            mv -T "$tmp_recent" "$recent_file" 2>/dev/null || rm -f "$tmp_recent"
            echo "  - Reset recent files history for: $(basename "$h")"
        fi

        if is_safe_user_path "$h" "$h/.local/share/.vivaldi_reporting_data" && [ ! -L "$h/.local/share/.vivaldi_reporting_data" ]; then
            rm -f "$h/.local/share/.vivaldi_reporting_data" 2>/dev/null || true
        fi
        if is_safe_user_path "$h" "$h/.local/share/zeitgeist" && [ ! -L "$h/.local/share/zeitgeist" ]; then
            rm -rf "$h/.local/share/zeitgeist" 2>/dev/null || true
        fi
    done
    echo "[+] Activity history cleared."
    echo ""

    # 3. Web Browser Caches (Only caches - preserves bookmarks, passwords, logins & history)
    echo ">>> [3/6] Cleaning Web Browser Caches..."
    if pgrep -x "firefox|firefox-bin|chrome|chromium|brave|vivaldi" &>/dev/null; then
        echo "  [!] Notice: Active web browser detected. Some in-use cache files may remain locked."
    fi

    for h in /root /home/*; do
        [ -d "$h" ] || continue
        [ -L "$h" ] && continue
        is_safe_user_path "$h" "$h" || continue

        if is_safe_user_path "$h" "$h/.cache/mozilla/firefox" && [ -d "$h/.cache/mozilla/firefox" ]; then
            find "$h/.cache/mozilla/firefox" -mindepth 1 -maxdepth 3 -type d \( -name "cache2" -o -name "startupCache" -o -name "jumpListCache" \) -exec rm -rf {} + 2>/dev/null || true
            echo "  - Cleaned Firefox caches in $(basename "$h")"
        fi

        local chromium_cache_dirs=(
            "$h/.cache/google-chrome"
            "$h/.cache/chromium"
            "$h/.cache/BraveSoftware/Brave-Browser"
            "$h/.cache/vivaldi"
        )
        for cdir in "${chromium_cache_dirs[@]}"; do
            if is_safe_user_path "$h" "$cdir" && [ -d "$cdir" ]; then
                find "$cdir" -mindepth 1 -maxdepth 4 -type d \( -name "Cache" -o -name "GPUCache" -o -name "Code Cache" -o -name "ShaderCache" -o -name "GrShaderCache" \) -exec rm -rf {} + 2>/dev/null || true
                echo "  - Cleaned $(basename "$cdir") caches in $(basename "$h")"
            fi
        done

        if is_safe_user_path "$h" "$h/.var/app" && [ -d "$h/.var/app" ]; then
            find "$h/.var/app" -mindepth 2 -maxdepth 4 -type d -name "cache" -exec rm -rf {} + 2>/dev/null || true
        fi
    done
    echo "[+] Web browser caches cleaned."
    echo ""

    # 4. Thumbnail Caches (Symlink Protected)
    echo ">>> [4/6] Purging Image & Document Preview Thumbnails..."
    for h in /root /home/*; do
        [ -d "$h" ] || continue
        [ -L "$h" ] && continue
        is_safe_user_path "$h" "$h" || continue

        if is_safe_user_path "$h" "$h/.cache/thumbnails" && [ -d "$h/.cache/thumbnails" ]; then
            find "$h/.cache/thumbnails" -mindepth 1 -maxdepth 3 ! -type l -delete 2>/dev/null || true
            echo "  - Purged thumbnail previews in: $(basename "$h")"
        fi
    done
    echo "[+] Thumbnail caches purged."
    echo ""

    # 5. Trash Bins (Symlink Protected)
    echo ">>> [5/6] Emptying Trash Bins..."
    for h in /root /home/*; do
        [ -d "$h" ] || continue
        [ -L "$h" ] && continue
        is_safe_user_path "$h" "$h" || continue

        if is_safe_user_path "$h" "$h/.local/share/Trash" && [ -d "$h/.local/share/Trash" ]; then
            for tsub in files info; do
                local tdir="$h/.local/share/Trash/$tsub"
                if is_safe_user_path "$h" "$tdir" && [ -d "$tdir" ]; then
                    find "$tdir" -mindepth 1 -maxdepth 4 ! -type l -delete 2>/dev/null || true
                fi
            done
            echo "  - Emptied trash for: $(basename "$h")"
        fi
    done
    echo "[+] Trash bins emptied."
    echo ""

    # 6. Crash Reports & Core Dumps
    echo ">>> [6/6] Purging Crash Logs & Memory Core Dumps..."
    local do_crash=1
    if [ "${FORCE_YES:-0}" -ne 1 ] && [ -t 0 ]; then
        read -r -p "  Purge system crash reports (/var/crash) and core dumps? [y/N]: " crash_ans
        [[ "$crash_ans" =~ ^[Yy]$ ]] || do_crash=0
    fi
    if [ "$do_crash" -eq 1 ]; then
        rm -rf /var/crash/* 2>/dev/null || true
        rm -rf /var/lib/systemd/coredump/* 2>/dev/null || true
        echo "  - Removed system crash reports and core dumps."
    else
        echo "  - Preserved system crash reports and core dumps."
    fi
    echo "[+] Crash reports cleaned."
    echo ""

    print_summary "$avail_before"
}

# ==============================================================================
# MODULE 5: Optimization & Housekeeping
# ==============================================================================

update_apt() {
    echo ">>> Updating APT Packages..."
    echo "  - Refreshing repository package lists (apt-get update)..."
    apt-get update

    echo "  - Upgrading installed packages (apt-get dist-upgrade)..."
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y -o Dpkg::Options::="--force-confold"
    echo "[+] APT package updates complete."
    echo ""
}

update_flatpak() {
    echo ">>> Updating Flatpak Applications & Runtimes..."
    if command -v flatpak &>/dev/null; then
        echo "  - Updating system Flatpak packages..."
        flatpak update -y || echo "  [!] Notice: Flatpak system update reported warnings."

        if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            echo "  - Updating user Flatpak packages ($SUDO_USER)..."
            sudo -u "$SUDO_USER" flatpak update -y 2>/dev/null || true
        fi
        echo "[+] Flatpak updates complete."
    else
        echo "  - Flatpak not installed; skipping update."
    fi
    echo ""
}

clean_apt() {
    echo ">>> APT Cache Cleaning & Orphan Removal..."
    echo "  - Purging orphaned packages and leftover dependencies (autoremove)..."
    DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y -o Dpkg::Options::="--force-confold" 2>/dev/null || true

    echo "  - Cleaning downloaded package archive caches (clean & autoclean)..."
    apt-get clean
    apt-get autoclean -y >/dev/null

    echo "  - Checking for residual package configurations (rc state)..."
    local rc_pkgs
    rc_pkgs=$(dpkg -l 2>/dev/null | awk '/^rc/ {print $2}')
    if [ -n "$rc_pkgs" ]; then
        echo "  - Purging residual configurations: $rc_pkgs"
        echo "$rc_pkgs" | xargs -r dpkg --purge 2>/dev/null || true
    else
        echo "  - No residual configuration packages found."
    fi
    echo "[+] APT housekeeping complete."
    echo ""
}

clean_flatpak() {
    echo ">>> Flatpak Runtimes & Cache Maintenance..."
    if command -v flatpak &>/dev/null; then
        echo "  - Uninstalling unused Flatpak runtimes and orphan SDKs (system)..."
        flatpak uninstall --unused -y 2>/dev/null || true

        if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            echo "  - Uninstalling unused Flatpak runtimes (user: $SUDO_USER)..."
            sudo -u "$SUDO_USER" flatpak uninstall --unused -y 2>/dev/null || true
        fi

        echo "  - Checking and repairing Flatpak runtime integrity..."
        flatpak repair 2>/dev/null || true

        echo "  - Cleaning temporary Flatpak caches..."
        rm -rf /var/tmp/flatpak-cache-* 2>/dev/null || true
        echo "[+] Flatpak maintenance complete."
    else
        echo "  - Flatpak not installed; skipping."
    fi
    echo ""
}

clean_systemd() {
    echo ">>> Systemd Journals & Residual Services..."
    if command -v journalctl &>/dev/null; then
        local j_before
        j_before=$(journalctl --disk-usage 2>/dev/null || echo "N/A")
        echo "  - Current journal footprint: $j_before"

        journalctl --rotate >/dev/null 2>&1 || true
        journalctl --vacuum-time=7d >/dev/null 2>&1 || true
        journalctl --vacuum-size=100M >/dev/null 2>&1 || true

        local j_after
        j_after=$(journalctl --disk-usage 2>/dev/null || echo "N/A")
        echo "  - Journal footprint after vacuuming: $j_after"
    fi

    if [ -f "/var/log/dnscrypt-proxy/query.log" ]; then
        local qlog_size
        qlog_size=$(stat -c '%s' "/var/log/dnscrypt-proxy/query.log" 2>/dev/null || echo 0)
        if [ "$qlog_size" -gt 10485760 ]; then
            : > "/var/log/dnscrypt-proxy/query.log" 2>/dev/null || true
            echo "  - Truncated oversized dnscrypt-proxy query log (>10MB)."
        fi
    fi

    local failed_units
    failed_units=$(systemctl --failed --no-legend 2>/dev/null || true)
    if [ -n "$failed_units" ]; then
        echo "  [!] Notice: Found failed systemd units:"
        echo "$failed_units" | sed 's/^/      /'
    else
        echo "  - All systemd system services are running healthy (0 failed)."
    fi
    echo "[+] Systemd maintenance complete."
    echo ""
}

clean_user_cache() {
    echo ">>> Stale Caches & Safe Temp Cleanups..."
    echo "  - Cleaning stale thumbnail caches older than 14 days (symlink protected)..."
    for h in /root /home/*; do
        [ -d "$h" ] || continue
        [ -L "$h" ] && continue
        is_safe_user_path "$h" "$h" || continue
        if [ -d "$h/.cache/thumbnails" ] && [ ! -L "$h/.cache/thumbnails" ] && is_safe_user_path "$h" "$h/.cache/thumbnails"; then
            find "$h/.cache/thumbnails" -mindepth 1 -maxdepth 4 -type f ! -type l -mtime +14 -delete 2>/dev/null || true
        fi
    done

    echo "  - Pruning old /var/tmp residual files (> 30 days old)..."
    find /var/tmp -mindepth 1 -maxdepth 3 -type f ! -type l -mtime +30 -delete 2>/dev/null || true

    echo "[+] Cache housekeeping complete."
    echo ""
}

run_optimizer() {
    check_root "${1:-optimize}"

    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}       Linux Mint System Optimizer & Housekeeping${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    local avail_before
    avail_before=$(df -k / 2>/dev/null | awk 'END {print $4}')
    [[ "$avail_before" =~ ^[0-9]+$ ]] || avail_before=0
    echo "[*] Initial free space on root filesystem: $(format_kb "$avail_before")"
    echo ""

    clean_apt
    clean_flatpak
    clean_systemd
    clean_user_cache
    print_summary "$avail_before"
}

update_and_clean() {
    check_root "${1:-update}"

    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}   Linux Mint Package Update & Dependency Cleanup${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    local avail_before
    avail_before=$(df -k / 2>/dev/null | awk 'END {print $4}')
    [[ "$avail_before" =~ ^[0-9]+$ ]] || avail_before=0
    echo "[*] Initial free space on root filesystem: $(format_kb "$avail_before")"
    echo ""

    update_apt
    update_flatpak

    clean_apt
    clean_flatpak

    print_summary "$avail_before"
}

run_full_update_and_optimizer() {
    check_root "${1:-all}"

    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD} Linux Mint Full Update & Complete System Optimization${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    local avail_before
    avail_before=$(df -k / 2>/dev/null | awk 'END {print $4}')
    [[ "$avail_before" =~ ^[0-9]+$ ]] || avail_before=0
    echo "[*] Initial free space on root filesystem: $(format_kb "$avail_before")"
    echo ""

    update_apt
    update_flatpak

    clean_apt
    clean_flatpak
    clean_systemd
    clean_user_cache

    print_summary "$avail_before"
}

run_complete_suite() {
    check_root "full-suite"

    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}  Linux Mint Total Suite: Update, Housekeep & Privacy${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    local avail_before
    avail_before=$(df -k / 2>/dev/null | awk 'END {print $4}')
    [[ "$avail_before" =~ ^[0-9]+$ ]] || avail_before=0

    update_apt
    update_flatpak

    clean_apt
    clean_flatpak
    clean_systemd
    clean_user_cache

    clean_privacy "privacy"

    local do_mac=1
    if [ "${FORCE_YES:-0}" -ne 1 ] && [ -t 0 ]; then
        echo ""
        read -r -p "Randomizing MAC addresses will momentarily cycle network connections. Proceed? [y/N]: " mac_ans
        [[ "$mac_ans" =~ ^[Yy]$ ]] || do_mac=0
    fi
    if [ "$do_mac" -eq 1 ]; then
        randomize_mac "mac"
    else
        log_info "Skipping MAC address randomization as requested."
    fi

    print_summary "$avail_before"
}

# ==============================================================================
# MODULE 6: Automated Weekly Maintenance Timers
# ==============================================================================

install_weekly_timer() {
    check_root "timer" "install"

    log_info "Setting up weekly automated maintenance timer..."

    local exec_target="$SCRIPT_PATH"
    local owner_uid
    owner_uid=$(stat -c '%u' "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$owner_uid" != "0" ] || [[ "$SCRIPT_PATH" == /home/* ]]; then
        log_info "Securing systemd timer: installing root-owned script to $CANONICAL_BIN..."
        mkdir -p /usr/local/sbin
        if ! install -m 755 -o root -g root "$SCRIPT_PATH" "$CANONICAL_BIN"; then
            log_err "Failed to securely install root-owned binary to $CANONICAL_BIN."
            exit 1
        fi
        exec_target="$CANONICAL_BIN"
    fi

    cat << EOF > "$OPTIMIZER_SERVICE"
[Unit]
Description=Linux Mint Weekly System Optimizer & Housekeeping
Documentation="file://$exec_target"
After=network.target

[Service]
Type=oneshot
ExecStart="$exec_target" optimize
Nice=19
IOSchedulingClass=idle
EOF
    chmod 644 "$OPTIMIZER_SERVICE"

    cat << 'EOF' > "$OPTIMIZER_TIMER"
[Unit]
Description=Run Linux Mint System Optimizer Weekly
Documentation=file:///etc/systemd/system/mint-optimizer.service

[Timer]
OnCalendar=Sun *-*-* 03:00:00
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF
    chmod 644 "$OPTIMIZER_TIMER"

    systemctl daemon-reload
    systemctl enable --now mint-optimizer.timer
    systemctl restart mint-optimizer.timer 2>/dev/null || true

    log_success "Weekly optimization timer installed and activated!"
    echo "    - Target    : $exec_target optimize"
    echo "    - Frequency : Every Sunday at 03:00 AM (runs upon next boot if laptop was asleep/off)"
    echo "    - Logs      : journalctl -u mint-optimizer.service"
}

uninstall_weekly_timer() {
    check_root "timer" "uninstall"

    log_info "Disabling and removing weekly optimization timer..."
    systemctl stop mint-optimizer.timer 2>/dev/null || true
    systemctl disable mint-optimizer.timer 2>/dev/null || true
    rm -f "$OPTIMIZER_SERVICE" "$OPTIMIZER_TIMER"
    if [ -f "$CANONICAL_BIN" ]; then
        rm -f "$CANONICAL_BIN"
        log_info "Removed canonical binary: $CANONICAL_BIN"
    fi
    systemctl daemon-reload

    log_success "Weekly optimization timer uninstalled."
}

show_timer_status() {
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}        Weekly Optimizer Timer Status${NC}"
    echo -e "${CYAN}========================================================${NC}"
    if [ -f "$OPTIMIZER_TIMER" ] && systemctl is-enabled --quiet mint-optimizer.timer 2>/dev/null; then
        echo -e "Status: ${GREEN}ACTIVE & ENABLED${NC}"
        echo ""
        systemctl list-timers mint-optimizer.timer --no-pager 2>/dev/null || true
        echo ""
        echo "Last Run Log:"
        journalctl -u mint-optimizer.service -n 10 --no-pager 2>/dev/null || echo "No previous runs logged yet."
    else
        echo -e "Status: ${YELLOW}NOT INSTALLED / DISABLED${NC}"
        echo "Run 'sudo $0 timer install' to enable weekly automatic maintenance."
    fi
    echo -e "${CYAN}========================================================${NC}"
}

# ==============================================================================
# MODULE 7: System Performance Tuning & Privacy Hardening
# ==============================================================================

save_tuning_baseline() {
    mkdir -p /var/lib/mint-admin
    if [ ! -f "$BASELINE_SYSCTL" ]; then
        local avahi_active=0 cups_active=0 modem_active=0 wait_active=0
        systemctl is-active --quiet avahi-daemon 2>/dev/null && avahi_active=1
        systemctl is-active --quiet cups-browsed 2>/dev/null && cups_active=1
        systemctl is-active --quiet ModemManager 2>/dev/null && modem_active=1
        systemctl is-enabled --quiet NetworkManager-wait-online.service 2>/dev/null && wait_active=1

        {
            echo "BASE_SUID_DUMPABLE=$(sysctl -n fs.suid_dumpable 2>/dev/null || echo 2)"
            echo "BASE_BPF_DISABLED=$(sysctl -n kernel.unprivileged_bpf_disabled 2>/dev/null || echo 2)"
            echo "BASE_FASTOPEN=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo 1)"
            echo "BASE_SWAPPINESS=$(sysctl -n vm.swappiness 2>/dev/null || echo 60)"
            echo "BASE_VFS_PRESSURE=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null || echo 100)"
            echo "BASE_DMESG_RESTRICT=$(sysctl -n kernel.dmesg_restrict 2>/dev/null || echo 0)"
            echo "BASE_KPTR_RESTRICT=$(sysctl -n kernel.kptr_restrict 2>/dev/null || echo 1)"
            echo "BASE_TCP_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo cubic)"
            echo "BASE_QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo fq_codel)"
            echo "BASE_AVAHI_ACTIVE=$avahi_active"
            echo "BASE_CUPS_ACTIVE=$cups_active"
            echo "BASE_MODEM_ACTIVE=$modem_active"
            echo "BASE_NM_WAIT_ACTIVE=$wait_active"
        } > "$BASELINE_SYSCTL" 2>/dev/null || true
    fi
}

show_tuning_status() {
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}         System Performance & Privacy Tuning Status${NC}"
    echo -e "${CYAN}========================================================${NC}"

    # 1. TCP Congestion Control
    local tcp_cc qdisc
    tcp_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "Unknown")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "Unknown")
    if [ "$tcp_cc" = "bbr" ]; then
        echo -e "TCP Congestion Control : ${GREEN}BBR${NC} (Optimal low-latency, qdisc: $qdisc)"
    else
        echo -e "TCP Congestion Control : ${YELLOW}$tcp_cc${NC} (Legacy; switch to BBR for faster network)"
    fi

    # 2. Memory & Swappiness
    local swappiness vfs_press
    swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "Unknown")
    vfs_press=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null || echo "Unknown")
    if [[ "$swappiness" =~ ^[0-9]+$ ]] && [ "$swappiness" -eq 100 ]; then
        echo -e "vm.swappiness          : ${GREEN}$swappiness${NC} (Optimized for ZRAM & NVMe SSD)"
    else
        echo -e "vm.swappiness          : ${YELLOW}$swappiness${NC} (Default / standard disk swap)"
    fi
    echo -e "vm.vfs_cache_pressure  : $vfs_press"

    # 3. ZRAM Compressed Swap
    if swapon --show 2>/dev/null | grep -q "zram"; then
        local zram_info
        zram_info=$(swapon --show 2>/dev/null | grep "zram" | awk '{print $3, "used: "$4, "prio: "$5}')
        echo -e "ZRAM Compressed Swap   : ${GREEN}ACTIVE${NC} ($zram_info)"
    else
        echo -e "ZRAM Compressed Swap   : ${YELLOW}INACTIVE${NC} (Using standard disk swap)"
    fi

    # 4. Hostname Privacy over DHCP
    if [ "$(status_get_dhcp)" = "BLOCKED (Protected)" ]; then
        echo -e "DHCP Hostname Leak     : ${GREEN}BLOCKED${NC} (Hostname not sent to Wi-Fi routers)"
    else
        echo -e "DHCP Hostname Leak     : ${YELLOW}EXPOSED${NC} (Routers log your PC hostname)"
    fi

    # 5. Boot Speed (NetworkManager-wait-online)
    if systemctl is-enabled --quiet NetworkManager-wait-online.service 2>/dev/null; then
        echo -e "NM Wait-Online Delay   : ${YELLOW}ENABLED${NC} (Adds ~7s delay to system boot)"
    else
        echo -e "NM Wait-Online Delay   : ${GREEN}DISABLED${NC} (Fast desktop boot)"
    fi

    # 6. Background Broadcast Daemons
    local avahi_st cups_st modem_st
    systemctl is-active --quiet avahi-daemon 2>/dev/null && avahi_st="${YELLOW}ACTIVE (mDNS broadcasting)${NC}" || avahi_st="${GREEN}DISABLED${NC}"
    systemctl is-active --quiet cups-browsed 2>/dev/null && cups_st="${YELLOW}ACTIVE (UDP 631 polling)${NC}" || cups_st="${GREEN}DISABLED${NC}"
    systemctl is-active --quiet ModemManager 2>/dev/null && modem_st="${YELLOW}ACTIVE${NC}" || modem_st="${GREEN}DISABLED${NC}"
    echo -e "mDNS Hostname Broadcast: $avahi_st"
    echo -e "CUPS Network Polling   : $cups_st"
    echo -e "ModemManager Daemon    : $modem_st"

    # 7. Kernel Privacy Hardening
    local dmesg_r kptr_r
    dmesg_r=$(cat /proc/sys/kernel/dmesg_restrict 2>/dev/null || echo "0")
    kptr_r=$(cat /proc/sys/kernel/kptr_restrict 2>/dev/null || echo "0")
    if [ "$dmesg_r" -ge 1 ] && [ "$kptr_r" -ge 1 ]; then
        echo -e "Kernel Memory Privacy  : ${GREEN}HARDENED${NC} (dmesg & kptr restricted to root)"
    else
        echo -e "Kernel Memory Privacy  : ${YELLOW}PERMISSIVE${NC} (Kernel logs visible to unprivileged apps)"
    fi

    # 8. IPv6 Protocol State
    local ipv6_dis
    ipv6_dis=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo "0")
    if [ "$ipv6_dis" -eq 1 ]; then
        echo -e "IPv6 Protocol State    : ${RED}DISABLED (Leak Protected)${NC}"
    else
        echo -e "IPv6 Protocol State    : ${GREEN}ENABLED${NC}"
    fi
    echo -e "${CYAN}========================================================${NC}"
}

# ------------------------------------------------------------------------------
# Individual Subsystem Toggles
# ------------------------------------------------------------------------------

# 1. NM Wait-Online Delay (Fast Desktop Boot)
enable_nm_wait_online() {
    check_root "tune" "wait-online" "enable"
    log_info "Enabling NetworkManager-wait-online service..."
    systemctl unmask NetworkManager-wait-online.service 2>/dev/null || true
    systemctl enable NetworkManager-wait-online.service 2>/dev/null || true
    log_success "NM Wait-Online Delay enabled (system boot delays until network is up)."
}

disable_nm_wait_online() {
    check_root "tune" "wait-online" "disable"
    log_info "Disabling NetworkManager-wait-online service..."
    systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
    log_success "NM Wait-Online Delay disabled (~7s delay removed for fast desktop boot)."
}

toggle_nm_wait_online() {
    check_root "tune" "wait-online" "toggle"
    if systemctl is-enabled --quiet NetworkManager-wait-online.service 2>/dev/null; then
        disable_nm_wait_online
    else
        enable_nm_wait_online
    fi
}

# 2. TCP Congestion Control (Google BBR)
enable_bbr() {
    check_root "tune" "bbr" "enable"
    save_tuning_baseline
    log_info "Enabling Google TCP BBR Congestion Control..."
    mkdir -p /etc/modules-load.d /etc/sysctl.d
    echo "tcp_bbr" > "$BBR_MODULE_CONF"
    modprobe tcp_bbr 2>/dev/null || true
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1 || true

    touch "$PERF_SYSCTL"
    sed -i '/^net\.core\.default_qdisc/d; /^net\.ipv4\.tcp_congestion_control/d; /^net\.ipv4\.tcp_fastopen/d' "$PERF_SYSCTL" 2>/dev/null || true
    cat << 'EOF' >> "$PERF_SYSCTL"
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
EOF
    log_success "TCP BBR active (optimal low-latency congestion control, qdisc: fq)."
}

disable_bbr() {
    check_root "tune" "bbr" "disable"
    log_info "Disabling TCP BBR and restoring baseline congestion control..."
    rm -f "$BBR_MODULE_CONF"
    local b_cc="cubic" b_qdisc="fq_codel" b_fastopen=1
    if [ -f "$BASELINE_SYSCTL" ]; then
        # shellcheck disable=SC1090
        . "$BASELINE_SYSCTL"
        b_cc="${BASE_TCP_CC:-cubic}"
        b_qdisc="${BASE_QDISC:-fq_codel}"
        b_fastopen="${BASE_FASTOPEN:-1}"
    fi
    sysctl -w net.ipv4.tcp_congestion_control="$b_cc" >/dev/null 2>&1 || true
    sysctl -w net.core.default_qdisc="$b_qdisc" >/dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_fastopen="$b_fastopen" >/dev/null 2>&1 || true
    if [ -f "$PERF_SYSCTL" ]; then
        sed -i '/^net\.core\.default_qdisc/d; /^net\.ipv4\.tcp_congestion_control/d; /^net\.ipv4\.tcp_fastopen/d' "$PERF_SYSCTL"
        grep -qE '^[a-zA-Z]' "$PERF_SYSCTL" 2>/dev/null || rm -f "$PERF_SYSCTL"
    fi
    log_success "TCP Congestion Control restored to baseline default ($b_cc, qdisc: $b_qdisc, fastopen: $b_fastopen)."
}

toggle_bbr() {
    check_root "tune" "bbr" "toggle"
    local cur_cc
    cur_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "Unknown")
    if [ "$cur_cc" = "bbr" ]; then
        disable_bbr
    else
        enable_bbr
    fi
}

# 3. Memory Swappiness & Cache Pressure
enable_swappiness() {
    check_root "tune" "swappiness" "enable"
    save_tuning_baseline
    log_info "Configuring optimized swappiness (100) and vfs_cache_pressure (50)..."
    mkdir -p /etc/sysctl.d
    touch "$PERF_SYSCTL"
    sed -i '/^vm\.swappiness/d; /^vm\.vfs_cache_pressure/d' "$PERF_SYSCTL" 2>/dev/null || true
    cat << 'EOF' >> "$PERF_SYSCTL"
vm.swappiness = 100
vm.vfs_cache_pressure = 50
EOF
    sysctl -w vm.swappiness=100 >/dev/null 2>&1 || true
    sysctl -w vm.vfs_cache_pressure=50 >/dev/null 2>&1 || true
    log_success "Memory tuning active: vm.swappiness=100, vm.vfs_cache_pressure=50 (optimized for ZRAM/SSD)."
}

disable_swappiness() {
    check_root "tune" "swappiness" "disable"
    log_info "Restoring default memory swappiness values..."
    local b_swap=60 b_vfs=100
    if [ -f "$BASELINE_SYSCTL" ]; then
        # shellcheck disable=SC1090
        . "$BASELINE_SYSCTL"
        b_swap="${BASE_SWAPPINESS:-60}"
        b_vfs="${BASE_VFS_PRESSURE:-100}"
    fi
    sysctl -w vm.swappiness="$b_swap" >/dev/null 2>&1 || true
    sysctl -w vm.vfs_cache_pressure="$b_vfs" >/dev/null 2>&1 || true
    if [ -f "$PERF_SYSCTL" ]; then
        sed -i '/^vm\.swappiness/d; /^vm\.vfs_cache_pressure/d' "$PERF_SYSCTL"
        grep -qE '^[a-zA-Z]' "$PERF_SYSCTL" 2>/dev/null || rm -f "$PERF_SYSCTL"
    fi
    log_success "Swappiness restored to baseline defaults (swappiness: $b_swap, vfs_pressure: $b_vfs)."
}

toggle_swappiness() {
    check_root "tune" "swappiness" "toggle"
    local cur_swap
    cur_swap=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "60")
    if [ "$cur_swap" -eq 100 ]; then
        disable_swappiness
    else
        enable_swappiness
    fi
}

# 4. ZRAM Compressed RAM Swap
enable_zram() {
    check_root "tune" "zram" "enable"
    log_info "Setting up ZRAM compressed RAM swap (zstd algorithm)..."
    if ! dpkg -l zram-tools &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y zram-tools
    fi

    cat << 'EOF' > "$ZRAM_CONF"
# ZRAM configuration (mint-admin - 50% RAM for 16GB laptop)
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF
    systemctl daemon-reload
    if systemctl enable --now zramswap.service 2>/dev/null; then
        log_success "ZRAM active: 50% RAM compressed with zstd (highest swap priority)."
    else
        log_warn "Failed to start zramswap.service; check systemctl status zramswap."
    fi
}

disable_zram() {
    check_root "tune" "zram" "disable"
    log_info "Disabling ZRAM compressed swap..."
    systemctl stop zramswap.service 2>/dev/null || true
    systemctl disable zramswap.service 2>/dev/null || true
    swapoff /dev/zram* 2>/dev/null || true
    command -v zramctl &>/dev/null && zramctl --reset /dev/zram* 2>/dev/null || true
    rm -f "$ZRAM_CONF"
    log_success "ZRAM swap deactivated and removed."
}

toggle_zram() {
    check_root "tune" "zram" "toggle"
    if swapon --show 2>/dev/null | grep -q "zram"; then
        disable_zram
    else
        enable_zram
    fi
}

# 5. Prevent DHCP Hostname Leakage
enable_dhcp_privacy() {
    check_root "tune" "dhcp" "enable"
    log_info "Configuring NetworkManager DHCP hostname privacy across connections..."
    rm -f "$DHCP_PRIVACY_CONF"
    mkdir -p /var/lib/mint-admin
    touch /var/lib/mint-admin/dhcp-privacy-enabled

    if command -v nmcli &>/dev/null; then
        while IFS= read -r uuid; do
            [ -n "$uuid" ] || continue
            nmcli con modify "$uuid" ipv4.dhcp-send-hostname no ipv6.dhcp-send-hostname no 2>/dev/null || true
        done < <(nmcli -t -f UUID connection show 2>/dev/null)
        nmcli general reload 2>/dev/null || true
    fi
    log_success "DHCP hostname leak protection active (hostname hidden from Wi-Fi routers)."
}

disable_dhcp_privacy() {
    check_root "tune" "dhcp" "disable"
    log_info "Disabling DHCP hostname leak protection..."
    rm -f "$DHCP_PRIVACY_CONF" /var/lib/mint-admin/dhcp-privacy-enabled

    if command -v nmcli &>/dev/null; then
        while IFS= read -r uuid; do
            [ -n "$uuid" ] || continue
            nmcli con modify "$uuid" ipv4.dhcp-send-hostname yes ipv6.dhcp-send-hostname yes 2>/dev/null || true
        done < <(nmcli -t -f UUID connection show 2>/dev/null)
        nmcli general reload 2>/dev/null || true
    fi
    log_success "DHCP hostname leak protection disabled (hostname will be sent in DHCP requests)."
}

toggle_dhcp_privacy() {
    check_root "tune" "dhcp" "toggle"
    if [ "$(status_get_dhcp)" = "BLOCKED (Protected)" ]; then
        disable_dhcp_privacy
    else
        enable_dhcp_privacy
    fi
}

# 6. Kernel Memory Privacy Hardening
enable_kernel_hardening() {
    check_root "tune" "kernel" "enable"
    save_tuning_baseline
    log_info "Configuring kernel privacy & memory protection sysctls..."
    mkdir -p /etc/sysctl.d
    cat << 'EOF' > "$PRIVACY_SYSCTL"
# Kernel Privacy & Security Hardening (mint-admin)
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.unprivileged_bpf_disabled = 1
fs.suid_dumpable = 0
EOF
    sysctl -p "$PRIVACY_SYSCTL" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1 || true
    log_success "Kernel privacy hardened (dmesg & kptr restricted to root)."
}

disable_kernel_hardening() {
    check_root "tune" "kernel" "disable"
    log_info "Restoring default kernel privacy sysctls..."
    rm -f "$PRIVACY_SYSCTL"
    local b_suid=2 b_bpf=2 b_dmesg=0 b_kptr=1
    if [ -f "$BASELINE_SYSCTL" ]; then
        # shellcheck disable=SC1090
        . "$BASELINE_SYSCTL"
        b_suid="${BASE_SUID_DUMPABLE:-2}"
        b_bpf="${BASE_BPF_DISABLED:-2}"
        b_dmesg="${BASE_DMESG_RESTRICT:-0}"
        b_kptr="${BASE_KPTR_RESTRICT:-1}"
    fi
    sysctl -w kernel.dmesg_restrict="$b_dmesg" >/dev/null 2>&1 || true
    sysctl -w kernel.kptr_restrict="$b_kptr" >/dev/null 2>&1 || true
    sysctl -w kernel.unprivileged_bpf_disabled="$b_bpf" >/dev/null 2>&1 || true
    sysctl -w fs.suid_dumpable="$b_suid" >/dev/null 2>&1 || true
    log_success "Kernel memory privacy restored to default permissive values."
}

toggle_kernel_hardening() {
    check_root "tune" "kernel" "toggle"
    local dmesg_r kptr_r
    dmesg_r=$(cat /proc/sys/kernel/dmesg_restrict 2>/dev/null || echo "0")
    kptr_r=$(cat /proc/sys/kernel/kptr_restrict 2>/dev/null || echo "0")
    if [ "$dmesg_r" -ge 1 ] && [ "$kptr_r" -ge 1 ]; then
        disable_kernel_hardening
    else
        enable_kernel_hardening
    fi
}

# 7. Background Discovery Daemons
toggle_avahi() {
    check_root "tune" "avahi" "toggle"
    if systemctl is-active --quiet avahi-daemon 2>/dev/null || systemctl is-enabled --quiet avahi-daemon 2>/dev/null; then
        log_info "Disabling avahi-daemon (mDNS broadcast)..."
        systemctl stop avahi-daemon.service avahi-daemon.socket 2>/dev/null || true
        systemctl disable avahi-daemon.service avahi-daemon.socket 2>/dev/null || true
        log_success "Avahi mDNS daemon stopped & disabled."
    else
        log_info "Enabling avahi-daemon (mDNS broadcast)..."
        systemctl unmask avahi-daemon.service avahi-daemon.socket 2>/dev/null || true
        systemctl enable --now avahi-daemon.socket avahi-daemon.service 2>/dev/null || true
        log_success "Avahi mDNS daemon enabled & started."
    fi
}

toggle_cups_browsed() {
    check_root "tune" "cups" "toggle"
    if systemctl is-active --quiet cups-browsed 2>/dev/null || systemctl is-enabled --quiet cups-browsed 2>/dev/null; then
        log_info "Disabling cups-browsed (UDP 631 printer polling)..."
        systemctl stop cups-browsed 2>/dev/null || true
        systemctl disable cups-browsed 2>/dev/null || true
        log_success "CUPS network browsing stopped & disabled."
    else
        log_info "Enabling cups-browsed..."
        systemctl unmask cups-browsed 2>/dev/null || true
        systemctl enable --now cups-browsed 2>/dev/null || true
        log_success "CUPS network browsing enabled & started."
    fi
}

toggle_modemmanager() {
    check_root "tune" "modem" "toggle"
    if systemctl is-active --quiet ModemManager 2>/dev/null || systemctl is-enabled --quiet ModemManager 2>/dev/null; then
        log_info "Disabling ModemManager (cellular serial scanner)..."
        systemctl stop ModemManager 2>/dev/null || true
        systemctl disable ModemManager 2>/dev/null || true
        log_success "ModemManager stopped & disabled."
    else
        log_info "Enabling ModemManager..."
        systemctl unmask ModemManager 2>/dev/null || true
        systemctl enable --now ModemManager 2>/dev/null || true
        log_success "ModemManager enabled & started."
    fi
}

toggle_broadcast_daemons() {
    check_root "tune" "daemons" "toggle"
    if systemctl is-active --quiet avahi-daemon 2>/dev/null || systemctl is-active --quiet cups-browsed 2>/dev/null || systemctl is-active --quiet ModemManager 2>/dev/null; then
        log_info "Stopping & disabling all background discovery daemons..."
        systemctl stop avahi-daemon.service avahi-daemon.socket cups-browsed ModemManager 2>/dev/null || true
        systemctl disable avahi-daemon.service avahi-daemon.socket cups-browsed ModemManager 2>/dev/null || true
        log_success "All discovery broadcast daemons disabled (Avahi, CUPS, ModemManager)."
    else
        log_info "Enabling & starting discovery broadcast daemons..."
        systemctl unmask avahi-daemon.service avahi-daemon.socket cups-browsed ModemManager 2>/dev/null || true
        systemctl enable --now avahi-daemon.socket avahi-daemon.service 2>/dev/null || true
        systemctl enable --now cups-browsed 2>/dev/null || true
        systemctl enable --now ModemManager 2>/dev/null || true
        log_success "Discovery broadcast daemons enabled & active."
    fi
}

apply_system_tuning() {
    check_root "tune" "apply"

    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}     Applying Performance & Privacy System Tuning${NC}"
    echo -e "${CYAN}========================================================${NC}"

    # Capture initial baseline values before first modification
    save_tuning_baseline

    # 1. Enable Google BBR and Performance sysctls
    enable_bbr

    # 2. Memory & Swappiness Optimization
    enable_swappiness

    # 3. Kernel Privacy & Anti-Leak Sysctls
    enable_kernel_hardening

    # 4. Prevent DHCP Hostname Leakage in NetworkManager
    enable_dhcp_privacy

    # 5. Optional: Disable slow boot delays and background broadcast daemons
    local disable_services=0
    if [ "${FORCE_YES:-0}" -eq 1 ]; then
        disable_services=0
    elif [ -t 0 ]; then
        echo ""
        log_warn "Disabling avahi-daemon/cups-browsed disables mDNS discovery and breaks dynamically discovered (dnssd://) network printers."
        read -r -p "Disable discovery background daemons (avahi-daemon, cups-browsed, ModemManager)? [y/N]: " daemon_ans
        if [[ "$daemon_ans" =~ ^[Yy]$ ]]; then
            disable_services=1
        else
            log_info "Keeping background discovery daemons active."
        fi
    fi

    if [ "$disable_services" -eq 1 ]; then
        log_info "Optimizing startup services and eliminating broadcast daemons..."
        disable_nm_wait_online
        systemctl stop avahi-daemon.service avahi-daemon.socket 2>/dev/null || true
        systemctl disable avahi-daemon.service avahi-daemon.socket 2>/dev/null && echo "  - Disabled avahi-daemon & avahi-daemon.socket (mDNS stopped)." || true
        systemctl stop cups-browsed 2>/dev/null || true
        systemctl disable cups-browsed 2>/dev/null && echo "  - Disabled cups-browsed (UDP 631 printer polling stopped)." || true
        systemctl stop ModemManager 2>/dev/null || true
        systemctl disable ModemManager 2>/dev/null && echo "  - Disabled ModemManager (cellular serial scanner stopped)." || true
    fi

    # 6. ZRAM Compressed RAM Swap
    enable_zram

    echo ""
    log_success "All system performance and privacy tunings applied successfully!"
    echo -e "${CYAN}========================================================${NC}"
}

revert_system_tuning() {
    check_root "tune" "revert"

    log_warn "Reverting performance & privacy tunings to Linux Mint defaults..."
    disable_bbr
    disable_swappiness
    disable_kernel_hardening
    disable_dhcp_privacy

    local b_avahi=0 b_cups=0 b_modem=0 b_wait=1
    if [ -f "$BASELINE_SYSCTL" ]; then
        # shellcheck disable=SC1090
        . "$BASELINE_SYSCTL"
        b_avahi="${BASE_AVAHI_ACTIVE:-0}"
        b_cups="${BASE_CUPS_ACTIVE:-0}"
        b_modem="${BASE_MODEM_ACTIVE:-0}"
        b_wait="${BASE_NM_WAIT_ACTIVE:-1}"
    fi

    if [ "$b_wait" -eq 1 ]; then
        enable_nm_wait_online
    else
        disable_nm_wait_online
    fi

    if [ "$b_avahi" -eq 1 ]; then
        systemctl unmask avahi-daemon.service avahi-daemon.socket 2>/dev/null || true
        systemctl enable --now avahi-daemon.socket avahi-daemon.service 2>/dev/null || true
    else
        systemctl stop avahi-daemon.service avahi-daemon.socket 2>/dev/null || true
        systemctl disable avahi-daemon.service avahi-daemon.socket 2>/dev/null || true
    fi

    if [ "$b_cups" -eq 1 ]; then
        systemctl unmask cups-browsed 2>/dev/null || true
        systemctl enable --now cups-browsed 2>/dev/null || true
    else
        systemctl stop cups-browsed 2>/dev/null || true
        systemctl disable cups-browsed 2>/dev/null || true
    fi

    if [ "$b_modem" -eq 1 ]; then
        systemctl unmask ModemManager 2>/dev/null || true
        systemctl enable --now ModemManager 2>/dev/null || true
    else
        systemctl stop ModemManager 2>/dev/null || true
        systemctl disable ModemManager 2>/dev/null || true
    fi

    disable_zram
    rm -f "$BASELINE_SYSCTL"

    nmcli general reload 2>/dev/null || systemctl reload NetworkManager 2>/dev/null || true
    log_success "System settings reverted to baseline defaults."
}

# ==============================================================================
# MODULE 8: IPv6 Protocol Control & Toggle
# ==============================================================================

show_ipv6_status() {
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}                  IPv6 Protocol Status${NC}"
    echo -e "${CYAN}========================================================${NC}"
    local ipv6_dis
    ipv6_dis=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo "0")
    if [ "$ipv6_dis" -eq 1 ]; then
        echo -e "System IPv6 State : ${RED}DISABLED (Blocked)${NC}"
        echo "  - No IPv6 traffic will be transmitted or received."
        echo "  - Loopback ::1 remains preserved for local service sockets."
    else
        echo -e "System IPv6 State : ${GREEN}ENABLED (Active)${NC}"
        local addrs
        addrs=$(ip -6 addr show scope global 2>/dev/null | awk '/inet6/ {print $2}')
        if [ -n "$addrs" ]; then
            echo "  - Active Global IPv6 Addresses:"
            echo "$addrs" | sed 's/^/      /'
        else
            echo "  - No global IPv6 addresses currently assigned."
        fi
    fi
    if [ -f "$IPV6_SYSCTL_CONF" ]; then
        echo "Configuration     : Config file present in $IPV6_SYSCTL_CONF"
    else
        echo "Configuration     : Standard system defaults"
    fi
    echo -e "${CYAN}========================================================${NC}"
}

disable_ipv6() {
    check_root "ipv6" "disable"

    log_info "Disabling IPv6 system-wide (preserving loopback ::1)..."
    mkdir -p /etc/sysctl.d
    cat << 'EOF' > "$IPV6_SYSCTL_CONF"
# Disable IPv6 system-wide (mint-admin - loopback ::1 preserved)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 0
EOF
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null 2>&1 || true
    for iface in /proc/sys/net/ipv6/conf/*; do
        if [ -d "$iface" ] && [ "$(basename "$iface")" != "lo" ]; then
            echo 1 > "$iface/disable_ipv6" 2>/dev/null || true
        fi
    done
    nmcli general reload 2>/dev/null || true

    log_success "IPv6 has been DISABLED across network interfaces (localhost ::1 preserved)."
}

enable_ipv6() {
    check_root "ipv6" "enable"

    log_info "Enabling IPv6 system-wide..."
    rm -f "$IPV6_SYSCTL_CONF"
    sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null 2>&1 || true
    for iface in /proc/sys/net/ipv6/conf/*; do
        [ -d "$iface" ] && echo 0 > "$iface/disable_ipv6" 2>/dev/null || true
    done
    nmcli general reload 2>/dev/null || true

    log_success "IPv6 has been ENABLED across all network interfaces."
}

toggle_ipv6() {
    local ipv6_dis
    ipv6_dis=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo "0")
    if [ "$ipv6_dis" -eq 1 ]; then
        enable_ipv6
    else
        disable_ipv6
    fi
}

# ==============================================================================
# Guided Optimization Wizard
# ==============================================================================

run_guided_wizard() {
    check_root "wizard"
    clear 2>/dev/null || true
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}       Laptop Linux Optimizer — Guided Step-by-Step Setup Wizard${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "This wizard configures your laptop in the recommended operational order:"
    echo -e "  [Step 1/5] System & Package Updates     (APT & Flatpaks)"
    echo -e "  [Step 2/5] Battery Charge Limiter       (60% / 80% / 100% threshold)"
    echo -e "  [Step 3/5] Encrypted DNS Configuration  (dnscrypt-proxy DoH / Relays / Tor)"
    echo -e "  [Step 4/5] Performance & ZRAM Tuning    (TCP BBR, ZRAM 50%, Swappiness 100)"
    echo -e "  [Step 5/5] Privacy & Activity Scrub     (Caches, history, DNS logs)"
    echo -e "  [Finish]   Final Verification & Reboot Advisory"
    echo -e "${CYAN}======================================================================${NC}"
    echo ""
    read -rp "Press Enter to begin or Ctrl+C to abort..." _
    echo ""

    # STEP 1: Updates
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 1/5] System & Package Updates${NC}"
    echo -e "Updating packages first ensures core libraries and kernel are current."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "Run system updates and package cleanup? [Y/n]: " ans_up
    if [[ ! "$ans_up" =~ ^[Nn] ]]; then
        update_and_clean
    else
        log_info "Skipping Step 1 (Updates)."
    fi
    echo ""

    # STEP 2: Battery Management
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 2/5] Battery Diagnostics & Charge Threshold${NC}"
    echo -e "Limiting battery charge to 80% significantly reduces chemical wear."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    show_battery_status
    echo ""
    read -rp "Configure persistent battery charge limiter? [Y/n]: " ans_bat
    if [[ ! "$ans_bat" =~ ^[Nn] ]]; then
        echo "Preset Modes:"
        echo "  60  - Maximum Lifespan (constantly plugged into AC charger)"
        echo "  80  - Balanced (Recommended everyday longevity)"
        echo "  100 - Full Capacity (maximum portable runtime for travel)"
        read -rp "Enter target percentage [60/80/100, default: 80]: " bval
        bval="${bval:-80}"
        if [[ "$bval" =~ ^[0-9]+$ ]] && [ "$bval" -ge 20 ] && [ "$bval" -le 100 ]; then
            install_battery_service "$bval"
        else
            log_warn "Invalid threshold entered; defaulting to 80%."
            install_battery_service 80
        fi
    else
        log_info "Skipping Step 2 (Battery Limiter)."
    fi
    echo ""

    # STEP 3: Encrypted DNS
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 3/5] Encrypted DNS Configuration (dnscrypt-proxy)${NC}"
    echo -e "Encrypts DNS queries to prevent ISP tracking, with fallback-leak blocking."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "Configure Encrypted DNS now? [Y/n]: " ans_dns
    if [[ ! "$ans_dns" =~ ^[Nn] ]]; then
        interactive_dns_menu
    else
        log_info "Skipping Step 3 (DNS)."
    fi
    echo ""

    # STEP 4: Performance & ZRAM Tuning
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 4/5] Performance & ZRAM Tuning${NC}"
    echo -e "Enables TCP BBR congestion control, ZRAM compressed swap (50% RAM with zstd),"
    echo -e "swappiness 100 (optimal for 16GB laptops), and DHCP hostname privacy."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "Apply performance, ZRAM, and kernel tunings? [Y/n]: " ans_tune
    if [[ ! "$ans_tune" =~ ^[Nn] ]]; then
        apply_system_tuning
    else
        log_info "Skipping Step 4 (Tuning)."
    fi
    echo ""

    # STEP 5: Privacy Scrubbing
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 5/5] Privacy & Activity Scrubbing${NC}"
    echo -e "Purges browser caches, recent documents, preview thumbnails, and DNS query logs."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "Perform privacy and cache scrub now? [Y/n]: " ans_priv
    if [[ ! "$ans_priv" =~ ^[Nn] ]]; then
        clean_privacy "privacy"
    else
        log_info "Skipping Step 5 (Privacy Scrub)."
    fi
    echo ""

    # FINISH & REBOOT ADVISORY
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${GREEN}${BOLD}✓ Guided Laptop Optimization Complete!${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "All selected configurations, hardware limits, and tunings have been applied."
    echo -e "Because new kernel sysctls, ZRAM swap, and network drop-ins were installed,"
    echo -e "a system reboot is ${BOLD}strongly recommended${NC} to ensure all services start clean."
    echo ""
    read -rp "Would you like to reboot the laptop now? [y/N]: " ans_reboot
    if [[ "$ans_reboot" =~ ^[Yy]$ ]]; then
        log_info "Rebooting system now..."
        reboot
    else
        log_info "Reboot skipped. Please remember to reboot when convenient."
    fi
}

# ==============================================================================
# MODULE 9: Profile Presets, System Status & Advisory
# ==============================================================================

get_active_preset() {
    if [ -f "$PROFILE_CONF" ]; then
        local p
        p=$(grep "^PROFILE=" "$PROFILE_CONF" 2>/dev/null | cut -d= -f2 || echo "")
        [ -n "$p" ] && echo "$p" && return
    fi
    local thresh bbr zram
    thresh=$(cat /sys/class/power_supply/BAT*/charge_control_end_threshold 2>/dev/null | head -n1 || echo "")
    bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
    zram=0
    swapon --show 2>/dev/null | grep -q "zram" && zram=1

    if [ "$thresh" = "60" ] && [ "$bbr" = "bbr" ] && [ "$zram" -eq 1 ]; then
        echo "desk"
    elif [ "$thresh" = "80" ] && [ "$bbr" = "bbr" ] && [ "$zram" -eq 1 ]; then
        echo "balanced"
    elif [ "$thresh" = "100" ]; then
        echo "travel"
    else
        echo "custom"
    fi
}

status_get_preset() {
    local preset
    preset=$(get_active_preset)
    case "$preset" in
        desk) echo "Desk / Docked (60% Limit + BBR + ZRAM)" ;;
        balanced) echo "Balanced Daily (80% Limit + BBR + ZRAM)" ;;
        travel) echo "Travel / Mobile (100% Full Capacity)" ;;
        *) echo "Custom Configuration" ;;
    esac
}

status_get_battery() {
    local bat
    bat=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1 || true)
    if [ -z "$bat" ] || [ ! -d "$bat" ]; then
        echo "No Battery Detected"
        return
    fi
    local cap state thresh
    cap=$(cat "$bat/capacity" 2>/dev/null || echo "?")
    state=$(cat "$bat/status" 2>/dev/null || echo "Unknown")
    thresh=$(cat "$bat/charge_control_end_threshold" 2>/dev/null || echo "100")
    local persist="Session"
    if [ -f "$BATTERY_SERVICE" ] && systemctl is-enabled --quiet asus-battery-limit.service 2>/dev/null; then
        persist="Persistent"
    fi
    echo "${thresh}% Limit [${persist}] | ${cap}% (${state})"
}

status_get_zram() {
    if swapon --show 2>/dev/null | grep -q "zram"; then
        local sz swap
        sz=$(swapon --show 2>/dev/null | grep "zram" | awk '{print $3}' | head -n1)
        swap=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "60")
        echo "ACTIVE (${sz}, swappiness ${swap})"
    else
        echo "INACTIVE"
    fi
}

status_get_bbr() {
    local cc qdisc
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "Unknown")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "Unknown")
    if [ "$cc" = "bbr" ]; then
        echo "BBR (Optimal, qdisc: ${qdisc})"
    else
        echo "${cc} (Legacy)"
    fi
}

status_get_dns() {
    if systemctl is-active --quiet dnscrypt-proxy.service 2>/dev/null; then
        local svr="Encrypted"
        if [ -f "$DNS_CONFIG" ]; then
            if awk '/^\[/{exit} /proxy =/{found=1} END{exit !found}' "$DNS_CONFIG" 2>/dev/null; then
                svr="Tor Onion DNS (127.0.2.1)"
            elif grep -q "routes = \[{ server_name='\*'" "$DNS_CONFIG" 2>/dev/null; then
                svr="Anonymized Relays (127.0.2.1)"
            else
                local sname
                sname=$(grep -E "^server_names =" "$DNS_CONFIG" 2>/dev/null | cut -d= -f2- | tr -d "[] \"'" | tr "," " " | awk '{print $1}')
                svr="${sname:-dnscrypt-proxy} (127.0.2.1)"
            fi
        fi
        echo "ACTIVE: ${svr}"
    else
        echo "Standard DHCP / NetworkManager"
    fi
}

status_get_mac() {
    if [ -f "$NM_MAC_CONF" ] && grep -q "wifi.cloned-mac-address=random" "$NM_MAC_CONF" 2>/dev/null; then
        echo "PERSISTENT (Cloned Random)"
    else
        echo "DEFAULT (Hardware MAC)"
    fi
}

status_get_timer() {
    if [ -f "$OPTIMIZER_TIMER" ] && systemctl is-enabled --quiet mint-optimizer.timer 2>/dev/null; then
        echo "ACTIVE (Weekly Sun 03:00)"
    else
        echo "DISABLED"
    fi
}

status_get_ipv6() {
    local dis
    dis=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo "0")
    if [ "$dis" -eq 1 ]; then
        echo "BLOCKED / DISABLED"
    else
        echo "ENABLED"
    fi
}

status_get_wait_online() {
    if systemctl is-enabled --quiet NetworkManager-wait-online.service 2>/dev/null; then
        echo "ENABLED (~7s boot delay)"
    else
        echo "DISABLED (Fast boot)"
    fi
}

status_get_swappiness() {
    local sw vfs
    sw=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "60")
    vfs=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null || echo "100")
    if [ "$sw" -eq 100 ]; then
        echo "100/50 (Optimized for ZRAM)"
    else
        echo "${sw}/${vfs} (Default)"
    fi
}

status_get_dhcp() {
    if command -v nmcli &>/dev/null; then
        local active_uuid
        active_uuid=$(nmcli -t -f UUID,TYPE connection show --active 2>/dev/null | grep -E ':(802-11-wireless|802-3-ethernet)' | head -n1 | cut -d: -f1 || true)
        if [ -n "$active_uuid" ]; then
            local send_host
            send_host=$(nmcli -g ipv4.dhcp-send-hostname connection show "$active_uuid" 2>/dev/null || echo "yes")
            if [ "$send_host" = "no" ] || [ "$send_host" = "0" ] || [ "$send_host" = "false" ]; then
                echo "BLOCKED (Protected)"
                return
            else
                echo "EXPOSED (Leaking)"
                return
            fi
        fi
    fi
    if [ -f /var/lib/mint-admin/dhcp-privacy-enabled ]; then
        echo "BLOCKED (Protected)"
    else
        echo "EXPOSED (Leaking)"
    fi
}

status_get_kernel_privacy() {
    local dmesg_r kptr_r
    dmesg_r=$(cat /proc/sys/kernel/dmesg_restrict 2>/dev/null || echo "0")
    kptr_r=$(cat /proc/sys/kernel/kptr_restrict 2>/dev/null || echo "0")
    if [ "$dmesg_r" -ge 1 ] && [ "$kptr_r" -ge 1 ]; then
        echo "HARDENED (Root only)"
    else
        echo "PERMISSIVE (Default)"
    fi
}

status_get_avahi() {
    if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
        echo "ACTIVE (mDNS)"
    else
        echo "DISABLED"
    fi
}

status_get_cups() {
    if systemctl is-active --quiet cups-browsed 2>/dev/null; then
        echo "ACTIVE (UDP 631)"
    else
        echo "DISABLED"
    fi
}

status_get_modem() {
    if systemctl is-active --quiet ModemManager 2>/dev/null; then
        echo "ACTIVE"
    else
        echo "DISABLED"
    fi
}

check_pending_updates() {
    local count=0
    if [ -x "/usr/lib/update-notifier/apt-check" ]; then
        count=$(/usr/lib/update-notifier/apt-check 2>/dev/null | cut -d';' -f1 || echo 0)
    else
        count=$(apt-get -s -u upgrade 2>/dev/null | grep -E '^[0-9]+ upgraded' | awk '{print $1}' || echo 0)
    fi
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    echo "$count"
}

check_cleanable_cache() {
    local total_kb=0
    local apt_kb=0
    if [ -d "/var/cache/apt/archives" ]; then
        apt_kb=$(du -sk /var/cache/apt/archives 2>/dev/null | awk '{print $1}' || echo 0)
    fi
    [[ "$apt_kb" =~ ^[0-9]+$ ]] || apt_kb=0
    total_kb=$(( total_kb + apt_kb ))

    local j_kb=0
    if command -v journalctl &>/dev/null; then
        local j_str
        j_str=$(journalctl --disk-usage 2>/dev/null || echo "")
        if [[ "$j_str" =~ ([0-9]+(\.[0-9]+)?)([MG]) ]]; then
            local val="${BASH_REMATCH[1]}"
            local unit="${BASH_REMATCH[3]}"
            if [ "$unit" = "M" ]; then
                j_kb=$(awk "BEGIN {print int($val * 1024)}")
            elif [ "$unit" = "G" ]; then
                j_kb=$(awk "BEGIN {print int($val * 1048576)}")
            fi
        fi
    fi
    [[ "$j_kb" =~ ^[0-9]+$ ]] || j_kb=0
    if [ "$j_kb" -gt 102400 ]; then
        total_kb=$(( total_kb + (j_kb - 102400) ))
    fi
    echo "$total_kb"
}

apply_preset() {
    local preset="${1:-}"
    check_root "preset" "apply" "$preset"

    case "$preset" in
        desk|docked)
            log_info "Applying 'Desk / Docked' profile preset..."
            install_battery_service 60
            apply_system_tuning
            mkdir -p "$(dirname "$PROFILE_CONF")"
            echo "PROFILE=desk" > "$PROFILE_CONF"
            log_success "Profile preset 'Desk / Docked' applied (60% battery threshold, BBR, ZRAM)."
            ;;
        balanced|daily|default)
            log_info "Applying 'Balanced Daily' profile preset..."
            install_battery_service 80
            apply_system_tuning
            mkdir -p "$(dirname "$PROFILE_CONF")"
            echo "PROFILE=balanced" > "$PROFILE_CONF"
            log_success "Profile preset 'Balanced Daily' applied (80% battery threshold, BBR, ZRAM)."
            ;;
        travel|mobile|full)
            log_info "Applying 'Travel / Mobile' profile preset..."
            set_battery_threshold 100
            mkdir -p "$(dirname "$PROFILE_CONF")"
            echo "PROFILE=travel" > "$PROFILE_CONF"
            log_success "Profile preset 'Travel / Mobile' applied (100% full capacity for portable travel)."
            ;;
        custom|reset)
            rm -f "$PROFILE_CONF"
            log_info "Profile preset reset to Custom."
            ;;
        *)
            log_err "Unknown profile preset: '$preset'"
            echo "Available presets: desk (60%), balanced (80%), travel (100%), custom"
            exit 1
            ;;
    esac
}

show_preset_status() {
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}               Profile Preset Status${NC}"
    echo -e "${CYAN}========================================================${NC}"
    local p
    p=$(status_get_preset)
    echo -e "Active Profile Preset : ${GREEN}${BOLD}${p}${NC}"
    echo ""
    echo "Available Presets:"
    echo "  1) desk     : 60% battery limit, BBR congestion control, ZRAM compressed swap."
    echo "                Ideal for laptops permanently or frequently on AC power."
    echo "  2) balanced : 80% battery limit, BBR congestion control, ZRAM compressed swap."
    echo "                Recommended default balance between battery health and mobile runtime."
    echo "  3) travel   : 100% full charge capacity."
    echo "                Maximum battery runtime when traveling away from outlets."
    echo "  4) custom   : Individual subsystem settings configured independently."
    echo ""
    echo "To switch presets: sudo $0 preset apply <desk|balanced|travel>"
    echo -e "${CYAN}========================================================${NC}"
}

interactive_preset_menu() {
    clear 2>/dev/null || true
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}             Laptop Linux Optimizer — Profile Presets Switcher        ${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "Current Active Profile: ${GREEN}${BOLD}$(status_get_preset)${NC}"
    echo ""
    echo -e "Select a preset mode:"
    echo -e "  1) ${BOLD}Desk / Docked${NC}    | 60% battery limit + BBR + ZRAM (Constantly plugged in)"
    echo -e "  2) ${BOLD}Balanced Daily${NC}   | 80% battery limit + BBR + ZRAM (Everyday longevity - Recommended)"
    echo -e "  3) ${BOLD}Travel / Mobile${NC}  | 100% battery capacity (Maximum battery runtime on the go)"
    echo -e "  4) ${BOLD}Custom / Reset${NC}   | Mark profile as custom"
    echo -e "  5) Cancel / Return"
    echo -e "${CYAN}======================================================================${NC}"
    read -rp "Select preset [1-4, 5 to Cancel]: " pchoice
    case "$pchoice" in
        1|desk) apply_preset "desk" ;;
        2|balanced) apply_preset "balanced" ;;
        3|travel) apply_preset "travel" ;;
        4|custom) apply_preset "custom" ;;
        *) log_info "Preset switch cancelled." ;;
    esac
}

show_maintenance_advisory() {
    local updates cleanable_kb
    updates=$(check_pending_updates)
    cleanable_kb=$(check_cleanable_cache)
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}           System Updates & Housekeeping Advisory${NC}"
    echo -e "${CYAN}========================================================${NC}"
    if [ "$updates" -gt 0 ]; then
        echo -e "Pending Package Updates : ${YELLOW}${BOLD}${updates} packages available${NC}"
    else
        echo -e "Pending Package Updates : ${GREEN}All packages up to date${NC}"
    fi

    if [ "$cleanable_kb" -gt 50000 ]; then
        echo -e "Cleanable Caches & Logs : ${YELLOW}${BOLD}$(format_kb "$cleanable_kb") reclaimable${NC}"
    else
        echo -e "Cleanable Caches & Logs : ${GREEN}System storage is lean (~$(format_kb "$cleanable_kb"))${NC}"
    fi
    echo -e "${CYAN}========================================================${NC}"
}

# ==============================================================================
# Master Interactive Terminal User Interface (TUI Dashboard)
# ==============================================================================

FIRST_PROMPT_DONE=0

run_menu_action() {
    local rc=0
    ( "$@" ) || rc=$?
    if [ $rc -ne 0 ]; then
        echo ""
        log_warn "Action finished with exit code $rc."
    fi
    echo ""
    if [ -t 0 ]; then
        read -rp "Press Enter to return to Dashboard..." _ || true
    fi
}

run_whiptail_action() {
    local rc=0
    ( "$@" ) || rc=$?
    if [ $rc -ne 0 ]; then
        echo ""
        log_warn "Action finished with exit code $rc."
    fi
    echo ""
    if [ -t 0 ]; then
        read -rp "Press Enter to return..." _ || true
    fi
}

show_system_summary() {
    local cur_preset cur_bat cur_zram cur_bbr cur_dns cur_mac cur_timer cur_ipv6 cur_nm
    cur_preset=$(status_get_preset)
    cur_bat=$(status_get_battery)
    cur_zram=$(status_get_zram)
    cur_bbr=$(status_get_bbr)
    cur_dns=$(status_get_dns)
    cur_mac=$(status_get_mac)
    cur_timer=$(status_get_timer)
    cur_ipv6=$(status_get_ipv6)
    cur_nm=$(status_get_wait_online)

    local updates="${1:-}"
    local cleanable_kb="${2:-}"
    [ -z "$updates" ] && updates=$(check_pending_updates)
    [ -z "$cleanable_kb" ] && cleanable_kb=$(check_cleanable_cache)

    echo -e "${CYAN}┌──────────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}  ${BOLD}${GREEN}⚡ Laptop Linux Optimizer — Comprehensive System Status Summary${NC}             ${CYAN}│${NC}"
    echo -e "${CYAN}├──────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC}  ${BOLD}[ HARDWARE & PERFORMANCE ]${NC}"
    echo -e "${CYAN}│${NC}  • Active Profile Preset: ${GREEN}${BOLD}${cur_preset}${NC}"
    echo -e "${CYAN}│${NC}  • Battery Diagnostics  : ${CYAN}${cur_bat}${NC}"
    echo -e "${CYAN}│${NC}  • ZRAM Compressed Swap : ${GREEN}${cur_zram}${NC}"
    echo -e "${CYAN}│${NC}  • TCP Congestion (BBR) : ${GREEN}${cur_bbr}${NC}"
    echo -e "${CYAN}│${NC}  • NM Boot Speed Delay  : ${GREEN}${cur_nm}${NC}"
    echo -e "${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${BOLD}[ SECURITY & NETWORK PRIVACY ]${NC}"
    echo -e "${CYAN}│${NC}  • Encrypted DNS Status : ${BLUE}${cur_dns}${NC}"
    echo -e "${CYAN}│${NC}  • Network MAC Address  : ${MAGENTA}${cur_mac}${NC}"
    echo -e "${CYAN}│${NC}  • IPv6 Protocol State  : ${cur_ipv6}"
    echo -e "${CYAN}│${NC}  • Automated Background : ${cur_timer}"
    echo -e "${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${BOLD}[ MAINTENANCE & STORAGE ADVISORY ]${NC}"
    if [ "$updates" -gt 0 ]; then
        echo -e "${CYAN}│${NC}  • Package Updates      : ${YELLOW}${BOLD}${updates} package update(s) ready to install${NC}"
    else
        echo -e "${CYAN}│${NC}  • Package Updates      : ${GREEN}All packages up to date${NC}"
    fi
    if [ "$cleanable_kb" -gt 50000 ]; then
        echo -e "${CYAN}│${NC}  • Cleanable Storage    : ${YELLOW}${BOLD}~$(format_kb "$cleanable_kb")${NC} in cleanable caches & logs"
    else
        echo -e "${CYAN}│${NC}  • Cleanable Storage    : ${GREEN}System storage is lean (~$(format_kb "$cleanable_kb"))${NC}"
    fi
    echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
}

# ------------------------------------------------------------------------------
# Whiptail / Dialog Curses Submenus
# ------------------------------------------------------------------------------

whiptail_battery_menu() {
    local tui_cmd="$1"
    while true; do
        local b_info
        b_info=$(status_get_battery)
        local bchoice
        bchoice=$($tui_cmd --title "Battery Diagnostics & Limiter Configuration" \
            --menu "Current: $b_info\nSelect battery action:" 16 70 5 \
            "1" "View Detailed Battery Health & Diagnostics" \
            "2" "Set Charge Limit (e.g. 60%, 80%, 100%)" \
            "3" "Install Persistent Charge Limiter Service" \
            "4" "Uninstall Limiter Service (Restore 100%)" \
            "Q" "Return to Main Menu" \
            3>&1 1>&2 2>&3 || echo "Q")

        case "$bchoice" in
            1) show_battery_status; read -rp "Press Enter to return..." _ ;;
            2)
                local bval
                bval=$($tui_cmd --title "Set Charge Limit" --inputbox "Enter target percentage [20-100]:" 10 60 "80" 3>&1 1>&2 2>&3 || echo "")
                if [ -n "$bval" ]; then
                    run_whiptail_action set_battery_threshold "$bval"
                fi
                ;;
            3)
                local bval
                bval=$($tui_cmd --title "Install Limiter Service" --inputbox "Enter persistent target limit [20-100]:" 10 60 "80" 3>&1 1>&2 2>&3 || echo "")
                if [ -n "$bval" ]; then
                    run_whiptail_action install_battery_service "$bval"
                fi
                ;;
            4)
                run_whiptail_action uninstall_battery_service
                ;;
            Q|"") break ;;
        esac
    done
}

whiptail_mac_menu() {
    local tui_cmd="$1"
    while true; do
        local m_info
        m_info=$(status_get_mac)
        local mchoice
        mchoice=$($tui_cmd --title "Network MAC Randomization & Spoofing" \
            --menu "Current State: $m_info\nSelect MAC action:" 16 70 5 \
            "1" "View Physical Interfaces & Current MACs" \
            "2" "Randomize MAC Addresses Now (Instant Spoof)" \
            "3" "Enable Persistent NetworkManager Randomization" \
            "4" "Disable Persistent Auto-Randomization" \
            "Q" "Return to Main Menu" \
            3>&1 1>&2 2>&3 || echo "Q")

        case "$mchoice" in
            1) show_mac_status; read -rp "Press Enter to return..." _ ;;
            2) run_whiptail_action randomize_mac ;;
            3) run_whiptail_action enable_mac_randomization ;;
            4) run_whiptail_action disable_mac_randomization ;;
            Q|"") break ;;
        esac
    done
}

whiptail_timer_menu() {
    local tui_cmd="$1"
    while true; do
        local tm_info
        tm_info=$(status_get_timer)
        local tmchoice
        tmchoice=$($tui_cmd --title "Automated Weekly Maintenance Timer" \
            --menu "Timer State: $tm_info\nSelect timer action:" 15 70 4 \
            "1" "View Timer Status & Recent Run Logs" \
            "2" "Install / Enable Weekly Timer (Sun 03:00)" \
            "3" "Uninstall / Disable Weekly Timer" \
            "Q" "Return to Main Menu" \
            3>&1 1>&2 2>&3 || echo "Q")

        case "$tmchoice" in
            1) show_timer_status; read -rp "Press Enter to return..." _ ;;
            2) run_whiptail_action install_weekly_timer ;;
            3) run_whiptail_action uninstall_weekly_timer ;;
            Q|"") break ;;
        esac
    done
}

whiptail_tuning_menu() {
    local tui_cmd="$1"
    while true; do
        local cur_nm cur_bbr cur_swap cur_zram cur_dhcp cur_kern cur_avahi cur_cups cur_modem
        cur_nm=$(status_get_wait_online)
        cur_bbr=$(status_get_bbr)
        cur_swap=$(status_get_swappiness)
        cur_zram=$(status_get_zram)
        cur_dhcp=$(status_get_dhcp)
        cur_kern=$(status_get_kernel_privacy)
        cur_avahi=$(status_get_avahi)
        cur_cups=$(status_get_cups)
        cur_modem=$(status_get_modem)

        local tchoice
        tchoice=$($tui_cmd --title "Performance, Privacy & Startup Toggles" \
            --menu "Select an option to toggle or configure:" 24 78 13 \
            "1" "NM Wait-Online Delay   [$cur_nm]" \
            "2" "TCP Congestion Control  [$cur_bbr]" \
            "3" "Swappiness & VFS Cache  [$cur_swap]" \
            "4" "ZRAM Compressed Swap    [$cur_zram]" \
            "5" "DHCP Hostname Leak      [$cur_dhcp]" \
            "6" "Kernel Memory Privacy   [$cur_kern]" \
            "7" "Avahi mDNS Daemon       [$cur_avahi]" \
            "8" "CUPS Network Polling    [$cur_cups]" \
            "9" "ModemManager Daemon     [$cur_modem]" \
            "B" "Toggle All 3 Broadcast Daemons" \
            "A" "Apply All Performance & Privacy Tunings" \
            "R" "Revert All Tunings to System Baseline" \
            "S" "Display Full Status Report" \
            3>&1 1>&2 2>&3 || echo "Q")

        case "$tchoice" in
            1) run_whiptail_action toggle_nm_wait_online ;;
            2) run_whiptail_action toggle_bbr ;;
            3) run_whiptail_action toggle_swappiness ;;
            4) run_whiptail_action toggle_zram ;;
            5) run_whiptail_action toggle_dhcp_privacy ;;
            6) run_whiptail_action toggle_kernel_hardening ;;
            7) run_whiptail_action toggle_avahi ;;
            8) run_whiptail_action toggle_cups_browsed ;;
            9) run_whiptail_action toggle_modemmanager ;;
            B) run_whiptail_action toggle_broadcast_daemons ;;
            A) run_whiptail_action apply_system_tuning ;;
            R) run_whiptail_action revert_system_tuning ;;
            S) show_tuning_status; read -rp "Press Enter to continue..." _ ;;
            Q|"") break ;;
        esac
    done
}

show_whiptail_tui() {
    local tui_cmd=""
    if command -v whiptail &>/dev/null; then
        tui_cmd="whiptail"
    elif command -v dialog &>/dev/null; then
        tui_cmd="dialog"
    else
        log_warn "Neither whiptail nor dialog found; falling back to ANSI dashboard."
        return 1
    fi

    while true; do
        local p_info b_info z_info bbr_info nm_info
        p_info=$(status_get_preset)
        b_info=$(status_get_battery)
        z_info=$(status_get_zram)
        bbr_info=$(status_get_bbr)
        nm_info=$(status_get_wait_online)

        local choice
        choice=$($tui_cmd --title "Laptop Linux Optimizer & Admin Suite (v$VERSION)" \
            --backtitle "Preset: $p_info | Bat: $b_info | ZRAM: $z_info | BBR: $bbr_info | NM Boot: $nm_info" \
            --menu "Select a subsystem or management action below:" 22 78 13 \
            "P"  "Switch Profile Preset (Desk / Balanced / Travel)" \
            "1"  "Guided Laptop Optimization Wizard (5-Step Setup)" \
            "2"  "Update All Packages & Sweep Clean (APT + Flatpak)" \
            "3"  "System Housekeeping (Caches, journals, temp)" \
            "4"  "Battery Diagnostics & Charge Limiter Configuration" \
            "5"  "Encrypted DNS Manager (DoH / Relays / Tor)" \
            "6"  "Network MAC Randomization & Spoofing" \
            "7"  "Performance, Privacy & Startup Toggles (NM Boot, BBR, ZRAM)" \
            "8"  "Privacy & Anti-Tracking Activity Scrub" \
            "9"  "Automated Weekly Maintenance Timer" \
            "10" "Toggle IPv6 Protocol (Enable / Disable)" \
            "11" "Complete Master Suite (All-In-One)" \
            "A"  "Switch to Curses / Ink Terminal Dashboard" \
            3>&1 1>&2 2>&3 || echo "Q")

        case "$choice" in
            P) interactive_preset_menu ;;
            1) run_whiptail_action run_guided_wizard ;;
            2) run_whiptail_action update_and_clean ;;
            3) run_whiptail_action run_optimizer ;;
            4) whiptail_battery_menu "$tui_cmd" ;;
            5) interactive_dns_menu ;;
            6) whiptail_mac_menu "$tui_cmd" ;;
            7) whiptail_tuning_menu "$tui_cmd" ;;
            8) run_whiptail_action clean_privacy "privacy" ;;
            9) whiptail_timer_menu "$tui_cmd" ;;
            10)
                local cur_st="ENABLED"
                [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 0)" -eq 1 ] && cur_st="DISABLED"
                local next_st="DISABLE"
                [ "$cur_st" = "DISABLED" ] && next_st="ENABLE"
                if $tui_cmd --title "IPv6 Protocol Toggle" --yesno "Current IPv6 State: $cur_st\n\nWould you like to toggle IPv6 ($next_st system-wide)?" 10 65; then
                    run_whiptail_action toggle_ipv6
                fi
                ;;
            11) run_whiptail_action run_complete_suite ;;
            A|Q|"") break ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Interactive Subsystem Ink / Curses Menus
# ------------------------------------------------------------------------------

interactive_battery_menu() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${CYAN}╭──────────────────────────────────────────────────────────────────────────────╮${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}${GREEN}🔋 BATTERY LIFESPAN & CHARGE LIMITER CONTROLS${NC}                               ${CYAN}│${NC}"
        echo -e "${CYAN}╰──────────────────────────────────────────────────────────────────────────────╯${NC}"
        show_battery_status
        echo -e "${CYAN}┌── BATTERY MANAGEMENT ACTIONS ────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[1]${NC} Set Session Charge Threshold  (e.g. 60%, 80%, 100%)"
        echo -e "${CYAN}│${NC}  ${BOLD}[2]${NC} Install Persistent Limiter    (Persists across reboot & sleep)"
        echo -e "${CYAN}│${NC}  ${BOLD}[3]${NC} Uninstall Limiter Service     (Restore full 100% capacity)"
        echo -e "${CYAN}│${NC}  ${BOLD}[0/Q]${NC} Return to Master Dashboard"
        echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        read -rp "Select an option [1-3, Q]: " bopt
        case "$bopt" in
            1)
                read -rp "Enter target percentage [20-100, default 80]: " bval
                bval="${bval:-80}"
                run_menu_action set_battery_threshold "$bval"
                ;;
            2)
                read -rp "Enter target persistent limit [20-100, default 80]: " bval
                bval="${bval:-80}"
                run_menu_action install_battery_service "$bval"
                ;;
            3)
                run_menu_action uninstall_battery_service
                ;;
            0|[Qq]|return|"") break ;;
            *) log_warn "Invalid selection."; sleep 1 ;;
        esac
    done
}

interactive_mac_menu() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${CYAN}╭──────────────────────────────────────────────────────────────────────────────╮${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}${MAGENTA}🕵️  NETWORK MAC RANDOMIZATION & HARDWARE PRIVACY${NC}                            ${CYAN}│${NC}"
        echo -e "${CYAN}╰──────────────────────────────────────────────────────────────────────────────╯${NC}"
        show_mac_status
        echo -e "${CYAN}┌── MAC ADDRESS ACTIONS ───────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[1]${NC} Randomize MAC Addresses Now  (Instant spoof on active interfaces)"
        echo -e "${CYAN}│${NC}  ${BOLD}[2]${NC} Enable Persistent Randomizer (NetworkManager auto-spoof on connect)"
        echo -e "${CYAN}│${NC}  ${BOLD}[3]${NC} Disable Persistent Spoofing  (Restore permanent hardware MAC)"
        echo -e "${CYAN}│${NC}  ${BOLD}[0/Q]${NC} Return to Master Dashboard"
        echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        read -rp "Select an option [1-3, Q]: " mopt
        case "$mopt" in
            1) run_menu_action randomize_mac ;;
            2) run_menu_action enable_mac_randomization ;;
            3) run_menu_action disable_mac_randomization ;;
            0|[Qq]|return|"") break ;;
            *) log_warn "Invalid selection."; sleep 1 ;;
        esac
    done
}

interactive_timer_menu() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${CYAN}╭──────────────────────────────────────────────────────────────────────────────╮${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}${BLUE}⏱️  AUTOMATED WEEKLY BACKGROUND MAINTENANCE TIMER${NC}                            ${CYAN}│${NC}"
        echo -e "${CYAN}╰──────────────────────────────────────────────────────────────────────────────╯${NC}"
        show_timer_status
        echo -e "${CYAN}┌── TIMER CONTROLS ────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[1]${NC} Install / Enable Weekly Maintenance Timer  (Runs Sundays at 03:00 AM)"
        echo -e "${CYAN}│${NC}  ${BOLD}[2]${NC} Uninstall / Disable Weekly Timer           (Remove systemd schedule)"
        echo -e "${CYAN}│${NC}  ${BOLD}[0/Q]${NC} Return to Master Dashboard"
        echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        read -rp "Select an option [1-2, Q]: " tmopt
        case "$tmopt" in
            1) run_menu_action install_weekly_timer ;;
            2) run_menu_action uninstall_weekly_timer ;;
            0|[Qq]|return|"") break ;;
            *) log_warn "Invalid selection."; sleep 1 ;;
        esac
    done
}

interactive_tuning_menu() {
    while true; do
        clear 2>/dev/null || true
        local cur_nm cur_bbr cur_swap cur_zram cur_dhcp cur_kern cur_avahi cur_cups cur_modem
        cur_nm=$(status_get_wait_online)
        cur_bbr=$(status_get_bbr)
        cur_swap=$(status_get_swappiness)
        cur_zram=$(status_get_zram)
        cur_dhcp=$(status_get_dhcp)
        cur_kern=$(status_get_kernel_privacy)
        cur_avahi=$(status_get_avahi)
        cur_cups=$(status_get_cups)
        cur_modem=$(status_get_modem)

        local nm_pill bbr_pill swap_pill zram_pill dhcp_pill kern_pill avahi_pill cups_pill modem_pill
        [[ "$cur_nm" =~ DISABLED ]] && nm_pill="${GREEN}[✓ FAST BOOT (DISABLED)]${NC}" || nm_pill="${YELLOW}[● ENABLED (~7s delay)]${NC}"
        [[ "$cur_bbr" =~ BBR ]] && bbr_pill="${GREEN}[✓ ACTIVE (BBR)]${NC}" || bbr_pill="${YELLOW}[○ $cur_bbr]${NC}"
        [[ "$cur_swap" =~ 100 ]] && swap_pill="${GREEN}[✓ OPTIMIZED (100/50)]${NC}" || swap_pill="${YELLOW}[○ DEFAULT]${NC}"
        [[ "$cur_zram" =~ ACTIVE ]] && zram_pill="${GREEN}[✓ ACTIVE]${NC}" || zram_pill="${YELLOW}[○ INACTIVE]${NC}"
        [[ "$cur_dhcp" =~ BLOCKED ]] && dhcp_pill="${GREEN}[✓ BLOCKED (Shielded)]${NC}" || dhcp_pill="${YELLOW}[○ EXPOSED (Leaking)]${NC}"
        [[ "$cur_kern" =~ HARDENED ]] && kern_pill="${GREEN}[✓ HARDENED]${NC}" || kern_pill="${YELLOW}[○ PERMISSIVE]${NC}"
        [[ "$cur_avahi" =~ DISABLED ]] && avahi_pill="${GREEN}[✓ DISABLED]${NC}" || avahi_pill="${YELLOW}[● ACTIVE (mDNS)]${NC}"
        [[ "$cur_cups" =~ DISABLED ]] && cups_pill="${GREEN}[✓ DISABLED]${NC}" || cups_pill="${YELLOW}[● ACTIVE (UDP 631)]${NC}"
        [[ "$cur_modem" =~ DISABLED ]] && modem_pill="${GREEN}[✓ DISABLED]${NC}" || modem_pill="${YELLOW}[● ACTIVE (Modem)]${NC}"

        echo -e "${CYAN}╭──────────────────────────────────────────────────────────────────────────────╮${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}${GREEN}⚡ PERFORMANCE, PRIVACY & STARTUP OPTIMIZATION TOGGLES${NC}                  ${CYAN}│${NC}"
        echo -e "${CYAN}╰──────────────────────────────────────────────────────────────────────────────╯${NC}"
        echo -e "${CYAN}┌── LIVE TOGGLES & SUBSYSTEM CONTROLS ─────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[1]${NC} NM Wait-Online Delay   : $nm_pill ⇄ Toggle Fast Boot"
        echo -e "${CYAN}│${NC}  ${BOLD}[2]${NC} TCP Congestion (BBR)   : $bbr_pill ⇄ Toggle BBR / Cubic"
        echo -e "${CYAN}│${NC}  ${BOLD}[3]${NC} Swappiness & VFS Cache : $swap_pill ⇄ Toggle 100/50 vs 60/100"
        echo -e "${CYAN}│${NC}  ${BOLD}[4]${NC} ZRAM Compressed Swap   : $zram_pill ⇄ Toggle 50% RAM zstd swap"
        echo -e "${CYAN}│${NC}  ${BOLD}[5]${NC} DHCP Hostname Privacy  : $dhcp_pill ⇄ Toggle Hostname Leak Shield"
        echo -e "${CYAN}│${NC}  ${BOLD}[6]${NC} Kernel Memory Privacy  : $kern_pill ⇄ Toggle dmesg/kptr restrict"
        echo -e "${CYAN}│${NC}  ${BOLD}[7]${NC} Avahi mDNS Daemon      : $avahi_pill ⇄ Toggle mDNS Broadcast"
        echo -e "${CYAN}│${NC}  ${BOLD}[8]${NC} CUPS Network Polling   : $cups_pill ⇄ Toggle UDP 631 Printer Poll"
        echo -e "${CYAN}│${NC}  ${BOLD}[9]${NC} ModemManager Daemon    : $modem_pill ⇄ Toggle Cellular Scanner"
        echo -e "${CYAN}│${NC}  ${BOLD}[B]${NC} Toggle All 3 Discovery Broadcast Daemons at once"
        echo -e "${CYAN}├──────────────────────────────────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[A]${NC} Apply All Performance & Privacy Tunings (One-click full setup)"
        echo -e "${CYAN}│${NC}  ${BOLD}[R]${NC} Revert All Tunings to Linux Mint Distro Baseline Defaults"
        echo -e "${CYAN}│${NC}  ${BOLD}[S]${NC} Display Detailed Diagnostics Status Report"
        echo -e "${CYAN}│${NC}  ${BOLD}[0/Q]${NC} Return to Master Dashboard"
        echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        read -rp "Select an option [1-9, B, A, R, S, Q]: " topt

        case "$topt" in
            1) run_menu_action toggle_nm_wait_online ;;
            2) run_menu_action toggle_bbr ;;
            3) run_menu_action toggle_swappiness ;;
            4) run_menu_action toggle_zram ;;
            5) run_menu_action toggle_dhcp_privacy ;;
            6) run_menu_action toggle_kernel_hardening ;;
            7) run_menu_action toggle_avahi ;;
            8) run_menu_action toggle_cups_browsed ;;
            9) run_menu_action toggle_modemmanager ;;
            [Bb]|daemons) run_menu_action toggle_broadcast_daemons ;;
            [Aa]|apply) run_menu_action apply_system_tuning ;;
            [Rr]|revert) run_menu_action revert_system_tuning ;;
            [Ss]|status)
                echo ""
                show_tuning_status
                echo ""
                read -rp "Press Enter to continue..." _
                ;;
            0|[Qq]|exit|return|"") break ;;
            *)
                log_warn "Invalid selection: '$topt'"
                sleep 1
                ;;
        esac
    done
}

show_tui_dashboard() {
    if [ ! -t 0 ]; then
        show_help
        return 0
    fi

    # Check for pending updates and cleanable caches
    local updates cleanable_kb
    updates=$(check_pending_updates)
    cleanable_kb=$(check_cleanable_cache)

    # Initial display on first interactive launch: complete summary of all statuses
    if [ "$FIRST_PROMPT_DONE" -eq 0 ]; then
        FIRST_PROMPT_DONE=1
        clear 2>/dev/null || true
        show_system_summary "$updates" "$cleanable_kb"

        if [ "$updates" -gt 0 ] || [ "$cleanable_kb" -gt 50000 ]; then
            echo ""
            echo -e "  ${YELLOW}${BOLD}🔔 Notice: Pending maintenance actions detected.${NC}"
            read -rp "  Run package updates and cache cleanups now? [y/N/Skip]: " maint_ans
            if [[ "$maint_ans" =~ ^[Yy]$ ]]; then
                run_menu_action update_and_clean
                run_menu_action run_optimizer
                echo ""
                read -rp "Press Enter to proceed to Master Dashboard..." _ || true
                updates=$(check_pending_updates)
                cleanable_kb=$(check_cleanable_cache)
            fi
        else
            echo ""
            read -rp "Press Enter to proceed to Master Dashboard..." _ || true
        fi
    fi

    while true; do
        clear 2>/dev/null || true

        # Gather real-time status metrics
        local cur_preset cur_bat cur_zram cur_bbr cur_dns cur_mac cur_timer cur_ipv6 cur_nm
        cur_preset=$(status_get_preset)
        cur_bat=$(status_get_battery)
        cur_zram=$(status_get_zram)
        cur_bbr=$(status_get_bbr)
        cur_dns=$(status_get_dns)
        cur_mac=$(status_get_mac)
        cur_timer=$(status_get_timer)
        cur_ipv6=$(status_get_ipv6)
        cur_nm=$(status_get_wait_online)

        local cur_nm_pill
        [[ "$cur_nm" =~ DISABLED ]] && cur_nm_pill="${GREEN}${BOLD}[ FAST BOOT (Disabled) ]${NC} (No ~7s delay)" || cur_nm_pill="${YELLOW}${BOLD}[ ENABLED (~7s delay) ]${NC}"

        echo -e "${CYAN}╭──────────────────────────────────────────────────────────────────────────────╮${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}${GREEN}⚡ LAPTOP LINUX OPTIMIZER & SYSTEM CONTROL CENTER${NC}                  ${DIM}v${VERSION}${NC}  ${CYAN}│${NC}"
        echo -e "${CYAN}╰──────────────────────────────────────────────────────────────────────────────╯${NC}"
        echo -e "${CYAN}┌── LIVE SYSTEM & HARDWARE STATUS ─────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}Active Preset${NC}   : ${GREEN}${BOLD}${cur_preset}${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}Battery Limit${NC}   : ${CYAN}${cur_bat}${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}ZRAM RAM Swap${NC}   : ${GREEN}${cur_zram}${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}TCP Congestion${NC}  : ${GREEN}${cur_bbr}${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}Encrypted DNS${NC}   : ${BLUE}${cur_dns}${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}Network MAC${NC}     : ${MAGENTA}${cur_mac}${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}NM Fast Boot${NC}    : ${cur_nm_pill}"
        echo -e "${CYAN}│${NC}  ${BOLD}IPv6 Protocol${NC}   : ${cur_ipv6}  ${CYAN}│${NC}  ${BOLD}Weekly Timer${NC}: ${cur_timer}"
        echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────────┘${NC}"

        # Display advisory banner if updates or cleanups pending
        if [ "$updates" -gt 0 ] || [ "$cleanable_kb" -gt 50000 ]; then
            echo -e "${YELLOW}┌── NOTIFICATIONS & MAINTENANCE ADVISORY ──────────────────────────────────────┐${NC}"
            if [ "$updates" -gt 0 ]; then
                echo -e "${YELLOW}│${NC}  ${YELLOW}●${NC} ${BOLD}$updates${NC} package update(s) available.          ${DIM}[Press ${BOLD}U${NC}${DIM} to Update Now]${NC}"
            fi
            if [ "$cleanable_kb" -gt 50000 ]; then
                echo -e "${YELLOW}│${NC}  ${YELLOW}●${NC} ~${BOLD}$(format_kb "$cleanable_kb")${NC} cleanable caches & logs.        ${DIM}[Press ${BOLD}C${NC}${DIM} to Clean Now]${NC}"
            fi
            echo -e "${YELLOW}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        fi

        local ipv6_lbl="ENABLED"
        [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 0)" -eq 1 ] && ipv6_lbl="DISABLED"

        echo -e "${CYAN}┌── MANAGEMENT ACTIONS & SUBSYSTEM PANELS ─────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[P]${NC} ${BOLD}Switch Profile Preset${NC}  ${DIM}(Desk: 60% | Balanced: 80% | Travel: 100%)${NC}"
        echo -e "${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[1]${NC} 🚀 Guided Laptop Optimization Wizard   ${DIM}(Full 5-step interactive setup)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[2]${NC} 📦 Update Packages & Sweep Clean       ${DIM}(APT dist-upgrade + Flatpak)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[3]${NC} 🧹 System Housekeeping & Cleanups      ${DIM}(Journals, APT, Temp caches)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[4]${NC} 🏆 Complete Master Suite               ${DIM}(Update + Clean + Privacy + MAC)${NC}"
        echo -e "${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[5]${NC} 🔋 Battery Diagnostics & Charge Limiter Configuration"
        echo -e "${CYAN}│${NC}  ${BOLD}[6]${NC} 🛡️  Encrypted DNS Manager              ${DIM}(DoH / Relays / Tor)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[7]${NC} 🕵️  Network MAC Randomization & Inspection"
        echo -e "${CYAN}│${NC}  ${BOLD}[8]${NC} 🌐 Toggle IPv6 Protocol                ${DIM}(State: [${ipv6_lbl}])${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[9]${NC} ⚡ Performance, Privacy & Startup Toggles ${DIM}(NM Boot, BBR, ZRAM, DHCP)${NC}"
        echo -e "${CYAN}│${NC} ${BOLD}[10]${NC} 🔒 Privacy & Anti-Tracking Activity Scrub"
        echo -e "${CYAN}│${NC} ${BOLD}[11]${NC} ⏱️  Automated Weekly Maintenance Timer  ${DIM}(Systemd)${NC}"
        echo -e "${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[D]${NC} Curses/Whiptail Mode   ${BOLD}[R]${NC} Refresh Status          ${BOLD}[0/Q]${NC} Exit"
        echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        read -rp "Select an option [0-11, P, U, C, D, R, Q]: " opt || break

        case "$opt" in
            [Pp]|preset)
                run_menu_action interactive_preset_menu
                ;;
            [Uu]|update)
                run_menu_action update_and_clean
                updates=$(check_pending_updates)
                cleanable_kb=$(check_cleanable_cache)
                ;;
            [Cc]|clean)
                run_menu_action run_optimizer
                cleanable_kb=$(check_cleanable_cache)
                ;;
            [Dd]|dialog|whiptail)
                show_whiptail_tui || true
                ;;
            [Rr]|refresh)
                updates=$(check_pending_updates)
                cleanable_kb=$(check_cleanable_cache)
                ;;
            1|wizard)
                run_menu_action run_guided_wizard
                ;;
            2)
                run_menu_action update_and_clean
                updates=$(check_pending_updates)
                cleanable_kb=$(check_cleanable_cache)
                ;;
            3)
                run_menu_action run_optimizer
                cleanable_kb=$(check_cleanable_cache)
                ;;
            4)
                read -rp "Run complete master suite (Update + Clean + Privacy + MAC)? [y/N]: " conf_suite
                if [[ "$conf_suite" =~ ^[Yy]$ ]]; then
                    run_menu_action run_complete_suite
                    updates=$(check_pending_updates)
                    cleanable_kb=$(check_cleanable_cache)
                fi
                ;;
            5|battery)
                interactive_battery_menu
                ;;
            6|dns)
                run_menu_action interactive_dns_menu
                ;;
            7|mac)
                interactive_mac_menu
                ;;
            8|ipv6)
                echo ""
                show_ipv6_status
                echo ""
                local cur_st="ENABLED"
                [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 0)" -eq 1 ] && cur_st="DISABLED"
                local next_action="Disable IPv6 (Block leaks & IPv6 traffic)"
                [ "$cur_st" = "DISABLED" ] && next_action="Enable IPv6 system-wide"
                echo -e "${CYAN}┌── IPV6 PROTOCOL TOGGLE ──────────────────────────────────────────────────────┐${NC}"
                echo -e "${CYAN}│${NC}  ${BOLD}[1]${NC} Toggle IPv6 Protocol ($next_action)"
                echo -e "${CYAN}│${NC}  ${BOLD}[0/Q]${NC} Return to Master Dashboard"
                echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
                read -rp "Option [1 or Q, default 1]: " iopt
                iopt="${iopt:-1}"
                case "$iopt" in
                    1) run_menu_action toggle_ipv6 ;;
                esac
                ;;
            9|tune|toggles)
                interactive_tuning_menu
                ;;
            10|privacy)
                read -rp "Run privacy and activity scrub now? [y/N]: " conf_priv
                if [[ "$conf_priv" =~ ^[Yy]$ ]]; then
                    run_menu_action clean_privacy "privacy"
                fi
                ;;
            11|timer)
                interactive_timer_menu
                ;;
            0|[Qq]|exit|quit)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                log_warn "Invalid selection."
                sleep 1
                ;;
        esac
    done
}

show_interactive_menu() {
    # Option 1: Guided Laptop Optimization Wizard (Recommended)
    show_tui_dashboard "$@"
}

show_help() {
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}       Linux Mint Master Admin & System Control Utility (mint-admin)${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo "Usage: $0 [command] [subcommand / options...]"
    echo ""
    echo "Command Subsystems:"
    echo "  wizard, guided            Run the 5-step guided laptop optimization wizard"
    echo "  battery                   Battery diagnostics and charge limiter"
    echo "    status                  Display battery capacity, cycles, health & limit"
    echo "    set <20-100>            Set charge threshold temporarily (e.g. 60, 80, 100)"
    echo "    install [limit]         Install persistent systemd service & sleep hook (default: 80)"
    echo "    uninstall               Remove limiter service and restore 100%"
    echo ""
    echo "  dns                       Encrypted DNS (DoH, Anonymized Relays, Tor)"
    echo "    menu                    Interactive encrypted DNS selection menu"
    echo "    apply <0-14|profile>    Apply DNS profile directly by index or name"
    echo "    status                  Show current active DNS resolver status"
    echo "    revert                  Restore default DHCP DNS configuration"
    echo ""
    echo "  mac                       MAC address randomization & inspection"
    echo "    status                  Display interfaces, current MAC, permanent MAC & state"
    echo "    randomize               Randomize MAC addresses on demand"
    echo "    enable                  Enable persistent auto-randomization in NetworkManager"
    echo "    disable                 Disable persistent auto-randomization"
    echo ""
    echo "  ipv6                      IPv6 network protocol control & toggle"
    echo "    status                  Display current IPv6 status and active addresses"
    echo "    toggle                  Toggle IPv6 on/off instantly"
    echo "    disable, off            Disable IPv6 system-wide (preserving loopback ::1)"
    echo "    enable, on              Enable IPv6 system-wide"
    echo ""
    echo "  wait-online               NetworkManager wait-online boot delay toggle (Fast Boot)"
    echo "    status                  Display wait-online service enabled/disabled state"
    echo "    toggle                  Toggle between Fast Boot (disabled) and Network Wait"
    echo "    disable, off            Disable wait-online (~7s delay removed for fast boot)"
    echo "    enable, on              Enable wait-online (boot waits for network)"
    echo ""
    echo "  tune, harden              Performance tuning & privacy hardening"
    echo "    status                  Display TCP BBR, ZRAM, swappiness, and privacy status"
    echo "    menu                    Interactive performance, privacy & startup toggle hub"
    echo "    apply                   Enable BBR, ZRAM, swappiness 100, DHCP privacy & fast boot"
    echo "    revert                  Revert system tunings to standard Linux Mint defaults"
    echo "    wait-online [toggle]    Toggle NetworkManager wait-online boot delay (~7s saved)"
    echo "    bbr [toggle]            Toggle Google TCP BBR low-latency congestion control"
    echo "    swappiness [toggle]     Toggle swappiness & cache pressure (100/50 vs 60/100)"
    echo "    zram [toggle]           Toggle ZRAM 50% RAM compressed swap"
    echo "    dhcp [toggle]           Toggle DHCP hostname leak protection"
    echo "    kernel [toggle]         Toggle kernel memory privacy (dmesg & kptr restrict)"
    echo "    avahi [toggle]          Toggle Avahi mDNS discovery broadcast daemon"
    echo "    cups [toggle]           Toggle CUPS network printer polling daemon"
    echo "    modem [toggle]          Toggle ModemManager cellular serial scanner"
    echo "    daemons [toggle]        Toggle all 3 discovery broadcast daemons at once"
    echo ""
    echo "  preset, profile           Switch or view laptop performance/battery profile presets"
    echo "    status                  Display active profile preset & hardware status"
    echo "    apply <desk|balanced|travel>  Apply one-click profile preset"
    echo "    desk                    Preset: 60% battery limit + BBR + ZRAM (AC docked)"
    echo "    balanced                Preset: 80% battery limit + BBR + ZRAM (Daily default)"
    echo "    travel                  Preset: 100% full capacity (Travel / mobile)"
    echo ""
    echo "  check, advisory           Check pending package updates and cleanable cache storage"
    echo "  summary, status           Display comprehensive summary of all system statuses"
    echo "  tui, dashboard, menu      Launch interactive terminal dashboard (TUI / Curses)"
    echo "    --dialog, --whiptail    Launch in modal dialog / whiptail curses GUI mode"
    echo ""
    echo "  optimize, clean           Run routine housekeeping (APT, Flatpak, journals, temp)"
    echo "  update, upgrade           Update all packages (APT & Flatpak) and purge orphans/caches"
    echo "  all                       Full update followed by complete system housekeeping"
    echo "  privacy                   Scrub privacy caches (browsers, recent files, DNS, trash)"
    echo "  full-suite                Total master run: update + housekeeping + privacy + MAC"
    echo ""
    echo "  timer                     Automated weekly background maintenance"
    echo "    status                  View timer status and previous run logs"
    echo "    install                 Install persistent systemd weekly timer"
    echo "    uninstall               Remove systemd weekly timer"
    echo ""
    echo "  version, -v, --version    Show version information"
    echo "  help, --help, -h          Show this help manual"
    echo ""
    echo "Options:"
    echo "  -y, --yes, --force        Execute non-interactively without confirmation prompts"
    echo ""
    echo "Examples:"
    echo "  $0                                # Launch master interactive TUI dashboard"
    echo "  $0 preset balanced                # Switch to Balanced Daily preset (80% + BBR + ZRAM)"
    echo "  $0 preset desk                    # Switch to AC Docked preset (60% + BBR + ZRAM)"
    echo "  $0 check                          # Inspect pending updates & cleanable disk space"
    echo "  $0 battery status                 # Check battery health & current threshold"
    echo "  sudo $0 battery set 80            # Set charge limiter to 80%"
    echo "  sudo $0 battery install 80        # Persist 80% limit across reboots & sleep"
    echo "  sudo $0 wait-online toggle        # Toggle NetworkManager boot delay on/off"
    echo "  sudo $0 tune bbr toggle           # Toggle Google BBR TCP congestion control"
    echo "  sudo $0 tune zram toggle          # Toggle ZRAM compressed RAM swap"
    echo "  sudo $0 dns apply cloudflare      # Switch to Cloudflare DoH"
    echo "  sudo $0 dns apply 0               # Switch to Auto-Failover pool"
    echo "  sudo $0 dns revert                # Revert back to standard DHCP DNS"
    echo "  sudo $0 privacy                   # Scrub browser caches, recent files & flush DNS"
    echo "  $0 mac status                     # View current vs permanent MAC addresses"
    echo "  sudo $0 mac randomize             # Randomize MAC addresses now"
    echo "  sudo $0 update                    # Update all APT & Flatpak packages and clean up"
    echo "  sudo $0 all                       # Full update + complete system housekeeping"
    echo "  sudo $0 full-suite                # Total system refresh & privacy scrub"
}

# ==============================================================================
# Master CLI Dispatcher
# ==============================================================================

FORCE_YES=0
CLEAN_ARGS=()
for arg in "$@"; do
    case "$arg" in
        -y|--yes|--force)
            FORCE_YES=1
            ;;
        *)
            CLEAN_ARGS+=("$arg")
            ;;
    esac
done

if [ "${#CLEAN_ARGS[@]}" -gt 0 ]; then
    set -- "${CLEAN_ARGS[@]}"
else
    set --
fi

if [ "$#" -eq 0 ]; then
    if [ ! -t 0 ]; then
        show_help
        exit 0
    fi
    show_interactive_menu
    exit 0
fi

CMD="$1"
shift

case "$CMD" in
    wizard|guided|setup)
        run_guided_wizard
        ;;

    battery|bat)
        SUB="${1:-status}"
        shift || true
        case "$SUB" in
            status)
                show_battery_status
                ;;
            set)
                if [ $# -lt 1 ]; then
                    log_err "Missing threshold value. Usage: sudo $0 battery set <20-100>"
                    exit 1
                fi
                set_battery_threshold "$1"
                ;;
            install)
                install_battery_service "${1:-80}"
                ;;
            uninstall)
                uninstall_battery_service
                ;;
            *)
                log_err "Unknown battery command: '$SUB'"
                echo "Usage: $0 battery [status | set <20-100> | install [limit] | uninstall]"
                exit 1
                ;;
        esac
        ;;

    dns)
        SUB="${1:-status}"
        shift || true
        case "$SUB" in
            menu)
                interactive_dns_menu
                ;;
            status)
                show_dns_status
                ;;
            apply|set)
                if [ $# -lt 1 ]; then
                    interactive_dns_menu
                else
                    apply_dns_profile "$1"
                fi
                ;;
            revert|dhcp)
                revert_dns_changes
                ;;
            *)
                apply_dns_profile "$SUB"
                ;;
        esac
        ;;

    mac)
        SUB="${1:-status}"
        shift || true
        case "$SUB" in
            status)
                show_mac_status
                ;;
            randomize|spoof)
                randomize_mac
                ;;
            enable)
                enable_mac_randomization
                ;;
            disable)
                disable_mac_randomization
                ;;
            *)
                log_err "Unknown mac command: '$SUB'"
                echo "Usage: $0 mac [status | randomize | enable | disable]"
                exit 1
                ;;
        esac
        ;;

    ipv6)
        SUB="${1:-status}"
        shift || true
        case "$SUB" in
            status)
                show_ipv6_status
                ;;
            toggle)
                toggle_ipv6
                ;;
            disable|off|block)
                disable_ipv6
                ;;
            enable|on)
                enable_ipv6
                ;;
            *)
                log_err "Unknown ipv6 command: '$SUB'"
                echo "Usage: $0 ipv6 [status | toggle | disable | enable]"
                exit 1
                ;;
        esac
        ;;

    toggle-ipv6)
        toggle_ipv6
        ;;

    disable-ipv6)
        disable_ipv6
        ;;

    enable-ipv6)
        enable_ipv6
        ;;

    wait-online|nm-wait-online)
        SUB="${1:-toggle}"
        shift || true
        case "$SUB" in
            status)
                echo "NM Wait-Online Delay: $(status_get_wait_online)"
                ;;
            toggle)
                toggle_nm_wait_online
                ;;
            disable|off)
                disable_nm_wait_online
                ;;
            enable|on)
                enable_nm_wait_online
                ;;
            *)
                log_err "Unknown wait-online command: '$SUB'"
                echo "Usage: $0 wait-online [status | toggle | disable | enable]"
                exit 1
                ;;
        esac
        ;;

    toggle-wait-online)
        toggle_nm_wait_online
        ;;

    optimize|clean|--run|-r)
        run_optimizer
        ;;

    update|upgrade|--update|-u)
        update_and_clean
        ;;

    all|full|--all|-a)
        run_full_update_and_optimizer
        ;;

    privacy|--privacy|-p)
        clean_privacy
        ;;

    tune|harden|sysctl)
        SUB="${1:-status}"
        shift || true
        case "$SUB" in
            status)
                show_tuning_status
                ;;
            menu|interactive|tui)
                interactive_tuning_menu
                ;;
            apply|enable|on)
                apply_system_tuning
                ;;
            revert|disable|off)
                revert_system_tuning
                ;;
            wait-online|nm-wait-online|nm|fast-boot)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_nm_wait_online ;;
                    enable|on) enable_nm_wait_online ;;
                    disable|off) disable_nm_wait_online ;;
                    status) echo "NM Wait-Online Delay: $(status_get_wait_online)" ;;
                    *) log_err "Unknown wait-online action: '$ACT'"; exit 1 ;;
                esac
                ;;
            bbr|tcp)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_bbr ;;
                    enable|on) enable_bbr ;;
                    disable|off) disable_bbr ;;
                    status) echo "TCP Congestion Control: $(status_get_bbr)" ;;
                    *) log_err "Unknown bbr action: '$ACT'"; exit 1 ;;
                esac
                ;;
            swappiness|swap|vfs)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_swappiness ;;
                    enable|on) enable_swappiness ;;
                    disable|off) disable_swappiness ;;
                    status) echo "Swappiness / VFS: $(status_get_swappiness)" ;;
                    *) log_err "Unknown swappiness action: '$ACT'"; exit 1 ;;
                esac
                ;;
            zram)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_zram ;;
                    enable|on) enable_zram ;;
                    disable|off) disable_zram ;;
                    status) echo "ZRAM Swap: $(status_get_zram)" ;;
                    *) log_err "Unknown zram action: '$ACT'"; exit 1 ;;
                esac
                ;;
            dhcp|dhcp-privacy|hostname)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_dhcp_privacy ;;
                    enable|on) enable_dhcp_privacy ;;
                    disable|off) disable_dhcp_privacy ;;
                    status) echo "DHCP Hostname Leak: $(status_get_dhcp)" ;;
                    *) log_err "Unknown dhcp action: '$ACT'"; exit 1 ;;
                esac
                ;;
            kernel|privacy-sysctl|hardening)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_kernel_hardening ;;
                    enable|on) enable_kernel_hardening ;;
                    disable|off) disable_kernel_hardening ;;
                    status) echo "Kernel Privacy: $(status_get_kernel_privacy)" ;;
                    *) log_err "Unknown kernel action: '$ACT'"; exit 1 ;;
                esac
                ;;
            avahi|mdns)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_avahi ;;
                    enable|on)
                        systemctl is-active --quiet avahi-daemon || toggle_avahi
                        ;;
                    disable|off)
                        systemctl is-active --quiet avahi-daemon && toggle_avahi
                        ;;
                    status) echo "Avahi mDNS: $(status_get_avahi)" ;;
                    *) log_err "Unknown avahi action: '$ACT'"; exit 1 ;;
                esac
                ;;
            cups|cups-browsed)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_cups_browsed ;;
                    enable|on)
                        systemctl is-active --quiet cups-browsed || toggle_cups_browsed
                        ;;
                    disable|off)
                        systemctl is-active --quiet cups-browsed && toggle_cups_browsed
                        ;;
                    status) echo "CUPS Browsed: $(status_get_cups)" ;;
                    *) log_err "Unknown cups action: '$ACT'"; exit 1 ;;
                esac
                ;;
            modem|modemmanager)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_modemmanager ;;
                    enable|on)
                        systemctl is-active --quiet ModemManager || toggle_modemmanager
                        ;;
                    disable|off)
                        systemctl is-active --quiet ModemManager && toggle_modemmanager
                        ;;
                    status) echo "ModemManager: $(status_get_modem)" ;;
                    *) log_err "Unknown modem action: '$ACT'"; exit 1 ;;
                esac
                ;;
            daemons|broadcast)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_broadcast_daemons ;;
                    enable|on)
                        systemctl is-active --quiet avahi-daemon || toggle_broadcast_daemons
                        ;;
                    disable|off)
                        systemctl is-active --quiet avahi-daemon && toggle_broadcast_daemons
                        ;;
                    status)
                        echo "Avahi: $(status_get_avahi) | CUPS: $(status_get_cups) | Modem: $(status_get_modem)"
                        ;;
                    *) log_err "Unknown daemons action: '$ACT'"; exit 1 ;;
                esac
                ;;
            *)
                log_err "Unknown tune command: '$SUB'"
                echo "Usage: $0 tune [status | menu | apply | revert | wait-online | bbr | swappiness | zram | dhcp | kernel | avahi | cups | modem | daemons]"
                exit 1
                ;;
        esac
        ;;

    full-suite|master)
        run_complete_suite
        ;;

    timer)
        SUB="${1:-status}"
        shift || true
        case "$SUB" in
            status)
                show_timer_status
                ;;
            install)
                install_weekly_timer
                ;;
            uninstall)
                uninstall_weekly_timer
                ;;
            *)
                log_err "Unknown timer command: '$SUB'"
                echo "Usage: $0 timer [status | install | uninstall]"
                exit 1
                ;;
        esac
        ;;

    preset|profile)
        SUB="${1:-status}"
        shift || true
        case "$SUB" in
            status)
                show_preset_status
                ;;
            apply|set)
                if [ $# -lt 1 ]; then
                    interactive_preset_menu
                else
                    apply_preset "$1"
                fi
                ;;
            desk|balanced|travel|custom)
                apply_preset "$SUB"
                ;;
            *)
                log_err "Unknown preset command: '$SUB'"
                echo "Usage: $0 preset [status | apply <desk|balanced|travel|custom>]"
                exit 1
                ;;
        esac
        ;;

    summary|status|report)
        show_system_summary
        ;;

    check|advisory|notify)
        show_maintenance_advisory
        ;;

    tui|dashboard|menu|interactive)
        if [ "${1:-}" = "--dialog" ] || [ "${1:-}" = "--whiptail" ]; then
            show_whiptail_tui
        else
            show_tui_dashboard
        fi
        ;;

    version|-v|--version)
        echo "Laptop Linux Optimizer (mint-admin) v${VERSION}"
        ;;

    help|--help|-h)
        show_help
        ;;

    *)
        log_err "Unknown command: '$CMD'"
        show_help
        exit 1
        ;;
esac
