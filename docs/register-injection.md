# Register Injection

> **Retired.** HFIM-client is replaced by `hfim run --on <server>` from hfim-core
> (phase R-4). Its scripts print the hfim command that replaces them and exit 2.
> Set up a Server and run a campaign there: hfim-docs, `guides/run-on-a-server.md`.
> The table of every old command and its replacement is in that guide.

Register injection flips bits in CPU registers during the fault window. It is
the default target, so `--fault register` is implied unless you say otherwise.

## The default register set (and why it can hide bugs)

If you do **not** set `target_registers`, FIM uses an integer-only default set.

**RISC-V64 default:** `a0`-`a7`, `s0`-`s11`, `t0`-`t6` (computation registers
only, no float and no control/pointer registers). This is the fallback when you
set neither `target_registers` nor `auto_registers`; autodetect casts a wider
net (see [Autodetect](#autodetect-auto_registers-true) below).

This matters: **for float-heavy code, the default set will report mostly
MASKED.** A PID controller, a DSP kernel, or anything doing real arithmetic
keeps its live values in the float registers (`fa*`, `fs*`, `ft*`). If you only
inject into integer registers, ~95% of faults land in idle registers and look
harmless - you miss the real SDCs. Override `target_registers` to include the
float ABI when your computation is floating-point.

## Selecting registers

List ABI names (recommended) or raw register numbers in `fim.yaml`:

```yaml
target_registers:
  # integer ABI - control flow, loop counters, addresses, integer math
  - a0
  - a1
  - s0
  - t0
  # float ABI - where floating-point math actually lives
  - fa0
  - fa1
  - fs0
  - ft0
```

## What if a register is listed but the code never uses it?

An explicit `target_registers` list is **not** cross-checked against the
disassembly. FIM only verifies each name is valid for the architecture; it does
not require the register to appear in your program. So if you list a register
the code never touches (say `s11` in a routine that only uses `s0`-`s2`), the
campaign **still runs normally** - it injects into that idle register, and
those injections almost always classify as **MASKED**, because the corrupted
value is never read back. Nothing errors and nothing is skipped. This is by
design: targeting an unused register is a valid (if low-yield) experiment, and
deciding what is "unused" is the study designer's call. If you want FIM to pick
only registers the program actually uses, that is exactly what autodetect
(below) is for.

The one thing that *is* rejected is a name that is not a valid register for the
architecture at all (a typo like `a99`), which fails fast at setup.

## Autodetect: `auto_registers: true`

Instead of hand-listing registers, let FIM read your ELF and target only the
registers the program actually uses. It disassembles the binary and keeps the
distinct ABI registers that appear:

```yaml
auto_registers: true     # autodetect the GPR pool from the ELF
include_int: true        # default true  - every integer GPR (a*, s*, t*, ra, sp, gp, tp, fp)
include_floats: false    # default false - fa*, fs*, ft*
```

The two booleans apply **only** to autodetect (they are ignored, with a
warning, if you give an explicit list and no `auto_registers`):

| `include_int` | `include_floats` | Pool |
| --- | --- | --- |
| true (default) | false (default) | integer registers the ELF uses |
| true | true | integer + float registers the ELF uses |
| false | true | only the float registers the ELF uses |
| false | false | rejected (selects nothing) |

Autodetect targets the **whole integer register file** - the computation
registers (`a*`, `s*`, `t*`) and the control/pointer registers (`ra`, `sp`,
`gp`, `tp`, `fp`) alike. Flipping `ra`/`sp` tends to CRASH rather than produce
an SDC, but that is your call as the study designer, not something the framework
decides for you. For float-heavy code, the cleanest fix to the masked-fault
problem above is `auto_registers: true` with `include_floats: true`. The number
of injections (`-n`) stays under your control; autodetect only chooses the
register pool, not the count.

> **Note:** `pc` is never part of the autodetect pool - it is not a GPR (see
> below). It only enters a campaign when you name it explicitly.

### Autodetect plus explicit extras

`auto_registers: true` and `target_registers` combine: the autodetected pool is
**unioned** with whatever you list. Use this to add a register autodetect would
never include on its own, most usefully `pc`:

```yaml
auto_registers: true     # the GPR pool the ELF uses
target_registers:        # ... plus these extras, merged in
  - pc
```

With no `target_registers`, the pool is used alone. With a list and no
`auto_registers`, only the list is used (the original explicit form).

> The legacy string form `target_registers: auto` still works but is
> deprecated - it prints a warning pointing you at `auto_registers: true`. The
> string was easy to misread as a register name; the boolean directive is not.

## Special registers: `pc`

`pc` (the program counter) is **not** a general-purpose register - it is not in
the `x0`-`x31` integer file, so it never appears in autodetect. You can still
target it by naming it explicitly:

```yaml
target_registers:
  - pc
```

Flipping `pc` rewrites *where* the program is executing, not a data value, so it
derails control flow: in practice it produces mostly **TIMEOUT** (and some
CRASH), rarely an SDC. Whether that is useful is, again, the study designer's
call. You can mix it with GPRs (`[a1, pc, t0]`) or union it onto the autodetect
pool (`auto_registers: true` + `target_registers: [pc]`).

## Valid RISC-V64 register names

**Integer (x1-x31; `x0` is hardwired zero and cannot be injected):**

| ABI name | x-number | Role |
| --- | --- | --- |
| `ra` | x1 | return address |
| `sp` | x2 | stack pointer |
| `gp` / `tp` | x3 / x4 | global / thread pointer |
| `t0`-`t2` | x5-x7 | temporaries |
| `s0`/`fp`, `s1` | x8, x9 | saved / frame pointer |
| `a0`-`a7` | x10-x17 | function args / return values |
| `s2`-`s11` | x18-x27 | saved registers |
| `t3`-`t6` | x28-x31 | temporaries |

**Float (f0-f31, with the D extension these are 64-bit doubles):**

| ABI name | f-number | Role |
| --- | --- | --- |
| `ft0`-`ft7` | f0-f7 | FP temporaries |
| `fs0`, `fs1` | f8, f9 | FP saved |
| `fa0`-`fa7` | f10-f17 | FP args / return values |
| `fs2`-`fs11` | f18-f27 | FP saved |
| `ft8`-`ft11` | f28-f31 | FP temporaries |

You may use the alias (`a0`) or the raw number (`x10` / `f10`) interchangeably.

**AArch64:** valid registers are `x0`-`x30` and `v0`-`v31` (`d0`-`d31` alias the
64-bit view); default set is `x0`-`x15`.

`bit_width` and `fault_model` apply here too - see the
[fim.yaml Reference](fim-yaml-reference.md).

## See also

- [Memory Injection](memory-injection.md)
- [fim.yaml Reference](fim-yaml-reference.md)
