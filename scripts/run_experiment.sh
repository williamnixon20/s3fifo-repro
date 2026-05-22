#!/usr/bin/env bash
#
# run_experiment.sh - Run the S3FIFO cache-eviction comparison.
#
# For every downloaded trace, simulate each eviction algorithm at each cache
# size with libCacheSim's `cachesim`, parse the miss ratios into results.csv,
# and (on Chameleon) upload the CSV to the object store so the Jupyter server
# can retrieve it.
#
# Usage:
#   run_experiment.sh [TRACE_DIR]
#
# Environment overrides:
#   CACHESIM  path to the cachesim binary
#   ALGOS     comma-separated eviction algorithms
#   SIZES     comma-separated cache sizes as a fraction of the working set

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TRACE_DIR="${1:-$HOME/traces}"
CACHESIM="${CACHESIM:-$HOME/libCacheSim/_build/bin/cachesim}"
ALGOS="${ALGOS:-lru,lfu,arc,lecar,s3fifo}"
SIZES="${SIZES:-0.001,0.01,0.1}"
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

mapfile -t TRACES < <(ls "$TRACE_DIR" 2>/dev/null)
N=${#TRACES[@]}
if [ "$N" -eq 0 ]; then
    echo "ERROR: no traces in $TRACE_DIR. Run scripts/download_traces.sh first." >&2
    exit 1
fi

IFS=',' read -ra SIZE_ARR <<< "$SIZES"

echo "=============================================="
echo " S3FIFO reproduction - running experiment"
echo "   traces      : $N  (in $TRACE_DIR)"
echo "   algorithms  : $ALGOS"
echo "   cache sizes : $SIZES  (fraction of working set)"
echo "=============================================="

start=$(date +%s)
i=0
for t in "${TRACES[@]}"; do
    i=$((i + 1))
    # Strip extensions (e.g. .oracleGeneral.zst) for a clean trace label.
    base="${t%%.*}"
    echo "[${i}/${N}] ${t}"
    for s in "${SIZE_ARR[@]}"; do
        out="${RAW_DIR}/${base}__size_${s}.txt"
        "$CACHESIM" "${TRACE_DIR}/${t}" "$TRACE_TYPE" "$ALGOS" "$s" \
            --ignore-obj-size 1 > "$out" 2>&1 \
            || echo "   WARNING: cachesim failed on ${t} @ size ${s}"
    done
done
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
