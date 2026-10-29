#!/usr/bin/env bash
# ==============================================================================
# Laptop Linux Optimizer & Master Administration Suite (mint-admin)
# Version: 0.1.0
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

VERSION="0.1.0"
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
BATTERY_SLEEP_HOOK="/lib/systemd/system-sleep/asus-battery-limit.sh"
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
        echo -e "${YELLOW}[-] Please run with sudo: sudo $0 ${*:-}${NC}" >&2
        exit 1
    fi
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
    echo "${nodes[@]:-}"
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
        [ -f "$BATTERY_UDEV_RULE" ] && echo "AC Plug Watcher  : udev rule active (prevents AC-plug reset)"
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

    local nodes
    nodes=$(find_battery_threshold_nodes)
    if [ -z "$nodes" ]; then
        log_err "No supported battery threshold interface found in /sys/class/power_supply/"
        exit 1
    fi

    for node in $nodes; do
        echo "$val" > "$node"
    done

    echo "THRESHOLD=$val" > "$BATTERY_CONF"
    chmod 644 "$BATTERY_CONF"

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

    cat << 'EOF' > "$BATTERY_SERVICE"
[Unit]
Description=ASUS Battery Charge Limit Persister
After=multi-user.target suspend.target hibernate.target hybrid-sleep.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'if [ -f /etc/asus-battery-limit.conf ]; then . /etc/asus-battery-limit.conf; else THRESHOLD=80; fi; for bat in /sys/class/power_supply/BAT*/charge_control_end_threshold; do [ -f "$bat" ] && [ "$(cat "$bat" 2>/dev/null)" != "$THRESHOLD" ] && echo "$THRESHOLD" > "$bat" 2>/dev/null || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "$BATTERY_SERVICE"

    if [ -d "/lib/systemd/system-sleep" ]; then
        cat << 'EOF' > "$BATTERY_SLEEP_HOOK"
#!/bin/sh
case "$1" in
    post)
        if [ -f /etc/asus-battery-limit.conf ]; then
            . /etc/asus-battery-limit.conf
        else
            THRESHOLD=80
        fi
        for bat in /sys/class/power_supply/BAT*/charge_control_end_threshold; do
            [ -f "$bat" ] && [ "$(cat "$bat" 2>/dev/null)" != "$THRESHOLD" ] && echo "$THRESHOLD" > "$bat" 2>/dev/null || true
        done
        ;;
esac
EOF
        chmod +x "$BATTERY_SLEEP_HOOK"
    fi

    # 3. Write udev rule (re-applies threshold when AC adapter is plugged/unplugged, without looping)
    if [ -d "/etc/udev/rules.d" ]; then
        cat << 'EOF' > "$BATTERY_UDEV_RULE"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ACTION=="change", RUN+="/bin/sh -c 'if [ -f /etc/asus-battery-limit.conf ]; then . /etc/asus-battery-limit.conf; for bat in /sys/class/power_supply/BAT*/charge_control_end_threshold; do [ -f \"$$bat\" ] && [ \"$$(cat \"$$bat\" 2>/dev/null)\" != \"$$THRESHOLD\" ] && echo \"$$THRESHOLD\" > \"$$bat\" 2>/dev/null || true; done; fi'"
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
    rm -f "$BATTERY_SERVICE" "$BATTERY_SLEEP_HOOK" "$BATTERY_CONF" "$BATTERY_UDEV_RULE"
    udevadm control --reload-rules 2>/dev/null || true
    systemctl daemon-reload

    local nodes
    nodes=$(find_battery_threshold_nodes)
    for node in $nodes; do
        echo "100" > "$node" 2>/dev/null || true
    done
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

check_tor_service() {
    log_info "Checking Tor service..."
    if ! command -v tor &>/dev/null; then
        apt-get update && apt-get install -y tor
    fi
    systemctl enable --now tor
    log_success "Tor is active on 127.0.0.1:9050."
}

apply_dnscrypt_config() {
    local servers="$1"
    local use_anonymized="$2"
    local use_tor="$3"

    log_info "Applying settings to $DNS_CONFIG..."

    sed -i "s/^listen_addresses = .*/listen_addresses = []/" "$DNS_CONFIG"
    sed -i "s/^server_names = .*/server_names = $servers/" "$DNS_CONFIG"

    # Always strip existing proxy and force_tcp settings before re-applying
    sed -i '/^[[:space:]]*proxy[[:space:]]*=/d; /^[[:space:]]*force_tcp[[:space:]]*=/d' "$DNS_CONFIG"

    if [[ "$use_tor" == "true" ]]; then
        log_info "Routing DNS queries through Tor Onion proxy (127.0.2.1 -> 127.0.0.1:9050)..."
        # Insert at the top-level table immediately following server_names, before any [section]
        sed -i "/^server_names =/a proxy = 'socks5://127.0.0.1:9050'\nforce_tcp = true" "$DNS_CONFIG"
    fi

    if [[ "$use_anonymized" == "true" ]]; then
        log_info "Setting up Anonymized DNS relay routes..."
        if ! grep -q "sources.'relays'" "$DNS_CONFIG"; then
            cat << 'EOF' >> "$DNS_CONFIG"

[sources.'relays']
  url = 'https://download.dnscrypt.info/resolvers-list/v2/relays.md'
  cache_file = '/var/cache/dnscrypt-proxy/relays.md'
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  refresh_delay = 72
  prefix = ''
EOF
        fi

        sed -i '/^\[anonymized_dns\]/,/^\[/ { /^routes =/d }' "$DNS_CONFIG"
        if ! grep -q "^\[anonymized_dns\]" "$DNS_CONFIG"; then
            echo -e "\n[anonymized_dns]" >> "$DNS_CONFIG"
        fi
        sed -i "/^\[anonymized_dns\]/a routes = [{ server_name='*', via=['anon-cs-de', 'anon-ibksturm', 'anon-tiar-nl'] }]" "$DNS_CONFIG"
    else
        sed -i '/^routes = \[{ server_name='\''\*'\''/d' "$DNS_CONFIG"
    fi

    if ! dnscrypt-proxy -config "$DNS_CONFIG" -check &>/dev/null; then
        log_err "Configuration syntax test failed! Reverting $DNS_CONFIG..."
        cp "$DNS_BACKUP" "$DNS_CONFIG"
        exit 1
    fi
    log_success "dnscrypt-proxy configuration syntax verified."
}

setup_system_dns() {
    log_info "Configuring system DNS drop-ins for 127.0.2.1..."

    mkdir -p /etc/NetworkManager/conf.d
    cat <<EOF > "$NM_DNS_DROPIN"
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
EOF
    fi
    log_success "System DNS directed to local proxy (127.0.2.1)."
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

    if systemctl is-active dnscrypt-proxy.service &>/dev/null || systemctl is-active dnscrypt-proxy.socket &>/dev/null; then
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
            apply_dnscrypt_config "['quad9-doh-ip4-port443-filter-pri', 'cloudflare', 'adguard-dns-doh']" "false" "false"
            setup_system_dns && restart_dns_services
            log_success "Auto-Failover Pool active (Quad9 + Cloudflare + AdGuard)."
            ;;
        1|cloudflare)
            apply_dnscrypt_config "['cloudflare', 'cloudflare-ipv6']" "false" "false"
            setup_system_dns && restart_dns_services
            log_success "Cloudflare Anycast DoH active."
            ;;
        2|google)
            apply_dnscrypt_config "['google', 'google-ipv6']" "false" "false"
            setup_system_dns && restart_dns_services
            log_success "Google Public DNS active."
            ;;
        3|quad9)
            apply_dnscrypt_config "['quad9-doh-ip4-port443-filter-pri', 'quad9-doh-ip6-port443-filter-pri']" "false" "false"
            setup_system_dns && restart_dns_services
            log_success "Quad9 DoH active (Swiss malware filter)."
            ;;
        4|adguard)
            apply_dnscrypt_config "['adguard-dns-doh', 'adguard-dns-doh-ipv6']" "false" "false"
            setup_system_dns && restart_dns_services
            log_success "AdGuard Adblock DoH active."
            ;;
        5|controld)
            apply_dnscrypt_config "['controld-block-malware-ad']" "false" "false"
            setup_system_dns && restart_dns_services
            log_success "Control D Adblock DoH active."
            ;;
        6|libredns)
            apply_dnscrypt_config "['libredns']" "false" "false"
            setup_system_dns && restart_dns_services
            log_success "LibreDNS Standard active."
            ;;
        7|libredns-adblock)
            apply_dnscrypt_config "['libredns-noads']" "false" "false"
            setup_system_dns && restart_dns_services
            log_success "LibreDNS with Adblock active."
            ;;
        8|cloudflare-odoh)
            apply_dnscrypt_config "['cloudflare']" "true" "false"
            setup_system_dns && restart_dns_services
            log_success "Cloudflare via ODoH (Anonymized Relays) active."
            ;;
        9|quad9-odoh)
            apply_dnscrypt_config "['quad9-doh-ip4-port443-filter-pri']" "true" "false"
            setup_system_dns && restart_dns_services
            log_success "Quad9 via ODoH active."
            ;;
        10|libredns-odoh)
            apply_dnscrypt_config "['libredns-noads']" "true" "false"
            setup_system_dns && restart_dns_services
            log_success "LibreDNS via ODoH active."
            ;;
        11|quad9-tor)
            check_tor_service
            apply_dnscrypt_config "['quad9-doh-ip4-port443-filter-pri']" "false" "true"
            setup_system_dns && restart_dns_services
            log_success "Quad9 via Tor Onion routing active."
            ;;
        12|libredns-tor)
            check_tor_service
            apply_dnscrypt_config "['libredns-noads']" "false" "true"
            setup_system_dns && restart_dns_services
            log_success "LibreDNS Adblock via Tor active."
            ;;
        13|cloudflare-tor)
            check_tor_service
            apply_dnscrypt_config "['cloudflare']" "false" "true"
            setup_system_dns && restart_dns_services
            log_success "Cloudflare via Tor active."
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
        local recent_file="$h/.local/share/recently-used.xbel"
        if [ -f "$recent_file" ] && [ ! -L "$recent_file" ]; then
            local tmp_recent="${recent_file}.tmp.$$"
            echo '<?xml version="1.0" encoding="UTF-8"?><xbel version="1.0" xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks" xmlns:mime="http://www.freedesktop.org/standards/shared-mime-info"></xbel>' > "$tmp_recent"
            local owner
            owner=$(stat -c '%u:%g' "$h" 2>/dev/null || echo "0:0")
            chown --no-dereference "$owner" "$tmp_recent" 2>/dev/null || true
            chmod 600 "$tmp_recent" 2>/dev/null || true
            mv -T "$tmp_recent" "$recent_file" 2>/dev/null || rm -f "$tmp_recent"
            echo "  - Reset recent files history for: $(basename "$h")"
        fi

        [ ! -L "$h/.local/share/.vivaldi_reporting_data" ] && rm -f "$h/.local/share/.vivaldi_reporting_data" 2>/dev/null || true
        [ ! -L "$h/.local/share/zeitgeist" ] && rm -rf "$h/.local/share/zeitgeist" 2>/dev/null || true
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

        if [ -d "$h/.cache/mozilla/firefox" ] && [ ! -L "$h/.cache/mozilla/firefox" ]; then
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
            if [ -d "$cdir" ] && [ ! -L "$cdir" ]; then
                find "$cdir" -mindepth 1 -maxdepth 4 -type d \( -name "Cache" -o -name "GPUCache" -o -name "Code Cache" -o -name "ShaderCache" -o -name "GrShaderCache" \) -exec rm -rf {} + 2>/dev/null || true
                echo "  - Cleaned $(basename "$cdir") caches in $(basename "$h")"
            fi
        done

        if [ -d "$h/.var/app" ] && [ ! -L "$h/.var/app" ]; then
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
        if [ -d "$h/.cache/thumbnails" ] && [ ! -L "$h/.cache/thumbnails" ]; then
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
        if [ -d "$h/.local/share/Trash" ] && [ ! -L "$h/.local/share/Trash" ]; then
            for tsub in files info; do
                local tdir="$h/.local/share/Trash/$tsub"
                if [ -d "$tdir" ] && [ ! -L "$tdir" ]; then
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
    rm -rf /var/crash/* 2>/dev/null || true
    rm -rf /var/lib/systemd/coredump/* 2>/dev/null || true
    echo "  - Removed system crash reports and core dumps."
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
        # shellcheck disable=SC2086
        dpkg --purge $rc_pkgs 2>/dev/null || true
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
    echo "  - Cleaning stale thumbnail caches older than 14 days..."
    find /home/*/.cache/thumbnails /root/.cache/thumbnails -type f -mtime +14 -delete 2>/dev/null || true

    echo "  - Pruning old /var/tmp residual files (> 30 days old)..."
    find /var/tmp -mindepth 1 -maxdepth 3 -type f -mtime +30 -delete 2>/dev/null || true

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
    avail_before=$(df -k / | awk 'NR==2 {print $4}')
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
    avail_before=$(df -k / | awk 'NR==2 {print $4}')
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
    randomize_mac "mac"

    print_summary "$avail_before"
}

# ==============================================================================
# MODULE 6: Automated Weekly Maintenance Timers
# ==============================================================================

install_weekly_timer() {
    check_root "timer" "install"

    log_info "Setting up weekly automated maintenance timer..."

    local owner_uid
    owner_uid=$(stat -c '%u' "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$owner_uid" != "0" ]; then
        log_warn "Notice: '$SCRIPT_PATH' is owned by UID $owner_uid (non-root)."
        log_warn "The weekly systemd timer will run this script with root privileges."
    fi

    cat << EOF > "$OPTIMIZER_SERVICE"
[Unit]
Description=Linux Mint Weekly System Optimizer & Housekeeping
Documentation=file://$SCRIPT_PATH
After=network.target

[Service]
Type=oneshot
ExecStart="$SCRIPT_PATH" optimize
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
    echo "    - Frequency : Every Sunday at 03:00 AM (runs upon next boot if laptop was asleep/off)"
    echo "    - Logs      : journalctl -u mint-optimizer.service"
}

uninstall_weekly_timer() {
    check_root "timer" "uninstall"

    log_info "Disabling and removing weekly optimization timer..."
    systemctl stop mint-optimizer.timer 2>/dev/null || true
    systemctl disable mint-optimizer.timer 2>/dev/null || true
    rm -f "$OPTIMIZER_SERVICE" "$OPTIMIZER_TIMER"
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
    if [[ "$swappiness" =~ ^[0-9]+$ ]] && [ "$swappiness" -le 100 ]; then
        echo -e "vm.swappiness          : ${GREEN}$swappiness${NC} (Optimized for ZRAM & NVMe SSD)"
    else
        echo -e "vm.swappiness          : ${YELLOW}$swappiness${NC} (Default / standard disk swap)"
    fi
    echo -e "vm.vfs_cache_pressure  : $vfs_press"

    # 3. ZRAM Compressed Swap
    if swapon --show | grep -q "zram"; then
        local zram_info
        zram_info=$(swapon --show | grep "zram" | awk '{print $3, "used: "$4, "prio: "$5}')
        echo -e "ZRAM Compressed Swap   : ${GREEN}ACTIVE${NC} ($zram_info)"
    else
        echo -e "ZRAM Compressed Swap   : ${YELLOW}INACTIVE${NC} (Using standard disk swap)"
    fi

    # 4. Hostname Privacy over DHCP
    if [ -f "$DHCP_PRIVACY_CONF" ] && grep -q "ipv4.dhcp-send-hostname=false" "$DHCP_PRIVACY_CONF" 2>/dev/null; then
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
    systemctl is-active --quiet avahi-daemon && avahi_st="${YELLOW}ACTIVE (mDNS broadcasting)${NC}" || avahi_st="${GREEN}DISABLED${NC}"
    systemctl is-active --quiet cups-browsed && cups_st="${YELLOW}ACTIVE (UDP 631 polling)${NC}" || cups_st="${GREEN}DISABLED${NC}"
    systemctl is-active --quiet ModemManager && modem_st="${YELLOW}ACTIVE${NC}" || modem_st="${GREEN}DISABLED${NC}"
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

apply_system_tuning() {
    check_root "tune" "apply"

    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}     Applying Performance & Privacy System Tuning${NC}"
    echo -e "${CYAN}========================================================${NC}"

    # Capture initial baseline values before first modification
    mkdir -p /var/lib/mint-admin
    if [ ! -f "$BASELINE_SYSCTL" ]; then
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
        } > "$BASELINE_SYSCTL"
    fi

    # 1. Enable Google BBR and Performance sysctls
    log_info "Configuring TCP BBR & memory performance sysctls..."
    mkdir -p /etc/modules-load.d /etc/sysctl.d
    echo "tcp_bbr" > "$BBR_MODULE_CONF"
    modprobe tcp_bbr 2>/dev/null || true

    cat << 'EOF' > "$PERF_SYSCTL"
# Performance & TCP Tuning (mint-admin)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3

# Memory & ZRAM Swappiness Optimization (Balanced for 16GB laptop)
vm.swappiness = 100
vm.vfs_cache_pressure = 50
EOF

    # 2. Kernel Privacy & Anti-Leak Sysctls
    log_info "Configuring kernel privacy & memory protection sysctls..."
    cat << 'EOF' > "$PRIVACY_SYSCTL"
# Kernel Privacy & Security Hardening (mint-admin)
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.unprivileged_bpf_disabled = 1
fs.suid_dumpable = 0
EOF

    sysctl --system >/dev/null 2>&1 || sysctl -p "$PERF_SYSCTL" "$PRIVACY_SYSCTL" >/dev/null 2>&1 || true
    log_success "Kernel performance & privacy sysctls active."

    # 3. Prevent DHCP Hostname Leakage in NetworkManager
    log_info "Configuring NetworkManager DHCP hostname privacy..."
    mkdir -p /etc/NetworkManager/conf.d
    cat << 'EOF' > "$DHCP_PRIVACY_CONF"
[connection]
# Do not send machine hostname in DHCP requests
ipv4.dhcp-send-hostname=false
ipv6.dhcp-send-hostname=false
EOF
    chmod 644 "$DHCP_PRIVACY_CONF"
    nmcli general reload 2>/dev/null || systemctl reload NetworkManager 2>/dev/null || true
    log_success "DHCP hostname leak protection active."

    # 4. Optional: Disable slow boot delays and background broadcast daemons
    local disable_services=1
    if [ "${FORCE_YES:-0}" -ne 1 ] && [ -t 0 ]; then
        echo ""
        read -r -p "Disable discovery background daemons (avahi-daemon, cups-browsed, ModemManager)? [y/N]: " daemon_ans
        if [[ ! "$daemon_ans" =~ ^[Yy]$ ]]; then
            disable_services=0
            log_info "Keeping background discovery daemons active."
        fi
    fi

    if [ "$disable_services" -eq 1 ]; then
        log_info "Optimizing startup services and eliminating broadcast daemons..."
        systemctl disable NetworkManager-wait-online.service 2>/dev/null && echo "  - Disabled NetworkManager-wait-online (~7s boot delay removed)." || true
        systemctl stop avahi-daemon.service avahi-daemon.socket 2>/dev/null || true
        systemctl disable avahi-daemon.service avahi-daemon.socket 2>/dev/null && echo "  - Disabled avahi-daemon & avahi-daemon.socket (mDNS stopped)." || true
        systemctl stop cups-browsed 2>/dev/null || true
        systemctl disable cups-browsed 2>/dev/null && echo "  - Disabled cups-browsed (UDP 631 printer polling stopped)." || true
        systemctl stop ModemManager 2>/dev/null || true
        systemctl disable ModemManager 2>/dev/null && echo "  - Disabled ModemManager (cellular serial scanner stopped)." || true
    fi

    # 5. ZRAM Compressed RAM Swap
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

    echo ""
    log_success "All system performance and privacy tunings applied successfully!"
    echo -e "${CYAN}========================================================${NC}"
}

revert_system_tuning() {
    check_root "tune" "revert"

    log_warn "Reverting performance & privacy tunings to Linux Mint defaults..."
    rm -f "$PERF_SYSCTL" "$PRIVACY_SYSCTL" "$BBR_MODULE_CONF" "$DHCP_PRIVACY_CONF"

    # Restore from baseline if available, otherwise safe defaults
    local b_suid=2 b_bpf=2 b_fastopen=1 b_swap=60 b_vfs=100 b_dmesg=0 b_kptr=1 b_cc=cubic b_qdisc=fq_codel
    if [ -f "$BASELINE_SYSCTL" ]; then
        # shellcheck disable=SC1090
        . "$BASELINE_SYSCTL"
        b_suid="${BASE_SUID_DUMPABLE:-2}"
        b_bpf="${BASE_BPF_DISABLED:-2}"
        b_fastopen="${BASE_FASTOPEN:-1}"
        b_swap="${BASE_SWAPPINESS:-60}"
        b_vfs="${BASE_VFS_PRESSURE:-100}"
        b_dmesg="${BASE_DMESG_RESTRICT:-0}"
        b_kptr="${BASE_KPTR_RESTRICT:-1}"
        b_cc="${BASE_TCP_CC:-cubic}"
        b_qdisc="${BASE_QDISC:-fq_codel}"
        rm -f "$BASELINE_SYSCTL"
    fi

    # Reset kernel sysctls to defaults
    sysctl -w net.ipv4.tcp_congestion_control="$b_cc" >/dev/null 2>&1 || true
    sysctl -w net.core.default_qdisc="$b_qdisc" >/dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_fastopen="$b_fastopen" >/dev/null 2>&1 || true
    sysctl -w vm.swappiness="$b_swap" >/dev/null 2>&1 || true
    sysctl -w vm.vfs_cache_pressure="$b_vfs" >/dev/null 2>&1 || true
    sysctl -w kernel.dmesg_restrict="$b_dmesg" >/dev/null 2>&1 || true
    sysctl -w kernel.kptr_restrict="$b_kptr" >/dev/null 2>&1 || true
    sysctl -w kernel.unprivileged_bpf_disabled="$b_bpf" >/dev/null 2>&1 || true
    sysctl -w fs.suid_dumpable="$b_suid" >/dev/null 2>&1 || true

    # Re-enable services
    systemctl enable NetworkManager-wait-online.service 2>/dev/null || true
    systemctl enable --now avahi-daemon.socket avahi-daemon.service 2>/dev/null || true
    systemctl enable --now cups-browsed 2>/dev/null || true
    systemctl enable --now ModemManager 2>/dev/null || true

    # Disable ZRAM and remove config if user reverts
    systemctl stop zramswap.service 2>/dev/null || true
    systemctl disable zramswap.service 2>/dev/null || true
    rm -f "$ZRAM_CONF"

    nmcli general reload 2>/dev/null || systemctl reload NetworkManager 2>/dev/null || true
    log_success "System settings reverted to baseline defaults."
}

# ==============================================================================
# MODULE 8: IPv6 Protocol Management
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
        echo "  - Prevents IPv6 leaks on VPNs and untrusted Wi-Fi."
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
        echo "Persistence       : Persistent configuration active in $IPV6_SYSCTL_CONF"
    else
        echo "Persistence       : Standard kernel defaults"
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

    log_success "IPv6 has been disabled across network interfaces (localhost ::1 preserved)."
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

    log_success "IPv6 has been enabled across all interfaces."
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
# Master Interactive Dashboard
# ==============================================================================

show_interactive_menu() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${CYAN}======================================================================${NC}"
        echo -e "${BOLD}       Laptop Linux Optimizer & System Control Center (v${VERSION})${NC}"
        echo -e "${CYAN}======================================================================${NC}"
        echo -e "${GREEN}${BOLD}  1) 🚀 Guided Laptop Optimization Wizard (Recommended)${NC}"
        echo -e "     Step-by-step: Updates -> Battery -> DNS -> ZRAM & BBR -> Privacy"
        echo ""
        echo -e "${CYAN}[ 1. Maintenance & Package Updates ]${NC}"
        echo -e "  2) ${BOLD}Update All Packages & Sweep Clean${NC}     | APT dist-upgrade + Flatpak + orphan clean"
        echo -e "  3) ${BOLD}System Housekeeping & Optimization${NC}    | Clean caches, journals, and temp"
        echo ""
        echo -e "${CYAN}[ 2. Hardware Battery Management ]${NC}"
        echo -e "  4) ${BOLD}Battery Diagnostics & Health Report${NC}   | Capacity, cycle count & charge limit status"
        echo -e "  5) ${BOLD}Configure Battery Charge Limiter${NC}      | Set threshold (60% / 80% / 100%) & persistence"
        echo ""
        echo -e "${CYAN}[ 3. Network & Encrypted DNS ]${NC}"
        echo -e "  6) ${BOLD}Encrypted DNS Manager (DoH/Relay/Tor)${NC}| Switch profiles (Cloudflare, Quad9, AdGuard)"
        echo -e "  7) ${BOLD}Check Active DNS Resolvers${NC}            | View active nameservers & proxy state"
        echo -e "  8) ${BOLD}Randomize Network MAC Addresses${NC}       | Instantaneous spoofing + auto-randomization"
        echo -e "  9) ${BOLD}Inspect MAC & Network Interfaces${NC}      | Check active vs permanent hardware MACs"
        echo -e " 10) ${BOLD}IPv6 Protocol Control (Enable/Disable)${NC} | Toggle IPv6 network stack system-wide"
        echo ""
        echo -e "${CYAN}[ 4. Performance Tuning & RAM ]${NC}"
        echo -e " 11) ${BOLD}Performance & Privacy Tuning Menu${NC}     | BBR, ZRAM, Swappiness 100, DHCP privacy"
        echo ""
        echo -e "${CYAN}[ 5. Privacy Scrubbing (Requires App Restart) ]${NC}"
        echo -e " 12) ${BOLD}Privacy & Activity Cache Scrub${NC}        | Clear browser caches, recent files, DNS logs"
        echo ""
        echo -e "${CYAN}[ 6. Automation & Master Tasks ]${NC}"
        echo -e " 13) ${BOLD}Manage Weekly Maintenance Timer${NC}       | Status, install or remove automated schedule"
        echo -e " 14) ${BOLD}TOTAL MASTER SUITE${NC}                     | Update + Housekeeping + Privacy + MAC"
        echo ""
        echo -e "  0) ${BOLD}Exit${NC}"
        echo -e "${CYAN}======================================================================${NC}"
        read -rp "Select an option [0-14]: " choice

        case "$choice" in
            1)
                run_guided_wizard
                read -rp "Press Enter to continue..."
                ;;
            2)
                update_and_clean
                read -rp "Press Enter to continue..."
                ;;
            3)
                run_optimizer
                read -rp "Press Enter to continue..."
                ;;
            4)
                show_battery_status
                read -rp "Press Enter to continue..."
                ;;
            5)
                echo ""
                echo "Preset Modes:"
                echo "  60  - Maximum Lifespan (constantly plugged into AC)"
                echo "  80  - Balanced (recommended everyday longevity)"
                echo "  100 - Full Capacity (travel / maximum portable runtime)"
                read -rp "Enter target threshold percentage [20-100, default: 80]: " tval
                tval="${tval:-80}"
                if [[ "$tval" =~ ^[0-9]+$ ]] && [ "$tval" -ge 20 ] && [ "$tval" -le 100 ]; then
                    read -rp "Enable persistence across reboots & sleep? [Y/n]: " pyn
                    if [[ "$pyn" =~ ^[Nn] ]]; then
                        set_battery_threshold "$tval"
                    else
                        install_battery_service "$tval"
                    fi
                else
                    log_err "Invalid threshold."
                fi
                read -rp "Press Enter to continue..."
                ;;
            6)
                interactive_dns_menu
                read -rp "Press Enter to continue..."
                ;;
            7)
                show_dns_status
                read -rp "Press Enter to continue..."
                ;;
            8)
                read -rp "Randomize network MAC addresses now? [y/N]: " conf_mac
                if [[ "$conf_mac" =~ ^[Yy]$ ]]; then
                    randomize_mac
                else
                    log_info "MAC randomization cancelled."
                fi
                read -rp "Press Enter to continue..."
                ;;
            9)
                show_mac_status
                read -rp "Press Enter to continue..."
                ;;
            10)
                echo ""
                show_ipv6_status
                echo ""
                echo "1) Disable IPv6 (Block IPv6 traffic & VPN/WebRTC leaks)"
                echo "2) Enable IPv6"
                echo "3) Return"
                read -rp "Option: " ipv6_opt
                case "$ipv6_opt" in
                    1) disable_ipv6 ;;
                    2) enable_ipv6 ;;
                esac
                read -rp "Press Enter to continue..."
                ;;
            11)
                echo ""
                show_tuning_status
                echo ""
                echo "1) Apply Performance & Privacy Tunings (BBR, ZRAM, Swappiness 100, DHCP privacy, fast boot)"
                echo "2) Revert Tunings to Standard Mint Defaults"
                echo "3) Return"
                read -rp "Option: " tune_opt
                case "$tune_opt" in
                    1) apply_system_tuning ;;
                    2) revert_system_tuning ;;
                esac
                read -rp "Press Enter to continue..."
                ;;
            12)
                read -rp "Run privacy and activity scrub now? [y/N]: " conf_priv
                if [[ "$conf_priv" =~ ^[Yy]$ ]]; then
                    clean_privacy "privacy"
                else
                    log_info "Privacy scrub cancelled."
                fi
                read -rp "Press Enter to continue..."
                ;;
            13)
                echo ""
                show_timer_status
                echo ""
                echo "1) Install / Enable Weekly Timer"
                echo "2) Uninstall / Disable Weekly Timer"
                echo "3) Return"
                read -rp "Option: " topt
                case "$topt" in
                    1) install_weekly_timer ;;
                    2) uninstall_weekly_timer ;;
                esac
                read -rp "Press Enter to continue..."
                ;;
            14)
                read -rp "Run total master suite (Update + Housekeep + Privacy + MAC)? [y/N]: " conf_suite
                if [[ "$conf_suite" =~ ^[Yy]$ ]]; then
                    run_complete_suite
                else
                    log_info "Master suite cancelled."
                fi
                read -rp "Press Enter to continue..."
                ;;
            0|q|exit)
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
    echo "  ipv6                      IPv6 network protocol control"
    echo "    status                  Display current IPv6 status and active addresses"
    echo "    disable, off            Disable IPv6 system-wide (prevents VPN/WebRTC leaks)"
    echo "    enable, on              Enable IPv6 system-wide"
    echo ""
    echo "  optimize, clean           Run routine housekeeping (APT, Flatpak, journals, temp)"
    echo "  update, upgrade           Update all packages (APT & Flatpak) and purge orphans/caches"
    echo "  all                       Full update followed by complete system housekeeping"
    echo "  privacy                   Scrub privacy caches (browsers, recent files, DNS, trash)"
    echo "  tune, harden              Performance tuning & privacy hardening"
    echo "    status                  Display TCP BBR, ZRAM, swappiness, and privacy status"
    echo "    apply                   Enable BBR, ZRAM, swappiness 100, DHCP privacy & fast boot"
    echo "    revert                  Revert system tunings to standard Linux Mint defaults"
    echo "  full-suite                Total master run: update + housekeeping + privacy + MAC"
    echo ""
    echo "  timer                     Automated weekly background maintenance"
    echo "    status                  View timer status and previous run logs"
    echo "    install                 Install persistent systemd weekly timer"
    echo "    uninstall               Remove systemd weekly timer"
    echo ""
    echo "  menu, interactive         Launch the master interactive terminal dashboard"
    echo "  version, -v, --version    Show version information"
    echo "  help, --help, -h          Show this help manual"
    echo ""
    echo "Options:"
    echo "  -y, --yes, --force        Execute non-interactively without confirmation prompts"
    echo ""
    echo "Examples:"
    echo "  $0                                # Launch master interactive menu"
    echo "  $0 battery status                 # Check battery health & current threshold"
    echo "  sudo $0 battery set 80            # Set charge limiter to 80%"
    echo "  sudo $0 battery install 80        # Persist 80% limit across reboots & sleep"
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
for arg in "${@:-}"; do
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
            disable|off|block)
                disable_ipv6
                ;;
            enable|on)
                enable_ipv6
                ;;
            *)
                log_err "Unknown ipv6 command: '$SUB'"
                echo "Usage: $0 ipv6 [status | disable | enable]"
                exit 1
                ;;
        esac
        ;;

    disable-ipv6)
        disable_ipv6
        ;;

    enable-ipv6)
        enable_ipv6
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
            apply|enable|on)
                apply_system_tuning
                ;;
            revert|disable|off)
                revert_system_tuning
                ;;
            *)
                log_err "Unknown tune command: '$SUB'"
                echo "Usage: $0 tune [status | apply | revert]"
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

    version|-v|--version)
        echo "Laptop Linux Optimizer (mint-admin) v${VERSION}"
        ;;

    menu|interactive|dashboard)
        show_interactive_menu
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
