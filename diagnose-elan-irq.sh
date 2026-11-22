#!/usr/bin/env bash
# diagnose-elan-irq.sh — catch a touchpad freeze and say which layer stalled.
#
# The runtime-PM fix is holding (controller stays status=active), so this
# instruments the next suspect: the shared pinctrl_amd / amd_gpio interrupt.
#
# A freeze is measured where you feel it: a hole in /dev/input/eventN while a
# finger is DOWN on the pad. While a finger is down the pad reports
# continuously (~170-290/s); with no finger it is silent, so a hole under a
# finger is a real stall. For each hole every layer underneath is sampled:
#
#   irqN  amd_gpio (ELAN1300:00)   the ELAN asserted the interrupt line
#   irqP  pinctrl_amd              the pin controller saw the pin change
#   irqM  AMDI0010:03 (i2c_dw)     a report moved over I2C
#   eventN /dev/input/eventN       the report reached userspace
#
# Holes of 50ms and up are logged; only ones >=150ms decide the verdict, so
# single-frame jitter cannot blame the GPIO path. A pad that stops for good
# sends no resume report, so a hole that outlasts itself (1s of silence) is
# reported on a timeout and marked "never recovered" instead of being lost.
#
# You can also mark a freeze by hand: press F9 the moment the cursor stops.
# That records how long the input layer had already been silent ("ago") and
# counts the IRQs for the next second, so it works even if the pad is dead
# before you reach the keyboard. Keep a finger down when you press it -- an
# idle pad is silent by design, so a mark with no finger down is ignored:
#
#   MARKER 01:14:02 ago=2.311 down=1 gpio=+0 i2c=+0 parent=+0   -> dead GPIO path
#   MARKER 01:14:02 ago=0.020 down=1 gpio=+9 i2c=+31 parent=+9  -> data was moving
#
# While it runs, irq_handler_entry is traced for those three lines, so the
# report can show exactly when each last fired even when the counters agree.
# If the pin keeps firing while no report is read, a "NOTE hot" line records
# it: line stuck/hot, or reports dropped before /dev/input.
#
#   gpio silent  -> pinctrl_amd / amd_gpio lost the interrupt (level IRQ left
#                   masked, or an edge lost) -> patch/override that path
#   i2c silent   -> gpio fired but the DesignWare controller stalled
#   both active  -> data arrived; the stall is i2c_hid / hid-multitouch
#                   (or a compositor stall if the driver logged nothing)
#
# Usage:
#   sudo ./diagnose-elan-irq.sh            # watch for 5 minutes
#   sudo ./diagnose-elan-irq.sh -d 900     # 15 minutes
#
# Root is needed to read /dev/input/eventN. While it runs, use the touchpad
# normally — drag a window around now and then so a freeze has a chance to
# happen with a finger down, and press F9 while it is stuck.
#
# The report says when a run proves nothing: "nothing to judge" means the pad
# was never touched, and no reports while the pin fires means either a dead pad
# or the wrong input node -- it says so instead of guessing.

set -euo pipefail

DUR=300
OUT=/tmp/elan-diag-$(date +%Y%m%d-%H%M%S)
die() { echo "[!] $*" >&2; exit 1; }
info() { echo "[*] $*"; }

while [ $# -gt 0 ]; do
    case $1 in
        -d|--duration) DUR=${2:?seconds} ; shift 2 ;;
        -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d;s/^# \{0,1\}//' ; exit 0 ;;
        *) die "unknown argument: $1 (try --help)" ;;
    esac
done
case $DUR in ''|*[!0-9]*) die "duration must be a number of seconds" ;; esac
[ "$DUR" -gt 0 ] || die "duration must be > 0"

[ "$EUID" -eq 0 ] || die "run with sudo: /dev/input/eventN is root-only"

# Fail here rather than sampling a path we cannot read for the whole window.
probe_readable() { # <node>
    [ -c "$1" ] || return 1
    timeout 1 dd if="$1" of=/dev/null bs=1 count=0 status=none 2>/dev/null
}

# --- discovery -------------------------------------------------------------
ELAN_BASE=$(for d in /sys/bus/i2c/devices/*ELAN*; do
    [ -r "$d/name" ] && { echo "$d"; break; }
done || true)
[ -n "$ELAN_BASE" ] || die "no ELAN I2C touchpad found"

CTRL=$(readlink -f "$ELAN_BASE/.."); CTRL=${CTRL%/*}   # AMDI0010:03
EVDEV=$(grep -l "Touchpad" /sys/class/input/event*/device/name 2>/dev/null | head -1)
EVDEV=${EVDEV%/device/name}
[ -n "$EVDEV" ] || die "could not find the touchpad input node"
# that is the sysfs node; the one to read is /dev/input/eventN
EVDEV_NODE=/dev/input/${EVDEV##*/}
[ -c "$EVDEV_NODE" ] || die "$EVDEV_NODE is not a character device"
probe_readable "$EVDEV_NODE" || die "cannot read $EVDEV_NODE (are you root?)"

# Any keyboard works for the F9 marker; prefer the built-in one. Note these are
# sysfs paths: the node to open is the matching /dev/input/eventN.
KBD=""
for n in /sys/class/input/event*/device/name; do
    [ -r "$n" ] || continue
    case $(<"$n") in
        *[Tt]ouchpad*|*Mouse*) continue ;;
        *"Set 2 keyboard"*) KBD=${n%/device/name}; break ;;
    esac
done
if [ -n "$KBD" ]; then KBD=/dev/input/${KBD##*/}; fi
[ -c "${KBD:-/nonexistent}" ] || KBD=""

GPIO_IRQ=$(awk -v n="${ELAN_BASE##*/i2c-}" '/amd_gpio/ && index($0, n) { sub(":", ""); print $1 }' /proc/interrupts)
I2C_IRQ=$(awk -v n="${CTRL##*/}" 'index($0, n) { sub(":", ""); print $1 }' /proc/interrupts)
[ -n "$GPIO_IRQ" ] || die "could not find the amd_gpio IRQ for $ELAN_BASE (is pinctrl_amd loaded?)"

# The parent of the amd_gpio line: if it fires but irq$GPIO_IRQ does not, the
# pin controller took the interrupt and never dispatched it to the ELAN.
GPIO_PARENT=$(awk '/pinctrl_amd/ { sub(":", ""); print $1 }' /proc/interrupts | head -1)
GPIO_PARENT=${GPIO_PARENT:--1}

PM_CTRL="$CTRL/power/control"
PM_BEFORE=$(cat "$CTRL/power/runtime_suspended_time" 2>/dev/null || echo 0)
SPUR_BEFORE=$(cat /proc/irq/"$GPIO_IRQ"/spurious 2>/dev/null | tr '\n' ' ' || true)

irq_total() { # <irq>
    awk -v n="$1" '$1 == n ":" { s = 0; for (i = 2; i <= NF; i++) { if ($i !~ /^[0-9]+$/) break; s += $i } print s }' \
        /proc/interrupts
}
GPIO_BEFORE=$(irq_total "$GPIO_IRQ")
I2C_BEFORE=$(irq_total "${I2C_IRQ:--1}")

# ftrace: a per-interrupt timeline. The counters only say "did it move during
# this hole"; the trace says exactly when the line last fired and for how long
# it went quiet, which is what we need if the counters look ambiguous.
TRACE_DIR=""
for d in /sys/kernel/tracing /sys/kernel/debug/tracing; do
    [ -w "$d/current_tracer" ] && { TRACE_DIR=$d; break; }
done

trace_on() {
    [ -n "$TRACE_DIR" ] || return 1
    local ev="$TRACE_DIR/events/irq/irq_handler_entry" want="irq==$GPIO_IRQ"
    # -1 means "line not identified": leave it out of the filter
    if [ "${I2C_IRQ:--1}" != -1 ]; then want="$want || irq==$I2C_IRQ"; fi
    if [ "${GPIO_PARENT:--1}" != -1 ]; then want="$want || irq==$GPIO_PARENT"; fi
    {
        echo nop > "$TRACE_DIR/current_tracer" &&
        printf '%s' "$want" > "$ev/filter" &&
        echo 1 > "$ev/enable" &&
        echo > "$TRACE_DIR/trace"
    } 2>/dev/null || { TRACE_DIR=""; return 1; }
    return 0
}

trace_off() {
    [ -n "$TRACE_DIR" ] || return 0
    echo 0 > "$TRACE_DIR/events/irq/irq_handler_entry/enable" 2>/dev/null || true
    echo 0 > "$TRACE_DIR/events/irq/irq_handler_entry/filter" 2>/dev/null || true
}

mkdir -p "$OUT"
info "touchpad   : $ELAN_BASE"
info "controller : $CTRL"
info "input node : $EVDEV_NODE"
info "gpio irq   : $GPIO_IRQ    i2c irq: ${I2C_IRQ:-unknown}    parent: ${GPIO_PARENT:-none}"
info "output     : $OUT"
info "sampling for ${DUR}s — use the touchpad normally (Ctrl-C to stop early)"
info "keep a finger on the pad while you drag: a freeze only counts then"
if [ -n "$KBD" ]; then
    info "press F9 the instant it freezes (watching ${KBD##*/})"
else
    info "no keyboard found: F9 marking disabled"
fi
if trace_on; then
    info "ftrace: recording irq_handler_entry for irq $GPIO_IRQ / ${I2C_IRQ:-?} / ${GPIO_PARENT:-?}"
else
    info "ftrace unavailable (not root on tracingfs?): counters only"
fi

# --- sampler ---------------------------------------------------------------
cat > "$OUT/sample.py" <<'PY'
import os, select, struct, sys, time

dur, evdev, outpath, gpio_irq, i2c_irq, kbd, gpio_parent = sys.argv[1:8]
dur = float(dur)
out = open(outpath, "w", buffering=1)

EV = struct.Struct("llHHi")        # struct input_event on x86_64
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
ABS_MT_SLOT, ABS_MT_TRACKING_ID = 0x2f, 0x39
KEY_F9 = 67
SAMPLE = 0.02
MARK_WINDOW = 1.0      # how long to watch the IRQs after a manual mark
GAP_SQLT = 0.05        # single-frame hole: >= one 60 Hz frame, below is jitter
GAP_BIG = 0.15         # a hole the user actually notices
IDLE_STOP = 1.0        # silence this long while down == the freeze never ended
GAPS_MAX = 200         # keep gaps.log bounded when the pad dies early

def counters():
    """Cumulative interrupt counts: ELAN pin, its pinctrl_amd parent, the i2c line."""
    got = {"gpio": 0, "i2c": 0, "parent": 0}
    # the override exists so the sampler can be tested without real hardware
    with open(os.environ.get("TOUCHPAD_DIAG_INTERRUPTS", "/proc/interrupts")) as f:
        for line in f:
            if ":" not in line:
                continue
            irq = line.split(":", 1)[0].strip()
            key = {gpio_irq: "gpio", gpio_parent: "parent"}.get(irq)
            if i2c_irq != "-1":          # "-1" = the i2c line was not identified
                key = key or {i2c_irq: "i2c"}.get(irq)
            if key:
                # per-CPU counts, then the chip and the action name: stop at the
                # first non-number so this works on any CPU count (not just 12)
                n = 0
                parts = line.split(":", 1)[1].split()
                for x in parts:
                    if not x.isdigit():
                        break
                    n += int(x)
                got[key] = n
    return got

def state(src, active):
    if (src == "i2c" and i2c_irq == "-1") or (src == "parent" and gpio_parent == "-1"):
        return "n/a"                     # line not identified, nothing to say
    return "active" if active[src] else "silent"

def emit(kind, gap, active):
    out.write("%s %s %.3f gpio=%s i2c=%s parent=%s\n" % (
        kind, time.strftime("%H:%M:%S", time.localtime(time.time() - gap)), gap,
        state("gpio", active), state("i2c", active), state("parent", active)))

def summary():
    # Rewritten continuously, so a Ctrl-C or a freeze that kills the pad still
    # leaves a verdict in gaps.log instead of an empty file.
    out.write("SUMMARY events=%d max_down=%d late=%d max_lag=%.0fms gaps=%d "
              "long=%d longest=%.2fs\n"
              % (events, max_down, late, max_lag * 1000, gaps, long, longest))

def begin_hole(now, length):
    """One hole in the input stream, closed by the next report or by timeout."""
    global gaps, long, longest, freezes
    emit("GAP", length, {s: ticks[s] - at_ev[s] > 0 for s in ticks})
    gaps += 1
    if length > longest:
        longest = length
    if length >= GAP_BIG:
        long += 1
        freezes += 1

fd = os.open(evdev, os.O_RDONLY | os.O_NONBLOCK)
kfd = os.open(kbd, os.O_RDONLY | os.O_NONBLOCK) if kbd else None
fds = [fd] + ([kfd] if kfd else [])

# slot -> finger down?  A gap only counts as a freeze when a finger was down:
# an untouched pad legitimately produces no events (typing, reading, ...).
slots = {}
cur_slot = 0
down = 0

prev = counters()
ticks = {"gpio": 0, "i2c": 0, "parent": 0}   # ticks in which each layer moved
at_ev = dict(ticks)                # ticks at the previous event
last_ev = time.monotonic()
freezes = 0
residue = b""
kresidue = b""
mark = None                        # pending F9 observation
events = 0                         # pad reports seen
max_down = 0                       # most fingers down at once
max_lag = 0.0                      # worst input-event delivery lag (s)
late = 0                           # events that arrived late from the kernel
rerr = 0                           # consecutive read errors
LATE = 0.05
gaps = long = 0                    # holes in the stream (>=GAP_SQLT / >=GAP_BIG)
longest = 0.0
hole_open = False                  # finger down and nothing arriving
out_tick = time.monotonic()
hot = 0                            # consecutive ticks in which the ELAN pin fired
hot_reported = False
summary()

end = time.monotonic() + dur
while True:
    now = time.monotonic()
    if now >= end:
        break
    r, _, _ = select.select(fds, [], [], SAMPLE)
    if fd in r:
        try:
            buf = residue + os.read(fd, EV.size * 256)
        except OSError as e:
            rerr += 1
            if rerr == 1:
                out.write("NOTE read-error %s\n" % e)
            if rerr > 3:                 # nothing will ever arrive: stop
                out.write("NOTE fatal cannot read %s (%s)\n" % (evdev, e))
                break
            buf = residue
        if not buf:                      # readable but empty (EOF on a fifo /
            time.sleep(SAMPLE)           # a node with nothing to give): don't spin
        whole = len(buf) - len(buf) % EV.size
        residue = buf[whole:]
        was_down = down > 0              # finger state during the gap
        wall = time.time()               # input_event stamps are CLOCK_REALTIME
        for off in range(0, whole, EV.size):
            sec, usec, etype, code, value = EV.unpack_from(buf, off)
            if etype != 0:               # EV_SYN 0 carries the same timestamp
                lag = wall - (sec + usec / 1e6)
                if 0 <= lag <= 5:        # ignore clock steps
                    if lag > max_lag:
                        max_lag = lag
                    if lag > LATE:
                        late += 1
            if etype == EV_ABS and code == ABS_MT_SLOT:
                cur_slot = value
            elif etype == EV_ABS and code == ABS_MT_TRACKING_ID:
                was = slots.get(cur_slot, False)
                is_down = value >= 0
                if is_down != was:
                    down += 1 if is_down else -1
                slots[cur_slot] = is_down
        if whole:
            now = time.monotonic()
            events += whole // EV.size
            if down > max_down:
                max_down = down
            gap = now - last_ev
            if gaps < GAPS_MAX:
                if hole_open:            # the timeout already reported this one
                    hole_open = False
                elif gap >= GAP_SQLT and was_down:
                    begin_hole(now, gap)
            last_ev = now
            at_ev = dict(ticks)

    if kfd and kfd in r:
        try:
            kbuf = kresidue + os.read(kfd, EV.size * 64)
        except OSError:
            kbuf = kresidue
        kwhole = len(kbuf) - len(kbuf) % EV.size
        kresidue = kbuf[kwhole:]
        now = time.monotonic()
        for off in range(0, kwhole, EV.size):
            _, _, etype, code, value = EV.unpack_from(kbuf, off)
            if etype == EV_KEY and code == KEY_F9 and value == 1 and mark is None:
                mark = {"t": time.time(), "ago": now - last_ev, "down": down > 0,
                        "at": counters(), "until": now + MARK_WINDOW}

    if mark and now >= mark["until"]:
        cur = counters()
        dg = cur.get("gpio", 0) - mark["at"].get("gpio", 0)
        di = cur.get("i2c", 0) - mark["at"].get("i2c", 0)
        dp = cur.get("parent", 0) - mark["at"].get("parent", 0)
        out.write("MARKER %s ago=%.3f down=%d gpio=+%d i2c=+%d parent=+%d\n" % (
            time.strftime("%H:%M:%S", time.localtime(mark["t"])),
            mark["ago"], 1 if mark["down"] else 0, dg, di, dp))
        mark = None

    # A pad that stops for good sends no resume report, so a hole cannot be
    # closed by waiting for the next event -- that is why a dead pad used to
    # come out as "no freeze captured". Close it on a timeout instead.
    if down > 0 and not hole_open and gaps < GAPS_MAX:
        hole = now - last_ev
        if hole >= IDLE_STOP:
            begin_hole(now, hole)
            out.write("NOTE stuck\n")
            slots.clear()                # don't report the same dead touch twice
            down = 0
            hole_open = True

    if now - out_tick >= 1.0:            # keep SUMMARY fresh for Ctrl-C
        summary()
        out_tick = now

    cur = counters()
    for src in ticks:
        if cur.get(src) != prev.get(src):
            ticks[src] += 1
    # Is the pin itself self-triggering? The ELAN's idle pin does not fire at all
    # (measured: irq50 and irq7 both +0 over 10s with no finger), so a pin that
    # keeps firing while no report is being read is either a line stuck/hot or
    # reports being dropped between the ELAN and /dev/input. Normal movement
    # fires the pin too, so require that input has also gone quiet.
    hot = hot + 1 if cur.get("gpio", 0) != prev.get("gpio", 0) else 0
    if hot >= 20 and not hot_reported and now - last_ev >= 0.4:
        hot_reported = True
        out.write("NOTE hot gpio irq%s asserted %d consecutive ticks (~%.1fs) "
                  "with %d report(s) read\n"
                  % (gpio_irq, hot, hot * SAMPLE, events))
    prev = cur

summary()
out.write("DONE freezes=%d\n" % freezes)
PY

trap 'kill $JOURNAL 2>/dev/null || true; trace_off' INT TERM
journalctl -k -f --since "$(date '+%Y-%m-%d %H:%M:%S')" > "$OUT/dmesg.log" 2>/dev/null &
JOURNAL=$!
python3 "$OUT/sample.py" "$DUR" "$EVDEV_NODE" "$OUT/gaps.log" "$GPIO_IRQ" "${I2C_IRQ:--1}" \
        "$KBD" "${GPIO_PARENT:--1}" || true
kill $JOURNAL 2>/dev/null || true
wait $JOURNAL 2>/dev/null || true
if [ -n "$TRACE_DIR" ]; then
    trace_off
    cat "$TRACE_DIR/trace" > "$OUT/irq.trace" 2>/dev/null || true
fi

PM_AFTER=$(cat "$CTRL/power/runtime_suspended_time" 2>/dev/null || echo 0)
PM_STATUS=$(cat "$CTRL/power/runtime_status" 2>/dev/null || echo n/a)
SPUR_AFTER=$(cat /proc/irq/"$GPIO_IRQ"/spurious 2>/dev/null | tr '\n' ' ' || true)
GPIO_AFTER=$(irq_total "$GPIO_IRQ")
I2C_AFTER=$(irq_total "${I2C_IRQ:--1}")
GPIO_D=$(( ${GPIO_AFTER:-0} - ${GPIO_BEFORE:-0} ))
I2C_D=$(( ${I2C_AFTER:-0} - ${I2C_BEFORE:-0} ))

# --- report ----------------------------------------------------------------
{
    echo "ELAN touchpad freeze report — $(date)"
    echo "================================================================"
    echo "watch window : ${DUR}s"
    echo "gpio irq     : $GPIO_IRQ (amd_gpio, ELAN pin)   parent: $GPIO_PARENT (pinctrl_amd)"
    echo "i2c irq      : ${I2C_IRQ:-unknown} ($CTRL)"
    echo "runtime pm   : control=$(cat "$PM_CTRL" 2>/dev/null || echo n/a) status=$PM_STATUS" \
         "suspended_during_run=$(( PM_AFTER - PM_BEFORE ))ms"
    echo "irq activity : gpio +$GPIO_D  i2c +$I2C_D  over ${DUR}s"
    if grep -q '^SUMMARY' "$OUT/gaps.log"; then
        echo "pad activity : $(grep '^SUMMARY' "$OUT/gaps.log" | tail -1 | sed 's/^SUMMARY //')"
        echo "               (events read from ${EVDEV##*/}; late/max_lag = kernel"
        echo "               delivery delay of those reports)"
    fi
    echo
    if grep -q '^GAP' "$OUT/gaps.log"; then
        echo "holes in the input stream with a finger down (per layer):"
        awk '/^GAP/ { printf "  %-6s %s  %-6s %s %s %s\n",
                       ($3 + 0 >= 0.15 ? "LONG" : "short"), $2, $3, $4, $5, $6 }
             /^NOTE stuck/ { print "  (the hole above never recovered: reported by"
                             " timeout, not by a later report)" }' "$OUT/gaps.log"
        echo "  LONG = >=150ms, i.e. one you felt. gpio=silent means the ELAN pin"
        echo "  did not fire at all during that hole."
    elif ! grep -q '^MARKER' "$OUT/gaps.log"; then
        echo "no hole in the input stream while a finger was down."
    fi
    grep '^NOTE hot' "$OUT/gaps.log" | sed 's/^/  /' || true
    if grep -q '^MARKER' "$OUT/gaps.log"; then
        echo
        echo "manual F9 marks (input silence before the key; IRQ counts for 1s after):"
        grep '^MARKER' "$OUT/gaps.log" | sed 's/^MARKER /  /'
        echo "  ago>0.15 down=1 means the pad had already stopped delivering."
        echo "  gpio=+0 i2c=+0          => the ELAN never asserted: pinctrl_amd / amd_gpio."
        echo "  gpio=+0 parent=+N       => the pin controller fired but never dispatched"
        echo "                             to the ELAN: misrouted amd_gpio interrupt."
        echo "  gpio=+N i2c=+0          => GPIO fired but the I2C transfer did not complete."
        echo "  gpio=+N i2c=+M          => data kept arriving: i2c_hid/hid-multitouch/userspace."
    fi
    grep '^NOTE \(read-error\|fatal\)' "$OUT/gaps.log" | sed 's/^/  /' || true

    if [ -s "$OUT/irq.trace" ]; then
        echo
        echo "irq timeline (from ftrace; gaps here are when a line did not fire)"
        echo "----------------------------------------------------------------"
        awk '/irq_handler_entry:/ {
                match($0, /irq=[0-9]+/); irq = substr($0, RSTART + 4, RLENGTH - 4)
                t = $4; sub(/:$/, "", t)
                if (irq in first) { last[irq] = t } else { first[irq] = t; last[irq] = t }
                n[irq]++
             }
             END { for (i in n) printf "  irq%s: %d calls, first %s, last %s\n", i, n[i], first[i], last[i] }' \
            "$OUT/irq.trace" | sort -t'q' -k2 -n
        echo "  full log: $OUT/irq.trace"
    fi

    echo
    echo "gpio irq $GPIO_IRQ spurious/unhandled: before [ $SPUR_BEFORE] after [ $SPUR_AFTER]"
    echo
    echo "kernel messages during the run"
    echo "----------------------------------------------------------------"
    if grep -Eqi 'i2c|hid|gpio|elan|irq|timeout|error' "$OUT/dmesg.log" 2>/dev/null; then
        grep -Ei 'i2c|hid|gpio|elan|irq|timeout|error' "$OUT/dmesg.log" | tail -40
    else
        echo "  (none — the driver never reported an error)"
    fi

    echo
    echo "verdict"
    echo "----------------------------------------------------------------"
    awk -v girq="$GPIO_IRQ" -v iirq="${I2C_IRQ:-?}" \
        -v iglobal="$GPIO_D" \
        -v nevents="$(awk '/^SUMMARY/ { for (i = 2; i <= NF; i++) { split($i, kv, "="); if (kv[1] == "events") ev = kv[2] } } END { print ev+0 }' "$OUT/gaps.log" 2>/dev/null)" \
        -v ngaps="$(awk '/^SUMMARY/ { for (i = 2; i <= NF; i++) { split($i, kv, "="); if (kv[1] == "gaps") gp = kv[2] } } END { print gp+0 }' "$OUT/gaps.log" 2>/dev/null)" \
        -v longest="$(awk '/^SUMMARY/ { for (i = 2; i <= NF; i++) { split($i, kv, "="); if (kv[1] == "longest") { sub("s$", "", kv[2]); lg = kv[2] } } } END { print lg+0 }' "$OUT/gaps.log" 2>/dev/null)" \
        -v hot="$(grep -c '^NOTE hot' "$OUT/gaps.log" 2>/dev/null || echo 0)" \
        -v known_i2c="$([ "${I2C_IRQ:--1}" = -1 ] && echo 0 || echo 1)" '
        /^GAP/ {
            n++
            # only holes you could actually feel decide the verdict; sub-150ms
            # ones are jitter and would otherwise blame the GPIO path for nothing
            if ($3 + 0 >= 0.15) { longn++
                # a layer is "silent" only if we were actually watching it
                if ($4 == "gpio=silent")                  g++
                else if ($5 == "i2c=silent" && known_i2c) i++
                else                                      h++
                if ($4 == "gpio=silent" && $6 == "parent=active") pg++
            }
        }
        /^MARKER/ {
            split($3, a, "="); split($4, d, "="); split($5, b, "="); split($6, c, "=")
            split($7, e, "=")
            if (a[2] + 0 > 0.15) {
                # A mark with no finger down proves nothing: an idle pad is
                # silent by design. Keep it out of the verdict, mention it.
                if (d[2] + 0 != 1) { md0++; next }
                m++
                if (b[2] + 0 == 0 && c[2] + 0 == 0) {
                    mg++
                    if (e[2] + 0 > 0) pm++
                } else if (c[2] + 0 == 0)   mi++
                else                        mh++
            }
        }
        END {
            if (!longn && !m) {
                if (!iglobal) {
                    print "  nothing to judge: the ELAN pin never fired, so the pad"
                    print "  was not touched during the run. A freeze could not have"
                    print "  been caught. Rerun and keep using the touchpad."
                } else if (nevents + 0 == 0) {
                    printf "  no input report was read at all, yet irq%s fired %s\n", \
                           girq, iglobal
                    print  "  times. Either the pad was dead for the whole window, or"
                    print  "  the wrong input node was opened. Next: while the pad is"
                    print  "  dead, run   sudo xxd -l 64 /dev/hidraw0"
                    print  "  Raw reports there => the stall is above i2c_hid (HID /"
                    print  "  hid-multitouch). It hangs => i2c_hid or the bus, not GPIO."
                } else {
                    printf "  no freeze: %d report(s) arrived and none stalled >=150ms\n", nevents
                    print  "  with a finger down. Rerun with a longer -d, or start it"
                    print  "  right before the pad usually dies."
                }
            } else if (g || mg) {
                g = g + mg; longn = longn + m
                printf "  %d/%d holes: irq%s (amd_gpio) went silent -> pinctrl_amd /\n", g, longn, girq
                print  "  amd_gpio lost the ELAN interrupt (level IRQ left masked, or"
                print  "  an edge lost while the line was masked). That is the cause;"
                print  "  the fix is a pinctrl_amd/amd_gpio patch or an ACPI override."
                if (pg || pm) {
                    printf "  in %d of them the pinctrl_amd parent irq still fired, so\n", pg + pm
                    print  "  the pin controller took the interrupt and never dispatched"
                    print  "  it to the ELAN: a spurious/misrouted amd_gpio dispatch, not"
                    print  "  a missed edge. Neither is fixable from ACPI alone; the"
                    print  "  irq.trace next to this report has the exact timeline."
                } else {
                    print  "  the parent pinctrl_amd irq was silent too: the ELAN itself"
                    print  "  did not assert, or the pin was left masked by amd_gpio."
                }
            } else if (i || mi) {
                i = i + mi; longn = longn + m
                printf "  %d/%d holes: gpio fired but irq%s (i2c) went silent -> the\n", i, longn, iirq
                print  "  DesignWare controller stalled mid-transfer."
            } else {
                h = h + mh; longn = longn + m
                printf "  %d/%d holes: both IRQs kept firing but nothing reached\n", h, longn
                print  "  /dev/input. Data arrived at i2c_hid, so the stall is in"
                print  "  i2c_hid / hid-multitouch or in the compositor, not the GPIO path."
            }
            if (longn + 0 > 0)
                printf "  %d hole(s) >=150ms, longest %.2fs (of %d >=50ms)\n", longn, longest, ngaps
            else if (ngaps + 0 > 0)
                printf "  %d hole(s), none >=150ms; longest %.2fs -> jitter, not a freeze\n", ngaps, longest
            if (hot + 0 > 0) {
                print  "  the ELAN pin also fired continuously with no report read:"
                print  "  see the NOTE hot line above (line stuck/hot, or reports dropped"
                print  "  before /dev/input). Compare with irq.trace for the exact timing."
            }
            if (md0) {
                printf "  %d F9 mark(s) had no finger down, so they were ignored:\n", md0
                print  "  an idle pad is silent by design. To catch a freeze, keep a"
                print  "  finger on the pad and press F9 with the other hand."
            }
        }' "$OUT/gaps.log"
} | tee "$OUT/report.txt"

if [ -s "$OUT/irq.trace" ]; then
    echo
    info "irq timeline: $OUT/irq.trace ($(wc -l < "$OUT/irq.trace") lines)"
fi
echo
info "wrote $OUT/report.txt"
