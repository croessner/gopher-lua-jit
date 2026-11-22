#!/usr/bin/env python3
"""Summarizes the raw benchmark outputs in results/ as Markdown tables.

Usage: python3 summarize.py > results/summary.md
"""
import re
import statistics
import sys
from collections import defaultdict


def load_go(path):
    """Returns {benchmark name: {"ns": median, "bytes": median, "allocs": median, extra metrics}}."""
    runs = defaultdict(lambda: defaultdict(list))
    for line in open(path):
        if not line.startswith("Benchmark"):
            continue
        fields = line.split()
        name = re.sub(r"-\d+$", "", fields[0])[len("Benchmark"):]
        values = fields[2:]
        for value, unit in zip(values[0::2], values[1::2]):
            runs[name][unit].append(float(value))
    return {n: {u: statistics.median(v) for u, v in m.items()} for n, m in runs.items()}


def load_external(path):
    out = {}
    for line in open(path):
        m = re.match(r"(\S+)\s+n=\d+\s+(\d+) ns/op", line)
        if m:
            out[m.group(1)] = float(m.group(2))
    return out


def ms(ns):
    return "%.2f" % (ns / 1e6)


def main():
    fork = load_go("results/fork.txt")
    up = load_go("results/upstream.txt")
    lua55 = load_external("results/lua55.txt")
    luajit = load_external("results/luajit.txt")
    kernels = [n.split("/")[1] for n in up if n.startswith("Kernel/")]

    print("### Kernels: time per call in milliseconds (median of 3 runs)\n")
    print("| kernel | upstream | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 | lua5.5 | luajit |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|")
    for k in kernels:
        row = [k, ms(up["Kernel/%s/upstream" % k]["ns/op"])]
        for cfg in ("interp-lua51", "jit-lua51", "interp-lua55", "jit-lua55"):
            row.append(ms(fork["Kernel/%s/%s" % (k, cfg)]["ns/op"]))
        row.append(ms(lua55[k]) if k in lua55 else "-")
        row.append(ms(luajit[k]) if k in luajit else "-")
        print("| " + " | ".join(row) + " |")

    print("\n### Kernels: speedup relative to upstream GopherLua (higher is better)\n")
    print("| kernel | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 |")
    print("|---|---:|---:|---:|---:|")
    for k in kernels:
        base = up["Kernel/%s/upstream" % k]["ns/op"]
        row = [k]
        for cfg in ("interp-lua51", "jit-lua51", "interp-lua55", "jit-lua55"):
            row.append("%.2fx" % (base / fork["Kernel/%s/%s" % (k, cfg)]["ns/op"]))
        print("| " + " | ".join(row) + " |")

    print("\n### Kernels: heap allocations per call\n")
    print("| kernel | upstream allocs | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 | upstream bytes | JIT 5.5 bytes |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|")
    for k in kernels:
        row = [k, "%d" % up["Kernel/%s/upstream" % k]["allocs/op"]]
        for cfg in ("interp-lua51", "jit-lua51", "interp-lua55", "jit-lua55"):
            row.append("%d" % fork["Kernel/%s/%s" % (k, cfg)]["allocs/op"])
        row.append("%d" % up["Kernel/%s/upstream" % k]["B/op"])
        row.append("%d" % fork["Kernel/%s/jit-lua55" % k]["B/op"])
        print("| " + " | ".join(row) + " |")

    print("\n### JIT code size and compilation time per kernel (Lua 5.5 profile)\n")
    print("| kernel | units | executable memory (bytes) | total compile time (µs) |")
    print("|---|---:|---:|---:|")
    for k in kernels:
        m = fork["Kernel/%s/jit-lua55" % k]
        print("| %s | %d | %d | %d |" % (k, m.get("units", 0), m.get("code-bytes", 0), m.get("compile-us", 0)))

    print("\n### Other benchmarks (ns per operation, allocations per operation)\n")
    print("| benchmark | upstream | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 |")
    print("|---|---:|---:|---:|---:|---:|")
    groups = sorted({n.rsplit("/", 1)[0] for n in up if not n.startswith("Kernel/")} | {n for n in up if "/" not in n})
    for g in groups:
        def cell(table, cfg):
            m = table.get("%s/%s" % (g, cfg))
            if m is None:
                return "-"
            return "%.0f ns, %d allocs" % (m["ns/op"], m.get("allocs/op", 0))
        print("| %s | %s | %s | %s | %s | %s |" % (
            g, cell(up, "upstream"), cell(fork, "interp-lua51"), cell(fork, "jit-lua51"),
            cell(fork, "interp-lua55"), cell(fork, "jit-lua55")))


if __name__ == "__main__":
    sys.exit(main())
