# ADR-0001: 暂缓 C# 重写，先 Profile 再决定

> 日期: 2026-06-21 | 状态: 已决策 | 决策者: kenyonxu + Claude

## 背景

gdscript-ast-flow 当前用纯 GDScript 实现 tokenizer + parser + symbol resolver。GDScript 是解释执行（字节码 VM），对计算密集任务有性能疑虑。是否用 C# 重写以获得性能提升？

## 评估

### C# 重写预期收益

| 组件 | GDScript 痛点 | C# 倍率 |
|------|--------------|---------|
| Tokenizer | `source[idx]` 每次返回 String（堆分配），10k 行 = 10k+ 分配 | 30-50x |
| Parser | 递归下降调用开销 + RefCounted 节点分配 | 10-20x |
| Resolver | Dictionary 查找 + 对象访问 | 5-10x |
| **整管道** | — | **~15-30x**（1000 行 ~80ms → ~3-5ms，估值） |

### 关键前提（冷水）

Godot 引擎**内部已有 C++ 的 GDScriptParser**（供 LSP/补全用）。我们用 GDScript 重写 parser 是为了**控制要抓的数据 + 暴露 AST**，不是为性能。若纯为性能，正解是设法复用引擎 C++ parser，而非用 C# 重写第二遍。

### 重写的真实代价

- **构建复杂度**：C# GDExtension 需 .NET SDK + 独立 assembly + Godot 版本耦合。当前**纯 GDScript = 零构建、可移植**，是需保留的优势。
- **编辑器插件层必须留 GDScript**（`@tool` EditorPlugin），C# 只能做分析核心 → 必然有 GDScript↔C# 数据 marshalling 边界。
- **重写量**：核心 3 文件 ~2000 行 + AST 节点类。

## 决策

**暂缓 C# 重写。** 三条触发条件目前都不满足：
1. 未做基准测试（"1000 行 < 50ms" 是猜测，从未 profile）
2. 用户未感知性能痛点（单文件分析无抱怨）
3. 重写 ROI 未知（不知时间花在哪）

## 触发条件（何时重新评估）

满足**全部**时重开评估：

1. **已 profile**：用 Godot 内置 profiler 测过大文件/大项目分析，确认 tokenizer 占 >60% 时间
2. **用户感知痛**：项目扫描 100+ 文件明显卡顿，或保存触发分析延迟影响编辑
3. **GDScript 优化已尽**：试过零成本优化（PackedByteArray、节点池等）仍不达标

## 路径（若未来重开）

1. **第一步永远是 Profile**（Phase 3.4 首项）——用数据说话，不靠猜
2. **GDScript 内优化优先**（零迁移成本，可能拿 3-5x）：
   - tokenizer 预转 `PackedByteArray` 或缓存 `source[idx]`
   - AST 节点对象池（减少 RefCounted 分配）
3. **若仍不够 → 局部 C# 移植**：
   - **只移 tokenizer**（最大收益、最孤立、无 Godot API 依赖）→ 80% 收益 / 20% 力
   - parser/resolver 留 GDScript（与 AST 结构、编辑器插件耦合深，迁移成本高，最后再考虑）

## 当前优先级

性能是**工程**优化；图可视化（Phase 3.3）是**用户价值**跃迁。先把 Phase 3.3 做完，让工具真正可用起来，再用 profile 数据决定是否需要 C#。

## 参考

- 性能基准 + profile 列为 **Phase 3.4 第一项**
- GDScript 性能特性：解释执行、String 索引分配、RefCounted 分配开销
- 引擎内置 C++ GDScriptParser：`modules/gdscript/gdscript_parser.cpp`
