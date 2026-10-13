# Running Campaigns

> **Retired.** HFIM-client is replaced by `hfim run --on <server>` from hfim-core
> (phase R-4). Its scripts print the hfim command that replaces them and exit 2.
> Set up a Server and run a campaign there: hfim-docs, `guides/run-on-a-server.md`.
> The table of every old command and its replacement is in that guide.

`run.sh` does the whole pipeline in one command: upload the benchmark, build
it, run the golden reference, run the fault-injection campaign, then download
the results to your machine.

```bash
./run.sh benchmarks/mmult -n 20
```

Results land in `results/<campaign>/` locally. See [Results](results.md).

## CLI flags

The first argument is the benchmark directory. Everything after it is
forwarded to the server-side runner.

| Flag | Values | Default | Notes |
| --- | --- | --- | --- |
| `-n`, `--injections N` | integer | 20 | Number of fault injections |
| `--fault TYPE` | `register`, `memory` (+ gem5 targets) | `register` | What to corrupt |
| `--workers N` | integer | 1 | Parallel instances (throughput only) |
| `--arch ARCH` | `riscv64`, `aarch64` | `riscv64` | Target architecture |
| `--seed N` | integer | 42 | Fault-list PRNG seed |
| `--simulator SIM` | `qemu`, `gem5` | `qemu` | Backend simulator |

Most settings can also be put in the benchmark's `fim.yaml` so you do not
have to repeat them on the command line. CLI flags override `fim.yaml`.
See the [fim.yaml Reference](fim-yaml-reference.md).

### `--fault` targets

- `register` (default) - corrupt a CPU register bit. See
  [Register Injection](register-injection.md).
- `memory` - corrupt a byte in an address range or ELF section. See
  [Memory Injection](memory-injection.md).
- gem5-only targets (caches, DRAM, microarchitecture) exist for advanced
  studies and require `--simulator gem5`. See
  [Advanced (gem5) Targets](gem5-targets.md).

## Parallel runs

Single-process (default) runs injections one at a time. When some faults hang
to the timeout wall, those slow runs dominate the wall-clock. Use `--workers N`
to run N injections concurrently:

```bash
./run.sh benchmarks/mmult -n 100 --workers 8
```

Worker count changes throughput only - never the outcome distribution.

## Reproducibility

`--seed` controls the fault-list PRNG only: which register/address/bit is hit,
in what order. It does **not** seed the workload. A benchmark whose own runtime
is non-deterministic (for example, one driven by an unseeded external
simulator) can produce a different instruction timeline run-to-run even at the
same seed. For such benchmarks, set a fixed `timeout` in `fim.yaml` rather than
relying on a golden-derived one. See [Serial Feeder](serial-feeder.md).

## See also

- [Writing Benchmarks](writing-benchmarks.md)
- [fim.yaml Reference](fim-yaml-reference.md)
- [Results](results.md)
