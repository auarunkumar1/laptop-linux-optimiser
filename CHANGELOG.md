# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.5.15] - 2026-11-22

### Added
- **Smart Touchpad Auto-Tune Subsystem (`smart_touchpad_autotune`)**:
  - Implemented one-click hardware-aware auto-tuning accessible via `$0 touchpad auto` and `$0 touchpad smart`.
  - Automatically identifies I2C host controllers (AMD DesignWare `AMDI0010` and Intel I2C) and touch devices, locking host controller runtime PM awake via persistent udev rules (`/etc/udev/rules.d/99-elan-power.rules`) and sleep hooks (`/usr/lib/systemd/system-sleep/99-elan-resume.sh`) to eliminate idle sleep dropouts.
  - Automatically verifies DisplayLink EVDI driver status to prevent multi-head Wayland compositor lockups.
  - Cleans legacy or conflicting libinput quirks without applying intrusive overrides on hardware that already reports calibrated resolutions.

### Changed
- **Touchpad Menu Streamlining & Cognitive Load Reduction**:
  - Replaced the bloated, overlapping 14-item touchpad menu in both interactive TUI (`interactive_touchpad_menu`) and Whiptail dialog (`whiptail_touchpad_menu`) with a clean 5-action interface:
    - `[1] Smart Auto-Tune (One-Click System-Aware Optimization)`
    - `[2] View Detailed Hardware, Bus & Power Status`
    - `[3] Run Live 120s Interrupt & Freeze Diagnostics (diagnose-elan-irq)`
    - `[4] Revert All Touchpad Settings (restore OS defaults)`
    - `[5] Advanced Manual Tuning (Submenu for granular knobs)`
  - Added dedicated submenus (`interactive_touchpad_advanced_menu` and `whiptail_touchpad_advanced_menu`) for granular knobs (acceleration profile, palm rejection, tap-and-drag, C-state cap, GPU PSR fix, I2C bus speed, and EVDI mode).
- **Restored Safe, Non-Destructive Desktop Defaults in `tune_gnome_touchpad`**:
  - Restored `click-method 'default'` instead of forcing `'fingers'`, repairing the physical bottom-right corner right-click button zone on buttonpad laptops while maintaining two-finger tap for right click.
  - Restored `disable-while-typing true` (palm rejection) instead of forcing `false`, eliminating stray cursor jitter, phantom jumps, and accidental taps while typing or resting hands near the trackpad.
  - Preserved `accel-profile 'flat'` for 1:1 linear pointer tracking without low-speed deadband dampening.
- **Automated Validation Suite**:
  - Added unit test coverage for `smart_touchpad_autotune` and CLI dispatcher aliases in `tests/test_laptop_linux_optimiser.sh`, bringing total coverage to 440 passing tests.

## [v0.5.14] - 2026-11-21

### Fixed
- **Two-Finger Scrolling & Multi-Touch Gesture Restoration (`BTN_TOOL_DOUBLETAP` Masking Removal)**:
  - Diagnosed regression where two-finger scrolling and two-finger right click ceased functioning after applying libinput quirks.
  - Root Cause: In Linux `evdev`, `BTN_TOOL_DOUBLETAP` is the standard kernel event emitted whenever two fingers are placed on the trackpad. `libinput` directly requires this key code to transition its internal state machine into two-finger scrolling mode. Masking `BTN_TOOL_DOUBLETAP` via `AttrEventCode` stripped the capability from libinput's device representation, causing it to ignore two-finger contacts.
  - Removed `AttrEventCode=-BTN_TOOL_DOUBLETAP;-BTN_TOOL_TRIPLETAP;-BTN_TOOL_QUADTAP;` from `apply_touchpad_quirks()` in `laptop-linux-optimiser.sh`, ensuring two-finger scrolling, two-finger tapping, and multi-finger gestures remain fully functional while retaining calibrated `AttrResolutionHint=31x31`.
  - Updated `fix_touchpad_stutter()` to automatically detect and sanitize outdated quirks files containing `BTN_TOOL_DOUBLETAP` masking.
  - Updated `is_touchpad_quirks_installed()`, `show_touchpad_quirks_status()`, and `show_touchpad_status()` to flag quirks with `BTN_TOOL_DOUBLETAP` as `OUTDATED`.
  - Preserved `tap-and-drag true` by default in `tune_gnome_touchpad()` to prevent unintended loss of tap-to-drag, keeping `touchpad tap-drag disable` as an explicit opt-in toggle.
  - Integrated `reset_gnome_touchpad()` into `revert_touchpad()` to cleanly reset all touchpad GSettings to desktop schema defaults upon system revert.
  - Added Section 5 (Known Linux Kernel Patches), Section 6.4 (Empirical Telemetry & Real-World Diagnostics Case Study), and Section 11 (Hazard of Fix Snowballing & Controlled Isolation Protocol) to `touchpad-optimisation.md`.
  - Updated test suite in `tests/test_laptop_linux_optimiser.sh`; all 438 unit tests passing.

## [v0.5.13] - 2026-11-21

### Fixed
- **Initial Touch Lag & Start-up Hesitation Elimination (Tap-and-Drag Disambiguation & Pointer Acceleration)**:
  - Pinpointed the physical root cause of the initial touch hesitation (*"after initial lag touchpad works continuously"*):
    - **GNOME Tap-and-Drag Disambiguation Window**: In GNOME Wayland, `tap-and-drag` is enabled by default (`true`). On every initial finger contact after a pause, `libinput` halts coordinate dispatch during a ~200ms disambiguation window to see if the contact is the second tap of a tap-drag sequence. Once movement breaks free, tracking runs continuously at 100 Hz without interruption, but every subsequent touch down after lifting the finger re-triggers the 200ms delay.
    - Updated `tune_gnome_touchpad()` to disable both `tap-and-drag` and `tap-and-drag-lock` (`false`), removing the motion hold entirely so touch motion begins on the first millisecond of contact.
    - Added dedicated helper functions: `status_get_touchpad_tap_drag()`, `show_touchpad_tap_drag_status()`, `enable_touchpad_tap_drag()`, `disable_touchpad_tap_drag()`, and `toggle_touchpad_tap_drag()`.
    - Added pointer acceleration profile helpers: `status_get_touchpad_accel_profile()`, `show_touchpad_accel_profile_status()`, `set_touchpad_accel_profile()`, and `toggle_touchpad_accel_profile()` (supporting `flat`, `adaptive`, and `default`) to eliminate low-velocity deadband suppression.
  - **Libinput Quirks Verification & Event Masking Update**:
    - Updated `is_touchpad_quirks_installed()` to verify both `AttrResolutionHint=31x31` and multi-touch button masking (`BTN_TOOL_DOUBLETAP`).
    - Updated `show_touchpad_quirks_status()` and `show_touchpad_status()` to flag older quirks files lacking event masking as `OUTDATED`.
    - Enhanced `fix_touchpad_stutter()` to automatically upgrade outdated quirks files to include `AttrEventCode=-BTN_TOOL_DOUBLETAP;-BTN_TOOL_TRIPLETAP;-BTN_TOOL_QUADTAP;`.
  - **Menu & CLI Integration**:
    - Added Option 11 (Tap-and-Drag) and Option 12 (Acceleration Profile) to `interactive_touchpad_menu()` and `whiptail_touchpad_menu()`.
    - Added CLI dispatchers: `$0 touchpad tap-drag [status|enable|disable|toggle]` and `$0 touchpad accel [status|flat|adaptive|default|toggle]`.
    - Updated `--help` documentation and status dashboard.
  - **Validation Test Suite**:
    - Added 16 new automated unit tests in `tests/test_laptop_linux_optimiser.sh`, bringing the total to 437 tests; all 437 tests passed.

## [v0.5.12] - 2026-11-21

### Fixed
- **ELAN1300 I2C Bus Frequency Clamping to 100 kHz via Early Initrd ACPI DSDT Upgrade**:
  - Identified the root cause of lingering sporadic lag and momentary touchpad freezes on ASUS VivoBook laptops (`X513UA_KM513UA` / AMD Ryzen 5500U with `ELAN1300:00 04F3:3104`):
    - The laptop's factory ACPI DSDT table defines the I2C connection speed at 400 kHz (`0x00061A80`).
    - At 400 kHz on the AMD DesignWare I2C controller (`AMDI0010:03`), electrical bus capacitance and timing noise trigger internal touchpad microcontroller noise suppression. The touchpad firmware enters excessive smoothing mode and temporarily drops/suppresses coordinates (the upstream kernel patch *"i2c: acpi: Force ELAN1300 touchpads to 100 kHz"* addresses this by forcing 100 kHz, but was only merged into Linux 7.3).
  - Implemented the kernel-sanctioned `CONFIG_ACPI_TABLE_UPGRADE` early initrd override subsystem:
    - Added `apply_touchpad_acpi_100khz()`, `remove_touchpad_acpi_100khz()`, and `toggle_touchpad_acpi_100khz()`.
    - Reads `/sys/firmware/acpi/tables/DSDT`, locates the `ELAN1300` device block, patches the `I2cSerialBusV2` connection speed descriptor from 400 kHz (`\x80\x1a\x06\x00`) to 100 kHz (`\xa0\x86\x01\x00`), recomputes the ACPI table checksum, and packages `kernel/firmware/acpi/dsdt.aml` into `/boot/acpi_override` (cpio newc).
    - Writes GRUB drop-in `/etc/default/grub.d/99-elan-acpi.cfg` (`GRUB_EARLY_INITRD_LINUX_CUSTOM="acpi_override"`), natively prepending the override before initrd in `/etc/grub.d/10_linux`.
  - Added automated invocation to `fix_touchpad_stutter()` and `install_touchpad_permanent()` for pre-7.3 kernels.
  - Added CLI dispatchers: `$0 touchpad speed [status|100khz|400khz|toggle]` and `$0 tune touchpad speed ...`.
  - Added status reporting to `show_touchpad_status()` and interactive/Whiptail menus (Option 10).

- **Multi-Touch Tap Code Masking in Libinput Quirks**:
  - Added `AttrEventCode=-BTN_TOOL_DOUBLETAP;-BTN_TOOL_TRIPLETAP;-BTN_TOOL_QUADTAP;` to `/etc/libinput/local-overrides.quirks`.
  - Prevents spurious multi-finger button events from disrupting libinput's native slot-based coordinate tracking on multi-touch precision touchpads.

## [v0.5.11] - 2026-11-21

### Fixed
- **D-Bus Session Bus Propagation for Unprivileged User Settings under Sudo (`run_user_gsettings` / `get_user_gsettings`)**:
  - Implemented robust `run_user_gsettings()` and `get_user_gsettings()` helper functions that automatically discover the target user's active UID via `id -u "$target_user"` and export `DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${user_uid}/bus"` when running under `sudo`.
  - Fixes silent failures where `sudo -u "$SUDO_USER" gsettings` was rejected by D-Bus with "Cannot autolaunch D-Bus without X11 $DISPLAY" or ignored because the user's session dconf bus was inaccessible from the root environment.
  - Replaced all raw `sudo -u "$SUDO_USER" gsettings` calls across touchpad tuning, font anti-blur, and theme synchronization (`status_get_uniform_theme`, `apply_uniform_theme`).

- **DisplayLink EVDI Dummy Heads & Kernel Virtual DRM Card Cleanup**:
  - Identified that DisplayLink EVDI dummy multi-head allocation (`initial_device_count=4` in `/etc/modprobe.d/evdi.conf` and loaded via initramfs) created 4 virtual DRM cards (`/dev/dri/card2` through `/dev/dri/card5`). Even with no DisplayLink dock connected, the GNOME Shell / Mutter Wayland compositor continuously synced against these inactive displays, stalling the main event loop for 124–264ms (`libinput error: client bug: timer event6 hold: scheduled expiry is in the past (-264ms), your system is too slow`) and causing severe sporadic cursor freezes.
  - Enhanced EVDI detection and cleanup (`fix_evdi_boot_hijack` / `restore_evdi_boot_hijack`):
    - Added inspection and removal for `/etc/modprobe.d/evdi.conf`.
    - Triggers `update-initramfs -u` to ensure virtual card allocation is purged from the early boot ramdisk.
    - Updated `show_evdi_status()` and `show_touchpad_status()` to report both `modules-load.d` and `modprobe.d` configurations.

- **ELAN1300 Multi-Touch Clickpad Jump Discard Fix (`click-method 'fingers'`)**:
  - Diagnosed recurring kernel/libinput touch drops on `ELAN1300:00 04F3:3104 Touchpad` (`libinput error: event6 - ELAN1300:00 04F3:3104 Touchpad: kernel bug: Touch jump detected and discarded`). Clickpads configured with bottom software button zones (`click-method 'default'`) confuse multi-touch coordinate tracking when fingers rest or brush near the bottom edge. Libinput treats the sudden delta as an impossible physical jump and drops all motion packets until lift-off.
  - Enforced `click-method 'fingers'` (two-finger right click, three-finger middle click) via `tune_gnome_touchpad()` and live dconf tuning, eliminating software button zones and touch jump discards entirely.

- **Touchpad Disable-While-Typing (DWT) Management Subsystem**:
  - Identified GNOME's aggressive 500ms keyboard lockout (`disable-while-typing true`), which halts cursor motion whenever keys are pressed or hands lightly rest on the palm rest.
  - Added full DWT management functions: `status_get_touchpad_dwt()`, `show_touchpad_dwt_status()`, `enable_touchpad_dwt()`, `disable_touchpad_dwt()`, and `toggle_touchpad_dwt()`.
  - Added CLI dispatchers: `$0 touchpad dwt [status|enable|disable|toggle]` and `$0 tune touchpad dwt [status|enable|disable|toggle]`.
  - Added interactive and Whiptail toggles for Typing Lockout (DWT) in `interactive_touchpad_menu()` and `whiptail_touchpad_menu()`.
  - Integrated Typing Lockout (DWT) and Click Method inspection directly into `show_touchpad_status()`.

## [v0.5.10] - 2026-11-20

### Added
- **Root User Hardening & Delegation Subsystem**:
  - Pre-flight administrative safety check (`lock_root_user`): verifies that at least one administrative user exists in `sudo`, `wheel`, or `admin` before executing password lock to prevent lockout.
  - Password lock enforcement: disables root password via `passwd -l root` (and `usermod -L root` fallback), rendering the root password field locked with `!` in `/etc/shadow`.
  - Shell integrity preservation: explicitly preserves `/bin/bash` login shell for the root account; never sets shell to `/usr/sbin/nologin` or `/bin/false`, ensuring `sudo -i`, `sudo su -`, and emergency single-user recovery mode continue working without interruption.
  - SSH root login block: writes drop-in configuration `/etc/ssh/sshd_config.d/00-disable-root-login.conf` enforcing `PermitRootLogin no`.
  - Direct root SSH key isolation: moves `/root/.ssh/authorized_keys` to `/root/.ssh/authorized_keys.disabled` (mode 0600) upon lock, and restores it on unlock.
  - Unprivileged state manifest: writes `/etc/laptop-root-lock.conf` (mode 0644) so non-root status calls (`status`, `summary`, and dashboard) can query root hardening status without needing sudo permissions.
  - CLI integration: added `$0 root [status|lock|unlock|toggle]` and `$0 tune root [status|lock|unlock|toggle]`.
  - UI integration: added `[L]` Root User Hardening Shield to the Master TUI Dashboard (`show_tui_dashboard`), Interactive Tuning Menu (`interactive_tuning_menu`), Whiptail menu (`whiptail_tuning_menu`), and Step 13 of the Guided Wizard (`run_guided_wizard`).
  - Validation test suite: added Test 49 in `tests/test_laptop_linux_optimiser.sh` with 18 comprehensive test assertions; all 391 tests passing.

- **Modern Mesa Gallium Unified Driver Compatibility**:
  - Enhanced `status_get_media_drivers()` and `show_media_driver_status()` to inspect `mesa-libgallium` alongside `mesa-va-drivers` and `mesa-vdpau-drivers`. In modern Mesa (Mesa 25/26+ on Ubuntu 24.10/26.04+ and Debian Trixie/Sid), `mesa-libgallium` replaces standalone `mesa-va-drivers` and directly provides `/usr/lib/*/dri/*_drv_video.so`.
  - Fixed `vainfo` driver version string parser in `show_media_driver_status` using `sed` to accurately extract the driver name and kernel DRM details.
  - Test suite expanded to 393 assertions with Test 46 verification for `mesa-libgallium`.

## [v0.5.9] - 2026-11-20

### Added
- **Comprehensive 14-Step Guided Setup Wizard (`run_guided_wizard`)**:
  - Expanded the guided setup wizard from 8 steps to a 14-step walkthrough organized across 5 clear operational phases:
    1. *Phase 1: Foundation & Battery Health* (Target OS platform selection, persistent battery charge limiter 60%/80%/100%, package updates).
    2. *Phase 2: Hardware Acceleration & Drivers* (Mesa Vulkan RADV, VA-API hardware video decode, media codecs, font packs, browser VA-API injection, audio powersave DAC click/crackle shield).
    3. *Phase 3: Input, Display & Storage Maintenance* (ELAN I2C touchpad zero-latency PM, subpixel font anti-blur & High-DPI clarity, automated weekly SSD/NVMe TRIM timer).
    4. *Phase 4: Kernel, Power & Network Tuning* (AMD P-State EPP governor profile, Google TCP BBR, ZRAM compressed swap, NetworkManager fast desktop boot).
    5. *Phase 5: Security, Privacy & System Polish* (Hardened laptop UFW inbound firewall, Ubuntu Apport crash error shield, DHCP hostname masking, kernel memory protection, SSH server masking, and ModemManager cellular scanning deactivation while strictly preserving CUPS printing & Avahi mDNS).
    6. *Bonus Step*: Popular Themes Gallery for uniform GTK3/Libadwaita/Flatpak styling.
  - Deep educational context for every optimization: displays the problem, underlying hardware mechanism, performance/battery benefit, and recommended defaults with interactive prompts.

### Changed
- **Logically Categorized Terminal Dashboard & TUI Controls**:
  - Structured the Master TUI Dashboard (`show_tui_dashboard`) into 5 clean thematic sections:
    - *Core Setup & Quick Workflows* (`[1]` Guided Wizard, `[P]` Presets, `[2]` Updates, `[3]` Housekeeping, `[4]` Master Suite)
    - *Hardware, Battery & Power Management* (`[5]` Battery, `[E]` EPP, `[K]` Audio Pop Shield, `[S]` SSD TRIM, `[12]` Touchpad)
    - *Graphics, Display & Acceleration* (`[15]` Media & GPU Drivers, `[V]` Browser VA-API, `[F]` Font Anti-Blur)
    - *Security, Network & Privacy* (`[H]` Laptop UFW Firewall, `[D]` Apport Crash Shield, `[6]` DNS, `[7]` MAC, `[8]` IPv6, `[10]` Privacy Scrub)
    - *System Tools & Advanced Configuration* (`[9]` Toggles, `[13]` Themes, `[14]` GRUB, `[11]` Weekly Timer)
  - Added direct shortcuts `[E]`, `[K]`, `[S]`, `[V]`, `[H]`, `[D]`, and `[F]` to the master dashboard.
  - Restructured `interactive_tuning_menu()` and `whiptail_tuning_menu()` into matching logical categories with educational descriptions for each toggle.

## [v0.5.8] - 2026-11-20

### Added
- **AMD P-State EPP Governor Tuning (Module 13)**:
  - Energy Performance Preference governor control (`set_epp_preference`, `cycle_epp_preference`, `show_epp_status`) for AMD Zen APUs (`amd-pstate-epp`), persisted via `/etc/tmpfiles.d/laptop-epp.conf`.
- **Audio Power-Save DAC Popping & Crackle Shield**:
  - Eliminates speaker/headphone clicks on Intel & Realtek HDA audio chips by disabling idle DAC power-save (`power_save=0`) via `/etc/modprobe.d/laptop-audio-powersave.conf`.
- **Browser Hardware Video Acceleration (VA-API)**:
  - Automatic injection of VA-API hardware decoding preferences into native and Snap Firefox profiles (`user.js`) and Chromium/Brave/Chrome GPU flags files (`~/.config/*-flags.conf`).
- **SSD / NVMe Periodic TRIM Maintenance**:
  - Automated weekly TRIM management (`fstrim.timer`) and manual TRIM trigger (`fstrim -av`) for flash storage endurance.
- **Ubuntu Apport Crash Error Popups Shield**:
  - Silences recurring error dialogs (`/etc/default/apport` enabled=0 and masks `apport.service`) and purges leftover crash dumps.
- **Hardened Laptop UFW Firewall Shield**:
  - Inbound deny, outbound allow firewall profile for public Wi-Fi safety with LAN rules for LocalSend (`53317/tcp+udp`) and CUPS printing (`631/udp`).
- **PipeWire Bluetooth High-Fidelity Audio Codecs**:
  - High-res LDAC, AAC, and aptX codec integration via `libspa-0.2-bluetooth`.

## [v0.5.7] - 2026-11-20

### Added
- **Hardware Acceleration Drivers, Media Codecs & Font Packs (Module 12)**:
  - Added comprehensive multimedia, typography, and graphics driver subsystem tailored for Ubuntu LTS, AMD APUs (Ryzen 5 5500U / Radeon Vega 7 / VCN 2.2), Intel, and Mesa.
  - 64-bit native AMD/Mesa graphics and video acceleration: `mesa-vulkan-drivers` (RADV), `vulkan-tools`, `libvulkan1`, `mesa-va-drivers` (`radeonsi`), `mesa-vdpau-drivers`, `libva2`, `vainfo`, `vdpauinfo`.
  - Media codecs and GStreamer framework: `ubuntu-restricted-extras`, `ffmpeg`, `gstreamer1.0-plugins-base/good/bad/ugly`, `gstreamer1.0-libav`, and `gstreamer1.0-vaapi`.
  - Essential font packs: `ttf-mscorefonts-installer` (with non-interactive debconf license pre-seeding), `fonts-crosextra-carlito` (Calibri metric substitute), `fonts-crosextra-caladea` (Cambria substitute), `fonts-liberation2`, `fonts-noto-core`, `fonts-noto-cjk`, `fonts-noto-color-emoji`, `fonts-dejavu`, `fonts-firacode`, and automatic `fc-cache -f` cache rebuild.
  - Verification & diagnostics: `verify_hardware_acceleration()` tests VA-API decode profiles and Vulkan GPU capabilities via `vainfo` and `vulkaninfo --summary`.
  - Multiarch gaming support: optional `enable_i386_support()` / `disable_i386_support()` to safely manage 32-bit Vulkan/VA-API libraries for Steam / Wine / Proton without breaking clean 64-bit native baselines.
  - Interactive integration: added Option 15 to the Master TUI Dashboard, Curses Whiptail submenu, CLI commands (`./laptop-linux-optimiser.sh media [status|install|drivers|codecs|fonts|verify|i386|menu]`), and aliases (`codecs`, `fonts`, `drivers`).

### Fixed
- **GRUB Bootloader Configuration Deletion & Recovery (Module 10)**:
  - Fixed severe bug where `clean_apt()` residual configuration purge (`dpkg --purge`) deleted `/etc/default/grub` when purging leftover `grub-pc` configuration files on EFI installations.
  - Added strict package name exclusion filter to `clean_apt()` preventing `dpkg --purge` on any bootloader, kernel, or EFI packages (`^(grub|shim|linux-|systemd-boot|efibootmgr)`).
  - Implemented `ensure_grub_default_config()` which automatically verifies and restores `/etc/default/grub` from canonical `/usr/share/grub/default/grub` if missing, repairing default boot parameters (`GRUB_DEFAULT=0`, `GRUB_TIMEOUT=0`, `GRUB_TIMEOUT_STYLE=hidden`, `GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"`).
  - Added automatic verification and restoration of `/etc/default/grub` across all bootloader-modifying operations: `clean_apt()`, `apply_touchpad_cstate_cap()`, `apply_touchpad_psr_fix()`, `remove_touchpad_cstate_cap()`, and `remove_touchpad_psr_fix()`.
  - Added CLI commands: `./laptop-linux-optimiser.sh grub [status|fix|repair]` and TUI dashboard Option 14 / Whiptail menu support.
- **Cloudflare WARP Network Outage & Clean Decoupling**:
  - Resolved complete network drop caused by Netplan & NetworkManager managing the `CloudflareWARP` interface. Modifying connections via `nmcli con modify` on Ubuntu 24.04 serialized dynamic tunnel routing tables into `/etc/netplan/90-NM-*.yaml` with `autoconnect: yes`, auto-activating the tunnel on boot before `warp-svc` connected and creating an outbound routing loop to Cloudflare edge IPs.
  - Restricted `enable_dhcp_privacy()` and `disable_dhcp_privacy()` to strictly target physical Wi-Fi and Ethernet interfaces (`802-11-wireless|802-3-ethernet`), never modifying `tun`, `tap`, `vpn`, or loopback connections.
  - Updated `clean_network_overrides()` (`sudo ./laptop-linux-optimiser.sh network clean-overrides`) to automatically:
    - Purge rogue Netplan YAML configurations capturing `CloudflareWARP`.
    - Delete lingering NetworkManager connection profiles for `CloudflareWARP`.
    - Deploy `/etc/NetworkManager/conf.d/99-unmanage-warp.conf` enforcing `unmanaged-devices=interface-name:CloudflareWARP` so NetworkManager never hijacks or interferes with the WARP tunnel on boot.
    - Flush all legacy iptables/ip6tables mangle and nat chains and restore standard NetworkManager connectivity probes.

- **Wayland Native Anti-Blur & High-DPI Adaptation (Module 9)**:
  - Adapted `enable_font_antiblur()`, `disable_font_antiblur()`, and `status_get_font_antiblur()` to be fully Wayland-aware.
  - Eliminated counter-productive X11-only settings (`gtk-xft-dpi=122880`, `GDK_DPI_SCALE=1.25`, and `hintfull`) on Wayland environments, which previously caused double-scaling and blurry rendering in XWayland.
  - On Wayland sessions (`XDG_SESSION_TYPE=wayland`), enforced native grayscale antialiasing, `hintslight`, and deployed native Ozone platform hints (`ELECTRON_OZONE_PLATFORM_HINT=auto`, `MOZ_ENABLE_WAYLAND=1`, `~/.config/electron-flags.conf`) to resolve the true root cause of blurry Electron/Chromium apps under XWayland.

### Removed
- **Obsolete Network & DPI Bypass Tools**:
  - Completely excised obsolete Deep Packet Inspection (DPI) bypass engine (Tier 1 MSS clamping, Tier 2 Byedpi daemon, flags, presets, and diagnostic probes) from the script and interactive UI.
  - Excised DNS Leak Shield netfilter rules and NetworkManager probe toggles that conflicted with modern VPNs and tunnel interfaces (Cloudflare WARP `warp-svc`, WireGuard, Tailscale).

## [v0.5.6] - 2026-11-15

### Security & Hardening
- **Comprehensive Privacy & Security Audit Remediation (26 Findings Confirmed & Remediated)**:
  - **Critical (C1–C4)**:
    - C1: Corrected Byedpi iptables rule ordering; inserted transparent REDIRECT first, then RETURN exemptions at position 1 (`-I OUTPUT 1`).
    - C2 & H5: Changed default Byedpi port to dedicated port `47891`, strictly bound daemon to loopback `127.0.0.1`, removed systemd cgroup egress-blocking filter, and hardened systemd unit with full sandboxing.
    - C3 & H1: Fixed root-driven symlink traversals in `enable_font_antiblur` and `verify_theme_preservation` with `chown --no-dereference`; fixed self-guard containment in `is_safe_user_path` and introduced `is_safe_home`.
    - C4: Scoped fallback resolver ACCEPT rules in DNS Leak Shield strictly to DNS proxy UID (`-m owner --uid-owner $dns_uid`).
  - **High & Medium (H1–H9, M1–M13)**:
    - H2 & H6: Targeted TOML query_log parser for zero-log truthfulness; hardened live evasion diagnostics against false-positive TLS assertions.
    - H3: Boot persistence systemd unit (`laptop-dpi-mss.service`) for Tier 1 TCP MSS clamping.
    - H4: Pinned Byedpi source builds to commit SHA `3d21c43770335bb549647bb5542a3cf205634594`.
    - H8: Enabled RFC 4941 / RFC 7217 IPv6 privacy extensions (`use_tempaddr=2`, `addr_gen_mode=3`).
    - H9 & M6: Decoupled NetworkManager connectivity check lifecycle from Byedpi; implemented complete Byedpi uninstallation.
    - M7 & M8: Global DHCP hostname privacy via NetworkManager drop-in; preserved Ethernet MAC by default.
  - **UI & Menus**: Fixed raw ANSI escape sequences (`echo -e`) and perfected column alignment in `interactive_dns_menu`.
  - **Testing**: Expanded automated test suite in `tests/test_laptop_linux_optimiser.sh` to 282 passing assertions (Tests 34–40).

## [v0.5.5] - 2026-11-15

### Added
- **DisplayLink EVDI On-Demand & Primary GPU Protection (Module 11)**:
  - Fixed Wayland compositor (`cosmic-comp`, GNOME Mutter, KDE KWin) micro-stutters and texture import failures (`Failed to render texture ..., import for wrong devices DrmNode`) caused by `/etc/modules-load.d/evdi.conf` loading EVDI at boot and stealing primary `/dev/dri/card0` from the hardware GPU.
  - Added `is_evdi_boot_load_enabled`, `is_evdi_card0_hijacked`, `fix_evdi_boot_hijack`, `restore_evdi_boot_hijack`, `toggle_evdi_boot_hijack`, and `show_evdi_status`.
  - Configured EVDI for safe on-demand loading via `displaylink-driver.service` and udev rules (`99-displaylink.rules`) so DisplayLink monitors continue to work seamlessly when docked without displacing the primary hardware GPU.
  - Automatically hooked into `install_touchpad_permanent` to prevent EVDI card0 hijacking out of the box.
- **Precision Touchpad (PTP) Libinput Quirk Sanitization**:
  - Added `touchpad_has_pressure` capability detection checking kernel evdev axes (`ABS_PRESSURE` bit 24 and `ABS_MT_PRESSURE` bit 58).
  - Resolved sporadic initial-touch deadzones and light swipe drops caused by applying `AttrPressureRange=10:8` to Windows Precision Touchpads (PTP) over `hid-multitouch` (such as `ELAN1300:00 04F3:3104`) that lack a hardware pressure axis.
  - Updated `apply_touchpad_quirks` to skip phantom pressure thresholds on zero-pressure devices, avoiding false-positive "hover" classification in libinput.
  - Updated `show_touchpad_quirks_status` to detect and warn about phantom pressure quirks on zero-pressure hardware.
- **One-Click Stutter Remediation Engine (`fix_touchpad_stutter`)**:
  - Implemented `fix_touchpad_stutter` accessible via CLI `./laptop-linux-optimiser.sh touchpad fix-stutter` and TUI menu option 6.
  - Combines EVDI on-demand reconfiguration, libinput pressure sanitization, runtime PM enforcement, C-state cap verification, and GPU PSR verification into a single command.
  - Added CLI dispatchers: `./laptop-linux-optimiser.sh touchpad evdi [status|fix|restore|toggle]` and `tune evdi [status|fix|restore|toggle]`.
  - Added TUI options 6 and 7 to interactive and curses menus.
  - Expanded test suite to 256 automated unit and regression tests (Test 33 expanded with 14 new assertions).

## [v0.5.4] - 2026-11-14

### Added
- **ELAN I2C Touchpad & AMD DesignWare Host Controller Optimization (Module 11)**:
  - Consolidated standalone `elantech/fix-touchpad.sh`, `fix-touchpad-v2.sh`, and `diagnose-elan-irq.sh` directly into `laptop-linux-optimiser.sh` for unified single-script management.
  - Resolved root causes of touchpad dropout, microsecond lag, and sluggish tracking on AMD Ryzen & Intel laptops:
    1. *Idle Dropout*: AMD DesignWare I2C controller (`AMDI0010:xx`) aggressive runtime autosuspend (1000ms timeout) drops initial touch interrupts. Fixed by enforcing controller `power/control="on"` via udev rule (`99-elan-power.rules`) and post-resume hook (`99-elan-resume.sh`).
    2. *Mid-Drag Dropout*: Deep CPU C3 idle state exit latency (350 µs) starves I2C FIFO transfer buffers during continuous finger movement. Fixed by capping CPU idle C-states via `processor.max_cstate=2`.
    3. *Sluggish Tracking & Initial Touch Deadzone*: Missing libinput hardware resolution hint and high default pressure thresholds cause heavy, slow pointer acceleration and micro-delay on touch. Fixed by installing `/etc/libinput/local-overrides.quirks` with calibrated `AttrResolutionHint=31x31` and light `AttrPressureRange=10:8` matching `*ELAN*Touchpad*` and vendor `0x04F3`.
    4. *Microsecond Wake-Up Stutter*: AMDGPU and Intel Panel Self Refresh (PSR) / Panel Replay puts the display engine to sleep during static frames, delaying cursor updates by 100-200ms upon initial touch. Fixed by disabling PSR via bootloader kernel parameters (`amdgpu.dcdebugmask=0x410` for AMD GPUs, `i915.enable_psr=0` for Intel GPUs).
  - Implemented multi-bootloader detection and management (`detect_bootloader_type`, `apply_touchpad_cstate_cap`, `apply_touchpad_psr_fix`, `remove_touchpad_psr_fix`, `toggle_touchpad_psr_fix`):
    - Pop!_OS: native `kernelstub` integration (`processor.max_cstate=2` and `amdgpu.dcdebugmask=0x410` / `i915.enable_psr=0`).
    - Ubuntu / Debian / Linux Mint: GRUB drop-in configuration (`/etc/default/grub.d/99-touchpad-cstate.cfg` with `update-grub`).
  - Added dedicated libinput quirks management (`apply_touchpad_quirks`, `remove_touchpad_quirks`, `toggle_touchpad_quirks`, `is_touchpad_quirks_installed`).
  - Automatically installed live diagnostic tracer (`diagnose-elan-irq.sh`) to `/usr/local/sbin/diagnose-elan-irq.sh`.
  - Added CLI dispatchers: `./laptop-linux-optimiser.sh touchpad [status|install|revert|runtime|cstate|psr|quirks|diagnose|menu]` and `tune touchpad [status|toggle|install|revert|runtime|cstate|psr|quirks]`.
  - Added Interactive TUI Dashboard Option 13 (`[Tt]` Touchpad Tuning) with full dialog / whiptail menus.
  - Added real-time summary indicator: `ELAN Touchpad PM` in `show_system_summary()`.
  - Expanded test suite to 242 automated unit and regression tests (Test 33 expanded).
- **Byedpi Flag Management & Desynchronization Presets Engine (Module 10)**:
  - Added dynamic Byedpi flags management system (`get_byedpi_flags`, `set_byedpi_flags`) backed by `/etc/byedpi.conf` and `byedpi.service` auto-reloading.
  - Built-in tested desynchronization presets:
    - `standard`: `-K tls -s 1 -d 1+s -f -1 -t 8` (Classic out-of-order reverse split)
    - `tlsrec`: `-K tls -r 1+s -s 1+s` (RFC-compliant multi-record split, zero TTL drops)
    - `aggressive`: `-K tls -r 1+s -s 1 -d 1+s -f -1 -t 5 -S` (Record split + disorder + fake + MD5)
    - `fake-sni`: `-K tls -s 1+s -f 1+s -n www.google.com -t 5` (Fake Google SNI poisoning)
    - `auto`: `-A torst,redirect,ssl_err -L 3 -u 3600 -K tls -r 1+s -s 1 -d 1+s -f -1 -t 5` (Adaptive heuristic)
  - Added CLI command: `./laptop-linux-optimiser.sh dpi byedpi flags [preset|"custom flags"]`.
  - Added active flags readout to `show_dpi_status`.

## [v0.5.3] - 2026-11-13

### Fixed
- **NetworkManager Captive Portal Probe Deadlock with Transparent Proxies (Byedpi)**:
  - Fixed an issue where Flatpak applications (such as Sitra font preview) falsely reported "No Internet connection" despite full working network access.
  - Resolved root-cause conflict: NetworkManager's periodic HTTP connectivity probe (`http://204.pop-os.org/`) uses `SO_BINDTODEVICE` on `wlp1s0`. When Byedpi transparent NAT redirection (`iptables -t nat ... -j REDIRECT --to-ports 1080`) is active, packets bound to the physical Wi-Fi interface cannot be routed to loopback (`127.0.0.1`), causing NetworkManager's 20-second probe timeout.
  - Because of the probe failure, NetworkManager placed the system into `CONNECTIVITY: limited` (state `2`) and applied a `+20000` metric penalty to the default route. `xdg-desktop-portal` relayed this limited status to Flatpak sandboxes, where GLib's `GNetworkMonitor` strictly checked for full connectivity (`4`).
  - Added `disable_nm_connectivity_check`, `enable_nm_connectivity_check`, `toggle_nm_connectivity_check`, and `status_get_nm_connectivity` management helpers.
  - Automatically hooked `disable_nm_connectivity_check` into `byedpi_rules_add` to install `/etc/NetworkManager/conf.d/20-connectivity.conf` (`[connectivity] enabled=false`) and set the runtime D-Bus property `ConnectivityCheckEnabled=false`.
  - Added CLI dispatchers for `connectivity` and `tune connectivity [status|toggle|disable|enable]`.
  - Added Test 32 (9 new unit test assertions) expanding automated test coverage to 197 passing assertions.
- **Byedpi Protocol Whitelist & SNI Desync Cancellation Fix**:
  - Fixed an issue where non-TLS traffic (HTTP port 80, gRPC, and non-SNI packets) caused Byedpi (`ciadpi`) to fail SNI offset extraction with `split cancel: pos=0--1`, cancelling packet segmentation and falling back to unfragmented transmission.
  - Added `-K tls` protocol whitelisting to `byedpi.service` along with ascending byte segmentation (`-K tls -s 1 -d 1+s -f -1 -t 8`), ensuring TLS ClientHello is reliably segmented across the SNI boundary without cancelling on non-TLS flows.
  - Enhanced `test_dpi_evasion` with Cloudflare endpoint trace analysis (`sni=plaintext` vs `sni=encrypted` ECH status) and Byedpi journal cancellation warnings. Expanded test suite to 198 assertions.

## [v0.5.2] - 2026-11-12

### Fixed
- **Local Hostname Resolution Stalls & Firefox Cold-Boot Delay**:
  - Resolved a **2-minute cold-boot freeze** where Firefox and other local desktop services hung when clicked immediately after system boot.
  - Implemented `get_system_hostname()` helper that dynamically determines the active machine hostname (via `hostnamectl`, `hostname -s`, `/etc/hostname`, or `uname -n`) without hardcoding.
  - Implemented `ensure_hostname_resolution()` to map the detected system hostname to `127.0.1.1` in `/etc/hosts` if missing, completely preventing synchronous `PR_GetHostByName(hostname)` stalls during Firefox profile locking (`nsProfileLock::LockWithSymlink`).
  - Automatically hooked `ensure_hostname_resolution` into `setup_system_dns()`, `enable_dhcp_privacy()`, `apply_system_tuning()`, and provided CLI dispatchers (`dns hosts` / `tune hosts`).
- **`dnscrypt-proxy` Boot-Time Circular Resolver Deadlock**:
  - Injected explicit fallback resolvers (`fallback_resolvers = ['9.9.9.9:53', '149.112.112.112:53', '1.1.1.1:53', '1.0.0.1:53']`) and enabled `ignore_system_dns = true` in `/etc/dnscrypt-proxy/dnscrypt-proxy.toml`.
  - Neutralized a 120-second circular dependency where `dnscrypt-proxy` attempted to query the local system resolver (`systemd-resolved` -> `127.0.2.1`) before upstream relay/source lists were fetched. `dnscrypt-proxy` now directly bootstraps over UDP port 53 (whitelisted in `laptop-dns-shield`) in <1s.
- **DNS Leak Shield Shutdown Deadlock & Persistence**:
  - Separated unit lifecycle management from runtime netfilter rule enforcement (`apply` and `clear` commands). `ExecStop` now only flushes netfilter rules without recursively invoking `systemctl stop`, deleting unit files, or running `daemon-reload`, eliminating a 90-second shutdown hang. Added `TimeoutStopSec=5s` safety threshold.
- **System Resolver DNSSEC Loopback Validation (`missing-key`)**:
  - Changed `DNSSEC=allow-downgrade` to `DNSSEC=no` in `/etc/systemd/resolved.conf.d/dnscrypt.conf`.
  - Resolved `DNSSEC validation failed: missing-key` errors where `systemd-resolved` rejected valid answers from `127.0.2.1` (`dnscrypt-proxy`), preventing glibc/NSS lookups from resolving and causing "System resolver still settling or failing" warnings. DNSSEC validation remains handled by the upstream encrypted resolver.

## [v0.5.1] - 2026-11-12

### Changed
- **Suite Consolidation (`laptop-linux-optimiser.sh`)**:
  - Consolidated all platform scripts (`pop-admin.sh`, `mint-admin.sh`, and `laptop-optimizer.sh`) into a single, unified master script: `laptop-linux-optimiser.sh`.
  - Deleted legacy scripts (`pop-admin.sh`, `mint-admin.sh`, `laptop-optimizer.sh`) matching the GitHub repository name (`laptop-linux-optimiser`).
  - Canonical installation path unified to `/usr/local/sbin/laptop-linux-optimiser` with automatic backward-compatible symlinks for `pop-admin`, `mint-admin`, and `laptop-optimizer`.
  - Consolidated automated test suite into `tests/test_laptop_linux_optimiser.sh` with 178 passing assertions.

### Fixed
- **Tier 1 Transport Handshake Framing & TCP MSS Clamping Inversion**:
  - Corrected netfilter clamping direction from `OUTPUT --dport` to `INPUT --sport 80,443 --tcp-flags SYN,ACK SYN,ACK -j TCPMSS --set-mss 536` (and IPv6 twin). Clamping incoming SYN-ACK forces the peer to lower advertised send MSS, successfully splitting outgoing TLS ClientHellos across packets and neutralizing shallow packet inspection.
  - Enforced strict input validation (`536 <= MSS <= 1460`) before flushing state or applying rules, preventing TCP blackholes from values below IPv4 minimum (536).
  - Added `-w 5` to all iptables and ip6tables invocations to prevent xtables lock contention races with Docker, ufw, and NetworkManager.
  - Eliminated rule accumulation by purging existing matching rules before inserting new ones.
- **DNS Leak Shield Bootstrap Deadlock & Persistence**:
  - Whitelisted `_dnscrypt-proxy` and `dnscrypt-proxy` system accounts before outbound DROP rules.
  - Whitelisted upstream bootstrap / fallback resolvers (`9.9.9.9`, `149.112.112.112`, `1.1.1.1`, `1.0.0.1`, `2620:fe::fe`, `2606:4700:4700::1111`) before DROP rules, preventing boot-time chicken-and-egg DNS deadlocks when fetching resolver lists.
  - Resolved **90-second shutdown deadlock** and ~2s boot delay in `laptop-dns-shield.service`: separated unit lifecycle management from runtime rule enforcement (`apply` and `clear` commands). `ExecStop` now only flushes netfilter rules without recursively invoking `systemctl stop`, deleting unit files, or running `daemon-reload`. Added `TimeoutStopSec=5s` safety threshold.
  - Added `laptop-dns-shield.service` systemd unit and state file tracking for boot persistence.
  - Added active resolver check that warns before activating the shield if `dnscrypt-proxy` is inactive.
- **True Anonymized Multi-Hop Relays (DNSCrypt)**:
  - Refactored profiles 8–10 to utilize true DNSCrypt-protocol resolvers (`cs-de`, `cs-ch`, `quad9-dnscrypt-ip4-filter-pri`, `scaleway-ams`) so dnscrypt-proxy actually routes queries through independent multi-hop relays instead of connecting directly to DoH server IPs.
  - Updated status reporting to accurately verify whether active resolvers use DNSCrypt before declaring anonymized relays active.
- **Transport Reachability Diagnostic Probe Correction**:
  - Fixed `test_dpi_evasion` curl response parsing, removing stdout string concatenation (`000FAIL`) that caused non-existent or unreachable domains to falsely report `SUCCESS`.
  - Probe now captures curl's exit code and HTTP status cleanly, accurately reporting `FAILED / TIMEOUT` on connection drops or RST injection.
- **Tier 2 Userspace Transport Shaper Hardening**:
  - Added IPv6 NAT transparent redirection via `ip6tables -w 5 -t nat -I OUTPUT 1 ... -j REDIRECT`.
  - Excluded local loopback ranges (`! -d 127.0.0.0/8` and `! -d ::1/128`) to prevent hijacking local development servers on port 443.
  - Excluded `_dnscrypt-proxy`, `dnscrypt-proxy`, and `debian-tor` UIDs from redirection to prevent proxy loops.
  - Bound daemon to dual-stack `::`, dropped unnecessary `AmbientCapabilities=CAP_NET_BIND_SERVICE`, and enforced `NoNewPrivileges=yes`.
  - Tied iptables redirection rules directly to daemon lifecycle via systemd `ExecStartPost=` and `ExecStopPost=`, preventing boot desync and eliminating port 80/443 blackouts when the service stops.
  - Added SHA-256 cryptographic verification and `--fail` flag to daemon binary downloads.
- **Non-Root Status Reporting**:
  - Updated `status_get_dpi` and `status_get_dns_shield` to inspect persistent state files when invoked by non-root users, eliminating false `DISABLED` reports caused by non-root `iptables -C` permission failures.
- **Lock Re-Entrancy**:
  - Added `OPTIMIZER_LOCKED` environment tracking to `acquire_lock` so nested function calls and TUI subshells do not abort with "Another instance is running".

### Added
- **Transport Integrity & Anti-Throttling Engine (Tier 1 & Tier 2)**:
  - **Tier 1 (In-Kernel Framing)**: TCP MSS adjustment on incoming SYN-ACK (`iptables -w 5 -t mangle -A INPUT -p tcp -m multiport --sports 80,443 --tcp-flags SYN,ACK SYN,ACK -j TCPMSS --set-mss 536`). Induces packet boundary segmentation on connection handshakes, neutralizing shallow middlebox packet inspection and stream throttling with zero userspace dependencies.
  - **Tier 2 (Userspace Transport Shaper)**: Optional dual-stack userspace transport multiplexer (`byedpi` / `ciadpi`) providing packet segmentation and out-of-order delivery to mitigate intrusive middlebox throttling on restrictive links.
  - **Systemd Daemon & Loopback Isolation**: Automatically compiles and manages `/usr/local/bin/ciadpi` with `/etc/systemd/system/byedpi.service` running as dedicated system user `byedpi`. Transparent redirection rules explicitly exclude `--uid-owner byedpi` and local loopback traffic.
  - **Interactive Transport Toggle Hub & TUI**: Option 12 / `[D]` in TUI Dashboard, Whiptail modal dialog support, and dedicated CLI controls via `dpi [menu | status | test | off | mss | byedpi]`.
  - **Transport Integrity Probe**: Integrated diagnostic probe verifying handshake timing and reachability.
- **DNS Privacy Hardening & Zero-Log In-Memory Caching**:
  - `apply_dnscrypt_config` zeroes out on-disk `query.log` and `nx.log` paths (`file = ''`), preventing query histories from writing to unencrypted storage.
  - Configures high-performance local RAM cache (`cache = true`, `cache_size = 8192`, `cache_min_ttl = 2400`, `cache_max_ttl = 86400`).
  - Dynamic IPv6 sync: aligns `block_ipv6` in `dnscrypt-proxy.toml` with the system's active IPv6 status from Module 8.
  - `setup_system_dns` hardens `systemd-resolved` drop-in configuration with `LLMNR=no`, `MulticastDNS=no`, and `DNSSEC=allow-downgrade` to eliminate local network name leakage and DNSSEC failure deadlocks.
- **Strict DNS Leak Shield (Killswitch)**:
  - Implemented iptables DNS Leak Shield blocking all outbound cleartext UDP and TCP traffic on port 53 across network interfaces while allowing loopback resolution to `127.0.0.1` and `127.0.2.1`.
  - Added CLI controls via `dns shield [status | toggle | enable | disable]`.
  - Integrated `[S] 🛡️ Toggle DNS Leak Shield` shortcut in the Interactive DNS Profile Menu.
  - Integrated DNS Leak Shield live status indicators across CLI summary, diagnostics, and dashboard.
- **Testing**:
  - Expanded test coverage across `tests/test_audit_fixes.sh` (144 tests) and `tests/test_pop_admin.sh` (155 tests) to a total of **299 passing automated assertions**.

## [v0.4.0] - 2026-11-10

### Added
- **Pop!_OS & COSMIC Desktop Edition Support (`pop-admin.sh`)**:
  - Full dedicated administration suite for Pop!_OS 24.04 LTS and the COSMIC Desktop Environment.
  - Retains `mint-admin.sh` for Linux Mint Cinnamon compatibility.
- **OS Platform Detection & Target OS Switching**:
  - Auto-detects `Pop!_OS (COSMIC DE)` vs `Linux Mint (Cinnamon)` with manual switching via `pop-admin os [popos|mint|toggle|status]`.
  - Automatic suppression of font overrides on COSMIC DE where Wayland subpixel font rendering is sharp natively.
- **Pop!_OS Native ZRAM Integration**:
  - Detects `pop-default-settings-zram` (zstd algorithm) and recognizes swappiness 180 as optimal.
- **Network Printer Discovery & LocalSend Preservation**:
  - `cups-browsed` (UDP 631) is protected from automatic disabling so Wi-Fi/network printers are auto-discovered without disruption.
  - `avahi-daemon` (mDNS) is preserved to ensure peer-to-peer file transfers with LocalSend and `.local` hostnames remain functional.
- **SSH Inbound Shield & Hardening**:
  - Added dedicated SSH server masking controls via `pop-admin ssh [mask|unmask|toggle|status]`.
- **7-Step Guided Optimization Wizard**:
  - Step-by-step interactive onboarding: OS Selection -> Updates -> Battery Limiter -> Network Speed -> Security -> DNS -> Printer Preservation.
- **Universal Launcher**:
  - `laptop-optimizer.sh` dynamically routes to `pop-admin.sh` or `mint-admin.sh` based on platform availability.
- **Testing**:
  - Added `tests/test_pop_admin.sh` with 120 passing automated test checks.

## [v0.3.2] - 2026-11-09

### Added
- **Subpixel Font Anti-Blur & High-DPI Scaling (Flatpak/Cinnamon/Wayland/X11)**:
  - Added dedicated toggle control for font anti-blur via `mint-admin antiblur [status | toggle | enable | disable]` and `mint-admin tune antiblur`.
  - Configures fontconfig (`~/.config/fontconfig/fonts.conf`) with `antialias=true`, `hinting=true`, `hintstyle=hintfull`, `rgba=rgb`, and `lcdfilter=lcddefault`.
  - Configures GTK 3 & GTK 4 `settings.ini` with subpixel XFT rendering properties (`gtk-xft-antialias`, `gtk-xft-hinting`, `gtk-xft-hintstyle=hintfull`, `gtk-xft-rgba=rgb`, and scaled DPI).
  - Configures global Flatpak sandbox overrides (`~/.local/share/flatpak/overrides/global`) with `--filesystem=xdg-config/fontconfig:ro`, `--filesystem=xdg-data/fonts:ro`, and `--env=ELECTRON_OZONE_PLATFORM_HINT=auto` to eliminate blurry font rendering in Flatpak Chromium/Electron/GTK apps across both X11 and Wayland sessions.
- **TUI Dashboard & Tuning Menu Integration**:
  - Added live status pill `Font Anti-Blur : [ ACTIVE (Subpixel RGB) ]` across Dashboard, System Summary (`mint-admin summary`), and Tuning Status (`mint-admin tune status`).
  - Added notification alert in `NOTIFICATIONS & MAINTENANCE ADVISORY` banner when font blurriness is detected:
    `● Flatpak text blurriness detected.     [Press F to Fix Anti-Blur]`
  - Added `[F] 🔍 Fix / Toggle Font Anti-Blur` in Management Actions and Option 9 Interactive Tuning Hub.
  - Added curses dialog toggle entry in Whiptail modal GUI mode.
- **Testing**:
  - Added Test 23 to `tests/test_audit_fixes.sh`, expanding automated test coverage to 109 passing checks.

## [v0.3.1] - 2026-11-09

### Fixed
- **Cleaner Single-Pass Optimization**:
  - Fixed duplicate cleaner execution on interactive startup: replaced chained `update_and_clean` + `run_optimizer` calls with unified single-pass `run_full_update_and_optimizer`.
  - Eliminated redundant intermediate prompt steps and duplicate summary banners.
  - Added `[A] / all` option in the TUI dashboard menu and notification advisory for one-key all-in-one update and housekeeping.
- **Cinna-Themes & Desktop Theming Preservation**:
  - Safeguarded Flatpak theme runtimes: `clean_flatpak()` now pins all installed `org.gtk.Gtk3theme.*` and `org.kde.KStyle.*` runtimes (system and user) prior to running `flatpak uninstall --unused -y`.
  - Added `verify_theme_preservation()` helper in `clean_user_cache()` and `clean_privacy()` ensuring user Flatpak sandbox overrides (`~/.local/share/flatpak/overrides/global`), theme directories (`~/.themes`), icon packs (`~/.icons`, `~/.local/share/icons`), and GTK 3/4 styling (`~/.config/gtk-3.0`, `~/.config/gtk-4.0`) remain intact and uncorrupted.
- **Testing**:
  - Added Test 22 to `tests/test_audit_fixes.sh`, expanding automated test coverage to 97 passing checks.

## [v0.3.0] - 2026-11-04

### Added
- **NetworkManager Wait-Online Delay Toggle (Fast Desktop Boot)**:
  - Added dedicated toggle control for `NetworkManager-wait-online.service` via `mint-admin wait-online [status | toggle | enable | disable]` and `mint-admin tune wait-online`.
  - Disabling removes ~7s delay on desktop boot time without affecting graphical session initialization.
  - Added live status pill (`[✓ FAST BOOT (Disabled)]` / `[● ENABLED (~7s delay)]`) across Dashboard, Summary, and Tuning menus.
- **Full Subsystem Toggles (Zero Options Left Without Toggle)**:
  - Every tuning and optimization option displayed in status and diagnostics now possesses an individual toggle:
    - **NM Wait-Online Delay**: `toggle_nm_wait_online`
    - **Google TCP BBR Congestion Control**: `toggle_bbr`
    - **Memory Swappiness (100 vs 60) & VFS Cache**: `toggle_swappiness`
    - **ZRAM 50% Compressed RAM Swap**: `toggle_zram`
    - **DHCP Hostname Leak Shield**: `toggle_dhcp_privacy`
    - **Kernel Memory Privacy Hardening (dmesg & kptr)**: `toggle_kernel_hardening`
    - **Avahi mDNS Discovery Broadcast Daemon**: `toggle_avahi`
    - **CUPS Network Printer Polling (UDP 631)**: `toggle_cups_browsed`
    - **ModemManager Cellular Serial Scanner**: `toggle_modemmanager`
    - **All 3 Broadcast Daemons**: `toggle_broadcast_daemons`
  - All toggles are exposed in CLI: `mint-admin tune <subsystem> [toggle|enable|disable|status]`.
- **Interactive Performance, Privacy & Startup Toggle Hub (`Option 9` / `mint-admin tune menu`)**:
  - Full-screen interactive hub presenting live indicators for all subsystems and 1-key instant toggles.
- **Modern Curses / Ink-Style Terminal UI**:
  - Upgraded ANSI Terminal Dashboard with Ink-style framing, Unicode box drawing (`╭─╮│╰─╯`, `┌─┐│└─┘`), and high-contrast status pill badges.
  - Upgraded Curses / Whiptail GUI modal mode (`mint-admin tui --dialog` or `[D]`) with full curses dialog submenus for Tuning, Battery, MAC, and Timers.
- **Comprehensive Automated Test Suite**:
  - Expanded test suite to 92 automated tests in `tests/test_audit_fixes.sh` covering live sysctls, interface filters, TOML parsing, intermediate symlink traversal protection, non-TTY input, systemd units, and subsystem toggles.

### Fixed & Hardened (Complete Security & Logic Audit Remediation)
- **Critical #1 - DHCP Hostname Leak Shield Enforcement**:
  - Replaced unsupported `/etc/NetworkManager/conf.d/` connection drop-in key with native NetworkManager profile modification: `nmcli con modify "$uuid" ipv4.dhcp-send-hostname no ipv6.dhcp-send-hostname no`.
  - Updated `status_get_dhcp()` to directly inspect active connection profile state via `nmcli -g ipv4.dhcp-send-hostname` rather than relying on conf file existence.
- **Critical #2 - Symlink Containment & Intermediate Traversal Immunity**:
  - Implemented `is_safe_user_path "$user_home" "$target"` with realpath canonicalization and intermediate component walk to prevent directory traversal and symlink hijacking across `/root` and `/home/*`.
  - Guarded all destructive operations in `clean_privacy()` (recent files, browser caches, thumbnail previews, trash bins) and `clean_user_cache()` against both leaf and intermediate symlinks.
- **Critical #3 & #4 - Encrypted DNS Relays & Verification Fail-Stop**:
  - Upgraded DNSCrypt anonymized relay sources to `resolvers-list/v3/relays.md` for `dnscrypt-proxy >= 2.0.45`.
  - Added dynamic relay extraction from cached relays list via `get_active_relays()`, eliminating invalid/defunct relay names (`anon-ibksturm`, `anon-tiar-nl`).
  - Added pre-modification `.bak` config snapshots and implemented `activate_dns_config()` helper ensuring resolution failure aborts with proper error logging rather than falsely declaring success.
  - Hardened Tor SOCKS proxy configuration injection to verify active Tor daemon and validate successful top-level TOML placement.
- **Critical #5 - Systemd Timer Privilege Escalation Fail-Stop**:
  - Hardened `install_weekly_timer()` to abort with an error if copying/installing to root-owned canonical `/usr/local/sbin/mint-admin` fails, strictly preventing systemd unit from pointing to unprivileged user home paths.
  - Quoted `Documentation="file://$exec_target"` in systemd unit definitions to handle paths with whitespace without `systemd-analyze verify` errors.
  - Updated `uninstall_weekly_timer()` to remove `/usr/local/sbin/mint-admin`.
- **Critical #6 - Dashboard & Whiptail Subshell Isolation**:
  - Wrapped interactive actions in `run_menu_action` and `run_whiptail_action` using isolated subshells `( "$@" ) || rc=$?` so non-root `check_root` exit code 1 does not terminate the dashboard session.
  - Guarded `show_tui_dashboard` against non-TTY stdin (`[ -t 0 ] || { show_help; return 0; }`).
- **High #7 - TCP FastOpen Baseline Restoration**:
  - Updated `disable_bbr` to restore `net.ipv4.tcp_fastopen` to recorded `BASE_FASTOPEN` rather than leaving it stuck at 3.
- **High #8 - Tuning Baseline State Preservation**:
  - Enhanced `save_tuning_baseline` to record baseline active states of `avahi-daemon`, `cups-browsed`, `ModemManager`, and `NetworkManager-wait-online.service`.
  - Updated `revert_system_tuning` to restore services to their exact prior baseline state instead of unconditionally forcing all daemons active.
- **High #9 - Swappiness Status Condition**:
  - Fixed swappiness status condition to strictly check `[ "$swappiness" -eq 100 ]` rather than `-le 100`.
- **High #10 & #14 - Non-Interactive `-y`/`--force` & MAC Cycling Prompt**:
  - Wired `FORCE_YES` across destructive actions (`clean_privacy`, `run_complete_suite`).
  - Added confirmation prompt before network MAC address cycling in `run_complete_suite` unless `--force` / `-y` is passed.
- **High #11 - Single-Label DNS Leak Shield**:
  - Added `[global-dns]` with empty `searches=` to NetworkManager drop-in and `ResolveUnicastSingleLabel=yes` to systemd-resolved drop-in to prevent `.lan` lookup leaks.
- **High #12 - Concurrency Mutex Lock**:
  - Added `acquire_lock()` using `flock -n 200` on `/var/run/mint-admin.lock` during privileged execution.
- **High #13 - Privacy Scrubbing Safety**:
  - Added confirmation prompt before purging `/var/crash/*` and core dumps in `clean_privacy` unless `--force` is specified.
  - Added automatic rotation/truncation for dnscrypt query log if it exceeds 10MB during housekeeping.
- **Medium & Hygiene Fixes**:
  - Quoted `$0` in `check_root` guidance hints to handle paths containing spaces safely.
  - Hardened battery sysfs node traversal to handle spaces safely using newline splitting.

## [v0.2.1] - 2026-11-01

### Changed
- **UI & Terminology Refinement**:
  - Replaced all dashboard occurrences of the term "telemetry" with "Live System Status" (`LIVE SYSTEM & HARDWARE STATUS` and `Refresh Status`) to eliminate user privacy concerns and reinforce that all subsystem health checks are strictly local.
  - Updated documentation, test suite descriptions, and roadmap items to use clean status reporting terminology.

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
