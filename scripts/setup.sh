#!/usr/bin/env bash
#
# setup.sh - Install build dependencies and compile libCacheSim on the node.
#
# This is run once on a freshly provisioned Chameleon bare metal node
# (Ubuntu 22.04). It mirrors the upstream libCacheSim build instructions.

set -euo pipefail

echo "=============================================="
echo " S3FIFO reproduction - environment setup"
echo "=============================================="
set -x

# --- System packages ---------------------------------------------------
sudo apt-get update -yqq
sudo apt-get install -yqq \
    build-essential cmake ninja-build pkg-config git unzip \
    libglib2.0-dev libzstd-dev \
    google-perftools libgoogle-perftools-dev \
    python3-pip python3-swiftclient wget curl

pip3 install --quiet --upgrade pandas matplotlib seaborn

# --- Build libCacheSim --------------------------------------------------
cd "$HOME"
if [ ! -d "$HOME/libCacheSim" ]; then
    git clone https://github.com/1a1a11a/libCacheSim.git
fi

cd "$HOME/libCacheSim"
mkdir -p _build
cd _build
cmake -G Ninja ..
ninja
sudo ninja install || true   # install is optional; we use the in-tree binary

set +x
CACHESIM="$HOME/libCacheSim/_build/bin/cachesim"
if [ -x "$CACHESIM" ]; then
    echo "=============================================="
    echo " Setup complete."
    echo " cachesim binary: $CACHESIM"
    "$CACHESIM" --help 2>&1 | head -n 3 || true
    echo "=============================================="
else
    echo "ERROR: cachesim binary was not produced at $CACHESIM" >&2
    exit 1
fi
