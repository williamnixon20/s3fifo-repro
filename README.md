# Reproducing S3-FIFO on Chameleon Bare Metal

A reproducible [Chameleon](https://www.chameleoncloud.org/) / [Trovi](https://chameleoncloud.readthedocs.io/en/latest/technical/sharing/index.html)
artifact that reproduces the central result of the SOSP'23 paper
**"FIFO queues are all you need for cache evictions"** (Yang et al.):

> The **S3-FIFO** eviction policy achieves lower cache miss ratios than the
> widely used LRU and LFU policies, and also beats the more sophisticated
> ARC and LeCaR policies — using nothing but simple FIFO queues.

This artifact follows the
[Chameleon bare metal experiment pattern](https://github.com/ChameleonCloud/bare_metal_experiment_pattern):
provision a node, run the experiment, plot the results.

## What it does

1. **Node setup** — reserves a Chameleon bare metal node and builds
   [libCacheSim](https://github.com/1a1a11a/libCacheSim), a high-performance
   cache simulator.
2. **Experiment** — downloads **100 CloudPhysics block-I/O traces** from the
   open [cacheMon/cache_dataset](https://github.com/cacheMon/cache_dataset)
   corpus and simulates **LRU, LFU, ARC, LeCaR, and S3-FIFO** on each trace at
   three cache sizes (0.1%, 1%, 10% of the working set).
3. **Analysis** — plots the miss-ratio comparison across the 100 traces.

## Prerequisites

- An active Chameleon account with a project allocation.
- Run the notebooks from Chameleon's JupyterHub server.
- Estimated time: ~1.5 hours (mostly simulation).

## How to run

Open [`Experiment.ipynb`](Experiment.ipynb) and run the cells top to bottom.
The single notebook covers the whole pipeline — provision a node, install
libCacheSim, download 100 traces, run the experiment, retrieve `results.csv`,
and then analyze and **plot the S3-FIFO vs LRU/LFU/ARC/LeCaR comparison
inline**.

The analysis section works **without** a Chameleon allocation: if no real
results are present it falls back to [`results/sample_results.csv`](results/),
a 100-trace synthetic dataset shipped with the artifact, so the plots render
out of the box.

## Repository layout

```
s3fifo_repro/
├── Experiment.ipynb         # full pipeline: provision -> run -> plot
├── trovi.json               # Trovi artifact metadata
├── requirements.txt         # Python deps for the Jupyter side
├── scripts/
│   ├── setup.sh             # build libCacheSim + dependencies on the node
│   ├── download_traces.sh   # fetch 100 traces from the public S3 corpus
│   ├── run_experiment.sh    # simulate all 5 algorithms on every trace
│   ├── parse_results.py     # raw cachesim output -> results.csv
│   └── make_sample_data.py  # regenerate the sample dataset
└── results/
    ├── sample_results.csv   # 100-trace synthetic results (analysis fallback)
    └── fig*.png             # example figures produced by Analysis.ipynb
```

## Running the scripts directly (without Chameleon)

The `scripts/` directory is self-contained — you can reproduce the experiment
on any Linux box with Docker-free access to the trace corpus:

```bash
bash scripts/setup.sh                  # build libCacheSim
bash scripts/download_traces.sh 100    # fetch 100 CloudPhysics traces
bash scripts/run_experiment.sh         # -> out/results.csv
```

The analysis section of `Experiment.ipynb` picks up `out/results.csv`
automatically.

### Tuning the experiment

`run_experiment.sh` honors environment variables:

```bash
ALGOS="lru,lfu,arc,lecar,s3fifo,fifo,sieve" \
SIZES="0.001,0.01,0.1" \
bash scripts/run_experiment.sh
```

Use a different trace corpus by passing a dataset prefix to
`download_traces.sh` (e.g. `2020_twitter`, `2007_msr`); list available
datasets with
`aws s3 ls s3://cache-datasets/cache_dataset_oracleGeneral/ --no-sign-request`.

## Expected result

S3-FIFO attains the **lowest mean miss ratio**, reduces misses by roughly
15–20% relative to LRU, and has the lowest miss ratio on the large majority of
traces — with ARC and LeCaR in the middle and LRU/LFU last.

## References

- S3-FIFO paper / artifact: <https://github.com/Thesys-lab/sosp23-s3fifo>
- libCacheSim: <https://github.com/1a1a11a/libCacheSim>
- Cache trace corpus: <https://github.com/cacheMon/cache_dataset>
- Chameleon sharing / Trovi: <https://chameleoncloud.readthedocs.io/en/latest/technical/sharing/index.html>

## Support

For Chameleon platform issues, contact help@chameleoncloud.org.
