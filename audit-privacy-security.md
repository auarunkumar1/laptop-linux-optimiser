# Audit: `laptop-linux-optimiser.sh` — Privacy & Security Hardening
### Focus: Encrypted DNS / DNS leak shield, DPI bypass, privacy scrubbing

Audit date: 2026-11-15
Scope: static review of `laptop-linux-optimiser.sh` v0.5.5 (6,638 lines) **plus reproduction of every finding**
below on this host (`iptables` 1.8.10 nf_tables backend, `dnscrypt-proxy` 2.0.45, `ufw` 0.36.2, `systemd-resolved` active).
`bash -n` passes; all 256 assertions in `tests/test_laptop_linux_optimiser.sh` pass. **The test suite only greps for
strings — none of the findings below are detectable by it.** `shellcheck` is not installed here.

Severity legend: **C** = critical (root compromise / traffic interception / silent privacy failure),
**H** = high, **M** = medium. Every claim marked *(reproduced)* was executed, not inferred.

---

## Summary of the real posture problems

The three headline features — "DNS Leak Shield", "DPI Bypass", "Privacy Scrub" — each **report success in
states where they are not doing the thing they claim**. That is the core risk here: not that the primitives
are missing, but that the dashboard and `log_success` lines assert protection the code does not provide.
A user who trusts this tool's own status output will believe their DNS is encrypted, their traffic is
un-fingerprintable, and their activity history is gone. In the tested configuration, all three assertions
were false or unverified at least once.

### What is already correct (do not regress)

Credit where due — several prior-audit findings are genuinely fixed:

- `generate_random_mac()` uses `od -An -N5 -tx1 /dev/urandom` and the `02:` locally-administered, unicast prefix.
- `install_weekly_timer()` installs a root-owned copy to `/usr/local/sbin` when the script lives under `/home`.
- Tor profile now inserts `proxy` / `force_tcp` **after `server_names`** (top-level TOML, before any `[section]`).
  Verified: `dnscrypt-proxy -config /tmp/tor.toml -check` → "Configuration successfully checked" *(reproduced)*.
- `save_tuning_baseline()` captures prior sysctl/service state instead of hardcoding a revert guess.
- `avahi-daemon.socket` is handled alongside `avahi-daemon.service`; `/etc/hosts` no longer rewrites through a
  symlinked path; recently-used.xbel is replaced via temp file + `mv -T` with `chown --no-dereference`.
- The per-path `is_safe_user_path` child guards do resolve `realpath`, and therefore **do** block the classic
  `~/.cache/thumbnails -> /etc` attack *(reproduced: child guard FAILS on a symlink pointing outside home)*.

---

## C1 — DPI REDIRECT rule is inserted *ahead* of its own exclusion list

**Severity: Critical — `byedpi_rules_add()`, lines 3811–3849**

The function inserts a `RETURN` exemption for `_dnscrypt-proxy`, `dnscrypt-proxy` and `debian-tor` first,
then inserts the `REDIRECT` rule — both at **position 1**. The last insert wins position 1, so the rule order
on the wire is the inverse of the intent:

```
-A OUTPUT ! -d 127.0.0.0/8 -p tcp -m multiport --dports 80,443 ... -j REDIRECT --to-ports 1080   <-- runs FIRST
-A OUTPUT -p tcp -m multiport --dports 80,443 -m owner --uid-owner _dnscrypt-proxy ... -j RETURN  <-- never reached
```

*(reproduced)* — inserting exactly as the script does yields REDIRECT at position 1 and the RETURN exemptions dead.

Consequences:

1. `dnscrypt-proxy`'s own DoH traffic (TCP 443 to Cloudflare/Quad9/AdGuard) is redirected into ciadpi. The
   exemption written to protect encrypted DNS does nothing.
2. `debian-tor`'s directory/guard connections are redirected too — so the "DNS over 3-hop Tor" profiles are
   fragmented by a desync engine while also being SOCKS-proxied.
3. ciadpi's own upstream connections are only protected by the `! --uid-owner byedpi` clause — and the third
   fallback branch (line 3834) silently drops `$uid_match` entirely when the owner match fails, leaving a
   redirect with **no self-exclusion**, i.e. a packet loop.

The live journal corroborates the interaction: `ciadpi[...]: split cancel: pos=1--1, n=261` repeatedly during
the same window dnscrypt-proxy is serving DoH.

**Fix:** append the REDIRECT (`-A`) and insert the exemptions at position 1, or insert REDIRECT first and then
the RETURNs. Then assert ordering, not mere presence:

```bash
# after building rules
first=$(iptables -w 5 -t nat -S OUTPUT | grep laptop-optimizer-dpi | head -n1)
[[ "$first" == *REDIRECT* ]] || { log_err "REDIRECT is shadowed by an exemption rule"; return 1; }
```

Do not keep the no-`uid_match` fallback: failing closed (no redirect) beats an unexcluded loop.

---

## C2 — ciadpi binds `::` (all interfaces) whenever IPv6 is enabled

**Severity: Critical — `install_byedpi()`, lines 3758–3762**

```bash
local bind_ip="127.0.0.1"
if ... [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)" -eq 0 ]; then
    bind_ip="::"
fi
```

`::` is the IPv6 wildcard, not loopback (`::1`). The listener therefore covers every interface.

*(reproduced)* — `ciadpi -i :: -p 18080 -E` → `LISTEN 0 10 *:18080 *:*`, and the same via the host's LAN
address `192.168.31.84:18082`. On this host the bug is masked only because IPv6 is currently disabled
(`disable_ipv6=1`), so the service happens to be on `127.0.0.1:1080`.

This tool **ships an IPv6 toggle** (`disable_ipv6` / `enable_ipv6` / `toggle_ipv6`, and the guided wizard).
Any user who re-enables IPv6 — a normal thing to do — gets an unauthenticated listener on the LAN from a
transparent-proxy daemon running as a system user, with no `IPAddressAllow` and no firewall rule scoping it.
The service unit does not restrict it either (no `RestrictAddressFamilies`).

**Fix:** the bind address must never depend on IPv6 sysctl state:

```bash
local bind_ip="127.0.0.1"
# dual-stack loopback only, never the wildcard
[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 1)" -eq 0 ] && bind_ip="::1"
```

and add `RestrictAddressFamilies=AF_INET AF_INET6` plus, in the unit, `IPAddressAllow=localhost IPAddressDeny=any`
(systemd 249+) so a future flag regression cannot expose it.

---

## C3 — Root writes into user-controlled directories with no symlink check

**Severity: High — `enable_font_antiblur()` lines 2549–2593, `verify_theme_preservation()` lines 1754–1765**

Two root code paths create and write files under `$uhome/.config/...` and `$uhome/.local/share/...` **without
any `-L` check or `realpath` containment**:

```bash
local fc_dir="$uhome/.config/fontconfig"
mkdir -p "$fc_dir"
cat << 'EOF_FC' > "$fc_dir/fonts.conf"     # follows symlinks
...
chown -R "$owner_uid:$owner_gid" "$fc_dir"
```

*(reproduced)* — with `~/.config/fontconfig` as a symlink to `/tmp/fp/etc`:

- `mkdir -p` happily creates directories **outside** the home directory
  (`/tmp/symtest2/etc/fontconfig` appeared after `mkdir -p symtest2/home/fontconfig`);
- `cat > .../fonts.conf` writes the file at the symlink target
  (`/tmp/fp/etc/fonts.conf` was created, outside the user's home).

`verify_theme_preservation()` is the worse of the two, because it runs over **every** `/home/*` and both
writes and chowns:

```bash
local fp_ov="$h/.local/share/flatpak/overrides/global"
if [ -f "$fp_ov" ] && [ ! -s "$fp_ov" ]; then
    cat << 'EOF_OV' > "$fp_ov"     # follows symlink
    ...
    chown "$owner" "$fp_ov"        # follows symlink, no --no-dereference
```

*(reproduced)* — a symlink at `overrides/global` → some empty file: the target's contents were replaced with
`[Context] ...` and the target was then chowned to the home owner. The `[ ! -s ]` gate limits the target to a
currently-empty file, which is why this is High rather than Critical for a pure unprivileged attacker; but the
primitive is arbitrary root file overwrite + arbitrary chown, reachable from `clean_privacy`,
`clean_user_cache`, `run_optimizer`, `full-suite`, `tune apply`, the guided wizard, and the presets.

Note the asymmetry that creates the risk: the *other* destructive paths in `clean_privacy()` are carefully
guarded with `is_safe_user_path` + `realpath`, so the reader assumes the file is hardened. These two paths were
missed.

**Fix:** reuse the guard that already exists, and never chown through a link:

```bash
[ -L "$uhome/.config/fontconfig" ] && { log_warn "Refusing symlinked fontconfig dir"; return 1; }
is_safe_user_path "$uhome" "$uhome/.config/fontconfig" || return 1
...
[ -L "$fp_ov" ] && continue
is_safe_user_path "$h" "$fp_ov" || continue
chown --no-dereference "$owner" "$fp_ov" 2>/dev/null || true
```

---

## C4 — The DNS "killswitch" is permanently open to four hardcoded resolvers, and lives only in the filter table

**Severity: Critical — `enable_dns_shield()` lines 949–1029**

### C4a — owner-agnostic cleartext hole

```bash
for ip in 9.9.9.9 149.112.112.112 1.1.1.1 1.0.0.1; do
    iptables -w 5 -I OUTPUT 1 -p udp -d "$ip" --dport 53 ... -j ACCEPT
```

These `ACCEPT`s are inserted at position 1, above the DROP, and carry **no `-m owner` match** — unlike the
correctly owner-scoped `_dnscrypt-proxy` ACCEPT above them. Result: *any* process on the box can send
cleartext UDP/TCP port-53 queries to Cloudflare and Quad9, which is exactly the traffic the shield exists to
prevent. The intent was "let the bootstrap resolver work"; the effect is a four-address bypass that also works
for userland apps and for anything that falls back to `1.1.1.1`. IPv6 has the same pair (`2620:fe::fe`,
`2606:4700:4700::1111`).

### C4b — the shield does not survive a firewall reload, but the DPI redirect does

The shield is `filter`-table OUTPUT rules only. Anything that rebuilds that table removes it silently:
`ufw` with `MANAGE_BUILTINS=yes` (`/lib/ufw/ufw-init-functions`, `flush_builtins()`), `nft flush ruleset`,
a `docker`/`podman` restart, `nftables.service`.

*(reproduced)* — `iptables -F` removed both shield rules (`2 → 0`) while the `nat` REDIRECT survived intact.
So the failure mode after a firewall reload is the worst combination: **cleartext DNS is allowed again, and
HTTPS is still being transparently redirected into ciadpi.**

`status_get_dns_shield()` for non-root callers then reports `ACTIVE` from the `${STATE_DIR}/dns-shield-active`
marker file alone, so the dashboard shows "ENABLED (Port 53 Killswitch Active)" while nothing is enforced.

Additional robustness gaps in the same function:

- Lines 973/975/988/990 have **no** `2>/dev/null || true`, unlike their neighbours. Under `set -euo pipefail`,
  an `ip6tables` failure aborts the function *after* some ACCEPTs are installed and *before* the DROP rules and
  the state file — leaving a partially applied, non-protecting state with a non-zero exit that the menu only
  prints as "exit code 1".
- `disable_dns_shield()` treats any single delete failure as terminal (`|| break`), so it can leave remnants.

**Fix (minimum):** scope the bootstrap ACCEPTs to the dnscrypt UID, and make the state truthful:

```bash
for ip in 9.9.9.9 149.112.112.112 1.1.1.1 1.0.0.1; do
  iptables -w 5 -I OUTPUT 1 -p udp -d "$ip" --dport 53 -m owner --uid-owner "$dns_uid" ... -j ACCEPT || true
done
```

then have `status_get_dns_shield()` re-verify the live ruleset (and fall back to the marker only for
non-root), and add a `nft`-side equivalent (or an `ufw/after.init` hook) so a reload cannot silently drop it.

---

## H1 — The privacy scrub is currently a silent no-op, and it says the opposite

**Severity: High — `is_safe_user_path` line 155–184, called as `is_safe_user_path "$h" "$h"` at lines 1532, 1565, 1597, 1612, 1812**

`is_safe_user_path` compares `real_target` against `"$real_h"/*`. When the target **is** the home directory,
`real_target == real_h`, which never matches the `/*` pattern — so the function returns 1:

```
h=/home/plasma  real_h=/home/plasma  real_target=/home/plasma
'/home/plasma' == real_h + '/*' ? -> NO
SELF GUARD: FAIL -> '|| continue' skips the whole user
CHILD GUARD: PASS
```

*(reproduced in a user namespace with a real `/home/alice`)* — after running the verbatim loops:

```
BEFORE: thumbs=1 trash=1
AFTER : thumbs=1 trash=1
```

Nothing was scrubbed, and the thumbnail purge line was never even printed. Because every user loop in
`clean_privacy()` and `clean_user_cache()` starts with `is_safe_user_path "$h" "$h" || continue`, **steps 2–5 of
the privacy module (recent files, Zeitgeist/Vivaldi, all browser caches, Flatpak caches, thumbnails, Trash) do
nothing on any system**, while the function still prints:

```
[+] Activity history cleared.
[+] Web browser caches cleaned.
[+] Thumbnail caches purged.
[+] Trash bins emptied.
```

This is the highest-value bug in the file from a user-trust standpoint: a "privacy scrub" that scrubs nothing
but reports success. It is also a latent critical: the moment someone "fixes" this by removing the `|| continue`
without keeping the child guards, the classic `~/.cache/thumbnails -> /etc` attack in the older audit comes
back for the *recent-files* write path too.

**Fix:** allow the home directory itself, keep the strict child semantics:

```bash
is_safe_home() {                       # $1 = candidate home
  local h; [ -d "$1" ] && [ ! -L "$1" ] || return 1
  h=$(realpath -q "$1") || return 1
  [[ "$h" == /home/* || "$h" == /root ]]
}
# call site
is_safe_home "$h" || continue
```

and make the per-step echoes conditional on the step actually having matched something.

---

## H2 — "ZERO-LOG (Forensic Privacy Preserved)" is a false positive

**Severity: High — `show_dns_status()` lines 1110–1114, `apply_dnscrypt_config()` lines 752–754**

The status check is:

```bash
if grep -qE "^[[:space:]]*file = ''" "$DNS_CONFIG" || ! grep -q "query\.log" "$DNS_CONFIG"; then
    echo "ZERO-LOG (Forensic Privacy Preserved)"
```

The package default config contains **both** `[query_log]` and `[nx_log]`, each with `file = ''`. So the first
`grep` matches the `[nx_log]` line and the branch reports zero-log **regardless of the `[query_log]` setting**.

*(reproduced)* with a config whose `[query_log] file = 'query.log'` is live:

```
REPORTED: ZERO-LOG (Forensic Privacy Preserved)
TRUTH: query.log IS enabled
```

The scrub regex does not rescue this either — it requires a `/` in the path:

```bash
sed -i "s|^[[:space:]]*file = .*/query\.log.*|file = ''|"
```

*(reproduced)*: an absolute `file = '/var/log/dnscrypt-proxy/query.log'` is rewritten to `file = ''`, but a
relative `file = 'query.log'` (which the shipped example documents as valid — "absolute, or relative to the
same directory as the config file") is **left enabled**.

**Fix:** parse the `[query_log]` table only, and verify by asking the daemon rather than grepping:

```bash
awk '/^\[query_log\]/{f=1;next} /^\[/{f=0} f && /^[[:space:]]*file[[:space:]]*=/{print; exit}' "$DNS_CONFIG"
# and treat a relative "query.log" as LOGGING ACTIVE, not as zero-log
```

---

## H3 — Tier 1 (MSS clamp) never persists, and the dashboard reports it as ACTIVE

**Severity: High — `enable_dpi_mss()` lines 3541–3567, `status_get_dpi()` lines 3512–3539**

`enable_dpi_mss` writes `/var/lib/.../dpi-mode` and installs `mangle` INPUT rules. There is **no systemd unit**
that re-applies those rules (compare `laptop-dns-shield.service`), so they vanish on reboot and on any
`iptables -F`. The non-root branch of `status_get_dpi` then answers from the state file alone:

```bash
if [ "$mode" = "mss" ]; then echo "ACTIVE: TIER 1 (Kernel TCP MSS: ${mval})"; return; fi
```

So `dpi status` / the TUI pill shows "ACTIVE: TIER 1" on a machine with zero firewall rules. The root branch
is correct, so the same command prints two different truths depending on whether it ran under `sudo`.

`show_dpi_status()` compounds it: its rule counters call `iptables` without root and report `0` while the
daemon is active, so "NAT redirect rules active : 0" appears next to "ACTIVE: TIER 2".

**Fix:** mirror the DNS shield pattern — a `oneshot` unit with `ExecStart=... dpi mss enable <n>` /
`ExecStop=... dpi mss disable` — and make the non-root status resolver-aware rather than state-file-aware
(at minimum print `UNKNOWN (run as root)` instead of `ACTIVE`).

---

## H4 — Byedpi can be installed from an unpinned `git clone` built as root

**Severity: High — `install_byedpi()` lines 3729–3745**

The prebuilt path is good: pinned URL **and** a hardcoded SHA-256 that is verified before extraction.
The fallback is not:

```bash
git clone --depth=1 --branch v0.17.3 https://github.com/hufrea/byedpi "$src_dir" || \
git clone --depth=1 https://github.com/hufrea/byedpi "$src_dir"
make -C "$src_dir"
install -m 755 "$src_dir/ciadpi" "$BYEDPI_BIN"
```

No commit SHA pin, no tag signature verification, and the `||` fallback silently clones the **default branch
HEAD** if the tag disappears or is unreachable — then compiles it and installs it as root into
`/usr/local/bin`. On any architecture without a published binary (`uname -m` anything else), this is the only
path taken. Add to that: `curl -sSLf` without `--proto '=https' --tlsv1.2` will follow a redirect to plaintext.

**Fix:** pin `CIADPI_COMMIT=<sha>`, `git fetch --depth=1 origin "$CIADPI_COMMIT" && git checkout "$CIADPI_COMMIT"`,
drop the default-branch fallback (fail closed and print the manual build command), and add
`--proto '=https' --tlsv1.2 --proto-redir '=https'` to the curl.

---

## H5 — Byedpi service is unsandboxed and `:1080` ownership is never verified

**Severity: High — `install_byedpi()` lines 3771–3794, port defined line 97**

`User=byedpi` + `NoNewPrivileges=yes` is a start, but the unit has none of
`ProtectSystem=strict`, `PrivateTmp`, `ProtectHome`, `ProtectKernelTunables`, `RestrictAddressFamilies`,
`CapabilityBoundingSet=`, `MemoryDenyWriteExecute=`. It is a network-facing daemon owned by a system user with
the full filesystem visible.

Separately, `BYEDPI_PORT=1080` is a **well-known SOCKS port above 1024**. `byedpi_rules_add()` REDIRECTs all
80/443 to it without checking that the listener is actually ciadpi. Between a ciadpi crash and
`RestartSec=3`, or whenever a user runs a VPN/SOCKS client on 1080, redirected traffic is delivered to a
*different* process — including plaintext HTTP for port 80. Any local user can win that race.

**Fix:** pick a high fixed port unlikely to collide (e.g. 47891), verify ownership before/after installing
rules (`ss -ltnp 'sport = :47891' | grep -q ciadpi`), and add the sandboxing keys to the generated unit.

---

## H6 — The "evasion diagnostic" asserts protection it has not measured

**Severity: High (misleading security claim) — `test_dpi_evasion()` lines 3921–3985**

- Any HTTP status other than `000` is printed as `SUCCESS ... Clean TLS Handshake Established`. A **403 from an
  ISP blocking page** or a captive portal satisfies that test and is reported as successful evasion.
- The function prints `Wire-Level Protection: Byedpi/MSS splits TLS packets on wire so ISP cannot read SNI`
  unconditionally. Nothing in the code observes the wire; SNI leakage is never tested.
- The ECH claim is read from `crypto.cloudflare.com/cdn-cgi/trace` and, per the script's own note, is normally
  `plaintext` for curl — so the tool prints a warning about its own headline feature succeeding or failing to
  succeed, then asserts it works anyway.

The DPI feature may well work. The point is that the *verification* is theater, and this is the output a user
will screenshot as proof. Compare against a real check: `openssl s_client -connect host:443 -servername host`
while capturing with `tcpdump -c` on the interface, or at least require `http_code == 200` and record the
observed `sni=` value as the result rather than overriding it.

---

## H7 — System-wide DNS is "verified" by something that cannot fail

**Severity: High — `restart_dns_services()` lines 882–905, `setup_system_dns()` lines 835–847**

```bash
sys_ip=$(getent ahostsv4 example.com ...)
if [ -n "$sys_ip" ]; then log_success "System-wide DNS resolution verified active!"; fi
```

`getent` succeeds if the name resolves **by any means** — `/etc/hosts`, a stale cache, the link-local router, or
the ISP resolver. It does not prove the query went to `127.0.2.1`. If the NetworkManager drop-in is ignored
(different DNS backend) or `systemd-resolved` was not active when the drop-in was written (it is written only
`if systemctl is-active systemd-resolved`), the tool still reports success.

Also in this path:

- `DNSSEC=no` is written into the resolved drop-in. For a tool sold as privacy/security hardening, disabling
  validation to make the proxy work is a downgrade that should at minimum be surfaced in the status output.
- `restart_dns_services()` guards the socket with `if systemctl list-unit-files dnscrypt-proxy.socket &>/dev/null`
  — *(reproduced)* that returns 0 for a **nonexistent** unit, so the guard is always true and meaningless.
- There is no negative test. The one test that matters for a killswitch is: stop dnscrypt, query a cleartext
  resolver, and confirm it is **dropped**. Nothing does this.

**Fix:** resolve through the system stub *and* prove the path: check `resolvectl dns` shows only `127.0.2.1`,
`resolvectl domain` shows `~.`, then stop `dnscrypt-proxy` and assert `dig @9.9.9.9 example.com` fails while the
shield is enabled.

Note the resolver config is otherwise in good shape on this host: `Global: 127.0.2.1`, `Domain: ~.`,
link scope `-DefaultRoute`, `FallbackDNS=` cleared — so the *implementation* works; only the verification lies.

---

## H8 — IPv6 privacy extensions are never enabled

**Severity: High (privacy) — no `use_tempaddr` / `addr_gen_mode` anywhere in the file**

`grep -c use_tempaddr` → 0. The tool offers `enable_ipv6()`, `disable_ipv6()`, and the guided wizard includes
IPv6. When IPv6 is enabled, nothing sets `net.ipv6.conf.*.use_tempaddr=2` (RFC 4941) or
`addr_gen_mode=3`, so a laptop using IPv6 presents a stable interface identifier derivable from the MAC — a
persistent trackable identifier across networks, which is precisely what the MAC-randomization module is trying
to prevent. MAC randomization and stable IPv6 addresses in the same toolkit is an internal contradiction.

**Fix:** add `use_tempaddr=2` (and, with your judgement, `addr_gen_mode=3`) to the privacy sysctl file, and
report it in `show_ipv6_status()`.

---

## H9 — Enabling the DPI bypass silently disables a NetworkManager privacy control

**Severity: Medium — `byedpi_rules_add()` line 3816**

```bash
# Disable NM captive portal check to prevent flatpak offline deadlock
disable_nm_connectivity_check 2>/dev/null || true
```

This runs as an undocumented side effect of `dpi byedpi enable` (and of every `ExecStartPost`). It *is* privacy
positive (NM's connectivity probe phones home), but it is attributed to the wrong feature, is not reversible
from the DPI module (`disable_byedpi` never restores it), and is not mentioned in the DPI menu. A user who
disables the DPI bypass believes the change was undone.

**Fix:** move it to the privacy/tuning module with its own toggle and its own status line, and stop calling it
from the DPI path.

---

## Medium findings

| # | Finding | Location |
|---|---|---|
| M1 | `xargs`-free but still unguarded: `revert_dns_changes()` **deletes** the NM and resolved drop-ins instead of restoring a pre-existing user drop-in, and restores `DNS_CONFIG` only if `DNS_BACKUP` exists; relay/`[anonymized_dns]` blocks survive when it does not. | 908–931 |
| M2 | `cp "$DNS_CONFIG" "${DNS_CONFIG}.bak"` runs before every apply and is overwritten each time; a failed second apply leaves `.bak` as the only rollback. If `DNS_CONFIG` is absent, `set -e` aborts mid-apply. | 740, 812–816 |
| M3 | `check_tor_service()` only asserts `systemctl is-active tor`; Tor needs tens of seconds to bootstrap and the SOCKS port can be up but unusable. Boot-time DNS then fails while the shield blocks the fallback. | 715–730 |
| M4 | `disable_dns_shield()` treats the first delete failure as terminal (`\|\| break`) and leaves the rest of the chain in place. | 1044, 1051 |
| M5 | Some `iptables -I` calls in the shield path lack `2>/dev/null \|\| true`, so `set -e` can abort between the ACCEPTs and the DROP. Failure is then reported only as "Action finished with exit code 1". | 973, 975, 988, 990 |
| M6 | `uninstall_byedpi()` removes the unit and binary but leaves the `byedpi` system user and `/etc/byedpi.conf` behind. | 3800–3809 |
| M7 | `enable_dhcp_privacy()` only rewrites **existing** NM profiles; every new SSID joined later sends the hostname again, while status reports "BLOCKED (Protected)" from the marker file. | 2371–2387, 3178–3199 |
| M8 | `NM_MAC_CONF` sets `ethernet.cloned-mac-address=random` globally with no warning about 802.1X, DHCP reservations, captive portals, or Wake-on-LAN. | 1459–1470 |
| M9 | `clean_apt()` runs `autoremove --purge -y` with output suppressed, weekly, as root from the timer; `dist-upgrade -y --force-confold` can hold back security-relevant conffile changes. | 1680–1700, 1652–1660 |
| M10 | `restart_dns_services()` guards the socket with an always-true `list-unit-files` check (reproduced). | 868 |
| M11 | `clean_privacy()` truncates `/var/crash/*` and `/var/lib/systemd/coredump/*` uninspected — destroys crash evidence that a privacy scrub should arguably preserve for forensics on a compromised host. | 1634–1637 |
| M12 | Profile names are valid on this distro's resolver list (all 15 verified present in `public-resolvers.md`), but `dnscrypt-proxy -check` only validates TOML syntax — a distribution refresh that renames `cs-de`/`scaleway-ams` would fail at runtime, after the drop-ins are already pointed at a dead proxy. | 732–818 |
| M13 | The `anonymized_dns` label and the menu's "ODoH"/"Onion routing" wording overstate the mechanism: this is DNSCrypt relay routing, and for profiles 11–13 it is a SOCKS proxy through Tor's `9050`, not an onion service. The binary itself refuses anonymization for non-DNSCrypt servers ("DNS anonymization is only supported with the DNSCrypt protocol"). | 1176–1202, 1252–1261 |

---

## Suggested order of work

1. **C1** (DPI rule ordering) and **C2** (`-i ::`) — both are one-line-class changes that restore the
   exclusions the code already intends and stop exposing a LAN listener.
2. **H1** (privacy scrub no-op) — the module is presently lying about its primary function. Fix the guard, and
   re-verify the child guards still block the symlink attack afterwards.
3. **C3** — add `-L` / `realpath` containment to the two unguarded root write paths; reuse `is_safe_user_path`.
4. **C4** — owner-scope the bootstrap ACCEPTs, and make the shield survive a filter-table reload.
5. **H2, H3, H6, H7** — replace string-greps with observations. A hardening tool's status output is a security
   control; these four are the ones that report success in a failing state.
6. **H4, H5** — supply chain pin and unit sandboxing.
7. **H8** — add RFC 4941 to the privacy sysctls.
