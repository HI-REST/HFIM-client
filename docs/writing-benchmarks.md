# Writing a Benchmark

> **Retired.** HFIM-client is replaced by `hfim run --on <server>` from hfim-core
> (phase R-4). Its scripts print the hfim command that replaces them and exit 2.
> Set up a Server and run a campaign there: hfim-docs, `guides/run-on-a-server.md`.
> The table of every old command and its replacement is in that guide.

A benchmark is a small bare-metal C program plus a `fim.yaml` describing how to
run it. Start from the template:

```bash
cp -r benchmarks/template benchmarks/my_algo
```

## main.c

```c
#include "hfim.h"

#define N 64

volatile int result[N];          /* observable output - file scope, volatile */

int main(void) {
    int input[N];
    for (int i = 0; i < N; i++) input[i] = i;   /* setup BEFORE the window */

    fim_init();                  /* fault injection window opens */

    for (int i = 0; i < N; i++) {
        result[i] = input[i] * input[i] + 1;     /* code under test */
    }

    fim_exit(0);                 /* fault injection window closes */
}
```

## The rules

1. **`fim_init()` / `fim_exit(0)` bracket the code under test.** In random
   injection the fault address is drawn from the `[fim_init, fim_exit)`
   instruction window - the two markers ARE the window, you do not declare it
   separately. Do all setup before `fim_init()`. If the code under test is a
   loop inside the window, breakpoint mode also spreads injections across the
   loop's iterations (see "hit-instance" in the
   [fim.yaml Reference](fim-yaml-reference.md)).

2. **Observable outputs are file-scope `volatile`.** FIM reads these to detect
   SDC. Declare them as `volatile int result[N]` at file scope, never as locals
   (locals live in registers/stack and are not reliably observable).

3. **List observables in `fim.yaml`.** Just the names - types are auto-detected
   from the ELF.

4. **No stdlib.** This is bare-metal. You get `<stdint.h>` and the FIM SDK.
   No `printf`, no `malloc`, no libc.

5. **Initialize before `fim_init()`.** Arrays, constants, and any I/O handshake
   belong before the window so a fault can't corrupt setup.

6. **`fim_breakpoint()` pins a punctual injection point (feeder benchmarks).**
   Place `fim_breakpoint();` on the line you want to fault. In breakpoint mode
   the campaign auto-detects it and stops the PC there - no `inject_at_symbol`
   needed. Use it when the `[fim_init, fim_exit)` window is unreliable: a
   serial-feeder benchmark spends most of the window in a UART spin loop whose
   per-PC execution count is not reproducible run-to-run, so a window draw lands
   on the spin instead of the code under test. The symbol address is
   recompile-stable, unlike a raw `main + 0xNN` byte offset. Benchmarks that do
   not call it keep using the window unchanged.

## fim.yaml (minimum)

```yaml
observable_outputs:
  comparison: "exact"
  variables:
    - name: "result"
```

That is enough to run:

```bash
./run.sh benchmarks/my_algo -n 50
```

Every other field is optional and documented in the
[fim.yaml Reference](fim-yaml-reference.md).

## Choosing what to corrupt

By default FIM flips bits in CPU **registers**. For float-heavy code you will
usually want to override the register set, and for some studies you will target
**memory** instead. Both are explained in:

- [Register Injection](register-injection.md)
- [Memory Injection](memory-injection.md)

## Benchmarks that talk to an external simulator

If your benchmark exchanges data over UART with a host-side process (e.g. a
robot controller driven by a physics simulator), see
[Serial Feeder](serial-feeder.md). That page also covers writing a per-fault
trajectory/sensor file that comes back with your results.
