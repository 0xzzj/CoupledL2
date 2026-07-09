# CoupledL2

![Build Status](https://github.com/RISCVERS/HuanCun/actions/workflows/main.yml/badge.svg)

## Compile source code

```
make init
make compile
```

## TL2TL test with tl-test

`scripts/run_tltest_tl2tl.sh` runs a pure TileLink test for CoupledL2.  It
generates `TestTop_L2L3L2`, builds `tl-test`, runs two coherent TL-C agents, and
dumps FST waves for protocol analysis.

The topology is:

```
L1D0/tl-test CAgent0 -> L2_0 \
                              L3 (TileLink)
L1D1/tl-test CAgent1 -> L2_1 /
```

This flow does not generate CHI RTL and does not run CHI tests.  It is intended
for TL2TL-only validation and for taking Acquire, Probe, and Release waveform
screenshots.

### Prepare tl-test

Clone `tl-test` next to this repository.  The script uses `../tl-test` by
default:

```
cd ..
git clone git@github.com:0xzzj/tl-test.git tl-test
cd CoupledL2
```

If `tl-test` is somewhere else, pass it with `TLTEST_HOME`:

```
TLTEST_HOME=/path/to/tl-test scripts/run_tltest_tl2tl.sh --help
```

The script does not modify the original `tl-test` checkout.  It copies it into
`tl-test-out/l2l3l2/src` and patches that local copy for this DUT:

- use two coherent agents, `master_port_0_0` and `master_port_1_0`
- dump FST instead of VCD
- build generated `TestTop` RTL with Verilator
- link the generated ChiselDB/perfCCT sources

### Dependencies

The flow expects these commands to be available:

```
make
mill
cmake
verilator
rsync
perl
gtkwave
fst2vcd
fstminer
```

On Ubuntu, the native libraries usually needed by `tl-test` are:

```
sudo apt install cmake sqlite3 libsqlite3-dev zlib1g-dev liblz4-dev gtkwave
```

### Build and run

For a clean first run:

```
THREADS=4 scripts/run_tltest_tl2tl.sh --fresh --verbose
```

For a build-only run:

```
THREADS=4 scripts/run_tltest_tl2tl.sh --fresh --build-only
```

After the build succeeds, rerun simulation only:

```
THREADS=4 scripts/run_tltest_tl2tl.sh --run-only --verbose
```

Useful environment variables:

| Variable | Default | Meaning |
| --- | --- | --- |
| `TLTEST_HOME` | `../tl-test` | Source checkout of `tl-test` |
| `OUT_ROOT` | `./tl-test-out` | Output root |
| `THREADS` | `1` | CMake/Verilator parallel build jobs |
| `SEED` | `1000` | `tl-test` random seed |
| `CYCLES` | `20000` | Simulation cycles |
| `WAVE_BEGIN` | `0` | First dumped wave cycle |
| `WAVE_END` | `CYCLES` | Last dumped wave cycle |

All generated files are under `tl-test-out/`, which is ignored by git.

### PASS screenshot

When simulation finishes successfully, the script prints a PASS banner:

```
[tl2tl-test] ========================================
[tl2tl-test] TL2TL TEST PASS
[tl2tl-test] seed=1000 cycles=1720 wave=1490..1525
[tl2tl-test] ========================================
```

For a report, capture the terminal area containing this banner and the following
output paths.  The raw log is also saved at:

```
tl-test-out/l2l3l2/run.log
```

### Waveform screenshot example

To reproduce a compact wave window containing all three major TL coherence
transactions:

```
THREADS=4 SEED=1000 CYCLES=1720 WAVE_BEGIN=1490 WAVE_END=1525 \
  scripts/run_tltest_tl2tl.sh --run-only --verbose
```

Open the generated FST:

```
latest_fst="$(ls -t tl-test-out/l2l3l2/build/*.fst | head -n1)"
gtkwave "$latest_fst"
```

If a GTKWave save file is available, open it with the FST:

```
latest_fst="$(ls -t tl-test-out/l2l3l2/build/*.fst | head -n1)"
gtkwave "$latest_fst" tl-test-out/l2l3l2/cpl2-tl-1490-1525.gtkw
```

Recommended screenshot points for `SEED=1000`, `WAVE_BEGIN=1490`,
`WAVE_END=1525`:

| Transaction | Cycle | Signals | What to show |
| --- | ---: | --- | --- |
| Acquire | `1515` | `TOP.master_port_1_0_a_*` | A channel `valid && ready`, opcode `0110` (`AcquireBlock`), address `0xcd40` |
| Release | `1500`, `1508` | `TOP.master_port_0_0_c_*`, `TOP.master_port_0_0_d_*` | C channel `ReleaseData`, then D channel `ReleaseAck` |
| Probe | `1514`, `1521` | `TOP.master_port_1_0_b_*`, `TOP.master_port_1_0_c_*`, `TOP.master_port_0_0_b_*`, `TOP.master_port_0_0_c_*` | B channel `Probe`, then C channel `ProbeAckData` or `ProbeAck` |

Use `valid && ready` as the cycle boundary.  The verbose `tl-test` log can be
off by one cycle relative to the FST dump point, so the waveform handshake is
the source of truth for screenshots.

### TileLink opcode reference

Useful opcode values for this flow:

| Channel | Opcode | Meaning |
| --- | --- | --- |
| A | `0110` | `AcquireBlock` |
| A | `0111` | `AcquirePerm` |
| B | `110` | `Probe` |
| C | `100` | `ProbeAck` |
| C | `101` | `ProbeAckData` |
| C | `110` | `Release` |
| C | `111` | `ReleaseData` |
| D | `0100` | `Grant` |
| D | `0101` | `GrantData` |
| D | `0110` | `ReleaseAck` |

### Clean outputs

To remove generated TL2TL artifacts:

```
rm -rf tl-test-out/l2l3l2
```
