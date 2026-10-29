# Audit: `mint-admin.sh`

Audit date: 2026-10-29
Scope: static review of `mint-admin.sh` (no source changes made)
Validation: `bash -n mint-admin.sh` passes. `shellcheck` was unavailable in this environment.
File ownership observed: `minty:minty`, mode `755` (relevant to the timer finding below).

## Observed system state

The machine already has parts of this script applied: `dnscrypt-proxy 2.0.45` with `listen_addresses = []`, an `[anonymized_dns]` route to `anon-cs-de`/`anon-ibksturm`/`anon-tiar-nl`, and query logging active in `/var/log/dnscrypt-proxy/query.log`. `resolvectl` shows a global `127.0.2.1` route with `Domains=~.`, plus link-level `9.9.9.9`/`149.112.112.112` for the `lan` domain. `dnscrypt-proxy.toml.orig` exists, so the DNS rollback path has a backup to restore.

### Verification notes

The main findings were reproduced where possible:

- A symlinked `~/.cache/thumbnails` caused `rm -rf "$dir"/*` to delete the target directory's contents as the current user.
- Redirecting into a symlinked recent-files path overwrote the symlink target.
- `dnscrypt-proxy -check` rejected the Tor config produced by the script with `FATAL Unsupported key in configuration file: [anonymized_dns.proxy]`. In this distro's config layout, the Tor profile fails rather than applying.
- `dig @127.0.2.1 nonsense.invalid` returned exit status `0`, confirming that `dig` success is not proof of resolution.
- `resolvectl status` still listed the Wi-Fi link DNS servers (`9.9.9.9`, `149.112.112.112`) for the `lan` domain alongside the global `127.0.2.1`. The script never verifies which path an actual system query takes.
- In testing, a `resolvectl query` did reach dnscrypt-proxy, so the global `~.` route works here; the finding is that the script does not verify this, not that routing is always broken.
- `/var/log/dnscrypt-proxy/query.log` is enabled and contains query records; the privacy module has no code to clear or rotate it, so a "privacy scrub" leaves DNS query history on disk.
- `avahi-daemon.socket` remained enabled and active while the script only disables `avahi-daemon.service`.
- A unit with an unquoted `ExecStart` path containing a space failed `systemd-analyze verify` (`Command /tmp/space is not executable`).
- `env -u TERM bash -c 'set -e; clear; echo survived'` exited `1`, confirming the interactive menu can abort without a usable `TERM`.
- `fs.suid_dumpable=2` is the Mint/Ubuntu default here (`/usr/lib/sysctl.d/50-coredump.conf`), so that specific value in `revert_system_tuning()` is not itself a regression on this system.

---

## Critical and high-impact findings

Severity is marked on each item. Items 1–3 are the ones I would treat as release-blocking.

### 1. Root symlink attack in `clean_privacy()` — arbitrary file overwrite/deletion
**Severity: Critical — Lines 854, 902, 914**

`clean_privacy()` runs as root and follows user-controlled symlinks:

```bash
if [ -f "$recent_file" ]; then
    echo '<?xml ...' > "$recent_file"      # line 854
    chown "$owner" "$recent_file"          # line 857
fi
...
rm -rf "$h/.cache/thumbnails"/*            # line 902
...
rm -rf "$h/.local/share/Trash"/files/* ... # line 914
```

A local user can create:

```bash
ln -s /etc/shadow ~/.local/share/recently-used.xbel
ln -s /etc ~/.cache/thumbnails
ln -s / ~/.local/share/Trash/files
```

When an administrator runs `sudo mint-admin.sh privacy` (or `full-suite`), the attacker does not need sudo — write access to their own home directory is enough. The script can then:

- truncate `/etc/shadow` and `chown` it to the attacker (lines 854/857) — root compromise or lockout;
- delete the contents of `/etc` (line 902);
- delete the contents of `/` (line 914).

Even if the `chown` fails, truncating `/etc/shadow` is a denial-of-service.

**Fix:** refuse symlinks before every destructive path, for example:

```bash
[ -L "$recent_file" ] && continue
[ -L "$h/.cache/thumbnails" ] && continue
[ -L "$h/.local/share/Trash" ] && continue
[ -L "$h/.local/share/Trash/files" ] && continue
```

For the recent-files rewrite, write to a temp file in the same directory and `mv -T` it over the target, using `chown --no-dereference`. Also skip symlinked home directories (`[ -L "$h" ] && continue`).

---

### 2. Weekly root timer executes a user-owned script from `/home`

**Severity: Critical — Lines 17, 1154–1165**

`SCRIPT_PATH="$(realpath "$0")"` resolves to a path such as:

```text
/home/minty/Documents/pyscripts/system-tools/mint-admin.sh
```

`install_weekly_timer()` writes:

```ini
ExecStart=/home/minty/Documents/pyscripts/system-tools/mint-admin.sh optimize
```

The service runs as **root**, but the file is owned by `minty`. Any process running as `minty` can replace the script and wait for the weekly timer, gaining root. The unquoted path also breaks if it contains spaces.

**Fix:** install a root-owned copy and point the timer at it:

```bash
install -D -m 0755 -o root -g root "$SCRIPT_PATH" /usr/local/sbin/mint-admin
# ExecStart=/usr/local/sbin/mint-admin optimize
```

If executing in place is required, reject a script path under `/home` unless it is root-owned and not group- or world-writable.

---

### 3. Tor DNS settings are appended into the wrong TOML table

**Severity: Critical — Lines 362–367**

```bash
echo "proxy = 'socks5://127.0.0.1:9050'" >> "$DNS_CONFIG"
echo "force_tcp = true" >> "$DNS_CONFIG"
```

`proxy` and `force_tcp` are top-level dnscrypt-proxy options. Appending them to the end of the file places them after the last `[section]`, so in TOML they become keys of that table (for example `[anonymized_dns].proxy`), not global settings.

On the installed `dnscrypt-proxy 2.0.45`, this fails the config check with:

```text
[FATAL] Unsupported key in configuration file: [anonymized_dns.proxy]
```

The script's `dnscrypt-proxy -check` then restores the backup and exits, so Tor mode does not work at all here. On a parser that ignores unknown keys, the keys would instead be silently ignored while the line-486 grep still reports "Tor Routing: ENABLED". Either outcome is wrong.

**Fix:** insert the keys before the first section header, or use a real TOML editor. At minimum:

```bash
sed -i "/^server_names =/a proxy = 'socks5://127.0.0.1:9050'\nforce_tcp = true" "$DNS_CONFIG"
```

Also make `show_dns_status` verify effective behavior instead of the presence of a line.

---

### 4. DNS "verified" test is a false positive and does not check system-wide routing

**Severity: High — Lines 404–448**

```bash
if dig @127.0.2.1 example.com +short &>/dev/null; then
    log_success "Internet & Encrypted DNS verified active via 127.0.2.1!"
```

Problems:

- `dig` exits `0` when it receives any response, including `SERVFAIL` or `NXDOMAIN`; it does not prove successful resolution.
- It tests `127.0.2.1` directly. It does not prove that the OS/system resolver is actually using that address.
- `setup_system_dns()` writes a NetworkManager `[global-dns-domain-*]` file that NM may ignore depending on its DNS backend.
- The systemd-resolved drop-in is written only if `systemd-resolved` is currently active.
- `DNSSEC=no` is set at line 419.
- `FallbackDNS=` is not cleared, so systemd-resolved can fall back to its compiled-in public resolvers on failure — a DNS leak.

**Fix:** verify all layers:

1. Confirm `resolvectl status` / `/etc/resolv.conf` shows the intended nameserver.
2. Query through the system resolver, not only `@127.0.2.1`.
3. Parse the answer and require a non-empty A/AAAA result, not just exit status.
4. Set `FallbackDNS=` / configure `DNS=` explicitly and test after a forced proxy stop to confirm no leak.

Also reconsider `DNSSEC=no`; it weakens integrity for a tool marketed as privacy/security hardening.

---

### 5. Battery udev rule can cause an event loop / excessive writes

**Severity: High — Line 295**

```udev
SUBSYSTEM=="power_supply", ACTION=="change", RUN+="/bin/sh -c '... echo \"$THRESHOLD\" > \"$bat\" ...'"
```

Writing `charge_control_end_threshold` commonly calls `power_supply_changed()`, which emits another `change` uevent. The rule then runs again. Even if the driver suppresses duplicate-value events, this fires on every battery capacity/AC change, not just AC plug events, causing repeated root shell invocations and udev log spam.

**Fix:** trigger only on the relevant condition (for example `ATTR{type}=="Mains", ATTR{online}=="1"`) and make the write idempotent. Prefer a small systemd unit triggered by udev (`TAG+="systemd"`, `ENV{SYSTEMD_WANTS}=...`) over a shell `RUN+=`.

---

### 6. MAC randomization can kill the current session and leave the machine offline

**Severity: High — Lines 745–756**

```bash
nmcli connection down "$active_conn" || true
sleep 1
nmcli connection up "$active_conn" || true
```

If connected via Wi-Fi, SSH, or a VPN over that interface, this intentionally drops the connection. If `nmcli connection up` fails, the script continues and the machine may remain offline. The script prints "Updated MAC" regardless of the actual result (line 776).

`generate_random_mac()` also uses `$RANDOM` (lines 643–646), which has limited/predictable entropy — weak for a privacy feature.

**Fix:**

- Detect `SSH_CONNECTION` and the interface carrying the default route; refuse or require `--force`.
- Check the return status of `nmcli connection up` and roll back/retry.
- Use `od -An -N5 -tx1 /dev/urandom` for MAC bytes.
- Print the actual new MAC, not "Updated" unconditionally.

---

### 7. `revert_system_tuning()` does not actually restore the prior state

**Severity: High — Lines 1386–1404**

```bash
sysctl -w fs.suid_dumpable=2
```

On this Mint install `fs.suid_dumpable=2` is the distro default (`/usr/lib/sysctl.d/50-coredump.conf`), so this particular line matches Mint. It is still not a safe generic revert: on a system whose prior/default value was `0`, setting `2` permits setuid processes to dump core. The function also leaves other state behind:

- `kernel.unprivileged_bpf_disabled=1` is not reset at runtime.
- `net.ipv4.tcp_fastopen=3` is not reset.
- `ModemManager` is never re-enabled (lines 1397–1400).
- `/etc/default/zramswap` is not removed, so old ZRAM settings return if the service is re-enabled.
- The original values are never captured, so "revert" is a hardcoded guess rather than a restore.

**Fix:** capture the previous sysctl values and service states before applying, restore those, and explicitly re-enable `ModemManager`.

---

### 8. Tuning disables services without consent, and `avahi` is not fully disabled

**Severity: High — Lines 1357–1359**

```bash
systemctl disable --now avahi-daemon
systemctl disable --now cups-browsed
systemctl disable --now ModemManager
```

This breaks:

- `.local` mDNS resolution, network printer/scanner discovery, AirPlay/Chromecast discovery (`avahi`);
- network printer auto-discovery (`cups-browsed`);
- mobile broadband/WWAN (`ModemManager`).

There is no prompt or warning. Additionally, `avahi-daemon.socket` is often still enabled; socket activation can start `avahi-daemon` again on demand, so the "broadcast stopped" claim is not reliable.

**Fix:** require confirmation, disable `avahi-daemon.socket` too, and re-enable all three in `revert_system_tuning()`.

---

### 9. `vm.swappiness=10` combined with ZRAM is counterproductive

**Severity: High — Lines 1324, 1361–1375**

ZRAM is swap. A very low swappiness discourages the kernel from using it, which can increase memory pressure and OOM risk, especially on low-RAM machines. Recommended values with ZRAM are usually much higher (often 100–150), not 10.

**Fix:** either do not install ZRAM, or use a ZRAM-appropriate swappiness. Do not advertise "swappiness 10" as an optimization on a ZRAM system.

---

### 10. Success is logged even when critical setup failed

**Severity: High — Lines 1338–1339, 1374–1375; also 440–448 and 951–957**

```bash
sysctl --system ... || true
log_success "Kernel performance & privacy sysctls active."
...
systemctl enable --now zramswap.service
log_success "ZRAM active..."
```

If BBR is unavailable, a sysctl is rejected, or `zramswap.service` does not exist, the script still claims success. The same pattern appears in DNS verification and Flatpak updates.

**Fix:** check each critical result and either fail or log a clear warning. Reserve `|| true` for genuinely optional operations.

---

## High / correctness issues

### DNS

- **`listen_addresses = []` relies on distro socket activation** (line 359). On this system `/usr/lib/systemd/system/dnscrypt-proxy.socket` listens on `127.0.2.1:53`, so it works here, but the script assumes that unit exists and listens on that address. On a package or install where it does not, DNS is broken while the script reports success.
- **`systemctl enable dnscrypt-proxy.socket dnscrypt-proxy.service`** (line 429) fails hard under `set -e` if either unit does not exist. Restarting both socket and service can also race; restart the service and only touch the socket if present.
- **"ODoH" is mislabeled** (lines 374, 391, 619–622). This block configures `[anonymized_dns]`, which is Anonymized DNS relay routing, not Oblivious DoH. dnscrypt-proxy does support ODoH, but it requires the `odoh-servers`/`odoh-relays` sources and `odoh_servers = true`; the script neither sets those nor uses ODoH-capable stamps. The hardcoded relays are also unverified and may be renamed or removed.
- **`check_tor_service()` does not verify Tor is active or bootstrapped** (lines 343–350). It installs/starts Tor and immediately logs "Tor is active"; Tor circuits can take much longer than the 3-second DNS test.
- **DNS backup is created only once** (`check_dns_dependencies`). After `dns revert`, the backup remains; a later `dns apply` will not refresh it, so it may restore a stale or modified config. If the config did not exist at first run, the backup is missing and the failure path at line 398 can `cp` a nonexistent file.
- **`server_names` replacement only matches an exact `^server_names =` line** (line 360). A commented or multiline value silently leaves the old profile in place. `dnscrypt-proxy -check` validates syntax, not that server/relay names exist or are reachable.
- **`setup_system_dns()` does not verify the NM drop-in is honored.** `[global-dns-domain-*]` can be ignored depending on the NM DNS backend. There is no check that `/etc/resolv.conf` or `resolvectl` actually points at the proxy.
- **`show_dns_status()` greps anywhere in the file** (lines 486, 491), so it can report Tor/ODoH enabled even when the keys are in the wrong TOML table.
- **`apply_dns_profile()` logs success unconditionally** after `setup_system_dns && restart_dns_services` (for example lines 519–520). If `setup_system_dns` fails, the failure is on the left side of `&&` and `set -e` does not exit; the success line still runs.
- **`revert_dns_changes()` does not restore pre-existing NM/resolved drop-ins**; it deletes them. It also leaves relay config behind if no backup exists.

### Package / Flatpak maintenance

- **`clean_apt()` runs `autoremove --purge -y` with output suppressed** (line 967). On a weekly timer, this can remove packages the user still expects, and the user never sees the removal list. `dpkg --purge $rc_pkgs` (line 979) has no error handling; a failure aborts the script mid-clean under `set -e`.
- **`update_apt()` uses `DEBIAN_FRONTEND=noninteractive` but not `-o Dpkg::Options::=--force-confold`.** A conffile prompt can still block or fail, especially from the timer.
- **User Flatpak updates are unreliable.** `sudo -u "$SUDO_USER" flatpak update` (line 955) often lacks `HOME`, `XDG_RUNTIME_DIR`, and the D-Bus session; failures are suppressed with `2>/dev/null || true`. The weekly timer runs as root with `SUDO_USER` unset, so user Flatpaks are never updated at all.
- **`flatpak repair` is system-only** (line 999); user installations are not repaired.

### Privacy scrubbing

- **Trash emptying is irreversible and runs for every user with no confirmation.** Combined with the symlink issue above, this is dangerous.
- **Browser caches are deleted while browsers may be running.** This is usually tolerated but can cause browser errors; warn or check for running processes.
- **Flatpak cache deletion** (`find ~/.var/app ... -name cache`) can remove app state that is not purely cache.
- **The DNS flush does not clear dnscrypt-proxy's own cache or query logs.** If query logging is enabled, "privacy scrub" leaves DNS query records behind.
- **`/var/tmp` pruning at 7 days** conflicts with the FHS expectation that `/var/tmp` persists reboots; systemd-tmpfiles normally uses a longer interval.

### Battery

- **Health is wrong for charge-based batteries.** `charge_full` is in µAh, but lines 166–168 divide by 1,000,000 and label the result "Wh". That is off by the battery voltage. Use `energy_full` when available, or compute Wh from charge × voltage; otherwise display mAh/Ah.
- **`install_battery_service()` silently clamps an invalid threshold to 80.** `battery install 5` succeeds with 80 instead of reporting an error.
- **Persistence claims are unconditional.** The function logs "across reboots, sleep/wake, and AC plug events" even if `/lib/systemd/system-sleep` or the udev directory is missing.
- **The sleep hook launches a background subshell after `sleep 2`.** systemd-sleep may finish and kill the hook's process group before the write happens.
- **`find_battery_threshold_nodes()` clobbers the caller's `nullglob` setting** (sets and unsets it globally).

### IPv6 / tuning status

- **`disable_ipv6()` disables IPv6 on `lo`** (line 1452). This is unnecessary for leak prevention and can break services that bind `::1`.
- **IPv6 sysctl failures are suppressed and then success is logged** (lines 1454–1461). On an IPv6-only network, disabling IPv6 can break connectivity entirely; there is no warning.
- **`show_tuning_status()` does arithmetic on "Unknown"** (line 1244). If `/proc/sys/vm/swappiness` is unreadable, `[ "Unknown" -le 15 ]` prints an error.
- **`show_tuning_status()` uses file presence as proof for DHCP privacy** (line 1261), not whether NetworkManager actually applied it.
- **`revert_system_tuning()` does not re-enable `ModemManager`** and does not reset `kernel.unprivileged_bpf_disabled` or `tcp_fastopen` at runtime.

### Timer / menu

- **`install_weekly_timer()` does not restart an already-active timer.** `systemctl enable --now` will not reload a changed `OnCalendar`; use `systemctl restart mint-optimizer.timer` after `daemon-reload`.
- **`show_interactive_menu()` calls bare `clear`** (line 1486). If `TERM` is unset or `clear` is missing, `set -e` kills the script. Use `clear 2>/dev/null || true`.
- **Zero-argument invocation always launches the interactive menu**, even when stdin is not a TTY (pipeline/cron). Check `[ -t 0 ]`.
- **Destructive menu options have no confirmation**: privacy scrub, MAC randomization, tuning apply, and the full suite all execute immediately.
- **Any unhandled command failure aborts the menu** because of global `set -e`; the user cannot return to the menu after an apt/network error.
- **`show_timer_status()`** uses `journalctl ... || echo "No previous runs"`, but `journalctl` succeeds with "-- No entries --", so that fallback rarely appears.

---

## Lower-priority / cleanup

- **`print_summary()` only measures `/`** (line 84). If `/home` or `/var` is a separate filesystem, reclaimed space is misreported. `df -k / | awk 'NR==2 {print $4}'` is also brittle if `df` emits a warning line.
- **`format_kb()` and `print_summary()` do not guard against empty `df` output**; arithmetic errors can abort under `set -e`.
- **`clean_apt()`'s `dpkg --purge $rc_pkgs` is unquoted** (intentional word splitting, but relies on package names being safe; add error handling).
- **`clean_systemd()` vacuums journals to 7 days/100 MB** (lines 1017–1019), destroying potentially useful audit logs. If a command fails, `failed_units` is empty and the script says "0 failed".
- **MAC interface filter** (lines 671/723) misses `br-*`, `bond*`, `team*`, `dummy*`, `lxcbr*`, `incusbr*`, `podman*`, `ppp*`, `can*`. Randomizing a bridge/bond MAC can break containers or networking.
- **Persistent Ethernet randomization** (`ethernet.cloned-mac-address=random`, line 797) can break MAC-bound DHCP, 802.1X, captive portals, and Wake-on-LAN. Warn the user.
- **`randomize_mac()` can report "Updated MAC" even when the driver rejected the change.**
- **`ip`/`link` parsing is locale- and format-sensitive**, though less likely on Mint.
- **No `ERR` trap / no logging to syslog.** For a 1,900-line root script, a trap that logs the failing line would make failures diagnosable.
- **No lock file.** A manual run and the weekly timer can overlap; APT has locks, but privacy scrubbing/MAC changes do not.
- **`install_weekly_timer()` has no service hardening** (`ProtectSystem`, `PrivateTmp`, etc.). Hardening is harder because of apt, but the unit is currently fully privileged.
- **`install_weekly_timer()`'s `Documentation=file://$SCRIPT_PATH`** also breaks on paths with spaces.
- **`show_dns_status()` treats an active socket as an active resolver**, even if the service is dead.
- **`revert_system_tuning()` hardcodes `fs.suid_dumpable=2`** instead of restoring the prior value. It matches Mint's default here, but is wrong on systems with a stricter prior value.

---

## Recommended fix order

1. **Symlink hardening + root-owned timer copy** — direct root-compromise paths.
2. **DNS Tor TOML placement + real system-wide DNS verification + `FallbackDNS=`** — current code can silently leak DNS while reporting success.
3. **MAC/udev safety** — avoid killing remote sessions and avoid battery udev loops.
4. **Tuning revert correctness** — `fs.suid_dumpable`, `ModemManager`, BPF/fastopen, ZRAM config.
5. **Stop swallowing failures** — sysctl, `zramswap`, Flatpak user updates, DNS setup.
6. **Confirmations / `--dry-run`** for privacy scrub, MAC randomization, tuning apply, and full suite.
