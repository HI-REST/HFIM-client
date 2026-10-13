# Batch Campaigns

> **Retired.** HFIM-client is replaced by `hfim run --on <server>` from hfim-core
> (phase R-4). Its scripts print the hfim command that replaces them and exit 2.
> Set up a Server and run a campaign there: hfim-docs, `guides/run-on-a-server.md`.
> The table of every old command and its replacement is in that guide.

A batch runs several campaigns from one YAML file instead of invoking `run.sh`
once per benchmark. Each campaign in the file inherits a shared `defaults:`
block and can override any field, so you describe a whole sweep (different
benchmarks, fault types, seeds, sections, architectures) in a single place.

```bash
./run.sh --batch campaign.yaml              # submit the batch, return
./run.sh --batch campaign.yaml --background # same (explicit alias)
```

`run.sh` uploads every benchmark the file references, then starts the batch on
the server fleet.

## The batch file

A batch file has two top-level keys: `defaults:` (applied to every campaign) and
`campaigns:` (the list, each entry overriding whatever it needs).

```yaml
defaults:
  arch: riscv64       # riscv64 or aarch64
  injections: 100     # fault injections per campaign
  fault: register     # register or memory (or a gem5 fault, see below)
  seed: 42            # PRNG seed for reproducibility
  # workers: 1        # parallel instances (default 1)
  # timeout: 60       # override the auto-calculated timeout (seconds)

campaigns:
  # inherits every default - a plain register campaign on mmult
  - benchmark: mmult

  # override just the injection count
  - benchmark: fibonacci
    injections: 50

  # same benchmark, different seed (a second independent draw)
  - benchmark: mmult
    seed: 99

  # memory faults into a named ELF section
  - benchmark: mmult
    fault: memory
    section: ".bss"

  # full custom: different arch, fault, section, count, and seed
  - benchmark: checksum
    arch: aarch64
    fault: memory
    section: ".data"
    injections: 200
    seed: 7
```

Each entry must name its `benchmark` (or inherit one from `defaults`). Any field
valid in a single campaign's `fim.yaml` can appear in `defaults:` or on an
entry - see the [fim.yaml Reference](fim-yaml-reference.md). The shipped
`campaign.yaml.example` has the full set of patterns.

### One fault type per entry

Give exactly one `fault:` per campaign; do not mix `register`/`memory`/cache
keys in a single entry. To sweep several fault types over one benchmark, write
one entry per type:

```yaml
campaigns:
  - benchmark: mmult
    fault: memory
    section: ".bss"
  - benchmark: mmult
    fault: memory
    section: ".data"
  - benchmark: mmult
    fault: register
    target_registers: auto
```

### gem5-only faults

Cache, DRAM, and microarchitectural faults need `simulator: gem5` on the entry
and use the same `fault:` key:

```yaml
campaigns:
  - benchmark: mmult
    simulator: gem5
    fault: cache_l1d
  - benchmark: mmult
    simulator: gem5
    fault: dram
```

See [gem5 Targets](gem5-targets.md) for the full fault list.

## Status and results

A batch is a [background job](background-jobs.md) like any other run: it submits
and returns, and each campaign in it shows up separately in `status.sh`.

```bash
./status.sh                # every campaign, batch or not
./status.sh --watch        # redraw until all are terminal
```

Download per campaign with `download.sh` (by id, unique prefix, or `--latest`),
exactly as for a single run:

```bash
./download.sh --latest
./download.sh <id> --full
```

When you run a batch in the foreground (no `--background`), `run.sh` downloads
the results for **only the benchmarks named in that batch** once they finish -
the server results directory is shared box-wide, so the download is scoped to
your own benchmarks rather than globbing everything.

## See also

- [Background Jobs](background-jobs.md) - the submit / status / download lifecycle
- [Running Campaigns](running-campaigns.md) - the run.sh pipeline and flags
- [Results](results.md) - outcome classes and what each result file contains
