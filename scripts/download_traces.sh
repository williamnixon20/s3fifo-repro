#!/usr/bin/env bash
#
# download_traces.sh - Fetch CloudPhysics cache traces for the S3FIFO experiment.
#
# Traces are downloaded over HTTP from the CMU PDL public mirror. They are in
# the `oracleGeneral` binary format that libCacheSim reads natively
# (zstd-compressed). The CloudPhysics dataset has 106 traces (w01..w106).
#
# Usage:
#   download_traces.sh [N] [BASE_URL] [DEST]
#     N         number of traces to download    (default: 100)
#     BASE_URL  HTTP directory of trace files    (default: CMU CloudPhysics)
#     DEST      local destination directory      (default: $HOME/traces)
#
# Environment overrides:
#   JOBS      number of parallel download workers (default: 8)

set -uo pipefail

N="${1:-100}"
BASE_URL="${2:-https://ftp.pdl.cmu.edu/pub/datasets/twemcacheWorkload/cacheDatasets/cloudphysics/}"
DEST="${3:-$HOME/traces}"
JOBS="${JOBS:-8}"

# Normalize: ensure exactly one trailing slash.
BASE_URL="${BASE_URL%/}/"

# Pick an available downloader.
if command -v wget >/dev/null 2>&1; then
    fetch()        { wget -q -O "$1" "$2"; }
    fetch_stdout() { wget -q -O -  "$1"; }
elif command -v curl >/dev/null 2>&1; then
    fetch()        { curl -fsSL -o "$1" "$2"; }
    fetch_stdout() { curl -fsSL      "$1"; }
else
    echo "ERROR: neither wget nor curl is installed. Run scripts/setup.sh first." >&2
    exit 1
fi

mkdir -p "$DEST"

# --- List traces by scraping the HTTP directory index ------------------
echo "Listing traces at ${BASE_URL} ..."
fetch_stdout "$BASE_URL" > /tmp/index.html 2>/tmp/index_err.txt
if [ ! -s /tmp/index.html ]; then
    echo "ERROR: could not fetch directory listing from ${BASE_URL}" >&2
    sed 's/^/  /' /tmp/index_err.txt >&2
    exit 1
fi

# grep exits 1 when nothing matches; tolerate that so we can report it below.
grep -oE 'w[0-9]+\.oracleGeneral\.bin\.zst' /tmp/index.html \
    | sort -u -V > /tmp/all_traces.txt || true

total=$(wc -l < /tmp/all_traces.txt)
echo "Found ${total} traces."

if [ "$total" -eq 0 ]; then
    echo "ERROR: no trace files found at ${BASE_URL}" >&2
    echo "Check the BASE_URL points at an HTTP directory of *.oracleGeneral.bin.zst files." >&2
    exit 1
fi

# --- Download the first N (in parallel) --------------------------------
head -n "$N" /tmp/all_traces.txt > /tmp/selected_traces.txt
want=$(wc -l < /tmp/selected_traces.txt)
echo "Downloading ${want} traces to ${DEST} with ${JOBS} parallel workers ..."

# Download one trace. Background jobs ('&') inherit this function and the
# DEST / BASE_URL / fetch definitions from the parent shell.
download_one() {
    local f="$1"
    if [ -s "${DEST}/${f}" ]; then
        echo "  ${f} (cached)"
        return 0
    fi
    if fetch "${DEST}/${f}" "${BASE_URL}${f}"; then
        echo "  ${f} (done)"
    else
        echo "  WARNING: failed to download ${f}"
        rm -f "${DEST}/${f}"
    fi
}

while read -r f; do
    download_one "$f" &
    # Throttle: keep at most JOBS workers running at once.
    while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do
        wait -n
    done
done < /tmp/selected_traces.txt
wait  # let the final batch finish

got=$(ls "$DEST" 2>/dev/null | wc -l)
echo "Done. ${DEST} now holds ${got} trace files."
if [ "$got" -lt "$want" ]; then
    echo "WARNING: expected ${want} traces but only ${got} are present." >&2
fi
