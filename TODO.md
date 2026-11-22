# Project Roadmap & TODO

## Active Issues & Immediate Tasks

### [ ] ELAN I2C Touchpad Latency & Cursor Lag on AMD Ryzen Platforms
- **Target Platforms**: AMD Ryzen Laptops (ThinkPad, ASUS Zenbook, Framework, Lenovo IdeaPad) with ELAN I2C touchpads (e.g., `ELAN1300`, `ELAN0676`, `ELAN0515` over DesignWare I2C `AMDI0010:xx` and `pinctrl_amd`).
- **Target Script**: `laptop-linux-optimiser.sh`, `diagnose-elan-irq.sh`, and `elantech/`.

#### Problem Context
Users report that the touchpad feels "laggy", "sluggish", or experiences cursor micro-stutter/dropped samples during continuous motion or upon initial touch:
1. **Interrupt Rate & DesignWare I2C Polling Latency**:
   - The AMD DesignWare I2C controller (`AMDI0010:xx`) uses ACPI-configured interrupt pins mediated by `pinctrl_amd`.
   - On kernels 6.5+, latency spikes occur if interrupt lines are throttled or if the I2C host clock is scaled down aggressively during runtime PM.
2. **APU C-State Wakeup Delay**:
   - When the cursor is still, CPU cores quickly drop into deep C-states (C3 / C6).
   - Upon initial finger touch, the I2C interrupt wakeup latency through the AMD GPIO interrupt controller causes a noticeable 20-50ms deadzone or missed initial displacement.
3. **Panel Self Refresh (PSR) & Panel Replay Delays**:
   - AMDGPU eDP Panel Self Refresh (`amdgpu.dcdebugmask=0x410`) or Intel PSR (`i915.enable_psr=0`) causes frame drops and delayed cursor redraw during low-framerate bursts or compositor sleep.
4. **Libinput Motion Accel & Flat Speed Curve Mismatch**:
   - Default adaptive acceleration curves with missing or incorrect `AttrResolutionHint` can make precision glass touchpads feel heavy, delayed, or jerky.
5. **Compositor Render Sync & EVDI / DisplayLink Conflicts**:
   - DisplayLink (`evdi`) modules stealing `card0` or frame sync delays between Mutter/KWin/COSMIC and Wayland clients.

#### Implementation Tasks
1. **Enhanced Diagnostic & Profiling Engine**:
   - [ ] Add real-time report rate checker (`evhz` / `libinput measure touch-size` / `libinput record` runner) to measure actual touch poll frequency (aiming for 125Hz-140Hz native ELAN tracking).
   - [ ] Trace I2C bus transactions via `ftrace` / `/sys/kernel/tracing/events/i2c/` to detect timeout retries or clock stretching by `AMDI0010`.
   - [ ] Verify IRQ storm or missed interrupts in `/proc/interrupts` for `AMDI0010` and `pinctrl_amd`.
2. **Kernel & Driver Tuning**:
   - [ ] Test and evaluate `i2c-hid` vs `hid-multitouch` driver parameters (e.g. `i2c_designware_core` clocking, polling vs edge-triggered IRQ).
   - [ ] Provide dedicated libinput speed curve profile (`accel-profile=adaptive` vs `flat`, customized acceleration speed).
   - [ ] Validate runtime PM settings for AMD host controller (`/sys/bus/platform/drivers/i2c_designware/AMDI0010:*/power/control`).
   - [ ] Add option to lock minimum CPU frequency or deeper C-state cap (`processor.max_cstate=2` vs `intel_idle.max_cstate=1` / `amd_iommu=off`).
3. **CLI & TUI Integration**:
   - [ ] Add `./laptop-linux-optimiser.sh touchpad lag-test` or `touchpad bench` to test and report live polling rate and event latency.
   - [ ] Expose aggressive latency preset vs power-saving preset in `interactive_touchpad_menu`.

## Upcoming Features (Planned for v0.6.0)

### [ ] Wayland Xorg/X11 Application Discovery & Autofix
- **Target Platforms**: Pop!_OS 24.04 (COSMIC Desktop Edition), Linux Mint (Wayland Session), and Ubuntu/Debian.
- **Target Script**: `laptop-linux-optimiser.sh`.

#### Problem Context
Legacy administrative GUI utilities requiring superuser elevation (via `pkexec` or `sudo`), such as `gufw`, `synaptic`, `timeshift-gtk`, `gparted`, and `bleachbit`, fail under Wayland with display connection crashes (e.g., `Gtk-ERROR: Can't create a GtkStyleContext without a display connection` or `Authorization required, but no authorization protocol specified`).
- Root cause 1: `pkexec` drops environment variables (`DISPLAY`, `XAUTHORITY`, `WAYLAND_DISPLAY`).
- Root cause 2: XWayland blocks the root user (`uid 0`) from the display socket by default.
- Root cause 3: Pure Wayland sockets disallow root graphical clients, requiring explicit fallback to X11 (`GDK_BACKEND=x11`).

#### Implementation Tasks
1. **Audit & Discovery Engine**:
   - [ ] Implement `detect_display_server` (`wayland` vs `x11`).
   - [ ] Implement `is_xwayland_root_allowed` (check `xhost` output for `SI:localuser:root`).
   - [ ] Implement `audit_wayland_apps` to scan for installed root GUI apps (`gufw`, `synaptic`, `timeshift-gtk`, `gparted`, `bleachbit`).
   - [ ] Report patch status for each detected app.

2. **Autofix & Compatibility Engine**:
   - [ ] Implement `enable_wayland_compat`:
     - [ ] Deploy `/etc/xdg/autostart/xhost-wayland-compat.desktop` (`xhost +si:localuser:root`).
     - [ ] Apply immediate live authorization (`xhost +si:localuser:root`).
     - [ ] Safely patch `gufw` and `gufw-pkexec` with `.bak` safety backups.
     - [ ] Ensure `GDK_BACKEND=x11` fallback for affected legacy tools.
   - [ ] Implement `disable_wayland_compat` / `revert`:
     - [ ] Remove autostart entry.
     - [ ] Revoke XWayland root authorization (`xhost -si:localuser:root`).
     - [ ] Restore `.bak` files for any patched binaries.
   - [ ] Implement `toggle_wayland_compat` (instant toggle switch).

3. **CLI & TUI Integration**:
   - [ ] Add CLI commands: `laptop-linux-optimiser wayland [status|audit|fix|revert|toggle]` and `tune wayland [enable|disable|toggle|status]`.
   - [ ] Add live status indicator to `show_tuning_status()` and `show_system_summary()`.
   - [ ] Add `[W]` hotkey to interactive tuning menu.
   - [ ] Add TUI dashboard indicator pill (`[ WAYLAND: COMPATIBLE ]` / `[ WAYLAND: BLOCKED ]` / `[ WAYLAND: N/A (X11) ]`).
   - [ ] Add Wayland check step to guided wizard (`run_guided_wizard`).

4. **Testing & QA**:
   - [ ] Add Wayland Xorg App Compatibility test assertions to `tests/test_laptop_linux_optimiser.sh`.
   - [ ] Verify 100% test pass rate.

5. **Documentation & Release**:
   - [ ] Update `README.md` documentation table and CLI guide.
   - [ ] Update `CHANGELOG.md` for `[v0.6.0]`.
