#!/usr/bin/env python3
"""
tero_host.py -- talk to the TC-TERO design on the EDGE Artix-7 board.

  python tero_host.py --port COM5 ping
  python tero_host.py --port COM5 search  --out search_tc_X4Y16.bin            (2^20 params)
  python tero_host.py --port COM5 search  --bits 16 --out search_c_X4Y16.bin   (C-TERO)
  python tero_host.py --port COM5 counter --param 0x080ec --n 65536 --out cnt.bin
  python tero_host.py --port COM5 trng    --param 0x080ec --nbytes 134217728 --out trng.bin

Linux: --port /dev/ttyUSB1 (the FT2232H shows two ports; the UART is usually the 2nd).
"""
import argparse, os, struct, sys, time
import serial

BAUD = 3_000_000
LOOP_NAMES = {0: "plain TERO", 1: "C-TERO (16-bit)", 2: "TC-TERO (20-bit)"}


def open_port(name):
    s = serial.Serial(name, BAUD, timeout=0.2)
    try:
        s.set_buffer_size(rx_size=1 << 22, tx_size=4096)   # Windows only
    except Exception:
        pass
    time.sleep(0.05)
    s.reset_input_buffer()
    return s


def read_exact(s, n, idle_timeout=15.0, progress=None, sink=None):
    """Read exactly n bytes. If sink is given, bytes are written there instead
    of being kept in memory. Raises TimeoutError if the board goes silent."""
    buf = bytearray()
    got, last = 0, time.time()
    t0 = time.time()
    while got < n:
        chunk = s.read(min(1 << 16, n - got))
        if chunk:
            got += len(chunk)
            last = time.time()
            if sink is not None:
                sink.write(chunk)
            else:
                buf += chunk
            if progress:
                progress(got, n, time.time() - t0)
        elif time.time() - last > idle_timeout:
            raise TimeoutError(f"board silent: got {got} of {n} bytes")
    return bytes(buf)


def bar(prefix):
    state = {"t": 0}
    def p(got, n, el):
        if time.time() - state["t"] < 0.5 and got < n:
            return
        state["t"] = time.time()
        rate = got / el / 1024 if el > 0 else 0
        eta = (n - got) / (got / el) if got and el > 0 else 0
        sys.stdout.write(f"\r{prefix} {100*got/n:6.2f}%  {got}/{n} B  {rate:7.1f} KiB/s  ETA {eta/60:6.1f} min ")
        sys.stdout.flush()
        if got >= n:
            sys.stdout.write("\n")
    return p


def cmd_ping(s, a):
    s.write(b"P")
    r = read_exact(s, 6, idle_timeout=2.0)
    if r[:4] != b"TERO":
        print("Unexpected reply:", r.hex()); return 1
    print(f"OK: board answered, LOOP_TYPE={r[4]} ({LOOP_NAMES.get(r[4], '?')}), version={r[5]}")
    return 0


def cmd_search(s, a):
    total = 1 << a.bits
    start = a.start
    end = total if a.count is None else start + a.count
    mode = "ab" if (a.resume and os.path.exists(a.out)) else "wb"
    if mode == "ab":
        done = os.path.getsize(a.out) // 8
        start = a.start + done
        print(f"Resuming at parameter {start} ({done} records already in {a.out})")
    chunk = a.chunk
    with open(a.out, mode) as f:
        p = start
        t0 = time.time()
        while p < end:
            n = min(chunk, end - p)
            for attempt in range(3):
                try:
                    s.reset_input_buffer()
                    s.write(b"S" + p.to_bytes(3, "big") + n.to_bytes(3, "big"))
                    data = read_exact(s, 8 * n, idle_timeout=20.0)
                    break
                except TimeoutError as e:
                    print(f"\n  chunk at {p}: {e}; press the centre button (SW22) if needed, retrying...")
                    time.sleep(2.0)
            else:
                print("Giving up. Re-run with --resume to continue."); return 1
            f.write(data); f.flush()
            p += n
            el = time.time() - t0
            frac = (p - start) / (end - start)
            eta = el / frac * (1 - frac) if frac > 0 else 0
            print(f"\r  params {p:8d}/{end}  ({100*frac:5.1f}%)  elapsed {el/60:5.1f} min  ETA {eta/60:5.1f} min", end="")
    print(f"\nSaved {a.out}")
    return 0


def search_one(s, p):
    s.reset_input_buffer()
    s.write(b"S" + p.to_bytes(3, "big") + (1).to_bytes(3, "big"))
    v = int.from_bytes(read_exact(s, 8, idle_timeout=5.0), "big")
    sat = v >> 63; sm = (v >> 32) & 0x7FFFFFFF; sq = v & 0xFFFFFFFF
    m = sm / 4096; sd = max(sq / 4096 - m * m, 0) ** 0.5
    return m, sd, sat


def cmd_probe(s, a):
    """Re-measure parameters with 4096 back-to-back trials, several times."""
    print("param      run   avg     std    saturated?")
    for p in a.params:
        for r in range(a.repeat):
            m, sd, sat = search_one(s, p)
            print(f"0x{p:05x}  {r+1:3d}  {m:7.2f} {sd:6.2f}   {'YES' if sat else 'no'}")
            time.sleep(a.gap)
    return 0


def run_stream(s, cmdbyte, a, nbytes):
    s.reset_input_buffer()
    s.write(cmdbyte + a.param.to_bytes(3, "big") + nbytes.to_bytes(4, "big"))
    t0 = time.time()
    with open(a.out, "wb") as f:
        read_exact(s, nbytes, idle_timeout=20.0, progress=bar("  receiving"), sink=f)
    tr = read_exact(s, 16, idle_timeout=5.0)
    wall = time.time() - t0
    act, ntr, nsat = struct.unpack(">QII", tr)
    return act, ntr, nsat, wall


def cmd_counter(s, a):
    act, ntr, nsat, wall = run_stream(s, b"C", a, a.n)
    print(f"Saved {a.n} counter values to {a.out}")
    print(f"  trials={ntr}  saturated(0xFF)={nsat}  on-chip time={act/1e8:.3f} s  "
          f"trial rate={ntr/(act/1e8)/1e6:.3f} M trials/s")
    return 0


def cmd_trng(s, a):
    act, ntr, nsat, wall = run_stream(s, b"T", a, a.nbytes)
    bits = 8 * a.nbytes
    t = act / 1e8
    gen = ntr - nsat
    print(f"Saved {bits} random bits to {a.out}")
    print(f"  trials={ntr}  discarded (saturated)={nsat} ({100*nsat/max(ntr,1):.3f} %)")
    print(f"  generator throughput = {gen/t/1e6:.3f} Mbit/s   (paper: 1.912 Mbit/s)")
    print(f"  (bits generated = {gen}, sent to PC = {bits}; the rest were dropped while the UART was busy)")
    print(f"  wall-clock time = {wall:.1f} s (includes UART)")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", required=True)
    sp = ap.add_subparsers(dest="cmd", required=True)
    sp.add_parser("ping")
    q = sp.add_parser("search")
    q.add_argument("--out", required=True)
    q.add_argument("--bits", type=int, default=20, help="20 for TC-TERO, 16 for C-TERO")
    q.add_argument("--start", type=int, default=0)
    q.add_argument("--count", type=int, default=None)
    q.add_argument("--chunk", type=int, default=16384)
    q.add_argument("--resume", action="store_true")
    q = sp.add_parser("probe")
    q.add_argument("--params", type=lambda x: int(x, 0), nargs="+", required=True)
    q.add_argument("--repeat", type=int, default=3)
    q.add_argument("--gap", type=float, default=0.5, help="seconds between repeats")
    for name in ("counter", "trng"):
        q = sp.add_parser(name)
        q.add_argument("--param", type=lambda x: int(x, 0), required=True)
        q.add_argument("--out", required=True)
        if name == "counter":
            q.add_argument("--n", type=int, default=65536)
        else:
            q.add_argument("--nbytes", type=int, default=1 << 27)
    a = ap.parse_args()
    s = open_port(a.port)
    try:
        return {"ping": cmd_ping, "search": cmd_search,
                "counter": cmd_counter, "trng": cmd_trng, "probe": cmd_probe}[a.cmd](s, a)
    finally:
        s.close()


if __name__ == "__main__":
    sys.exit(main())
