#!/usr/bin/env python3
"""Generate a sample results.csv so Analysis.ipynb runs without Chameleon.

The numbers are synthetic but follow the qualitative findings of the SOSP'23
S3-FIFO paper ("FIFO queues are all you need for cache evictions"): S3-FIFO
attains the lowest mean miss ratio, advanced policies (ARC, LeCaR) sit in the
middle, and LRU/LFU trail. Real runs replace this file via run_experiment.sh.
"""
import csv
import random

random.seed(20231023)  # S3-FIFO publication date - reproducible sample

N_TRACES = 100
SIZES = [0.001, 0.01, 0.1]

# Mean miss-ratio multiplier relative to LRU (1.0). Lower is better.
ALGO_QUALITY = {
    "lru": 1.000,
    "lfu": 0.985,
    "arc": 0.905,
    "lecar": 0.880,
    "s3fifo": 0.835,
}


def main() -> None:
    rows = []
    for t in range(1, N_TRACES + 1):
        trace = f"cphy_{t:03d}"
        num_req = random.randint(2_000_000, 40_000_000)
        # Per-trace base difficulty (cacheability varies a lot across traces).
        base_mr = random.uniform(0.18, 0.62)
        for size in SIZES:
            # Larger caches -> lower miss ratio (diminishing returns).
            size_factor = 0.30 + 0.70 * (0.1 / (size + 0.1)) ** 0.6
            for algo, quality in ALGO_QUALITY.items():
                noise = random.gauss(1.0, 0.05)
                mr = base_mr * size_factor * quality * noise
                mr = min(max(mr, 0.002), 0.95)
                rows.append(
                    {
                        "trace": trace,
                        "algo": algo,
                        "cache_fraction": size,
                        "num_req": num_req,
                        "miss_ratio": round(mr, 6),
                    }
                )

    rows.sort(key=lambda r: (r["trace"], r["cache_fraction"], r["algo"]))
    out = "results/sample_results.csv"
    with open(out, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=["trace", "algo", "cache_fraction", "num_req", "miss_ratio"],
        )
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} rows for {N_TRACES} traces -> {out}")


if __name__ == "__main__":
    main()
