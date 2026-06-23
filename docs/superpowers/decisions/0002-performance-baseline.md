# ADR-0002: 性能基准 — Tokenizer 是瓶颈，暂不优化

> 日期: 2026-06-23 | 状态: 已决策 | 关联: ADR-0001（暂缓 C# 重写）

## 背景

ADR-0001 决定"先 profile 再决定是否 C# 重写"。本文档记录基准数据并给出结论。

## 基准数据（Godot 4.7 编辑器内，EditorScript _run()）

| 文件 | 行数 | Tokenize | Parse | Resolve | 总计 |
|------|------|----------|-------|---------|------|
| analysis_demo.gd | 47 | 1.1ms | 0.7ms | 0.5ms | 2.2ms |
| gds_tokenizer.gd | 495 | 14.8ms | 2.0ms | 0.9ms | 17.7ms |
| gds_parser.gd | 1078 | 34.6ms | 1.4ms | 1.4ms | 37.5ms |
| gds_symbol_resolver.gd | 668 | 24.2ms | 1.4ms | 1.3ms | 26.9ms |
| gds_project_analyzer.gd | 143 | 4.9ms | 0.7ms | 0.5ms | 6.0ms |

## 分析

### 瓶颈定位

- **Tokenizer 占 82-92%**（确认 ADR-0001 预测）
- Parse + Resolve 各 <2ms，**无需优化**
- 根因：`source[idx]` 字符串索引每次分配 String 对象

### 缩放预测（线性 ~0.032ms/行）

| 规模 | Tokenizer | 总管道 | 评价 |
|------|-----------|--------|------|
| 500 行（典型脚本） | ~16ms | ~18ms | ✅ 无感 |
| 1000 行 | ~32ms | ~37ms | ✅ 可接受 |
| 5000 行（大文件） | ~160ms | ~165ms | ⚠️ 可感知延迟 |
| 10000 行（超大） | ~320ms | ~330ms | ❌ 卡 |

### 额外发现

- 4/5 测试文件 PARSE_ERR——parser 不认 match/ternary 等自身 addon 语法（独立问题，不影响性能结论）
- 项目扫描（Phase 3.2）串行分析 N 文件 = N × 单文件耗时，deferred 不阻塞但大项目首扫慢

## 决策

**暂不优化。** 理由：

1. **当前够用**：典型 Godot 脚本 200-500 行，管道 <20ms，用户无感
2. **Phase 3.2 项目扫描 deferred**：即使首扫慢也不阻塞编辑器
3. **优化路径已明确**：若需优化，按 ADR-0001 先 GDScript 内优化（PackedByteArray），再 tokenizer 单点 C#

## 何时重新评估

满足**任一**：
- 用户分析 >2000 行文件时感知卡顿
- 项目扫描 100+ 文件首扫 >5s
- 有 GDScript 零成本优化方案（如 PackedByteArray）可快速验证

## 若优化：优先级

1. **GDScript 内零成本**（预估 3-5x）：
   - tokenizer 预转 `source.to_utf8_buffer()` → 按字节索引（避免 String 分配）
   - AST 节点对象池
2. **Tokenizer 单点 C#**（预估 30-50x，ADR-0001 推荐路径）
3. Parse/Resolve 不动（已够快）

## 参考

- ADR-0001: 暂缓 C# 重写（触发条件 + 路径）
- 基准脚本：`tests/benchmark.gd`
- Godot 源码 tokenizer 对比：`modules/gdscript/gdscript_tokenizer.cpp`
