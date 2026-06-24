# AST 行号填充 + class_name 误判修复 设计规范

> 日期: 2026-06-23 | 状态: 设计中 | 依赖: Phase 1 Parser (已完成 ✅)

## 一、目标

两个独立的 parser 数据质量问题，从 codegraph.json 导出发现：

1. **AST 节点缺行号** — `IdentifierNode`/`CallNode`/`LiteralNode` 等创建时没填 `.line`，导致调用边/跨文件边/codegraph 全是 `line: 0`
2. **内部类名误当文件级 class_name** — `class InnerHelper:` 内部类被误提取为文件 `class_name`

## 二、问题 1：AST 行号

### 现状

```json
// codegraph.json 里的调用边
{"caller": "_ready", "callee": "take_damage", "type": "SELF", "line": 0}
//                                                                ^^^^^^^^ 应该是实际行号
```

### 根因

`_parse_atom` 创建表达式节点时不填 `.line`：

```gdscript
# 当前（line 永远 0）:
GDScriptToken.Type.IDENTIFIER:
    _advance()
    var node = GDScriptToken.IdentifierNode.new()
    node.name = t.literal
    return node  # ← node.line 没设
```

同样问题的节点：`IdentifierNode`、`LiteralNode`、`CallNode`、`AttributeNode`、`BinaryOpNode`、`UnaryOpNode`、`TernaryOpNode`、`AssignmentNode`、`ArrayNode`、`DictionaryNode`、`SelfNode`、`SuperNode`、`PreloadNode`、`CastNode`、`TypeTestNode`、`SubscriptNode`、`LambdaNode`、`FormattedStringNode`

### 修复

每个 `_parse_atom` / `_parse_expression` 分支创建节点时填 `.line = t.start_line`（token 的行号）。

**规则：**
- 简单节点（Identifier/Literal/Self/Super）：`.line = t.start_line`
- 复合节点（BinaryOp/Call/Assignment）：`.line = left.line`（取操作数或 callee 的行号）
- 语句节点（If/While/For/Return）：已有 `.line`（Phase 1 已填）

### 影响

- **codegraph.json**：调用边/跨文件边带正确行号 → AI agent 可跳转
- **Call Graph 面板**：点节点跳转定位到正确行
- **Def-Use 链**：读写站点的行号准确
- **不破坏现有功能**：`.line` 之前是 0，现在填实际值，只是更准

## 三、问题 2：class_name 误判

### 现状

```json
// parser_edge_cases.gd 有 class InnerHelper: （内部类）
// 但 codegraph.json 显示:
"class_name": "InnerHelper"  // ← 错！该文件没有 class_name 声明
```

### 根因

`parse()` 的 header 循环只检测 `CLASS_NAME` 关键字（文件级），不检测 `CLASS`（内部类）。但如果 tokenizer 把 `class InnerHelper:` 的 `class` 误识别为 `CLASS_NAME`，就会误填 `classname_id`。

更可能的原因：`_parse_class_member` 的 `CLASS` 分支调用 `_parse_inner_class()`，内部类解析后返回 ClassNode，但**没清 classname_id**。如果内部类是最后一个 class 成员，其 classname_id 可能被外层误读。

### 修复

确认 `_parse_inner_class` 返回的 ClassNode **只在 members 数组里**，不影响外层 root.classname_id。如果 root.classname_id 在 header 循环后就没被内部类改过，那问题在别处——需要排查 parser_edge_cases.gd 的 token 流。

## 四、范围

### 做：

1. **`_parse_atom` 全部分支填 `.line`** — ~15 个节点类型
2. **`_parse_expression` 复合节点填 `.line`** — BinaryOp/Unary/Ternary/Assignment/Call/Attribute/Subscript
3. **排查 class_name 误判** — 确认是 token 识别还是数据流问题

### 不做：

- ❌ 重构 AST 行号传播架构 — 逐节点补行号够用
- ❌ 修改 tokenizer — 行号在 token 里已正确（`start_line`）

## 五、交付物

| 文件 | 类型 | 说明 |
|------|------|------|
| `gds_parser.gd` | 修改 | `_parse_atom` + `_parse_expression` 所有分支填 `.line` |
| `gds_parser.gd` | 修改 | 排查 class_name 误判（可能改 header 循环或 token 检测） |

## 六、验收标准

- [ ] codegraph.json 调用边的 `line` 不再全是 0
- [ ] `_ready` 调 `take_damage` 的 line 对应源码行号
- [ ] 跨文件边的 `line` 正确
- [ ] parser_edge_cases.gd 的 `class_name` 为空（无 class_name 声明）
- [ ] 有 class_name 的文件（player.gd）仍正确
- [ ] Phase 1-3 回归测试全过
- [ ] Test 15/15 全 PASS

## 七、风险

| 风险 | 缓解 |
|------|------|
| 遗漏某些节点类型 | 逐一检查 _parse_atom 的每个 case |
| 复合节点取哪个 token 的行号 | 统一规则：取第一个子节点的行号（或 left/callee） |
| class_name 问题可能是 tokenizer 误识别 | 先加 debug 打印 token 流确认 |
