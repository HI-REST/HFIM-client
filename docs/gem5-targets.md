# Advanced (gem5) Targets

> **Retired.** HFIM-client is replaced by `hfim run --on <server>` from hfim-core
> (phase R-4). Its scripts print the hfim command that replaces them and exit 2.
> Set up a Server and run a campaign there: hfim-docs, `guides/run-on-a-server.md`.
> The table of every old command and its replacement is in that guide.

`register` and `memory` work on both backends. gem5 additionally exposes
microarchitectural targets that QEMU cannot model. These are for advanced
resilience studies and all require `--simulator gem5`.

```bash
./run.sh benchmarks/my_algo --simulator gem5 --fault cache_l1d
```

## Target families

| Family | `--fault` values | Models |
| --- | --- | --- |
| Caches (data) | `cache_l1d`, `cache_l1i`, `cache_l2` | bit flip in a cached data line |
| Cache tags | `cache_tag`, `cache_tag_parity` | corruption of the tag array |
| Cache ECC bits | `ecc_parity_l1d`, `ecc_parity_l1i`, `ecc_parity_l2` | a flipped ECC check bit |
| DRAM | `dram`, `ecc_parity_dram` | main-memory cell / DRAM ECC bit |
| CPU microarch | `phys_reg`, `rename_map`, `rob`, `lsq`, `branch_pred`, `tlb` | structures inside an out-of-order core |

The exact set available depends on how the server's gem5 was built. If a target
is not supported by the active configuration, the run reports it rather than
silently falling back.

## Related flags

| Flag | Meaning |
| --- | --- |
| `--multi-bit-count N` | inject N-bit multi-bit upsets per fault (default 1) |
| `--cache-ecc` | enable the cache ECC shadow-map model |
| `--no-cache-ecc` | explicitly disable it (for a paired control campaign) |
| `--cache-ecc-scope data\|tag\|both` | which array the ECC model protects (currently `data`) |

Use QEMU (default) for fast register/memory campaigns; use gem5 only when the
question is about a structure QEMU does not simulate.

## See also

- [Running Campaigns](running-campaigns.md)
- [fim.yaml Reference](fim-yaml-reference.md)
