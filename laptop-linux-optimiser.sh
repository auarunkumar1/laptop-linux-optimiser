#!/usr/bin/env bash
# ==============================================================================
# Laptop Linux Optimizer & Master Administration Suite (laptop-linux-optimiser)
# Version: 0.5.15
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
#   9. Subpixel Font Anti-Blur & High-DPI Scaling (Cinnamon, COSMIC & GNOME)
#  10. ELAN I2C Touchpad Freeze Fix & AMD Bus Power Management
#  11. Popular Themes Gallery & Uniform Styling (GTK3, Libadwaita & Flatpak)
#  12. GRUB Bootloader Baseline & Recovery
#  13. SSH Inbound Server Hardening (Mask / Unmask / Status)
#  14. Multi-OS Platform Detection & Runtime Tuning (Pop!_OS, Linux Mint, Ubuntu, Debian)
#  15. Hardware Drivers, Media Codecs & Font Packs (AMD APU / Mesa / Fonts)
#  16. AMD P-State EPP Governor Tuning (power / balance / performance)
#  17. Audio Powersave DAC Popping & Crackle Fix
#  18. Browser Hardware Video Acceleration (VA-API for Firefox / Brave / Chromium)
#  19. SSD / NVMe Periodic TRIM Maintenance (fstrim.timer)
#  20. Ubuntu Apport Crash Error Popups Shield
#  21. Hardened Laptop UFW Firewall Preset (LocalSend & CUPS friendly)
#  22. PipeWire Bluetooth High-Fidelity Audio Codecs (LDAC, AAC, aptX)
# ==============================================================================

set -euo pipefail

VERSION="0.5.15"
SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

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
BATTERY_CONF="/etc/laptop-battery-limit.conf"
[ ! -f "$BATTERY_CONF" ] && [ -f "/etc/pop-battery-limit.conf" ] && BATTERY_CONF="/etc/pop-battery-limit.conf"
[ ! -f "$BATTERY_CONF" ] && [ -f "/etc/asus-battery-limit.conf" ] && BATTERY_CONF="/etc/asus-battery-limit.conf"
BATTERY_SERVICE="/etc/systemd/system/laptop-battery-limit.service"
BATTERY_SLEEP_HOOK="/usr/lib/systemd/system-sleep/laptop-battery-limit.sh"
[ ! -d "/usr/lib/systemd/system-sleep" ] && [ -d "/lib/systemd/system-sleep" ] && BATTERY_SLEEP_HOOK="/lib/systemd/system-sleep/laptop-battery-limit.sh"
BATTERY_UDEV_RULE="/etc/udev/rules.d/99-laptop-battery-charge-limit.rules"

DNS_CONFIG="/etc/dnscrypt-proxy/dnscrypt-proxy.toml"
DNS_BACKUP="/etc/dnscrypt-proxy/dnscrypt-proxy.toml.orig"
NM_DNS_DROPIN="/etc/NetworkManager/conf.d/00-dnscrypt.conf"
RESOLVED_DNS_DROPIN="/etc/systemd/resolved.conf.d/dnscrypt.conf"

NM_MAC_CONF="/etc/NetworkManager/conf.d/00-macrandomize.conf"

TOUCHPAD_UDEV_RULE="/etc/udev/rules.d/99-elan-power.rules"
TOUCHPAD_SLEEP_HOOK="/usr/lib/systemd/system-sleep/99-elan-resume.sh"
[ ! -d "/usr/lib/systemd/system-sleep" ] && [ -d "/lib/systemd/system-sleep" ] && TOUCHPAD_SLEEP_HOOK="/lib/systemd/system-sleep/99-elan-resume.sh"
TOUCHPAD_LEGACY_GRUB="/etc/default/grub.d/99-elan-polling.cfg"
TOUCHPAD_CSTATE_GRUB="/etc/default/grub.d/99-touchpad-cstate.cfg"
TOUCHPAD_LIBINPUT_QUIRKS="/etc/libinput/local-overrides.quirks"
TOUCHPAD_DIAG_CANONICAL="/usr/local/sbin/diagnose-elan-irq.sh"
TOUCHPAD_ACPI_OVERRIDE="/boot/acpi_override"
TOUCHPAD_ACPI_GRUB="/etc/default/grub.d/99-elan-acpi.cfg"
EVDI_MODULES_CONF="/etc/modules-load.d/evdi.conf"
EVDI_MODPROBE_CONF="/etc/modprobe.d/evdi.conf"

OPTIMIZER_SERVICE="/etc/systemd/system/laptop-optimizer.service"
OPTIMIZER_TIMER="/etc/systemd/system/laptop-optimizer.timer"

PERF_SYSCTL="/etc/sysctl.d/99-laptop-optimizer-performance.conf"
PRIVACY_SYSCTL="/etc/sysctl.d/99-laptop-optimizer-privacy.conf"
BBR_MODULE_CONF="/etc/modules-load.d/bbr.conf"
DHCP_PRIVACY_CONF="/etc/NetworkManager/conf.d/01-privacy-dhcp.conf"
ZRAM_CONF="/etc/default/zramswap"
IPV6_SYSCTL_CONF="/etc/sysctl.d/99-disable-ipv6.conf"

STATE_DIR="/var/lib/laptop-linux-optimiser"
if [ ! -d "$STATE_DIR" ]; then
    if [ -d "/var/lib/pop-admin" ]; then
        STATE_DIR="/var/lib/pop-admin"
    elif [ -d "/var/lib/mint-admin" ]; then
        STATE_DIR="/var/lib/mint-admin"
    fi
fi
BASELINE_SYSCTL="${STATE_DIR}/tuning-baseline.env"
PROFILE_CONF="/etc/laptop-optimizer-profile.conf"
[ ! -f "$PROFILE_CONF" ] && [ -f "/etc/pop-admin-profile.conf" ] && PROFILE_CONF="/etc/pop-admin-profile.conf"
[ ! -f "$PROFILE_CONF" ] && [ -f "/etc/mint-admin-profile.conf" ] && PROFILE_CONF="/etc/mint-admin-profile.conf"

CANONICAL_BIN="/usr/local/sbin/laptop-linux-optimiser"
LOCK_FILE="/var/run/laptop-linux-optimiser.lock"
OS_CONF="/etc/laptop-optimizer-os.conf"
GRUB_DEFAULT_FILE="/etc/default/grub"
GRUB_DEFAULT_TEMPLATE="/usr/share/grub/default/grub"

# ------------------------------------------------------------------------------
# Helper Utilities
# ------------------------------------------------------------------------------

log_info()    { echo -e "${BLUE}[*]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
log_err()     { echo -e "${RED}[✗]${NC} $1"; }

trap 'log_err "Unexpected failure at line $LINENO in command: $BASH_COMMAND"' ERR

check_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo -e "${RED}[-] Error: This operation requires root privileges.${NC}" >&2
        echo -e "${YELLOW}[-] Please run with sudo: sudo \"$0\" ${*:-}${NC}" >&2
        exit 1
    fi
    acquire_lock
}

check_root_nolock() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo -e "${RED}[-] Error: This operation requires root privileges.${NC}" >&2
        echo -e "${YELLOW}[-] Please run with sudo: sudo \"$0\" ${*:-}${NC}" >&2
        exit 1
    fi
}

acquire_lock() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        if [ "${OPTIMIZER_LOCKED:-0}" = "1" ]; then
            return 0
        fi
        mkdir -p /var/run
        exec 200>"$LOCK_FILE"
        if ! flock -n 200; then
            log_err "Another instance of laptop-linux-optimiser is currently running."
            exit 1
        fi
        export OPTIMIZER_LOCKED=1
    fi
}

ensure_canonical_bin() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        if [ ! -f "$CANONICAL_BIN" ] || [ "$SCRIPT_PATH" -nt "$CANONICAL_BIN" ]; then
            mkdir -p "$(dirname "$CANONICAL_BIN")"
            if install -m 755 -o root -g root "$SCRIPT_PATH" "$CANONICAL_BIN" 2>/dev/null || cp "$SCRIPT_PATH" "$CANONICAL_BIN" 2>/dev/null; then
                chmod 755 "$CANONICAL_BIN" 2>/dev/null || true
                ln -sf "$CANONICAL_BIN" /usr/local/sbin/pop-admin 2>/dev/null || true
                ln -sf "$CANONICAL_BIN" /usr/local/sbin/mint-admin 2>/dev/null || true
                ln -sf "$CANONICAL_BIN" /usr/local/sbin/laptop-optimizer 2>/dev/null || true
                ln -sf "$CANONICAL_BIN" /usr/local/sbin/ubuntu-optimizer 2>/dev/null || true
            fi
        fi
    fi
}

is_safe_home() {
    local candidate="${1:-}"
    [ -n "$candidate" ] || return 1
    [ -d "$candidate" ] || return 1
    [ -L "$candidate" ] && return 1

    local real_cand
    real_cand=$(realpath -q "$candidate") || return 1
    [[ "$real_cand" == "/home/"* || "$real_cand" == "/root" ]] || return 1
    return 0
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

    # Allow when target is the home directory itself (self guard)
    if [ "$real_target" = "$real_h" ]; then
        return 0
    fi

    # Strictly require child target to reside beneath the verified home
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

run_user_gsettings() {
    local target_user="${SUDO_USER:-$USER}"
    if ! command -v gsettings >/dev/null 2>&1; then
        return 0
    fi
    if [ -z "$target_user" ] || [ "$target_user" = "root" ]; then
        gsettings "$@" 2>/dev/null || true
        return 0
    fi
    local user_uid
    user_uid=$(id -u "$target_user" 2>/dev/null || echo "")
    if [ -n "$user_uid" ] && [ -S "/run/user/${user_uid}/bus" ]; then
        sudo -u "$target_user" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${user_uid}/bus" gsettings "$@" 2>/dev/null || true
    elif [ -n "$user_uid" ]; then
        sudo -u "$target_user" gsettings "$@" 2>/dev/null || true
    else
        gsettings "$@" 2>/dev/null || true
    fi
}

get_user_gsettings() {
    local target_user="${SUDO_USER:-$USER}"
    if ! command -v gsettings >/dev/null 2>&1; then
        echo ""
        return 0
    fi
    if [ -z "$target_user" ] || [ "$target_user" = "root" ]; then
        gsettings "$@" 2>/dev/null || echo ""
        return 0
    fi
    local user_uid
    user_uid=$(id -u "$target_user" 2>/dev/null || echo "")
    if [ -n "$user_uid" ] && [ -S "/run/user/${user_uid}/bus" ]; then
        sudo -u "$target_user" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${user_uid}/bus" gsettings "$@" 2>/dev/null || echo ""
    elif [ -n "$user_uid" ]; then
        sudo -u "$target_user" gsettings "$@" 2>/dev/null || echo ""
    else
        gsettings "$@" 2>/dev/null || echo ""
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

# ------------------------------------------------------------------------------
# OS Platform Detection & Target OS Switching (Ubuntu LTS vs Pop!_OS vs Linux Mint)
# ------------------------------------------------------------------------------

detect_system_os() {
    if [ -f "/etc/os-release" ]; then
        if grep -qi "ID=ubuntu" /etc/os-release || grep -qi "Ubuntu" /etc/os-release; then
            echo "ubuntu"
            return
        elif grep -qi "ID=pop" /etc/os-release || grep -qi "Pop!_OS" /etc/os-release; then
            echo "popos"
            return
        elif grep -qi "ID=linuxmint" /etc/os-release || grep -qi "Linux Mint" /etc/os-release; then
            echo "mint"
            return
        fi
    fi
    if [ "${XDG_CURRENT_DESKTOP:-}" = "ubuntu:GNOME" ] || [ "${XDG_CURRENT_DESKTOP:-}" = "GNOME" ]; then
        echo "ubuntu"
    elif [ -d "${HOME}/.config/cosmic" ] || [ "${XDG_CURRENT_DESKTOP:-}" = "COSMIC" ]; then
        echo "popos"
    elif [ -d "${HOME}/.config/cinnamon" ] || [ "${XDG_CURRENT_DESKTOP:-}" = "X-Cinnamon" ]; then
        echo "mint"
    else
        echo "ubuntu"
    fi
}

get_target_os() {
    if [ -f "$OS_CONF" ]; then
        local saved_os
        saved_os=$(grep "^TARGET_OS=" "$OS_CONF" 2>/dev/null | cut -d= -f2 | tr -d ' "')
        if [ "$saved_os" = "ubuntu" ] || [ "$saved_os" = "popos" ] || [ "$saved_os" = "mint" ]; then
            echo "$saved_os"
            return
        fi
    fi
    detect_system_os
}

set_target_os() {
    local target="$1"
    check_root "os" "set" "$target"
    case "$target" in
        ubuntu|ubuntults|ubuntu_lts)
            echo "TARGET_OS=ubuntu" > "$OS_CONF"
            chmod 644 "$OS_CONF"
            log_success "Target OS set to: Ubuntu LTS (GNOME Desktop Edition)."
            ;;
        pop|popos|pop_os)
            echo "TARGET_OS=popos" > "$OS_CONF"
            chmod 644 "$OS_CONF"
            log_success "Target OS set to: Pop!_OS (COSMIC Desktop Edition)."
            ;;
        mint|linuxmint)
            echo "TARGET_OS=mint" > "$OS_CONF"
            chmod 644 "$OS_CONF"
            log_success "Target OS set to: Linux Mint (Cinnamon Desktop Edition)."
            ;;
        detect|auto|reset)
            rm -f "$OS_CONF"
            log_success "Target OS reset to auto-detected: $(detect_system_os)"
            ;;
        *)
            log_err "Unknown OS: '$target'. Choose 'ubuntu', 'popos' or 'mint'."
            return 1
            ;;
    esac
}

toggle_target_os() {
    check_root "os" "toggle"
    local cur
    cur=$(get_target_os)
    if [ "$cur" = "ubuntu" ]; then
        set_target_os "popos"
    elif [ "$cur" = "popos" ]; then
        set_target_os "mint"
    else
        set_target_os "ubuntu"
    fi
}

status_get_target_os() {
    local os
    os=$(get_target_os)
    if [ "$os" = "ubuntu" ]; then
        echo "Ubuntu LTS (GNOME DE)"
    elif [ "$os" = "popos" ]; then
        echo "Pop!_OS (COSMIC DE)"
    else
        echo "Linux Mint (Cinnamon)"
    fi
}

# ------------------------------------------------------------------------------
# SSH Server Inbound Shield & Hardening
# ------------------------------------------------------------------------------

status_get_ssh_server() {
    if systemctl is-enabled ssh.service 2>/dev/null | grep -q "masked" || systemctl is-enabled sshd.service 2>/dev/null | grep -q "masked" || systemctl is-enabled ssh.socket 2>/dev/null | grep -q "masked"; then
        echo "MASKED (Server blocked)"
    elif systemctl is-active --quiet ssh.service 2>/dev/null || systemctl is-active --quiet ssh.socket 2>/dev/null || systemctl is-active --quiet sshd.service 2>/dev/null; then
        echo "ACTIVE (Port 22 open)"
    elif command -v sshd &>/dev/null; then
        echo "DISABLED (Installed, inactive)"
    else
        echo "NOT INSTALLED (Client only)"
    fi
}

enable_ssh_hardening() {
    check_root "tune" "ssh" "enable"
    log_info "Masking and disabling SSH server inbound listeners..."
    systemctl stop ssh.service sshd.service ssh.socket 2>/dev/null || true
    systemctl disable ssh.service sshd.service ssh.socket 2>/dev/null || true
    systemctl mask ssh.service sshd.service ssh.socket 2>/dev/null || true
    log_success "SSH server masked & blocked (cannot be spawned by systemd or sockets)."
}

disable_ssh_hardening() {
    check_root "tune" "ssh" "disable"
    log_info "Unmasking SSH server units..."
    systemctl unmask ssh.service sshd.service ssh.socket 2>/dev/null || true
    log_success "SSH server units unmasked."
}

toggle_ssh_hardening() {
    check_root "tune" "ssh" "toggle"
    local cur
    cur=$(status_get_ssh_server)
    if [[ "$cur" =~ MASKED ]]; then
        disable_ssh_hardening
    else
        enable_ssh_hardening
    fi
}

# ------------------------------------------------------------------------------
# Root User Access Hardening & Delegation
# ------------------------------------------------------------------------------
ROOT_LOCK_CONF="/etc/laptop-root-lock.conf"
SSH_ROOT_DROPIN="/etc/ssh/sshd_config.d/00-disable-root-login.conf"

status_get_root_lock() {
    # Check shadow if readable (running as root or elevated)
    if [ -r "/etc/shadow" ]; then
        local pass_field
        pass_field=$(grep "^root:" /etc/shadow 2>/dev/null | cut -d: -f2 || echo "")
        if [[ "$pass_field" =~ ^[\!\*] ]] || [ "$pass_field" = "!" ] || [ "$pass_field" = "*" ]; then
            if [ -f "$SSH_ROOT_DROPIN" ] || [ -f "$ROOT_LOCK_CONF" ]; then
                echo "LOCKED & SHIELDED (Sudo only)"
            else
                echo "LOCKED (Password disabled)"
            fi
            return
        elif [ -n "$pass_field" ]; then
            echo "UNLOCKED (Password set)"
            return
        fi
    fi

    # Fallback when /etc/shadow is not readable (unprivileged user-space)
    if [ -f "$ROOT_LOCK_CONF" ] || [ -f "$SSH_ROOT_DROPIN" ]; then
        echo "LOCKED & SHIELDED (Sudo only)"
    else
        echo "LOCKED (Default sudo-only)"
    fi
}

lock_root_user() {
    check_root "root" "lock"

    # Pre-flight safety check: Ensure at least one sudo-capable user exists
    local admin_user="${SUDO_USER:-}"
    local has_sudo_admin=0

    if [ -n "$admin_user" ] && [ "$admin_user" != "root" ]; then
        if id -nG "$admin_user" 2>/dev/null | grep -E -q "\b(sudo|wheel|admin)\b"; then
            has_sudo_admin=1
        fi
    fi

    if [ "$has_sudo_admin" -eq 0 ]; then
        if getent group sudo 2>/dev/null | grep -E -q ":[a-zA-Z0-9_-]+"; then
            has_sudo_admin=1
        elif getent group wheel 2>/dev/null | grep -E -q ":[a-zA-Z0-9_-]+"; then
            has_sudo_admin=1
        fi
    fi

    if [ "$has_sudo_admin" -eq 0 ]; then
        log_err "Pre-flight safety check failed: No administrative user found in 'sudo' or 'wheel' group."
        log_err "Aborting root password lock to prevent administrative lockout."
        return 1
    fi

    log_info "Locking root user password in /etc/shadow..."
    passwd -l root 2>/dev/null || usermod -L root 2>/dev/null || true

    # Ensure root shell in /etc/passwd is a standard valid shell, NOT nologin
    local cur_shell
    cur_shell=$(grep "^root:" /etc/passwd 2>/dev/null | cut -d: -f7 || echo "")
    if [[ "$cur_shell" =~ (nologin|false) ]]; then
        log_warn "Root shell was set to '$cur_shell' (breaks emergency recovery & sudo -i). Restoring /bin/bash..."
        chsh -s /bin/bash root 2>/dev/null || usermod -s /bin/bash root 2>/dev/null || true
    fi

    # Block direct SSH root login if OpenSSH server is present or configured
    if [ -d "/etc/ssh" ]; then
        mkdir -p "/etc/ssh/sshd_config.d" 2>/dev/null || true
        cat << 'EOF_SSH' > "$SSH_ROOT_DROPIN"
# Managed by Laptop Linux Optimizer
# Disables direct remote SSH login for root account
PermitRootLogin no
EOF_SSH
        chmod 0644 "$SSH_ROOT_DROPIN" 2>/dev/null || true
        log_info "Configured OpenSSH drop-in: $SSH_ROOT_DROPIN (PermitRootLogin no)."
    fi

    # Backup and disable /root/.ssh/authorized_keys if present
    if [ -f "/root/.ssh/authorized_keys" ]; then
        local key_count
        key_count=$(wc -l < "/root/.ssh/authorized_keys" 2>/dev/null || echo 0)
        if [ "$key_count" -gt 0 ]; then
            log_warn "Found $key_count authorized SSH key(s) in /root/.ssh/authorized_keys."
            log_info "Moving /root/.ssh/authorized_keys to /root/.ssh/authorized_keys.disabled..."
            mv -f "/root/.ssh/authorized_keys" "/root/.ssh/authorized_keys.disabled" 2>/dev/null || true
            chmod 0600 "/root/.ssh/authorized_keys.disabled" 2>/dev/null || true
        fi
    fi

    # Write state manifest
    cat << EOF_RL > "$ROOT_LOCK_CONF"
# Managed by Laptop Linux Optimizer
ROOT_LOCKED="true"
SSH_ROOT_BLOCKED="true"
LAST_APPLIED="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "applied")"
EOF_RL
    chmod 0644 "$ROOT_LOCK_CONF" 2>/dev/null || true

    log_success "Root account safely locked! Password disabled & direct SSH login blocked (sudo access preserved)."
}

unlock_root_user() {
    check_root "root" "unlock"
    log_info "Unlocking root account..."
    passwd -u root 2>/dev/null || true

    if [ -f "$SSH_ROOT_DROPIN" ]; then
        rm -f "$SSH_ROOT_DROPIN" 2>/dev/null || true
        log_info "Removed OpenSSH root block: $SSH_ROOT_DROPIN"
    fi

    if [ -f "/root/.ssh/authorized_keys.disabled" ]; then
        mv -f "/root/.ssh/authorized_keys.disabled" "/root/.ssh/authorized_keys" 2>/dev/null || true
        log_info "Restored /root/.ssh/authorized_keys"
    fi

    rm -f "$ROOT_LOCK_CONF" 2>/dev/null || true
    log_success "Root account unlocked."
}

toggle_root_user() {
    local cur
    cur=$(status_get_root_lock)
    if [[ "$cur" =~ UNLOCKED ]]; then
        lock_root_user
    else
        read -rp "Root is currently locked. Do you really want to unlock the root account? [y/N]: " conf_unlock
        if [[ "$conf_unlock" =~ ^[Yy]$ ]]; then
            unlock_root_user
        else
            log_info "Root lock retained."
        fi
    fi
}

show_root_hardening_status() {
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}              Root User Access & Account Hardening Status             ${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "Root Lock State        : ${GREEN}${BOLD}$(status_get_root_lock)${NC}"
    echo -e "Root Shell             : $(grep "^root:" /etc/passwd 2>/dev/null | cut -d: -f7 || echo "/bin/bash")"

    local sudo_users
    sudo_users=$(getent group sudo 2>/dev/null | cut -d: -f4 || echo "")
    [ -z "$sudo_users" ] && sudo_users=$(getent group wheel 2>/dev/null | cut -d: -f4 || echo "")
    echo -e "Authorized Sudo Users  : ${CYAN}${sudo_users:-"None found"}${NC}"

    if [ -f "$SSH_ROOT_DROPIN" ]; then
        echo -e "SSH PermitRootLogin    : ${GREEN}BLOCK ENFORCED (/etc/ssh/sshd_config.d/00-disable-root-login.conf)${NC}"
    else
        echo -e "SSH PermitRootLogin    : ${YELLOW}DEFAULT (No drop-in override)${NC}"
    fi

    if [ -f "/root/.ssh/authorized_keys" ]; then
        echo -e "Root Authorized Keys   : ${YELLOW}PRESENT (/root/.ssh/authorized_keys)${NC}"
    elif [ -f "/root/.ssh/authorized_keys.disabled" ]; then
        echo -e "Root Authorized Keys   : ${GREEN}DISABLED (Backed up to authorized_keys.disabled)${NC}"
    else
        echo -e "Root Authorized Keys   : ${GREEN}NONE (No direct SSH keys)${NC}"
    fi
    echo -e "${CYAN}======================================================================${NC}"
}


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
    elif systemctl is-active --quiet system76-power.service 2>/dev/null; then
        echo -e "Power Daemon     : system76-power (active)"
    elif systemctl is-active --quiet power-profiles-daemon.service 2>/dev/null; then
        echo -e "Power Daemon     : power-profiles-daemon (active)"
    elif systemctl is-active --quiet upower.service 2>/dev/null; then
        echo -e "Power Daemon     : upower (active)"
    fi

    # Persistence check
    if [ -f "$BATTERY_SERVICE" ] && (systemctl is-enabled --quiet laptop-battery-limit.service 2>/dev/null || systemctl is-enabled --quiet asus-battery-limit.service 2>/dev/null || systemctl is-enabled --quiet pop-battery-limit.service 2>/dev/null); then
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
SUBSYSTEM=="power_supply", KERNEL=="BAT[0-9]*", TEST=="charge_control_end_threshold", IMPORT{file}="$BATTERY_CONF", ATTR{charge_control_end_threshold}="\$env{THRESHOLD}"

# 2. Re-trigger persistence service on AC power state change (Mains)
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ACTION=="change", RUN+="/usr/bin/systemctl --no-block restart laptop-battery-limit.service"
EOF
        udevadm control --reload-rules 2>/dev/null || true
    fi

    if [ -f "$BATTERY_SERVICE" ]; then
        systemctl restart laptop-battery-limit.service pop-battery-limit.service asus-battery-limit.service 2>/dev/null || true
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
Description=Laptop Battery Charge Limit Persister
DefaultDependencies=no
After=local-fs.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'if [ -f /etc/laptop-battery-limit.conf ]; then . /etc/laptop-battery-limit.conf; elif [ -f /etc/pop-battery-limit.conf ]; then . /etc/pop-battery-limit.conf; elif [ -f /etc/asus-battery-limit.conf ]; then . /etc/asus-battery-limit.conf; else THRESHOLD=80; fi; for bat in /sys/class/power_supply/BAT*/charge_control_end_threshold; do [ -f "$bat" ] && [ "$(cat "$bat" 2>/dev/null)" != "$THRESHOLD" ] && echo "$THRESHOLD" > "$bat" 2>/dev/null || true; done'
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
            if [ -f /etc/laptop-battery-limit.conf ]; then
                . /etc/laptop-battery-limit.conf
            elif [ -f /etc/pop-battery-limit.conf ]; then
                . /etc/pop-battery-limit.conf
            elif [ -f /etc/asus-battery-limit.conf ]; then
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
        if command -v systemd-run >/dev/null 2>&1; then
            systemd-run --no-block --on-active=2s /usr/bin/systemctl restart laptop-battery-limit.service >/dev/null 2>&1 || true
        fi
        ;;
esac
EOF
        chmod +x "$BATTERY_SLEEP_HOOK"
    fi

    # 3. Write udev rule (direct attribute assignment on battery add/change, and AC plug watcher)
    if [ -d "/etc/udev/rules.d" ]; then
        cat << EOF > "$BATTERY_UDEV_RULE"
# 1. Direct sysfs attribute assignment via udev on battery add/change
SUBSYSTEM=="power_supply", KERNEL=="BAT[0-9]*", TEST=="charge_control_end_threshold", IMPORT{file}="$BATTERY_CONF", ATTR{charge_control_end_threshold}="\$env{THRESHOLD}"

# 2. Re-trigger persistence service on AC power state change (Mains)
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ACTION=="change", RUN+="/usr/bin/systemctl --no-block restart laptop-battery-limit.service"
EOF
        udevadm control --reload-rules 2>/dev/null || true
    fi

    systemctl daemon-reload
    systemctl enable laptop-battery-limit.service 2>/dev/null || true
    systemctl restart laptop-battery-limit.service 2>/dev/null || true

    set_battery_threshold "$val"
    log_success "Persistent battery limiter active across reboots, sleep/wake, and AC plug events!"
}

uninstall_battery_service() {
    check_root "battery" "uninstall"

    log_info "Removing persistent battery charge limiter..."
    systemctl stop laptop-battery-limit.service pop-battery-limit.service asus-battery-limit.service 2>/dev/null || true
    systemctl disable laptop-battery-limit.service pop-battery-limit.service asus-battery-limit.service 2>/dev/null || true
    rm -f "$BATTERY_SERVICE" "$BATTERY_CONF" "$BATTERY_UDEV_RULE"
    rm -f /usr/lib/systemd/system-sleep/laptop-battery-limit.sh /usr/lib/systemd/system-sleep/asus-battery-limit.sh /lib/systemd/system-sleep/asus-battery-limit.sh /lib/systemd/system-sleep/laptop-battery-limit.sh
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

get_system_hostname() {
    local host_name=""
    if command -v hostnamectl &>/dev/null; then
        host_name=$(hostnamectl --static 2>/dev/null || true)
    fi
    if [ -z "$host_name" ] && command -v hostname &>/dev/null; then
        host_name=$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)
    fi
    if [ -z "$host_name" ] && [ -r "/etc/hostname" ]; then
        host_name=$(head -n 1 /etc/hostname 2>/dev/null | tr -d '[:space:]' || true)
    fi
    if [ -z "$host_name" ]; then
        host_name=$(uname -n 2>/dev/null || true)
    fi
    echo "$host_name" | tr -d '[:space:]'
}

ensure_hostname_resolution() {
    local hosts_file="${1:-/etc/hosts}"
    local host_name="${2:-}"

    if [ -z "$host_name" ]; then
        host_name=$(get_system_hostname)
    fi

    if [ -z "$host_name" ]; then
        log_warn "Unable to detect system hostname; skipping /etc/hosts verification."
        return 0
    fi

    if [ ! -f "$hosts_file" ]; then
        if [ -w "$(dirname "$hosts_file")" ]; then
            touch "$hosts_file"
        else
            return 0
        fi
    fi

    # Check if the dynamic system hostname is already mapped to any address in /etc/hosts
    if grep -E "^[[:space:]]*[0-9a-fA-F:.]+[[:space:]]+.*\\b${host_name}\\b" "$hosts_file" >/dev/null 2>&1; then
        log_info "System hostname '$host_name' is already mapped in $hosts_file."
        return 0
    fi

    if [ ! -w "$hosts_file" ]; then
        log_warn "$hosts_file is not writable; run with sudo to map system hostname."
        return 1
    fi

    log_info "Mapping system hostname '$host_name' in $hosts_file to prevent local DNS deadlock..."
    if grep -E "^[[:space:]]*127\.0\.1\.1[[:space:]]" "$hosts_file" >/dev/null 2>&1; then
        sed -i -E "s/^([[:space:]]*127\.0\.1\.1[[:space:]]+.*)/\1 ${host_name}/" "$hosts_file"
    elif grep -E "^[[:space:]]*127\.0\.0\.1[[:space:]]" "$hosts_file" >/dev/null 2>&1; then
        sed -i "/^[[:space:]]*127\.0\.0\.1[[:space:]]/a 127.0.1.1\t${host_name}" "$hosts_file"
    else
        echo -e "127.0.1.1\t${host_name}" >> "$hosts_file"
    fi
    log_success "System hostname '$host_name' successfully mapped to 127.0.1.1 in $hosts_file."
}

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

    # Verify SOCKS port readiness (allow up to 10 seconds for initial bootstrap)
    local retries=10
    local tor_ready=0
    log_info "Waiting for Tor SOCKS proxy listener on 127.0.0.1:9050..."
    while [ "$retries" -gt 0 ]; do
        if command -v ss &>/dev/null && ss -ltn 'sport = :9050' | grep -q ":9050"; then
            tor_ready=1
            break
        elif command -v nc &>/dev/null && nc -z 127.0.0.1 9050 2>/dev/null; then
            tor_ready=1
            break
        elif (echo > /dev/tcp/127.0.0.1/9050) 2>/dev/null; then
            tor_ready=1
            break
        fi
        sleep 1
        retries=$((retries - 1))
    done

    if [ "$tor_ready" -eq 1 ]; then
        log_success "Tor is active and SOCKS proxy is listening on 127.0.0.1:9050."
    else
        log_warn "Tor daemon active, but SOCKS port 9050 not yet answering (circuits may still be establishing)."
    fi
}

apply_dnscrypt_config() {
    local servers="$1"
    local use_anonymized="$2"
    local use_tor="$3"

    [ -f "$DNS_CONFIG" ] || { log_err "dnscrypt-proxy configuration file not found at $DNS_CONFIG!"; return 1; }
    [ -f "$DNS_BACKUP" ] || cp "$DNS_CONFIG" "$DNS_BACKUP" 2>/dev/null || true
    cp "$DNS_CONFIG" "${DNS_CONFIG}.bak"

    log_info "Applying settings to $DNS_CONFIG..."

    sed -i "s/^listen_addresses = .*/listen_addresses = []/" "$DNS_CONFIG"
    if grep -q "^server_names =" "$DNS_CONFIG"; then
        sed -i "s/^server_names = .*/server_names = $servers/" "$DNS_CONFIG"
    else
        sed -i "/^listen_addresses =/a server_names = $servers" "$DNS_CONFIG"
    fi

    # Always strip existing proxy and force_tcp settings before re-applying
    sed -i '/^[[:space:]]*proxy[[:space:]]*=/d; /^[[:space:]]*force_tcp[[:space:]]*=/d' "$DNS_CONFIG"

    # Privacy Hardening: Disable on-disk query and NX domain logging (absolute or relative)
    sed -i -E "s|^[[:space:]]*file[[:space:]]*=.*query\.log.*|file = ''|" "$DNS_CONFIG" 2>/dev/null || true
    sed -i -E "s|^[[:space:]]*file[[:space:]]*=.*nx\.log.*|file = ''|" "$DNS_CONFIG" 2>/dev/null || true

    # Privacy Hardening: Enforce high-efficiency local in-memory caching
    sed -i '/^cache =/d; /^cache_size =/d; /^cache_min_ttl =/d; /^cache_max_ttl =/d' "$DNS_CONFIG"
    sed -i "/^server_names =/a cache = true\ncache_size = 8192\ncache_min_ttl = 2400\ncache_max_ttl = 86400" "$DNS_CONFIG"

    # Privacy Hardening: Direct fallback resolvers & ignore system DNS to prevent boot-time circular deadlocks
    sed -i '/^[[:space:]]*fallback_resolvers[[:space:]]*=/d; /^[[:space:]]*ignore_system_dns[[:space:]]*=/d' "$DNS_CONFIG"
    sed -i "/^server_names =/a fallback_resolvers = ['9.9.9.9:53', '149.112.112.112:53', '1.1.1.1:53', '1.0.0.1:53']\nignore_system_dns = true" "$DNS_CONFIG"

    # Privacy Hardening: Dynamic IPv6 alignment with Module 8
    local ipv6_dis
    ipv6_dis=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo "0")
    sed -i '/^block_ipv6 =/d' "$DNS_CONFIG"
    if [ "$ipv6_dis" -eq 1 ]; then
        sed -i "/^server_names =/a block_ipv6 = true" "$DNS_CONFIG"
    else
        sed -i "/^server_names =/a block_ipv6 = false" "$DNS_CONFIG"
    fi

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

snapshot_dns_baseline() {
    mkdir -p "${STATE_DIR}/dns_baseline"
    if [ -f "$NM_DNS_DROPIN" ] && [ ! -f "${STATE_DIR}/dns_baseline/nm_dropin.orig" ]; then
        if ! grep -q "127.0.2.1" "$NM_DNS_DROPIN" 2>/dev/null; then
            cp "$NM_DNS_DROPIN" "${STATE_DIR}/dns_baseline/nm_dropin.orig" 2>/dev/null || true
        fi
    fi
    if [ -f "$RESOLVED_DNS_DROPIN" ] && [ ! -f "${STATE_DIR}/dns_baseline/resolved_dropin.orig" ]; then
        if ! grep -q "127.0.2.1" "$RESOLVED_DNS_DROPIN" 2>/dev/null; then
            cp "$RESOLVED_DNS_DROPIN" "${STATE_DIR}/dns_baseline/resolved_dropin.orig" 2>/dev/null || true
        fi
    fi
}

setup_system_dns() {
    log_info "Configuring system DNS drop-ins for 127.0.2.1..."
    ensure_hostname_resolution
    snapshot_dns_baseline

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
LLMNR=no
MulticastDNS=no
ResolveUnicastSingleLabel=yes
EOF
    fi
    log_success "System DNS directed to local proxy (127.0.2.1) with LLMNR & mDNS leak suppression."
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
    if systemctl cat dnscrypt-proxy.socket &>/dev/null || systemctl list-unit-files dnscrypt-proxy.socket 2>/dev/null | grep -q dnscrypt-proxy.socket; then
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

    local sys_routed=0
    if command -v resolvectl &>/dev/null && systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        if resolvectl dns 2>/dev/null | grep -q "127.0.2.1"; then
            sys_routed=1
        fi
    fi

    local sys_ip=""
    sys_ip=$(getent ahostsv4 example.com 2>/dev/null | awk '{print $1}' | head -n1 || true)
    if [ -n "$sys_ip" ]; then
        if [ "$sys_routed" -eq 1 ]; then
            log_success "System-wide DNS resolution verified active via local proxy (example.com -> $sys_ip)!"
        else
            log_success "System-wide DNS resolution verified active (example.com -> $sys_ip)."
        fi
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
    if [ -f "${STATE_DIR}/dns_baseline/nm_dropin.orig" ]; then
        cp "${STATE_DIR}/dns_baseline/nm_dropin.orig" "$NM_DNS_DROPIN" 2>/dev/null || true
        log_info "Restored original NetworkManager DNS drop-in."
    else
        rm -f "$NM_DNS_DROPIN"
    fi
    if [ -f "${STATE_DIR}/dns_baseline/resolved_dropin.orig" ]; then
        cp "${STATE_DIR}/dns_baseline/resolved_dropin.orig" "$RESOLVED_DNS_DROPIN" 2>/dev/null || true
        log_info "Restored original systemd-resolved DNS drop-in."
    else
        rm -f "$RESOLVED_DNS_DROPIN"
    fi
    rm -rf "${STATE_DIR}/dns_baseline" 2>/dev/null || true
    [ -f "$DNS_BACKUP" ] && cp "$DNS_BACKUP" "$DNS_CONFIG" && log_info "Restored baseline $DNS_CONFIG"
    [ ! -f "$DNS_BACKUP" ] && [ -f "${DNS_CONFIG}.bak" ] && cp "${DNS_CONFIG}.bak" "$DNS_CONFIG"
    [ -f "$DNS_CONFIG" ] && sed -i '/^[[:space:]]*proxy[[:space:]]*=/d; /^[[:space:]]*force_tcp[[:space:]]*=/d' "$DNS_CONFIG" 2>/dev/null || true
    systemctl reset-failed dnscrypt-proxy.service dnscrypt-proxy.socket 2>/dev/null || true
    systemctl stop dnscrypt-proxy.service dnscrypt-proxy.socket 2>/dev/null || true
    systemctl disable dnscrypt-proxy.service dnscrypt-proxy.socket 2>/dev/null || true

    if systemctl is-active systemd-resolved &>/dev/null; then
        systemctl restart systemd-resolved
    fi
    nmcli general reload 2>/dev/null || systemctl reload NetworkManager 2>/dev/null || systemctl restart NetworkManager 2>/dev/null

    log_success "System restored to default DHCP DNS."
}

clean_network_overrides() {
    check_root "network" "clean-overrides"
    log_info "Cleaning custom DNS drop-ins, legacy shields, and DPI firewall rules..."
    log_info "Ensuring 100% clean baseline compatibility for Cloudflare WARP and standard networking..."

    # 1. Stop and disable legacy DNS, shield, and DPI services
    systemctl stop dnscrypt-proxy.service dnscrypt-proxy.socket laptop-dns-shield.service laptop-dpi-mss.service byedpi.service 2>/dev/null || true
    systemctl disable dnscrypt-proxy.service dnscrypt-proxy.socket laptop-dns-shield.service laptop-dpi-mss.service byedpi.service 2>/dev/null || true

    # 2. Remove configuration drop-ins, state flags, and obsolete files
    rm -f "$NM_DNS_DROPIN" "$RESOLVED_DNS_DROPIN" \
          "/etc/systemd/system/laptop-dns-shield.service" \
          "/etc/systemd/system/laptop-dpi-mss.service" \
          "/etc/systemd/system/byedpi.service" \
          "${STATE_DIR}/dpi-mss-value" \
          "${STATE_DIR}/dpi-mode" \
          "${STATE_DIR}/dns-shield-active" \
          "/etc/NetworkManager/conf.d/20-connectivity.conf" \
          "/etc/byedpi.conf" \
          "/usr/local/bin/ciadpi"
    userdel "byedpi" 2>/dev/null || true

    # 3. Flush all legacy netfilter rules created by laptop-optimizer (dns-shield, dpi)
    if command -v iptables &>/dev/null; then
        while IFS= read -r rule; do
            [ -n "$rule" ] || continue
            local del_cmd
            del_cmd=$(echo "$rule" | sed 's/^-A/-D/')
            iptables -w 5 $del_cmd 2>/dev/null || true
        done < <(iptables -w 5 -S OUTPUT 2>/dev/null | grep -E "laptop-optimizer-dns-shield|laptop-optimizer-dpi" || true)

        while IFS= read -r rule; do
            [ -n "$rule" ] || continue
            local del_cmd
            del_cmd=$(echo "$rule" | sed 's/^-A/-D/')
            iptables -w 5 -t mangle $del_cmd 2>/dev/null || true
        done < <(iptables -w 5 -t mangle -S INPUT 2>/dev/null | grep -E "laptop-optimizer-dpi" || true)

        while IFS= read -r rule; do
            [ -n "$rule" ] || continue
            local del_cmd
            del_cmd=$(echo "$rule" | sed 's/^-A/-D/')
            iptables -w 5 -t nat $del_cmd 2>/dev/null || true
        done < <(iptables -w 5 -t nat -S OUTPUT 2>/dev/null | grep -E "laptop-optimizer-dpi" || true)
    fi

    if command -v ip6tables &>/dev/null; then
        while IFS= read -r rule; do
            [ -n "$rule" ] || continue
            local del_cmd
            del_cmd=$(echo "$rule" | sed 's/^-A/-D/')
            ip6tables -w 5 $del_cmd 2>/dev/null || true
        done < <(ip6tables -w 5 -S OUTPUT 2>/dev/null | grep -E "laptop-optimizer-dns-shield|laptop-optimizer-dpi" || true)

        while IFS= read -r rule; do
            [ -n "$rule" ] || continue
            local del_cmd
            del_cmd=$(echo "$rule" | sed 's/^-A/-D/')
            ip6tables -w 5 -t mangle $del_cmd 2>/dev/null || true
        done < <(ip6tables -w 5 -t mangle -S INPUT 2>/dev/null | grep -E "laptop-optimizer-dpi" || true)

        while IFS= read -r rule; do
            [ -n "$rule" ] || continue
            local del_cmd
            del_cmd=$(echo "$rule" | sed 's/^-A/-D/')
            ip6tables -w 5 -t nat $del_cmd 2>/dev/null || true
        done < <(ip6tables -w 5 -t nat -S OUTPUT 2>/dev/null | grep -E "laptop-optimizer-dpi" || true)
    fi

    # 4. Clean up rogue NetworkManager/Netplan configurations for CloudflareWARP
    # Cloudflare WARP is a self-managing daemon (warp-svc). NetworkManager must NEVER
    # manage the CloudflareWARP tun interface, or it injects static routes and causes routing loops on boot.
    if command -v nmcli &>/dev/null; then
        while IFS= read -r uuid; do
            [ -n "$uuid" ] || continue
            nmcli connection delete "$uuid" 2>/dev/null || true
        done < <(nmcli -t -f UUID,NAME,TYPE connection show 2>/dev/null | grep -E ':(CloudflareWARP|tun)' | cut -d: -f1 || true)
    fi

    # Remove rogue Netplan YAML files that captured CloudflareWARP routes
    for f in /etc/netplan/90-NM-*.yaml; do
        [ -f "$f" ] || continue
        if grep -q "CloudflareWARP" "$f" 2>/dev/null; then
            rm -f "$f"
        fi
    done
    rm -f /run/NetworkManager/system-connections/*CloudflareWARP* 2>/dev/null || true

    # Permanently instruct NetworkManager to treat CloudflareWARP as strictly unmanaged
    local nm_warp_dropin="/etc/NetworkManager/conf.d/99-unmanage-warp.conf"
    mkdir -p "$(dirname "$nm_warp_dropin")"
    cat << 'EOF_NM_WARP' > "$nm_warp_dropin"
[keyfile]
unmanaged-devices=interface-name:CloudflareWARP
EOF_NM_WARP

    if command -v netplan &>/dev/null; then
        netplan apply 2>/dev/null || netplan generate 2>/dev/null || true
    fi

    # 5. Restore NetworkManager connectivity check to default if busctl is available
    if command -v busctl &>/dev/null; then
        busctl set-property org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.freedesktop.NetworkManager ConnectivityCheckEnabled b true 2>/dev/null || true
    fi

    # 6. Reload NetworkManager, restart systemd-resolved, and restart warp-svc if running
    if systemctl is-active systemd-resolved &>/dev/null; then
        systemctl restart systemd-resolved 2>/dev/null || true
    fi
    nmcli general reload 2>/dev/null || systemctl reload NetworkManager 2>/dev/null || true
    if systemctl is-active warp-svc &>/dev/null; then
        systemctl restart warp-svc 2>/dev/null || true
    fi

    log_success "Network stack is completely pristine! Clean baseline restored for Cloudflare WARP and standard networking."
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
                if grep -qE "cs-[a-z]+|dnscrypt|scaleway" "$DNS_CONFIG" 2>/dev/null; then
                    echo -e "Anonymized Relays: ${GREEN}ENABLED (Traffic routed through independent relays)${NC}"
                else
                    echo -e "Anonymized Relays: ${YELLOW}CONFIGURED BUT INACTIVE (Active server uses DoH; relays require DNSCrypt protocol)${NC}"
                fi
            else
                echo "Anonymized Relays: DISABLED"
            fi
            if grep -q "cache = true" "$DNS_CONFIG" 2>/dev/null; then
                echo -e "DNS Local Cache  : ${GREEN}ENABLED (RAM Memory-Only Cache)${NC}"
            else
                echo "DNS Local Cache  : DISABLED"
            fi
            local qlog_file=""
            qlog_file=$(awk '/^\[query_log\]/{f=1;next} /^\[/{f=0} f && /^[[:space:]]*file[[:space:]]*=/{
                gsub(/[[:space:]'\''"]/, "", $0);
                split($0, a, "=");
                print a[2];
                exit
            }' "$DNS_CONFIG" 2>/dev/null || true)
            if [ -z "$qlog_file" ] || [ "$qlog_file" = "''" ] || [ "$qlog_file" = "\"\"" ]; then
                echo -e "Query Log Disk   : ${GREEN}ZERO-LOG (Forensic Privacy Preserved)${NC}"
            else
                echo -e "Query Log Disk   : ${YELLOW}LOGGING ACTIVE (${qlog_file})${NC}"
            fi
        fi
    else
        echo -e "dnscrypt-proxy   : ${YELLOW}INACTIVE / DISABLED${NC} (System using standard DHCP DNS)"
    fi

    if [ -f "$RESOLVED_DNS_DROPIN" ] && grep -qi "DNSSEC=no" "$RESOLVED_DNS_DROPIN" 2>/dev/null; then
        echo -e "DNSSEC Policy    : ${YELLOW}DISABLED in systemd-resolved (Loopback proxy compatibility)${NC}"
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
        8|dnscrypt-relay|multihop|cloudflare-odoh)
            apply_dnscrypt_config "['cs-de', 'cs-ch']" "true" "false" && \
            activate_dns_config "DNSCrypt Multi-Hop Relay (Cryptostorm via Anonymized Relays)"
            ;;
        9|quad9-relay|quad9-odoh)
            apply_dnscrypt_config "['quad9-dnscrypt-ip4-filter-pri']" "true" "false" && \
            activate_dns_config "Quad9 Malware Filter via Multi-Hop Relay (DNSCrypt)"
            ;;
        10|scaleway-relay|libredns-odoh)
            apply_dnscrypt_config "['scaleway-ams']" "true" "false" && \
            activate_dns_config "Scaleway Privacy via Multi-Hop Relay (DNSCrypt)"
            ;;
        11|quad9-tor)
            check_tor_service && \
            apply_dnscrypt_config "['quad9-doh-ip4-port443-filter-pri']" "false" "true" && \
            activate_dns_config "Quad9 via Tor SOCKS Proxy"
            ;;
        12|libredns-tor)
            check_tor_service && \
            apply_dnscrypt_config "['libredns-noads']" "false" "true" && \
            activate_dns_config "LibreDNS Adblock via Tor SOCKS Proxy"
            ;;
        13|cloudflare-tor)
            check_tor_service && \
            apply_dnscrypt_config "['cloudflare']" "false" "true" && \
            activate_dns_config "Cloudflare via Tor SOCKS Proxy"
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


    echo -e "${CYAN}-- High Availability & Redundancy (Recommended for daily use) --${NC}"
    echo -e "  0) ${BOLD}Auto-Failover Pool (Recommended)${NC}    | Quad9 + Cloudflare + AdGuard. Auto-switches during outages"
    echo ""
    echo -e "${CYAN}-- High-Speed Anycast (DoH) --${NC}"
    echo -e "  1) ${BOLD}Cloudflare Anycast${NC}                  | Ultra-low latency (1.1.1.1); no client IP logging"
    echo -e "  2) ${BOLD}Google Public DNS${NC}                   | Global capacity, near-100% infrastructure uptime"
    echo -e "  3) ${BOLD}Quad9 Swiss DNS${NC}                     | Swiss jurisdiction, strict privacy + real-time malware blocking"
    echo ""
    echo -e "${CYAN}-- Ad, Tracker & Malware Blocking (Privacy-First DoH) --${NC}"
    echo -e "  4) ${BOLD}AdGuard DNS${NC}                         | Dedicated DNS-level blocking of ads, web trackers & phishing"
    echo -e "  5) ${BOLD}Control D${NC}                           | Lightweight ad, tracker, and telemetry domain blocking"
    echo -e "  6) ${BOLD}LibreDNS Standard${NC}                   | Community non-profit (zero logs, open-source)"
    echo -e "  7) ${BOLD}LibreDNS with Adblock${NC}               | Community non-profit with built-in ad & tracking blocker"
    echo ""
    echo -e "${CYAN}-- Anonymized Multi-Hop Relays (DNSCrypt Protocol — Decouples home IP from resolver) --${NC}"
    echo -e "  8) ${BOLD}Cryptostorm Multi-Hop Relay${NC}         | Two-hop relay routing (cs-de / cs-ch via anonymized relays)"
    echo -e "  9) ${BOLD}Quad9 Malware Filter via Relay${NC}      | Quad9 DNSCrypt queries routed via anonymized relays"
    echo -e " 10) ${BOLD}Scaleway Privacy via Relay${NC}          | Scaleway DNSCrypt queries routed via anonymized relays"
    echo ""
    echo -e "${CYAN}-- Maximum Privacy (DNS Over 3-Hop Tor SOCKS Circuits) --${NC}"
    echo -e " 11) ${BOLD}Quad9 via Tor SOCKS Proxy${NC}           | Malware filtering routed over 3-hop Tor circuits"
    echo -e " 12) ${BOLD}LibreDNS Adblock via Tor${NC}            | Ad-blocking over Tor; absolute zero IP leakage to resolver"
    echo -e " 13) ${BOLD}Cloudflare via Tor${NC}                  | Anycast queries routed anonymously over Tor"
    echo ""
    echo -e "${CYAN}-- System Management --${NC}"
    echo -e " 14) ${BOLD}Revert to Default DHCP DNS${NC}          | Restores standard ISP / router DHCP DNS configuration"
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
    local opt_eth="${1:-}"

    log_info "Enabling persistent MAC address randomization in NetworkManager..."
    local eth_clause=""
    if [ "$opt_eth" = "--ethernet" ] || [ "$opt_eth" = "all" ]; then
        eth_clause=$'\n# Randomize Ethernet connections as well\nethernet.cloned-mac-address=random'
        log_info "Ethernet MAC randomization included (--ethernet requested)."
    else
        log_info "Ethernet MAC randomization skipped by default to preserve 802.1X enterprise logins & static DHCP (pass --ethernet to include)."
    fi

    cat << EOF > "$NM_MAC_CONF"
[device]
# Randomize MAC address while scanning for Wi-Fi networks
wifi.scan-rand-mac-address=yes

[connection]
# Randomize MAC address when connecting to a Wi-Fi network
wifi.cloned-mac-address=random$eth_clause
EOF
    chmod 644 "$NM_MAC_CONF"
    systemctl reload NetworkManager 2>/dev/null || systemctl restart NetworkManager 2>/dev/null || true
    log_success "Persistent MAC randomization enabled. NetworkManager will auto-assign random MACs on Wi-Fi connection and scan."
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
    echo -e "${BOLD}   Privacy & Activity Scrubbing ($(status_get_target_os))${NC}"
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

    # Enforce GNOME desktop activity privacy
    if command -v gsettings &>/dev/null; then
        run_user_gsettings set org.gnome.desktop.privacy remember-app-usage false 2>/dev/null || true
        run_user_gsettings set org.gnome.desktop.privacy remember-recent-files false 2>/dev/null || true
        run_user_gsettings set org.gnome.desktop.privacy remove-old-trash-files true 2>/dev/null || true
        run_user_gsettings set org.gnome.desktop.privacy remove-old-temp-files true 2>/dev/null || true
        run_user_gsettings set org.gnome.desktop.privacy send-software-usage-stats false 2>/dev/null || true
        run_user_gsettings set org.gnome.desktop.privacy report-technical-problems false 2>/dev/null || true
        echo "  - Enforced GNOME desktop privacy (disabled app usage tracking & recent files logging)."
    fi
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

        # Snap-based browser caches (Ubuntu LTS default for Firefox & Chromium)
        if is_safe_user_path "$h" "$h/snap" && [ -d "$h/snap" ]; then
            for sbrowser in firefox chromium; do
                local scache="$h/snap/$sbrowser/common/.cache"
                if is_safe_user_path "$h" "$scache" && [ -d "$scache" ]; then
                    find "$scache" -mindepth 1 -maxdepth 4 -type d \( -name "cache2" -o -name "startupCache" -o -name "Cache" -o -name "GPUCache" -o -name "Code Cache" \) -exec rm -rf {} + 2>/dev/null || true
                    echo "  - Cleaned Snap $sbrowser caches in $(basename "$h")"
                fi
            done
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

    # 6. Crash Reports, Telemetry & Core Dumps
    echo ">>> [6/6] Purging Crash Logs, Telemetry & Memory Core Dumps..."
    if command -v ubuntu-report &>/dev/null; then
        ubuntu-report -f send no 2>/dev/null || true
        echo "  - Disabled Ubuntu telemetry submission (ubuntu-report opt-out)."
    fi
    rm -rf /var/metrics/* 2>/dev/null || true

    local do_crash=0
    local purge_flag="${PURGE_COREDUMPS:-0}"
    if [ "$purge_flag" -eq 1 ]; then
        do_crash=1
    elif [ "${FORCE_YES:-0}" -ne 1 ] && [ -t 0 ]; then
        read -r -p "  Purge system crash reports (/var/crash) and core dumps? [y/N]: " crash_ans
        [[ "$crash_ans" =~ ^[Yy]$ ]] && do_crash=1
    fi
    if [ "$do_crash" -eq 1 ]; then
        rm -rf /var/crash/* 2>/dev/null || true
        rm -rf /var/lib/systemd/coredump/* 2>/dev/null || true
        echo "  - Removed system crash reports and core dumps."
    else
        echo "  - Preserved system crash reports and core dumps (forensic evidence retained)."
    fi
    echo "[+] Crash reports & telemetry cleaned."
    echo ""

    verify_theme_preservation
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

update_snap() {
    echo ">>> Updating Snap Packages..."
    if command -v snap &>/dev/null; then
        echo "  - Refreshing installed snap packages (snap refresh)..."
        snap refresh || echo "  [!] Notice: Snap refresh reported warnings."
        echo "[+] Snap package updates complete."
    else
        echo "  - Snap not installed; skipping update."
    fi
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
        elif [ "${EUID:-$(id -u)}" -eq 0 ]; then
            for u_home in /home/*; do
                [ -d "$u_home" ] && [ ! -L "$u_home" ] || continue
                local u_name
                u_name=$(stat -c '%U' "$u_home" 2>/dev/null || true)
                [ -n "$u_name" ] && [ "$u_name" != "root" ] || continue
                if [ -d "$u_home/.local/share/flatpak" ]; then
                    echo "  - Updating user Flatpak packages ($u_name)..."
                    local u_uid
                    u_uid=$(id -u "$u_name" 2>/dev/null || echo "")
                    if [ -n "$u_uid" ]; then
                        sudo -u "$u_name" XDG_RUNTIME_DIR="/run/user/$u_uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$u_uid/bus" flatpak update -y 2>/dev/null || sudo -u "$u_name" flatpak update -y 2>/dev/null || true
                    fi
                fi
            done
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
    local apt_log="/var/log/laptop-optimizer-apt.log"
    mkdir -p "$(dirname "$apt_log")" 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y -o Dpkg::Options::="--force-confold" >> "$apt_log" 2>&1 || true

    echo "  - Cleaning downloaded package archive caches (clean & autoclean)..."
    apt-get clean
    apt-get autoclean -y >/dev/null

    echo "  - Checking for residual package configurations (rc state)..."
    local rc_pkgs
    # Exclude bootloader (grub, shim, systemd-boot, efibootmgr) and kernel/system packages from rc purge to prevent debconf prompts and bootloader corruption
    rc_pkgs=$(dpkg -l 2>/dev/null | awk '/^rc/ && $2 !~ /^(grub|shim|linux-|systemd-boot|efibootmgr)/ {print $2}')
    if [ -n "$rc_pkgs" ]; then
        echo "  - Purging residual configurations: $rc_pkgs"
        echo "$rc_pkgs" | xargs -r env DEBIAN_FRONTEND=noninteractive dpkg --force-confdef --force-confold --purge >> "$apt_log" 2>&1 || true
    else
        echo "  - No residual configuration packages found."
    fi
    ensure_grub_default_config
    echo "[+] APT housekeeping complete (logged to $apt_log)."
    echo ""
}

clean_snap() {
    echo ">>> Snap Package Maintenance & Revision Cleaning..."
    if command -v snap &>/dev/null; then
        echo "  - Removing disabled/old snap package revisions..."
        local old_snaps
        old_snaps=$(snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' || true)
        if [ -n "$old_snaps" ]; then
            while read -r sname srev; do
                [ -n "$sname" ] && [ -n "$srev" ] || continue
                echo "    • Removing disabled revision: $sname (rev $srev)..."
                snap remove "$sname" --revision="$srev" 2>/dev/null || true
            done <<< "$old_snaps"
        else
            echo "  - No disabled snap revisions found."
        fi
        echo "  - Cleaning temporary snap cache files..."
        rm -rf /var/lib/snapd/cache/* 2>/dev/null || true
        echo "[+] Snap housekeeping complete."
    else
        echo "  - Snap not installed; skipping."
    fi
    echo ""
}

clean_flatpak() {
    echo ">>> Flatpak Runtimes & Cache Maintenance..."
    if command -v flatpak &>/dev/null; then
        echo "  - Safeguarding installed Flatpak desktop theme runtimes (GTK & KDE)..."
        local sys_themes user_themes
        sys_themes=$(flatpak list --runtime --columns=ref 2>/dev/null | grep -E 'org\.(gtk\.Gtk3theme|kde\.KStyle)' || true)
        for ref in $sys_themes; do
            flatpak pin "$ref" 2>/dev/null || true
        done
        if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            user_themes=$(sudo -u "$SUDO_USER" flatpak list --user --runtime --columns=ref 2>/dev/null | grep -E 'org\.(gtk\.Gtk3theme|kde\.KStyle)' || true)
            for ref in $user_themes; do
                sudo -u "$SUDO_USER" flatpak pin --user "$ref" 2>/dev/null || true
            done
        fi

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
        echo "  - Preserved COSMIC & Flatpak desktop theming integrity."
        echo "[+] Flatpak maintenance complete."
    else
        echo "  - Flatpak not installed; skipping."
    fi
    echo ""
}

verify_theme_preservation() {
    # Guard against accidental deletion or corruption of desktop theme & font assets
    local target_users=()
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        local user_home
        user_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
        [ -n "$user_home" ] && [ -d "$user_home" ] && [ ! -L "$user_home" ] && target_users+=("$user_home")
    fi
    for u in /home/*; do
        [ -d "$u" ] && [ ! -L "$u" ] && target_users+=("$u")
    done

    for h in "${target_users[@]}"; do
        [ -d "$h" ] || continue
        [ -L "$h" ] && continue
        is_safe_home "$h" || continue

        # Verify Flatpak theme overrides remain valid, non-empty, and free of symlink traps
        local fp_ov="$h/.local/share/flatpak/overrides/global"
        [ -L "$fp_ov" ] && continue
        is_safe_user_path "$h" "$fp_ov" || continue

        if [ -f "$fp_ov" ] && [ ! -s "$fp_ov" ]; then
            log_warn "Flatpak global override file in $(basename "$h") was empty; restoring required theming rules..."
            local tmp_ov="${fp_ov}.tmp.$$"
            cat << 'EOF_OV' > "$tmp_ov"
[Context]
filesystems=xdg-config/gtk-3.0:ro;xdg-config/gtk-4.0:ro;xdg-data/icons:ro;xdg-data/themes:ro;~/.themes:ro;~/.icons:ro;xdg-config/fontconfig:ro;
unset-environment=GTK_THEME;ICON_THEME;
EOF_OV
            local owner
            owner=$(stat -c '%u:%g' "$h" 2>/dev/null || echo "1000:1000")
            chown --no-dereference "$owner" "$tmp_ov" 2>/dev/null || true
            chmod 644 "$tmp_ov" 2>/dev/null || true
            mv -T "$tmp_ov" "$fp_ov" 2>/dev/null || rm -f "$tmp_ov"
        fi
    done
}

clean_systemd() {
    echo ">>> Systemd Journals & Residual Services..."
    if command -v journalctl &>/dev/null; then
        local j_before
        j_before=$(journalctl --disk-usage 2>/dev/null || echo "N/A")
        echo "  - Current journal footprint: $j_before"

        journalctl --rotate >/dev/null 2>&1 || true
        if [ "${VACUUM_JOURNALS:-1}" -eq 1 ]; then
            journalctl --vacuum-time=7d >/dev/null 2>&1 || true
            journalctl --vacuum-size=100M >/dev/null 2>&1 || true
        else
            echo "  - Journal vacuuming skipped (VACUUM_JOURNALS=0, forensic logs retained)."
        fi

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

    verify_theme_preservation
    echo "  - Preserved desktop theme assets, icon packs, and GTK 3/4 styling."
    echo "[+] Cache housekeeping complete."
    echo ""
}

run_optimizer() {
    check_root "${1:-optimize}"

    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}   System Optimizer & Housekeeping ($(status_get_target_os))${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    local avail_before
    avail_before=$(df -k / 2>/dev/null | awk 'END {print $4}')
    [[ "$avail_before" =~ ^[0-9]+$ ]] || avail_before=0
    echo "[*] Initial free space on root filesystem: $(format_kb "$avail_before")"
    echo ""

    clean_apt
    clean_snap
    clean_flatpak
    clean_systemd
    clean_user_cache
    print_summary "$avail_before"
}

update_and_clean() {
    check_root "${1:-update}"

    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD} Package Update & Dependency Cleanup ($(status_get_target_os))${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    local avail_before
    avail_before=$(df -k / 2>/dev/null | awk 'END {print $4}')
    [[ "$avail_before" =~ ^[0-9]+$ ]] || avail_before=0
    echo "[*] Initial free space on root filesystem: $(format_kb "$avail_before")"
    echo ""

    update_apt
    update_snap
    update_flatpak

    clean_apt
    clean_snap
    clean_flatpak

    print_summary "$avail_before"
}

run_full_update_and_optimizer() {
    check_root "${1:-all}"

    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD} Full Update & System Optimization ($(status_get_target_os))${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    local avail_before
    avail_before=$(df -k / 2>/dev/null | awk 'END {print $4}')
    [[ "$avail_before" =~ ^[0-9]+$ ]] || avail_before=0
    echo "[*] Initial free space on root filesystem: $(format_kb "$avail_before")"
    echo ""

    update_apt
    update_snap
    update_flatpak

    clean_apt
    clean_snap
    clean_flatpak
    clean_systemd
    clean_user_cache

    print_summary "$avail_before"
}

run_complete_suite() {
    check_root "full-suite"

    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}  Total Suite: Update, Housekeep & Privacy ($(status_get_target_os))${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    local avail_before
    avail_before=$(df -k / 2>/dev/null | awk 'END {print $4}')
    [[ "$avail_before" =~ ^[0-9]+$ ]] || avail_before=0

    update_apt
    update_snap
    update_flatpak

    clean_apt
    clean_snap
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
        ln -sf "$CANONICAL_BIN" /usr/local/sbin/pop-admin 2>/dev/null || true
        ln -sf "$CANONICAL_BIN" /usr/local/sbin/mint-admin 2>/dev/null || true
        ln -sf "$CANONICAL_BIN" /usr/local/sbin/laptop-optimizer 2>/dev/null || true
        exec_target="$CANONICAL_BIN"
    fi

    cat << EOF > "$OPTIMIZER_SERVICE"
[Unit]
Description=Laptop Linux Optimizer Weekly System Maintenance & Housekeeping
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
Description=Run Laptop Linux Optimizer Weekly Maintenance
Documentation=file:///etc/systemd/system/laptop-optimizer.service

[Timer]
OnCalendar=Sun *-*-* 03:00:00
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF
    chmod 644 "$OPTIMIZER_TIMER"

    systemctl daemon-reload
    systemctl stop pop-optimizer.timer mint-optimizer.timer 2>/dev/null || true
    systemctl disable pop-optimizer.timer mint-optimizer.timer 2>/dev/null || true
    systemctl enable --now laptop-optimizer.timer
    systemctl restart laptop-optimizer.timer 2>/dev/null || true

    log_success "Weekly optimization timer installed and activated!"
    echo "    - Target    : $exec_target optimize"
    echo "    - Frequency : Every Sunday at 03:00 AM (runs upon next boot if laptop was asleep/off)"
    echo "    - Logs      : journalctl -u laptop-optimizer.service"
}

uninstall_weekly_timer() {
    check_root "timer" "uninstall"

    log_info "Disabling and removing weekly optimization timer..."
    systemctl stop laptop-optimizer.timer pop-optimizer.timer mint-optimizer.timer 2>/dev/null || true
    systemctl disable laptop-optimizer.timer pop-optimizer.timer mint-optimizer.timer 2>/dev/null || true
    rm -f "$OPTIMIZER_SERVICE" "$OPTIMIZER_TIMER" "/etc/systemd/system/pop-optimizer.service" "/etc/systemd/system/pop-optimizer.timer"
    if [ -f "$CANONICAL_BIN" ]; then
        if [ ! -f "$BATTERY_SERVICE" ]; then
            rm -f "$CANONICAL_BIN" /usr/local/sbin/pop-admin /usr/local/sbin/mint-admin /usr/local/sbin/laptop-optimizer
            log_info "Removed canonical binary: $CANONICAL_BIN"
        fi
    fi
    systemctl daemon-reload

    log_success "Weekly optimization timer uninstalled."
}

show_timer_status() {
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}        Weekly Optimizer Timer Status${NC}"
    echo -e "${CYAN}========================================================${NC}"
    if [ -f "$OPTIMIZER_TIMER" ] && (systemctl is-enabled --quiet laptop-optimizer.timer 2>/dev/null || systemctl is-enabled --quiet pop-optimizer.timer 2>/dev/null); then
        echo -e "Status: ${GREEN}ACTIVE & ENABLED${NC}"
        echo ""
        systemctl list-timers laptop-optimizer.timer pop-optimizer.timer --no-pager 2>/dev/null || true
        echo ""
        echo "Last Run Log:"
        journalctl -u laptop-optimizer.service -u pop-optimizer.service -n 10 --no-pager 2>/dev/null || echo "No previous runs logged yet."
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
    mkdir -p "$STATE_DIR"
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
    echo -e "Target OS Platform     : ${GREEN}${BOLD}$(status_get_target_os)${NC}"
    echo -e "SSH Inbound Shield     : $(status_get_ssh_server)"

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
    if [[ "$swappiness" =~ ^[0-9]+$ ]] && [ "$swappiness" -ge 100 ]; then
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
    systemctl is-active --quiet avahi-daemon 2>/dev/null && avahi_st="${GREEN}ACTIVE (LocalSend & mDNS ready)${NC}" || avahi_st="${YELLOW}DISABLED${NC}"
    systemctl is-active --quiet cups-browsed 2>/dev/null && cups_st="${GREEN}ACTIVE (Network printer discovery supported)${NC}" || cups_st="${YELLOW}DISABLED${NC}"
    systemctl is-active --quiet ModemManager 2>/dev/null && modem_st="${YELLOW}ACTIVE (Cellular scanner)${NC}" || modem_st="${GREEN}DISABLED${NC}"
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

    # 9. Font Anti-Blur & High-DPI Scaling (Flatpak/COSMIC Wayland/X11)
    local cur_blur
    cur_blur=$(status_get_font_antiblur)
    if [[ "$cur_blur" =~ (ACTIVE|COSMIC) ]]; then
        echo -e "Font Anti-Blur (LCD)   : ${GREEN}${BOLD}${cur_blur}${NC}"
    else
        echo -e "Font Anti-Blur (LCD)   : ${YELLOW}${BOLD}${cur_blur}${NC} (Run: sudo $0 tune antiblur enable)"
    fi

    # 10. AMD P-State EPP Governor
    local cur_epp
    cur_epp=$(status_get_epp)
    echo -e "AMD P-State EPP        : ${GREEN}${BOLD}${cur_epp}${NC} (Run: sudo $0 epp [profile])"

    # 11. Audio Powersave DAC Popping Fix
    local cur_audio
    cur_audio=$(status_get_audio_powersave)
    if [[ "$cur_audio" =~ FIXED ]]; then
        echo -e "Audio Pop Shield       : ${GREEN}${BOLD}${cur_audio}${NC}"
    else
        echo -e "Audio Pop Shield       : ${YELLOW}${BOLD}${cur_audio}${NC} (Run: sudo $0 audio fix)"
    fi

    # 12. Apport Crash Error Popups
    local cur_apport
    cur_apport=$(status_get_apport)
    if [[ "$cur_apport" =~ DISABLED ]]; then
        echo -e "Apport Crash Popups    : ${GREEN}${BOLD}${cur_apport}${NC}"
    else
        echo -e "Apport Crash Popups    : ${YELLOW}${BOLD}${cur_apport}${NC} (Run: sudo $0 apport disable)"
    fi

    # 13. SSD / NVMe Periodic TRIM Maintenance
    local cur_trim
    cur_trim=$(status_get_fstrim)
    if [[ "$cur_trim" =~ ACTIVE ]]; then
        echo -e "SSD Periodic TRIM      : ${GREEN}${BOLD}${cur_trim}${NC}"
    else
        echo -e "SSD Periodic TRIM      : ${YELLOW}${BOLD}${cur_trim}${NC} (Run: sudo $0 trim enable)"
    fi

    # 14. Hardened Laptop UFW Firewall
    local cur_ufw
    cur_ufw=$(status_get_ufw)
    if [[ "$cur_ufw" =~ ACTIVE ]]; then
        echo -e "Laptop UFW Firewall    : ${GREEN}${BOLD}${cur_ufw}${NC}"
    else
        echo -e "Laptop UFW Firewall    : ${YELLOW}${BOLD}${cur_ufw}${NC} (Run: sudo $0 firewall enable)"
    fi

    # 15. Browser Hardware Video Acceleration (VA-API)
    local cur_bvaapi
    cur_bvaapi=$(status_get_browser_vaapi)
    if [[ "$cur_bvaapi" =~ CONFIGURED ]]; then
        echo -e "Browser Video VA-API   : ${GREEN}${BOLD}${cur_bvaapi}${NC}"
    else
        echo -e "Browser Video VA-API   : ${YELLOW}${BOLD}${cur_bvaapi}${NC} (Run: $0 browser-vaapi enable)"
    fi

    # 17. Root User Access Hardening
    local cur_root
    cur_root=$(status_get_root_lock)
    if [[ "$cur_root" =~ LOCKED ]]; then
        echo -e "Root User Hardening    : ${GREEN}${BOLD}${cur_root}${NC}"
    else
        echo -e "Root User Hardening    : ${YELLOW}${BOLD}${cur_root}${NC} (Run: sudo $0 root lock)"
    fi

    # 16. Bluetooth High-Fidelity Audio Codecs
    local cur_bt
    cur_bt=$(status_get_bluetooth_codecs)
    if [[ "$cur_bt" =~ INSTALLED ]]; then
        echo -e "Bluetooth HD Codecs    : ${GREEN}${BOLD}${cur_bt}${NC}"
    else
        echo -e "Bluetooth HD Codecs    : ${YELLOW}${BOLD}${cur_bt}${NC} (Run: sudo $0 bluetooth install)"
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
    local cur_cc
    cur_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "Unknown")
    if [ "$cur_cc" = "bbr" ]; then
        log_success "TCP BBR active (optimal low-latency congestion control, qdisc: fq)."
        return 0
    else
        log_warn "Notice: TCP BBR was requested but active congestion control is '$cur_cc'."
        return 1
    fi
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
    local cur_swap cur_vfs
    cur_swap=$(sysctl -n vm.swappiness 2>/dev/null || echo "Unknown")
    cur_vfs=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null || echo "Unknown")
    if [ "$cur_swap" = "100" ] && [ "$cur_vfs" = "50" ]; then
        log_success "Memory tuning active: vm.swappiness=100, vm.vfs_cache_pressure=50 (optimized for ZRAM/SSD)."
        return 0
    else
        log_warn "Notice: Memory tuning applied with deviations: swappiness=$cur_swap, vfs_cache_pressure=$cur_vfs."
        return 1
    fi
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
# ZRAM configuration (pop-admin - 50% RAM for 16GB laptop)
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
    ensure_hostname_resolution
    printf '[connection]\nipv4.dhcp-send-hostname=false\nipv6.dhcp-send-hostname=false\n' > "$DHCP_PRIVACY_CONF" 2>/dev/null || true
    mkdir -p "$STATE_DIR" && touch "$STATE_DIR/dhcp-privacy-enabled"

    if command -v nmcli &>/dev/null; then
        # Strictly target physical Wi-Fi and Ethernet connections; never touch tun, tap, loopback, or VPN connections (e.g. CloudflareWARP)
        while IFS= read -r uuid; do
            [ -n "$uuid" ] || continue
            nmcli con modify "$uuid" ipv4.dhcp-send-hostname no ipv6.dhcp-send-hostname no 2>/dev/null || true
        done < <(nmcli -t -f UUID,TYPE connection show 2>/dev/null | grep -E ':(802-11-wireless|802-3-ethernet)' | cut -d: -f1 || true)
        nmcli general reload 2>/dev/null || true
    fi
    log_success "DHCP hostname leak protection active (global NM drop-in created & connections updated)."
}

disable_dhcp_privacy() {
    check_root "tune" "dhcp" "disable"
    log_info "Disabling DHCP hostname leak protection..."
    rm -f "$DHCP_PRIVACY_CONF" "$STATE_DIR/dhcp-privacy-enabled" /var/lib/pop-admin/dhcp-privacy-enabled /var/lib/mint-admin/dhcp-privacy-enabled

    if command -v nmcli &>/dev/null; then
        # Strictly target physical Wi-Fi and Ethernet connections; never touch tun, tap, loopback, or VPN connections (e.g. CloudflareWARP)
        while IFS= read -r uuid; do
            [ -n "$uuid" ] || continue
            nmcli con modify "$uuid" ipv4.dhcp-send-hostname yes ipv6.dhcp-send-hostname yes 2>/dev/null || true
        done < <(nmcli -t -f UUID,TYPE connection show 2>/dev/null | grep -E ':(802-11-wireless|802-3-ethernet)' | cut -d: -f1 || true)
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
# Kernel Privacy & Security Hardening (pop-admin)
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
        log_warn "Warning: Disabling cups-browsed will stop automatic discovery of Wi-Fi / network printers!"
        log_info "Stopping & disabling cups-browsed..."
        systemctl stop cups-browsed 2>/dev/null || true
        systemctl disable cups-browsed 2>/dev/null || true
        log_success "CUPS network browsing stopped & disabled."
    else
        log_info "Enabling cups-browsed for network printer discovery..."
        systemctl unmask cups-browsed 2>/dev/null || true
        systemctl enable --now cups-browsed 2>/dev/null || true
        log_success "CUPS network browsing enabled & started (network printer discovery active)."
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

# 8. Subpixel Font Anti-Blur & High-DPI Scaling
enable_font_antiblur() {
    local target_user="${SUDO_USER:-$USER}"
    local uhome
    uhome=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)
    [ -z "$uhome" ] && uhome="$HOME"
    local owner_gid
    owner_gid=$(id -g "$target_user" 2>/dev/null || echo "1000")
    local owner_uid
    owner_uid=$(id -u "$target_user" 2>/dev/null || echo "1000")

    local is_wayland=0
    if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        is_wayland=1
    fi

    log_info "Configuring font clarity & High-DPI anti-blur for $target_user (${is_wayland:+"Wayland Native"}${is_wayland:-"X11 Subpixel"})..."

    # If cinna-theme is available on X11, invoke it
    if [ "$is_wayland" -eq 0 ] && [ -x "$uhome/.local/bin/cinna-theme" ]; then
        if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            sudo -u "$SUDO_USER" "$uhome/.local/bin/cinna-theme" --fix-blur 2>/dev/null || true
        else
            "$uhome/.local/bin/cinna-theme" --fix-blur 2>/dev/null || true
        fi
    fi

    # Ensure fontconfig file is configured safely without following symlink traps
    local fc_dir="$uhome/.config/fontconfig"
    local fc_file="$fc_dir/fonts.conf"
    if [ -L "$fc_dir" ] || [ -L "$fc_file" ] || ! is_safe_user_path "$uhome" "$fc_file"; then
        log_warn "Refusing to modify symlinked fontconfig path for $(basename "$uhome")."
    else
        mkdir -p "$fc_dir"
        local tmp_fc="${fc_file}.tmp.$$"
        if [ "$is_wayland" -eq 1 ]; then
            cat << 'EOF_FC_W' > "$tmp_fc"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- Wayland Native Font Clarity: slight hinting & lcddefault filter; avoid subpixel fringing on GTK4/Wayland -->
  <match target="font">
    <edit mode="assign" name="antialias"><bool>true</bool></edit>
    <edit mode="assign" name="hinting"><bool>true</bool></edit>
    <edit mode="assign" name="hintstyle"><const>hintslight</const></edit>
    <edit mode="assign" name="rgba"><const>none</const></edit>
    <edit mode="assign" name="lcdfilter"><const>lcddefault</const></edit>
  </match>
</fontconfig>
EOF_FC_W
        else
            cat << 'EOF_FC' > "$tmp_fc"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- Enforce Subpixel RGB Antialiasing and Full Hinting for razor-sharp text on X11 -->
  <match target="font">
    <edit mode="assign" name="antialias"><bool>true</bool></edit>
    <edit mode="assign" name="hinting"><bool>true</bool></edit>
    <edit mode="assign" name="hintstyle"><const>hintfull</const></edit>
    <edit mode="assign" name="rgba"><const>rgb</const></edit>
    <edit mode="assign" name="lcdfilter"><const>lcddefault</const></edit>
  </match>
</fontconfig>
EOF_FC
        fi
        chown --no-dereference "$owner_uid:$owner_gid" "$tmp_fc" 2>/dev/null || true
        chmod 644 "$tmp_fc" 2>/dev/null || true
        mv -T "$tmp_fc" "$fc_file" 2>/dev/null || rm -f "$tmp_fc"
        chown --no-dereference "$owner_uid:$owner_gid" "$fc_dir" 2>/dev/null || true
    fi

    # GTK 3 & GTK 4 settings.ini
    for gtk_ver in "gtk-3.0" "gtk-4.0"; do
        local gdir="$uhome/.config/$gtk_ver"
        local gini="$gdir/settings.ini"
        if [ -L "$gdir" ] || [ -L "$gini" ] || ! is_safe_user_path "$uhome" "$gini"; then
            log_warn "Refusing to modify symlinked GTK settings path for $(basename "$uhome")."
            continue
        fi
        mkdir -p "$gdir"
        local tmp_gini="${gini}.tmp.$$"
        if [ "$is_wayland" -eq 1 ]; then
            # On Wayland, clean out legacy Xft and avoid hardcoded gtk-xft-dpi=122880 to prevent double-scaling
            if [ -f "$gini" ]; then
                cp -p "$gini" "$tmp_gini" 2>/dev/null || true
                sed -i '/^gtk-xft-/d' "$tmp_gini" 2>/dev/null || true
                cat << 'EOF_GTK_W' >> "$tmp_gini"
gtk-xft-antialias = 1
gtk-xft-hinting = 1
gtk-xft-hintstyle = hintslight
gtk-xft-rgba = none
EOF_GTK_W
            else
                cat << 'EOF_GTK_W' > "$tmp_gini"
[Settings]
gtk-font-name = Ubuntu 10
gtk-xft-antialias = 1
gtk-xft-hinting = 1
gtk-xft-hintstyle = hintslight
gtk-xft-rgba = none
EOF_GTK_W
            fi
        else
            if [ -f "$gini" ]; then
                cp -p "$gini" "$tmp_gini" 2>/dev/null || true
                sed -i '/^gtk-xft-/d' "$tmp_gini" 2>/dev/null || true
                cat << 'EOF_GTK' >> "$tmp_gini"
gtk-xft-antialias = 1
gtk-xft-hinting = 1
gtk-xft-hintstyle = hintfull
gtk-xft-rgba = rgb
gtk-xft-dpi = 122880
EOF_GTK
            else
                cat << 'EOF_GTK' > "$tmp_gini"
[Settings]
gtk-font-name = Ubuntu 10
gtk-xft-antialias = 1
gtk-xft-hinting = 1
gtk-xft-hintstyle = hintfull
gtk-xft-rgba = rgb
gtk-xft-dpi = 122880
EOF_GTK
            fi
        fi
        chown --no-dereference "$owner_uid:$owner_gid" "$tmp_gini" 2>/dev/null || true
        chmod 644 "$tmp_gini" 2>/dev/null || true
        mv -T "$tmp_gini" "$gini" 2>/dev/null || rm -f "$tmp_gini"
        chown --no-dereference "$owner_uid:$owner_gid" "$gdir" 2>/dev/null || true
    done

    # Flatpak user overrides
    if command -v flatpak &>/dev/null; then
        local fp_cmd
        if [ "$is_wayland" -eq 1 ]; then
            # On Wayland, avoid GDK_DPI_SCALE=1.25 which causes double-scaling; enforce Ozone native Wayland
            fp_cmd=(flatpak override --user --filesystem=xdg-config/fontconfig:ro --filesystem=xdg-data/fonts:ro --filesystem=~/.fonts:ro --env=ELECTRON_OZONE_PLATFORM_HINT=auto --env=MOZ_ENABLE_WAYLAND=1 --env=QT_AUTO_SCREEN_SCALE_FACTOR=1 --env=QT_ENABLE_HIGHDPI_SCALING=1 --unset-env=GDK_DPI_SCALE)
        else
            fp_cmd=(flatpak override --user --filesystem=xdg-config/fontconfig:ro --filesystem=xdg-data/fonts:ro --filesystem=~/.fonts:ro --env=ELECTRON_OZONE_PLATFORM_HINT=auto --env=QT_AUTO_SCREEN_SCALE_FACTOR=1 --env=QT_ENABLE_HIGHDPI_SCALING=1 --env=GDK_DPI_SCALE=1.25)
        fi
        if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            sudo -u "$SUDO_USER" "${fp_cmd[@]}" 2>/dev/null || true
        else
            "${fp_cmd[@]}" 2>/dev/null || true
        fi
    fi

    # Native Wayland flags for Electron / Chromium desktop apps (prevents XWayland blurry bitmap upscaling)
    if [ "$is_wayland" -eq 1 ]; then
        for cfg in "$uhome/.config/electron-flags.conf" "$uhome/.config/chrome-flags.conf" "$uhome/.config/code-flags.conf"; do
            mkdir -p "$(dirname "$cfg")"
            if [ ! -f "$cfg" ] || ! grep -q "ozone-platform-hint" "$cfg" 2>/dev/null; then
                echo "--ozone-platform-hint=auto" >> "$cfg" 2>/dev/null || true
                chown --no-dereference "$owner_uid:$owner_gid" "$cfg" 2>/dev/null || true
            fi
        done
    fi

    # Desktop interface font rendering settings
    if [ "$is_wayland" -eq 1 ]; then
        # Wayland: grayscale antialiasing & slight hinting (matches modern GTK4/Libadwaita text rendering)
        run_user_gsettings set org.gnome.desktop.interface font-antialiasing 'grayscale'
        run_user_gsettings set org.gnome.desktop.interface font-hinting 'slight'
    else
        # X11 / Cinnamon: subpixel RGB antialiasing & full hinting
        run_user_gsettings set org.cinnamon.desktop.interface upscale-fractional-scaling false
        run_user_gsettings set org.gnome.desktop.interface font-antialiasing 'rgba'
        run_user_gsettings set org.gnome.desktop.interface font-hinting 'full'
    fi

    log_success "Font clarity & High-DPI anti-blur rules enabled (${is_wayland:+"Wayland Native Ozone"}${is_wayland:-"X11 Subpixel RGB"})!"
}

disable_font_antiblur() {
    local target_user="${SUDO_USER:-$USER}"
    local uhome
    uhome=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)
    [ -z "$uhome" ] && uhome="$HOME"

    log_info "Disabling subpixel font anti-blur for $target_user..."
    rm -f "$uhome/.config/fontconfig/fonts.conf"

    for gtk_ver in "gtk-3.0" "gtk-4.0"; do
        local gini="$uhome/.config/$gtk_ver/settings.ini"
        [ -f "$gini" ] && sed -i '/^gtk-xft-/d' "$gini" 2>/dev/null || true
    done

    run_user_gsettings set org.gnome.desktop.interface font-antialiasing 'grayscale'
    run_user_gsettings set org.gnome.desktop.interface font-hinting 'slight'

    if command -v flatpak &>/dev/null; then
        local fp_cmd=(flatpak override --user --nofilesystem=xdg-config/fontconfig:ro --unset-env=ELECTRON_OZONE_PLATFORM_HINT --unset-env=MOZ_ENABLE_WAYLAND --unset-env=GDK_DPI_SCALE)
        if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            sudo -u "$SUDO_USER" "${fp_cmd[@]}" 2>/dev/null || true
        else
            "${fp_cmd[@]}" 2>/dev/null || true
        fi
    fi

    for cfg in "$uhome/.config/electron-flags.conf" "$uhome/.config/chrome-flags.conf" "$uhome/.config/code-flags.conf"; do
        if [ -f "$cfg" ]; then
            sed -i '/--ozone-platform-hint=auto/d' "$cfg" 2>/dev/null || true
            [ ! -s "$cfg" ] && rm -f "$cfg"
        fi
    done

    log_success "Font anti-blur rules disabled (reverted to system default)."
}

toggle_font_antiblur() {
    local cur
    cur=$(status_get_font_antiblur)
    if [[ "$cur" =~ ACTIVE ]]; then
        disable_font_antiblur
    else
        enable_font_antiblur
    fi
}

# 9. AMD P-State & EPP Energy Preference
status_get_epp() {
    if [ -f "/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference" ]; then
        cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo "unknown"
    elif [ -f "/sys/devices/system/cpu/cpu0/power/energy_performance_preference" ]; then
        cat /sys/devices/system/cpu/cpu0/power/energy_performance_preference 2>/dev/null || echo "unknown"
    else
        echo "UNSUPPORTED"
    fi
}

set_epp_preference() {
    local target="${1:-balance_power}"
    check_root "tune" "epp" "$target"
    local found=0
    for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference /sys/devices/system/cpu/cpu*/power/energy_performance_preference; do
        if [ -f "$f" ]; then
            echo "$target" > "$f" 2>/dev/null || true
            found=1
        fi
    done
    if [ "$found" -eq 0 ]; then
        log_warn "Energy Performance Preference (EPP) not supported on this CPU / driver."
        return 0
    fi
    mkdir -p /etc/tmpfiles.d
    cat << 'EOF' > /etc/tmpfiles.d/laptop-epp.conf
w- /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference - - - - TARGET_VAL
w- /sys/devices/system/cpu/cpu*/power/energy_performance_preference - - - - TARGET_VAL
EOF
    sed -i "s/TARGET_VAL/$target/g" /etc/tmpfiles.d/laptop-epp.conf
    log_success "AMD P-State EPP preference set to: $target (persisted via /etc/tmpfiles.d/laptop-epp.conf)"
}

cycle_epp_preference() {
    local cur
    cur=$(status_get_epp)
    case "$cur" in
        power) set_epp_preference "balance_power" ;;
        balance_power) set_epp_preference "balance_performance" ;;
        balance_performance) set_epp_preference "performance" ;;
        performance|*) set_epp_preference "power" ;;
    esac
}

show_epp_status() {
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}         AMD P-State & EPP Energy Tuning Status${NC}"
    echo -e "${CYAN}========================================================${NC}"
    local driver="unknown"
    [ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_driver" ] && driver=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null)
    local cur_epp
    cur_epp=$(status_get_epp)
    local avail="default performance balance_performance balance_power power"
    if [ -f "/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_available_preferences" ]; then
        avail=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_available_preferences 2>/dev/null)
    elif [ -f "/sys/devices/system/cpu/cpu0/power/energy_performance_available_preferences" ]; then
        avail=$(cat /sys/devices/system/cpu/cpu0/power/energy_performance_available_preferences 2>/dev/null)
    fi
    echo "  • Scaling Driver       : $driver"
    echo -e "  • Active EPP Preference : ${GREEN}${BOLD}${cur_epp}${NC}"
    echo "  • Available Preferences: $avail"
    if [ -f "/etc/tmpfiles.d/laptop-epp.conf" ]; then
        echo -e "  • Persistent Hook      : ${GREEN}INSTALLED (/etc/tmpfiles.d/laptop-epp.conf)${NC}"
    else
        echo "  • Persistent Hook      : NOT INSTALLED"
    fi
    echo -e "${CYAN}========================================================${NC}"
}

# 10. Audio Powersave DAC Popping & Crackle Fix
AUDIO_POWERSAVE_CONF="/etc/modprobe.d/laptop-audio-powersave.conf"

status_get_audio_powersave() {
    local ps=1
    if [ -f "/sys/module/snd_hda_intel/parameters/power_save" ]; then
        ps=$(cat /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null || echo 1)
    fi
    if [ "$ps" -eq 0 ] || [ -f "$AUDIO_POWERSAVE_CONF" ]; then
        echo "FIXED (Crackle Shielded)"
    else
        echo "POWERSAVE (Click/Pop risk)"
    fi
}

enable_audio_powersave_fix() {
    check_root "tune" "audio" "fix"
    log_info "Configuring audio controller to eliminate idle popping and crackle..."
    cat << 'EOF' > "$AUDIO_POWERSAVE_CONF"
# Laptop Linux Optimizer: Disable aggressive audio DAC power-save to prevent popping/clicks
options snd_hda_intel power_save=0 power_save_controller=N
options snd_acp3x_rn power_save=0 2>/dev/null || true
EOF
    chmod 644 "$AUDIO_POWERSAVE_CONF"
    if [ -f "/sys/module/snd_hda_intel/parameters/power_save" ]; then
        echo 0 > /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null || true
    fi
    if [ -f "/sys/module/snd_hda_intel/parameters/power_save_controller" ]; then
        echo N > /sys/module/snd_hda_intel/parameters/power_save_controller 2>/dev/null || true
    fi
    log_success "Audio powersave click/popping fix enabled and persisted."
}

revert_audio_powersave_fix() {
    check_root "tune" "audio" "revert"
    log_info "Reverting audio powersave configuration to system default..."
    rm -f "$AUDIO_POWERSAVE_CONF"
    if [ -f "/sys/module/snd_hda_intel/parameters/power_save" ]; then
        echo 1 > /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null || true
    fi
    log_success "Audio powersave restored to default."
}

toggle_audio_powersave_fix() {
    if [[ "$(status_get_audio_powersave)" =~ FIXED ]]; then
        revert_audio_powersave_fix
    else
        enable_audio_powersave_fix
    fi
}

# 11. Ubuntu Apport Crash Error Popups Shield
status_get_apport() {
    local enabled=0
    [ -f "/etc/default/apport" ] && grep -qi "enabled=1" /etc/default/apport && enabled=1
    if systemctl is-active --quiet apport 2>/dev/null && [ "$enabled" -eq 1 ]; then
        echo "ACTIVE (Popups Enabled)"
    else
        echo "DISABLED (Silenced)"
    fi
}

disable_apport() {
    check_root "tune" "apport" "disable"
    log_info "Silencing Apport crash error dialogs and popups..."
    if [ -f "/etc/default/apport" ]; then
        sed -i 's/enabled=1/enabled=0/g' /etc/default/apport
    else
        echo "enabled=0" > /etc/default/apport
    fi
    systemctl stop apport 2>/dev/null || true
    systemctl mask apport 2>/dev/null || true
    rm -rf /var/crash/* 2>/dev/null || true
    log_success "Apport crash popups disabled and /var/crash cleared."
}

enable_apport() {
    check_root "tune" "apport" "enable"
    log_info "Re-enabling Apport crash reporting..."
    if [ -f "/etc/default/apport" ]; then
        sed -i 's/enabled=0/enabled=1/g' /etc/default/apport
    else
        echo "enabled=1" > /etc/default/apport
    fi
    systemctl unmask apport 2>/dev/null || true
    systemctl start apport 2>/dev/null || true
    log_success "Apport crash reporting restored."
}

toggle_apport() {
    if [[ "$(status_get_apport)" =~ ACTIVE ]]; then
        disable_apport
    else
        enable_apport
    fi
}

clean_crash_reports() {
    check_root "tune" "apport" "clean"
    log_info "Purging system crash reports (/var/crash) and core dumps..."
    rm -rf /var/crash/* /var/lib/systemd/coredump/* 2>/dev/null || true
    log_success "System crash dumps purged."
}

# 12. SSD / NVMe Periodic TRIM Maintenance
status_get_fstrim() {
    if systemctl is-enabled --quiet fstrim.timer 2>/dev/null; then
        if systemctl is-active --quiet fstrim.timer 2>/dev/null; then
            echo "ACTIVE (Weekly TRIM)"
        else
            echo "ENABLED (Inactive)"
        fi
    else
        echo "DISABLED"
    fi
}

enable_fstrim_timer() {
    check_root "tune" "trim" "enable"
    log_info "Enabling and starting systemd fstrim.timer..."
    systemctl unmask fstrim.timer 2>/dev/null || true
    systemctl enable --now fstrim.timer 2>/dev/null || true
    log_success "fstrim.timer enabled and running (weekly SSD TRIM active)."
}

disable_fstrim_timer() {
    check_root "tune" "trim" "disable"
    log_info "Disabling fstrim.timer..."
    systemctl disable --now fstrim.timer 2>/dev/null || true
    log_success "fstrim.timer disabled."
}

toggle_fstrim_timer() {
    if [[ "$(status_get_fstrim)" =~ ACTIVE|ENABLED ]]; then
        disable_fstrim_timer
    else
        enable_fstrim_timer
    fi
}

run_fstrim_now() {
    check_root "tune" "trim" "run"
    log_info "Executing manual SSD/NVMe TRIM across all mounted filesystems (fstrim -av)..."
    fstrim -av
    log_success "Manual TRIM completed successfully."
}

show_storage_trim_status() {
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}       SSD / NVMe Health & TRIM Maintenance Status${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo "  • fstrim.timer State   : $(status_get_fstrim)"
    if command -v systemctl &>/dev/null; then
        systemctl list-timers fstrim.timer --no-pager 2>/dev/null || true
    fi
    echo ""
    echo "  • Block Device Schedulers:"
    for d in /sys/block/nvme* /sys/block/sd*; do
        [ -d "$d" ] || continue
        local bname
        bname=$(basename "$d")
        local sched="unknown"
        [ -f "$d/queue/scheduler" ] && sched=$(cat "$d/queue/scheduler" 2>/dev/null)
        echo "    - $bname: $sched"
    done
    echo -e "${CYAN}========================================================${NC}"
}

# 13. Hardened Laptop UFW Firewall Shield
status_get_ufw() {
    if command -v ufw &>/dev/null; then
        local st
        st=$(ufw status 2>/dev/null | grep -i "Status:" | awk '{print $2}' || echo "unknown")
        if [ "$st" = "active" ]; then
            echo "ACTIVE (Shielded)"
        else
            echo "INACTIVE (Unprotected)"
        fi
    else
        echo "NOT INSTALLED"
    fi
}

enable_laptop_firewall() {
    check_root "tune" "firewall" "enable"
    if ! command -v ufw &>/dev/null; then
        log_info "Installing ufw package..."
        apt-get update && apt-get install -y ufw
    fi
    log_info "Configuring hardened Laptop Firewall profile..."
    ufw --force reset >/dev/null 2>&1 || true
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    ufw allow 53317/tcp comment "LocalSend TCP" >/dev/null 2>&1 || true
    ufw allow 53317/udp comment "LocalSend UDP" >/dev/null 2>&1 || true
    ufw allow 631/udp comment "CUPS printer discovery" >/dev/null 2>&1 || true
    ufw --force enable >/dev/null 2>&1
    log_success "Laptop firewall active: Incoming blocked, LocalSend (53317) & CUPS (631) allowed."
}

disable_laptop_firewall() {
    check_root "tune" "firewall" "disable"
    log_info "Disabling UFW firewall..."
    ufw disable >/dev/null 2>&1 || true
    log_success "Firewall disabled."
}

toggle_laptop_firewall() {
    if [[ "$(status_get_ufw)" =~ ACTIVE ]]; then
        disable_laptop_firewall
    else
        enable_laptop_firewall
    fi
}

show_ufw_status() {
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}         Laptop UFW Firewall Shield Status${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo "  • Firewall State: $(status_get_ufw)"
    if command -v ufw &>/dev/null; then
        echo ""
        ufw status verbose 2>/dev/null || echo "Run as root to view detailed rules."
    fi
    echo -e "${CYAN}========================================================${NC}"
}

# 14. Browser Hardware Video Acceleration (VA-API)
status_get_browser_vaapi() {
    local target_user="${SUDO_USER:-$USER}"
    local uhome
    uhome=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)
    [ -z "$uhome" ] && uhome="$HOME"
    
    local ff_ok=0 cr_ok=0
    for ujs in "$uhome"/.mozilla/firefox/*default*/user.js "$uhome"/snap/firefox/common/.mozilla/firefox/*default*/user.js; do
        if [ -f "$ujs" ] && grep -q "media.ffmpeg.vaapi.enabled" "$ujs" 2>/dev/null; then
            ff_ok=1
            break
        fi
    done
    for cflags in "$uhome/.config/brave-flags.conf" "$uhome/.config/chromium-flags.conf" "$uhome/.config/chrome-flags.conf"; do
        if [ -f "$cflags" ] && grep -q "VaapiVideoDecodeLinuxGL" "$cflags" 2>/dev/null; then
            cr_ok=1
            break
        fi
    done

    if [ "$ff_ok" -eq 1 ] || [ "$cr_ok" -eq 1 ]; then
        echo "CONFIGURED (VA-API Active)"
    else
        echo "DEFAULT (CPU Decode)"
    fi
}

enable_browser_vaapi() {
    local target_user="${SUDO_USER:-$USER}"
    local uhome
    uhome=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)
    [ -z "$uhome" ] && uhome="$HOME"

    log_info "Configuring Hardware Video Acceleration (VA-API) for $target_user browsers..."

    for pdir in "$uhome"/.mozilla/firefox/*default* "$uhome"/snap/firefox/common/.mozilla/firefox/*default*; do
        [ -d "$pdir" ] || continue
        local ujs="$pdir/user.js"
        log_info "  - Injecting VA-API preferences into: $ujs"
        cat << 'EOF' >> "$ujs"

// Laptop Linux Optimizer: Hardware Video Acceleration (VA-API)
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("gfx.webrender.all", true);
user_pref("widget.dmabuf.force-enabled", true);
user_pref("media.rdd-vpx.enabled", true);
user_pref("media.rdd-ffmpeg.enabled", true);
EOF
        awk '!seen[$0]++' "$ujs" > "$ujs.tmp" && mv "$ujs.tmp" "$ujs"
        chown "$target_user:$target_user" "$ujs" 2>/dev/null || true
    done

    mkdir -p "$uhome/.config"
    for cfile in "$uhome/.config/brave-flags.conf" "$uhome/.config/chromium-flags.conf" "$uhome/.config/chrome-flags.conf"; do
        cat << 'EOF' > "$cfile"
--enable-features=VaapiVideoDecodeLinuxGL,VaapiIgnoreDriverChecks
--enable-gpu-rasterization
--enable-zero-copy
EOF
        chown "$target_user:$target_user" "$cfile" 2>/dev/null || true
    done

    log_success "Browser Hardware Video Acceleration (VA-API) enabled for Firefox, Brave, and Chromium!"
}

revert_browser_vaapi() {
    local target_user="${SUDO_USER:-$USER}"
    local uhome
    uhome=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)
    [ -z "$uhome" ] && uhome="$HOME"

    log_info "Reverting browser hardware acceleration flags for $target_user..."
    for ujs in "$uhome"/.mozilla/firefox/*default*/user.js "$uhome"/snap/firefox/common/.mozilla/firefox/*default*/user.js; do
        if [ -f "$ujs" ]; then
            sed -i '/media.ffmpeg.vaapi.enabled/d' "$ujs" 2>/dev/null || true
            sed -i '/widget.dmabuf.force-enabled/d' "$ujs" 2>/dev/null || true
            sed -i '/media.rdd-vpx.enabled/d' "$ujs" 2>/dev/null || true
            sed -i '/media.rdd-ffmpeg.enabled/d' "$ujs" 2>/dev/null || true
        fi
    done
    for cfile in "$uhome/.config/brave-flags.conf" "$uhome/.config/chromium-flags.conf" "$uhome/.config/chrome-flags.conf"; do
        rm -f "$cfile"
    done
    log_success "Browser hardware acceleration flags reverted to defaults."
}

toggle_browser_vaapi() {
    if [[ "$(status_get_browser_vaapi)" =~ CONFIGURED ]]; then
        revert_browser_vaapi
    else
        enable_browser_vaapi
    fi
}

show_browser_vaapi_status() {
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}     Browser Hardware Video Acceleration Status${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo "  • VA-API Status: $(status_get_browser_vaapi)"
    echo "  • Supported Browsers: Firefox (Native & Snap), Brave, Chromium, Chrome"
    echo -e "${CYAN}========================================================${NC}"
}

# 15. PipeWire Bluetooth High-Fidelity Audio Codecs
status_get_bluetooth_codecs() {
    if dpkg -s libspa-0.2-bluetooth &>/dev/null; then
        echo "INSTALLED (LDAC / AAC / aptX ready)"
    else
        echo "NOT INSTALLED (Standard SBC only)"
    fi
}

install_bluetooth_codecs() {
    check_root "media" "bluetooth"
    log_info "Installing PipeWire Bluetooth high-fidelity audio codecs (libspa-0.2-bluetooth)..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y libspa-0.2-bluetooth
    log_success "High-fidelity Bluetooth codecs (LDAC, AAC, aptX) installed successfully."
}

show_bluetooth_status() {
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}       PipeWire Bluetooth Audio Codecs Status${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo "  • Codec Package: $(status_get_bluetooth_codecs)"
    echo "  • Supported Codecs: LDAC, AAC, aptX, aptX-HD, SBC-XQ"
    echo -e "${CYAN}========================================================${NC}"
}

# ==============================================================================
# GNOME Uniform Theming & Popular Themes Gallery
# Unified styling for deb (GTK 3), Libadwaita (GTK 4), and Flatpak apps
# ==============================================================================

# Theme metadata registry
# Format: id|title|folder|color_scheme|accent_desc|upstream_url
GALLERY_THEMES_MANIFEST=(
    "adw-gtk3-dark|Adw-gtk3 Dark (1:1 Libadwaita Match)|adw-gtk3-dark|prefer-dark|Modern dark matching GNOME 45/46 Libadwaita|https://github.com/lassekongo83/adw-gtk3/releases/latest/download/adw-gtk3v5.3.tar.tar"
    "adw-gtk3|Adw-gtk3 Light (1:1 Libadwaita Match)|adw-gtk3|default|Clean light matching GNOME 45/46 Libadwaita|https://github.com/lassekongo83/adw-gtk3/releases/latest/download/adw-gtk3v5.3.tar.tar"
    "catppuccin-mocha|Catppuccin Mocha|Catppuccin-Mocha-Standard-Lavender-Dark|prefer-dark|Soothing pastel dark aesthetic with lavender accent|https://github.com/catppuccin/gtk/releases/download/v1.0.3/Catppuccin-Mocha-Standard-Lavender-Dark.zip"
    "catppuccin-latte|Catppuccin Latte|Catppuccin-Latte-Standard-Lavender-Light|default|Crisp, refreshing pastel light aesthetic with lavender accent|https://github.com/catppuccin/gtk/releases/download/v1.0.3/Catppuccin-Latte-Standard-Lavender-Light.zip"
    "dracula|Dracula Dark|Dracula|prefer-dark|High-contrast gothic dark palette with violet/pink neon accents|https://github.com/dracula/gtk/archive/master.tar.gz"
    "nordic|Nordic Arctic Dark|Nordic|prefer-dark|Clean, distraction-free arctic north-blue dark palette|https://github.com/EliverLara/Nordic/releases/latest/download/Nordic.tar.xz"
    "gruvbox-dark|Gruvbox Dark|Gruvbox-Dark|prefer-dark|Warm retro earthy groove tones for low eye strain|https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme/archive/refs/heads/master.tar.gz"
    "tokyo-night-dark|Tokyo Night Dark|Tokyo-Night-Dark|prefer-dark|Sleek cyberpunk aesthetic inspired by Tokyo neon lights|https://github.com/Fausto-Korpsvart/Tokyo-Night-GTK-Theme/archive/refs/heads/master.tar.gz"
    "yaru-blue-dark|Ubuntu Yaru Blue Dark|Yaru-blue-dark|prefer-dark|Official Ubuntu dark theme with vibrant blue accents|preinstalled"
    "yaru-dark|Ubuntu Yaru Dark (Standard)|Yaru-dark|prefer-dark|Canonical flagship dark theme with aubergine accents|preinstalled"
    "yaru|Ubuntu Yaru Light (Standard)|Yaru|default|Canonical flagship light theme with aubergine accents|preinstalled"
)

status_get_uniform_theme() {
    local gtheme="Unknown" cscheme="Unknown"
    if command -v gsettings &>/dev/null; then
        local raw_theme raw_scheme
        raw_theme=$(get_user_gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
        [ -n "$raw_theme" ] && gtheme="$raw_theme"
        raw_scheme=$(get_user_gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
        [ -n "$raw_scheme" ] && cscheme="$raw_scheme"
    fi
    echo "${gtheme} (${cscheme})"
}

is_theme_installed() {
    local theme_folder="$1"
    local target_user="${SUDO_USER:-$USER}"
    local uhome
    uhome=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)
    [ -z "$uhome" ] && uhome="$HOME"

    if [ -d "$uhome/.themes/$theme_folder" ] || [ -d "/usr/share/themes/$theme_folder" ] || [ -d "$uhome/.local/share/themes/$theme_folder" ]; then
        return 0
    fi
    return 1
}

show_theme_gallery() {
    local cur_theme
    cur_theme=$(status_get_uniform_theme)
    local active_name
    active_name=$(echo "$cur_theme" | awk '{print $1}')

    echo -e "${CYAN}========================================================================================${NC}"
    echo -e "${BOLD}              🎨 Popular Linux Themes Gallery & GNOME Uniform Styling${NC}"
    echo -e "${CYAN}========================================================================================${NC}"
    echo -e "Current Active Theme: ${GREEN}${BOLD}${cur_theme}${NC}"
    echo -e "Synchronizes: ${CYAN}Debian packages (GTK 3)${NC} ⇄ ${MAGENTA}GNOME Libadwaita (GTK 4)${NC} ⇄ ${YELLOW}Flatpak Sandboxes${NC}"
    echo ""
    printf "  %-18s %-24s %-12s %-10s\n" "THEME ID" "NAME & PALETTE" "STATUS" "STYLE"
    echo "  --------------------------------------------------------------------------------------"

    for entry in "${GALLERY_THEMES_MANIFEST[@]}"; do
        IFS='|' read -r tid tname tfolder tscheme tdesc turl <<< "$entry"
        local st_str="${DIM}Available${NC}"
        if is_theme_installed "$tfolder"; then
            st_str="${GREEN}[Installed]${NC}"
        fi
        if [ "$tfolder" = "$active_name" ]; then
            st_str="${MAGENTA}${BOLD}[★ ACTIVE]${NC}"
        fi

        local style_pill="${BLUE}Light${NC}"
        [ "$tscheme" = "prefer-dark" ] && style_pill="${CYAN}Dark${NC}"

        printf "  %-18s %-24s %-20b %-16b\n" "$tid" "$tname" "$st_str" "$style_pill"
        echo -e "    ${DIM}↳ $tdesc${NC}"
    done

    echo ""
    echo -e "${CYAN}----------------------------------------------------------------------------------------${NC}"
    echo -e "Quick Actions:"
    echo "  • Apply theme uniformly  : sudo $0 theme apply <theme_id>"
    echo "  • Download & install theme: sudo $0 theme install <theme_id>"
    echo "  • Reset to Ubuntu default : sudo $0 theme reset"
    echo "  • Check active sync state : $0 theme status"
    echo -e "${CYAN}========================================================================================${NC}"
}

interactive_theme_menu() {
    while true; do
        clear 2>/dev/null || true
        show_theme_gallery
        echo -e "${CYAN}┌── THEME SELECTION & ACTIONS ──────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${NC}  Enter a ${BOLD}Theme ID${NC} (e.g. adw-gtk3-dark, dracula, catppuccin-mocha) to apply"
        echo -e "${CYAN}│${NC}  ${BOLD}[R]${NC} Reset to Ubuntu System Default"
        echo -e "${CYAN}│${NC}  ${BOLD}[0/Q]${NC} Return to Previous Menu"
        echo -e "${CYAN}└───────────────────────────────────────────────────────────────────────────┘${NC}"
        read -rp "Select theme to apply [Theme ID / R / Q]: " topt || break
        case "$topt" in
            0|[Qq]|exit|back|"")
                break
                ;;
            [Rr]|reset)
                reset_uniform_theme
                echo ""
                read -rp "Press Enter to continue..." _ || true
                ;;
            *)
                apply_uniform_theme "$topt"
                echo ""
                read -rp "Press Enter to continue..." _ || true
                ;;
        esac
    done
}

install_gallery_theme() {
    local theme_key="$1"
    local target_user="${SUDO_USER:-$USER}"
    local uhome
    uhome=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)
    [ -z "$uhome" ] && uhome="$HOME"
    local owner_gid owner_uid
    owner_gid=$(id -g "$target_user" 2>/dev/null || echo "1000")
    owner_uid=$(id -u "$target_user" 2>/dev/null || echo "1000")

    local dest_dir="$uhome/.themes"
    mkdir -p "$dest_dir"

    local matched=0
    local target_url=""
    for entry in "${GALLERY_THEMES_MANIFEST[@]}"; do
        IFS='|' read -r tid tname tfolder tscheme tdesc turl <<< "$entry"
        if [ "$tid" = "$theme_key" ] || [ "$tfolder" = "$theme_key" ]; then
            matched=1
            target_url="$turl"
            break
        fi
    done

    if [ "$matched" -eq 0 ]; then
        log_err "Unknown gallery theme ID: '$theme_key'. Run '$0 theme gallery' to view available IDs."
        return 1
    fi

    if [ "$target_url" = "preinstalled" ]; then
        log_success "Theme '$theme_key' is already preinstalled on Ubuntu."
        return 0
    fi

    log_info "Downloading '$theme_key' package from upstream..."
    local tmp_archive
    tmp_archive=$(mktemp /tmp/theme_dl_XXXXXX)
    if curl -sSLf -m 35 "$target_url" -o "$tmp_archive" 2>/dev/null || wget -q -T 35 -O "$tmp_archive" "$target_url" 2>/dev/null; then
        log_info "Extracting theme archives into $dest_dir..."
        if [[ "$target_url" =~ \.zip$ ]]; then
            if command -v unzip &>/dev/null; then
                unzip -q -o "$tmp_archive" -d "$dest_dir" 2>/dev/null || true
            else
                log_warn "unzip utility not found; installing unzip..."
                apt-get update && apt-get install -y unzip
                unzip -q -o "$tmp_archive" -d "$dest_dir" 2>/dev/null || true
            fi
        elif [[ "$target_url" =~ \.tar\.xz$ ]]; then
            tar -xJf "$tmp_archive" -C "$dest_dir" 2>/dev/null || true
        else
            tar -xzf "$tmp_archive" -C "$dest_dir" 2>/dev/null || tar -xf "$tmp_archive" -C "$dest_dir" 2>/dev/null || true
        fi
        rm -f "$tmp_archive"
        chown -R --no-dereference "$owner_uid:$owner_gid" "$dest_dir" 2>/dev/null || true
        log_success "Theme '$theme_key' successfully installed in $dest_dir."
        return 0
    else
        rm -f "$tmp_archive"
        log_warn "Could not download theme '$theme_key' (network offline or upstream URL changed)."
        echo "You can manually extract the theme folder into $dest_dir."
        return 1
    fi
}

apply_uniform_theme() {
    local theme_choice="${1:-}"
    local target_user="${SUDO_USER:-$USER}"
    local uhome
    uhome=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)
    [ -z "$uhome" ] && uhome="$HOME"
    local owner_gid owner_uid
    owner_gid=$(id -g "$target_user" 2>/dev/null || echo "1000")
    owner_uid=$(id -u "$target_user" 2>/dev/null || echo "1000")

    if [ -z "$theme_choice" ]; then
        show_theme_gallery
        return 0
    fi

    local theme_folder="" color_scheme="prefer-dark" theme_title=""
    for entry in "${GALLERY_THEMES_MANIFEST[@]}"; do
        IFS='|' read -r tid tname tfolder tscheme tdesc turl <<< "$entry"
        if [ "$tid" = "$theme_choice" ] || [ "$tfolder" = "$theme_choice" ]; then
            theme_folder="$tfolder"
            color_scheme="$tscheme"
            theme_title="$tname"
            break
        fi
    done

    # Fallback to direct name matching if not in manifest
    if [ -z "$theme_folder" ]; then
        theme_folder="$theme_choice"
        if [[ "$theme_choice" =~ [Dd]ark ]]; then
            color_scheme="prefer-dark"
        else
            color_scheme="default"
        fi
        theme_title="$theme_choice"
    fi

    log_info "Synchronizing uniform theme: '$theme_title' across all application layers..."

    # Check existence
    local theme_path=""
    if [ -d "$uhome/.themes/$theme_folder" ]; then
        theme_path="$uhome/.themes/$theme_folder"
    elif [ -d "/usr/share/themes/$theme_folder" ]; then
        theme_path="/usr/share/themes/$theme_folder"
    elif [ -d "$uhome/.local/share/themes/$theme_folder" ]; then
        theme_path="$uhome/.local/share/themes/$theme_folder"
    fi

    if [ -z "$theme_path" ]; then
        log_warn "Theme '$theme_folder' is not currently installed."
        install_gallery_theme "$theme_choice" || true
        if [ -d "$uhome/.themes/$theme_folder" ]; then
            theme_path="$uhome/.themes/$theme_folder"
        elif [ -d "/usr/share/themes/$theme_folder" ]; then
            theme_path="/usr/share/themes/$theme_folder"
        fi
    fi

    # 1. GNOME Desktop Interface via gsettings
    if command -v gsettings &>/dev/null; then
        run_user_gsettings set org.gnome.desktop.interface gtk-theme "$theme_folder"
        run_user_gsettings set org.gnome.desktop.interface color-scheme "$color_scheme"
    fi

    # 2. GTK 3 & GTK 4 Configuration (settings.ini)
    for gver in "gtk-3.0" "gtk-4.0"; do
        local gdir="$uhome/.config/$gver"
        local gini="$gdir/settings.ini"
        if [ -L "$gdir" ] || [ -L "$gini" ] || ! is_safe_user_path "$uhome" "$gini"; then
            continue
        fi
        mkdir -p "$gdir"
        local dark_val=0
        [ "$color_scheme" = "prefer-dark" ] && dark_val=1
        if [ -f "$gini" ]; then
            sed -i '/^gtk-theme-name/d; /^gtk-application-prefer-dark-theme/d' "$gini" 2>/dev/null || true
            cat << EOF_S >> "$gini"
gtk-theme-name = $theme_folder
gtk-application-prefer-dark-theme = $dark_val
EOF_S
        else
            cat << EOF_S > "$gini"
[Settings]
gtk-theme-name = $theme_folder
gtk-application-prefer-dark-theme = $dark_val
EOF_S
        fi
        chown --no-dereference "$owner_uid:$owner_gid" "$gini" 2>/dev/null || true
        chmod 644 "$gini" 2>/dev/null || true
    done

    # 3. Libadwaita & GTK 4 Uniform Styling (gtk-4.0/gtk.css)
    local gtk4_dir="$uhome/.config/gtk-4.0"
    local gtk4_css="$gtk4_dir/gtk.css"
    if is_safe_user_path "$uhome" "$gtk4_dir"; then
        mkdir -p "$gtk4_dir"
        if [ -n "$theme_path" ] && [ -f "$theme_path/gtk-4.0/gtk.css" ]; then
            cp -p "$theme_path/gtk-4.0/gtk.css" "$gtk4_css" 2>/dev/null || true
            if [ -d "$theme_path/gtk-4.0/assets" ]; then
                cp -rp "$theme_path/gtk-4.0/assets" "$gtk4_dir/" 2>/dev/null || true
                chown -R --no-dereference "$owner_uid:$owner_gid" "$gtk4_dir/assets" 2>/dev/null || true
            fi
            chown --no-dereference "$owner_uid:$owner_gid" "$gtk4_css" 2>/dev/null || true
            chmod 644 "$gtk4_css" 2>/dev/null || true
            log_info "Synchronized Libadwaita GTK 4 custom CSS stylesheet ($gtk4_css)."
        elif [[ "$theme_folder" =~ ^adw-gtk3 ]] || [[ "$theme_folder" =~ ^Yaru ]]; then
            rm -f "$gtk4_css" "$gtk4_dir/gtk-dark.css"
            rm -rf "$gtk4_dir/assets"
            log_info "Cleaned custom GTK 4 CSS (Libadwaita will render pure native stylesheet matching $theme_folder)."
        fi
    fi

    # 4. Flatpak Sandbox Overrides & Environment
    if command -v flatpak &>/dev/null; then
        local fp_cmd=(flatpak override --user --filesystem=xdg-data/themes:ro --filesystem=~/.themes:ro --filesystem=xdg-data/icons:ro --filesystem=~/.icons:ro --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro --env=GTK_THEME="$theme_folder")
        if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            sudo -u "$SUDO_USER" "${fp_cmd[@]}" 2>/dev/null || true
        else
            "${fp_cmd[@]}" 2>/dev/null || true
        fi
        log_info "Configured Flatpak sandbox permissions and GTK_THEME=$theme_folder."
    fi

    verify_theme_preservation
    log_success "Uniform theming active: '$theme_title' synchronized across deb (GTK 3), Libadwaita (GTK 4), and Flatpak!"
}

reset_uniform_theme() {
    local target_user="${SUDO_USER:-$USER}"
    log_info "Resetting theming to default Ubuntu Yaru appearance for $target_user..."
    apply_uniform_theme "yaru-dark"
    if command -v flatpak &>/dev/null; then
        if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            sudo -u "$SUDO_USER" flatpak override --user --unset-env=GTK_THEME 2>/dev/null || true
        else
            flatpak override --user --unset-env=GTK_THEME 2>/dev/null || true
        fi
    fi
    log_success "Theme reset complete: restored default Ubuntu Yaru styling."
}

apply_system_tuning() {
    check_root "tune" "apply"

    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}     Applying Performance & Privacy System Tuning${NC}"
    echo -e "${CYAN}========================================================${NC}"

    # Capture initial baseline values before first modification
    save_tuning_baseline

    local tune_warns=0

    # 1. Enable Google BBR and Performance sysctls
    enable_bbr || ((tune_warns++)) || true

    # 2. Memory & Swappiness Optimization
    enable_swappiness || ((tune_warns++)) || true

    # 3. Kernel Privacy & Anti-Leak Sysctls
    enable_kernel_hardening

    # 3b. GNOME Desktop Privacy & Anti-Tracking
    if command -v gsettings &>/dev/null; then
        run_user_gsettings set org.gnome.desktop.privacy remember-app-usage false 2>/dev/null || true
        run_user_gsettings set org.gnome.desktop.privacy remember-recent-files false 2>/dev/null || true
        run_user_gsettings set org.gnome.desktop.privacy send-software-usage-stats false 2>/dev/null || true
        run_user_gsettings set org.gnome.desktop.privacy report-technical-problems false 2>/dev/null || true
    fi

    # 4. Prevent DHCP Hostname Leakage in NetworkManager
    enable_dhcp_privacy

    # 4b. Ensure local system hostname is resolved via /etc/hosts
    ensure_hostname_resolution

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

    # 7. Subpixel Font Anti-Blur (skipped on COSMIC DE where rendering is sharp natively)
    if [ "${XDG_CURRENT_DESKTOP:-}" != "COSMIC" ] && [ ! -d "${HOME}/.config/cosmic" ]; then
        enable_font_antiblur
    else
        log_info "COSMIC DE detected: font rendering is sharp natively, leaving undisturbed."
    fi

    echo ""
    if [ "$tune_warns" -eq 0 ]; then
        log_success "All system performance and privacy tunings applied successfully!"
    else
        log_warn "System tuning completed with $tune_warns warning(s); review output above."
    fi
    echo -e "${CYAN}========================================================${NC}"
}

revert_system_tuning() {
    check_root "tune" "revert"

    log_warn "Reverting performance & privacy tunings to Pop!_OS defaults..."
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
    disable_font_antiblur
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
# Disable IPv6 system-wide (pop-admin - loopback ::1 preserved)
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

    # Sync with dnscrypt-proxy if active
    if [ -f "$DNS_CONFIG" ] && systemctl is-active --quiet dnscrypt-proxy.service 2>/dev/null; then
        sed -i '/^block_ipv6 =/d' "$DNS_CONFIG"
        sed -i "/^listen_addresses =/a block_ipv6 = true" "$DNS_CONFIG"
        systemctl restart dnscrypt-proxy.service 2>/dev/null || true
    fi

    log_success "IPv6 has been DISABLED across network interfaces (localhost ::1 preserved)."
}

enable_ipv6() {
    check_root "ipv6" "enable"

    log_info "Enabling IPv6 system-wide with RFC 4941 Privacy Extensions..."
    rm -f "$IPV6_SYSCTL_CONF"
    sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null 2>&1 || true
    for iface in /proc/sys/net/ipv6/conf/*; do
        [ -d "$iface" ] && echo 0 > "$iface/disable_ipv6" 2>/dev/null || true
    done

    # RFC 4941 Privacy Extensions (randomized temporary addresses) & RFC 7217 Stable Privacy
    sysctl -w net.ipv6.conf.all.use_tempaddr=2 >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.default.use_tempaddr=2 >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.all.addr_gen_mode=3 >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.default.addr_gen_mode=3 >/dev/null 2>&1 || true
    for iface in /proc/sys/net/ipv6/conf/*; do
        if [ -d "$iface" ] && [ "$(basename "$iface")" != "lo" ]; then
            echo 2 > "$iface/use_tempaddr" 2>/dev/null || true
            echo 3 > "$iface/addr_gen_mode" 2>/dev/null || true
        fi
    done

    nmcli general reload 2>/dev/null || true

    # Sync with dnscrypt-proxy if active
    if [ -f "$DNS_CONFIG" ] && systemctl is-active --quiet dnscrypt-proxy.service 2>/dev/null; then
        sed -i '/^block_ipv6 =/d' "$DNS_CONFIG"
        sed -i "/^listen_addresses =/a block_ipv6 = false" "$DNS_CONFIG"
        systemctl restart dnscrypt-proxy.service 2>/dev/null || true
    fi

    log_success "IPv6 has been ENABLED across all network interfaces (RFC 4941 tempaddr=2 privacy active)."
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
    echo -e "${BOLD}    Laptop Linux Optimizer — Comprehensive Guided Setup Wizard        ${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "This wizard configures your laptop in a structured, logically sequenced order."
    echo -e "Every step explains ${BOLD}WHAT${NC} it changes, ${BOLD}WHY${NC} it is needed, and its direct benefit"
    echo -e "to battery health, responsiveness, acoustics, thermal performance & privacy:"
    echo ""
    echo -e "  ${BOLD}[ PHASE 1: FOUNDATION & BATTERY HEALTH ]${NC}"
    echo -e "  • Step 1/14: Target OS Platform Profile   (Ubuntu LTS vs Pop!_OS vs Linux Mint)"
    echo -e "  • Step 2/14: Battery Lifespan & Threshold (60% Desk / 80% Balanced / 100% Travel)"
    echo -e "  • Step 3/14: System Package Updates       (APT, Flatpak & Snap dist-upgrade)"
    echo ""
    echo -e "  ${BOLD}[ PHASE 2: HARDWARE ACCELERATION & DRIVERS ]${NC}"
    echo -e "  • Step 4/14: GPU Drivers & Media Codecs   (Mesa Vulkan, VA-API video decode, MS fonts)"
    echo -e "  • Step 5/14: Browser Video Acceleration   (VA-API hardware decode in Firefox/Brave)"
    echo -e "  • Step 6/14: Audio Pop & Crackle Shield   (Disable DAC sleep; eliminate speaker clicks)"
    echo ""
    echo -e "  ${BOLD}[ PHASE 3: INPUT, DISPLAY & STORAGE MAINTENANCE ]${NC}"
    echo -e "  • Step 7/14: Touchpad Latency & Gestures  (Zero-latency I2C bus PM & 1:1 kinetic gestures)"
    echo -e "  • Step 8/14: Font Anti-Blur & High-DPI    (Subpixel RGB hinting & Ozone Wayland clarity)"
    echo -e "  • Step 9/14: SSD / NVMe Periodic TRIM     (Automated weekly fstrim.timer for flash wear)"
    echo ""
    echo -e "  ${BOLD}[ PHASE 4: KERNEL, POWER & NETWORK TUNING ]${NC}"
    echo -e "  • Step 10/14: AMD CPU Power Governor (EPP)(balance_performance vs balance_power)"
    echo -e "  • Step 11/14: Kernel, Memory & Fast Boot  (TCP BBR, ZRAM compressed swap, NM boot delay)"
    echo ""
    echo -e "  ${BOLD}[ PHASE 5: SECURITY, PRIVACY & SYSTEM POLISH ]${NC}"
    echo -e "  • Step 12/14: Laptop Inbound Firewall     (UFW shield for public Wi-Fi; keeps LocalSend)"
    echo -e "  • Step 13/14: Privacy & Crash Shield      (Apport popups, DHCP hostname leak, kernel memory)"
    echo -e "  • Step 14/14: Background Daemons Clean   (Stop cellular scanning; protect printer discovery)"
    echo ""
    echo -e "  • Bonus:     Popular Themes Gallery       (Synchronize dark mode across GTK3, GTK4 & Flatpak)"
    echo -e "  • Finish:    Final Verification & Diagnostics Summary"
    echo -e "${CYAN}======================================================================${NC}"
    echo ""
    read -rp "Press Enter to begin or Ctrl+C to abort..." _
    echo ""

    # STEP 1: OS Selection
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 1/14] Target OS Platform Profile Selection${NC}"
    echo -e "Detected System Platform: ${GREEN}${BOLD}$(status_get_target_os)${NC}"
    echo ""
    echo -e "${BOLD}Why this matters:${NC}"
    echo -e "Different Linux desktop environments require distinct rendering rules, power"
    echo -e "management interfaces, and swappiness profiles:"
    echo -e "  • ${BOLD}Ubuntu LTS${NC} (GNOME) : Wayland native gestures, LCD subpixel rendering, Snap/APT."
    echo -e "  • ${BOLD}Pop!_OS${NC} (COSMIC)   : Rust-based COSMIC compositor, Pop ZRAM 180, system76-power."
    echo -e "  • ${BOLD}Linux Mint${NC} (Cinnamon): X11 font rendering, GTK XFT, swappiness 100."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "Select OS [1 for Ubuntu LTS, 2 for Pop!_OS, 3 for Linux Mint, Enter to keep current]: " os_choice
    case "$os_choice" in
        1) set_target_os "ubuntu" ;;
        2) set_target_os "popos" ;;
        3) set_target_os "mint" ;;
        *) log_info "Retaining target OS: $(status_get_target_os)" ;;
    esac
    echo ""

    # STEP 2: Battery Management
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 2/14] Battery Longevity & Persistent Charge Threshold${NC}"
    echo -e "Current Battery State: ${CYAN}${BOLD}$(status_get_battery)${NC}"
    echo ""
    echo -e "${BOLD}Why this matters:${NC}"
    echo -e "Lithium-ion batteries held at 100% state-of-charge under high cell voltage (>4.2V)"
    echo -e "suffer accelerated cathode oxidation and battery pouch swelling. Limiting maximum"
    echo -e "charge significantly reduces chemical wear, extending battery life by 2x to 3x."
    echo ""
    echo -e "Recommended Thresholds:"
    echo -e "  • ${BOLD}60%${NC}  - Desk / Docked: Minimal chemical stress for laptops plugged into AC."
    echo -e "  • ${BOLD}80%${NC}  - Balanced Daily (Recommended): Ample runtime (~5-7 hrs) with 2-3x longevity."
    echo -e "  • ${BOLD}100%${NC} - Travel / Mobile: Maximum battery runtime when preparing for flights/travel."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    show_battery_status
    echo ""
    read -rp "Configure persistent battery charge limiter? [Y/n] (Recommended: Y): " ans_bat
    if [[ ! "$ans_bat" =~ ^[Nn] ]]; then
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

    # STEP 3: System & Package Updates
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 3/14] System Package Updates & Cache Cleanup${NC}"
    echo ""
    echo -e "${BOLD}Why this matters:${NC}"
    echo -e "Running full package updates first refreshes APT repositories, Flatpaks, and Snaps."
    echo -e "This ensures that your Linux kernel, Mesa graphics libraries, and security patches"
    echo -e "are current before configuring hardware acceleration and background services."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "Run system updates and package cleanup? [Y/n] (Recommended: Y): " ans_up
    if [[ ! "$ans_up" =~ ^[Nn] ]]; then
        update_and_clean
    else
        log_info "Skipping Step 3 (Updates)."
    fi
    echo ""

    # STEP 4: GPU Drivers, VA-API & Essential Fonts
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 4/14] GPU Drivers, VA-API Video Acceleration & Fonts${NC}"
    echo -e "Current Media Suite: ${BOLD}$(status_get_media_drivers)${NC}"
    echo ""
    echo -e "${BOLD}Why this matters:${NC}"
    echo -e "Modern video streaming (YouTube, Twitch, Netflix) in 1080p and 4K requires dedicated"
    echo -e "hardware acceleration. Without Mesa Vulkan and VA-API drivers:"
    echo -e "  • Video decoding is handled entirely by your CPU, consuming 30-50% CPU power."
    echo -e "  • The CPU runs hotter, triggers audible fan noise, and drains battery rapidly."
    echo -e "Installing 'mesa-va-drivers' offloads video decoding to the AMD Vega VCN chip (<5% CPU)."
    echo -e "Additionally, installing Microsoft and coding fonts prevents missing glyphs and ugly"
    echo -e "fallback fonts in web pages, LibreOffice documents, and IDEs."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "Install Mesa Vulkan, VA-API video drivers, media codecs & fonts? [Y/n] (Recommended: Y): " ans_media
    if [[ ! "$ans_media" =~ ^[Nn] ]]; then
        install_all_media_suite
    else
        log_info "Skipping Step 4 (Hardware Acceleration Drivers)."
    fi
    echo ""

    # STEP 5: Browser Hardware Video Acceleration (VA-API)
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 5/14] Browser Hardware Video Acceleration (VA-API)${NC}"
    echo -e "Current Browser VA-API Status: ${BOLD}$(status_get_browser_vaapi)${NC}"
    echo ""
    echo -e "${BOLD}Why this matters:${NC}"
    echo -e "Even with GPU drivers installed, web browsers (Firefox Snap/native, Brave, Chrome)"
    echo -e "disable hardware video decoding on Linux by default. This causes browser tabs to decode"
    echo -e "YouTube and web video on the CPU."
    echo -e "Enabling VA-API injects hardware acceleration preferences into browser profile configs,"
    echo -e "allowing browsers to decode video directly on your AMD GPU, keeping your laptop cool and quiet."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "Configure Hardware Video Acceleration (VA-API) for Firefox, Brave & Chrome? [Y/n] (Recommended: Y): " ans_bvaapi
    if [[ ! "$ans_bvaapi" =~ ^[Nn] ]]; then
        enable_browser_vaapi
    else
        log_info "Skipping Step 5 (Browser VA-API)."
    fi
    echo ""

    # STEP 6: Audio Power-Save DAC Popping & Crackle Shield
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 6/14] Audio Power-Save DAC Popping & Crackle Shield${NC}"
    echo -e "Current Audio State: ${BOLD}$(status_get_audio_powersave)${NC}"
    echo ""
    echo -e "${BOLD}Why this matters:${NC}"
    echo -e "Intel and Realtek HDA audio controllers put the DAC (Digital-to-Analog Converter) into"
    echo -e "sleep mode after only 1 second of inactivity to save negligible power (~0.05W)."
    echo -e "Every time an app plays a notification, video, or music track, waking the DAC chip creates"
    echo -e "an audible 'pop', 'click', or crackle in your headphones and laptop speakers."
    echo -e "Disabling powersave (power_save=0) keeps the analog audio circuit active and permanently"
    echo -e "eliminates popping."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "Apply Audio Power-Save popping & crackle shield? [Y/n] (Recommended: Y): " ans_audio
    if [[ ! "$ans_audio" =~ ^[Nn] ]]; then
        enable_audio_powersave_fix
    else
        log_info "Skipping Step 6 (Audio Popping Shield)."
    fi
    echo ""

    # STEP 7: Touchpad Responsiveness & GNOME Gestures
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 7/14] Touchpad Responsiveness & GNOME Gestures${NC}"
    echo ""
    echo -e "${BOLD}Why this matters:${NC}"
    echo -e "On modern AMD laptops, ELAN/I2C trackpad controllers aggressively sleep the I2C bus"
    echo -e "whenever you stop typing. When you touch the trackpad again, it takes 50-200ms to wake"
    echo -e "up, causing a frustrating cursor freeze or stutter."
    echo -e "This optimization forces runtime PM awake, caps C2 sleep latency, and configures fluid"
    echo -e "1:1 kinetic multi-finger swipe gestures in GNOME/Wayland."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "Apply zero-latency Touchpad PM fix and tune GNOME gestures? [Y/n] (Recommended: Y): " ans_pad
    if [[ ! "$ans_pad" =~ ^[Nn] ]]; then
        tune_gnome_touchpad
        fix_touchpad_stutter
    else
        log_info "Skipping Step 7 (Touchpad Optimization)."
    fi
    echo ""

    # STEP 8: Subpixel Font Clarity & High-DPI Anti-Blur
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 8/14] Subpixel Font Clarity & High-DPI Anti-Blur${NC}"
    echo -e "Current Font Status: ${BOLD}$(status_get_font_antiblur)${NC}"
    echo ""
    echo -e "${BOLD}Why this matters:${NC}"
    echo -e "Flatpak containers, Electron applications (Slack, Discord, VS Code, Obsidian), and"
    echo -e "Wayland sessions often bypass native desktop subpixel hinting, resulting in blurry,"
    echo -e "fuzzy, low-contrast text on 1080p laptop displays."
    echo -e "Configuring fontconfig with subpixel RGB hinting and Ozone platform flags ensures"
    echo -e "crisp, razor-sharp typography across both native and containerized applications."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "Enable Subpixel Font Anti-Blur & High-DPI clarity rules? [Y/n] (Recommended: Y): " ans_blur
    if [[ ! "$ans_blur" =~ ^[Nn] ]]; then
        enable_font_antiblur
    else
        log_info "Skipping Step 8 (Font Anti-Blur)."
    fi
    echo ""

    # STEP 9: SSD / NVMe Periodic TRIM Maintenance
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 9/14] SSD / NVMe Periodic TRIM Maintenance${NC}"
    echo -e "Current TRIM State: ${BOLD}$(status_get_fstrim)${NC}"
    echo ""
    echo -e "${BOLD}Why this matters:${NC}"
    echo -e "Solid-state drives (NVMe & SATA SSDs) cannot overwrite flash cells without erasing"
    echo -e "them first. When files are deleted in Linux, the SSD is not notified unless a TRIM"
    echo -e "command is issued. Without periodic TRIM:"
    echo -e "  • Write speeds degrade over time."
    echo -e "  • Drive wear increases due to write amplification."
    echo -e "Enabling systemd's weekly 'fstrim.timer' runs automated background TRIM with zero"
    echo -e "system slowdown, preserving peak SSD performance and flash endurance."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "Enable automated weekly SSD / NVMe TRIM timer? [Y/n] (Recommended: Y): " ans_trim
    if [[ ! "$ans_trim" =~ ^[Nn] ]]; then
        enable_fstrim_timer
    else
        log_info "Skipping Step 9 (SSD TRIM)."
    fi
    echo ""

    # STEP 10: AMD P-State EPP CPU Power Governor
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 10/14] AMD P-State EPP Governor Profile${NC}"
    echo -e "Active EPP Preference: ${BOLD}${GREEN}$(status_get_epp)${NC}"
    echo ""
    echo -e "${BOLD}Why this matters:${NC}"
    echo -e "On AMD Ryzen processors running 'amd-pstate-epp', the Energy Performance Preference"
    echo -e "(EPP) determines how aggressively the CPU boosts frequencies for tasks:"
    echo -e "  • ${BOLD}balance_performance${NC} (Recommended): Ensures UI animations, browser scrolling, and"
    echo -e "    app launching feel instantaneous, while still clocking down to ~1.4GHz at idle."
    echo -e "  • ${BOLD}balance_power${NC}: Biases frequency scaling toward energy conservation for travel."
    echo -e "  • ${BOLD}power${NC}: Limits frequencies to base clocks for emergency battery saving."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "Select EPP profile [1: balance_performance (Recommended), 2: balance_power, 3: power, Enter to keep current]: " epp_choice
    case "$epp_choice" in
        1) set_epp_preference "balance_performance" ;;
        2) set_epp_preference "balance_power" ;;
        3) set_epp_preference "power" ;;
        *) log_info "Retaining active EPP preference: $(status_get_epp)" ;;
    esac
    echo ""

    # STEP 11: Kernel, Memory & Fast Desktop Boot
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 11/14] Kernel, Memory & Fast Desktop Boot Tuning${NC}"
    echo ""
    echo -e "${BOLD}Why this matters:${NC}"
    echo -e "This step optimizes three essential system-level performance bottlenecks:"
    echo -e "  1. ${BOLD}Google TCP BBR${NC}: Replaces legacy Cubic congestion control with BBR, keeping"
    echo -e "     network latency low and throughput high on lossy Wi-Fi networks."
    echo -e "  2. ${BOLD}ZRAM Compressed Swap (zstd)${NC}: Compresses idle RAM pages in-memory instead of"
    echo -e "     swapping to disk, effectively giving your laptop 50% more usable RAM."
    echo -e "  3. ${BOLD}Fast Desktop Boot${NC}: Disables 'NetworkManager-wait-online.service', removing"
    echo -e "     an unnecessary ~7 second delay during system startup."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "Enable TCP BBR, ZRAM compressed swap, and Fast Desktop Boot? [Y/n] (Recommended: Y): " ans_tune
    if [[ ! "$ans_tune" =~ ^[Nn] ]]; then
        enable_bbr
        disable_nm_wait_online
        enable_zram
    else
        log_info "Skipping Step 11 (Kernel & Boot Tuning)."
    fi
    echo ""

    # STEP 12: Laptop Inbound Firewall Shield (UFW)
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 12/14] Hardened Laptop Inbound Firewall Shield (UFW)${NC}"
    echo -e "Current Firewall State: ${BOLD}$(status_get_ufw)${NC}"
    echo ""
    echo -e "${BOLD}Why this matters:${NC}"
    echo -e "When connecting to public Wi-Fi in coffee shops, hotels, libraries, and universities,"
    echo -e "unshielded laptops are exposed to local network port scanning and exploit attempts."
    echo -e "Enabling the hardened UFW firewall blocks all unsolicited inbound connections while"
    echo -e "allowing all outbound internet traffic. LAN exceptions for LocalSend (53317/tcp+udp)"
    echo -e "and CUPS network printing (631/udp) are automatically created so your home LAN"
    echo -e "workflows remain completely uninterrupted."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "Enable hardened laptop UFW firewall with LocalSend/CUPS rules? [Y/n] (Recommended: Y): " ans_ufw
    if [[ ! "$ans_ufw" =~ ^[Nn] ]]; then
        enable_laptop_firewall
    else
        log_info "Skipping Step 12 (Firewall Shield)."
    fi
    echo ""

    # STEP 13: System Privacy & Apport Crash Popups Shield
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 13/14] System Privacy & Apport Crash Popups Shield${NC}"
    echo -e "Current Apport State: ${BOLD}$(status_get_apport)${NC}"
    echo ""
    echo -e "${BOLD}Why this matters:${NC}"
    echo -e "This step closes common privacy leaks and desktop annoyances:"
    echo -e "  1. ${BOLD}Apport Crash Shield${NC}: Silences recurring 'System program problem detected' popups"
    echo -e "     caused by non-fatal background crashes."
    echo -e "  2. ${BOLD}DHCP Hostname Mask${NC}: Prevents your laptop from broadcasting its hostname to Wi-Fi"
    echo -e "     routers, avoiding tracking in public router connection logs."
    echo -e "  3. ${BOLD}Kernel Memory Shield${NC}: Restricts unprivileged user-space processes from viewing"
    echo -e "     kernel memory pointers and logs (dmesg / kptr_restrict)."
    echo -e "  4. ${BOLD}SSH Inbound Shield${NC}: Masks the OpenSSH server daemon so port 22 is not left open."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "  • ${BOLD}Root Account Hardening${NC}: Ensures direct root password login & remote SSH login"
    echo -e "     are disabled, delegating administrative rights exclusively to sudo users."
    echo -e "Root Lock State: ${BOLD}$(status_get_root_lock)${NC}"
    read -rp "Apply privacy shields, lock root account & silence crash popups? [Y/n] (Recommended: Y): " ans_sec
    if [[ ! "$ans_sec" =~ ^[Nn] ]]; then
        lock_root_user
        disable_apport
        enable_dhcp_privacy
        enable_kernel_hardening
        enable_ssh_hardening
    else
        log_info "Skipping Step 13 (Privacy & Crash Shield)."
    fi
    echo ""

    # STEP 14: Background Daemons & Network Discovery
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Step 14/14] Background Daemons & Network Discovery${NC}"
    echo ""
    echo -e "${BOLD}Why this matters:${NC}"
    echo -e "Laptops without cellular SIM slots still run 'ModemManager', which wastes battery"
    echo -e "and CPU cycles periodically scanning serial ports."
    echo -e "We safely disable ModemManager while keeping discovery services active:"
    echo -e "  • ${BOLD}CUPS Browsed (Network Printers)${NC} : KEPT ACTIVE (Wi-Fi printer discovery preserved)"
    echo -e "  • ${BOLD}Avahi mDNS (Zeroconf / LocalSend)${NC}: KEPT ACTIVE (LocalSend & .local preserved)"
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "Disable ModemManager cellular scanner while preserving printer & LocalSend discovery? [Y/n] (Recommended: Y): " ans_daemons
    if [[ ! "$ans_daemons" =~ ^[Nn] ]]; then
        systemctl stop ModemManager 2>/dev/null || true
        systemctl disable ModemManager 2>/dev/null && echo "  [✓] Disabled ModemManager (cellular serial scanner stopped)." || true
        log_success "Network printer discovery (CUPS) and LocalSend discovery (Avahi) preserved!"
    else
        log_info "Skipping Step 14 (Background Daemons)."
    fi
    echo ""

    # BONUS STEP: Popular Themes Gallery & Uniform Theming
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    echo -e "${BOLD}>>> [Bonus Step] Popular Themes Gallery & Uniform Styling${NC}"
    echo -e "Current Uniform Theme: ${MAGENTA}${BOLD}$(status_get_uniform_theme)${NC}"
    echo ""
    echo -e "${BOLD}Why this matters:${NC}"
    echo -e "Synchronizes dark/light styling and accent colors across traditional deb packages (GTK3),"
    echo -e "modern Libadwaita apps (GTK4), and sandboxed Flatpaks for visual consistency."
    echo -e "${CYAN}----------------------------------------------------------------------${NC}"
    read -rp "Open Themes Gallery or apply a uniform theme now? [y/N]: " ans_theme
    if [[ "$ans_theme" =~ ^[Yy]$ ]]; then
        show_theme_gallery
        echo ""
        read -rp "Enter Theme ID to apply now (e.g. adw-gtk3-dark, dracula, or Enter to skip): " chosen_tid
        if [ -n "$chosen_tid" ]; then
            apply_uniform_theme "$chosen_tid"
        else
            log_info "No theme selected; retaining current styling."
        fi
    else
        log_info "Skipping Themes Gallery."
    fi
    echo ""

    # FINISH & SUMMARY
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${GREEN}${BOLD}✓ Comprehensive Guided Laptop Optimization Complete!${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    show_system_summary
    echo ""
    read -rp "Would you like to reboot the laptop now to finalize all kernel and network tunings? [y/N]: " ans_reboot
    if [[ "$ans_reboot" =~ ^[Yy]$ ]]; then
        log_info "Rebooting system now..."
        systemctl reboot -i 2>/dev/null || reboot
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
    if [ -f "$BATTERY_SERVICE" ] && (systemctl is-enabled --quiet laptop-battery-limit.service 2>/dev/null || systemctl is-enabled --quiet asus-battery-limit.service 2>/dev/null || systemctl is-enabled --quiet pop-battery-limit.service 2>/dev/null); then
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
    if [ -f "$OPTIMIZER_TIMER" ] && (systemctl is-enabled --quiet laptop-optimizer.timer 2>/dev/null || systemctl is-enabled --quiet pop-optimizer.timer 2>/dev/null); then
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
        local tempaddr
        tempaddr=$(cat /proc/sys/net/ipv6/conf/all/use_tempaddr 2>/dev/null || echo "0")
        if [ "$tempaddr" -eq 2 ]; then
            echo "ENABLED (RFC 4941 Privacy Active)"
        else
            echo "ENABLED"
        fi
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
    if [ -f "$STATE_DIR/dhcp-privacy-enabled" ] || [ -f /var/lib/pop-admin/dhcp-privacy-enabled ] || [ -f /var/lib/mint-admin/dhcp-privacy-enabled ]; then
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
        echo "ACTIVE (Printer Discovery)"
    else
        echo "DISABLED (No Network Discovery)"
    fi
}

status_get_modem() {
    if systemctl is-active --quiet ModemManager 2>/dev/null; then
        echo "ACTIVE"
    else
        echo "DISABLED"
    fi
}

status_get_font_antiblur() {
    # If target OS is Pop!_OS / COSMIC, font rendering is sharp natively; leave undisturbed
    if [ "$(get_target_os)" = "popos" ] || [ "${XDG_CURRENT_DESKTOP:-}" = "COSMIC" ] || [ -d "${HOME}/.config/cosmic" ]; then
        echo "COSMIC Native (Sharp)"
        return
    fi

    local target_user="${SUDO_USER:-$USER}"
    local uhome
    uhome=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)
    [ -z "$uhome" ] && uhome="$HOME"
    local fc_file="$uhome/.config/fontconfig/fonts.conf"
    local fp_overrides="$uhome/.local/share/flatpak/overrides/global"

    local is_wayland=0
    if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        is_wayland=1
    fi

    local has_fc=0
    local has_fp=0

    if [ -f "$fc_file" ] && grep -qi "lcdfilter\|subpixel\|hintfull\|hintslight" "$fc_file" 2>/dev/null; then
        has_fc=1
    fi
    if [ -f "$fp_overrides" ] && grep -qi "xdg-config/fontconfig\|ELECTRON_OZONE_PLATFORM_HINT" "$fp_overrides" 2>/dev/null; then
        has_fp=1
    elif ! command -v flatpak &>/dev/null; then
        has_fp=1
    fi

    if [ "$has_fc" -eq 1 ] && [ "$has_fp" -eq 1 ]; then
        if [ "$is_wayland" -eq 1 ]; then
            echo "ACTIVE (Wayland Native Ozone)"
        else
            echo "ACTIVE (Subpixel RGB)"
        fi
    else
        echo "UNCONFIGURED"
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
            set_epp_preference "balance_performance"
            mkdir -p "$(dirname "$PROFILE_CONF")"
            echo "PROFILE=desk" > "$PROFILE_CONF"
            log_success "Profile preset 'Desk / Docked' applied (60% battery threshold, BBR, ZRAM, EPP balance_performance)."
            ;;
        balanced|daily|default)
            log_info "Applying 'Balanced Daily' profile preset..."
            install_battery_service 80
            apply_system_tuning
            set_epp_preference "balance_power"
            mkdir -p "$(dirname "$PROFILE_CONF")"
            echo "PROFILE=balanced" > "$PROFILE_CONF"
            log_success "Profile preset 'Balanced Daily' applied (80% battery threshold, BBR, ZRAM, EPP balance_power)."
            ;;
        travel|mobile|full)
            log_info "Applying 'Travel / Mobile' profile preset..."
            set_battery_threshold 100
            set_epp_preference "power"
            mkdir -p "$(dirname "$PROFILE_CONF")"
            echo "PROFILE=travel" > "$PROFILE_CONF"
            log_success "Profile preset 'Travel / Mobile' applied (100% full capacity, EPP power)."
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
    local cur_preset cur_bat cur_zram cur_bbr cur_dns cur_mac cur_timer cur_ipv6 cur_nm cur_blur
    cur_preset=$(status_get_preset)
    cur_bat=$(status_get_battery)
    cur_zram=$(status_get_zram)
    cur_bbr=$(status_get_bbr)
    cur_dns=$(status_get_dns)
    cur_mac=$(status_get_mac)
    cur_timer=$(status_get_timer)
    cur_ipv6=$(status_get_ipv6)
    cur_nm=$(status_get_wait_online)
    cur_blur=$(status_get_font_antiblur)

    local updates="${1:-}"
    local cleanable_kb="${2:-}"
    [ -z "$updates" ] && updates=$(check_pending_updates)
    [ -z "$cleanable_kb" ] && cleanable_kb=$(check_cleanable_cache)

    echo -e "${CYAN}┌──────────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}  ${BOLD}${GREEN}⚡ Laptop Linux Optimizer — Comprehensive System Status Summary${NC}             ${CYAN}│${NC}"
    echo -e "${CYAN}├──────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC}  ${BOLD}[ HARDWARE & PERFORMANCE ]${NC}"
    echo -e "${CYAN}│${NC}  • Target OS Platform   : ${GREEN}${BOLD}$(status_get_target_os)${NC}"
    echo -e "${CYAN}│${NC}  • Active Profile Preset: ${GREEN}${BOLD}${cur_preset}${NC}"
    echo -e "${CYAN}│${NC}  • Battery Diagnostics  : ${CYAN}${cur_bat}${NC}"
    echo -e "${CYAN}│${NC}  • ZRAM Compressed Swap : ${GREEN}${cur_zram}${NC}"
    echo -e "${CYAN}│${NC}  • TCP Congestion (BBR) : ${GREEN}${cur_bbr}${NC}"
    echo -e "${CYAN}│${NC}  • NM Boot Speed Delay  : ${GREEN}${cur_nm}${NC}"
    echo -e "${CYAN}│${NC}  • GRUB Baseline Config : $([ -f "${GRUB_DEFAULT_FILE:-/etc/default/grub}" ] && echo -e "${GREEN}PRESENT (/etc/default/grub)${NC}" || echo -e "${YELLOW}MISSING${NC}")"
    echo -e "${CYAN}│${NC}  • ELAN Touchpad PM     : $(status_get_touchpad)"
    echo -e "${CYAN}│${NC}  • Media & GPU Drivers  : $(status_get_media_drivers)"
    echo -e "${CYAN}│${NC}  • CPU Scaling (EPP)    : ${GREEN}${BOLD}$(status_get_epp)${NC}"
    echo -e "${CYAN}│${NC}  • Audio Pop Shield     : $(status_get_audio_powersave)"
    echo -e "${CYAN}│${NC}  • SSD Periodic TRIM    : $(status_get_fstrim)"
    echo -e "${CYAN}│${NC}  • Browser Video VA-API : $(status_get_browser_vaapi)"
    if [[ "$cur_blur" =~ ACTIVE ]] || [[ "$cur_blur" =~ COSMIC ]]; then
        echo -e "${CYAN}│${NC}  • Font Anti-Blur (LCD) : ${GREEN}${cur_blur}${NC}"
    else
        echo -e "${CYAN}│${NC}  • Font Anti-Blur (LCD) : ${YELLOW}${cur_blur}${NC} (Flatpak blur risk)"
    fi
    echo -e "${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}  ${BOLD}[ SECURITY & NETWORK PRIVACY ]${NC}"
    echo -e "${CYAN}│${NC}  • Laptop UFW Shield    : $(status_get_ufw)"
    echo -e "${CYAN}│${NC}  • Apport Crash Popups  : $(status_get_apport)"
    echo -e "${CYAN}│${NC}  • Root User Access     : $(status_get_root_lock)"
    echo -e "${CYAN}│${NC}  • SSH Inbound Shield   : $(status_get_ssh_server)"
    echo -e "${CYAN}│${NC}  • Printer Discovery    : $(status_get_cups)"
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

# ==============================================================================
# MODULE 10: GRUB Bootloader Configuration & Recovery
# ==============================================================================

ensure_grub_default_config() {
    local bootloader
    bootloader=$(detect_bootloader_type)
    if [ "$bootloader" != "GRUB" ] && [ ! -d /boot/grub ] && ! command -v update-grub >/dev/null 2>&1; then
        return 0
    fi
    local grub_default="${GRUB_DEFAULT_FILE:-/etc/default/grub}"
    if [ ! -f "$grub_default" ]; then
        log_warn "GRUB configuration template $grub_default is missing; recovering canonical defaults..."
        mkdir -p /etc/default
        if [ -f "${GRUB_DEFAULT_TEMPLATE:-/usr/share/grub/default/grub}" ]; then
            cp "${GRUB_DEFAULT_TEMPLATE:-/usr/share/grub/default/grub}" "$grub_default"
        else
            cat << 'EOF' > "$grub_default"
# Generated by laptop-linux-optimiser: canonical bootloader configuration
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=`( . /etc/os-release && echo ${NAME} ) 2>/dev/null || echo "Ubuntu"`
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
GRUB_DISABLE_OS_PROBER=true
EOF
        fi
        chmod 644 "$grub_default" 2>/dev/null || true
        log_success "Restored canonical $grub_default."
        if command -v update-grub >/dev/null 2>&1 && [ -d /boot/grub ]; then
            log_info "Regenerating GRUB bootloader configuration (update-grub)..."
            update-grub >/dev/null 2>&1 || log_warn "update-grub exited with non-zero status"
            log_success "GRUB bootloader configuration rebuilt successfully (/boot/grub/grub.cfg)."
        fi
    fi
}

fix_grub_menu() {
    check_root "grub" "fix"
    log_info "Verifying and repairing GRUB bootloader configuration..."
    local grub_default="${GRUB_DEFAULT_FILE:-/etc/default/grub}"
    if [ ! -f "$grub_default" ]; then
        ensure_grub_default_config
    else
        log_info "Checking $grub_default entries..."
        local updated=0
        if ! grep -q "^GRUB_DEFAULT=" "$grub_default" 2>/dev/null; then
            echo 'GRUB_DEFAULT=0' >> "$grub_default"
            updated=1
        fi
        if ! grep -q "^GRUB_TIMEOUT=" "$grub_default" 2>/dev/null; then
            echo 'GRUB_TIMEOUT=0' >> "$grub_default"
            updated=1
        fi
        if ! grep -q "^GRUB_TIMEOUT_STYLE=" "$grub_default" 2>/dev/null; then
            echo 'GRUB_TIMEOUT_STYLE=hidden' >> "$grub_default"
            updated=1
        fi
        if ! grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_default" 2>/dev/null; then
            echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' >> "$grub_default"
            updated=1
        fi
        if command -v update-grub >/dev/null 2>&1 && [ -d /boot/grub ]; then
            log_info "Running update-grub to synchronize /boot/grub/grub.cfg..."
            update-grub >/dev/null 2>&1 || log_warn "update-grub failed; check /boot space"
            log_success "GRUB bootloader configuration refreshed."
        fi
    fi
}

show_grub_status() {
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}               GRUB Bootloader Status${NC}"
    echo -e "${CYAN}========================================================${NC}"
    local grub_default="${GRUB_DEFAULT_FILE:-/etc/default/grub}"
    if [ -f "$grub_default" ]; then
        local timeout style cmdline dist
        timeout=$(grep -E '^[[:space:]]*GRUB_TIMEOUT=' "$grub_default" | tail -n1 | cut -d= -f2- | tr -d '"' || echo "unset")
        style=$(grep -E '^[[:space:]]*GRUB_TIMEOUT_STYLE=' "$grub_default" | tail -n1 | cut -d= -f2- | tr -d '"' || echo "unset")
        cmdline=$(grep -E '^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_default" | tail -n1 | cut -d= -f2- | tr -d '"' || echo "unset")
        dist=$(grep -E '^[[:space:]]*GRUB_DISTRIBUTOR=' "$grub_default" | tail -n1 | cut -d= -f2- || echo "unset")
        echo -e "GRUB Base Config : ${GREEN}PRESENT ($grub_default)${NC}"
        echo -e "  • Timeout      : ${CYAN}${timeout}s${NC}"
        echo -e "  • Timeout Style: ${CYAN}${style}${NC}"
        echo -e "  • Kernel Cmdline: ${CYAN}${cmdline}${NC}"
        echo -e "  • Distributor  : ${CYAN}${dist}${NC}"
    else
        echo -e "GRUB Base Config : ${RED}MISSING ($grub_default)${NC}"
        echo -e "  ${YELLOW}Notice: Run 'sudo $0 grub fix' to restore canonical defaults.${NC}"
    fi
    if [ -d "/etc/default/grub.d" ]; then
        echo ""
        echo "Active GRUB Drop-ins (/etc/default/grub.d/):"
        for cf in /etc/default/grub.d/*.cfg; do
            [ -e "$cf" ] || continue
            echo -e "  • ${BOLD}$(basename "$cf")${NC}: $(cat "$cf" | tr '\n' ' ')"
        done
    fi
    echo -e "${CYAN}========================================================${NC}"
}

# ==============================================================================
# MODULE 11: ELAN I2C Touchpad Freeze Fix & AMD Bus Power Management
# ==============================================================================

# Discovery of ELAN I2C devices & DesignWare controllers
touchpad_elan_devs() {
    local d
    for d in /sys/bus/i2c/devices/*; do
        [ -r "$d/name" ] || continue
        [[ $(<"$d/name") == ELAN* ]] && printf '%s\n' "$d"
    done
    return 0
}

touchpad_ctrl_devs() {
    local d
    for d in /sys/bus/platform/drivers/i2c_designware/* /sys/devices/platform/AMDI0010:*; do
        [ -e "$d/power/control" ] && readlink -f "$d"
    done | sort -u
    return 0
}

detect_bootloader_type() {
    if [ -f /etc/kernelstub/configuration ]; then
        echo "systemd-boot (managed by kernelstub)"
    elif [ -d /sys/firmware/efi ] && bootctl status 2>/dev/null | grep -qi "systemd-boot"; then
        echo "systemd-boot"
    elif [ -d /boot/grub ] || command -v update-grub >/dev/null 2>&1; then
        echo "GRUB"
    else
        echo "standard EFI / unknown"
    fi
}

detect_gpu_psr_param() {
    if lspci 2>/dev/null | grep -qi "VGA.*AMD"; then
        echo "amdgpu.dcdebugmask=0x410"
    elif lspci 2>/dev/null | grep -qi "VGA.*Intel"; then
        echo "i915.enable_psr=0"
    elif [ -d /sys/module/amdgpu ]; then
        echo "amdgpu.dcdebugmask=0x410"
    elif [ -d /sys/module/i915 ]; then
        echo "i915.enable_psr=0"
    else
        echo ""
    fi
}

is_touchpad_cstate_configured() {
    if [ -f /etc/kernelstub/configuration ]; then
        grep -q "processor.max_cstate=2" /etc/kernelstub/configuration 2>/dev/null
    elif [ -f "$TOUCHPAD_CSTATE_GRUB" ]; then
        grep -q "processor.max_cstate=2" "$TOUCHPAD_CSTATE_GRUB" 2>/dev/null
    else
        return 1
    fi
}

apply_touchpad_cstate_cap() {
    check_root_nolock "touchpad" "cstate" "enable"
    log_info "Capping idle C-state to C2 (processor.max_cstate=2) to prevent I2C buffer starvation..."
    if command -v kernelstub >/dev/null 2>&1 && [ -f /etc/kernelstub/configuration ]; then
        if ! grep -q "processor.max_cstate=2" /etc/kernelstub/configuration 2>/dev/null; then
            kernelstub -a "processor.max_cstate=2"
            log_success "Added processor.max_cstate=2 to kernelstub (persists across kernel updates)."
        else
            log_success "processor.max_cstate=2 is already configured in kernelstub."
        fi
    elif [ -d /etc/default/grub.d ] || command -v update-grub >/dev/null 2>&1; then
        ensure_grub_default_config
        mkdir -p /etc/default/grub.d
        if [ -f "$TOUCHPAD_CSTATE_GRUB" ]; then
            if ! grep -q "processor.max_cstate=2" "$TOUCHPAD_CSTATE_GRUB" 2>/dev/null; then
                sed -i "s/\"$/ processor.max_cstate=2\"/" "$TOUCHPAD_CSTATE_GRUB"
            fi
        else
            cat << 'EOF' > "$TOUCHPAD_CSTATE_GRUB"
# Installed by laptop-linux-optimiser: cap idle C-states & disable GPU PSR stutter
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT processor.max_cstate=2"
EOF
            chmod 644 "$TOUCHPAD_CSTATE_GRUB" 2>/dev/null || true
        fi
        if command -v update-grub >/dev/null 2>&1 && [ -d /boot/grub ]; then
            update-grub >/dev/null 2>&1 || log_warn "update-grub failed; check /boot space"
        fi
        log_success "Added processor.max_cstate=2 to GRUB drop-in $TOUCHPAD_CSTATE_GRUB."
    else
        log_warn "No supported bootloader (kernelstub or GRUB) found to persist processor.max_cstate=2."
    fi
}

remove_touchpad_cstate_cap() {
    check_root_nolock "touchpad" "cstate" "disable"
    log_info "Reverting C-state cap (processor.max_cstate=2)..."
    if command -v kernelstub >/dev/null 2>&1 && [ -f /etc/kernelstub/configuration ]; then
        if grep -q "processor.max_cstate=2" /etc/kernelstub/configuration 2>/dev/null; then
            kernelstub -d "processor.max_cstate=2" 2>/dev/null || true
            log_success "Removed processor.max_cstate=2 from kernelstub."
        fi
    fi
    if [ -f "$TOUCHPAD_CSTATE_GRUB" ]; then
        if grep -q "processor.max_cstate=2" "$TOUCHPAD_CSTATE_GRUB" 2>/dev/null; then
            sed -i "s/ processor.max_cstate=2//g; s/processor.max_cstate=2//g" "$TOUCHPAD_CSTATE_GRUB"
            local param
            param=$(detect_gpu_psr_param)
            if [ -z "$param" ] || ! grep -q "$param" "$TOUCHPAD_CSTATE_GRUB" 2>/dev/null; then
                rm -f "$TOUCHPAD_CSTATE_GRUB"
            fi
            if command -v update-grub >/dev/null 2>&1 && [ -d /boot/grub ]; then
                ensure_grub_default_config
                update-grub >/dev/null 2>&1 || log_warn "update-grub failed; check /boot space"
            fi
            log_success "Removed processor.max_cstate=2 from $TOUCHPAD_CSTATE_GRUB."
        fi
    fi
}

toggle_touchpad_cstate_cap() {
    check_root_nolock "touchpad" "cstate" "toggle"
    if is_touchpad_cstate_configured || grep -q "processor.max_cstate=2" /proc/cmdline; then
        remove_touchpad_cstate_cap
    else
        apply_touchpad_cstate_cap
    fi
}

# GPU Panel Self Refresh (PSR) Disabling for Micro-Stutter Elimination
is_touchpad_psr_configured() {
    local param
    param=$(detect_gpu_psr_param)
    [ -z "$param" ] && return 1
    if [ -f /etc/kernelstub/configuration ]; then
        grep -q "$param" /etc/kernelstub/configuration 2>/dev/null
    elif [ -f "$TOUCHPAD_CSTATE_GRUB" ]; then
        grep -q "$param" "$TOUCHPAD_CSTATE_GRUB" 2>/dev/null
    else
        return 1
    fi
}

apply_touchpad_psr_fix() {
    check_root_nolock "touchpad" "psr" "enable"
    local param
    param=$(detect_gpu_psr_param)
    if [ -z "$param" ]; then
        log_info "No supported GPU (AMD or Intel) detected for Panel Self Refresh tuning."
        return 0
    fi
    log_info "Disabling GPU Panel Self Refresh ($param) to prevent display wake-up stutter..."
    if command -v kernelstub >/dev/null 2>&1 && [ -f /etc/kernelstub/configuration ]; then
        if ! grep -q "$param" /etc/kernelstub/configuration 2>/dev/null; then
            kernelstub -a "$param"
            log_success "Added $param to kernelstub (persists across kernel updates)."
        else
            log_success "$param is already configured in kernelstub."
        fi
    elif [ -d /etc/default/grub.d ] || command -v update-grub >/dev/null 2>&1; then
        ensure_grub_default_config
        mkdir -p /etc/default/grub.d
        if [ -f "$TOUCHPAD_CSTATE_GRUB" ]; then
            if ! grep -q "$param" "$TOUCHPAD_CSTATE_GRUB" 2>/dev/null; then
                sed -i "s/\"$/ $param\"/" "$TOUCHPAD_CSTATE_GRUB"
            fi
        else
            cat << EOF > "$TOUCHPAD_CSTATE_GRUB"
# Installed by laptop-linux-optimiser: cap idle C-states & disable GPU PSR stutter
GRUB_CMDLINE_LINUX_DEFAULT="\$GRUB_CMDLINE_LINUX_DEFAULT $param"
EOF
            chmod 644 "$TOUCHPAD_CSTATE_GRUB" 2>/dev/null || true
        fi
        if command -v update-grub >/dev/null 2>&1 && [ -d /boot/grub ]; then
            update-grub >/dev/null 2>&1 || log_warn "update-grub failed; check /boot space"
        fi
        log_success "Added $param to GRUB drop-in $TOUCHPAD_CSTATE_GRUB."
    else
        log_warn "No supported bootloader (kernelstub or GRUB) found to persist $param."
    fi
}

remove_touchpad_psr_fix() {
    check_root_nolock "touchpad" "psr" "disable"
    local param
    param=$(detect_gpu_psr_param)
    [ -z "$param" ] && return 0
    log_info "Reverting GPU PSR fix ($param)..."
    if command -v kernelstub >/dev/null 2>&1 && [ -f /etc/kernelstub/configuration ]; then
        if grep -q "$param" /etc/kernelstub/configuration 2>/dev/null; then
            kernelstub -d "$param" 2>/dev/null || true
            log_success "Removed $param from kernelstub."
        fi
    fi
    if [ -f "$TOUCHPAD_CSTATE_GRUB" ]; then
        if grep -q "$param" "$TOUCHPAD_CSTATE_GRUB" 2>/dev/null; then
            sed -i "s/ $param//g; s/$param//g" "$TOUCHPAD_CSTATE_GRUB"
            if ! grep -q "processor.max_cstate=2" "$TOUCHPAD_CSTATE_GRUB" 2>/dev/null; then
                rm -f "$TOUCHPAD_CSTATE_GRUB"
            fi
            if command -v update-grub >/dev/null 2>&1 && [ -d /boot/grub ]; then
                ensure_grub_default_config
                update-grub >/dev/null 2>&1 || log_warn "update-grub failed; check /boot space"
            fi
            log_success "Removed $param from $TOUCHPAD_CSTATE_GRUB."
        fi
    fi
}

toggle_touchpad_psr_fix() {
    check_root_nolock "touchpad" "psr" "toggle"
    local param
    param=$(detect_gpu_psr_param)
    if is_touchpad_psr_configured || ([ -n "$param" ] && grep -q "$param" /proc/cmdline); then
        remove_touchpad_psr_fix
    else
        apply_touchpad_psr_fix
    fi
}

show_touchpad_psr_status() {
    local param
    param=$(detect_gpu_psr_param)
    local psr_live="inactive (default GPU power management)"
    local psr_pers="absent"
    if [ -n "$param" ] && grep -q "$param" /proc/cmdline; then
        psr_live="active ($param present in /proc/cmdline)"
    elif [ "$(cat /sys/module/amdgpu/parameters/dcdebugmask 2>/dev/null)" = "1040" ] || [ "$(cat /sys/module/amdgpu/parameters/dcdebugmask 2>/dev/null)" = "16" ]; then
        psr_live="active (amdgpu dcdebugmask in effect)"
    fi
    if is_touchpad_psr_configured; then
        psr_pers="configured (persists across boots)"
    fi
    echo "Touchpad GPU PSR Fix: $psr_live [bootloader: $psr_pers]"
}

# Libinput Hardware Quirks (Resolution & Pressure Calibration)
touchpad_has_pressure() {
    local abs_cap
    for abs_cap in /sys/class/input/event*/device/capabilities/abs; do
        [ -r "$abs_cap" ] || continue
        local dev_name
        dev_name=$(cat "$(dirname "$abs_cap")/name" 2>/dev/null || true)
        if [[ "$dev_name" =~ [Tt]ouchpad ]]; then
            local hex_val
            hex_val=$(cat "$abs_cap" 2>/dev/null || echo "0")
            if command -v python3 >/dev/null 2>&1; then
                if python3 -c "v=int('$hex_val', 16); exit(0 if (v & ((1<<24)|(1<<58))) else 1)" 2>/dev/null; then
                    return 0
                fi
            fi
        fi
    done
    return 1
}

is_touchpad_quirks_installed() {
    [ -f "$TOUCHPAD_LIBINPUT_QUIRKS" ] && grep -q "AttrResolutionHint=31x31" "$TOUCHPAD_LIBINPUT_QUIRKS" 2>/dev/null && ! grep -q "BTN_TOOL_DOUBLETAP" "$TOUCHPAD_LIBINPUT_QUIRKS" 2>/dev/null
}

apply_touchpad_quirks() {
    check_root_nolock "touchpad" "quirks" "enable"
    log_info "Installing libinput hardware quirks ($TOUCHPAD_LIBINPUT_QUIRKS)..."
    mkdir -p "$(dirname "$TOUCHPAD_LIBINPUT_QUIRKS")"

    local pressure_block=""
    local has_p=0
    if touchpad_has_pressure; then
        has_p=1
        pressure_block="AttrPressureRange=10:8"
    fi

    cat << EOF > "$TOUCHPAD_LIBINPUT_QUIRKS"
# Installed by laptop-linux-optimiser: calibrate ELAN touchpad resolution and pressure
[ELAN Touchpad Responsive Calibration]
MatchName=*ELAN*Touchpad*
AttrResolutionHint=31x31
${pressure_block}

[ELAN I2C Hardware Matching]
MatchBus=i2c
MatchVendor=0x04F3
MatchUdevType=touchpad
AttrResolutionHint=31x31
${pressure_block}
EOF
    sed -i '/^[[:space:]]*$/d' "$TOUCHPAD_LIBINPUT_QUIRKS" 2>/dev/null || true
    chmod 644 "$TOUCHPAD_LIBINPUT_QUIRKS" 2>/dev/null || true
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --subsystem-match=input 2>/dev/null || true
    if [ "$has_p" -eq 1 ]; then
        log_success "Libinput quirks installed (calibrated 31x31 resolution hint and 10:8 pressure range; two-finger scrolling preserved)."
    else
        log_success "Libinput quirks installed (calibrated 31x31 resolution hint; phantom pressure skipped for zero-pressure PTP device; two-finger scrolling preserved)."
    fi
}

remove_touchpad_quirks() {
    check_root_nolock "touchpad" "quirks" "disable"
    log_info "Removing libinput hardware quirks ($TOUCHPAD_LIBINPUT_QUIRKS)..."
    rm -f "$TOUCHPAD_LIBINPUT_QUIRKS"
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --subsystem-match=input 2>/dev/null || true
    log_success "Libinput quirks removed."
}

toggle_touchpad_quirks() {
    check_root_nolock "touchpad" "quirks" "toggle"
    if is_touchpad_quirks_installed; then
        remove_touchpad_quirks
    else
        apply_touchpad_quirks
    fi
}

show_touchpad_quirks_status() {
    if is_touchpad_quirks_installed; then
        local q_desc="31x31 resolution (preserves two-finger scrolling & gestures)"
        if grep -q "AttrPressureRange" "$TOUCHPAD_LIBINPUT_QUIRKS" 2>/dev/null; then
            if ! touchpad_has_pressure; then
                q_desc="31x31 resolution, 10:8 pressure [WARNING: phantom pressure quirk active on zero-pressure PTP device - run fix-stutter]"
            else
                q_desc="31x31 resolution, 10:8 pressure"
            fi
        fi
        echo "Touchpad Libinput Quirks: INSTALLED ($TOUCHPAD_LIBINPUT_QUIRKS: $q_desc)"
    elif [ -f "$TOUCHPAD_LIBINPUT_QUIRKS" ] && grep -q "BTN_TOOL_DOUBLETAP" "$TOUCHPAD_LIBINPUT_QUIRKS" 2>/dev/null; then
        echo "Touchpad Libinput Quirks: OUTDATED ($TOUCHPAD_LIBINPUT_QUIRKS: masks BTN_TOOL_DOUBLETAP breaking two-finger scroll - run 'touchpad quirks enable')"
    elif [ -f "$TOUCHPAD_LIBINPUT_QUIRKS" ]; then
        echo "Touchpad Libinput Quirks: OUTDATED ($TOUCHPAD_LIBINPUT_QUIRKS: missing resolution calibration - run 'touchpad quirks enable')"
    else
        echo "Touchpad Libinput Quirks: NOT INSTALLED (Default libinput quirks in use)"
    fi
}

# DisplayLink EVDI Primary GPU Hijack & Wayland Stutter Prevention
is_evdi_boot_load_enabled() {
    if [ -f "$EVDI_MODULES_CONF" ] && grep -vqE '^\s*(#|$)' "$EVDI_MODULES_CONF" 2>/dev/null; then
        return 0
    fi
    if [ -f "$EVDI_MODPROBE_CONF" ] && grep -vqE '^\s*(#|$)' "$EVDI_MODPROBE_CONF" 2>/dev/null; then
        return 0
    fi
    return 1
}

is_evdi_running() {
    lsmod 2>/dev/null | grep -q "^evdi "
}

is_evdi_card0_hijacked() {
    if [ -e /sys/class/drm/card0 ]; then
        local card0_target
        card0_target=$(readlink -f /sys/class/drm/card0 2>/dev/null || true)
        if [[ "$card0_target" =~ evdi ]] && [ -e /sys/class/drm/card1 ]; then
            return 0
        fi
    fi
    return 1
}

fix_evdi_boot_hijack() {
    check_root_nolock "touchpad" "evdi" "fix"
    log_info "Configuring DisplayLink EVDI for on-demand loading (prevents compositor stalls)..."
    local changed=0
    if [ -f "$EVDI_MODULES_CONF" ]; then
        rm -f "$EVDI_MODULES_CONF"
        changed=1
        log_success "Removed $EVDI_MODULES_CONF."
    fi
    if [ -f "$EVDI_MODPROBE_CONF" ]; then
        rm -f "$EVDI_MODPROBE_CONF"
        changed=1
        log_success "Removed $EVDI_MODPROBE_CONF (prevents dummy multi-device allocation)."
    fi
    if [ "$changed" -eq 1 ]; then
        if command -v update-initramfs >/dev/null 2>&1; then
            log_info "Updating initramfs to remove early EVDI boot loading..."
            update-initramfs -u >/dev/null 2>&1 || log_warn "update-initramfs encountered a non-fatal warning"
            log_success "Initramfs updated: EVDI will now load on-demand when DisplayLink dock is connected."
        fi
        log_info "Note: If EVDI is currently running in this session, a reboot is recommended to fully release virtual DRM devices."
    else
        log_success "EVDI boot-load configuration is already disabled (on-demand mode active)."
    fi
}

restore_evdi_boot_hijack() {
    check_root_nolock "touchpad" "evdi" "restore"
    log_info "Restoring DisplayLink EVDI boot-time loading ($EVDI_MODULES_CONF)..."
    mkdir -p "$(dirname "$EVDI_MODULES_CONF")"
    echo "evdi" > "$EVDI_MODULES_CONF"
    chmod 644 "$EVDI_MODULES_CONF"
    if command -v update-initramfs >/dev/null 2>&1; then
        update-initramfs -u >/dev/null 2>&1 || true
    fi
    log_success "Restored $EVDI_MODULES_CONF (EVDI will load on early boot)."
}

toggle_evdi_boot_hijack() {
    check_root_nolock "touchpad" "evdi" "toggle"
    if is_evdi_boot_load_enabled; then
        fix_evdi_boot_hijack
    else
        restore_evdi_boot_hijack
    fi
}

show_evdi_status() {
    local boot_state="ON-DEMAND (Safe: GPU owns card0)"
    if is_evdi_boot_load_enabled; then
        boot_state="BOOT-TIME (Conflict: EVDI configured to load at boot)"
    fi
    local live_state="Inactive (Hardware GPU is primary)"
    if is_evdi_running; then
        local count
        count=$(ls -d /sys/devices/platform/evdi.* 2>/dev/null | wc -l)
        if is_evdi_card0_hijacked; then
            live_state="HIJACKED (EVDI owns card0; Wayland dmabuf texture stalls likely; reboot needed after fix)"
        else
            live_state="ACTIVE ($count virtual DRM nodes open; Wayland compositor atomic sync stalls possible)"
        fi
    fi
    echo "DisplayLink EVDI Load: $boot_state"
    echo "DRM EVDI Device State: $live_state"
}

status_get_touchpad_dwt() {
    local val
    val=$(get_user_gsettings get org.gnome.desktop.peripherals.touchpad disable-while-typing 2>/dev/null | tr -d "'")
    if [ "$val" = "false" ]; then
        echo "DISABLED (Zero typing lockout)"
    else
        echo "ENABLED (500ms keyboard pause)"
    fi
}

show_touchpad_dwt_status() {
    local status
    status=$(status_get_touchpad_dwt)
    echo "Touchpad Disable-While-Typing: $status"
}

enable_touchpad_dwt() {
    log_info "Enabling GNOME Touchpad Disable-While-Typing (500ms lockout on keystroke)..."
    run_user_gsettings set org.gnome.desktop.peripherals.touchpad disable-while-typing true
    log_success "Touchpad Disable-While-Typing ENABLED."
}

disable_touchpad_dwt() {
    log_info "Disabling GNOME Touchpad Disable-While-Typing (prevents momentary freeze when typing/resting hands)..."
    run_user_gsettings set org.gnome.desktop.peripherals.touchpad disable-while-typing false
    log_success "Touchpad Disable-While-Typing DISABLED (responsive at all times)."
}

toggle_touchpad_dwt() {
    local val
    val=$(get_user_gsettings get org.gnome.desktop.peripherals.touchpad disable-while-typing 2>/dev/null | tr -d "'")
    if [ "$val" = "false" ]; then
        enable_touchpad_dwt
    else
        disable_touchpad_dwt
    fi
}

status_get_touchpad_tap_drag() {
    local val lock_val
    val=$(get_user_gsettings get org.gnome.desktop.peripherals.touchpad tap-and-drag 2>/dev/null | tr -d "'")
    lock_val=$(get_user_gsettings get org.gnome.desktop.peripherals.touchpad tap-and-drag-lock 2>/dev/null | tr -d "'")
    if [ "$val" = "false" ]; then
        echo "DISABLED (Instant touch response - zero disambiguation delay)"
    elif [ "$lock_val" = "true" ]; then
        echo "ENABLED with Drag Lock (Double-tap drag active, sticky drag release delay)"
    else
        echo "ENABLED (Double-tap drag active, instant finger release)"
    fi
}

show_touchpad_tap_drag_status() {
    local status
    status=$(status_get_touchpad_tap_drag)
    echo "Touchpad Tap-and-Drag: $status"
}

enable_touchpad_tap_drag() {
    log_info "Enabling GNOME Touchpad Tap-and-Drag (allows double-tap dragging at the cost of initial touch latency)..."
    run_user_gsettings set org.gnome.desktop.peripherals.touchpad tap-and-drag true
    log_success "Touchpad Tap-and-Drag ENABLED."
}

disable_touchpad_tap_drag() {
    log_info "Disabling GNOME Touchpad Tap-and-Drag (eliminates initial touch hesitation/delay)..."
    run_user_gsettings set org.gnome.desktop.peripherals.touchpad tap-and-drag false
    run_user_gsettings set org.gnome.desktop.peripherals.touchpad tap-and-drag-lock false
    log_success "Touchpad Tap-and-Drag DISABLED (instant initial touch response)."
}

toggle_touchpad_tap_drag() {
    local val
    val=$(get_user_gsettings get org.gnome.desktop.peripherals.touchpad tap-and-drag 2>/dev/null | tr -d "'")
    if [ "$val" = "false" ]; then
        enable_touchpad_tap_drag
    else
        disable_touchpad_tap_drag
    fi
}

status_get_touchpad_accel_profile() {
    local val
    val=$(get_user_gsettings get org.gnome.desktop.peripherals.touchpad accel-profile 2>/dev/null | tr -d "'")
    if [ "$val" = "flat" ]; then
        echo "FLAT (1:1 linear tracking - zero low-speed deadband)"
    elif [ "$val" = "adaptive" ]; then
        echo "ADAPTIVE (Dynamic acceleration curve - low speeds dampened)"
    else
        echo "DEFAULT (Desktop default adaptive profile)"
    fi
}

show_touchpad_accel_profile_status() {
    local status
    status=$(status_get_touchpad_accel_profile)
    echo "Touchpad Acceleration Profile: $status"
}

set_touchpad_accel_profile() {
    local prof="${1:-flat}"
    case "$prof" in
        flat|adaptive|default)
            log_info "Setting GNOME Touchpad acceleration profile to '$prof'..."
            run_user_gsettings set org.gnome.desktop.peripherals.touchpad accel-profile "$prof"
            log_success "Touchpad acceleration profile set to '$prof'."
            ;;
        *)
            log_err "Invalid acceleration profile: '$prof'. Valid profiles: flat, adaptive, default."
            return 1
            ;;
    esac
}

toggle_touchpad_accel_profile() {
    local val
    val=$(get_user_gsettings get org.gnome.desktop.peripherals.touchpad accel-profile 2>/dev/null | tr -d "'")
    if [ "$val" = "flat" ]; then
        set_touchpad_accel_profile "default"
    else
        set_touchpad_accel_profile "flat"
    fi
}

is_touchpad_acpi_100khz_active() {
    [ -f "$TOUCHPAD_ACPI_OVERRIDE" ] && [ -f "$TOUCHPAD_ACPI_GRUB" ] && grep -q "GRUB_EARLY_INITRD_LINUX_CUSTOM.*acpi_override" "$TOUCHPAD_ACPI_GRUB" 2>/dev/null
}

status_get_touchpad_acpi_100khz() {
    if is_touchpad_acpi_100khz_active; then
        echo "ACTIVE (100 kHz forced via early initrd ACPI table upgrade)"
    elif [ -f "/sys/firmware/acpi/tables/DSDT" ]; then
        echo "DEFAULT (400 kHz Fast Mode - unpatched kernel ACPI DSDT)"
    else
        echo "Not Configured / Unknown"
    fi
}

show_touchpad_acpi_status() {
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}     ELAN I2C Bus Frequency & ACPI Override Status${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo "  State       : $(status_get_touchpad_acpi_100khz)"
    echo "  Override Img: $TOUCHPAD_ACPI_OVERRIDE"
    echo "  GRUB Drop-in: $TOUCHPAD_ACPI_GRUB"
    if is_touchpad_acpi_100khz_active; then
        echo -e "  ${GREEN}[✓] I2C bus clamped to 100 kHz: eliminates ELAN firmware noise suppression lag.${NC}"
    else
        echo -e "  ${YELLOW}[!] Running at 400 kHz: susceptible to sporadic firmware lag on ASUS/AMD laptops.${NC}"
        echo -e "  ${YELLOW}[!] Run 'sudo $0 touchpad speed 100khz' or 'fix-stutter' to apply 100 kHz override.${NC}"
    fi
    echo -e "${CYAN}========================================================${NC}"
}

apply_touchpad_acpi_100khz() {
    check_root_nolock "touchpad" "speed" "100khz"
    log_info "Generating ACPI DSDT 100 kHz speed override for ELAN touchpad..."

    if [ ! -r "/sys/firmware/acpi/tables/DSDT" ]; then
        log_warn "Cannot read /sys/firmware/acpi/tables/DSDT. ACPI sysfs interface unavailable."
        return 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        log_warn "Python 3 is required to patch the ACPI DSDT table."
        return 1
    fi

    if ! command -v cpio >/dev/null 2>&1; then
        log_warn "cpio is required to package the early initrd ACPI override."
        return 1
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/acpi_dsdt_XXXXXX) || { log_err "Failed to create temp directory"; return 1; }
    local target_aml="$tmp_dir/kernel/firmware/acpi/dsdt.aml"

    local py_res=0
    python3 - "$tmp_dir" << 'PYEOF' || py_res=$?
import sys, os

tmp_dir = sys.argv[1]
dsdt_path = "/sys/firmware/acpi/tables/DSDT"
out_path = os.path.join(tmp_dir, "kernel", "firmware", "acpi", "dsdt.aml")

try:
    with open(dsdt_path, "rb") as f:
        data = bytearray(f.read())
except Exception as e:
    sys.exit(f"Error opening DSDT: {e}")

if len(data) < 36 or data[:4] != b"DSDT":
    sys.exit("Error: Invalid DSDT table header")

target_hids = [b"ELAN1300", b"ELAN0678", b"ELAN06FA", b"DELL0A86", b"DLL0945"]
found_hid = None
hid_pos = -1
for hid in target_hids:
    pos = data.find(hid)
    if pos != -1:
        found_hid = hid
        hid_pos = pos
        break

if not found_hid:
    sys.exit("Notice: No affected ELAN/I2C touchpad HID found in DSDT")

# 400 kHz connection speed: 0x00061A80 (little endian: 80 1a 06 00)
# 100 kHz connection speed: 0x000186A0 (little endian: a0 86 01 00)
k400 = b"\x80\x1a\x06\x00"
k100 = b"\xa0\x86\x01\x00"

window_start = max(0, hid_pos - 2048)
window_end = min(len(data), hid_pos + 2048)
window = data[window_start:window_end]

rel_pos = window.find(k400)
if rel_pos == -1:
    if k100 in window:
        pass
    else:
        rel_pos = data.find(k400)
        if rel_pos != -1:
            data[rel_pos:rel_pos+4] = k100
else:
    abs_pos = window_start + rel_pos
    data[abs_pos:abs_pos+4] = k100

# Recalculate ACPI checksum at offset 9
data[9] = 0
checksum = (256 - (sum(data) % 256)) % 256
data[9] = checksum

os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "wb") as f:
    f.write(data)
PYEOF

    if [ "$py_res" -ne 0 ]; then
        rm -rf "$tmp_dir"
        log_warn "Could not patch DSDT for 100 kHz override (device may not use 400 kHz or DSDT parsing failed)."
        return 1
    fi

    if [ ! -f "$target_aml" ]; then
        rm -rf "$tmp_dir"
        log_err "Failed to produce patched dsdt.aml."
        return 1
    fi

    # Package into early CPIO archive
    mkdir -p "$(dirname "$TOUCHPAD_ACPI_OVERRIDE")"
    (
        cd "$tmp_dir" && find kernel -print0 | cpio --null -o -H newc > "$TOUCHPAD_ACPI_OVERRIDE" 2>/dev/null
    )
    chmod 644 "$TOUCHPAD_ACPI_OVERRIDE" 2>/dev/null || true
    rm -rf "$tmp_dir"

    if [ ! -s "$TOUCHPAD_ACPI_OVERRIDE" ]; then
        log_err "Failed to generate $TOUCHPAD_ACPI_OVERRIDE"
        return 1
    fi

    # Configure GRUB early initrd drop-in
    mkdir -p "$(dirname "$TOUCHPAD_ACPI_GRUB")"
    cat << 'EOF' > "$TOUCHPAD_ACPI_GRUB"
# Installed by laptop-linux-optimiser: force ELAN I2C bus to 100 kHz via early initrd ACPI upgrade
GRUB_EARLY_INITRD_LINUX_CUSTOM="acpi_override"
EOF
    chmod 644 "$TOUCHPAD_ACPI_GRUB" 2>/dev/null || true

    log_success "Created early ACPI initrd override at $TOUCHPAD_ACPI_OVERRIDE."
    log_info "Updating bootloader configuration..."
    if command -v update-grub >/dev/null 2>&1; then
        update-grub 2>/dev/null || true
    fi
    log_success "Configured bootloader to load $TOUCHPAD_ACPI_OVERRIDE early at boot."
    return 0
}

remove_touchpad_acpi_100khz() {
    check_root_nolock "touchpad" "speed" "400khz"
    log_info "Removing ACPI DSDT 100 kHz speed override..."
    rm -f "$TOUCHPAD_ACPI_OVERRIDE"
    rm -f "$TOUCHPAD_ACPI_GRUB"
    if command -v update-grub >/dev/null 2>&1; then
        update-grub 2>/dev/null || true
    fi
    log_success "Removed ACPI 100 kHz override and updated bootloader."
    return 0
}

toggle_touchpad_acpi_100khz() {
    if is_touchpad_acpi_100khz_active; then
        remove_touchpad_acpi_100khz
    else
        apply_touchpad_acpi_100khz
    fi
}

tune_gnome_touchpad() {
    local target_user="${SUDO_USER:-$USER}"
    log_info "Configuring optimal GNOME touchpad gestures & responsiveness for $target_user..."
    run_user_gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
    run_user_gsettings set org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled true
    run_user_gsettings set org.gnome.desktop.peripherals.touchpad click-method 'default'
    run_user_gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true
    run_user_gsettings set org.gnome.desktop.peripherals.touchpad disable-while-typing true
    run_user_gsettings set org.gnome.desktop.peripherals.touchpad tap-and-drag true
    run_user_gsettings set org.gnome.desktop.peripherals.touchpad tap-and-drag-lock false
    run_user_gsettings set org.gnome.desktop.peripherals.touchpad accel-profile 'flat'
    run_user_gsettings set org.gnome.desktop.peripherals.touchpad speed 0.25
    log_success "GNOME touchpad settings optimized (tap-to-click, two-finger scroll, natural scroll, button areas preserved, palm rejection active, flat 1:1 acceleration, speed 0.25)."
}

smart_touchpad_autotune() {
    check_root "touchpad" "auto"
    log_info "Analyzing hardware environment and applying smart touchpad tuning..."

    local target_user="${SUDO_USER:-$USER}"

    # 1. Hardware Detection & Verification
    local elan_list ctrl_list
    mapfile -t elan_list < <(touchpad_elan_devs)
    mapfile -t ctrl_list < <(touchpad_ctrl_devs)

    if [ "${#elan_list[@]}" -eq 0 ] && [ "${#ctrl_list[@]}" -eq 0 ]; then
        log_warn "No ELAN or AMD DesignWare I2C touchpad detected. Applying standard desktop optimizations only."
    else
        log_success "Detected hardware: ${#elan_list[@]} ELAN touch device(s), ${#ctrl_list[@]} I2C host controller(s)."
    fi

    # 2. DisplayLink EVDI Conflict Check
    if is_evdi_boot_load_enabled || is_evdi_running; then
        log_info "DisplayLink EVDI driver detected. Enforcing on-demand mode to prevent Wayland compositor stalls..."
        fix_evdi_boot_hijack
    else
        log_success "DisplayLink EVDI safe (no card0 compositor stalls)."
    fi

    # 3. Host Controller & Bus Power Stability (Locks host controller awake to prevent idle sleep dropouts)
    log_info "Securing I2C host controller power management against idle sleep drops..."
    apply_touchpad_runtime
    mkdir -p "$(dirname "$TOUCHPAD_UDEV_RULE")" "$(dirname "$TOUCHPAD_SLEEP_HOOK")"
    cat << 'EOF' > "$TOUCHPAD_UDEV_RULE"
# ELAN I2C touchpad on AMD APUs: keep the DesignWare host controller out of
# runtime suspend. Suspending it loses touch input for a second or two.
ACTION!="remove", SUBSYSTEM=="platform", DRIVER=="i2c_designware", TEST=="power/control", ATTR{power/control}="on"
ACTION!="remove", SUBSYSTEM=="platform", KERNEL=="AMDI0010:*", TEST=="power/control", ATTR{power/control}="on"
ACTION!="remove", SUBSYSTEM=="i2c", ATTR{name}=="ELAN*", TEST=="power/control", ATTR{power/control}="on"
ACTION!="remove", SUBSYSTEM=="pci", ATTR{class}=="0x0c80*", TEST=="power/control", ATTR{power/control}="on"
EOF
    chmod 644 "$TOUCHPAD_UDEV_RULE" 2>/dev/null || true

    cat << 'EOF' > "$TOUCHPAD_SLEEP_HOOK"
#!/bin/sh
# Re-apply ELAN I2C power settings after resume (installed by laptop-linux-optimiser)
[ "$1" = post ] || exit 0
for d in /sys/bus/platform/drivers/i2c_designware/* /sys/devices/platform/AMDI0010:*; do
    [ -w "$d/power/control" ] && echo on > "$d/power/control" 2>/dev/null
done
for d in /sys/bus/i2c/devices/*; do
    [ -r "$d/name" ] || continue
    case "$(cat "$d/name" 2>/dev/null)" in
        ELAN*) [ -w "$d/power/control" ] && [ "$(cat "$d/power/runtime_status" 2>/dev/null)" != "unsupported" ] && echo on > "$d/power/control" 2>/dev/null ;;
    esac
done
exit 0
EOF
    chmod 755 "$TOUCHPAD_SLEEP_HOOK" 2>/dev/null || true
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --subsystem-match=platform --subsystem-match=i2c 2>/dev/null || true

    # 4. Libinput Hardware Quirks Sanitization
    if [ -f "$TOUCHPAD_LIBINPUT_QUIRKS" ]; then
        if grep -q "BTN_TOOL_DOUBLETAP" "$TOUCHPAD_LIBINPUT_QUIRKS" 2>/dev/null; then
            log_info "Removing obsolete BTN_TOOL_DOUBLETAP masking from libinput quirks..."
            apply_touchpad_quirks
        fi
    fi

    # 5. GNOME Desktop Fluidity & Gesture Optimization (Safe Non-Destructive Defaults)
    tune_gnome_touchpad

    log_success "Smart Touchpad Auto-Tune complete! System optimized safely for $target_user."
}

reset_gnome_touchpad() {
    local target_user="${SUDO_USER:-$USER}"
    log_info "Resetting GNOME touchpad settings to desktop defaults for $target_user..."
    run_user_gsettings reset-recursively org.gnome.desktop.peripherals.touchpad 2>/dev/null || true
    log_success "GNOME touchpad settings reset to OS defaults."
}

fix_touchpad_stutter() {
    check_root "touchpad" "fix-stutter"
    log_info "Applying Comprehensive Touchpad Stutter & Latency Fix..."

    # 1. Disable EVDI boot-time load & dummy multi-head allocation to prevent Wayland compositor stalls
    if is_evdi_boot_load_enabled || is_evdi_running; then
        fix_evdi_boot_hijack
    else
        log_success "DisplayLink EVDI already configured for on-demand loading (no card0 conflict)."
    fi

    # 2. Ensure libinput hardware quirks are installed and sanitized
    if [ ! -f "$TOUCHPAD_LIBINPUT_QUIRKS" ]; then
        log_info "Installing calibrated libinput hardware quirks..."
        apply_touchpad_quirks
    elif ! touchpad_has_pressure && grep -q "AttrPressureRange" "$TOUCHPAD_LIBINPUT_QUIRKS" 2>/dev/null; then
        log_info "Sanitizing libinput quirks (removing phantom pressure thresholds on zero-pressure PTP device)..."
        apply_touchpad_quirks
    elif grep -q "BTN_TOOL_DOUBLETAP" "$TOUCHPAD_LIBINPUT_QUIRKS" 2>/dev/null; then
        log_info "Sanitizing libinput quirks (removing BTN_TOOL_DOUBLETAP masking to restore two-finger scrolling)..."
        apply_touchpad_quirks
    elif ! is_touchpad_quirks_installed; then
        log_info "Updating libinput quirks with calibrated resolution hint..."
        apply_touchpad_quirks
    fi

    # 3. Ensure runtime PM is active and persistent udev rule + sleep hook are installed
    apply_touchpad_runtime
    if [ ! -f "$TOUCHPAD_UDEV_RULE" ] || [ ! -f "$TOUCHPAD_SLEEP_HOOK" ]; then
        log_info "Installing persistent udev rule and post-resume sleep hook..."
        mkdir -p "$(dirname "$TOUCHPAD_UDEV_RULE")" "$(dirname "$TOUCHPAD_SLEEP_HOOK")"
        cat << 'EOF' > "$TOUCHPAD_UDEV_RULE"
# ELAN I2C touchpad on AMD APUs: keep the DesignWare host controller out of
# runtime suspend. Suspending it loses touch input for a second or two.
ACTION!="remove", SUBSYSTEM=="platform", DRIVER=="i2c_designware", TEST=="power/control", ATTR{power/control}="on"
ACTION!="remove", SUBSYSTEM=="platform", KERNEL=="AMDI0010:*", TEST=="power/control", ATTR{power/control}="on"
ACTION!="remove", SUBSYSTEM=="i2c", ATTR{name}=="ELAN*", TEST=="power/control", ATTR{power/control}="on"
ACTION!="remove", SUBSYSTEM=="pci", ATTR{class}=="0x0c80*", TEST=="power/control", ATTR{power/control}="on"
EOF
        chmod 644 "$TOUCHPAD_UDEV_RULE" 2>/dev/null || true

        cat << 'EOF' > "$TOUCHPAD_SLEEP_HOOK"
#!/bin/sh
# Re-apply ELAN I2C power settings after resume (installed by laptop-linux-optimiser)
[ "$1" = post ] || exit 0
for d in /sys/bus/platform/drivers/i2c_designware/* /sys/devices/platform/AMDI0010:*; do
    [ -w "$d/power/control" ] && echo on > "$d/power/control" 2>/dev/null
done
for d in /sys/bus/i2c/devices/*; do
    [ -r "$d/name" ] || continue
    case "$(cat "$d/name" 2>/dev/null)" in
        ELAN*) [ -w "$d/power/control" ] && [ "$(cat "$d/power/runtime_status" 2>/dev/null)" != "unsupported" ] && echo on > "$d/power/control" 2>/dev/null ;;
    esac
done
exit 0
EOF
        chmod 755 "$TOUCHPAD_SLEEP_HOOK" 2>/dev/null || true
        udevadm control --reload-rules 2>/dev/null || true
        udevadm trigger --subsystem-match=platform --subsystem-match=i2c 2>/dev/null || true
    fi

    # 4. Ensure C-state cap is active
    if ! is_touchpad_cstate_configured && ! grep -q "processor.max_cstate=2" /proc/cmdline; then
        apply_touchpad_cstate_cap
    fi

    # 5. Ensure GPU PSR fix is active
    local param
    param=$(detect_gpu_psr_param)
    if [ -n "$param" ] && ! is_touchpad_psr_configured && ! grep -q "$param" /proc/cmdline; then
        apply_touchpad_psr_fix
    fi

    # 6. Configure GNOME gestures & tap-to-click
    tune_gnome_touchpad

    # 7. Apply 100 kHz I2C bus speed ACPI table upgrade for ELAN touchpads on pre-7.3 kernels
    local k_major k_minor
    k_major=$(uname -r | cut -d. -f1)
    k_minor=$(uname -r | cut -d. -f2)
    if [ "$k_major" -lt 7 ] || { [ "$k_major" -eq 7 ] && [ "$k_minor" -lt 3 ]; }; then
        if [ -r "/sys/firmware/acpi/tables/DSDT" ]; then
            if ! is_touchpad_acpi_100khz_active; then
                log_info "Kernel $(uname -r) lacks ELAN1300 100 kHz quirk (merged upstream in Linux 7.3). Applying ACPI DSDT upgrade..."
                apply_touchpad_acpi_100khz || true
            else
                log_success "ACPI DSDT 100 kHz override already active ($TOUCHPAD_ACPI_OVERRIDE)."
            fi
        fi
    fi

    log_success "Touchpad stutter fix successfully applied."
    if is_evdi_card0_hijacked; then
        log_warn "EVDI currently holds card0. Please reboot so your AMD/Intel GPU reclaims primary card0."
    fi
}

touchpad_set_power() { # <sysfs path> <on|auto>
    [ -e "$1" ] || return 0
    if [ "$(cat "$(dirname "$1")/runtime_status" 2>/dev/null)" = unsupported ]; then
        return 0
    fi
    if printf '%s\n' "$2" > "$1" 2>/dev/null; then
        echo "      $1 -> $2"
    else
        log_warn "Could not write $2 to $1 (read-only or unsupported)"
    fi
}

verify_touchpad_device() {
    local p
    for p in /sys/bus/i2c/devices/*ELAN*/[0-9]*/input/input*/name; do
        if [ -r "$p" ] && grep -qi touchpad "$p"; then
            log_success "Touchpad input device present: $(<"$p")"
            return 0
        fi
    done
    log_warn "No active touchpad input device found under /sys/bus/i2c/devices."
    return 1
}

apply_touchpad_runtime() {
    check_root_nolock "touchpad" "runtime"
    log_info "Keeping AMD I2C DesignWare controllers and ELAN client out of runtime suspend..."
    local d
    local elan_list ctrl_list
    mapfile -t elan_list < <(touchpad_elan_devs)
    mapfile -t ctrl_list < <(touchpad_ctrl_devs)

    for d in "${ctrl_list[@]}" "${elan_list[@]}"; do
        touchpad_set_power "$d/power/control" on
    done
    log_success "Runtime power settings applied (I2C controllers kept active)."
}

install_touchpad_permanent() {
    check_root "touchpad" "install"
    log_info "Installing comprehensive ELAN touchpad responsiveness & power management suite..."

    # 1. Runtime settings
    apply_touchpad_runtime

    # 2. Udev rule
    log_info "Installing persistent udev rule ($TOUCHPAD_UDEV_RULE)..."
    mkdir -p "$(dirname "$TOUCHPAD_UDEV_RULE")"
    cat << 'EOF' > "$TOUCHPAD_UDEV_RULE"
# ELAN I2C touchpad on AMD APUs: keep the DesignWare host controller out of
# runtime suspend. Suspending it loses touch input for a second or two.
ACTION!="remove", SUBSYSTEM=="platform", DRIVER=="i2c_designware", TEST=="power/control", ATTR{power/control}="on"
ACTION!="remove", SUBSYSTEM=="platform", KERNEL=="AMDI0010:*", TEST=="power/control", ATTR{power/control}="on"
ACTION!="remove", SUBSYSTEM=="i2c", ATTR{name}=="ELAN*", TEST=="power/control", ATTR{power/control}="on"
# Some AMD laptops expose the I2C controller as a PCI device instead.
ACTION!="remove", SUBSYSTEM=="pci", ATTR{class}=="0x0c80*", TEST=="power/control", ATTR{power/control}="on"
EOF
    chmod 644 "$TOUCHPAD_UDEV_RULE" 2>/dev/null || true

    # 3. Post-resume sleep hook
    log_info "Installing post-resume sleep hook ($TOUCHPAD_SLEEP_HOOK)..."
    mkdir -p "$(dirname "$TOUCHPAD_SLEEP_HOOK")"
    cat << 'EOF' > "$TOUCHPAD_SLEEP_HOOK"
#!/bin/sh
# Re-apply ELAN I2C power settings after resume (installed by laptop-linux-optimiser)
[ "$1" = post ] || exit 0
for d in /sys/bus/platform/drivers/i2c_designware/* /sys/devices/platform/AMDI0010:*; do
    [ -w "$d/power/control" ] && echo on > "$d/power/control" 2>/dev/null
done
for d in /sys/bus/i2c/devices/*; do
    [ -r "$d/name" ] || continue
    case "$(cat "$d/name" 2>/dev/null)" in
        ELAN*) [ -w "$d/power/control" ] && [ "$(cat "$d/power/runtime_status" 2>/dev/null)" != "unsupported" ] && echo on > "$d/power/control" 2>/dev/null ;;
    esac
done
exit 0
EOF
    chmod 755 "$TOUCHPAD_SLEEP_HOOK" 2>/dev/null || true

    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --subsystem-match=platform --subsystem-match=i2c 2>/dev/null || true

    # 4. Libinput Hardware Quirks
    apply_touchpad_quirks

    # 5. Prevent DisplayLink EVDI primary card0 hijacking / Wayland compositor stutter
    if is_evdi_boot_load_enabled; then
        fix_evdi_boot_hijack
    fi

    # 6. Diagnostic Binary Installation
    if [ -f "${SCRIPT_DIR}/diagnose-elan-irq.sh" ]; then
        mkdir -p "$(dirname "$TOUCHPAD_DIAG_CANONICAL")"
        cp -f "${SCRIPT_DIR}/diagnose-elan-irq.sh" "$TOUCHPAD_DIAG_CANONICAL" 2>/dev/null || true
        chmod 755 "$TOUCHPAD_DIAG_CANONICAL" 2>/dev/null || true
        log_success "Installed live diagnostic utility to $TOUCHPAD_DIAG_CANONICAL."
    fi

    # 7. Obsolete GRUB cleanup
    if [ -f "$TOUCHPAD_LEGACY_GRUB" ]; then
        log_info "Removing obsolete polling GRUB drop-in $TOUCHPAD_LEGACY_GRUB..."
        rm -f "$TOUCHPAD_LEGACY_GRUB"
        if command -v update-grub >/dev/null 2>&1 && [ -d /boot/grub ]; then
            update-grub >/dev/null 2>&1 || true
        fi
    fi

    # 8. Bootloader C-State Cap (processor.max_cstate=2)
    apply_touchpad_cstate_cap

    # 9. Bootloader GPU Panel Self Refresh (PSR) Micro-Stutter Fix
    apply_touchpad_psr_fix

    # 10. GNOME Touchpad Gestures & Peripheral Tuning
    tune_gnome_touchpad

    # 11. I2C Bus Frequency ACPI DSDT Upgrade (Clamps 400 kHz to 100 kHz for ELAN touchpads on pre-7.3 kernels)
    local k_major k_minor
    k_major=$(uname -r | cut -d. -f1)
    k_minor=$(uname -r | cut -d. -f2)
    if [ "$k_major" -lt 7 ] || { [ "$k_major" -eq 7 ] && [ "$k_minor" -lt 3 ]; }; then
        if [ -r "/sys/firmware/acpi/tables/DSDT" ]; then
            apply_touchpad_acpi_100khz || true
        fi
    fi

    log_success "Permanent ELAN Touchpad configuration active (persists across boots and sleep cycles)."
}

revert_touchpad() {
    check_root "touchpad" "revert"
    log_info "Reverting ELAN Touchpad power configuration, quirks, and bootloader caps..."

    remove_touchpad_cstate_cap
    remove_touchpad_psr_fix
    remove_touchpad_quirks
    remove_touchpad_acpi_100khz
    reset_gnome_touchpad

    rm -f "$TOUCHPAD_UDEV_RULE" "$TOUCHPAD_SLEEP_HOOK" "$TOUCHPAD_LEGACY_GRUB"

    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --subsystem-match=platform --subsystem-match=i2c --subsystem-match=input 2>/dev/null || true

    log_info "Restoring default runtime power management for I2C controllers..."
    local d
    local elan_list ctrl_list
    mapfile -t elan_list < <(touchpad_elan_devs)
    mapfile -t ctrl_list < <(touchpad_ctrl_devs)

    for d in "${ctrl_list[@]}" "${elan_list[@]}"; do
        touchpad_set_power "$d/power/control" auto
    done

    log_success "ELAN touchpad configuration reverted to OS defaults."
}

status_get_touchpad() {
    local elan_list ctrl_list
    mapfile -t elan_list < <(touchpad_elan_devs)
    mapfile -t ctrl_list < <(touchpad_ctrl_devs)

    if [ "${#elan_list[@]}" -eq 0 ] && [ "${#ctrl_list[@]}" -eq 0 ]; then
        echo "N/A (No ELAN/AMD I2C)"
        return 0
    fi

    local udev_ok=0 hook_ok=0 ctrl_on=0 cstate_ok=0 psr_ok=0 quirks_ok=0
    [ -f "$TOUCHPAD_UDEV_RULE" ] && udev_ok=1
    [ -f "$TOUCHPAD_SLEEP_HOOK" ] && hook_ok=1
    grep -q "processor.max_cstate=2" /proc/cmdline && cstate_ok=1
    is_touchpad_quirks_installed && quirks_ok=1

    local psr_param
    psr_param=$(detect_gpu_psr_param)
    if [ -n "$psr_param" ] && grep -q "$psr_param" /proc/cmdline; then
        psr_ok=1
    elif [ "$(cat /sys/module/amdgpu/parameters/dcdebugmask 2>/dev/null)" = "1040" ] || [ "$(cat /sys/module/amdgpu/parameters/dcdebugmask 2>/dev/null)" = "16" ]; then
        psr_ok=1
    elif is_touchpad_psr_configured; then
        psr_ok=1
    elif [ -z "$psr_param" ]; then
        psr_ok=1
    fi

    local c
    for c in "${ctrl_list[@]}"; do
        if [ "$(cat "$c/power/control" 2>/dev/null)" = "on" ]; then
            ctrl_on=1
            break
        fi
    done

    if [ "$udev_ok" -eq 1 ] && [ "$ctrl_on" -eq 1 ] && [ "$cstate_ok" -eq 1 ] && [ "$psr_ok" -eq 1 ] && [ "$quirks_ok" -eq 1 ]; then
        echo "OPTIMIZED (PM Awake, C2 Cap, PSR Off, Libinput Quirks)"
    elif [ "$udev_ok" -eq 1 ] && [ "$ctrl_on" -eq 1 ] && [ "$cstate_ok" -eq 1 ]; then
        echo "OPTIMIZED (PM Awake, C2 Cap Active)"
    elif [ "$udev_ok" -eq 1 ] && [ "$ctrl_on" -eq 1 ]; then
        echo "OPTIMIZED (PM Awake, Default C-States)"
    elif [ "$ctrl_on" -eq 1 ]; then
        echo "RUNTIME ONLY (Session Awake)"
    else
        echo "UNOPTIMIZED (Autosuspend Active)"
    fi
}

show_touchpad_cstate_status() {
    local cstate_live="inactive (default C-states)"
    local cstate_pers="absent"
    if grep -q "processor.max_cstate=2" /proc/cmdline; then
        cstate_live="active (processor.max_cstate=2 present)"
    fi
    if is_touchpad_cstate_configured; then
        cstate_pers="configured (persists across boots)"
    fi
    echo "Touchpad C-State Cap: $cstate_live [bootloader: $cstate_pers]"
}

show_touchpad_status() {
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${BOLD}         ELAN I2C Touchpad & AMD Bus Status${NC}"
    echo -e "${CYAN}========================================================${NC}"

    local elan_list ctrl_list
    mapfile -t elan_list < <(touchpad_elan_devs)
    mapfile -t ctrl_list < <(touchpad_ctrl_devs)

    if [ "${#elan_list[@]}" -eq 0 ]; then
        log_warn "No ELAN I2C devices found on the I2C bus."
    fi
    for d in "${elan_list[@]}"; do
        echo "  Device : $d"
        echo "    Driver        : $(basename "$(readlink -f "$d/driver" 2>/dev/null)")"
        echo "    power/control : $(cat "$d/power/control" 2>/dev/null || echo n/a)"
        echo "    runtime_status: $(cat "$d/power/runtime_status" 2>/dev/null || echo n/a)"
    done
    for d in "${ctrl_list[@]}"; do
        echo "  Controller: $d"
        echo "    power/control : $(cat "$d/power/control" 2>/dev/null || echo n/a)"
        echo "    runtime_status: $(cat "$d/power/runtime_status" 2>/dev/null || echo n/a)"
        echo "    suspended_time: $(cat "$d/power/runtime_suspended_time" 2>/dev/null || echo n/a) ms"
        echo "    autosuspend   : $(cat "$d/power/autosuspend_delay_ms" 2>/dev/null || echo n/a) ms"
    done

    echo ""
    echo "  System Environment:"
    echo "    Kernel        : $(uname -r)"
    echo "    Desktop       : ${XDG_CURRENT_DESKTOP:-unknown}${XDG_SESSION_TYPE:+ ($XDG_SESSION_TYPE)}"
    echo "    Bootloader    : $(detect_bootloader_type)"

    local cstate_live="inactive (default C-states)"
    local cstate_pers="absent"
    if grep -q "processor.max_cstate=2" /proc/cmdline; then
        cstate_live="active (processor.max_cstate=2 present)"
    fi
    if is_touchpad_cstate_configured; then
        cstate_pers="configured (persists across boots)"
    fi
    echo "    C-State Cap   : $cstate_live [Bootloader: $cstate_pers]"

    local psr_param
    psr_param=$(detect_gpu_psr_param)
    local psr_live="inactive (default GPU power management)"
    local psr_pers="absent"
    if [ -n "$psr_param" ] && grep -q "$psr_param" /proc/cmdline; then
        psr_live="active ($psr_param present)"
    elif [ "$(cat /sys/module/amdgpu/parameters/dcdebugmask 2>/dev/null)" = "1040" ] || [ "$(cat /sys/module/amdgpu/parameters/dcdebugmask 2>/dev/null)" = "16" ]; then
        psr_live="active (amdgpu dcdebugmask in effect)"
    fi
    if is_touchpad_psr_configured; then
        psr_pers="configured (persists across boots)"
    fi
    echo "    GPU PSR Stutter: $psr_live [Bootloader: $psr_pers]"

    local quirks_state="NOT INSTALLED"
    if is_touchpad_quirks_installed; then
        local q_desc="31x31 resolution (preserves two-finger scrolling)"
        if grep -q "AttrPressureRange" "$TOUCHPAD_LIBINPUT_QUIRKS" 2>/dev/null; then
            if ! touchpad_has_pressure; then
                q_desc="31x31 resolution, 10:8 pressure [WARNING: phantom pressure quirk active on zero-pressure PTP device - run fix-stutter]"
            else
                q_desc="31x31 resolution, 10:8 pressure"
            fi
        fi
        quirks_state="ACTIVE ($TOUCHPAD_LIBINPUT_QUIRKS: $q_desc)"
    elif [ -f "$TOUCHPAD_LIBINPUT_QUIRKS" ] && grep -q "BTN_TOOL_DOUBLETAP" "$TOUCHPAD_LIBINPUT_QUIRKS" 2>/dev/null; then
        quirks_state="OUTDATED ($TOUCHPAD_LIBINPUT_QUIRKS: masks BTN_TOOL_DOUBLETAP breaking two-finger scroll - run 'touchpad quirks enable')"
    elif [ -f "$TOUCHPAD_LIBINPUT_QUIRKS" ]; then
        quirks_state="OUTDATED ($TOUCHPAD_LIBINPUT_QUIRKS: run 'touchpad quirks enable')"
    fi
    echo "    Libinput Quirks: $quirks_state"

    local evdi_boot="ON-DEMAND (Safe: GPU owns card0)"
    if is_evdi_boot_load_enabled; then
        evdi_boot="BOOT-TIME (Conflict: $EVDI_MODULES_CONF loads at boot)"
    fi
    local card0_info="Hardware GPU"
    if is_evdi_card0_hijacked; then
        card0_info="HIJACKED by EVDI (reboot needed after fix)"
    fi
    echo "    DisplayLink EVDI: $evdi_boot [card0: $card0_info]"

    if command -v gsettings >/dev/null 2>&1; then
        local dwt_val click_val tap_drag_val accel_val speed_val
        dwt_val=$(status_get_touchpad_dwt)
        click_val=$(get_user_gsettings get org.gnome.desktop.peripherals.touchpad click-method 2>/dev/null | tr -d "'")
        [ -z "$click_val" ] && click_val="default"
        tap_drag_val=$(status_get_touchpad_tap_drag)
        accel_val=$(status_get_touchpad_accel_profile)
        speed_val=$(get_user_gsettings get org.gnome.desktop.peripherals.touchpad speed 2>/dev/null | tr -d "'")
        [ -z "$speed_val" ] && speed_val="0.0"
        echo "    Typing Lockout: $dwt_val"
        echo "    Click Method  : $click_val"
        echo "    Tap-and-Drag  : $tap_drag_val"
        echo "    Accel Profile : $accel_val"
        echo "    Pointer Speed : $speed_val"
    fi
    echo "    I2C Bus Speed : $(status_get_touchpad_acpi_100khz)"

    echo ""
    echo "  Permanent Configuration:"
    for d in "$TOUCHPAD_UDEV_RULE" "$TOUCHPAD_SLEEP_HOOK" "$TOUCHPAD_LIBINPUT_QUIRKS"; do
        if [ -f "$d" ]; then
            echo -e "    ${GREEN}[+] Installed: $d${NC}"
        else
            echo "        Absent   : $d"
        fi
    done
    if is_evdi_boot_load_enabled; then
        echo -e "    ${YELLOW}[!] Conflict : DisplayLink EVDI boot-load active ($EVDI_MODULES_CONF)${NC}"
    else
        echo -e "    ${GREEN}[+] On-Demand: DisplayLink EVDI on-demand mode active${NC}"
    fi
    if is_touchpad_cstate_configured; then
        echo -e "    ${GREEN}[+] Installed: processor.max_cstate=2 in $(detect_bootloader_type)${NC}"
    else
        echo "        Absent   : processor.max_cstate=2 in bootloader"
    fi
    if is_touchpad_psr_configured; then
        echo -e "    ${GREEN}[+] Installed: $psr_param in $(detect_bootloader_type)${NC}"
    else
        echo "        Absent   : ${psr_param:-GPU PSR parameter} in bootloader"
    fi
    if is_touchpad_acpi_100khz_active; then
        echo -e "    ${GREEN}[+] Installed: $TOUCHPAD_ACPI_OVERRIDE (100 kHz I2C ACPI upgrade)${NC}"
    else
        echo "        Absent   : $TOUCHPAD_ACPI_OVERRIDE (running at 400 kHz)"
    fi
    if [ -x "$TOUCHPAD_DIAG_CANONICAL" ]; then
        echo -e "    ${GREEN}[+] Installed: $TOUCHPAD_DIAG_CANONICAL${NC}"
    fi

    if command -v system76-power >/dev/null 2>&1; then
        local prof
        prof=$(system76-power profile 2>/dev/null | awk -F': ' '/Power Profile/{print $2}' || echo unknown)
        echo "    Power Profile : $prof (system76-power)"
    elif command -v powerprofilesctl >/dev/null 2>&1; then
        local prof
        prof=$(powerprofilesctl get 2>/dev/null || echo unknown)
        echo "    Power Profile : $prof (powerprofilesctl)"
    fi

    verify_touchpad_device || true
    echo -e "${CYAN}========================================================${NC}"
}

run_touchpad_diagnostics() {
    local diag_bin="${SCRIPT_DIR}/diagnose-elan-irq.sh"
    if [ ! -x "$diag_bin" ]; then
        diag_bin="/usr/local/sbin/diagnose-elan-irq.sh"
    fi
    if [ -x "$diag_bin" ]; then
        log_info "Launching live ELAN interrupt & latency diagnostics ($diag_bin)..."
        "$diag_bin" "$@"
    else
        log_err "Diagnostics script not found at $diag_bin."
        return 1
    fi
}

interactive_touchpad_menu() {
    check_root "touchpad" "menu"
    while true; do
        clear 2>/dev/null || true
        local cur_tp
        cur_tp=$(status_get_touchpad)
        local tp_pill
        if [[ "$cur_tp" =~ OPTIMIZED ]]; then
            tp_pill="${GREEN}${BOLD}[ ACTIVE: $cur_tp ]${NC}"
        elif [[ "$cur_tp" =~ RUNTIME ]]; then
            tp_pill="${YELLOW}${BOLD}[ SESSION ONLY: $cur_tp ]${NC}"
        else
            tp_pill="${RED}${BOLD}[ $cur_tp ]${NC}"
        fi

        echo -e "${CYAN}==========================================================================================${NC}"
        echo -e "${BOLD}              Laptop Linux Optimizer — ELAN I2C Touchpad & AMD Bus Manager                ${NC}"
        echo -e "${CYAN}==========================================================================================${NC}"
        echo -e "Touchpad Bus Status : $tp_pill"
        echo ""
        echo "Root Causes Addressed:"
        echo "  • Idle Dropouts   : AMD DesignWare I2C host controller runtime autosuspend (1s timeout)"
        echo "  • Mid-Drag Stalls : AMD Ryzen deep C3 CPU idle state exit latency (capped via processor.max_cstate=2)"
        echo "  • Sluggish Cursor : Uncalibrated libinput resolution/pressure curves (fixed via local-overrides.quirks)"
        echo "  • Wake-Up Stutter : AMD/Intel GPU Panel Self Refresh sleep delay (fixed via dcdebugmask/enable_psr)"
        echo "  • Typing Freezes  : GNOME 500ms Disable-While-Typing lockout (toggleable via DWT)"
        echo "  • Touch Jumps     : Button-area multi-touch disambiguation (eliminated via click-method 'fingers')"
        echo "  • Display Stalls  : Unconnected EVDI/DisplayLink virtual card DRM stalls (fixed via On-Demand mode)"
        echo "  • I2C Bus Jitter  : 400 kHz bus clock noise triggering firmware smoothing (fixed via 100 kHz ACPI upgrade)"
        echo "  • Initial Touch Lag: Tap-and-drag disambiguation delay & adaptive deadband (fixed via tap-drag off / flat)"
        echo ""
        echo "Available Actions:"
        echo -e "  ${BOLD}[1]${NC} Smart Auto-Tune (One-Click Hardware-Aware Optimization)"
        echo -e "  ${BOLD}[2]${NC} View Comprehensive Hardware, Bus & Power Status"
        echo -e "  ${BOLD}[3]${NC} Run Live 120s Interrupt & Freeze Diagnostics (diagnose-elan-irq)"
        echo -e "  ${BOLD}[4]${NC} Revert All Touchpad Settings (restore OS defaults)"
        echo -e "  ${BOLD}[5]${NC} Advanced Manual Tuning (Submenu for granular knobs)"
        echo -e "  ${BOLD}[Q]${NC} Return to Main Menu"
        echo -e "${CYAN}------------------------------------------------------------------------------------------${NC}"
        read -rp "Select an option [1-5, Q]: " tpsel || break

        case "$tpsel" in
            1|auto|smart|install|apply)
                smart_touchpad_autotune
                read -rp "Press Enter to continue..." _
                ;;
            2|[Ss]|status)
                show_touchpad_status
                read -rp "Press Enter to continue..." _
                ;;
            3|[Dd]|diagnose)
                run_touchpad_diagnostics
                read -rp "Press Enter to continue..." _
                ;;
            4|[Rr]|revert|uninstall)
                revert_touchpad
                read -rp "Press Enter to continue..." _
                ;;
            5|advanced|adv|more)
                interactive_touchpad_advanced_menu
                ;;
            [Qq]|exit|"") break ;;
            *)
                log_warn "Invalid selection: '$tpsel'"
                sleep 1
                ;;
        esac
    done
}

interactive_touchpad_advanced_menu() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${CYAN}==========================================================================================${NC}"
        echo -e "${BOLD}              Touchpad Advanced Manual Knobs & Low-Level Overrides                        ${NC}"
        echo -e "${CYAN}==========================================================================================${NC}"
        echo -e "  ${BOLD}[1]${NC} Toggle Acceleration Profile (Flat 1:1 vs Adaptive) [Current: $(status_get_touchpad_accel_profile)]"
        echo -e "  ${BOLD}[2]${NC} Toggle Palm Rejection / Disable-While-Typing [Current: $(status_get_touchpad_dwt)]"
        echo -e "  ${BOLD}[3]${NC} Toggle Tap-and-Drag [Current: $(status_get_touchpad_tap_drag)]"
        echo -e "  ${BOLD}[4]${NC} Toggle Libinput Resolution Quirks (31x31 hint)"
        echo -e "  ${BOLD}[5]${NC} Toggle Bootloader C-State Cap (processor.max_cstate=2)"
        echo -e "  ${BOLD}[6]${NC} Toggle Bootloader GPU PSR Fix (amdgpu/intel wake-up stutter)"
        echo -e "  ${BOLD}[7]${NC} Toggle I2C Bus Clock (100 kHz ACPI table upgrade) [Current: $(status_get_touchpad_acpi_100khz)]"
        echo -e "  ${BOLD}[8]${NC} Toggle DisplayLink EVDI On-Demand Mode"
        echo -e "  ${BOLD}[9]${NC} Apply Runtime PM Fix Only (Current Session)"
        echo -e "  ${BOLD}[B]${NC} Back to Touchpad Menu"
        echo -e "${CYAN}------------------------------------------------------------------------------------------${NC}"
        read -rp "Select an option [1-9, B]: " advsel || break

        case "$advsel" in
            1) toggle_touchpad_accel_profile; read -rp "Press Enter to continue..." _ ;;
            2) toggle_touchpad_dwt; read -rp "Press Enter to continue..." _ ;;
            3) toggle_touchpad_tap_drag; read -rp "Press Enter to continue..." _ ;;
            4) toggle_touchpad_quirks; read -rp "Press Enter to continue..." _ ;;
            5) toggle_touchpad_cstate_cap; read -rp "Press Enter to continue..." _ ;;
            6) toggle_touchpad_psr_fix; read -rp "Press Enter to continue..." _ ;;
            7) toggle_touchpad_acpi_100khz; read -rp "Press Enter to continue..." _ ;;
            8) toggle_evdi_boot_hijack; read -rp "Press Enter to continue..." _ ;;
            9) apply_touchpad_runtime; read -rp "Press Enter to continue..." _ ;;
            [Bb]|[Qq]|"") break ;;
            *) log_warn "Invalid selection: '$advsel'"; sleep 1 ;;
        esac
    done
}

whiptail_touchpad_menu() {
    local tui_cmd="$1"
    while true; do
        local cur_tp
        cur_tp=$(status_get_touchpad)
        local tchoice
        tchoice=$($tui_cmd --title "ELAN I2C Touchpad & AMD Bus Manager" \
            --menu "Current State: $cur_tp\nSelect touchpad action:" 20 78 8 \
            "1" "Smart Auto-Tune (One-Click Hardware-Aware Optimization)" \
            "2" "View Detailed Hardware & Bus Status" \
            "3" "Run Live 120s Interrupt & Freeze Diagnostics" \
            "4" "Revert All Touchpad Changes to OS Defaults" \
            "5" "Advanced Manual Controls (Granular low-level knobs)" \
            "Q" "Return to Main Menu" \
            3>&1 1>&2 2>&3 || echo "Q")

        case "$tchoice" in
            1) run_whiptail_action smart_touchpad_autotune ;;
            2) show_touchpad_status; read -rp "Press Enter to return..." _ ;;
            3) run_whiptail_action run_touchpad_diagnostics ;;
            4) run_whiptail_action revert_touchpad ;;
            5) whiptail_touchpad_advanced_menu "$tui_cmd" ;;
            Q|"") break ;;
        esac
    done
}

whiptail_touchpad_advanced_menu() {
    local tui_cmd="$1"
    while true; do
        local achoice
        achoice=$($tui_cmd --title "Touchpad Advanced Manual Knobs" \
            --menu "Select granular setting to toggle:" 22 78 10 \
            "1" "Toggle Acceleration Profile (Flat vs Adaptive)" \
            "2" "Toggle Palm Rejection (Disable-While-Typing)" \
            "3" "Toggle Tap-and-Drag Delay" \
            "4" "Toggle Libinput Resolution Quirks (31x31 hint)" \
            "5" "Toggle Bootloader C-State Cap (max_cstate=2)" \
            "6" "Toggle Bootloader GPU PSR Fix (wake-up stutter)" \
            "7" "Toggle I2C Bus Speed (100 kHz ACPI upgrade)" \
            "8" "Toggle DisplayLink EVDI On-Demand Mode" \
            "9" "Apply Runtime PM Only (Current Session)" \
            "B" "Back to Touchpad Menu" \
            3>&1 1>&2 2>&3 || echo "B")

        case "$achoice" in
            1) run_whiptail_action toggle_touchpad_accel_profile ;;
            2) run_whiptail_action toggle_touchpad_dwt ;;
            3) run_whiptail_action toggle_touchpad_tap_drag ;;
            4) run_whiptail_action toggle_touchpad_quirks ;;
            5) run_whiptail_action toggle_touchpad_cstate_cap ;;
            6) run_whiptail_action toggle_touchpad_psr_fix ;;
            7) run_whiptail_action toggle_touchpad_acpi_100khz ;;
            8) run_whiptail_action toggle_evdi_boot_hijack ;;
            9) run_whiptail_action apply_touchpad_runtime ;;
            B|"") break ;;
        esac
    done
}

# ==============================================================================
# MODULE 12: Hardware Acceleration Drivers, Media Codecs & Font Packs
# Optimized for Ubuntu LTS, AMD APUs (Ryzen 5 5500U / Radeon Vega 7), and Mesa
# ==============================================================================

# Core 64-bit AMD/Mesa graphics and video acceleration packages
MEDIA_DRIVER_PKGS=(
    "mesa-vulkan-drivers"
    "vulkan-tools"
    "libvulkan1"
    "mesa-va-drivers"
    "mesa-vdpau-drivers"
    "libva2"
    "vainfo"
    "vdpauinfo"
)

# Core multimedia decoders and GStreamer framework plugins
MEDIA_CODEC_PKGS=(
    "ubuntu-restricted-extras"
    "ffmpeg"
    "gstreamer1.0-plugins-base"
    "gstreamer1.0-plugins-good"
    "gstreamer1.0-plugins-bad"
    "gstreamer1.0-plugins-ugly"
    "gstreamer1.0-libav"
    "gstreamer1.0-vaapi"
)

# Typography & compatibility font packs
MEDIA_FONT_PKGS=(
    "ttf-mscorefonts-installer"
    "fonts-crosextra-carlito"
    "fonts-crosextra-caladea"
    "fonts-liberation2"
    "fonts-noto-core"
    "fonts-noto-cjk"
    "fonts-noto-color-emoji"
    "fonts-dejavu"
    "fonts-firacode"
)

# Optional 32-bit multiarch packages for Steam / Wine Proton gaming
MEDIA_32BIT_PKGS=(
    "mesa-vulkan-drivers:i386"
    "mesa-va-drivers:i386"
    "mesa-vdpau-drivers:i386"
    "libvulkan1:i386"
)

detect_gpu_hardware() {
    local gpu=""
    if command -v lspci &>/dev/null; then
        gpu=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | head -n 1 | sed -E 's/^[0-9a-f:.]* [^:]+: //' || true)
        [ -z "$gpu" ] && gpu=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | head -n 1 || true)
    fi
    if [ -z "$gpu" ] && [ -d "/sys/class/drm/card0/device" ]; then
        local vendor device
        vendor=$(cat /sys/class/drm/card0/device/vendor 2>/dev/null || true)
        device=$(cat /sys/class/drm/card0/device/device 2>/dev/null || true)
        gpu="PCI Device [$vendor:$device]"
    fi
    echo "${gpu:-Generic Display Controller}"
}

status_get_media_drivers() {
    local has_va=0 has_vulkan=0 has_codecs=0 has_fonts=0
    { dpkg -s mesa-va-drivers &>/dev/null || dpkg -s mesa-libgallium &>/dev/null; } && has_va=1
    dpkg -s mesa-vulkan-drivers &>/dev/null && has_vulkan=1
    dpkg -s ubuntu-restricted-extras &>/dev/null && has_codecs=1
    dpkg -s fonts-crosextra-carlito &>/dev/null && has_fonts=1

    if [ "$has_va" -eq 1 ] && [ "$has_vulkan" -eq 1 ] && [ "$has_codecs" -eq 1 ] && [ "$has_fonts" -eq 1 ]; then
        echo "INSTALLED (VA-API / Vulkan / Codecs / Fonts)"
    elif [ "$has_va" -eq 1 ] || [ "$has_vulkan" -eq 1 ] || [ "$has_codecs" -eq 1 ]; then
        echo "PARTIAL (Components missing)"
    else
        echo "UNCONFIGURED (Option 15 to install)"
    fi
}

show_media_driver_status() {
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}   Hardware Acceleration Drivers, Media Codecs & Font Packs Status${NC}"
    echo -e "${CYAN}======================================================================${NC}"

    echo -e "${BOLD}Detected Graphics Controller:${NC}"
    echo "  • GPU / APU      : $(detect_gpu_hardware)"

    echo ""
    echo -e "${BOLD}Mesa & Vulkan 3D Acceleration:${NC}"
    if dpkg -s mesa-vulkan-drivers &>/dev/null; then
        echo -e "  • RADV / Vulkan : ${GREEN}INSTALLED (mesa-vulkan-drivers)${NC}"
        if command -v vulkaninfo &>/dev/null; then
            local v_dev
            v_dev=$(vulkaninfo --summary 2>/dev/null | awk -F'= ' '/deviceName/{print $2; exit}' || true)
            [ -n "$v_dev" ] && echo "    Device Name   : $v_dev"
        fi
    else
        echo -e "  • RADV / Vulkan : ${YELLOW}NOT INSTALLED (Run: sudo $0 media drivers)${NC}"
    fi

    echo ""
    echo -e "${BOLD}Hardware Video Acceleration (VA-API / VDPAU):${NC}"
    if dpkg -s mesa-va-drivers &>/dev/null || dpkg -s mesa-libgallium &>/dev/null; then
        local va_pkg="mesa-va-drivers"
        dpkg -s mesa-libgallium &>/dev/null && va_pkg="mesa-libgallium"
        echo -e "  • VA-API Driver : ${GREEN}INSTALLED ($va_pkg / radeonsi)${NC}"
        if command -v vainfo &>/dev/null; then
            local va_drv
            va_drv=$(vainfo 2>&1 | sed -n 's/.*Driver version: //p' | head -n 1 || true)
            [ -n "$va_drv" ] && echo "    Driver Info   : $va_drv"
        fi
    else
        echo -e "  • VA-API Driver : ${YELLOW}NOT INSTALLED (Run: sudo $0 media drivers)${NC}"
    fi

    if dpkg -s mesa-vdpau-drivers &>/dev/null || dpkg -s mesa-libgallium &>/dev/null; then
        local vdpau_pkg="mesa-vdpau-drivers"
        dpkg -s mesa-libgallium &>/dev/null && vdpau_pkg="mesa-libgallium (Gallium unified)"
        echo -e "  • VDPAU Driver  : ${GREEN}INSTALLED ($vdpau_pkg)${NC}"
    else
        echo -e "  • VDPAU Driver  : ${YELLOW}NOT INSTALLED${NC}"
    fi

    echo ""
    echo -e "${BOLD}Media Framework & Codecs:${NC}"
    if dpkg -s ubuntu-restricted-extras &>/dev/null; then
        echo -e "  • Restricted    : ${GREEN}INSTALLED (ubuntu-restricted-extras)${NC}"
    else
        echo -e "  • Restricted    : ${YELLOW}NOT INSTALLED (Run: sudo $0 media codecs)${NC}"
    fi
    if command -v ffmpeg &>/dev/null; then
        local ff_ver
        ff_ver=$(ffmpeg -version 2>/dev/null | head -n 1 | awk '{print $3}' || true)
        echo -e "  • FFmpeg        : ${GREEN}INSTALLED (${ff_ver:-ready})${NC}"
    else
        echo -e "  • FFmpeg        : ${YELLOW}NOT INSTALLED${NC}"
    fi
    if dpkg -s gstreamer1.0-vaapi &>/dev/null; then
        echo -e "  • GStreamer VA  : ${GREEN}INSTALLED (gstreamer1.0-vaapi)${NC}"
    else
        echo -e "  • GStreamer VA  : ${YELLOW}NOT INSTALLED${NC}"
    fi

    echo ""
    echo -e "${BOLD}Typography & Font Packs:${NC}"
    if dpkg -s ttf-mscorefonts-installer &>/dev/null; then
        echo -e "  • Microsoft Core: ${GREEN}INSTALLED (Arial, Times New Roman, Verdana)${NC}"
    else
        echo -e "  • Microsoft Core: ${YELLOW}NOT INSTALLED (Run: sudo $0 media fonts)${NC}"
    fi
    if dpkg -s fonts-crosextra-carlito &>/dev/null && dpkg -s fonts-crosextra-caladea &>/dev/null; then
        echo -e "  • Office Compat : ${GREEN}INSTALLED (Carlito/Calibri & Caladea/Cambria)${NC}"
    else
        echo -e "  • Office Compat : ${YELLOW}NOT INSTALLED${NC}"
    fi
    if dpkg -s fonts-noto-color-emoji &>/dev/null; then
        echo -e "  • Color Emoji   : ${GREEN}INSTALLED (fonts-noto-color-emoji)${NC}"
    else
        echo -e "  • Color Emoji   : ${YELLOW}NOT INSTALLED${NC}"
    fi
    if dpkg -s fonts-firacode &>/dev/null; then
        echo -e "  • Coding Fonts  : ${GREEN}INSTALLED (fonts-firacode ligatures)${NC}"
    else
        echo -e "  • Coding Fonts  : ${YELLOW}NOT INSTALLED${NC}"
    fi

    echo ""
    echo -e "${BOLD}32-Bit Multiarch Gaming Compatibility:${NC}"
    if dpkg --print-foreign-architectures 2>/dev/null | grep -q "i386"; then
        echo -e "  • i386 Multiarch: ${GREEN}ENABLED${NC}"
        if dpkg -s mesa-vulkan-drivers:i386 &>/dev/null; then
            echo -e "  • 32-bit Vulkan : ${GREEN}INSTALLED (Steam / Wine Proton ready)${NC}"
        else
            echo -e "  • 32-bit Vulkan : ${YELLOW}NOT INSTALLED${NC}"
        fi
    else
        echo -e "  • i386 Multiarch: ${CYAN}DISABLED (Clean 64-bit native baseline)${NC}"
    fi
    echo -e "${CYAN}======================================================================${NC}"
}

install_media_hardware_drivers() {
    check_root "media" "drivers"
    log_info "Updating repository package lists..."
    apt-get update
    log_info "Installing AMD/Mesa Vulkan, VA-API, and VDPAU 64-bit drivers..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${MEDIA_DRIVER_PKGS[@]}"
    log_success "Hardware acceleration drivers installed successfully."
    if command -v vainfo &>/dev/null; then
        echo ""
        log_info "VA-API Hardware Video Acceleration summary:"
        vainfo 2>&1 | head -n 12 || true
    fi
}

install_media_codecs() {
    check_root "media" "codecs"
    log_info "Pre-seeding Microsoft fonts EULA acceptance for non-interactive install..."
    echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections 2>/dev/null || true
    log_info "Updating repository package lists..."
    apt-get update
    log_info "Installing media codecs and GStreamer framework plugins..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${MEDIA_CODEC_PKGS[@]}"
    log_success "Media codecs and plugins installed successfully."
}

install_font_packs() {
    check_root "media" "fonts"
    log_info "Pre-seeding Microsoft fonts EULA acceptance for non-interactive install..."
    echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections 2>/dev/null || true
    log_info "Updating repository package lists..."
    apt-get update
    log_info "Installing Microsoft, Noto, Emoji, and programming font packs..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${MEDIA_FONT_PKGS[@]}"
    log_info "Refreshing system font cache (fc-cache)..."
    fc-cache -f 2>/dev/null || true
    log_success "Font packs installed and font cache refreshed successfully."
}

install_all_media_suite() {
    check_root "media" "install"
    log_info "Starting complete all-in-one setup for Hardware Drivers, Codecs & Fonts..."
    install_media_hardware_drivers
    install_media_codecs
    install_font_packs
    log_success "Complete Multimedia, Drivers & Fonts suite installed successfully!"
}

verify_hardware_acceleration() {
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}       Hardware Acceleration & Renderer Diagnostics${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    if command -v vainfo &>/dev/null; then
        echo -e "${BOLD}[ VA-API Video Acceleration (vainfo) ]${NC}"
        vainfo 2>&1 || true
    else
        log_warn "vainfo is not installed. Install via: sudo $0 media drivers"
    fi
    echo ""
    if command -v vulkaninfo &>/dev/null; then
        echo -e "${BOLD}[ Vulkan Driver & Capabilities (vulkaninfo --summary) ]${NC}"
        vulkaninfo --summary 2>&1 || true
    else
        log_warn "vulkaninfo is not installed. Install via: sudo $0 media drivers"
    fi
    echo -e "${CYAN}======================================================================${NC}"
}

enable_i386_support() {
    check_root "media" "i386" "enable"
    log_info "Enabling 32-bit (i386) multiarch architecture..."
    dpkg --add-architecture i386
    log_info "Updating repository package lists for i386..."
    apt-get update
    log_info "Installing 32-bit Mesa Vulkan and VA-API drivers for Steam/Wine..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${MEDIA_32BIT_PKGS[@]}"
    log_success "32-bit multiarch gaming support enabled and installed."
}

disable_i386_support() {
    check_root "media" "i386" "disable"
    log_info "Purging 32-bit (i386) packages..."
    apt-get purge -y ".*:i386" 2>/dev/null || true
    log_info "Removing 32-bit multiarch architecture..."
    dpkg --remove-architecture i386 2>/dev/null || true
    apt-get update
    log_success "32-bit support removed; restored clean 64-bit native baseline."
}

toggle_i386_support() {
    if dpkg --print-foreign-architectures 2>/dev/null | grep -q "i386"; then
        disable_i386_support
    else
        enable_i386_support
    fi
}

interactive_media_menu() {
    while true; do
        clear 2>/dev/null || true
        local cur_media cur_i386="DISABLED"
        cur_media=$(status_get_media_drivers)
        dpkg --print-foreign-architectures 2>/dev/null | grep -q "i386" && cur_i386="ENABLED"

        echo -e "${CYAN}==========================================================================================${NC}"
        echo -e "${BOLD}        Laptop Linux Optimizer — Media Codecs, Fonts & Hardware Drivers                   ${NC}"
        echo -e "${CYAN}==========================================================================================${NC}"
        echo -e "Media Suite Status  : ${GREEN}${BOLD}${cur_media}${NC}"
        echo -e "32-bit Gaming State : ${CYAN}${cur_i386}${NC} (Steam / Wine Proton multiarch)"
        echo -e "Target Hardware     : AMD APU (Ryzen 5 5500U / Radeon Vega / Mesa RADV / VCN 2.2)"
        echo ""
        echo -e "${CYAN}┌── INSTALLATION & CONFIGURATION ACTIONS ──────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[1]${NC} 🚀 Complete All-in-One Setup        ${DIM}(Mesa Vulkan, VA-API, Codecs, Fonts)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[2]${NC} 🎮 Install Mesa & Vulkan Drivers    ${DIM}(mesa-vulkan-drivers, libvulkan1, RADV)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[3]${NC} ⚡ Install Video Acceleration (VA)  ${DIM}(mesa-va-drivers, mesa-vdpau-drivers)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[4]${NC} 🎬 Install Codecs & GStreamer       ${DIM}(ubuntu-restricted-extras, ffmpeg)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[5]${NC} 🔤 Install Core Font Packs & Cache  ${DIM}(MS fonts, Noto, Emoji, Carlito, Fira)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[6]${NC} 🔍 Verify Hardware Acceleration     ${DIM}(vainfo & vulkaninfo diagnostic test)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[7]${NC} 🕹️  Toggle 32-bit Multiarch Support  ${DIM}(Optional for Steam / 32-bit Wine)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[8]${NC} 📊 Detailed Drivers & Codecs Report ${DIM}(Inspect GPU, Vulkan, Codecs, Fonts)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[0/Q]${NC} Return to Master Dashboard"
        echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        read -rp "Select an option [1-8, Q]: " mopt || break
        case "$mopt" in
            1)
                run_menu_action install_all_media_suite
                ;;
            2|3)
                run_menu_action install_media_hardware_drivers
                ;;
            4)
                run_menu_action install_media_codecs
                ;;
            5)
                run_menu_action install_font_packs
                ;;
            6)
                verify_hardware_acceleration
                if [ -t 0 ]; then
                    read -rp "Press Enter to return..." _ || true
                fi
                ;;
            7)
                run_menu_action toggle_i386_support
                ;;
            8)
                show_media_driver_status
                if [ -t 0 ]; then
                    read -rp "Press Enter to return..." _ || true
                fi
                ;;
            [Qq]|exit|0|"") break ;;
            *)
                log_warn "Invalid selection: '$mopt'"
                sleep 1
                ;;
        esac
    done
}

whiptail_media_menu() {
    local tui_cmd="$1"
    while true; do
        local cur_media
        cur_media=$(status_get_media_drivers)
        local cur_i386="DISABLED"
        dpkg --print-foreign-architectures 2>/dev/null | grep -q "i386" && cur_i386="ENABLED"

        local mmchoice
        mmchoice=$($tui_cmd --title "Media Codecs, Fonts & Hardware Drivers" \
            --menu "Current State: $cur_media | 32-bit: $cur_i386\nSelect multimedia action:" 18 78 8 \
            "1" "Complete All-in-One Setup (Drivers + Codecs + Fonts)" \
            "2" "Install Mesa Vulkan & Hardware Acceleration Drivers" \
            "3" "Install Ubuntu Restricted Media Codecs & GStreamer" \
            "4" "Install Core Font Packs & Refresh Font Cache" \
            "5" "Verify Hardware Video Acceleration (vainfo)" \
            "6" "Toggle 32-bit Multiarch Gaming Support (i386)" \
            "S" "Show Detailed Status Report" \
            "Q" "Return to Main Menu" \
            3>&1 1>&2 2>&3 || echo "Q")

        case "$mmchoice" in
            1) run_whiptail_action install_all_media_suite ;;
            2) run_whiptail_action install_media_hardware_drivers ;;
            3) run_whiptail_action install_media_codecs ;;
            4) run_whiptail_action install_font_packs ;;
            5) verify_hardware_acceleration; read -rp "Press Enter to return..." _ ;;
            6) run_whiptail_action toggle_i386_support ;;
            S) show_media_driver_status; read -rp "Press Enter to return..." _ ;;
            Q|"") break ;;
        esac
    done
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
        local cur_nm cur_bbr cur_swap cur_zram cur_dhcp cur_kern cur_avahi cur_cups cur_modem cur_blur
        cur_nm=$(status_get_wait_online)
        cur_bbr=$(status_get_bbr)
        cur_swap=$(status_get_swappiness)
        cur_zram=$(status_get_zram)
        cur_dhcp=$(status_get_dhcp)
        cur_kern=$(status_get_kernel_privacy)
        cur_avahi=$(status_get_avahi)
        cur_cups=$(status_get_cups)
        cur_modem=$(status_get_modem)
        cur_blur=$(status_get_font_antiblur)
        local cur_epp cur_audio cur_bvaapi cur_ufw cur_apport cur_trim
        cur_epp=$(status_get_epp)
        cur_audio=$(status_get_audio_powersave)
        cur_bvaapi=$(status_get_browser_vaapi)
        cur_ufw=$(status_get_ufw)
        cur_apport=$(status_get_apport)
        cur_trim=$(status_get_fstrim)

        local tchoice
        tchoice=$($tui_cmd --title "Performance, Privacy & Hardware Toggles" \
            --menu "Select an option to toggle or configure:" 28 80 18 \
            "E" "AMD P-State EPP Governor       [$cur_epp]" \
            "K" "Audio Powersave DAC Pop Fix   [$cur_audio]" \
            "V" "Browser Video VA-API Decode   [$cur_bvaapi]" \
            "T" "SSD Periodic TRIM (fstrim)    [$cur_trim]" \
            "F" "Font Anti-Blur (LCD Subpixel) [$cur_blur]" \
            "1" "NM Boot Wait Delay (~7s boot) [$cur_nm]" \
            "2" "TCP Congestion Control (BBR)  [$cur_bbr]" \
            "3" "Swappiness & VFS Cache        [$cur_swap]" \
            "4" "ZRAM In-Memory Swap (zstd)    [$cur_zram]" \
            "W" "Laptop Inbound UFW Firewall   [$cur_ufw]" \
            "P" "Apport Crash Popups Shield    [$cur_apport]" \
            "L" "Root Account Hardening        [$(status_get_root_lock)]" \
            "5" "DHCP Hostname Leak Shield     [$cur_dhcp]" \
            "6" "Kernel Memory Privacy (dmesg) [$cur_kern]" \
            "7" "SSH Inbound Server Shield     [$cur_ssh]" \
            "8" "Avahi mDNS (LocalSend)        [$cur_avahi]" \
            "9" "CUPS Printer Discovery        [$cur_cups]" \
            "M" "ModemManager Cellular Scan    [$cur_modem]" \
            "B" "Toggle All Broadcast Daemons" \
            "A" "Apply All Recommended Tunings" \
            "R" "Revert All Tunings to Baseline" \
            "S" "Display Full Diagnostics Report" \
            3>&1 1>&2 2>&3 || echo "Q")

        case "$tchoice" in
            E) run_whiptail_action cycle_epp_preference ;;
            K) run_whiptail_action toggle_audio_powersave_fix ;;
            V) run_whiptail_action toggle_browser_vaapi ;;
            W) run_whiptail_action toggle_laptop_firewall ;;
            P) run_whiptail_action toggle_apport ;;
            L) run_whiptail_action toggle_root_user ;;
            T) run_whiptail_action toggle_fstrim_timer ;;
            1) run_whiptail_action toggle_nm_wait_online ;;
            2) run_whiptail_action toggle_bbr ;;
            3) run_whiptail_action toggle_swappiness ;;
            4) run_whiptail_action toggle_zram ;;
            5) run_whiptail_action toggle_dhcp_privacy ;;
            6) run_whiptail_action toggle_kernel_hardening ;;
            7) run_whiptail_action toggle_ssh_hardening ;;
            8) run_whiptail_action toggle_avahi ;;
            9) run_whiptail_action toggle_cups_browsed ;;
            M) run_whiptail_action toggle_modemmanager ;;
            F) run_whiptail_action toggle_font_antiblur ;;
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
            --menu "Select a subsystem or management action below:" 24 78 15 \
            "P"  "Switch Profile Preset (Desk / Balanced / Travel)" \
            "1"  "Guided Laptop Optimization Wizard (14-Step Setup)" \
            "2"  "Update All Packages & Sweep Clean (APT + Snap + Flatpak)" \
            "3"  "System Housekeeping (Caches, journals, temp)" \
            "4"  "Battery Diagnostics & Charge Limiter Configuration" \
            "5"  "Encrypted DNS Manager (DoH / Relays / Tor)" \
            "6"  "Network MAC Randomization & Spoofing" \
            "7"  "Performance, Privacy & Startup Toggles (NM Boot, BBR, ZRAM)" \
            "8"  "Privacy & Anti-Tracking Activity Scrub" \
            "9"  "Automated Weekly Maintenance Timer" \
            "10" "Toggle IPv6 Protocol (Enable / Disable)" \
            "11" "Complete Master Suite (All-In-One)" \
            "12" "ELAN I2C Touchpad Freeze Fix & AMD Bus Manager" \
            "13" "Popular Themes Gallery & Uniform Styling" \
            "14" "GRUB Bootloader Configuration & Recovery" \
            "15" "Media Codecs, Fonts & Hardware Acceleration Drivers" \
            "L"  "Root Account Hardening Shield (Lock Root & SSH Block)" \
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
            L) run_whiptail_action toggle_root_user ;;
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
            12) whiptail_touchpad_menu "$tui_cmd" ;;
            13) run_whiptail_action interactive_theme_menu ;;
            14) run_whiptail_action fix_grub_menu ;;
            15) whiptail_media_menu "$tui_cmd" ;;
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
        local cur_os cur_nm cur_bbr cur_swap cur_zram cur_dhcp cur_kern cur_ssh cur_avahi cur_cups cur_modem cur_blur
        cur_os=$(status_get_target_os)
        cur_nm=$(status_get_wait_online)
        cur_bbr=$(status_get_bbr)
        cur_swap=$(status_get_swappiness)
        cur_zram=$(status_get_zram)
        cur_dhcp=$(status_get_dhcp)
        cur_kern=$(status_get_kernel_privacy)
        cur_ssh=$(status_get_ssh_server)
        cur_avahi=$(status_get_avahi)
        cur_cups=$(status_get_cups)
        cur_modem=$(status_get_modem)
        cur_blur=$(status_get_font_antiblur)
        local cur_epp cur_audio cur_bvaapi cur_ufw cur_apport cur_trim
        cur_epp=$(status_get_epp)
        cur_audio=$(status_get_audio_powersave)
        cur_bvaapi=$(status_get_browser_vaapi)
        cur_ufw=$(status_get_ufw)
        cur_apport=$(status_get_apport)
        cur_trim=$(status_get_fstrim)

        local nm_pill bbr_pill swap_pill zram_pill dhcp_pill kern_pill ssh_pill avahi_pill cups_pill modem_pill blur_pill
        local epp_pill audio_pill bvaapi_pill ufw_pill apport_pill trim_pill
        [[ "$cur_nm" =~ DISABLED ]] && nm_pill="${GREEN}[✓ FAST BOOT (DISABLED)]${NC}" || nm_pill="${YELLOW}[● ENABLED (~7s delay)]${NC}"
        [[ "$cur_bbr" =~ BBR ]] && bbr_pill="${GREEN}[✓ ACTIVE (BBR)]${NC}" || bbr_pill="${YELLOW}[○ $cur_bbr]${NC}"
        [[ "$cur_swap" =~ 100|180 ]] && swap_pill="${GREEN}[✓ OPTIMIZED]${NC}" || swap_pill="${YELLOW}[○ DEFAULT]${NC}"
        [[ "$cur_zram" =~ ACTIVE ]] && zram_pill="${GREEN}[✓ ACTIVE]${NC}" || zram_pill="${YELLOW}[○ INACTIVE]${NC}"
        [[ "$cur_dhcp" =~ BLOCKED ]] && dhcp_pill="${GREEN}[✓ BLOCKED (Shielded)]${NC}" || dhcp_pill="${YELLOW}[○ EXPOSED (Leaking)]${NC}"
        [[ "$cur_kern" =~ HARDENED ]] && kern_pill="${GREEN}[✓ HARDENED]${NC}" || kern_pill="${YELLOW}[○ PERMISSIVE]${NC}"
        [[ "$cur_ssh" =~ MASKED ]] && ssh_pill="${GREEN}[✓ MASKED (Blocked)]${NC}" || ssh_pill="${YELLOW}[○ $cur_ssh]${NC}"
        [[ "$cur_avahi" =~ DISABLED ]] && avahi_pill="${GREEN}[✓ DISABLED]${NC}" || avahi_pill="${YELLOW}[● ACTIVE (mDNS/LocalSend)]${NC}"
        [[ "$cur_cups" =~ ACTIVE ]] && cups_pill="${GREEN}[✓ ACTIVE (Printer Discovery)]${NC}" || cups_pill="${YELLOW}[○ DISABLED]${NC}"
        [[ "$cur_modem" =~ DISABLED ]] && modem_pill="${GREEN}[✓ DISABLED]${NC}" || modem_pill="${YELLOW}[● ACTIVE (Modem)]${NC}"
        [[ "$cur_blur" =~ ACTIVE ]] || [[ "$cur_blur" =~ COSMIC ]] && blur_pill="${GREEN}[✓ $cur_blur]${NC}" || blur_pill="${YELLOW}[○ UNCONFIGURED]${NC}"
        epp_pill="${GREEN}[✓ $cur_epp]${NC}"
        [[ "$cur_audio" =~ FIXED ]] && audio_pill="${GREEN}[✓ FIXED (Shielded)]${NC}" || audio_pill="${YELLOW}[● POWERSAVE (Pop risk)]${NC}"
        [[ "$cur_bvaapi" =~ CONFIGURED ]] && bvaapi_pill="${GREEN}[✓ VA-API ACTIVE]${NC}" || bvaapi_pill="${YELLOW}[○ DEFAULT]${NC}"
        [[ "$cur_ufw" =~ ACTIVE ]] && ufw_pill="${GREEN}[✓ ACTIVE (Shielded)]${NC}" || ufw_pill="${YELLOW}[○ INACTIVE]${NC}"
        [[ "$cur_apport" =~ DISABLED ]] && apport_pill="${GREEN}[✓ DISABLED (Silenced)]${NC}" || apport_pill="${YELLOW}[● ACTIVE (Popups)]${NC}"
        [[ "$cur_trim" =~ ACTIVE ]] && trim_pill="${GREEN}[✓ ACTIVE (Weekly)]${NC}" || trim_pill="${YELLOW}[○ DISABLED]${NC}"

        echo -e "${CYAN}╭──────────────────────────────────────────────────────────────────────────────╮${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}${GREEN}⚡ PERFORMANCE, PRIVACY & HARDENING TOGGLE HUB${NC}                             ${CYAN}│${NC}"
        echo -e "${CYAN}╰──────────────────────────────────────────────────────────────────────────────╯${NC}"
        echo -e "${CYAN}┌── ⚡ HARDWARE & POWER TUNING ─────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[O]${NC} Target OS Platform     : ${GREEN}${BOLD}[ $cur_os ]${NC} ⇄ Ubuntu / Pop!_OS / Linux Mint"
        echo -e "${CYAN}│${NC}  ${BOLD}[E]${NC} AMD P-State EPP        : $epp_pill ⇄ CPU frequency energy preference"
        echo -e "${CYAN}│${NC}  ${BOLD}[K]${NC} Audio Powersave Pop Fix: $audio_pill ⇄ Disable DAC sleep (stop speaker clicks)"
        echo -e "${CYAN}│${NC}  ${BOLD}[V]${NC} Browser Video VA-API   : $bvaapi_pill ⇄ Hardware video decode (Firefox/Brave)"
        echo -e "${CYAN}│${NC}  ${BOLD}[T]${NC} SSD Periodic TRIM      : $trim_pill ⇄ Weekly fstrim to maintain NVMe write speed"
        echo -e "${CYAN}│${NC}  ${BOLD}[F]${NC} Font Anti-Blur (LCD)   : $blur_pill ⇄ Subpixel RGB hinting (crisp Flatpaks)"
        echo -e "${CYAN}├── 🚀 KERNEL, MEMORY & BOOT SPEED ────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[1]${NC} NM Wait-Online Delay   : $nm_pill ⇄ Remove ~7s boot wait on network"
        echo -e "${CYAN}│${NC}  ${BOLD}[2]${NC} TCP Congestion (BBR)   : $bbr_pill ⇄ Google BBR low-latency Wi-Fi algorithm"
        echo -e "${CYAN}│${NC}  ${BOLD}[3]${NC} Swappiness & VFS Cache : $swap_pill ⇄ Swappiness 100 tuned for ZRAM & NVMe"
        echo -e "${CYAN}│${NC}  ${BOLD}[4]${NC} ZRAM Compressed Swap   : $zram_pill ⇄ In-RAM zstd swap (virtually +50% RAM)"
        echo -e "${CYAN}├── 🛡️  SECURITY, FIREWALL & PRIVACY SHIELDS ──────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[W]${NC} Laptop UFW Firewall    : $ufw_pill ⇄ Block inbound on public Wi-Fi"
        local cur_root
        cur_root=$(status_get_root_lock)
        local root_pill
        [[ "$cur_root" =~ LOCKED ]] && root_pill="${GREEN}[✓ LOCKED (Sudo only)]${NC}" || root_pill="${YELLOW}[● UNLOCKED (Password set)]${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[P]${NC} Apport Crash Popups    : $apport_pill ⇄ Silence Ubuntu crash error dialogs"
        echo -e "${CYAN}│${NC}  ${BOLD}[L]${NC} Root User Hardening    : $root_pill ⇄ Lock root password & block direct SSH"
        echo -e "${CYAN}│${NC}  ${BOLD}[5]${NC} DHCP Hostname Privacy  : $dhcp_pill ⇄ Stop leaking computer name to routers"
        echo -e "${CYAN}│${NC}  ${BOLD}[6]${NC} Kernel Memory Privacy  : $kern_pill ⇄ Restrict dmesg/kptr kernel memory to root"
        echo -e "${CYAN}│${NC}  ${BOLD}[7]${NC} SSH Inbound Server     : $ssh_pill ⇄ Mask SSH server (no open port 22)"
        echo -e "${CYAN}├── 📡 BACKGROUND DAEMONS & DISCOVERY ─────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[8]${NC} Avahi mDNS Daemon      : $avahi_pill ⇄ LocalSend & .local network discovery"
        echo -e "${CYAN}│${NC}  ${BOLD}[9]${NC} CUPS Network Polling   : $cups_pill ⇄ Wi-Fi printer discovery & sharing"
        echo -e "${CYAN}│${NC}  ${BOLD}[M]${NC} ModemManager Daemon    : $modem_pill ⇄ Stop cellular polling (saves battery)"
        echo -e "${CYAN}│${NC}  ${BOLD}[B]${NC} Toggle Broadcast Daemon: Toggle all 3 broadcast services safely"
        echo -e "${CYAN}├── 🏆 BATCH ACTIONS & DIAGNOSTICS ────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[A]${NC} Apply All Recommended  : Apply all optimizations (preserves LocalSend/CUPS)"
        echo -e "${CYAN}│${NC}  ${BOLD}[R]${NC} Revert All Tunings     : Restore system baseline configuration"
        echo -e "${CYAN}│${NC}  ${BOLD}[S]${NC} Detailed Report        : Display full status diagnostics report"
        echo -e "${CYAN}│${NC}  ${BOLD}[0/Q]${NC} Return to Master Dashboard"
        echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        read -rp "Select an option to toggle [0-9, O, E, K, V, W, P, L, T, H, M, F, B, A, R, S, Q]: " topt

        case "$topt" in
            [Oo]|os|platform) run_menu_action toggle_target_os ;;
            [Ee]|epp) run_menu_action cycle_epp_preference ;;
            [Kk]|audio) run_menu_action toggle_audio_powersave_fix ;;
            [Vv]|browser|vaapi) run_menu_action toggle_browser_vaapi ;;
            [Ww]|ufw|firewall) run_menu_action toggle_laptop_firewall ;;
            [Pp]|apport|crash) run_menu_action toggle_apport ;;
            [Ll]|root) run_menu_action toggle_root_user ;;
            [Tt]|trim|fstrim) run_menu_action toggle_fstrim_timer ;;
            1) run_menu_action toggle_nm_wait_online ;;
            2) run_menu_action toggle_bbr ;;
            3) run_menu_action toggle_swappiness ;;
            4) run_menu_action toggle_zram ;;
            5) run_menu_action toggle_dhcp_privacy ;;
            6) run_menu_action toggle_kernel_hardening ;;
            7|[Hh]|ssh) run_menu_action toggle_ssh_hardening ;;
            8) run_menu_action toggle_avahi ;;
            9) run_menu_action toggle_cups_browsed ;;
            [Mm]|modem) run_menu_action toggle_modemmanager ;;
            [Ff]|blur|antiblur) run_menu_action toggle_font_antiblur ;;
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
            echo -e "${YELLOW}Notice: System updates or cleanup recommended.${NC}"
            read -rp "Would you like to run full update & cleanup now? [Y/n]: " ans_init
            if [[ ! "$ans_init" =~ ^[Nn] ]]; then
                run_menu_action run_full_update_and_optimizer
                updates=$(check_pending_updates)
                cleanable_kb=$(check_cleanable_cache)
            fi
        fi
        echo ""
        read -rp "Press Enter to open the Master System Control Center..." _
    fi

    while true; do
        clear 2>/dev/null || true

        local cur_preset cur_bat cur_zram cur_bbr cur_dns cur_mac cur_timer cur_ipv6 cur_nm cur_blur cur_theme
        cur_preset=$(status_get_preset)
        cur_bat=$(status_get_battery)
        cur_zram=$(status_get_zram)
        cur_bbr=$(status_get_bbr)
        cur_dns=$(status_get_dns)
        cur_mac=$(status_get_mac)
        cur_timer=$(status_get_timer)
        cur_ipv6=$(status_get_ipv6)
        cur_nm=$(status_get_wait_online)
        cur_blur=$(status_get_font_antiblur)
        cur_theme=$(status_get_uniform_theme)
        local cur_epp cur_audio cur_trim cur_bvaapi cur_ufw cur_apport
        cur_epp=$(status_get_epp)
        cur_audio=$(status_get_audio_powersave)
        cur_trim=$(status_get_fstrim)
        cur_bvaapi=$(status_get_browser_vaapi)
        cur_ufw=$(status_get_ufw)
        cur_apport=$(status_get_apport)

        local cur_nm_pill
        [[ "$cur_nm" =~ DISABLED ]] && cur_nm_pill="${GREEN}${BOLD}[ FAST BOOT (Disabled) ]${NC} (No ~7s delay)" || cur_nm_pill="${YELLOW}${BOLD}[ ENABLED (~7s delay) ]${NC}"

        local cur_blur_pill
        [[ "$cur_blur" =~ ACTIVE ]] || [[ "$cur_blur" =~ COSMIC ]] && cur_blur_pill="${GREEN}${BOLD}[ $cur_blur ]${NC}" || cur_blur_pill="${YELLOW}${BOLD}[ UNCONFIGURED (Grayscale blur) ]${NC}"

        local cur_media_pill
        cur_media_pill=$(status_get_media_drivers)
        if [[ "$cur_media_pill" =~ INSTALLED ]]; then
            cur_media_pill="${GREEN}${BOLD}[ INSTALLED ]${NC}"
        elif [[ "$cur_media_pill" =~ PARTIAL ]]; then
            cur_media_pill="${YELLOW}${BOLD}[ PARTIAL ]${NC}"
        else
            cur_media_pill="${RED}${BOLD}[ UNCONFIGURED ]${NC}"
        fi

        echo -e "${CYAN}╭──────────────────────────────────────────────────────────────────────────────╮${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}${GREEN}⚡ LAPTOP LINUX OPTIMIZER & SYSTEM CONTROL CENTER${NC}                  ${DIM}v${VERSION}${NC}  ${CYAN}│${NC}"
        echo -e "${CYAN}╰──────────────────────────────────────────────────────────────────────────────╯${NC}"
        echo -e "${CYAN}┌── LIVE SYSTEM & HARDWARE STATUS ─────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}Active Preset${NC}   : ${GREEN}${BOLD}${cur_preset}${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}Battery Limit${NC}   : ${CYAN}${cur_bat}${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}CPU Scaling (EPP)${NC}: ${GREEN}${BOLD}${cur_epp}${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}Audio Pop Shield${NC}: ${cur_audio}"
        echo -e "${CYAN}│${NC}  ${BOLD}SSD Periodic TRIM${NC}: ${cur_trim}"
        echo -e "${CYAN}│${NC}  ${BOLD}ZRAM RAM Swap${NC}   : ${GREEN}${cur_zram}${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}TCP Congestion${NC}  : ${GREEN}${cur_bbr}${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}Encrypted DNS${NC}   : ${BLUE}${cur_dns}${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}Network MAC${NC}     : ${MAGENTA}${cur_mac}${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}Laptop UFW Shield${NC}: ${cur_ufw}"
        echo -e "${CYAN}│${NC}  ${BOLD}Apport Popups${NC}   : ${cur_apport}"
        echo -e "${CYAN}│${NC}  ${BOLD}Root User Access${NC} : $(status_get_root_lock)"
        echo -e "${CYAN}│${NC}  ${BOLD}NM Fast Boot${NC}    : ${cur_nm_pill}"
        echo -e "${CYAN}│${NC}  ${BOLD}Font Anti-Blur${NC}  : ${cur_blur_pill}"
        echo -e "${CYAN}│${NC}  ${BOLD}Browser Video VA${NC}: ${cur_bvaapi}"
        echo -e "${CYAN}│${NC}  ${BOLD}Uniform Theme${NC}  : ${MAGENTA}${BOLD}${cur_theme}${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}Media & Drivers${NC} : ${cur_media_pill}"
        echo -e "${CYAN}│${NC}  ${BOLD}IPv6 Protocol${NC}   : ${cur_ipv6}  ${CYAN}│${NC}  ${BOLD}Weekly Timer${NC}: ${cur_timer}"
        echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────────┘${NC}"

        # Display advisory banner if updates, cleanups, or blur fix pending
        if [ "$updates" -gt 0 ] || [ "$cleanable_kb" -gt 50000 ] || [[ "$cur_blur" =~ UNCONFIGURED ]]; then
            echo -e "${YELLOW}┌── NOTIFICATIONS & MAINTENANCE ADVISORY ──────────────────────────────────────┐${NC}"
            if [[ "$cur_blur" =~ UNCONFIGURED ]]; then
                echo -e "${YELLOW}│${NC}  ${YELLOW}●${NC} Flatpak text blurriness detected.      ${DIM}[Press ${BOLD}F${NC}${DIM} to Fix Anti-Blur]${NC}"
            fi
            if [ "$updates" -gt 0 ]; then
                echo -e "${YELLOW}│${NC}  ${YELLOW}●${NC} ${BOLD}$updates${NC} package update(s) available.          ${DIM}[Press ${BOLD}U${NC}${DIM} to Update Now]${NC}"
            fi
            if [ "$cleanable_kb" -gt 50000 ]; then
                echo -e "${YELLOW}│${NC}  ${YELLOW}●${NC} ~${BOLD}$(format_kb "$cleanable_kb")${NC} cleanable caches & logs.        ${DIM}[Press ${BOLD}C${NC}${DIM} to Clean Now]${NC}"
            fi
            if [ "$updates" -gt 0 ] && [ "$cleanable_kb" -gt 50000 ]; then
                echo -e "${YELLOW}│${NC}  ${YELLOW}●${NC} Full Update & Single-Pass Clean       ${DIM}[Press ${BOLD}A${NC}${DIM} for All-in-One]${NC}"
            fi
            echo -e "${YELLOW}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        fi

        local ipv6_lbl="ENABLED"
        [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 0)" -eq 1 ] && ipv6_lbl="DISABLED"

        echo -e "${CYAN}┌── 🚀 CORE SETUP & QUICK WORKFLOWS ───────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[1]${NC} 🚀 Guided Optimization Wizard       ${DIM}(14-step comprehensive setup with guidance)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[P]${NC} 🔄 Switch Profile Preset           ${DIM}(Desk: 60% | Balanced: 80% | Travel: 100%)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[2]${NC} 📦 Update Packages & Sweep Clean    ${DIM}(APT dist-upgrade + Snap + Flatpak)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[3]${NC} 🧹 System Housekeeping & Cleanups   ${DIM}(Journals, APT, Snap, Temp caches)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[4]${NC} 🏆 Complete Master Suite            ${DIM}(All-in-One: Update + Clean + Privacy + MAC)${NC}"
        echo -e "${CYAN}├── 🔋 HARDWARE, BATTERY & POWER MANAGEMENT ───────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[5]${NC} 🔋 Battery Diagnostics & Limiter    ${DIM}(Prevent wear: 60%/80%/100% threshold)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[E]${NC} ⚡ CPU Scaling (AMD P-State EPP)   ${DIM}(balance_performance vs balance_power)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[K]${NC} 🔊 Audio Pop & Crackle Shield      ${DIM}(Disable DAC sleep; eliminate speaker clicks)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[S]${NC} 💾 SSD / NVMe Periodic TRIM        ${DIM}(Weekly automated fstrim maintenance)${NC}"
        echo -e "${CYAN}│${NC} ${BOLD}[12]${NC} 🖱️  ELAN I2C Touchpad Freeze Fix & PM  ${DIM}(Zero-latency bus awake + 1:1 gestures)${NC}"
        echo -e "${CYAN}├── 🎬 GRAPHICS, DISPLAY & ACCELERATION ───────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC} ${BOLD}[15]${NC} 🎬 Media Codecs, Fonts & GPU Driver ${DIM}(Mesa Vulkan, VA-API video decode, MS fonts)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[V]${NC} 🌐 Browser Video Acceleration (VA)  ${DIM}(Hardware video decode for Firefox/Brave)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[F]${NC} 🔍 Font Anti-Blur & High-DPI Clarity ${DIM}(Subpixel RGB & Ozone Wayland rendering)${NC}"
        echo -e "${CYAN}├── 🛡️  SECURITY, NETWORK & PRIVACY ───────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[H]${NC} 🛡️  Laptop UFW Firewall Shield     ${DIM}(Inbound drop on public Wi-Fi; keep LAN share)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[D]${NC} 🛑 Apport Crash Popups Shield      ${DIM}(Silence recurring Ubuntu crash error dialogs)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[L]${NC} 🔒 Root User Hardening Shield      ${DIM}(Lock root password & block direct SSH login)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[6]${NC} 🔒 Encrypted DNS Manager           ${DIM}(DoH / Relays / NextDNS / Quad9 / Cloudflare)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[7]${NC} 🕵️  Network MAC Randomization & View ${DIM}(Prevent tracking across public Wi-Fi)${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[8]${NC} 🌐 Toggle IPv6 Protocol            ${DIM}(State: [${ipv6_lbl}] - leak protection)${NC}"
        echo -e "${CYAN}│${NC} ${BOLD}[10]${NC} 🔒 Privacy & Anti-Tracking Scrub   ${DIM}(Clean recent files, caches & activity history)${NC}"
        echo -e "${CYAN}├── ⚙️  SYSTEM TOOLS & ADVANCED CONFIGURATION ─────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[9]${NC} ⚡ Advanced Performance Toggles    ${DIM}(NM Boot, TCP BBR, ZRAM, DHCP, Daemons)${NC}"
        echo -e "${CYAN}│${NC} ${BOLD}[13]${NC} 🎨 Popular Themes Gallery & Uniform ${DIM}(GTK3, Libadwaita & Flatpak sync)${NC}"
        echo -e "${CYAN}│${NC} ${BOLD}[14]${NC} 🛠️  GRUB Bootloader Configuration   ${DIM}(Restore /etc/default/grub baseline)${NC}"
        echo -e "${CYAN}│${NC} ${BOLD}[11]${NC} ⏱️  Automated Maintenance Timer     ${DIM}(Set & forget systemd weekly timer)${NC}"
        echo -e "${CYAN}│${NC}"
        echo -e "${CYAN}│${NC}  ${BOLD}[W]${NC} Whiptail Mode   ${BOLD}[R]${NC} Refresh Status   ${BOLD}[0/Q]${NC} Exit"
        echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        read -rp "Select an option [0-15, P, E, K, S, V, F, H, D, L, W, R, Q]: " opt || break

        case "$opt" in
            [Pp]|preset)
                run_menu_action interactive_preset_menu
                ;;
            [Aa]|all)
                run_menu_action run_full_update_and_optimizer
                updates=$(check_pending_updates)
                cleanable_kb=$(check_cleanable_cache)
                ;;
            [Ff]|blur|antiblur)
                run_menu_action toggle_font_antiblur
                ;;
            [Ll]|root|lock-root)
                run_menu_action toggle_root_user
                ;;
            [Ee]|epp)
                run_menu_action cycle_epp_preference
                ;;
            [Kk]|audio)
                run_menu_action toggle_audio_powersave_fix
                ;;
            [Ss]|trim|fstrim)
                run_menu_action toggle_fstrim_timer
                ;;
            [Vv]|browser|vaapi)
                run_menu_action toggle_browser_vaapi
                ;;
            [Hh]|shield|firewall|ufw)
                run_menu_action toggle_laptop_firewall
                ;;
            [Dd]|apport|crash)
                run_menu_action toggle_apport
                ;;
            12|[Tt]|touchpad)
                run_menu_action interactive_touchpad_menu
                ;;
            13|[Gg]|gallery|theme|themes)
                run_menu_action interactive_theme_menu
                ;;
            14|grub|bootloader)
                run_menu_action fix_grub_menu
                ;;
            15|[Mm]|media|codecs|drivers)
                run_menu_action interactive_media_menu
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
            [Ww]|dialog|whiptail)
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
    echo -e "${BOLD}   Laptop Linux Optimizer & Master Administration Suite (laptop-linux-optimiser)${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo "Usage: $0 [command] [subcommand / options...]"
    echo ""
    echo "Command Subsystems:"
    echo "  wizard, guided            Run the comprehensive 14-step guided laptop optimization wizard"
    echo "  battery                   Battery diagnostics and charge limiter"
    echo "    status                  Display battery capacity, cycles, health & limit"
    echo "    set <20-100>            Set charge threshold temporarily (e.g. 60, 80, 100)"
    echo "    install [limit]         Install persistent systemd service & sleep hook (default: 80)"
    echo "    uninstall               Remove limiter service and restore 100%"
    echo ""
    echo "  os, platform              Target OS switching (Ubuntu LTS, Pop!_OS, Linux Mint)"
    echo "    status                  Display active target OS and auto-detected platform"
    echo "    ubuntu                  Set target OS to Ubuntu LTS (GNOME Desktop Edition)"
    echo "    popos                   Set target OS to Pop!_OS (COSMIC Desktop Edition)"
    echo "    mint                    Set target OS to Linux Mint (Cinnamon Desktop Edition)"
    echo "    toggle                  Cycle target OS between Ubuntu LTS, Pop!_OS, and Linux Mint"
    echo ""
    echo "  theme, themes, appearance Popular themes gallery & uniform styling (Deb, GTK3, Libadwaita & Flatpak)"
    echo "    gallery                 Interactive popular themes gallery (adw-gtk3, Catppuccin, Dracula, Nordic...)"
    echo "    apply <theme-name>      Apply theme across GTK3, Libadwaita CSS and Flatpaks"
    echo "    install <theme-name>    Download and extract theme from GitHub release"
    echo "    reset                   Reset theming to clean system default"
    echo "    status                  Display current active theme and Flatpak theme overrides"
    echo ""
    echo "  network, net              Clean network optimizations & bypass decoupling"
    echo "    clean-overrides         Remove dnscrypt drop-ins, legacy iptables & restore clean baseline"
    echo "    status                  Show current network overrides and standalone app compatibility"
    echo ""
    echo "  dns                       Encrypted DNS (DoH, Anonymized Relays, Tor)"
    echo "    menu                    Interactive encrypted DNS selection menu"
    echo "    apply <0-14|profile>    Apply DNS profile directly by index or name"
    echo "    status                  Show current active DNS resolver status"
    echo "    hosts                   Ensure dynamic system hostname is mapped in /etc/hosts"
    echo "    revert                  Restore default DHCP DNS configuration"
    echo ""
    echo "  grub, bootloader          GRUB bootloader configuration & recovery"
    echo "    status                  Display GRUB configuration and timeout settings"
    echo "    fix, repair             Restore canonical /etc/default/grub baseline and update-grub"
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
    echo "  antiblur, blur            Subpixel font anti-blur & High-DPI scaling (Flatpak/COSMIC)"
    echo "    status                  Display fontconfig and Flatpak anti-blur status"
    echo "    toggle                  Toggle subpixel RGB anti-blur and Ozone High-DPI flags"
    echo "    enable, on              Enable subpixel RGB, full hinting, and Flatpak font overrides"
    echo "    disable, off            Revert font anti-blur settings to system defaults"
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
    echo "    revert                  Revert system tunings to standard Pop!_OS defaults"
    echo "    wait-online [toggle]    Toggle NetworkManager wait-online boot delay (~7s saved)"
    echo "    bbr [toggle]            Toggle Google TCP BBR low-latency congestion control"
    echo "    swappiness [toggle]     Toggle swappiness & cache pressure (100/50 vs 60/100)"
    echo "    zram [toggle]           Toggle ZRAM 50% RAM compressed swap"
    echo "    dhcp [toggle]           Toggle DHCP hostname leak protection"
    echo "    hosts                   Ensure dynamic system hostname is mapped in /etc/hosts"
    echo "    kernel [toggle]         Toggle kernel memory privacy (dmesg & kptr restrict)"
    echo "    avahi [toggle]          Toggle Avahi mDNS discovery broadcast daemon"
    echo "    cups [toggle]           Toggle CUPS network printer polling daemon"
    echo "    modem [toggle]          Toggle ModemManager cellular serial scanner"
    echo "    daemons [toggle]        Toggle all 3 discovery broadcast daemons at once"
    echo ""
    echo "  touchpad, elan, trackpad  ELAN I2C touchpad responsiveness, dropout fix & AMD/Intel bus tuning"
    echo "    status                  Display real-time controller PM, runtime, C-state, PSR & libinput quirks"
    echo "    auto, smart             Smart hardware-aware auto-tuning (one-click safe optimization)"
    echo "    apply, install          Install permanent udev rule, resume hook, libinput quirks, C2 cap & PSR fix"
    echo "    gestures, gnome         Configure 1:1 Wayland/X11 multi-finger gestures & tap-to-click"
    echo "    dwt [toggle]            Toggle Disable-While-Typing (prevent 500ms keyboard pause)"
    echo "    revert, uninstall       Revert udev rules, resume hook, quirks & bootloader parameters"
    echo "    fix-stutter             One-click comprehensive fix for Wayland/DisplayLink hitching & ghost pressure"
    echo "    runtime                 Apply runtime PM fix to keep I2C controller awake for current session"
    echo "    cstate [toggle]         Toggle bootloader idle C-state cap (processor.max_cstate=2)"
    echo "    psr [toggle]            Toggle GPU Panel Self Refresh wake-up fix (amdgpu/intel)"
    echo "    quirks [toggle]         Toggle libinput hardware quirks (31x31 resolution hint)"
    echo "    evdi [status|fix|restore|toggle] DisplayLink EVDI on-demand mode (fixes primary GPU card0 hijacking)"
    echo "    speed [100khz|400khz|toggle] Force 100 kHz I2C bus clock via early initrd ACPI table upgrade"
    echo "    tap-drag [toggle]       Toggle tap-and-drag disambiguation delay (eliminates initial touch lag)"
    echo "    accel [flat|adaptive|toggle] Switch between Flat 1:1 linear motion and Adaptive acceleration"
    echo "    diagnose                Launch live hardware interrupt & drop diagnostic tracer"
    echo "    menu                    Interactive terminal management menu for ELAN touchpads"
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
    echo "  optimize, clean           Run routine housekeeping (APT, Snap, Flatpak, journals, temp)"
    echo "  update, upgrade           Update all packages (APT, Snap & Flatpak) and purge orphans/caches"
    echo "  all                       Full update followed by complete system housekeeping"
    echo "  privacy                   Scrub privacy caches (browsers, recent files, DNS, trash)"
    echo "  full-suite                Total master run: update + housekeeping + privacy + MAC"
    echo ""
    echo "  timer                     Automated weekly background maintenance"
    echo "    status                  View timer status and previous run logs"
    echo "    install                 Install persistent systemd weekly timer"
    echo "    uninstall               Remove systemd weekly timer"
    echo ""
    echo "  media, multimedia, codecs Media codecs, font packs & hardware acceleration drivers"
    echo "    status                  Show status of Vulkan, VA-API, VDPAU, codecs & fonts"
    echo "    install                 Install complete all-in-one suite (Drivers + Codecs + Fonts)"
    echo "    drivers                 Install AMD/Mesa Vulkan (RADV), VA-API & VDPAU drivers"
    echo "    codecs                  Install Ubuntu restricted extras & GStreamer plugins"
    echo "    fonts                   Install Microsoft core fonts, Noto, Emoji, and Carlito/Caladea"
    echo "    verify                  Verify VA-API and Vulkan hardware acceleration (vainfo)"
    echo "    i386 [status|enable|disable] Toggle optional 32-bit multiarch gaming support (Wine/Steam)"
    echo "    menu                    Interactive multimedia, drivers & fonts management menu"
    echo ""
    echo "  epp, amd-pstate           AMD P-State EPP energy performance preference"
    echo "    status                  Show current scaling driver and active EPP preference"
    echo "    power, balance_power, balance_performance, performance  Set EPP profile"
    echo "    cycle                   Cycle through available EPP energy preferences"
    echo ""
    echo "  audio, audio-powersave    Audio DAC power-save idle popping & crackle fix"
    echo "    status                  Show audio power_save state"
    echo "    fix, enable             Disable aggressive 1s DAC sleep (eliminates crackle)"
    echo "    revert, disable         Revert audio powersave to default"
    echo ""
    echo "  browser-vaapi, browser    Hardware video acceleration (VA-API) for browsers"
    echo "    status                  Inspect Firefox, Brave, and Chromium VA-API configs"
    echo "    apply, enable           Inject VA-API flags into Firefox user.js and Chromium flags"
    echo "    revert, disable         Revert browser hardware acceleration flags"
    echo ""
    echo "  trim, fstrim              SSD / NVMe periodic TRIM maintenance & health"
    echo "    status                  Inspect fstrim.timer and device I/O schedulers"
    echo "    run                     Run manual TRIM immediately across all filesystems"
    echo "    enable, disable         Manage systemd weekly fstrim.timer"
    echo ""
    echo "  apport, crash-reports     Ubuntu Apport crash error dialogs and dumps"
    echo "    status                  Show Apport enabled/disabled state"
    echo "    disable                 Silence intrusive 'System program problem' popups"
    echo "    enable                  Restore default Apport crash reporting"
    echo "    clean                   Purge /var/crash/ dumps and coredumps"
    echo ""
    echo "  root, root-lock           Root user access hardening (sudo delegation & SSH block)
    status                  Display root password lock, shell & SSH policy
    lock                    Lock root password & block direct SSH root login
    unlock                  Unlock root account (allow direct root password)
    toggle                  Toggle root account lock status

  firewall, ufw             Hardened 1-click laptop UFW firewall shield"
    echo "    status                  Show firewall status and active rules"
    echo "    enable                  Inbound deny, outbound allow, LocalSend & CUPS allowed"
    echo "    disable                 Disable UFW firewall"
    echo ""
    echo "  bluetooth, bt             PipeWire Bluetooth high-fidelity audio codecs"
    echo "    status                  Show installed status of LDAC, AAC, aptX codec package"
    echo "    install                 Install libspa-0.2-bluetooth codec library"
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
    echo "  sudo $0 theme gallery             # Open popular themes gallery & apply uniform styling"
    echo "  sudo $0 network clean-overrides   # Clean network overrides for Cloudflare WARP / VPNs"
    echo "  $0 touchpad gestures              # Optimize GNOME touchpad gestures & tap-to-click"
    echo "  sudo $0 wait-online toggle        # Toggle NetworkManager boot delay on/off"
    echo "  sudo $0 tune bbr toggle           # Toggle Google BBR TCP congestion control"
    echo "  sudo $0 tune zram toggle          # Toggle ZRAM compressed RAM swap"
    echo "  sudo $0 dns apply cloudflare      # Switch to Cloudflare DoH"
    echo "  sudo $0 dns apply 0               # Switch to Auto-Failover pool"
    echo "  sudo $0 dns revert                # Revert back to standard DHCP DNS"
    echo "  sudo $0 privacy                   # Scrub browser caches, recent files & flush DNS"
    echo "  $0 mac status                     # View current vs permanent MAC addresses"
    echo "  sudo $0 mac randomize             # Randomize MAC addresses now"
    echo "  sudo $0 media install             # Install complete multimedia, drivers & fonts suite"
    echo "  sudo $0 media drivers             # Install Mesa RADV Vulkan & VA-API video acceleration"
    echo "  sudo $0 media codecs              # Install Ubuntu restricted codecs & GStreamer"
    echo "  sudo $0 media fonts               # Install Microsoft core fonts & refresh font cache"
    echo "  $0 media verify                   # Test VA-API video decode and Vulkan GPU renderer"
    echo "  sudo $0 update                    # Update all APT, Snap & Flatpak packages and clean up"
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

    epp|amd-pstate|pstate)
        SUB="${1:-status}"
        shift || true
        case "$SUB" in
            status) show_epp_status ;;
            cycle) cycle_epp_preference ;;
            power|balance_power|balance_performance|performance) set_epp_preference "$SUB" ;;
            set) set_epp_preference "${1:-balance_power}" ;;
            *) log_err "Unknown epp option: '$SUB'. Usage: $0 epp [status | power | balance_power | balance_performance | performance | cycle]" ;;
        esac
        ;;

    audio|powersave-audio|audio-powersave)
        ACT="${1:-toggle}"
        case "$ACT" in
            status) echo "Audio Powersave: $(status_get_audio_powersave)" ;;
            fix|enable|on) enable_audio_powersave_fix ;;
            revert|disable|off) revert_audio_powersave_fix ;;
            toggle) toggle_audio_powersave_fix ;;
            *) log_err "Unknown audio action: '$ACT'. Usage: $0 audio [status | fix | revert | toggle]" ;;
        esac
        ;;

    browser-vaapi|browser|vaapi-browser)
        ACT="${1:-toggle}"
        case "$ACT" in
            status) show_browser_vaapi_status ;;
            apply|enable|on) enable_browser_vaapi ;;
            revert|disable|off) revert_browser_vaapi ;;
            toggle) toggle_browser_vaapi ;;
            *) log_err "Unknown browser-vaapi action: '$ACT'. Usage: $0 browser-vaapi [status | apply | revert | toggle]" ;;
        esac
        ;;

    trim|fstrim|ssd)
        ACT="${1:-status}"
        case "$ACT" in
            status) show_storage_trim_status ;;
            run|now) run_fstrim_now ;;
            enable|on) enable_fstrim_timer ;;
            disable|off) disable_fstrim_timer ;;
            toggle) toggle_fstrim_timer ;;
            *) log_err "Unknown trim action: '$ACT'. Usage: $0 trim [status | run | enable | disable | toggle]" ;;
        esac
        ;;

    apport|crash-reports|crash)
        ACT="${1:-status}"
        case "$ACT" in
            status) echo "Apport Crash Popups: $(status_get_apport)" ;;
            disable|off|silence|mask) disable_apport ;;
            enable|on|unmask) enable_apport ;;
            toggle) toggle_apport ;;
            clean|purge) clean_crash_reports ;;
            *) log_err "Unknown apport action: '$ACT'. Usage: $0 apport [status | disable | enable | toggle | clean]" ;;
        esac
        ;;

    root|root-lock|lock-root|root-hardening)
        ACT="${1:-status}"
        case "$ACT" in
            status) show_root_hardening_status ;;
            lock|enable|on) lock_root_user ;;
            unlock|disable|off) unlock_root_user ;;
            toggle) toggle_root_user ;;
            *) log_err "Unknown root action: '$ACT'. Usage: $0 root [status | lock | unlock | toggle]" ;;
        esac
        ;;

    firewall|ufw)
        ACT="${1:-status}"
        case "$ACT" in
            status) show_ufw_status ;;
            enable|on|apply) enable_laptop_firewall ;;
            disable|off|revert) disable_laptop_firewall ;;
            toggle) toggle_laptop_firewall ;;
            *) log_err "Unknown firewall action: '$ACT'. Usage: $0 firewall [status | enable | disable | toggle]" ;;
        esac
        ;;

    bluetooth|bt)
        SUB="${1:-status}"
        case "$SUB" in
            status) show_bluetooth_status ;;
            install|setup) install_bluetooth_codecs ;;
            *) log_err "Unknown bluetooth action: '$SUB'. Usage: $0 bluetooth [status | install]" ;;
        esac
        ;;

    media|multimedia|codecs|drivers|fonts)
        default_sub="status"
        [ "$CMD" = "codecs" ] && default_sub="codecs"
        [ "$CMD" = "fonts" ] && default_sub="fonts"
        [ "$CMD" = "drivers" ] && default_sub="drivers"
        SUB="${1:-$default_sub}"
        shift || true
        case "$SUB" in
            status)
                show_media_driver_status
                ;;
            install|setup|all)
                install_all_media_suite
                ;;
            drivers|vulkan|vaapi)
                install_media_hardware_drivers
                ;;
            codecs)
                install_media_codecs
                ;;
            fonts)
                install_font_packs
                ;;
            verify|test|check)
                verify_hardware_acceleration
                ;;
            i386|32bit)
                ACT="${1:-toggle}"
                case "$ACT" in
                    enable|on) enable_i386_support ;;
                    disable|off) disable_i386_support ;;
                    toggle) toggle_i386_support ;;
                    status)
                        if dpkg --print-foreign-architectures 2>/dev/null | grep -q "i386"; then
                            echo "32-bit (i386) multiarch: ENABLED"
                        else
                            echo "32-bit (i386) multiarch: DISABLED"
                        fi
                        ;;
                    *)
                        log_err "Unknown i386 action: '$ACT'"
                        echo "Usage: $0 media i386 [status | enable | disable | toggle]"
                        exit 1
                        ;;
                esac
                ;;
            menu|interactive|tui)
                interactive_media_menu
                ;;
            *)
                log_err "Unknown media command: '$SUB'"
                echo "Usage: $0 media [status | install | drivers | codecs | fonts | verify | i386 | menu]"
                exit 1
                ;;
        esac
        ;;

    os|platform)
        SUB="${1:-status}"
        shift || true
        case "$SUB" in
            status|get)
                echo "Target OS: $(status_get_target_os)"
                ;;
            detect)
                echo "Detected OS: $(detect_system_os)"
                ;;
            toggle)
                toggle_target_os
                ;;
            ubuntu|ubuntults|ubuntu_lts)
                set_target_os "ubuntu"
                ;;
            pop|popos|pop_os)
                set_target_os "popos"
                ;;
            mint|linuxmint)
                set_target_os "mint"
                ;;
            reset|auto)
                set_target_os "detect"
                ;;
            *)
                log_err "Unknown OS command: '$SUB'. Usage: $0 os [status | toggle | ubuntu | popos | mint | detect]"
                exit 1
                ;;
        esac
        ;;

    theme|themes|appearance)
        SUB="${1:-gallery}"
        shift || true
        case "$SUB" in
            gallery|list|show|menu)
                if [ -t 0 ]; then
                    interactive_theme_menu
                else
                    show_theme_gallery
                fi
                ;;
            apply|set)
                if [ $# -lt 1 ]; then
                    show_theme_gallery
                else
                    apply_uniform_theme "$1"
                fi
                ;;
            install|get)
                if [ $# -lt 1 ]; then
                    show_theme_gallery
                else
                    install_gallery_theme "$1"
                fi
                ;;
            reset|default|restore)
                reset_uniform_theme
                ;;
            status)
                echo "Uniform Theme Status: $(status_get_uniform_theme)"
                ;;
            *)
                log_err "Unknown theme command: '$SUB'"
                echo "Usage: $0 theme [gallery | apply <theme_id> | install <theme_id> | reset | status]"
                exit 1
                ;;
        esac
        ;;

    network|net)
        SUB="${1:-clean-overrides}"
        shift || true
        case "$SUB" in
            clean|clean-overrides|clear|reset)
                clean_network_overrides
                ;;
            status)
                echo "Network Status:"
                echo "  • TCP Congestion Control : $(status_get_bbr)"
                echo "  • DHCP Hostname Privacy  : $(status_get_dhcp)"
                echo "  • MAC Randomization      : $(status_get_mac)"
                echo "  • System DNS Mode        : $(status_get_dns)"
                ;;
            *)
                log_err "Unknown network command: '$SUB'. Usage: $0 network [clean-overrides | status]"
                exit 1
                ;;
        esac
        ;;

    ssh|sshd)
        ACT="${1:-toggle}"
        case "$ACT" in
            toggle) toggle_ssh_hardening ;;
            enable|on|mask) enable_ssh_hardening ;;
            disable|off|unmask) disable_ssh_hardening ;;
            status) echo "SSH Inbound Server: $(status_get_ssh_server)" ;;
            *) log_err "Unknown ssh action: '$ACT'"; exit 1 ;;
        esac
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
            hosts|fix-hosts)
                ensure_hostname_resolution
                ;;
            *)
                apply_dns_profile "$SUB"
                ;;
        esac
        ;;

    grub|bootloader)
        SUB="${1:-status}"
        shift || true
        case "$SUB" in
            status)
                show_grub_status
                ;;
            fix|repair|restore)
                fix_grub_menu
                ;;
            *)
                log_err "Unknown grub command: '$SUB'"
                echo "Usage: $0 grub [status | fix]"
                exit 1
                ;;
        esac
        ;;

    touchpad|elan|trackpad)
        SUB="${1:-status}"
        shift || true
        case "$SUB" in
            status)
                show_touchpad_status
                ;;
            auto|smart)
                smart_touchpad_autotune
                ;;
            apply|enable|install|on)
                install_touchpad_permanent
                ;;
            revert|disable|uninstall|off)
                revert_touchpad
                ;;
            runtime)
                apply_touchpad_runtime
                ;;
            cstate)
                ACT="${1:-status}"
                case "$ACT" in
                    status)
                        show_touchpad_cstate_status
                        ;;
                    apply|enable|on)
                        apply_touchpad_cstate_cap
                        ;;
                    revert|disable|off)
                        remove_touchpad_cstate_cap
                        ;;
                    toggle)
                        toggle_touchpad_cstate_cap
                        ;;
                    *)
                        log_err "Unknown cstate action: '$ACT'"
                        echo "Usage: $0 touchpad cstate [status | enable | disable | toggle]"
                        exit 1
                        ;;
                esac
                ;;
            psr)
                ACT="${1:-status}"
                case "$ACT" in
                    status)
                        show_touchpad_psr_status
                        ;;
                    apply|enable|on)
                        apply_touchpad_psr_fix
                        ;;
                    revert|disable|off)
                        remove_touchpad_psr_fix
                        ;;
                    toggle)
                        toggle_touchpad_psr_fix
                        ;;
                    *)
                        log_err "Unknown psr action: '$ACT'"
                        echo "Usage: $0 touchpad psr [status | enable | disable | toggle]"
                        exit 1
                        ;;
                esac
                ;;
            quirks)
                ACT="${1:-status}"
                case "$ACT" in
                    status)
                        show_touchpad_quirks_status
                        ;;
                    apply|enable|on)
                        apply_touchpad_quirks
                        ;;
                    revert|disable|off)
                        remove_touchpad_quirks
                        ;;
                    toggle)
                        toggle_touchpad_quirks
                        ;;
                    *)
                        log_err "Unknown quirks action: '$ACT'"
                        echo "Usage: $0 touchpad quirks [status | enable | disable | toggle]"
                        exit 1
                        ;;
                esac
                ;;
            fix-stutter|stutter|fix)
                fix_touchpad_stutter
                ;;
            gestures|gnome)
                tune_gnome_touchpad
                ;;
            dwt|typing)
                D_ACT="${1:-status}"
                case "$D_ACT" in
                    status)
                        show_touchpad_dwt_status
                        ;;
                    enable|on)
                        enable_touchpad_dwt
                        ;;
                    disable|off)
                        disable_touchpad_dwt
                        ;;
                    toggle)
                        toggle_touchpad_dwt
                        ;;
                    *)
                        log_err "Unknown dwt action: '$D_ACT'"
                        echo "Usage: $0 touchpad dwt [status | enable | disable | toggle]"
                        exit 1
                        ;;
                esac
                ;;
            evdi|displaylink)
                E_ACT="${1:-status}"
                shift || true
                case "$E_ACT" in
                    status)
                        show_evdi_status
                        ;;
                    fix|disable|off)
                        fix_evdi_boot_hijack
                        ;;
                    restore|enable|on)
                        restore_evdi_boot_hijack
                        ;;
                    toggle)
                        toggle_evdi_boot_hijack
                        ;;
                    *)
                        log_err "Unknown evdi action: '$E_ACT'"
                        echo "Usage: $0 touchpad evdi [status | fix | restore | toggle]"
                        exit 1
                        ;;
                esac
                ;;
            speed|acpi|frequency)
                S_ACT="${1:-status}"
                case "$S_ACT" in
                    status)
                        show_touchpad_acpi_status
                        ;;
                    100*|enable|on|force)
                        apply_touchpad_acpi_100khz
                        ;;
                    400*|disable|off|revert|default)
                        remove_touchpad_acpi_100khz
                        ;;
                    toggle)
                        toggle_touchpad_acpi_100khz
                        ;;
                    *)
                        log_err "Unknown speed action: '$S_ACT'"
                        echo "Usage: $0 touchpad speed [status | 100khz | 400khz | toggle]"
                        exit 1
                        ;;
                esac
                ;;
            tap-drag|tapdrag|drag)
                TD_ACT="${1:-status}"
                case "$TD_ACT" in
                    status)
                        show_touchpad_tap_drag_status
                        ;;
                    enable|on)
                        enable_touchpad_tap_drag
                        ;;
                    disable|off)
                        disable_touchpad_tap_drag
                        ;;
                    toggle)
                        toggle_touchpad_tap_drag
                        ;;
                    *)
                        log_err "Unknown tap-drag action: '$TD_ACT'"
                        echo "Usage: $0 touchpad tap-drag [status | enable | disable | toggle]"
                        exit 1
                        ;;
                esac
                ;;
            accel|acceleration|profile)
                A_ACT="${1:-status}"
                case "$A_ACT" in
                    status)
                        show_touchpad_accel_profile_status
                        ;;
                    flat)
                        set_touchpad_accel_profile "flat"
                        ;;
                    adaptive)
                        set_touchpad_accel_profile "adaptive"
                        ;;
                    default)
                        set_touchpad_accel_profile "default"
                        ;;
                    toggle)
                        toggle_touchpad_accel_profile
                        ;;
                    *)
                        log_err "Unknown accel action: '$A_ACT'"
                        echo "Usage: $0 touchpad accel [status | flat | adaptive | default | toggle]"
                        exit 1
                        ;;
                esac
                ;;
            diagnose)
                run_touchpad_diagnostics "$@"
                ;;
            menu|interactive|tui)
                interactive_touchpad_menu
                ;;
            *)
                log_err "Unknown touchpad command: '$SUB'"
                echo "Usage: $0 touchpad [status | install | revert | fix-stutter | runtime | cstate | psr | quirks | speed | tap-drag | accel | evdi | dwt | gestures | diagnose | menu]"
                exit 1
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
            touchpad|elan|trackpad)
                ACT="${1:-status}"
                shift || true
                case "$ACT" in
                    toggle)
                        if [[ "$(status_get_touchpad)" =~ OPTIMIZED ]]; then
                            revert_touchpad
                        else
                            install_touchpad_permanent
                        fi
                        ;;
                    auto|smart) smart_touchpad_autotune ;;
                    enable|install|on) install_touchpad_permanent ;;
                    disable|revert|off) revert_touchpad ;;
                    runtime) apply_touchpad_runtime ;;
                    status) show_touchpad_status ;;
                    cstate)
                        C_ACT="${1:-status}"
                        case "$C_ACT" in
                            status) show_touchpad_cstate_status ;;
                            toggle) toggle_touchpad_cstate_cap ;;
                            enable|on|apply) apply_touchpad_cstate_cap ;;
                            disable|off|revert) remove_touchpad_cstate_cap ;;
                            *) log_err "Unknown cstate action: '$C_ACT'"; exit 1 ;;
                        esac
                        ;;
                    psr)
                        P_ACT="${1:-status}"
                        case "$P_ACT" in
                            status) show_touchpad_psr_status ;;
                            toggle) toggle_touchpad_psr_fix ;;
                            enable|on|apply) apply_touchpad_psr_fix ;;
                            disable|off|revert) remove_touchpad_psr_fix ;;
                            *) log_err "Unknown psr action: '$P_ACT'"; exit 1 ;;
                        esac
                        ;;
                    quirks)
                        Q_ACT="${1:-status}"
                        case "$Q_ACT" in
                            status) show_touchpad_quirks_status ;;
                            toggle) toggle_touchpad_quirks ;;
                            enable|on|apply) apply_touchpad_quirks ;;
                            disable|off|revert) remove_touchpad_quirks ;;
                            *) log_err "Unknown quirks action: '$Q_ACT'"; exit 1 ;;
                        esac
                        ;;
                    fix-stutter|stutter|fix)
                        fix_touchpad_stutter
                        ;;
                    dwt|typing)
                        D_ACT="${1:-status}"
                        case "$D_ACT" in
                            status) show_touchpad_dwt_status ;;
                            toggle) toggle_touchpad_dwt ;;
                            enable|on) enable_touchpad_dwt ;;
                            disable|off) disable_touchpad_dwt ;;
                            *) log_err "Unknown dwt action: '$D_ACT'"; exit 1 ;;
                        esac
                        ;;
                    gestures|gnome)
                        tune_gnome_touchpad
                        ;;
                    evdi|displaylink)
                        E_ACT="${1:-status}"
                        case "$E_ACT" in
                            status) show_evdi_status ;;
                            fix|disable|off) fix_evdi_boot_hijack ;;
                            restore|enable|on) restore_evdi_boot_hijack ;;
                            toggle) toggle_evdi_boot_hijack ;;
                            *) log_err "Unknown evdi action: '$E_ACT'"; exit 1 ;;
                        esac
                        ;;
                    speed|acpi|frequency)
                        S_ACT="${1:-status}"
                        case "$S_ACT" in
                            status) show_touchpad_acpi_status ;;
                            100*|enable|on|force) apply_touchpad_acpi_100khz ;;
                            400*|disable|off|revert|default) remove_touchpad_acpi_100khz ;;
                            toggle) toggle_touchpad_acpi_100khz ;;
                            *) log_err "Unknown speed action: '$S_ACT'"; exit 1 ;;
                        esac
                        ;;
                    tap-drag|tapdrag|drag)
                        TD_ACT="${1:-status}"
                        case "$TD_ACT" in
                            status) show_touchpad_tap_drag_status ;;
                            toggle) toggle_touchpad_tap_drag ;;
                            enable|on) enable_touchpad_tap_drag ;;
                            disable|off) disable_touchpad_tap_drag ;;
                            *) log_err "Unknown tap-drag action: '$TD_ACT'"; exit 1 ;;
                        esac
                        ;;
                    accel|acceleration|profile)
                        A_ACT="${1:-status}"
                        case "$A_ACT" in
                            status) show_touchpad_accel_profile_status ;;
                            flat) set_touchpad_accel_profile "flat" ;;
                            adaptive) set_touchpad_accel_profile "adaptive" ;;
                            default) set_touchpad_accel_profile "default" ;;
                            toggle) toggle_touchpad_accel_profile ;;
                            *) log_err "Unknown accel action: '$A_ACT'"; exit 1 ;;
                        esac
                        ;;
                    *) log_err "Unknown touchpad action: '$ACT'"; exit 1 ;;
                esac
                ;;
            evdi|displaylink)
                ACT="${1:-status}"
                case "$ACT" in
                    status) show_evdi_status ;;
                    fix|disable|off) fix_evdi_boot_hijack ;;
                    restore|enable|on) restore_evdi_boot_hijack ;;
                    toggle) toggle_evdi_boot_hijack ;;
                    *) log_err "Unknown evdi action: '$ACT'"; exit 1 ;;
                esac
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
            hosts|fix-hosts)
                ensure_hostname_resolution
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
            os|platform)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_target_os ;;
                    pop|popos) set_target_os "popos" ;;
                    mint) set_target_os "mint" ;;
                    status) echo "Target OS: $(status_get_target_os)" ;;
                    *) log_err "Unknown os action: '$ACT'"; exit 1 ;;
                esac
                ;;
            ssh|sshd)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_ssh_hardening ;;
                    enable|on|mask) enable_ssh_hardening ;;
                    disable|off|unmask) disable_ssh_hardening ;;
                    status) echo "SSH Inbound Server: $(status_get_ssh_server)" ;;
                    *) log_err "Unknown ssh action: '$ACT'"; exit 1 ;;
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
            antiblur|blur|font)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_font_antiblur ;;
                    enable|on) enable_font_antiblur ;;
                    disable|off) disable_font_antiblur ;;
                    status) echo "Font Anti-Blur: $(status_get_font_antiblur)" ;;
                    *) log_err "Unknown antiblur action: '$ACT'"; exit 1 ;;
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
            epp|amd-pstate)
                ACT="${1:-status}"
                case "$ACT" in
                    status) show_epp_status ;;
                    cycle) cycle_epp_preference ;;
                    power|balance_power|balance_performance|performance) set_epp_preference "$ACT" ;;
                    *) set_epp_preference "$ACT" ;;
                esac
                ;;
            audio|audio-powersave)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_audio_powersave_fix ;;
                    fix|enable|on) enable_audio_powersave_fix ;;
                    revert|disable|off) revert_audio_powersave_fix ;;
                    status) echo "Audio Powersave: $(status_get_audio_powersave)" ;;
                    *) log_err "Unknown audio action: '$ACT'"; exit 1 ;;
                esac
                ;;
            apport|crash)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_apport ;;
                    disable|off) disable_apport ;;
                    enable|on) enable_apport ;;
                    clean|purge) clean_crash_reports ;;
                    status) echo "Apport Crash Popups: $(status_get_apport)" ;;
                    *) log_err "Unknown apport action: '$ACT'"; exit 1 ;;
                esac
                ;;
            trim|fstrim)
                ACT="${1:-status}"
                case "$ACT" in
                    status) show_storage_trim_status ;;
                    run|now) run_fstrim_now ;;
                    toggle) toggle_fstrim_timer ;;
                    enable|on) enable_fstrim_timer ;;
                    disable|off) disable_fstrim_timer ;;
                    *) log_err "Unknown trim action: '$ACT'"; exit 1 ;;
                esac
                ;;
            root|root-lock)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_root_user ;;
                    lock|enable|on) lock_root_user ;;
                    unlock|disable|off) unlock_root_user ;;
                    status) show_root_hardening_status ;;
                    *) log_err "Unknown root action: '$ACT'"; exit 1 ;;
                esac
                ;;

            firewall|ufw)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_laptop_firewall ;;
                    enable|on) enable_laptop_firewall ;;
                    disable|off) disable_laptop_firewall ;;
                    status) show_ufw_status ;;
                    *) log_err "Unknown firewall action: '$ACT'"; exit 1 ;;
                esac
                ;;
            browser|browser-vaapi)
                ACT="${1:-toggle}"
                case "$ACT" in
                    toggle) toggle_browser_vaapi ;;
                    enable|apply|on) enable_browser_vaapi ;;
                    disable|revert|off) revert_browser_vaapi ;;
                    status) show_browser_vaapi_status ;;
                    *) log_err "Unknown browser action: '$ACT'"; exit 1 ;;
                esac
                ;;
            bluetooth|bt)
                SUB_ACT="${1:-status}"
                case "$SUB_ACT" in
                    status) show_bluetooth_status ;;
                    install|setup) install_bluetooth_codecs ;;
                    *) log_err "Unknown bluetooth action: '$SUB_ACT'"; exit 1 ;;
                esac
                ;;
            *)
                log_err "Unknown tune command: '$SUB'"
                echo "Usage: $0 tune [status | menu | apply | revert | wait-online | bbr | swappiness | zram | dhcp | kernel | avahi | cups | modem | antiblur | daemons | epp | audio | apport | trim | firewall | browser | bluetooth]"
                exit 1
                ;;
        esac
        ;;

    antiblur|blur|font-blur)
        ACT="${1:-toggle}"
        case "$ACT" in
            toggle) toggle_font_antiblur ;;
            enable|on) enable_font_antiblur ;;
            disable|off) disable_font_antiblur ;;
            status) echo "Font Anti-Blur: $(status_get_font_antiblur)" ;;
            *) log_err "Unknown antiblur action: '$ACT'"; exit 1 ;;
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
        echo "Laptop Linux Optimizer (laptop-linux-optimiser) v${VERSION}"
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
