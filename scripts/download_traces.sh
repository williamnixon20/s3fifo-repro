#!/usr/bin/env bash
#
# download_traces.sh - Fetch cache traces for the S3FIFO experiment.
#
# Traces come from the open cacheMon/cache_dataset corpus hosted on a public
# S3 bucket (no credentials needed). By default we pull 100 CloudPhysics
# block-I/O traces in the `oracleGeneral` binary format that libCacheSim reads
# natively (zstd-compressed).
#
# Usage:
#   download_traces.sh [N] [DATASET] [DEST]
#     N        number of traces to download   (default: 100)
#     DATASET  S3 prefix under the bucket      (default: 2015_cloudPhysics)
#     DEST     local destination directory     (default: $HOME/traces)

set -euo pipefail

N="${1:-100}"
DATASET="${2:-2015_cloudPhysics}"
DEST="${3:-$HOME/traces}"

BUCKET="s3://cache-datasets"
PREFIX="cache_dataset_oracleGeneral/${DATASET}"

mkdir -p "$DEST"

echo "Listing traces under ${BUCKET}/${PREFIX}/ ..."
aws s3 ls "${BUCKET}/${PREFIX}/" --no-sign-request \
    | awk '{print $NF}' \
    | grep -E '\.(zst|oracleGeneral)$' \
    | sort > /tmp/all_traces.txt

total=$(wc -l < /tmp/all_traces.txt)
echo "Found ${total} traces in dataset '${DATASET}'."

if [ "$total" -eq 0 ]; then
    echo "ERROR: no traces found. Check the DATASET prefix." >&2
    echo "List available datasets with:" >&2
    echo "  aws s3 ls ${BUCKET}/cache_dataset_oracleGeneral/ --no-sign-request" >&2
    exit 1
fi

head -n "$N" /tmp/all_traces.txt > /tmp/selected_traces.txt
echo "Downloading $(wc -l < /tmp/selected_traces.txt) traces to ${DEST} ..."

i=0
while read -r f; do
    i=$((i + 1))
    if [ -f "${DEST}/${f}" ]; then
        echo "[${i}/${N}] ${f} (cached)"
    else
        echo "[${i}/${N}] ${f}"
        aws s3 cp "${BUCKET}/${PREFIX}/${f}" "${DEST}/${f}" \
            --no-sign-request --quiet
    fi
done < /tmp/selected_traces.txt

echo "Done. ${DEST} now holds $(ls "$DEST" | wc -l) trace files."
