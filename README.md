# Laptop Linux Optimizer (`laptop-linux-optimiser`)

[![Release](https://img.shields.io/badge/version-v0.5.15-blue.svg)](https://github.com/auarunkumar1/laptop-linux-optimiser/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Pop!_OS%20%7C%20Linux%20Mint%20%7C%20Ubuntu%20%7C%20Debian-lightgrey.svg)]()
[![Tests](https://img.shields.io/badge/tests-455%20passed-brightgreen.svg)]()
[![Shell](https://img.shields.io/badge/shell-bash%20%3E%3D%204.4-brightgreen.svg)]()

**Laptop Linux Optimizer** (`laptop-linux-optimiser.sh`) is a unified, privacy-first system administration, battery preservation, and network resilience suite for Linux laptops. Built for modern Linux environments, it provides native, fine-tuned optimizations for **Pop!_OS (COSMIC Desktop)**, **Linux Mint (Cinnamon)**, **Ubuntu (22.04/24.04+)**, and **Debian (12+)**.

Designed for developers, privacy-conscious professionals, and mobile Linux users, Laptop Linux Optimizer replaces fragmented scripts and manual tweaks with a single, hardened tool. It safeguards battery cell chemistry, enforces transport-level privacy and protocol neutrality against carrier throttling, locks down network exposure on public Wi-Fi, and streamlines system maintenance through an interactive terminal dashboard.

---

## Key Features

| Category | Capability | Description |
|---|---|---|
| 🌐 **Unified Multi-OS Core** | **Adaptive System Engine** | Single consolidated executable (`laptop-linux-optimiser.sh`) with intelligent distro auto-detection. Automatically adapts kernel sysctls, ZRAM parameters, swappiness, and font rendering per distribution. |
| 🔋 **Battery Cell Longevity** | **Hardware Charge Limiter** | Enforces hardware-level charge thresholds at **60%**, **80%**, or **100%** on ASUS and ACPI-compliant `BAT*` controllers. Persists reliably across reboots, suspend/resume cycles, and AC events. |
| 🖱️ **Hardware Input Resilience** | **ELAN Touchpad, Responsiveness & Zero-Lag** | Eliminates idle dropout, mid-drag freezes, microsecond wake-up stutter, and sluggish tracking on AMD Ryzen & Intel laptops via DesignWare host controller PM (`on`), deep CPU idle C-state caps (`processor.max_cstate=2`), GPU Panel Self Refresh wake-up bypass (`amdgpu.dcdebugmask=0x410` / `i915.enable_psr=0`), and libinput 31x31 resolution & light pressure calibration (`/etc/libinput/local-overrides.quirks`). |
| ⚡ **Memory & Kernel Tuning** | **ZRAM & TCP BBR** | Deploys compressed RAM swap (`zstd` algorithm) with distro-optimized swappiness (180 for Pop!_OS, 100 for Mint). Activates Google TCP BBR congestion control and trims unnecessary systemd boot delays. |
| 🛡️ **Encrypted DNS & Leak Shield** | **DoH, Relays, Tor & Killswitch** | Hardens `dnscrypt-proxy` across 14 resolver profiles (Auto-Failover pool, Cloudflare, Quad9, AdGuard, genuine DNSCrypt Anonymized Relays, and Tor onion routing). Features in-memory zero-log caching (`cache_size=8192`) and an iptables **DNS Leak Shield** killswitch with bootstrap resolver deadlock protection. |
| 📡 **Transport Integrity** | **Anti-Throttling & Middlebox Defense** | Mitigates discriminatory carrier throttling, intrusive middlebox metadata snooping, and stream degradation on hotel/cellular links. Features in-kernel TCP MSS packet boundary framing (Tier 1) and an optional dual-stack userspace transport shaper (Tier 2) with systemd lifecycle hooks and UID loopback isolation. |
| 🔒 **Inbound Security** | **SSH Port Shield** | Masks and disables inbound SSH server units (`ssh.service`, `sshd.service`, `ssh.socket`) to eliminate unauthorized port 22 exposure and unsolicited socket triggers on untrusted networks. |
| 🛡️ **Root Account Hardening** | **Safe Root Lock & Delegation** | Enforces root password lock (`passwd -l root`), verifies administrative sudo users before locking to prevent lockouts, preserves root login shell (`/bin/bash`), enforces SSH drop-in root blocks (`PermitRootLogin no`), and isolates direct root SSH keys. |
| 🖨️ **LAN Discovery Protection** | **Avahi & CUPS Safeguards** | Preserves `cups-browsed` (UDP 631) and `avahi-daemon` (mDNS) so network printing and LocalSend peer-to-peer file sharing continue working without interruption. |
| 🔍 **Display Typography** | **Subpixel Anti-Blur & Ozone** | Maintains native Wayland sharpness on COSMIC DE while eliminating blurry Flatpak and Cinnamon typography on Linux Mint through fontconfig LCD filtering and High-DPI Ozone flags. |
| 🕵️ **Identity & MAC Privacy** | **Hardware Randomization** | Generates cryptographically secure MAC addresses via `/dev/urandom`. Automatically detects active SSH sessions and default gateways to prevent dropped connections. Excludes virtual and tunnel interfaces (`docker`, `br-*`, `tailscale`, `wg`). |
| 🧹 **Zero-Footprint Purge** | **Hardened Storage Scrub** | Symlink-attack-immune cleanup of browser caches (Firefox, Chrome, Brave, Vivaldi), recent document metadata (`recently-used.xbel`), thumbnails, crash dumps, and DNS resolver logs. |
| 📦 **System Housekeeping** | **Package & Dependency Sweep** | Non-interactive APT upgrades with configuration file protection, Flatpak runtime pruning with theme preservation, journal log vacuuming, and orphaned package purging. |
| ⏱️ **Scheduled Maintenance** | **Weekly Systemd Automation** | Automated background maintenance timer running with root-owned canonical binary security (`/usr/local/sbin/laptop-linux-optimiser`) and path space quoting. |
| 🎛️ **One-Touch Presets** | **Workflow Presets** | Instant switching between **Desk / AC Docked** (60% charge limit, BBR, ZRAM), **Balanced Daily** (80% charge limit, BBR, ZRAM), and **Travel / Mobile** (100% capacity). |
| 🎬 **Hardware Drivers, Codecs & Fonts** | **AMD APU, Mesa & Typography** | One-click installation and verification of AMD/Mesa Vulkan (RADV), VA-API (`mesa-va-drivers` / `radeonsi`), VDPAU, Ubuntu Restricted Extras (`ffmpeg`, GStreamer plugins), Microsoft Core Fonts, Noto/Emoji, metric-compatible Calibri/Cambria (`fonts-crosextra-*`), Fira Code, and optional 32-bit (`i386`) gaming support. |
| 🖥️ **Terminal Interface** | **Interactive TUI Dashboard** | High-contrast full-screen TUI with real-time health badges, advisory alerts, single-key toggles, and graphical Whiptail dialog support. |

---

## Requirements

- **Operating System**: Pop!_OS 22.04/24.04+, Linux Mint 21+, Ubuntu 22.04/24.04+, Debian 12+, or derivatives
- **Shell**: Bash 4.4+
- **Privileges**: Root / sudo access for hardware controls and network firewall configuration
- **Recommended Dependencies** (automatically detected or installed when configuring specific modules):
  - `dnscrypt-proxy`, `dnsutils` (for Encrypted DNS)
  - `tor` (for DNS over Tor onion routing)
  - `zram-tools` / `pop-default-settings-zram` (for compressed memory swap)
  - `flatpak` (for Flatpak application maintenance and font flags)
  - `ethtool`, `iproute2`, `network-manager` (for interface controls and MAC privacy)

---

## Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/auarunkumar1/laptop-linux-optimiser.git
cd laptop-linux-optimiser
chmod +x laptop-linux-optimiser.sh
```

### 2. Launch the Master Suite
Execute without arguments to open the interactive full-screen dashboard:
```bash
./laptop-linux-optimiser.sh
```

### 3. Run the Guided Setup Wizard (Recommended for First-Time Setup)
Step through system hardening, battery preservation, and performance tuning in the verified logical sequence:
```bash
sudo ./laptop-linux-optimiser.sh wizard
```

### 4. Non-Destructive Status Inspection
Query system health, battery cell state, and network privacy indicators without altering any settings:
```bash
./laptop-linux-optimiser.sh summary          # Complete system health overview
./laptop-linux-optimiser.sh battery status   # Battery health, cycles & charge threshold
./laptop-linux-optimiser.sh root status      # Root user password lock & SSH PermitRootLogin state
./laptop-linux-optimiser.sh dns status       # Current encrypted DNS resolver configuration
./laptop-linux-optimiser.sh grub status      # GRUB bootloader defaults and menu recovery
./laptop-linux-optimiser.sh mac status       # Physical interface MAC addresses & randomization state
./laptop-linux-optimiser.sh tune status      # TCP BBR, ZRAM, swappiness & sysctl parameters
./laptop-linux-optimiser.sh ssh status       # Inbound SSH listener state & port 22 exposure
./laptop-linux-optimiser.sh antiblur status  # Font anti-blur & High-DPI scaling status
./laptop-linux-optimiser.sh os status        # Active OS profile & target configuration
```

---

## Recommended Sequence of Operations

When configuring a new installation or running maintenance, the guided wizard executes optimizations in this structured order:

1. **Target Platform Identification (`os`)**: Detects distribution (Pop!_OS vs Linux Mint) and applies distribution-native kernel sysctls and desktop rendering rules.
2. **Package & System Refresh (`update`)**: Updates repositories, upgrades packages non-interactively, and prunes unused runtimes to establish a stable package baseline.
3. **Hardware Battery Limiter (`battery`)**: Enforces and persists an 80% charge threshold (or 60% for desk docking) to minimize chemical wear on lithium-ion cells.
4. **Boot Latency Elimination (`wait-online`)**: Disables the blocking NetworkManager wait-online service to remove ~7 seconds of boot delay.
5. **Inbound Security Hardening (`ssh`)**: Masks and disables inbound SSH server units to block port 22 exposure on public networks.
6. **Encrypted DNS Setup (`dns`)**: Configures `dnscrypt-proxy` with hardened local RAM caching and enables DNS leak protection in `systemd-resolved`.
7. **Performance & Memory Tuning (`tune`)**: Enables TCP BBR, ZRAM compressed swap (`zstd`), balanced swappiness, and DHCP hostname privacy while preserving local printing and LocalSend.
8. **Display Sharpness (`antiblur`)**: Configures fontconfig subpixel rendering and High-DPI Ozone flags across Flatpak and Electron apps.
9. **Zero-Footprint Purge (`privacy`)**: Flushes DNS caches, purges browser histories, resets recent file records, and clears resolver logs.
10. **Reboot Advisory**: A clean reboot is suggested to finalize kernel sysctls, ZRAM swap devices, and systemd network drop-ins.

---

## Command Reference

### Guided Wizard
```bash
# Launch the step-by-step interactive optimization wizard
sudo ./laptop-linux-optimiser.sh wizard
```

### One-Touch Profile Presets
```bash
# Check active profile preset and current metrics
./laptop-linux-optimiser.sh preset status

# Desk / AC Docked: 60% battery threshold + TCP BBR + ZRAM
sudo ./laptop-linux-optimiser.sh preset desk

# Balanced Daily: 80% battery threshold + TCP BBR + ZRAM
sudo ./laptop-linux-optimiser.sh preset balanced

# Travel / Mobile: 100% full capacity for on-the-go battery runtime
sudo ./laptop-linux-optimiser.sh preset travel
```

### Battery Management & Charge Limiting
```bash
# Query battery health, wear level, cycles, and active charge limit
./laptop-linux-optimiser.sh battery status

# Set temporary charge limit for current session (e.g., 60 or 80)
sudo ./laptop-linux-optimiser.sh battery set 80

# Install persistent hardware charge limit (survives reboots, sleep/wake, and AC replug)
sudo ./laptop-linux-optimiser.sh battery install 80

# Remove limiter service and restore factory 100% charge limit
sudo ./laptop-linux-optimiser.sh battery uninstall
```

### Encrypted DNS & DNS Leak Shield (`dnscrypt-proxy`)
```bash
# Launch the interactive encrypted DNS profile selector (14 profiles + Shield toggle)
sudo ./laptop-linux-optimiser.sh dns menu

# Inspect active resolver configuration and protocol details
./laptop-linux-optimiser.sh dns status

# Apply a resolver profile directly by index or identifier:
sudo ./laptop-linux-optimiser.sh dns apply 0            # Auto-Failover pool (Quad9 + Cloudflare + AdGuard)
sudo ./laptop-linux-optimiser.sh dns apply cloudflare   # Cloudflare Anycast DoH
sudo ./laptop-linux-optimiser.sh dns apply quad9        # Quad9 Malware-blocking DoH
sudo ./laptop-linux-optimiser.sh dns apply adguard      # AdGuard Ad & Tracker blocking DoH
sudo ./laptop-linux-optimiser.sh dns apply 8            # Genuine DNSCrypt via Anonymized Multi-Hop Relays
sudo ./laptop-linux-optimiser.sh dns apply 11           # Quad9 routed over 3-hop Tor Onion circuits

# Revert DNS to standard DHCP / NetworkManager configuration
sudo ./laptop-linux-optimiser.sh dns revert

# Clean Network Overrides (Fix VPN / Cloudflare WARP conflicts & flush legacy netfilter rules)
sudo ./laptop-linux-optimiser.sh network clean-overrides
```

### GRUB Bootloader Configuration & Recovery (Module 10)
Package purge scripts (such as purging residual configuration files of `grub-pc` on EFI machines) can inadvertently delete `/etc/default/grub`, breaking `update-grub` and causing the GRUB boot menu to lose defaults or hang. Laptop Linux Optimizer protects bootloader packages and automatically restores the canonical configuration baseline:

```bash
# Check GRUB configuration presence, timeout, and defaults
./laptop-linux-optimiser.sh grub status

# Restore canonical /etc/default/grub baseline and run update-grub
sudo ./laptop-linux-optimiser.sh grub fix
```

### Hardware Acceleration Drivers, Media Codecs & Font Packs
```bash
# Query status of Mesa Vulkan, VA-API, VDPAU, Codecs, and Font Packs
./laptop-linux-optimiser.sh media status

# One-click install for complete 64-bit native suite (Drivers + Codecs + Fonts)
sudo ./laptop-linux-optimiser.sh media install

# Install AMD/Mesa Vulkan (RADV) & VA-API video acceleration drivers only
sudo ./laptop-linux-optimiser.sh media drivers

# Install Ubuntu restricted codecs, FFmpeg, and GStreamer framework plugins
sudo ./laptop-linux-optimiser.sh media codecs

# Install Microsoft core fonts, Noto, Emoji, Carlito/Caladea, and refresh font cache
sudo ./laptop-linux-optimiser.sh media fonts

# Live diagnostics & verification (runs vainfo & vulkaninfo --summary)
./laptop-linux-optimiser.sh media verify

# Optional: Manage 32-bit (i386) multiarch gaming support for Steam / Wine Proton
./laptop-linux-optimiser.sh media i386 status
sudo ./laptop-linux-optimiser.sh media i386 toggle
```

### Security Hardening: SSH Inbound Shield
```bash
# Check inbound SSH server status (inspects ssh.service, sshd.service, and ssh.socket)
./laptop-linux-optimiser.sh ssh status

# Mask and disable inbound SSH units (prevents port 22 exposure and socket activations)
sudo ./laptop-linux-optimiser.sh ssh enable

# Unmask SSH units
sudo ./laptop-linux-optimiser.sh ssh disable

# Toggle SSH inbound shield on/off
sudo ./laptop-linux-optimiser.sh ssh toggle
```

### Performance, Startup & Subsystem Toggles
```bash
# Comprehensive performance and sysctl status
./laptop-linux-optimiser.sh tune status

# Launch the interactive Performance, Privacy & Startup Toggle Hub
./laptop-linux-optimiser.sh tune menu

# Fast Desktop Boot: Toggle NetworkManager wait-online service (~7s delay removed)
./laptop-linux-optimiser.sh wait-online status          # Check wait-online state
sudo ./laptop-linux-optimiser.sh wait-online toggle     # Toggle between Fast Boot and Network Wait
sudo ./laptop-linux-optimiser.sh wait-online disable    # Force Fast Desktop Boot (disable delay)
sudo ./laptop-linux-optimiser.sh wait-online enable     # Enable wait-online delay

# Individual Subsystem Controls
sudo ./laptop-linux-optimiser.sh tune bbr toggle        # Toggle Google TCP BBR congestion control
sudo ./laptop-linux-optimiser.sh tune swappiness toggle # Toggle swappiness (180 Pop!_OS, 100 Mint)
sudo ./laptop-linux-optimiser.sh tune zram toggle       # Toggle 50% RAM compressed swap (zstd)
sudo ./laptop-linux-optimiser.sh tune dhcp toggle       # Toggle DHCP hostname privacy
sudo ./laptop-linux-optimiser.sh tune kernel toggle     # Toggle kernel memory hardening (dmesg & kptr restrict)
sudo ./laptop-linux-optimiser.sh tune avahi toggle      # Toggle Avahi mDNS daemon (LocalSend)
sudo ./laptop-linux-optimiser.sh tune cups toggle       # Toggle CUPS UDP 631 printer polling daemon
sudo ./laptop-linux-optimiser.sh tune modem toggle      # Toggle ModemManager cellular scanner daemon
sudo ./laptop-linux-optimiser.sh tune daemons toggle    # Toggle all 3 discovery daemons simultaneously

# Automated Tuning Application
sudo ./laptop-linux-optimiser.sh tune apply             # Apply recommended performance & privacy settings
sudo ./laptop-linux-optimiser.sh tune apply --yes       # Apply non-interactively
sudo ./laptop-linux-optimiser.sh tune revert            # Revert all sysctls and services to baseline defaults
```

### ELAN I2C Touchpad Responsiveness & Power Management
> 📖 **Technical Reference & Engineering Justifications**: For an in-depth breakdown of ACPI DSDT 100 kHz bus speed clamping, tap-and-drag disambiguation elimination, libinput multi-touch masking, C-state latency caps, and real-time IRQ event tracing, see [touchpad-optimisation.md](touchpad-optimisation.md).

```bash
# Query touchpad, AMD I2C host controller, C-state, GPU PSR, EVDI, and libinput quirk status
./laptop-linux-optimiser.sh touchpad status

# Smart One-Click Touchpad Auto-Tune (hardware-aware, safe defaults, no destructive overrides)
sudo ./laptop-linux-optimiser.sh touchpad auto

# One-click comprehensive fix for Wayland stutter, DisplayLink GPU hijacking, and phantom pressure
sudo ./laptop-linux-optimiser.sh touchpad fix-stutter

# Launch the interactive Touchpad Tuning & Diagnostics menu (or TUI option 13 / [Tt])
./laptop-linux-optimiser.sh touchpad menu

# Apply full persistent suite (udev rule, sleep hook, libinput quirks, C2 cap, PSR fix & EVDI on-demand)
sudo ./laptop-linux-optimiser.sh touchpad install

# Revert persistent touchpad modifications, quirks, and bootloader parameters
sudo ./laptop-linux-optimiser.sh touchpad revert

# Apply runtime-only power awake settings (immediate session without bootloader edits)
sudo ./laptop-linux-optimiser.sh touchpad runtime

# Check or force ELAN I2C bus clock to 100 kHz via early initrd ACPI DSDT upgrade (pre-7.3 kernels)
./laptop-linux-optimiser.sh touchpad speed status
sudo ./laptop-linux-optimiser.sh touchpad speed 100khz

# Check or toggle GNOME 200ms tap-and-drag disambiguation delay (eliminates initial touch lag)
./laptop-linux-optimiser.sh touchpad tap-drag status
./laptop-linux-optimiser.sh touchpad tap-drag disable

# Check or set pointer acceleration profile (flat for 1:1 linear tracking vs adaptive)
./laptop-linux-optimiser.sh touchpad accel status
./laptop-linux-optimiser.sh touchpad accel flat

# Check or toggle 500ms keyboard typing lockout (Disable-While-Typing)
./laptop-linux-optimiser.sh touchpad dwt status
./laptop-linux-optimiser.sh touchpad dwt disable

# Check or toggle bootloader CPU idle C-state cap (kernelstub on Pop!_OS / GRUB on Ubuntu/Mint)
./laptop-linux-optimiser.sh touchpad cstate status
sudo ./laptop-linux-optimiser.sh touchpad cstate toggle

# Check or toggle GPU Panel Self Refresh wake-up fix (amdgpu.dcdebugmask=0x410 / i915.enable_psr=0)
./laptop-linux-optimiser.sh touchpad psr status
sudo ./laptop-linux-optimiser.sh touchpad psr toggle

# Check or toggle libinput hardware quirks (31x31 resolution hint; auto-detects precision touchpads)
./laptop-linux-optimiser.sh touchpad quirks status
sudo ./laptop-linux-optimiser.sh touchpad quirks toggle

# Check or toggle DisplayLink EVDI on-demand mode (prevents EVDI from hijacking primary GPU card0)
./laptop-linux-optimiser.sh touchpad evdi status
sudo ./laptop-linux-optimiser.sh touchpad evdi fix
sudo ./laptop-linux-optimiser.sh touchpad evdi toggle

# Run hardware interrupt & power transition diagnostics
sudo ./laptop-linux-optimiser.sh touchpad diagnose
```

### Subpixel Font Anti-Blur & High-DPI Scaling
```bash
# Check current fontconfig & Flatpak sandbox font settings
./laptop-linux-optimiser.sh antiblur status

# Toggle font anti-blur on/off
sudo ./laptop-linux-optimiser.sh antiblur toggle

# Enable subpixel RGB fontconfig, full hinting, and Flatpak Ozone flags
sudo ./laptop-linux-optimiser.sh antiblur enable

# Revert font anti-blur rules to distribution default
sudo ./laptop-linux-optimiser.sh antiblur disable
```

### Layer-2 MAC Address Privacy
```bash
# Inspect physical interfaces, current MAC, and factory hardware MAC
./laptop-linux-optimiser.sh mac status

# Randomize MAC addresses on demand (preserves active SSH sessions and gateways)
sudo ./laptop-linux-optimiser.sh mac randomize

# Enable persistent MAC randomization in NetworkManager (randomizes on connect and scan)
sudo ./laptop-linux-optimiser.sh mac enable

# Disable persistent MAC randomization
sudo ./laptop-linux-optimiser.sh mac disable
```

### System Housekeeping & Privacy Scrubbing
```bash
# Routine housekeeping: APT cache clean, Flatpak unused runtimes, journal vacuuming
sudo ./laptop-linux-optimiser.sh optimize

# Update APT & Flatpak packages with config file protection
sudo ./laptop-linux-optimiser.sh update

# Scrub browser caches, recent documents, thumbnail previews, crash logs, and resolver logs
sudo ./laptop-linux-optimiser.sh privacy

# Complete Master Suite: Update + Housekeep + Privacy Scrub + MAC Randomize
sudo ./laptop-linux-optimiser.sh full-suite
```

### Automated Maintenance Timer
```bash
# Query weekly timer status and last execution timestamp
./laptop-linux-optimiser.sh timer status

# Install weekly systemd timer (runs Sundays at 3:00 AM)
sudo ./laptop-linux-optimiser.sh timer install

# Remove weekly maintenance timer
sudo ./laptop-linux-optimiser.sh timer uninstall
```

---

## Security & Architectural Hardening

Laptop Linux Optimizer follows strict defensive engineering practices:

1. **Root Symlink Traversal Protection**: File and history cleanups in `clean_privacy()` enforce non-dereferencing operations (`[ ! -L "$path" ]`), atomic temp-file creation with `chown --no-dereference`, and traversal boundary checks.
2. **Canonical Binary Execution**: Systemd timers install a root-owned binary (`/usr/local/sbin/laptop-linux-optimiser`) rather than invoking script paths in `/home`, neutralizing unprivileged binary substitution attacks.
3. **Quoted Systemd Directives**: All `ExecStart`, `ExecStartPost`, and `ExecStopPost` directives are strictly quoted to prevent argument-splitting vulnerabilities on paths with spaces.
4. **Session Drop Protection**: Network interface cycling detects active SSH sessions (`$SSH_CONNECTION`) and active default gateways to avoid disconnecting remote terminal sessions.
5. **Atomic Baseline State Capture**: Baseline sysctl parameters and service states are recorded into `/var/lib/laptop-linux-optimiser/tuning-baseline.env` before modifications occur, ensuring `tune revert` accurately restores the original system state.
6. **Storm-Free Udev Power Rules**: Battery threshold udev rules monitor `ATTR{type}=="Mains"` power transitions and read current limits before writing, eliminating recursive uevent storms.
7. **Bootstrap DNS Deadlock Prevention**: The DNS Leak Shield explicitly whitelists `dnscrypt-proxy` system UIDs and upstream fallback resolvers (`9.9.9.9`, `1.1.1.1`) before applying port 53 DROP rules, preventing boot-time name resolution deadlock.
8. **Loopback & Subsystem Isolation**: Userspace transport shaper rules explicitly exclude loopback traffic (`! -d 127.0.0.0/8`, `! -d ::1/128`) and bypass local resolver/Tor UIDs (`-j RETURN`), preventing proxy feedback loops.

---

## Automated Verification & Test Suite

The project features a comprehensive automated regression suite containing **178 validated assertions**:

```bash
# Run the complete test suite
./tests/test_laptop_linux_optimiser.sh
```

Validation includes:
- Cryptographic MAC address formatting, unicast bit validation (`02:`), and `/dev/urandom` entropy checks
- Virtual interface filtering exclusions (`docker`, `br-*`, `virbr`, `tailscale`, `wg`)
- `dnscrypt-proxy.toml` syntax parsing and configuration sanity checks
- Symlink traversal attack immunity across files, directories, and trash caches
- Non-TTY stdin pipe safety and usage formatting
- Battery udev rule specifications and event comparison logic
- Systemd timer `ExecStart` path quoting and canonical binary installation
- Desktop theme runtime preservation and Flatpak theme overrides
- Subpixel font anti-blur, fontconfig LCD rules, and High-DPI Ozone flags
- Multi-OS platform detection, manual switching, and configuration persistence
- SSH inbound shielding (masking, unmasking, and socket status reporting)
- Network printer (`cups-browsed`) and LocalSend (`avahi-daemon`) discovery preservation
- DNS privacy hardening: zero-log query/nx logs, local RAM caching, systemd-resolved LLMNR/mDNS/DNSSEC suppression
- DNS Leak Shield: firewall killswitch blocking cleartext outbound port 53 traffic with bootstrap resolver exceptions
- Transport Integrity: Tier 1 TCP MSS handshake framing, Tier 2 userspace transport shaper, dual-stack IPv4/IPv6 redirection, and diagnostic probes

---

## Roadmap

- [x] **Interactive TUI Dashboard (v0.2.0)**: Text user interface with interactive menus, live system indicators, and Whiptail modal dialog support.
- [x] **Profile Presets (v0.2.0)**: One-click switching between *Desk / AC Docked* (60%), *Balanced Daily* (80%), and *Travel / Mobile* (100%).
- [x] **Font Anti-Blur & Ozone Flags (v0.3.2)**: Subpixel LCD font anti-blur with Flatpak sandbox fontconfig overrides.
- [x] **Universal OS Engine (v0.5.0)**: Consolidated architecture supporting Pop!_OS, Linux Mint, Ubuntu, and Debian with SSH inbound shielding.
- [x] **DNS Leak Shield & Transport Integrity (v0.5.1)**: Zero-log RAM caching, strict port 53 killswitch with bootstrap deadlock protection, in-kernel TCP MSS framing (Tier 1), and userspace transport shaper (Tier 2).
- [x] **DNS Boot Deadlock & Hostname Resolution Fix (v0.5.2)**: Eliminate boot-time resolver circular locks and synchronous Firefox profile lock latency with dynamic `/etc/hosts` mapping and dnscrypt bootstrap fallbacks.
- [ ] **Wayland Root GUI Autofix (Planned for v0.6.0)**: Seamless display authorization and `xhost +si:localuser:root` compatibility for administrative root GUI apps (`gufw`, `synaptic`, `timeshift-gtk`, `gparted`, `bleachbit`) under Wayland / COSMIC sessions (see [TODO.md](TODO.md)).
- [ ] **Hardware Sensor Monitoring**: Real-time thermal zone readings and battery discharge rate graphing within the TUI dashboard.

---

## License

This project is licensed under the [MIT License](LICENSE) - see the `LICENSE` file for details.  
Copyright (c) 2026 Arun Kumar.
