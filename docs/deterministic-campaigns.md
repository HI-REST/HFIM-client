# Deterministic Campaigns

How to make a campaign reproducible: same seed in, same results out, row for
row. Written after the robot_arm determinism work (2026-08).

## The problem, in one example

A benchmark that talks to an external simulator (PyBullet, a sensor rig, a
network peer) waits for it in a UART loop. How many instructions that wait
burns depends on how fast the host started the other process **that day**.

Measured on robot_arm, three identical golden runs:

| What | Result |
| --- | --- |
| Trajectory files | byte-identical (the physics is deterministic) |
| Instructions spent waiting for the simulator | drifted **560172** between runs |
| Where one fixed instruction count landed | loop iteration 50, iteration 4, and past the end of the program |

So a campaign that names its injection instant by absolute instruction count
injects somewhere different every run. A historical faultlist of 128 fixed
counts produced 128 timeouts.

## The fix: name the instant by (instruction, Kth execution)

```yaml
injection_mode: breakpoint

injection_pc_exclude:
  - symbol: uart_getc      # the wait loop of YOUR benchmark
    offset_start: 0x4
    offset_end: 0xa
```

How many times an instruction executes is fixed by the program's control
flow, not by the wall clock, so "the 82nd execution of this instruction" is
the same moment on every run. K is drawn automatically from the golden run.

`injection_pc_exclude` removes the wait loop from the draw. Without it the
draw (weighted by execution count) lands on the spin almost every time: on
robot_arm the spin instructions run 203631 times versus 94 for the control
code.

**Result**: five full campaigns, byte-identical outcomes including the
corrupted trajectories of the SDC cases; n=100 run twice, identical; replay
from the emitted faultlist, identical.

## Proving it: witnesses

```yaml
observable_outputs:
  record_at_injection: true
  variables:
    - name: "loop_count"
      type: "int"
```

Writes `marker_readback.csv`: for every injection, what the program's own
variables held **at the instant the fault fired**. Rerunning and getting the
same file is proof from inside the program that the instant was the same,
not just a claim from the tool.

**Comparing two runs**: sort before diffing. Under the parallel fleet each
worker appends its rows when it finishes, so row ORDER reflects which
injection finished first, not the campaign. The content is what matters:

```bash
diff <(sort a/marker_readback.csv) <(sort b/marker_readback.csv)   # must be empty
```

Verified on the server (2026-08-30): two identical n=10 runs produced
byte-identical `injections.csv` and the same witness rows in a different
order.

## Analysing what actually happened: campaign_end hook

The injector's SDC verdict answers "did a variable change". For a robot that
is not the interesting question - the interesting question is "did the arm
still get where it was going".

```yaml
hooks:
  campaign_end: "python3 {benchmark_dir}/classify_trajectories.py {campaign_outdir} --golden {golden_dir}"
```

`classify_trajectories.py` ships with the robot_arm benchmark and writes
`trajectory_verdicts.csv` + `trajectory_summary.json`, classifying each
injection as `reached`, `wrong_pose`, `path_deviated`, `not_converged`,
`dead` (NaN) or `no_data`.

Why it matters, from the 4-target sweep (n=100 each, local rig):

| Target | SDC says | Trajectory says | Overstatement |
| --- | ---: | ---: | --- |
| `target_position` | 88% | 22% | 4.0x |
| `posicion` | 25% | 8% | 3.1x |
| `tau` | 21% | 2% | 10.5x |
| `loop_count` | 100% | **0%** | infinite |

`loop_count`: every single injection corrupted the observable, and every
single arm still reached its target. Reporting "100% SDC" for that variable
would be true and completely misleading.

## Reproducing the sweep

```bash
./run.sh --batch benchmarks/robot_arm/campaigns/sweep_4_targets.yaml
```

## Optional: snapshot restore

```yaml
checkpoint:
  anchor: fim_init
```

Restores the guest from a golden snapshot instead of booting it per
injection. The snapshot is sealed to the ELF's sha256, so recompiling
without regenerating the golden refuses to run rather than silently
executing the old code baked into the snapshot.

Not a speed feature: measured 9.1 s/injection versus 7.4 s for the plain
path on robot_arm. Use it for the sealing semantics.

## Full field reference

Every key, its default and its failure modes:
[fim.yaml Reference](fim-yaml-reference.md).
