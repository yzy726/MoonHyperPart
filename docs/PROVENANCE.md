# 来源与许可

MoonHyperPart 的模型、解析器、验证器、构造器、FM 移动/交换、报告和 CLI 由本项目独立实现，许可证为仓库根目录的 Apache-2.0。

`testdata/*.hgr` 全部为本项目自创夹具，同样按 Apache-2.0 分发。它们覆盖多端带权边、严格平衡、装箱修复、断连、孤立顶点和单点边。文件 SHA-256、容量、种子及预算在 `benchmarks/manifest.json`。现有基准记录来自这些自创数据。

接口与格式语义参考 [Mt-KaHyPar 官方格式说明](https://github.com/kahypar/mt-kahypar/blob/master/mt-kahypar/io/docs/FileFormats.md) 及其 [目标函数说明](https://github.com/kahypar/mt-kahypar#supported-objective-functions)。FM 使用公开的针脚计数增益、顶点锁定和最佳前缀思想，并加入有预算的可行成对交换。此仓库未引入 Mt-KaHyPar 实现代码、测试夹具或运行结果。

本模块仅依赖工具链内的 MoonBit core。core 的代码保留在工具链中，其版权和许可证由上游管理。Python 脚本使用标准库组织本地编译、文件测试、打包消费和进程测量。

注册表发布时应核实包名所有者、仓库 URL、版本状态、公开源码和实际发布结果，并保存与该版本对应的安装证据。当前仓库沿用模块名 Ag108/MoonHyperPart，Git 作者身份为 yzy726。
