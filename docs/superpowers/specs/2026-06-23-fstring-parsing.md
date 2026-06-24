# f-string 真解析 设计规范

> 日期: 2026-06-23 | 状态: 已完成 ✅ | 依赖: Phase 1 Parser + Tokenizer (已完成 ✅)

## 一、目标

把 f-string 从"文本段拼接"升级为**结构化 AST**——`{expr}` 内的表达式被递归解析成真正的表达式节点，使 def-use 链、调用图、类型推断能覆盖 f-string 内部。

**当前状态（简化版）：**
```gdscript
var msg = f"Hello, {name}! You have {count} items."
```
→ segments = `[{text:"Hello, "}, {expr:"name"}, {text:"! You have "}, {expr:"count"}, {text:" items."}]`
→ 包进 `LiteralNode(segments)` → resolver 跳过，不解析 `{name}`/`{count}` 的引用

**目标：**
→ `FormattedStringNode` 持有 `[{text:"Hello, "}, {expr: IdentifierNode("name")}, ...]`
→ resolver 递归解析 `{expr}` → `name` 的 READ 被记录、`count` 的 READ 被记录

## 二、范围

### 做：

1. **FormattedStringNode AST 节点** — segments 数组，文本段为 String，表达式段为 AST 节点
2. **Parser 解析 `{expr}`** — 对每个表达式段，用现有 tokenizer + parser 解析成表达式 AST
3. **Tokenizer 调整** — segments 保留原始文本（不做子词法），parser 负责解析
4. **Resolver 递归** — `FormattedStringNode` 的 expr 段走 `_resolve_expression`

### 不做：

- ❌ **格式说明符**（`{x:.2f}`）——解析冒号后的格式规范（复杂，低频）
- ❌ **嵌套 f-string**（`f"{f"inner"}"`）——递归词法，极少用
- ❌ **转义大括号** `{{`/`}}`——已在 tokenizer 层处理（`_peek() != "{"` 跳过 `{{`）

## 三、架构

```
addons/gdscript_util/
├── gds_ast_nodes.gd            # [修改] 新增 FormattedStringNode
├── gds_tokenizer.gd            # [不变] segments 已含原始 expr 文本
├── gds_parser.gd               # [修改] FORMAT_STRING_LITERAL → FormattedStringNode
└── gds_symbol_resolver.gd      # [修改] _resolve_expression 加 FormattedStringNode 分支
```

## 四、数据结构

### 4.1 FormattedStringNode

```gdscript
# gds_ast_nodes.gd 新增
class FormattedStringNode:
    extends ASTNode
    var segments: Array = []  # of {type: "text", value: String} 或 {type: "expr", node: ExpressionNode}
```

### 4.2 Tokenizer segments（已有，不变）

Tokenizer 当前产出：
```gdscript
# segments = [
#   {"text": "Hello, ", "expr": null},        # 纯文本
#   {"text": "", "expr": "name"},              # 表达式文本（待 parser 解析）
#   {"text": " items.", "expr": null},         # 纯文本
# ]
```

`expr` 字段是**原始字符串**，parser 负责把它解析成 AST。

### 4.3 Parser 流程

```
_parse_atom 遇到 FORMAT_STRING_LITERAL:
  → 取 token.literal（segments 数组）
  → 遍历 segments:
      expr == null → 添加 {type:"text", value: text}
      expr != null → 创建子 tokenizer + 子 parser 解析 expr 字符串
                    → 添加 {type:"expr", node: AST节点}
  → 返回 FormattedStringNode
```

**子解析器**：对每个 `{expr}` 的文本，创建临时 tokenizer + parser：
```gdscript
func _parse_fstring_expr(p_expr_text: String):
    var sub_tokenizer = GDScriptTokenizer.new()
    var sub_tokens = sub_tokenizer.tokenize(p_expr_text)
    var sub_parser = GDScriptParser.new()
    var sub_ast = sub_parser.parse(sub_tokens)  # 会得到 ClassNode 包装
    if sub_parser.error == "" and sub_ast.members.size() > 0:
        var stmt = sub_ast.members[0]
        if stmt is GDScriptToken.ExpressionStatementNode:
            return stmt.expression  # 提取表达式
    return null  # 解析失败 → 保留为文本
```

### 4.4 Resolver 递归

```gdscript
# _resolve_expression 加分支:
elif p_expr is GDScriptToken.FormattedStringNode:
    for seg in p_expr.segments:
        if seg.type == "expr" and seg.node != null:
            _resolve_expression(seg.node, p_scope, p_current_function, p_lambda_node)
```

## 五、交付物

| 文件 | 类型 | 说明 |
|------|------|------|
| `gds_ast_nodes.gd` | 修改 | 新增 FormattedStringNode |
| `gds_parser.gd` | 修改 | `_parse_atom` FORMAT_STRING_LITERAL → FormattedStringNode + `_parse_fstring_expr` |
| `gds_symbol_resolver.gd` | 修改 | `_resolve_expression` 加 FormattedStringNode 分支 |

## 六、验收标准

- [x] `f"Hello, {name}!"` → FormattedStringNode，含 IdentifierNode("name")
- [x] `name` 的 READ 被记录到 DefUseChain
- [x] `f"{obj.method()}"` → 含 CallNode → 调用图记录 method()
- [x] `f"{x + y}"` → 含 BinaryOpNode → def-use 记录 x/y 的 READ
- [x] 纯文本段 `f"hello"` → segments 只有 text，无 expr
- [x] Phase 1-3 回归测试全过
- [x] `{expr}` 解析失败时优雅降级（保留为文本，不崩溃）

## 七、风险

| 风险 | 缓解 |
|------|------|
| 子 tokenizer 对 `name` 解析得到 ClassNode 包装 | 提取 ExpressionStatementNode.expression |
| `{obj.method()}` 子解析产生多 token | 子 parser 递归下降应能处理 |
| 复杂表达式 `{x if cond else y}` | 三目运算符已支持，子 parser 能解析 |
| 格式说明符 `{x:.2f}` 冒号干扰 | tokenizer 分割 expr 时遇 `:` 截断（简化：不支持格式说明） |
| 性能：每个 `{expr}` 开子 tokenizer | f-string 内表达式通常很短，影响可忽略 |
