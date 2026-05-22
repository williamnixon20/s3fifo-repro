#!/usr/bin/env bash
#
# run_experiment.sh - Run the S3FIFO cache-eviction comparison.
#
# Simulates each eviction algorithm at each cache size with libCacheSim's
# `cachesim` on the smallest MAX_TRACES traces (shortest first), parses the
# miss ratios into results.csv, and (on Chameleon) uploads the CSV to the
# object store so the Jupyter server can retrieve it.
#
# Traces are simulated PARALLEL at a time.
#
# Usage:
#   run_experiment.sh [TRACE_DIR]
#
# Environment overrides:
#   CACHESIM    path to the cachesim binary
#   ALGOS       comma-separated eviction algorithms
#   SIZES       comma-separated cache sizes as a fraction of the working set
#   MAX_TRACES  number of traces to simulate, smallest first (default: 50)
#   PARALLEL    number of traces simulated concurrently     (default: 10)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TRACE_DIR="${1:-$HOME/traces}"
CACHESIM="${CACHESIM:-$HOME/libCacheSim/_build/bin/cachesim}"
ALGOS="${ALGOS:-lru,lfu,arc,lecar,s3fifo}"
SIZES="${SIZES:-0.01,0.1}"
MAX_TRACES="${MAX_TRACES:-50}"
PARALLEL="${PARALLEL:-10}"
TRACE_TYPE="oracleGeneral"

OUT_DIR="./out"
RAW_DIR="${OUT_DIR}/raw"

if [ ! -x "$CACHESIM" ]; then
    echo "ERROR: cachesim binary not found at $CACHESIM" >&2
    echo "Run scripts/setup.sh first." >&2
    exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$RAW_DIR"

# Select the smallest MAX_TRACES trace files, ordered shortest-first, so the
# quickest simulations finish first ('ls -S' sorts by size, '-r' ascending).
mapfile -t TRACES < <(ls -1Sr "$TRACE_DIR" 2>/dev/null | head -n "$MAX_TRACES")
N=${#TRACES[@]}
if [ "$N" -eq 0 ]; then
    echo "ERROR: no traces in $TRACE_DIR. Run scripts/download_traces.sh first." >&2
    exit 1
fi
available=$(ls -1 "$TRACE_DIR" 2>/dev/null | wc -l)

IFS=',' read -ra SIZE_ARR <<< "$SIZES"

echo "=============================================="
echo " S3FIFO reproduction - running experiment"
echo "   traces      : $N  (smallest first, of $available in $TRACE_DIR)"
echo "   algorithms  : $ALGOS"
echo "   cache sizes : $SIZES  (fraction of working set)"
echo "   parallelism : $PARALLEL traces at a time"
echo "=============================================="

# Simulate one trace at every cache size. Background jobs ('&') inherit this
# function and the variables / SIZE_ARR below from the parent shell.
run_trace() {
    local idx="$1" t="$2"
    local base="${t%%.*}"   # strip .oracleGeneral.bin.zst -> clean label
    local s out
    for s in "${SIZE_ARR[@]}"; do
        out="${RAW_DIR}/${base}__size_${s}.txt"
        if ! "$CACHESIM" "${TRACE_DIR}/${t}" "$TRACE_TYPE" "$ALGOS" "$s" \
                --ignore-obj-size 1 > "$out" 2>&1; then
            echo "  [${idx}/${N}] WARNING: cachesim failed on ${t} @ size ${s}"
        fi
    done
    echo "  [${idx}/${N}] done ${t}"
}

start=$(date +%s)
i=0
for t in "${TRACES[@]}"; do
    i=$((i + 1))
    run_trace "$i" "$t" &
    # Throttle: keep at most PARALLEL simulations running at once.
    while [ "$(jobs -rp | wc -l)" -ge "$PARALLEL" ]; do
        wait -n
    done
done
wait  # let the final batch finish
end=$(date +%s)
echo "Simulations finished in $((end - start))s."

echo "Parsing raw output ..."
python3 "${SCRIPT_DIR}/parse_results.py" "$RAW_DIR" "${OUT_DIR}/results.csv"

# --- Upload to the Chameleon object store ------------------------------
# ~/openrc is placed on Chameleon nodes automatically; skipped off-platform.
if [ -f "$HOME/openrc" ]; then
    # shellcheck disable=SC1091
    source "$HOME/openrc"
    today=$(date '+%Y-%m-%d')
    bucket="s3fifo_repro_data_${today}"
    echo "Uploading results to object store container: ${bucket}"
    swift post "$bucket"
    swift upload "$bucket" "${OUT_DIR}/results.csv" --object-name results.csv
    echo "Upload complete."
else
    echo "No ~/openrc found - skipping object-store upload (results in ${OUT_DIR}/results.csv)."
fi

echo "Done."
