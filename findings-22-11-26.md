# Audit: `laptop-linux-optimiser.sh` v0.5.15 — Fix Verification & Optimisation Assessment

**Date:** 22 November 2026
**Scope:** Static review of the 9,027-line script against the two prior audits (`audit.md` for the pre-consolidation `mint-admin.sh`, and `audit-privacy-security.md` for v0.5.5), plus assessment of the applied tuning choices.
**Verification:** `bash -n` passes; all 441 test assertions in `tests/test_laptop_linux_optimiser.sh` pass. `shellcheck` is not installed in this environment.

---

## 1. Fix verification — what is genuinely fixed

### Critical fixes confirmed in the current code

| Prior finding | Status | Evidence |
|---|---|---|
| **Root symlink attack** in privacy scrub | ✅ Fixed | `is_safe_user_path` (line 173) now has a correct self-guard (`real_target == real_h → return 0`, lines 187–190) *and* strict child containment with per-component symlink rejection (lines 196–206). `clean_privacy`/`clean_user_cache` loops use `is_safe_home "$h"` (line 2067) or `is_safe_user_path "$h" "$h"` + `[ -L "$h" ] && continue`. Thumbnail/Trash purges use `find ... ! -type l -delete` — symlink-immune. |
| **Root-owned timer execution** | ✅ Fixed | `install_weekly_timer()` (lines 2278–2296) installs a root-owned copy to `$CANONICAL_BIN` via `install -m 755 -o root -g root` whenever the script lives under `/home/*` or is non-root-owned, and quotes `ExecStart="$exec_target"`. |
| **Tor TOML placement** (keys appended into last `[section]`) | ✅ Fixed | Line 1055: `sed -i "/^server_names =/a proxy = ... force_tcp = true"` — inserted at top level before any section header. |
| **`dig`-only false-positive DNS verification** | ✅ Mostly fixed | Line 1161 requires a real A-record match (`grep -E '^[0-9]+...'`), not just exit status; line 1170 checks `resolvectl dns` for the proxy route and reports *whether* the system query is routed via the proxy. |
| **`FallbackDNS` leak** | ✅ Fixed | `FallbackDNS=` cleared in the resolved drop-in (line 1116). |
| **DNS zero-log false positive** | ✅ Fixed | `show_dns_status` now awk-parses only the `[query_log]` table (line 1361) and reports `LOGGING ACTIVE (file)` otherwise; the scrub regex no longer requires an absolute path (line 1028). `clean_privacy` also truncates the live `query.log` (line 1761). |
| **Battery udev event loop** | ✅ Largely fixed | Inline write-loop removed; the Mains rule now just `systemctl --no-block restart` a oneshot (lines 746/842), and direct ATTR writes are idempotent-on-match. |
| **MAC randomness & session kill** | ✅ Fixed | `generate_random_mac()` uses `od -An -N5 -tx1 /dev/urandom` with the `02:` locally-administered prefix (line 1537); `randomize_mac()` detects SSH sessions and skips bouncing the default-route interface (lines 1636–1643), and reports the *actual* post-change MAC rather than unconditional "Updated". |
| **`revert_system_tuning()` hardcoded guess** | ✅ Fixed | `save_tuning_baseline()` (line 2372) captures real prior sysctl/service state; revert restores from it, re-enables `ModemManager`/avahi/cups per captured state, and handles `avahi-daemon.socket`. |
| **Swappiness 10 + ZRAM contradiction** | ✅ Fixed | `vm.swappiness=100` with ZRAM (line 2653), status labels ≥100 as "Optimized for ZRAM & NVMe SSD". |
| **Battery install silently clamping to 80** | ✅ Fixed | `install_battery_service` now validates and `exit 1`s (line 773). |
| **`nullglob` clobbering** | ✅ Fixed | Saved/restored in `find_battery_threshold_nodes` (lines 599–603). |
| **Battery health math** (mAh labelled as Wh) | ✅ Fixed | Charge-based path converts via `voltage_min_design`/`voltage_now` and falls back to honest mAh display (lines 668–678). |
| **Menu robustness** (`clear`, TTY, confirmations, lock) | ✅ Fixed | All `clear` calls guarded; zero-arg non-TTY invocation does not launch the menu (line 7903); `flock` lock (line 131); full-suite, MAC, and crash-dump purges all gated behind prompts or `FORCE_YES`. Crash dumps are now **opt-in** with forensic evidence preserved by default (lines 1901–1913). |
| **v0.5.5 privacy-audit C1/C2/C4/H3–H6/H9 (DPI/byedpi, DNS shield)** | ✅ Resolved by removal | v0.5.7 excised the entire DPI bypass and DNS-shield netfilter subsystem (it conflicted with WARP/WireGuard/Tailscale). Only cleanup references to `laptop-dpi-mss.service`/`byedpi.service` remain in `clean_network_overrides` — correct. |
| **IPv6 hardening** | ✅ Fixed | `disable_ipv6` keeps `lo` enabled and skips lo in the per-interface loop (line 4029/4035); RFC 4941 privacy extensions (`use_tempaddr=2`, `addr_gen_mode=3`) applied live + per-interface (lines 4064–4070). |
| **APT safety** | ✅ Fixed | `--force-confold` on dist-upgrade and autoremove (lines 1931, 1970); GRUB/kernel/EFI packages excluded from `dpkg --purge` (v0.5.7 fix); purge runs through `xargs -r ... || true` with output logged. |

---

## 2. Remaining and residual issues

### Medium — correctness / honesty of status output

1. **`enable_bbr()` / `enable_swappiness()` still claim success on suppressed failures** (lines 2587–2608, 2642–2656). Every `sysctl -w` is `|| true`, then `log_success` fires unconditionally. `enable_zram()` now checks the unit start — extend the same pattern: if `sysctl -n net.ipv4.tcp_congestion_control` ≠ `bbr` after apply, warn instead of claiming success. Related: `apply_system_tuning()` ends with a blanket "All system performance and privacy tunings applied successfully!" regardless of any sub-failure.

2. **`revert_dns_changes()` deletes rather than restores** (lines 1194–1211). Pre-existing user NM/resolved drop-ins are `rm -f`'d, and `DNS_BACKUP` is created only once ever (line 943), so a second `dns apply` after a `revert` can restore a stale `.orig`. Snapshot whether the drop-ins existed before first apply and restore *that*.

3. **No negative DNS-leak test.** The one verification that matters is still missing: with the encrypted-DNS profile active, stop `dnscrypt-proxy`, query a cleartext resolver, and confirm failure. `getent ahostsv4 example.com` (line 1176) can succeed via `/etc/hosts` or a cached answer and does not prove the system resolver path.

4. **Tor readiness check is port-only** (lines 981–1003). Port 9050 listening ≠ bootstrapped circuits; the 10-second retry is a big improvement over the old unconditional claim, but a `getinfo status/circuit-established` control-port check would make "Tor is active" truthful.

5. **Battery sleep-hook background subshell** (line 827): `( sleep 1; apply_thresh; sleep 2; apply_thresh ) &` — systemd-sleep may finish and kill the hook's process group before the delayed writes run. Use a transient systemd unit (`systemd-run --on-active=`) or drop the delays; the immediate `apply_thresh` plus the udev Mains rule already cover most reset vectors.

6. **Weekly timer never updates user Flatpaks.** `update_flatpak()` gates the user-install update on `${SUDO_USER}` (line 1954); the timer runs as root with `SUDO_USER` unset, so user Flatpaks are silently never updated by the automation. Enumerate `/home/*` and run per-user updates with `XDG_RUNTIME_DIR`/`DBUS_SESSION_BUS_ADDRESS` set (reuse the pattern from `run_user_gsettings`).

7. **`DNSSEC=no`** remains in the resolved drop-in (line 1117). It's now at least *surfaced* in `show_dns_status` (line 1377–1378) with the rationale — acceptable trade-off, but consider `allow-downgrade` as an opt-in.

### Low / cosmetic

8. **Header/version mismatch**: header comment says `Version: 0.5.1` while `VERSION="0.5.15"` (lines 4 vs 33).
9. **No `ERR` trap / syslog logging** for a 9k-line root script — a `trap 'log_err "Failed at line $LINENO"' ERR` would make timer failures diagnosable from the journal.
10. **`laptop-optimizer.service` has no sandboxing** (`Nice=19` + idle I/O only). Hard apt operations limit this, but `ProtectHome=read-only` / `ProtectKernelTunables=yes` are feasible.
11. **Journal vacuum at 7d/100M** (lines 2099–2100) still trims potentially useful forensic logs weekly without a toggle.
12. **`battery set` udev rule redundancy**: the rule rewrites the literal `$val` on line one and `$env{THRESHOLD}` on line two — benign duplication, but the first line makes the conf import redundant.

---

## 3. Optimisation assessment — are the tunings sound?

| Tuning | Verdict |
|---|---|
| **ZRAM 50% zstd, priority 100 + swappiness 100** | ✅ Correct modern laptop setup. The old swappiness-10-with-ZRAM mistake is gone; priority 100 correctly outranks disk swap. |
| **TCP BBR + `fq` + fastopen=3** | ✅ Sound for interactive latency on lossy/variable Wi-Fi; harmless on healthy links. Baseline capture makes revert honest. |
| **ELAN/AMDI0010 runtime PM pinned `on` via udev + resume hook** | ✅ This is the *right* fix for idle-touch dropout (vs the older polling hacks). Power cost is negligible (µW-scale controller wakeup). |
| **`processor.max_cstate=2`** | ⚠️ Legitimate but the bluntest instrument — it costs real idle battery across *all* cores to fix an I2C wakeup path. Correctly gated behind an explicit toggle and a cap on kernel <7.3 via ACPI 100 kHz override first (v0.5.12), which is the better root-cause fix. |
| **PSR/Panel Replay disable (`amdgpu.dcdebugmask=0x410` / `i915.enable_psr=0`)** | ⚠️ Trade-off, not pure win: measurably increases panel power. Appropriately opt-in with per-GPU detection. |
| **ACPI DSDT I2C 100 kHz override (v0.5.12)** | ✅ Elegant, kernel-sanctioned (`CONFIG_ACPI_TABLE_UPGRADE`) fix targeting the actual firmware bug; checksum recompute + GRUB early-initrd wiring is the correct mechanism. Riskiest touchpad change in the file — worth keeping behind its explicit `touchpad speed` verb (it is). |
| **v0.5.14 quirk correction** | ✅ Removing the `BTN_TOOL_DOUBLETAP` masking was the right call — that "fix" broke libinput's two-finger state machine entirely; the auto-sanitize of outdated quirks files closes the regression loop. |
| **`click-method` default + DWT restored (v0.5.15)** | ✅ Restoring `disable-while-typing` and the physical buttonzone defaults undoes the over-aggressive v0.5.11 tuning — good example of the "fix snowballing" hazard the docs themselves describe. |
| **`vfs_cache_pressure=50`** | ⚠️ Mild; defensible on 16 GB, marginal on 8 GB — fine as-is. |
| **UFW deny-inbound/allow-outbound + LocalSend/CUPS holes** | ✅ Sensible laptop posture; scoped ports only. |
| **Wi-Fi-only MAC randomization default, Ethernet opt-in (`--ethernet`)** | ✅ Avoids the 802.1X/DHCP-reservation/WoL breakage the earlier audit flagged. |
| **Audio `power_save=0`** | ⚠️ Fixes DAC pop at a small idle-power cost; appropriately a named toggle, not bundled into "tune apply". |

**Overall optimisation verdict:** the current defaults are defensible and, importantly, every invasive knob (C-state cap, PSR, ACPI override, Ethernet MAC, daemon disabling) is opt-in or prompt-gated rather than bundled into `tune apply`. The one systematic weakness is that several `enable_*` functions report success without post-apply verification.

---

## 4. Recommended next steps (priority order)

1. Add post-apply verification to `enable_bbr`/`enable_swappiness` (read back the sysctl; warn on mismatch) and make `apply_system_tuning`'s final message reflect actual results.
2. Fix the battery sleep-hook race (transient timer unit instead of background subshell).
3. Per-user Flatpak updates from the weekly timer (enumerate `/home/*`).
4. Snapshot-and-restore semantics for DNS drop-ins; refresh `DNS_BACKUP` on each apply.
5. Add the negative DNS-leak test to the DNS status path.
6. Sync the header version string; add an `ERR` trap.

None of the remaining items are release-blocking; the critical exposure classes (root symlink traversal, user-owned timer payload, TOML misplacement, false success reporting on the primary privacy feature) are all closed in this version.
