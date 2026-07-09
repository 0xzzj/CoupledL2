# CoupledL2

![Build Status](https://github.com/RISCVERS/HuanCun/actions/workflows/main.yml/badge.svg)

本文档面向第一次看到这个仓库的人，目标是说明如何准备环境、如何选择测试场景、如何用 `tl-test` 跑纯 `TileLink` 测试，以及如何截图 `Acquire`、`Probe`、`Release` 三类一致性事务。

如果当前目标是只测试 `TileLink` 的 `L2`/`TL2TL` 行为，优先使用本文档里的 `tl-test` 流程。`tl-test-new` 更适合完整系统或 `CHI` 相关流，不作为本文档的主流程。

## 仓库准备

初始化子模块并编译 Scala/Chisel 源码：

```bash
make init
make compile
```

常用工具和依赖：

```bash
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

Ubuntu 上通常还需要这些本地库：

```bash
sudo apt install cmake sqlite3 libsqlite3-dev zlib1g-dev liblz4-dev gtkwave
```

## 测试场景选择

仓库在 [src/test/scala/TestTop.scala](src/test/scala/TestTop.scala) 里定义了多个 `TestTop`，对应的生成目标在 [Makefile](Makefile) 中。先根据你想验证的问题选择拓扑，再决定是否接 `tl-test` 随机激励。

| 场景 | 生成命令 | 拓扑 | 适合验证 | 是否适合截图 `Acquire`/`Probe`/`Release` |
| --- | --- | --- | --- | --- |
| 单个 `L2` | `make test-top-l2` | `L1D -> L2 -> TLRAM` | 单个 `L2` 的基本 `TL-C` 行为、目录、MSHR、替换、写回 | `Acquire`/`Release` 可以测，`Probe` 不一定稳定 |
| 单个 `L2` + 伪下游 | `make test-top-l2standalone` | `L1D -> L2 -> Fake_L3` | 把 `L2` 单独拿出来接一个支持 `Acquire` 的下游 `TL manager` | 比 `test-top-l2` 更像独立 `L2` 测试，但 `Probe` 仍不如多 `L2` 稳 |
| 一个 `L2` + 一个 `L3` | `make test-top-l2l3` | `L1I/L1D -> L2 -> L3 -> TLRAM` | `L2` 带真实 `TileLink L3` 的路径、`L1I`/`L1D` 混合入口、`ECC`/prefetch 配置 | 可观察更多下游交互，但不是最稳定的三事务截图场景 |
| 两个 `L2` + 共享 `L3` | `make test-top-l2l3l2` | `L1D0 -> L2_0 -> L3 <- L2_1 <- L1D1` | 多 `TL-C` agent、跨 `L2` 一致性、`Probe`/`Release` 事务 | 最推荐，用于报告截图 |
| 更完整系统 | `make test-top-fullsys` | 完整系统 `TestTop` | 集成级生成检查 | 不作为当前 `TL2TL` 主流程 |
| `CHI` 场景 | `make test-top-chi*` | `CHI` 相关拓扑 | `CHI` 集成验证 | 当前只测 `TileLink` 时不要用 |

简单判断：

- 只想看单个 `L2` 是否能生成 RTL：用 `make test-top-l2`。
- 想把 `L2` 放在近似独立环境中测：用 `make test-top-l2standalone`。
- 想看 `L2` 接真实 `TileLink L3`：用 `make test-top-l2l3`。
- 想稳定截图 `Acquire`、`Probe`、`Release`：用 `make test-top-l2l3l2` 或本文提供的 `scripts/run_tltest_tl2tl.sh`。

## 只生成 RTL

如果你只是想确认某个 `TestTop` 能完成 Chisel 展开并生成 RTL，可以直接运行：

```bash
make clean
make compile
make test-top-l2
```

生成物在 `build/` 下。其它拓扑替换最后一行即可：

```bash
make test-top-l2standalone
make test-top-l2l3
make test-top-l2l3l2
make test-top-fullsys
```

这一步只说明 Chisel 展开和 RTL 生成成功，不等价于协议随机测试 PASS。

## 准备 tl-test

`tl-test` 建议克隆到 `CoupledL2` 的同级目录。脚本默认查找 `../tl-test`：

```bash
cd ..
git clone git@github.com:0xzzj/tl-test.git tl-test
cd CoupledL2
```

如果 `tl-test` 不在默认位置，用 `TLTEST_HOME` 指定：

```bash
TLTEST_HOME=/path/to/tl-test scripts/run_tltest_tl2tl.sh --help
```

脚本不会修改原始 `tl-test` 仓库。它会复制一份到 `tl-test-out/l2l3l2/src`，然后只修改这份临时副本：

- 使用两个一致性 `agent`，对应 `master_port_0_0` 和 `master_port_1_0`
- 使用 `FST`，不生成大体积 `VCD`
- 用 `Verilator` 编译当前仓库生成的 `TestTop`
- 链接生成的 `ChiselDB`/`perfCCT` 源码

所有测试产物都放在 `tl-test-out/`，该目录已经被 `.gitignore` 忽略。

## 推荐的 TL2TL 自动化流程

当前自动化脚本是：

```bash
scripts/run_tltest_tl2tl.sh
```

它固定生成并测试 `TestTop_L2L3L2`：

```text
tl-test CAgent0 -> L2_0 \
                         L3
tl-test CAgent1 -> L2_1 /
```

这个拓扑是纯 `TileLink`，不会生成 `CHI RTL`，也不会运行 `CHI` 测试。它之所以默认用两个 `L2`，是因为两个一致性 `agent` 访问同一地址时更容易稳定触发 `Probe` 和 `Release`，适合做协议截图。

第一次完整运行：

```bash
THREADS=4 scripts/run_tltest_tl2tl.sh --fresh --verbose
```

只生成 RTL 并构建仿真器：

```bash
THREADS=4 scripts/run_tltest_tl2tl.sh --fresh --build-only
```

复用已有构建目录，只重新跑仿真：

```bash
THREADS=4 scripts/run_tltest_tl2tl.sh --run-only --verbose
```

常用环境变量：

| 变量 | 默认值 | 含义 |
| --- | --- | --- |
| `TLTEST_HOME` | `../tl-test` | `tl-test` 源码路径 |
| `OUT_ROOT` | `./tl-test-out` | 输出根目录 |
| `THREADS` | `1` | `CMake`/`Verilator` 并行编译线程数 |
| `SEED` | `1000` | `tl-test` 随机种子 |
| `CYCLES` | `20000` | 仿真周期数 |
| `WAVE_BEGIN` | `0` | 开始记录波形的周期 |
| `WAVE_END` | `CYCLES` | 停止记录波形的周期 |

脚本常用参数：

| 参数 | 作用 |
| --- | --- |
| `--fresh` | 重新复制并修改 `tl-test` 副本，同时清理旧构建目录 |
| `--build-only` | 只生成 RTL 和构建仿真器，不运行仿真 |
| `--run-only` | 复用已有构建目录，只运行仿真 |
| `--verbose` | 给 `tl-test` 传 `-v`，日志会打印 `Acquire`/`Probe`/`Release` 等事务 |

## PASS 截图

仿真成功后脚本会打印：

```text
[tl2tl-test] ========================================
[tl2tl-test] TL2TL TEST PASS
[tl2tl-test] seed=1000 cycles=1720 wave=1490..1525
[tl2tl-test] ========================================
```

报告中可以截终端最后几行，至少包含：

- `Finished`
- `Transactions: 0`
- `TL2TL TEST PASS`
- `run.log` 路径
- `*.fst` 路径

日志保存位置：

```bash
tl-test-out/l2l3l2/run.log
```

## 波形截图

复现一个较小、同时包含 `Acquire`、`Probe`、`Release` 的窗口：

```bash
THREADS=4 SEED=1000 CYCLES=1720 WAVE_BEGIN=1490 WAVE_END=1525 \
  scripts/run_tltest_tl2tl.sh --run-only --verbose
```

打开最新的 `FST`：

```bash
latest_fst="$(ls -t tl-test-out/l2l3l2/build/*.fst | head -n1)"
gtkwave "$latest_fst"
```

如果已有 `GTKWave` 保存文件，可以一起打开：

```bash
latest_fst="$(ls -t tl-test-out/l2l3l2/build/*.fst | head -n1)"
gtkwave "$latest_fst" tl-test-out/l2l3l2/cpl2-tl-1490-1525.gtkw
```

推荐截图点：

| 事务 | 周期 | 信号 | 截图重点 |
| --- | ---: | --- | --- |
| `Acquire` | `1515` | `TOP.master_port_1_0_a_*` | `A` channel `valid && ready`，`opcode=0110`，地址 `0xcd40` |
| `Release` | `1500`, `1508` | `TOP.master_port_0_0_c_*`, `TOP.master_port_0_0_d_*` | `C` channel `ReleaseData`，随后 `D` channel `ReleaseAck` |
| `Probe` | `1514`, `1521` | `TOP.master_port_1_0_b_*`, `TOP.master_port_1_0_c_*`, `TOP.master_port_0_0_b_*`, `TOP.master_port_0_0_c_*` | `B` channel `Probe`，随后 `C` channel `ProbeAckData` 或 `ProbeAck` |

截图时以波形里的 `valid && ready` 为准。`tl-test` 详细日志和 `FST` 记录点可能相差一个周期，所以最终解释应以波形握手为准。

## 事务和信号对应关系

`TileLink` 五个通道里，和一致性协议分析最相关的是：

| 通道 | 常见事务 | 顶层信号 |
| --- | --- | --- |
| `A` | `AcquireBlock`, `AcquirePerm` | `TOP.master_port_*_a_*` |
| `B` | `Probe` | `TOP.master_port_*_b_*` |
| `C` | `ProbeAck`, `ProbeAckData`, `Release`, `ReleaseData` | `TOP.master_port_*_c_*` |
| `D` | `Grant`, `GrantData`, `ReleaseAck` | `TOP.master_port_*_d_*` |
| `E` | `GrantAck` | `TOP.master_port_*_e_*` |

常用 `opcode`：

| 通道 | `opcode` | 含义 |
| --- | --- | --- |
| `A` | `0110` | `AcquireBlock` |
| `A` | `0111` | `AcquirePerm` |
| `B` | `110` | `Probe` |
| `C` | `100` | `ProbeAck` |
| `C` | `101` | `ProbeAckData` |
| `C` | `110` | `Release` |
| `C` | `111` | `ReleaseData` |
| `D` | `0100` | `Grant` |
| `D` | `0101` | `GrantData` |
| `D` | `0110` | `ReleaseAck` |

## 只测试 L2 时怎么做

如果你严格只想看单个 `L2`，先使用 RTL 生成目标：

```bash
make clean
make compile
make test-top-l2
```

这个场景能覆盖单个 `L2` 的基本 `Acquire`/`Grant` 路径，也可以观察替换和写回。但由于只有一个一致性 client，`Probe` 不一定稳定出现。

如果你想要一个更像独立 `L2` 的测试环境：

```bash
make clean
make compile
make test-top-l2standalone
```

它在下游接了伪 `TL manager`，更适合把 `L2` 从多级系统里拆出来看。

如果目标是报告中的三类事务截图，不建议只用单 `L2`。推荐继续使用 `L2L3L2`，因为两个 `TL-C` agent 更容易稳定触发跨缓存的 `Probe` 和 `Release`。

## 常见问题

### 为什么不用 VCD？

`FST` 文件更小，`GTKWave` 和 `Surfer` 都能打开。当前脚本会修改 `tl-test` 副本，让 `Verilator` 使用 `TRACE_FST`，因此默认生成 `*.fst`。

### 为什么 `L2L3L2` 里有 L3，但仍然说是 TL2TL？

这里的 `L3` 是 `TileLink` 侧的 `HuanCun`，不是 `CHI`。`L2L3L2` 的目的不是测试 `CHI`，而是提供两个一致性 `L2` 共享下游的环境，方便产生 `Probe` 和 `Release`。

### 为什么单个 L2 不容易看到 Probe？

`Probe` 通常由下游或同级一致性冲突触发。如果只有一个一致性 client，随机流里缺少另一个缓存来争抢同一 block，`Probe` 可能只在替换、降权或特殊回收路径里出现，不适合作为稳定截图来源。

### tl-test 原仓库会被改吗？

不会。脚本只复制 `tl-test` 到 `tl-test-out/l2l3l2/src`，然后修改这个副本。

### 如何清理测试产物？

```bash
rm -rf tl-test-out/l2l3l2
```

如果只想清理 RTL：

```bash
make clean
```
