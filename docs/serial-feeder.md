# Serial Feeder (External Simulator)

> **Retired.** HFIM-client is replaced by `hfim run --on <server>` from hfim-core
> (phase R-4). Its scripts print the hfim command that replaces them and exit 2.
> Set up a Server and run a campaign there: hfim-docs, `guides/run-on-a-server.md`.
> The table of every old command and its replacement is in that guide.

Some benchmarks exchange data over UART with a host-side process (e.g. a robot
controller reading joint positions from a physics simulator). FIM launches that
"feeder" alongside the simulator and wires them together over a PTY.

## Enabling it

In the benchmark's `fim.yaml`:

```yaml
serial_pty: true
serial_feeder_cmd: "python3 {benchmark_dir}/feeder.py --pty {pty}"
```

- `serial_pty: true` tells the simulator to expose its serial port as a PTY.
- `serial_feeder_cmd` is the host-side process to start; it drives that PTY.

Add a `requirements.txt` to the benchmark for any Python dependencies - they
are installed on the server automatically.

## Placeholders

These tokens in `serial_feeder_cmd` are substituted at runtime:

| Placeholder | Substituted with |
| --- | --- |
| `{pty}` | the PTY path allocated for serial I/O |
| `{benchmark_dir}` | your benchmark's directory on the server |
| `{injection_outdir}` | the per-injection result directory (`results/<campaign>/injections/NNNN/`). During the golden run it expands to the golden dir instead. |

## Per-fault output files (trajectory / sensor logs)

Use `{injection_outdir}` when the feeder should write an artefact **for each
fault** - a trajectory log, a sensor trace, a debug dump. Anything the feeder
writes inside that directory travels back to you with the results.

```yaml
serial_pty: true
serial_feeder_cmd: "python3 {benchmark_dir}/pybullet_feeder.py
                    --pty {pty}
                    --trajectory-log {injection_outdir}/trajectory.csv"
```

This produces one `trajectory.csv` per injection at
`results/<campaign>/injections/NNNN/trajectory.csv`, each associated with the
fault that ran in that slot. Because the same placeholder maps to the golden
dir during the golden run, every campaign also produces a matching baseline
file you can diff a corrupted run against.

The file is written entirely by **your feeder** - FIM only supplies the path
and ships the result back. The feeder decides the format and which variables to
record; FIM does not need to know.

## Timeouts for feeder-driven benchmarks

A closed-loop benchmark blocks on serial reads waiting for the feeder. If the
feeder's own runtime is not deterministic (e.g. an unseeded physics engine),
the instruction count can vary run-to-run at the same seed. For these, set a
fixed `timeout` rather than relying on a golden-derived one:

```yaml
timeout: 120
```

## Minimal end-to-end example

```yaml
timeout: 120

observable_outputs:
  comparison: "exact"
  variables:
    - name: "tau"
    - name: "posicion"

serial_pty: true
serial_feeder_cmd: "python3 {benchmark_dir}/feeder.py --pty {pty} --trajectory-log {injection_outdir}/trajectory.csv"
```

## See also

- [Results](results.md) - how per-injection files come back
- [fim.yaml Reference](fim-yaml-reference.md)
