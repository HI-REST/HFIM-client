# HFIM Client

Write bare-metal benchmarks and run fault-injection campaigns on the FIM
server. This client uploads your benchmark, builds it, runs a golden reference,
injects faults, and downloads the results, all from one command.

```bash
./run.sh benchmarks/mmult -n 20
```

## Quick start

1. **[Set up](docs/setup.md)** your connection (`config.yaml` + SSH key).
2. **[Write a benchmark](docs/writing-benchmarks.md)** (`main.c` + `fim.yaml`),
   or copy `benchmarks/template`.
3. **[Run a campaign](docs/running-campaigns.md)** with `./run.sh`.
4. **[Read the results](docs/results.md)** in `results/<campaign>/`.

## Documentation

| Topic | What's in it |
| --- | --- |
| [Setup](docs/setup.md) | Connect the client to the server |
| [Writing Benchmarks](docs/writing-benchmarks.md) | `main.c` rules, the fault window, observables |
| [Running Campaigns](docs/running-campaigns.md) | `run.sh`, CLI flags, parallel workers, seeds |
| [Background Jobs](docs/background-jobs.md) | `--background`, `status.sh`, the submit/download lifecycle |
| [Batch Campaigns](docs/batch-campaigns.md) | Run a whole sweep from one YAML file |
| [Notifications](docs/notifications.md) | Telegram alerts when a background run finishes |
| [fim.yaml Reference](docs/fim-yaml-reference.md) | Every config field and its allowed values |
| [Register Injection](docs/register-injection.md) | Register sets, the float-register gotcha |
| [Memory Injection](docs/memory-injection.md) | Address ranges and ELF-section targeting |
| [Serial Feeder](docs/serial-feeder.md) | External simulators, per-fault trajectory files |
| [Results](docs/results.md) | Output layout, outcome classes, `download.sh` |
| [Deterministic Campaigns](docs/deterministic-campaigns.md) | Reproducible timing, witnesses, lifecycle hooks, checkpoints |
| [Advanced (gem5) Targets](docs/gem5-targets.md) | Cache / DRAM / microarchitecture injection |

## Key rules (the short version)

- **`fim_init()` / `fim_exit(0)`** bracket the code under test, faults land
  only between them.
- **Observable outputs are file-scope `volatile`** and listed in `fim.yaml`.
- **No stdlib**: bare-metal, you get `<stdint.h>` and the FIM SDK.
- **Float-heavy code?** Override `target_registers` to include `fa*`/`fs*`/`ft*`,
  or nearly everything reports MASKED. See
  [Register Injection](docs/register-injection.md).
- **Benchmark talks to an external simulator?** Use `injection_mode: breakpoint`
  plus `injection_pc_exclude` on the UART wait loop, or your campaign is not
  reproducible: absolute instruction counts drift with how fast the host
  started the simulator. See
  [Deterministic Campaigns](docs/deterministic-campaigns.md).
- **Scripts called from hooks/coprocess must live inside the benchmark
  directory** and be referenced with `{benchmark_dir}`. That directory is what
  gets uploaded; anything outside it never reaches the server.

## Outcomes

| Outcome | Meaning |
| --- | --- |
| **MASKED** | Fault had no observable effect |
| **SDC** | Silent Data Corruption: wrong result, undetected |
| **DETECTED** | The benchmark's own checks caught it |
| **CRASH** | Program crashed |
| **TIMEOUT** | Exceeded the time limit (often a fault-induced hang) |

## Project layout

```
config.yaml            your server connection (from config.yaml.example)
run.sh                 upload + build + golden + run a campaign
status.sh              check running campaigns (status-only, --watch to poll)
download.sh            pull a finished campaign (and golden, with --with-golden)
build.sh               local cross-compile (optional; the server builds on run)
campaign.yaml.example  example batch campaign
sdk/                   FIM SDK (don't modify)
benchmarks/            your benchmarks (start from template/)
results/               downloaded campaign results
golden/                downloaded golden references
docs/                  this documentation
```

## Citation

If you use HFIM in academic work, please cite it. Machine-readable metadata
lives in `CITATION.cff` (GitHub renders a "Cite this repository" button from
it). BibTeX:

```bibtex
@software{hfim,
  title   = {{HFIM: Hardware Fault Injection Manager}},
  author  = {Cuenca-Asensi, S. and Abma-Romero, E. and Serrano-Cases, A.},
  year    = {2026},
  url     = {https://github.com/HI-REST/HFIM-client},
  version = {0.1.0},
  note    = {Universidad de Alicante}
}
```
