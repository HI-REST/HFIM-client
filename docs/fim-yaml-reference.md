# fim.yaml Reference

`fim.yaml` lives in your benchmark directory and configures how FIM runs it.
Every field is optional except where noted. CLI flags to `run.sh` override the
matching `fim.yaml` value.

## Observable outputs (SDC detection)

How FIM decides whether a fault produced wrong output.

```yaml
observable_outputs:
  comparison: "exact"        # "exact" | "tolerance"
  variables:
    - name: "result"         # variable name - type auto-detected from the ELF
    - name: "total"
    - name: "position"
      tolerance: 0.001       # per-variable, only used with comparison: tolerance
```

- `comparison: exact` - bit-exact match against the golden values.
- `comparison: tolerance` - numeric match within `tolerance` (use for floats,
  where bit-exact is too strict). Set `tolerance` per variable.

Observables must be file-scope `volatile` variables in your `main.c`. Without
an `observable_outputs` block, FIM falls back to comparing raw UART output,
which is less precise.

## Fault target

Which kind of state to corrupt. Default is `register`.

```yaml
fault: register            # or: memory (or a gem5-only target)
```

One campaign injects one fault type. Keys belong to fault families
(register / memory / cache), and FIM rejects a config that mixes keys from
different families - e.g. `fault: register` with a `memory_start` set is an
error. To sweep several fault types, use a
[batch campaign](batch-campaigns.md) with one entry per type.

### Register target

```yaml
fault: register
target_registers:          # a list of register names (or set auto_registers)
  - a0
  - fa0
  - pc                     # pc is allowed explicitly (not a GPR; never autodetected)
bit_width: 64              # 8 | 16 | 32 | 64 (default 32)
```

Or autodetect the registers the ELF actually uses:

```yaml
fault: register
auto_registers: true       # autodetect the GPR pool from the ELF
include_int: true          # default true  - integer GPRs (applies only to autodetect)
include_floats: false      # default false - float registers (applies only to autodetect)
target_registers:          # optional: extras unioned onto the autodetected pool
  - pc
```

`target_registers` is required unless `auto_registers: true` is set. The legacy
`target_registers: auto` string still works but is deprecated in favor of
`auto_registers: true`.

Full register list, the autodetect truth table, `pc` behavior, and the
float-register gotcha: [Register Injection](register-injection.md).

### Memory target

Easiest: name a whole ELF section with `section:` and FIM resolves the
address range from your ELF automatically.

```yaml
fault: memory
section: .bss              # .bss, .data, .rodata, .stack, ...
memory_access_size: 4      # 1 | 2 | 4 | 8 bytes (default 4)
bit_width: 8               # 8 | 16 | 32 | 64 (default 32)
```

`section: .stack` is special-cased for bare-metal C906 ELFs (resolved from the
linker's `__stack_bottom`/`__stack_top` symbols). See
[Memory Injection](memory-injection.md).

Or name a single global/`static` variable - address and size both come from
the ELF symbol table, so you never set the size:

```yaml
fault: memory
target_variable: "target_position"  # global or function-static; size from st_size
memory_access_size: 4
```

Or give an explicit address range (use one targeting mode, not several -
`target_variable` takes precedence over `section`/`memory_start`):

```yaml
fault: memory
memory_start: "0x80001000"  # section name, hex string, or int
memory_end:   "0x80002000"  # must be greater than memory_start
```

Details and the targeting-mode matrix: [Memory Injection](memory-injection.md).

### gem5-only targets

Cache, DRAM, and microarchitecture targets use the same `fault:` key and
run with `--simulator gem5`, e.g. `fault: cache_l1d`. See
[gem5 Targets](gem5-targets.md).

## Fault model

```yaml
fault_model: single_bit_flip   # single_bit_flip | stuck_at_0 | stuck_at_1
```

- `single_bit_flip` - one bit toggles (models a Single Event Upset).
- `stuck_at_0` / `stuck_at_1` - a bit is forced to a fixed value.

## Timing

```yaml
timeout: 120               # fixed max seconds per injection
timeout_factor: 1.5        # used only when timeout is "auto"
checkpoint_locations:      # function name for the simulator snapshot
  - "fim_init"             # (default: main)
```

- A numeric `timeout` is a fixed wall - best for benchmarks with a variable
  runtime (e.g. feeder-driven ones).
- `timeout: auto` derives the wall from the golden run:
  `timeout_factor * golden_execution_time`, floored at 30s. Use only when the
  golden run is deterministic and recorded a golden time.

## Injection timing + window

```yaml
injection_mode: breakpoint   # breakpoint | timer | icount | stepi (default: timer)
```

For random campaigns the fault's location is drawn from the
`[fim_init, fim_exit)` instruction window - the SDK markers you already place
around the code under test. There is no separate window field: instrument the
benchmark, and the window follows.

- `breakpoint` (recommended, feeder-robust): a GDB breakpoint at the drawn PC.
  The CPU stops exactly when it executes that instruction. Reliable for
  serial-feeder benchmarks where instruction counts drift with feeder wall-time.
- `timer` (default): continue for a scaled duration, then interrupt. Fast but
  imprecise about which instruction is hit.
- `icount`: a TCG plugin pauses at the Nth committed instruction. Deterministic,
  but fragile for feeder benchmarks (the count moves with feeder timing).
- `stepi`: single-step to the target. Deterministic but slow over the network.

### Hit-instance (loop-iteration spread)

When the code under test is a loop inside the window, a plain breakpoint fires
on the FIRST time the PC executes - always iteration 1. To spread injections
across the loop's iterations, breakpoint mode draws a random **hit-instance**
`K` per injection from `[0, window_hit_count)` and arms the breakpoint with a
GDB ignore-count of `K`, so it fires on the `(K+1)`th hit.

- `window_hit_count` is the loop trip count, harvested from the golden run's
  `trace.json`. You do not set it.
- When the golden run did not measure it (`window_hit_count` absent or `0`),
  `K` degrades to `0` (first hit) - i.e. exactly the legacy behaviour. No error.
- `K` is recorded per injection in the faultlist / `injections.csv`
  (`hit_instance` column) so a campaign replays deterministically. Old
  faultlists with no such column load as `K=0`.

## Serial feeder (external simulator)

```yaml
serial_pty: true
serial_feeder_cmd: "python3 {benchmark_dir}/feeder.py --pty {pty} --trajectory-log {injection_outdir}/trajectory.csv"
```

Placeholders and per-fault output files: [Serial Feeder](serial-feeder.md).

## Result saving

```yaml
results:
  save_per_injection: true     # write a per-injection dir (needed for feeder artefacts)
  save_uart_output: true       # capture UART per injection
  save_observable_state: true  # dump observable values per injection
  save_register_dump: false    # dump all registers per injection
  cleanup_injections: false    # delete injections/ after the campaign
```


## Deterministic injection timing (recommended for feeder benchmarks)

Default behaviour without these keys is unchanged. They exist because a
benchmark that talks to an external simulator (see *Serial feeder*) has one
part whose instruction count is NOT reproducible: the UART wait loop. How
long the firmware spins there depends on how fast the host started Python
that day. Anything that names an injection instant by absolute instruction
count therefore points at a different place on every run.

Measured on robot_arm: the pre-handshake wait alone drifted 560172
instructions between three identical runs, and one fixed icount landed on
loop iteration 50, on iteration 4, and past the end of the program.

### injection_pc_exclude

```yaml
injection_mode: breakpoint     # required for this key to have any effect

injection_pc_exclude:
  # form 1: symbol + offsets (survives recompilation, recommended)
  - symbol: uart_getc
    offset_start: 0x4          # the 3-instruction RX spin body
    offset_end: 0xa
  # form 2: whole function (uses the symbol size from the ELF)
  - symbol: some_wait_helper
  # form 3: raw address range (breaks on recompile, warns at setup)
  - "0x800001be-0x800001c4"
```

- **Default: absent** - the PC draw is unchanged, byte for byte.
- What it does: removes those addresses from the pool the campaign draws
  injection points from. In breakpoint mode the draw is weighted by how many
  times each instruction ran in the golden, so the UART spin (203631 hits in
  robot_arm, versus 94 for real control code) wins essentially every draw
  unless excluded.
- Entries are a list; a PC is excluded if it falls in **any** of them.
- Errors abort at setup: a symbol that does not exist, a reversed range, or
  an exclusion that would empty the whole draw pool.
- No effect (with a warning) in `injection_mode: icount`/`timer`, or on the
  gem5 backend.
- An explicitly named PC always wins: `inject_at_symbol` / `inject_at_addr`
  and faultlist replay rows are never blocked by this list (a warning notes
  the overlap).

### Where the instant comes from

With `injection_mode: breakpoint` the injection instant is a pair
**(instruction address, Kth execution)** - a coordinate the wall clock
cannot move, because how many times an instruction runs is fixed by the
program's control flow. K is drawn automatically from the golden's per-PC
hit count; you do not set it by hand.

## record_at_injection (witnesses)

Photographs the observable variables **at the moment the fault fires**, on
top of the end-of-run comparison that decides SDC.

```yaml
observable_outputs:
  comparison: "exact"
  record_at_injection: true    # default: false
  variables:
    - name: "tau"
      type: "float[4]"
    - name: "loop_count"
      type: "int"
    - name: "debug_flag"
      type: "int"
      compare: false           # witness only: never counts toward SDC
    - name: "big_buffer"
      type: "int[256]"
      record_at_injection: false   # compared at the end, not photographed
```

- **Default: false** - no file is written and nothing extra is read.
- Output: `marker_readback.csv` in the campaign directory, one row per
  variable per injection:
  `format,symbol,pc,hit_instance,size,size_source,truncated,raw_hex,value,typed_value`
- `raw_hex` is the authoritative record (byte identity across reruns is the
  determinism proof); `value` renders 1/2/4/8-byte integers; `typed_value`
  renders arrays and floats using the declared or DWARF type.
- Size is read from the ELF automatically (arrays included), capped at 64
  bytes with a `truncated` flag.
- Per-variable overrides use the **same key name** at variable level, plus
  `compare: false` for witness-only variables.
- Why it matters: it is the independent proof that a rerun hit the same
  instant. The program's own counter (e.g. `loop_count`) says which
  iteration it was in when the fault landed.

## type: is now optional

```yaml
observable_outputs:
  variables:
    - name: "tau"              # no type: needed
    - name: "result"
      type: "float[4]"         # still allowed, and now a CONTRACT
```

- **Default when omitted**: size comes from the ELF symbol table, and the
  type for reporting comes from DWARF debug info if the binary has it
  (benchmarks built by the FIM SDK always do). Without DWARF the value is
  reported as hex.
- The SDC verdict is a **byte comparison** either way, so an untyped
  observable is never less correct - only less readable.
- Declaring a type buys you a contract: if the declared size does not match
  what the ELF says, the campaign aborts at setup instead of misreading
  memory. Useful to catch a stale config after editing the benchmark.
- Tolerance comparison still requires a type (bytes cannot express an
  epsilon).

## Campaign lifecycle: hooks and coprocess

Commands FIM runs around the campaign. Everything the commands invoke must
live **inside the benchmark directory**, because that is what gets uploaded
to the server; reference it with `{benchmark_dir}`.

```yaml
hooks:
  campaign_start:  "sh {benchmark_dir}/prepare.sh {campaign_outdir}"
  injection_start: "sh {benchmark_dir}/before.sh {injection_id}"
  injection_end:   "sh {benchmark_dir}/after.sh {injection_id} {outcome}"
  campaign_end:    "python3 {benchmark_dir}/classify.py {campaign_outdir} --golden {golden_dir}"

coprocess:
  campaign:  "python3 {benchmark_dir}/sim.py --persist"   # one process, whole campaign
  injection: "python3 {benchmark_dir}/sim.py --pty {pty}" # one per injection
```

- **Default: all absent** - no hooks run, no coprocess is spawned.
- **Hooks** run to completion (blocking). `campaign_start`/`campaign_end`
  failing aborts the campaign; `injection_start`/`injection_end` failing
  marks that one injection `infrastructure_failure` and the campaign goes on.
  Per-hook timeout: `hook_timeout: 60` (seconds).
- **coprocess.injection** is the same slot as `serial_feeder_cmd`, which
  remains supported as its alias. Do not set both.
- **coprocess.campaign** is a supervised process that lives for the whole
  campaign and speaks a line protocol on stdin/stdout:

  ```
  FIM -> coprocess:  CAMPAIGN_START <campaign_outdir>
  FIM -> coprocess:  INJECTION_START <id> <injection_outdir> <pty>
  coprocess -> FIM:  READY            <- required before FIM proceeds
  FIM -> coprocess:  INJECTION_END <id> <outcome>
  FIM -> coprocess:  CAMPAIGN_END
  ```

  Your process **must flush** after writing READY (a line stuck in a block
  buffer looks like a hang). `ready_timeout: 120` sets the wait. FIM does not
  restart a dead coprocess: use a self-restarting wrapper if you want that.
- Placeholders per scope: campaign scope has `{campaign_id}`
  `{campaign_outdir}` `{benchmark}` `{benchmark_dir}` `{elf}` `{seed}`
  `{num_injections}` `{golden_dir}`; injection scope adds `{injection_id}`
  `{injection_outdir}` `{pty}`; `injection_end` adds `{outcome}`;
  `campaign_end` adds `{injections_csv}`. Using one outside its scope aborts
  at setup. The same values are exported as `FIM_*` environment variables.
- Not supported under `--workers N` (parallel): the keys are ignored with a
  warning.

## checkpoint (snapshot restore)

Restores the guest from a snapshot taken during the golden run instead of
booting it for every injection.

```yaml
checkpoint:
  anchor: fim_init          # recommended: the marker your benchmark already has
  # anchor: {symbol: main, offset: 0x50}
  # anchor: "0x800002a4"    # raw address, warns (breaks on recompile)
  restore: per_injection    # the only value in v1
  recycle_every: 0          # 0 = never recycle the QEMU/coprocess pair
```

- **Default: absent** - a fresh QEMU per injection, exactly as before.
- Requires `injection_mode: breakpoint`; rejects icount/timer and the gem5
  backend at setup.
- The anchor must be a point where **all external startup input has been
  consumed**. `fim_init` satisfies this when your benchmark calls it after
  the handshake with the feeder. If it does not, the first injection
  deadlocks and the campaign aborts at injection 1 naming this contract.
- With `serial_pty`, FIM verifies before every snapshot that the UART is
  quiet (nothing unread in the receive FIFO, transmitter idle) and aborts
  with a diagnostic if data arrived early - a snapshot taken mid-exchange
  would replay those bytes on every restore.
- The snapshot is **sealed to the ELF sha256**. Recompile the benchmark
  without regenerating the golden and the campaign refuses to start, instead
  of silently running the old code that lives inside the snapshot.
- Speed note, measured on robot_arm: this is not a speed feature. Warm
  restore measured 9.1 s/injection versus 7.4 s for the plain path, because
  what it removes (the guest's startup spin) never cost wall-clock time to
  begin with. Use it for the sealing and snapshot semantics, not to go
  faster.

## Quick reference: valid values

| Field | Allowed values |
| --- | --- |
| `comparison` | `exact`, `tolerance` |
| `fault_model` | `single_bit_flip`, `stuck_at_0`, `stuck_at_1` |
| `bit_width` | `8`, `16`, `32`, `64` |
| `injection_mode` | `breakpoint`, `timer`, `icount`, `stepi` |
| `memory_access_size` | `1`, `2`, `4`, `8` |
| `target_variable` | any global/`static` data symbol name (memory faults only) |
| `fault` | `register`, `memory`, `cache_l1d`, `cache_l1i`, `cache_l2`, `dram`, ... (gem5 targets in [gem5 Targets](gem5-targets.md)) |
| `record_at_injection` | `true`, `false` (group level and per variable) |
| `compare` | `false` (per variable: witness only, excluded from SDC) |
| `restore` | `per_injection` |
| `recycle_every` | any non-negative integer (`0` = never) |

## Defaults at a glance

What happens when you write nothing. Every row is the behaviour of a
`fim.yaml` that omits the key.

| Field | Default | Notes |
| --- | --- | --- |
| `fault` | `register` | |
| `fault_model` | `single_bit_flip` | |
| `injection_mode` | `timer` | `breakpoint` is what the deterministic clock needs |
| `memory_access_size` | `4` | bytes read-modify-written per memory injection. Use `1` to model a single-cell upset |
| `bit_width` | derived from the target | memory: `memory_access_size * 8`; registers: `64`. Setting it wider than the access aborts at setup |
| `seed` | `42` | `run.sh --seed N` overrides |
| `num_injections` | `20` | `run.sh -n N` overrides |
| `timeout` | golden time x1.5 | `injection_timeout: N` sets an exact per-injection cap instead |
| `type:` on observables | auto (ELF size + DWARF type) | declare it to get a size contract |
| `record_at_injection` | `false` | no witness file is written |
| `injection_pc_exclude` | absent | the PC draw is unchanged |
| `hooks` / `coprocess` | absent | nothing is spawned |
| `checkpoint` | absent | fresh QEMU per injection |
| `hook_timeout` | `60` s | per hook |
| `ready_timeout` | `120` s | coprocess READY wait |

## See also

- [Writing Benchmarks](writing-benchmarks.md)
- [Register Injection](register-injection.md)
- [Memory Injection](memory-injection.md)
- [Serial Feeder](serial-feeder.md)
