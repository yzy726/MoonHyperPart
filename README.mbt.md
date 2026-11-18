# MoonHyperPart

MoonBit 加权超图二分库，提供平衡初始划分、受预算限制的 FM 移动与成对交换，以及读取原始超图的独立验证器。超边直接连接多个顶点，优化目标为 cut-net。

核心库支持 native、JS、wasm-gc，文件 CLI 使用 native。当前版本为 0.1.0，Mooncakes 发布待完成。本地 ZIP 包的独立消费端验证可通过下述命令重跑。

## 环境与运行

开发验证使用 moon 0.1.20261104、moonc v0.10.20+65efd5b93、Node.js 和 Python 3。项目仅依赖随工具链提供的 MoonBit core。native CLI 使用 core 的实验性 async 文件接口。

```sh
moon version --all
moon test --target native --deny-warn
moon run cmd/main --target native -- --help
moon run cmd/main --target native -- inspect testdata/tiny_optimum.hgr
moon run cmd/main --target native -- partition testdata/tiny_optimum.hgr --output tiny.part --report tiny.json --capacities 3,3 --starts 1
moon run cmd/main --target native -- verify testdata/tiny_optimum.hgr tiny.part --capacities 3,3
```

`tiny.part`、`tiny.json` 须使用尚不存在的路径。此例的初始 cut-net 为 21，FM 后为 1，两个分区权重均为 3。报告中的权重、容量、目标值均为十进制字符串，以完整保留 Int64 精度。

## 库调用

其他项目在 `moon.pkg` 中导入 `"Ag108/MoonHyperPart"`。独立项目见 `examples/cli_consumer`。以下示例随 `moon test` 编译运行。

```mbt check
///|
test "usage/public weighted bipartition" {
  let graph = @MoonHyperPart.build(
    [1L, 1L, 1L, 1L, 1L, 1L],
    [[0, 1, 2], [3, 4, 5], [2, 3]],
    [10L, 10L, 1L],
  ).unwrap()
  let options : @MoonHyperPart.Options = {
    ..@MoonHyperPart.Options::default(),
    starts: 1,
  }
  let result = @MoonHyperPart.partition(graph, [3L, 3L], options~).unwrap()
  assert_eq(result.metrics.cut_net, 1L)
  let checked = @MoonHyperPart.verify(graph, result.assignment, [3L, 3L]).unwrap()
  assert_eq(checked.part_weights, (3L, 3L))
}
```

`build` 拥有输入的防御性副本。图的内部数组保持隐藏。访问某个顶点、超边或针脚的索引方法要求调用者提供有效编号。求解返回 `Result`，成功时覆盖所有顶点，两个分区均非空且满足显式容量。

## 格式、容量与预算

支持 hMETIS 的无权、超边权、顶点权、双权四种模式。文件针脚从 1 开始，内存编号从 0 开始。允许孤立顶点、单点超边和零条超边。格式错误带物理行号。

CLI 默认 `--imbalance 0.030`，按 `ceil(total * (1000 + 30) / 2000)` 计算统一整数容量。容差接受 0 到 1、最多三位小数。也可使用 `--capacities C0,C1`。报告展示实际分区权重和最大分区权重与平均权重之比。

默认构造参数为 seed 726、8 个起点、100000 个修复搜索节点。默认 FM 预算为 8 轮、10000 次顶点移动、10000 次成对候选和 200000 次单点候选扫描。CLI 支持 `--seed`、`--starts`、`--search-nodes`、`--passes`、`--moves`、`--swap-trials`、`--candidates`。

默认资源上限为 100000 个顶点、100000 条超边、1000000 个针脚、16 MiB UTF-8 文本。CLI 的四个 `--max-*` 选项可收紧这些上限。输入累计权重必须能用正 Int64 表示。

| 退出码 | 含义 |
|---|---|
| 0 | 成功，partition/verify 已独立验证 |
| 2 | 参数、格式、权重、UTF-8 或输入资源错误 |
| 3 | 可证明的必要条件失败，或预算内未找到可行划分，具体看 code |
| 4 | 外部分区验证失败 |
| 5 | 文件 I/O 或输出路径错误 |
| 6 | 内部一致性检查失败 |

`impossible` 用于重顶点、总容量不足和顶点不足等可证明情形。`search_exhausted` 表示本次有界构造未找到解。FM 预算耗尽时可以返回已验证的完整解，并在报告中标出 `budget_limited`。

## 五个示例与本地安装验证

```sh
python scripts/examples.py tiny_optimum
python scripts/examples.py weighted_balance
python scripts/examples.py hmetis_roundtrip
python scripts/examples.py bad_input_and_budget
python scripts/examples.py cli_consumer
python scripts/examples.py all
```

最后一个示例会打包当前模块，将 ZIP 解包到干净的临时工作区，以独立模块调用公共 API，并在 native、JS、wasm-gc 上核对分区和报告。其 CLI 结果同时参与比对。所用临时目录自动清理。

## 基准与限制

固定清单、seed、容量、预算及 SHA-256 在 `benchmarks/manifest.json`。Windows 的实际运行记录位于 `benchmarks/results-windows.json`，包含工具链、CPU、进程耗时及采样到的峰值工作集。计时覆盖进程启动和文件 I/O。

```sh
moon run cmd/main --target native --build-only
python scripts/benchmark.py --exe _build/native/debug/build/cmd/main/main.exe --output _build/benchmark.json
```

六份自创可再分发样本、两个 seed 共 12 次运行均满足容量且不劣于相同容量下的确定性初始解。其中四次严格改善，12 顶点样本由 43 降到 1。单起点基线的排序固定，因此这里两个 seed 的结果相同。8 顶点断连样本保持 2，说明该启发式仍可能停在较差解。

当前算法使用有界候选扫描，适合小型、教学和离线实验。它对一般实例提供启发式可行解。k 大于 2、多层划分、Matrix Market、固定顶点和多路 connectivity 优化留待后续版本。现有记录覆盖自创样本，工业实例吞吐与成熟求解器的差距仍待实测。

## 开发检查与文档

```sh
moon fmt --check
moon check --target native --deny-warn
moon test --target native --deny-warn
moon check --target js --deny-warn
moon test --target js --deny-warn
moon check --target wasm-gc --deny-warn
moon test --target wasm-gc --deny-warn
moon info
moon fmt
```

接口基线随 `pkg.generated.mbti` 提交。0.x 阶段会在 CHANGELOG 记录公共 API 变化。算法与复杂度见 [ALGORITHM](docs/ALGORITHM.md)，输入与输出见 [FORMAT](docs/FORMAT.md)，容量与指标见 [METRICS](docs/METRICS.md)，来源见 [PROVENANCE](docs/PROVENANCE.md)。输入边界见 [SECURITY](SECURITY.md)，AI 辅助范围见 [AI_USAGE](AI_USAGE.md)。许可证为 Apache-2.0。
