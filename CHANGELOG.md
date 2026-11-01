# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.2.0] - 2026-11-01

### Added
- **Interactive Terminal User Interface (TUI) Dashboard**:
  - Full-screen high-contrast terminal user interface (`show_tui_dashboard()`) displaying real-time system and hardware status indicators.
  - Live indicators for **Active Preset**, **Battery Charge Limiter & State**, **ZRAM Compressed Swap**, **TCP BBR**, **Encrypted DNS**, **MAC Randomization**, **Weekly Timer**, and **IPv6 Stack**.
  - Proactive system maintenance advisory: dynamically checks for pending APT/Flatpak package updates and cleanable storage footprint, prompting user with quick one-key actions (`[U]` to update, `[C]` to sweep).
  - Modal GUI dialog mode via `whiptail` / `dialog` (`[D]` key or `mint-admin tui --dialog`).
  - Isolated action runner (`run_menu_action`) to protect TUI session from termination if underlying subcommands return non-zero.
- **Profile Presets Management (`mint-admin preset`)**:
  - One-click profile preset switching between **Desk / AC Docked** (60% battery threshold + BBR + ZRAM), **Balanced Daily** (80% battery threshold + BBR + ZRAM), **Travel / Mobile** (100% full capacity), and **Custom**.
  - Persistent profile tracking in `/etc/mint-admin-profile.conf`.
  - CLI commands: `mint-admin preset [status | apply <desk|balanced|travel> | desk | balanced | travel]`.
  - Integrated preset selection directly into TUI and Guided Optimization Wizard.
- **System Maintenance Advisory CLI (`mint-admin check`)**:
  - Instant inspection of pending package updates and cleanable cache storage.

### Fixed & Hardened (Audit Findings)
- **Zero-Argument Argument Parsing Regression**:
  - Fixed `for arg in "${@:-}"` bug where an empty invocation expanded to a single empty string `""`, causing spurious `Unknown command: ''` failures. Corrected to native `for arg in "$@"`.
- **Systemd Timer Privilege Escalation Hardening**:
  - In `install_weekly_timer()`, prevented running user-writable scripts under root by copying/installing root-owned canonical binary to `/usr/local/sbin/mint-admin` (mode 0755, `root:root`) if invoked from a non-root or home directory.
  - Properly quoted `Documentation` URL file paths to prevent space-path unit parsing errors.
- **User Cache Symlink Protection**:
  - Hardened `clean_user_cache()` against directory symlink attacks across user homes (`/root /home/*`), requiring directory verification (`! -L`) and `-type f ! -type l` file deletion matching `clean_privacy()`.
- **Root Filesystem Space Metric Consistency**:
  - Standardized free-space metric gathering across `run_optimizer()`, `update_and_clean()`, and `run_full_update_and_optimizer()` using `df -k / 2>/dev/null | awk 'END {print $4}'` with numeric fallback guards.
- **Package Purge Safety in `clean_apt()`**:
  - Piped residual package lists into `xargs -r dpkg --purge` to prevent word-splitting and command length limit issues.
- **ZRAM Device Release on Tuning Revert**:
  - Enhanced `revert_system_tuning()` to explicitly execute `swapoff /dev/zram*` and `zramctl --reset` to ensure memory is released back to the operating system.
- **Test Suite Expansion**:
  - Expanded test suite from 26 to 49 tests in `tests/test_audit_fixes.sh`, adding test coverage for presets, TUI dashboard, system status checks, canonical path installation, and cache symlink protection.
- **IPv6 Protocol Control & Instant Toggle**:
  - Implemented `toggle_ipv6()` with automatic state detection, allowing 1-click toggling between enabled and disabled (with loopback `::1` preservation) in the TUI Dashboard, Whiptail dialogs, and CLI (`mint-admin ipv6 toggle`).
  - Added dedicated CLI commands: `mint-admin ipv6 [status | toggle | disable | enable]`.

## [v0.1.1] - 2026-11-01

### Fixed
- **Battery Charge Limit Persistence**:
  - **Wake / Resume Lifecycle**: Bound `asus-battery-limit.service` to `suspend.target`, `hibernate.target`, `hybrid-sleep.target`, and `suspend-then-hibernate.target` with `RemainAfterExit=no` to ensure automatic re-triggering upon waking from sleep or hibernation.
  - **Firmware Race Condition**: Added an asynchronous delayed background re-check loop (at 1s and 2s) to `/usr/lib/systemd/system-sleep/asus-battery-limit.sh` to override late ASUS EC / `asus_wmi` firmware resets after resume.
  - **Udev Rule Syntax & Scope**: Fixed udev rule to directly assign `ATTR{charge_control_end_threshold}` on `BAT*` device additions and changes, while re-triggering the persistence service non-blockingly on AC Mains adapter connect/disconnect events.
  - **Live Setting Synchronization**: Hardened `set_battery_threshold()` to automatically reload udev rules and restart the systemd persistence service whenever an existing installation is updated.

### Planned / Roadmap (Next Release)
- **Interactive TUI Dashboard**:
  - Full-featured Terminal User Interface (TUI) with interactive menus, live system sensor metrics, switch toggles, and keyboard navigation.

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
