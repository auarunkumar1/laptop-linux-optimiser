# Laptop Linux Optimizer (`laptop-linux-optimiser`)

[![Release](https://img.shields.io/badge/version-v0.1.0-blue.svg)](https://github.com/auarunkumar1/laptop-linux-optimiser/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20Mint%20%7C%20Ubuntu%20%7C%20Debian-lightgrey.svg)]()
[![Shell](https://img.shields.io/badge/shell-bash%20%3E%3D%204.4-brightgreen.svg)]()

**Laptop Linux Optimizer** is an all-in-one performance tuning, battery lifespan management, encrypted DNS, MAC spoofing, and privacy scrubbing administration suite for Linux laptops (optimized for Linux Mint, Ubuntu, and Debian-based systems).

---

## Key Features

| Category | Capability | Description |
|---|---|---|
| 🔋 **Battery Lifespan** | **Hardware Charge Limiter** | Caps charge at **60%**, **80%**, or **100%** on supported laptops (ASUS & standard `BAT*` controllers). Persists across reboots, wake from sleep, and AC adapter plug/unplug events without event loops. |
| ⚡ **Performance & RAM** | **ZRAM & TCP BBR** | Deploys 50% RAM compressed swap (`zstd` algorithm) with balanced swappiness (`vm.swappiness = 100`), optimal for 16GB laptops. Enables Google TCP BBR congestion control and fast boot optimizations. |
| 🛡️ **Encrypted DNS** | **DoH, Relays & Tor** | Configures `dnscrypt-proxy` with 14 profiles: Auto-Failover pool, Cloudflare, Quad9, AdGuard, LibreDNS, Anonymized Multi-Hop Relays, and Tor onion routing. Eliminates DNS fallback leaks. |
| 🕵️ **MAC Spoofing** | **Hardware Randomization** | Generates cryptographically strong random MACs via `/dev/urandom`. Automatically detects and protects active SSH connections and default gateways from drops. Excludes virtual/container interfaces (`docker`, `br-*`, `tailscale`, `wg`). |
| 🧹 **Privacy Scrubbing** | **Hardened Cache Purge** | Symlink-attack-immune cleanup of browser caches (Firefox, Chrome, Brave, Vivaldi), recent document histories (`recently-used.xbel`), thumbnails, trash bins, crash logs, and `dnscrypt-proxy` query logs. |
| 📦 **Housekeeping** | **Package & System Sweep** | APT update & `dist-upgrade` with non-interactive conffile protection, Flatpak system/user runtime cleanup, systemd journal rotation/vacuuming, and residual package (`rc`) purging. |
| ⏱️ **Automation** | **Weekly Systemd Timer** | Automated weekly background maintenance schedule executing in-place with space-safe quoting and privilege safety checks. |
| 🖥️ **Terminal UI** | **Interactive Menu** | Rich terminal dashboard with confirmation safeguards for destructive actions, plus full CLI support for non-interactive scripting (`-y` / `--yes`). |

---

## Requirements

- **Operating System**: Linux Mint 21+, Ubuntu 22.04+, Debian 12+, or derivatives
- **Shell**: Bash 4.4+
- **Privileges**: Root / sudo access for configuration and hardware operations
- **Optional Dependencies** (automatically installed or detected when needed):
  - `dnscrypt-proxy`, `dnsutils` (for Encrypted DNS)
  - `tor` (for DNS over Tor)
  - `zram-tools` (for ZRAM compressed memory swap)
  - `flatpak` (for Flatpak application updates and maintenance)
  - `ethtool`, `iproute2`, `network-manager` (for MAC address spoofing)

---

## Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/auarunkumar1/laptop-linux-optimiser.git
cd laptop-linux-optimiser
chmod +x mint-admin.sh
```

### 2. Run the Guided Setup Wizard (Recommended)
Guide through all laptop optimizations one by one in the correct logical sequence:
```bash
sudo ./laptop-optimizer.sh wizard
```

### 3. Or Launch the Interactive Dashboard
```bash
./laptop-optimizer.sh
# or using:
./mint-admin.sh
```

### 4. Non-Destructive System Status Checks
```bash
./laptop-optimizer.sh battery status    # Inspect battery health, cycles & charge limit
./laptop-optimizer.sh mac status        # Inspect physical interfaces & MAC addresses
./laptop-optimizer.sh dns status        # View active encrypted DNS resolvers
./laptop-optimizer.sh tune status       # View BBR, ZRAM, swappiness & privacy sysctls
./laptop-optimizer.sh ipv6 status       # Check IPv6 network status
```

---

## Recommended Order of Operations

When optimizing a new laptop or performing maintenance, the script guides you through the operations in this optimal sequence:

1. **System & Package Updates (`update`)**: Updates repository lists, upgrades APT & Flatpak packages, and cleans orphaned dependencies first so all system libraries and drivers are current.
2. **Battery Diagnostics & Limiter (`battery`)**: Sets and persists an 80% charge threshold to minimize chemical stress and extend laptop battery longevity.
3. **Encrypted DNS Manager (`dns`)**: Configures `dnscrypt-proxy` with your chosen profile (defaults to `[0] Auto-Failover Pool`) and enables DNS leak protection in `systemd-resolved`.
4. **Performance & ZRAM Tuning (`tune`)**: Deploys Google TCP BBR, ZRAM compressed swap (50% RAM with `zstd`), swappiness 100 (balanced for 16GB laptops), and DHCP hostname privacy.
5. **Privacy & Activity Scrub (`privacy`)**: Flushes DNS caches, purges browser caches, resets recent document history (`recently-used.xbel`), and clears `dnscrypt-proxy` query logs.
6. **Reboot Advisory**: Because kernel sysctls, ZRAM swap devices, and systemd network drop-ins were installed, a system reboot is recommended at the end to ensure clean startup.

---

## Command Reference

### Guided Optimization Wizard
```bash
# Run the interactive 5-step guided wizard
sudo ./laptop-optimizer.sh wizard
```

### Battery Management
```bash
# View battery health, cycle count, and current charge limit
./mint-admin.sh battery status

# Temporarily set battery threshold (e.g. 80% for everyday longevity)
sudo ./mint-admin.sh battery set 80

# Persist battery threshold across reboots, sleep/wake, and AC plug events
sudo ./mint-admin.sh battery install 80

# Uninstall persistence service and restore 100% charge limit
sudo ./mint-admin.sh battery uninstall
```

### System Performance & Kernel Tuning
```bash
# Check current tuning status
./mint-admin.sh tune status

# Apply TCP BBR, ZRAM (50% RAM, zstd), Swappiness 100, and DHCP privacy
# (Prompts before disabling broadcast daemons like cups-browsed / avahi)
sudo ./mint-admin.sh tune apply

# Apply non-interactively with --yes
sudo ./mint-admin.sh tune apply --yes

# Revert all sysctls and services back to initial distro baseline defaults
sudo ./mint-admin.sh tune revert
```

### Encrypted DNS (`dnscrypt-proxy`)
```bash
# Open interactive encrypted DNS selector menu
sudo ./mint-admin.sh dns menu

# View current active resolver configuration
./mint-admin.sh dns status

# Apply specific profile by index or name:
sudo ./mint-admin.sh dns apply 0            # Auto-Failover pool (Quad9 + Cloudflare + AdGuard)
sudo ./mint-admin.sh dns apply cloudflare   # Cloudflare Anycast DoH
sudo ./mint-admin.sh dns apply quad9        # Quad9 Malware-blocking DoH
sudo ./mint-admin.sh dns apply adguard      # AdGuard Ad & Tracker blocking DoH
sudo ./mint-admin.sh dns apply 8            # Cloudflare via Anonymized Multi-Hop Relays
sudo ./mint-admin.sh dns apply 11           # Quad9 routed over 3-hop Tor Onion circuits

# Revert DNS back to standard system DHCP / NetworkManager
sudo ./mint-admin.sh dns revert
```

### MAC Randomization & Network Privacy
```bash
# View current vs permanent hardware MAC addresses
./mint-admin.sh mac status

# Randomize MAC addresses on demand (protects active SSH connections)
sudo ./mint-admin.sh mac randomize

# Enable persistent MAC randomization in NetworkManager (randomizes on connect and scan)
sudo ./mint-admin.sh mac enable

# Disable persistent MAC randomization
sudo ./mint-admin.sh mac disable
```

### System Housekeeping & Updates
```bash
# Routine housekeeping: APT cache clean, Flatpak unused runtimes, journal vacuuming
sudo ./mint-admin.sh optimize

# Update APT & Flatpak packages and purge orphans
sudo ./mint-admin.sh update

# Full update + deep housekeeping
sudo ./mint-admin.sh all

# Complete Master Suite (Update + Housekeep + Privacy Scrub + MAC Randomize)
sudo ./mint-admin.sh full-suite
```

### Privacy Scrubbing
```bash
# Scrub browser caches, recent files, thumbnail previews, crash logs, and DNS query logs
sudo ./mint-admin.sh privacy
```

### Weekly Automated Maintenance Timer
```bash
# Check weekly timer status and last run log
./mint-admin.sh timer status

# Install systemd weekly maintenance timer (runs Sundays at 3:00 AM)
sudo ./mint-admin.sh timer install

# Remove weekly maintenance timer
sudo ./mint-admin.sh timer uninstall
```

---

## Security & Architecture

The script has undergone comprehensive vulnerability auditing and validation:

1. **Root Symlink Traversal Protection**: All file removal and history resets in `clean_privacy()` verify paths with strict symlink refusal (`[ ! -L "$path" ]`), atomic temp-file creation with `chown --no-dereference`, and non-dereferencing removals.
2. **Systemd Unit Quoting & Hardening**: `ExecStart` and documentation URLs are strictly quoted to prevent argument-splitting vulnerabilities on paths with spaces.
3. **Session Interruption Prevention**: Network interface cycling detects active SSH sessions (`$SSH_CONNECTION`) and default route carriers to prevent disconnecting remote sessions.
4. **State Baseline Capture**: Initial sysctl values and service states are captured into `/var/lib/mint-admin/tuning-baseline.env` prior to modification, ensuring `tune revert` accurately restores the machine to its exact prior state.
5. **No Event-Looping Udev Rules**: Battery udev rules trigger specifically on `ATTR{type}=="Mains"` and read the threshold before writing, avoiding recursive uevent storms.

---

## Running the Automated Test Suite

A standalone test suite is included in `tests/test_audit_fixes.sh` to verify security and logic integrity:

```bash
./tests/test_audit_fixes.sh
```

Tests cover:
- MAC address formatting, unicast prefix (`02:`), and `/dev/urandom` entropy
- Virtual interface filter exclusion
- `dnscrypt-proxy.toml` syntax check with top-level Tor configuration
- Symlink attack immunity on files, directories, and trash bins
- Non-TTY stdin handling and usage display
- Battery udev rule format and event comparison
- Systemd timer `ExecStart` path quoting

---

## License

This project is licensed under the [MIT License](LICENSE) - see the `LICENSE` file for details.
Copyright (c) 2026 Arun Kumar.
