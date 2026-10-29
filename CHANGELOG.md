# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.0] - 2026-10-29

### Added
- **Initial Release** of Laptop Linux Optimizer (`laptop-linux-optimiser`).
- **5-Step Guided Laptop Optimization Wizard (`wizard` / `guided`)**:
  - Step-by-step interactive optimization in the optimal logical sequence:
    1. System & Package Updates (base system & runtimes first)
    2. Battery Diagnostics & Charge Threshold (80% default for longevity)
    3. Encrypted DNS Manager (dnscrypt-proxy integration)
    4. Performance & ZRAM Tuning (TCP BBR, swappiness 100, ZRAM 50%)
    5. Privacy Scrubbing (browser caches, recent documents, DNS logs)
  - Final post-setup summary and system reboot advisory.
- **Enhanced DNS Profile Selector UI**:
  - Shows current active DNS resolver status at a glance.
  - Logical categorization into High Availability, Fast Anycast, Ad/Tracker Blocking, Multi-Hop Relays, and Tor Onion Circuits.
  - Interactive default prompt to `[0] Auto-Failover Pool` on Enter.
  - Seamless interactive fallback if `dns apply` is called without arguments.
- **Reorganized Master Interactive Menu**:
  - Restructured dashboard grouping operations in logical execution order with Guided Wizard as Option 1.
- **Battery Diagnostics & Hardware Charge Limiter**:
  - Support for 60% (desktop/AC plugged), 80% (balanced everyday longevity), and 100% (travel/maximum runtime) thresholds.
  - Multi-vector persistence across reboots, wake from sleep, and AC adapter plug/unplug events.
  - Correct health computation distinguishing `Wh` and `mAh` via battery voltage.
- **Encrypted DNS Manager (`dnscrypt-proxy`)**:
  - 14 DNS profiles including Auto-Failover pool, Cloudflare, Quad9, AdGuard, LibreDNS, Anonymized Multi-Hop Relays, and DNS over Tor.
  - Integration with `systemd-resolved` with `FallbackDNS=` set to prevent silent DNS fallback leaks.
- **Hardware MAC Randomization & Spoofing**:
  - Cryptographically strong random MAC generation using `/dev/urandom`.
  - Smart session protection: checks `$SSH_CONNECTION` and default gateway interface before bouncing connections.
  - Automatic exclusion of virtual and container network interfaces (`docker`, `br-*`, `veth`, `virbr`, `tailscale`, `wg`, `bond`, `team`).
- **System Performance & Kernel Tuning**:
  - Google TCP BBR congestion control and `fq` qdisc.
  - ZRAM compressed RAM swap (50% RAM with `zstd` compression).
  - Balanced swappiness (`vm.swappiness = 100`) tuned specifically for 16GB laptops with ZRAM.
  - NetworkManager DHCP hostname privacy to stop broadcasting laptop hostnames on Wi-Fi networks.
  - Kernel memory privacy hardening (`dmesg_restrict=1`, `kptr_restrict=2`, `unprivileged_bpf_disabled=1`).
  - Pre-modification baseline capture to `/var/lib/mint-admin/tuning-baseline.env` for 100% accurate revert.
- **Privacy & Activity Scrubbing**:
  - Clean browser caches for Firefox, Google Chrome, Chromium, Brave, and Vivaldi.
  - Reset recent documents history (`recently-used.xbel`).
  - Purge image preview thumbnails, system trash bins, crash logs, and `dnscrypt-proxy` query logs.
- **Automated Housekeeping & Timers**:
  - APT cache cleaning, `dist-upgrade` with `--force-confold` protection against blocking conffile prompts.
  - Flatpak runtime cleanups and system repair.
  - Systemd journal rotation and vacuuming (7 days / 100MB).
  - Weekly systemd maintenance timer running Sundays at 3:00 AM.
- **Interactive Terminal Dashboard & CLI**:
  - Interactive menu with confirmation safeguards before running destructive operations.
  - Non-TTY stdin detection for automated scripts and pipelines.
  - `-y` / `--yes` / `--force` flags for scripted execution.
  - `version` / `-v` / `--version` command support.
- **Automated Verification Test Suite**:
  - Comprehensive unit and regression test suite in `tests/test_audit_fixes.sh`.
- **Licensing**:
  - Licensed under the permissive MIT License.

### Security & Hardening
- **Root Symlink Traversal Protection**: Hardened all privacy scrub routines against local symlink attacks targeting user cache, thumbnails, trash, and recent-activity files.
- **Systemd Unit Quoting**: Quoted `ExecStart="$SCRIPT_PATH"` and unit documentation to prevent argument-splitting vulnerabilities on paths with spaces.
- **Udev Event Loop Elimination**: Battery udev rules trigger specifically on `ATTR{type}=="Mains"` with threshold pre-check to eliminate recursive uevent write storms.
- **TOML Top-Level Directive Insertion**: Fixed Tor proxy directives placement in `dnscrypt-proxy.toml` to prevent table corruption and fatal configuration check errors.
- **True Resolution Verification**: Validated DNS resolution through actual A-record address extraction across both local proxy (`127.0.2.1`) and system-wide resolver.
- **Loopback IPv6 Preservation**: Ensured loopback (`lo`) IPv6 binding (`::1`) remains active when system-wide IPv6 is disabled to avoid breaking local services.

### Fixed
- **Network Printer & Discovery Daemon Safeguards**:
  - Background discovery services (`avahi-daemon`, `cups-browsed`) now default to **safe/enabled** (`disable_services=0`), preventing unintended shutdown during non-interactive, scripted, or default wizard runs.
  - Added warning banner in system tuning and guided wizard clarifying that disabling `avahi-daemon` prevents mDNS (`.local`) hostname resolution and breaks dynamically discovered (`dnssd://`) network printers.
