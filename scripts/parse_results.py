#!/usr/bin/env python3
"""Parse raw cachesim output into a tidy CSV.

run_experiment.sh writes one raw output file per (trace, cache-size) pair,
named `<trace>__size_<fraction>.txt`. Each file holds one line per
algorithm, e.g.:

    trace.oracleGeneral oracleGeneral s3fifo cache size 1024, 987654 req, \
miss ratio 0.1234, byte miss ratio 0.1234

This script extracts (trace, algo, cache_fraction, num_req, miss_ratio)
and writes a single results.csv consumed by Analysis.ipynb.
"""
import csv
import os
import re
import sys

# Captures: <algo> cache size <N>, <nreq> req, miss ratio <mr>
LINE_RE = re.compile(
    r"\b([A-Za-z0-9][A-Za-z0-9_.+-]*)\s+cache size\s+([\d.eE+]+)\s*,\s*"
    r"(\d+)\s+req\s*,\s*miss ratio\s+([\d.]+)"
)
FNAME_RE = re.compile(r"^(?P<trace>.+)__size_(?P<frac>[\d.]+)\.txt$")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: parse_results.py <raw_dir> <out_csv>", file=sys.stderr)
        return 2

    raw_dir, out_csv = sys.argv[1], sys.argv[2]
    rows = []

    for fn in sorted(os.listdir(raw_dir)):
        m = FNAME_RE.match(fn)
        if not m:
            continue
        trace = m.group("trace")
        cache_fraction = float(m.group("frac"))

        with open(os.path.join(raw_dir, fn), encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                hit = LINE_RE.search(line)
                if not hit:
                    continue
                algo, _abs_size, nreq, mr = hit.groups()
                rows.append(
                    {
                        "trace": trace,
                        "algo": algo.lower(),
                        "cache_fraction": cache_fraction,
                        "num_req": int(nreq),
                        "miss_ratio": float(mr),
                    }
                )

    rows.sort(key=lambda r: (r["trace"], r["cache_fraction"], r["algo"]))
    with open(out_csv, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=["trace", "algo", "cache_fraction", "num_req", "miss_ratio"],
        )
        writer.writeheader()
        writer.writerows(rows)

    n_traces = len({r["trace"] for r in rows})
    n_algos = len({r["algo"] for r in rows})
    print(f"Parsed {len(rows)} rows ({n_traces} traces x {n_algos} algos) -> {out_csv}")
    if not rows:
        print("WARNING: no result rows parsed. Inspect the raw output files.",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
