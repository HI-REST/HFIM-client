# Background Jobs

> **Retired.** HFIM-client is replaced by `hfim run --on <server>` from hfim-core
> (phase R-4). Its scripts print the hfim command that replaces them and exit 2.
> Set up a Server and run a campaign there: hfim-docs, `guides/run-on-a-server.md`.
> The table of every old command and its replacement is in that guide.

Campaigns run on the server fleet, not on your machine. `run.sh` submits the
campaign and returns immediately - the run keeps going on the server after the
command exits and after you close your terminal. You check on it with
`status.sh` and pull the results later with `download.sh`.

## Run a campaign

```bash
./run.sh benchmarks/mmult -n 1000
```

This uploads the benchmark, builds it, runs the golden reference, submits the
campaign to your gateway + worker fleet, and returns. Nothing is downloaded
yet; the campaign is now running server-side.

`--background` is accepted as an explicit alias for this default behaviour, so
older scripts that pass it keep working:

```bash
./run.sh benchmarks/mmult -n 1000 --background   # same as the default
```

### Stream live instead (--follow)

If you want to watch a run to completion and download it automatically when it
finishes, use `--follow`:

```bash
./run.sh benchmarks/mmult -n 20 --follow
```

`--follow` blocks until the campaign is done, streams its output live, then
downloads the result tree for you. Use it for short runs; for long ones prefer
the default fire-and-forget plus `status.sh` / `download.sh`.

## Check status

`status.sh` lists every campaign you have on the server and its state (running,
queued, done, failed):

```bash
./status.sh
```

To poll until everything reaches a terminal state, use `--watch` (default 5s,
or pass an interval):

```bash
./status.sh --watch        # redraw every 5s, stop when all jobs are terminal
./status.sh --watch 10     # every 10s
```

`status.sh` is status-only. It never downloads or deletes anything, so it is
always safe to run (and to Ctrl-C - closing it does not affect the run).

## Download results

Downloading is a separate step, done with `download.sh`. You name WHICH campaign
to pull - an exact id, a unique prefix of one, or the most recent completed run:

```bash
./download.sh fibonacci_riscv64_20260602_131551_173700_314c55   # by id
./download.sh 314c55                                            # by unique prefix
./download.sh --latest                                          # most recent done
```

An ambiguous prefix (matching more than one campaign) is refused and the
candidates are listed, so you never download the wrong run. Use `status.sh` to
see the ids.

### About the campaign id

Ids look long because they are built to never collide:
`<benchmark>_<arch>_<date>_<time>_<micros>_<short-uuid>`, e.g.
`robot_arm_riscv64_20260605_183047_509126_57e7db`. You almost never type the
whole thing - any unique fragment works, so the trailing `57e7db` (or even
`robot_arm_riscv`) is enough as long as it matches exactly one run. When in
doubt, `--latest` grabs the most recent completed campaign with no id at all.

### Summary vs full

By default `download.sh` pulls a **summary**: enough to read the outcome without
the per-injection bulk.

```
results/<campaign>/
  injections.csv     # one row per injection
  report.tsv         # tab-separated report
  metadata.json      # campaign parameters, outcome tally, and target block (see Results)
  provenance.json    # what was run, with what tooling
  faultlist.json     # the fault list (reproducible from the seed)
  source/            # the benchmark as it was run
```

Add `--full` to also pull the per-injection tree - UART/register dumps, logs,
and any artefacts your feeder wrote (e.g. `trajectory.csv` for robot_arm):

```bash
./download.sh 314c55 --full
```

```
results/<campaign>/
  ... (summary files above) ...
  injections/
    0001/
      output.txt
      trajectory.csv     # per-injection artefact, if your feeder wrote one
    0002/
      ...
```

### Keeping or purging the server copy

The server copy is **kept** by default, so you can re-download. Pass `--purge`
to delete it from the server after a successful fetch:

```bash
./download.sh 314c55 --purge          # download summary, then remove server copy
./download.sh 314c55 --full --purge   # download everything, then remove it
```

## Batch campaigns

To run several campaigns from one YAML file instead of invoking `run.sh` per
benchmark, see [Batch Campaigns](batch-campaigns.md). A batch submits and
returns like any other background job, and each campaign in it shows up
separately in `status.sh`.

## See also

- [Batch Campaigns](batch-campaigns.md) - run a whole sweep from one YAML file
- [Running Campaigns](running-campaigns.md) - the run.sh pipeline and flags
- [Notifications](notifications.md) - get pinged when a run finishes
- [Results](results.md) - the outcome classes and what each file contains
