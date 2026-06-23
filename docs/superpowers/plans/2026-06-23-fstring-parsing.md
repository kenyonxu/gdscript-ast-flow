# f-string 真解析 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** f-string `{expr}` 内的表达式被递归解析成 AST 节点，使 def-use 链、调用图、类型推断能覆盖 f-string 内部。

**Architecture:** FormattedStringNode 新增 AST 节点；Parser 对每个 `{expr}` 用子 tokenizer+parser 解析；Resolver 递归处理表达式段。

**Tech Stack:** Godot 4.7, GDScript

**Spec reference:** `docs/superpowers/specs/2026-06-23-fstring-parsing.md`

---

## 文件结构

```
addons/gdscript_util/
├── gds_ast_nodes.gd            # [修改] 新增 FormattedStringNode
├── gds_parser.gd               # [修改] _parse_atom FORMAT_STRING_LITERAL + _parse_fstring_expr
└── gds_symbol_resolver.gd      # [修改] _resolve_expression 加 FormattedStringNode 分支
tests/
└── test_symbol_resolver.gd     # [修改] 新增 test_15_fstring
```

---

## Task 1: FormattedStringNode AST 节点

**Files:** Modify: `addons/gdscript_util/gds_ast_nodes.gd`

- [ ] **Step 1: 在 PreloadNode 之后追加**

```gdscript
# ---- Phase 3.4: f-string 结构化节点 ----
class FormattedStringNode:
    extends ASTNode
    var segments: Array = []  # of {"type":"text", "value":String} 或 {"type":"expr", "node":ExpressionNode}
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_ast_nodes.gd
git commit -m "feat: FormattedStringNode — structured f-string AST node"
```

---

## Task 2: Parser — _parse_fstring_expr 子解析器

**Files:** Modify: `addons/gdscript_util/gds_parser.gd`

- [ ] **Step 1: 添加 _parse_fstring_expr 方法**

在 `_parse_atom` 之前添加：

```gdscript
# 对 f-string {expr} 的文本创建子 tokenizer+parser 解析成表达式节点
func _parse_fstring_expr(p_expr_text: String):
	if p_expr_text == "":
		return null
	var sub_tokenizer = GDScriptTokenizer.new()
	var sub_tokens = sub_tokenizer.tokenize(p_expr_text)
	var sub_parser = GDScriptParser.new()
	var sub_ast = sub_parser.parse(sub_tokens)
	if sub_parser.error != "" or sub_ast == null:
		return null  # 解析失败 → 优雅降级（保留为文本）
	# parse() 返回 ClassNode，表达式语句在 members[0]
	if sub_ast.members.size() > 0:
		var member = sub_ast.members[0]
		if member is GDScriptToken.ExpressionStatementNode:
			return member.expression  # 提取表达式
	return null
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_parser.gd
git commit -m "feat: _parse_fstring_expr — sub-tokenizer+parser for {expr} segments"
```

---

## Task 3: Parser — _parse_atom FORMAT_STRING_LITERAL

**Files:** Modify: `addons/gdscript_util/gds_parser.gd`

- [ ] **Step 1: 替换 FORMAT_STRING_LITERAL 分支**

找到 `_parse_atom` 中的 `FORMAT_STRING_LITERAL` 分支（当前包进 LiteralNode），替换为：

```gdscript
        GDScriptToken.Format_STRING_LITERAL:
            _advance()
            var segments = t.literal  # tokenizer 产出的 [{text, expr}, ...]
            var fsnode = GDScriptToken.FormattedStringNode.new()
            for seg in segments:
                if seg.expr != null and seg.expr != "":
                    # 表达式段 → 子 parser 解析
                    var expr_node = _parse_fstring_expr(seg.expr)
                    if expr_node != null:
                        fsnode.segments.append({"type": "expr", "node": expr_node})
                    else:
                        # 解析失败 → 降级为文本 {原始表达式}
                        fsnode.segments.append({"type": "text", "value": "{" + seg.expr + "}"})
                else:
                    # 纯文本段
                    fsnode.segments.append({"type": "text", "value": seg.text})
            return fsnode
```

> **注意：** Token 枚举名 `FORMAT_STRING_LITERAL` 需确认与 `gds_ast_nodes.gd` 里一致。如 Token 名有出入，用 `Type.find_key` 确认。

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_parser.gd
git commit -m "feat: _parse_atom FORMAT_STRING_LITERAL → FormattedStringNode with parsed exprs"
```

---

## Task 4: Resolver — _resolve_expression 加分支

**Files:** Modify: `addons/gdscript_util/gds_symbol_resolver.gd`

- [ ] **Step 1: 在 _resolve_expression 的叶子节点分支之前加**

找到 `_resolve_expression` 中 `PreloadNode` 分支附近，追加：

```gdscript
	elif p_expr is GDScriptToken.FormattedStringNode:
		# f-string: 递归解析每个 {expr} 段
		for seg in p_expr.segments:
			if seg.get("type", "") == "expr" and seg.get("node", null) != null:
				_resolve_expression(seg.node, p_scope, p_current_function, p_lambda_node)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_symbol_resolver.gd
git commit -m "feat: resolver — recurse into FormattedStringNode expr segments"
```

---

## Task 5: 验收测试

**Files:** Modify: `tests/test_symbol_resolver.gd`

- [ ] **Step 1: 追加 test_15_fstring**

```gdscript
func test_15_fstring():
	print("Test 15: f-string parsing...")
	var source = "var name: String = \"World\"\nvar count: int = 42\nvar msg = f\"Hello, {name}! You have {count} items.\"\n"
	var ast = parse(source)
	var v = ast.members[2]  # var msg
	assert(v is GDScriptToken.VariableNode, "Expected VariableNode for msg")
	assert(v.initializer is GDScriptToken.FormattedStringNode, "Expected FormattedStringNode")
	var fs = v.initializer
	# 至少有 expr 段
	var has_expr = false
	for seg in fs.segments:
		if seg.get("type", "") == "expr":
			has_expr = true
			break
	assert(has_expr, "FormattedStringNode should have at least one expr segment")
	print("  PASS")
```

- [ ] **Step 2: 提交**

```bash
git add tests/test_symbol_resolver.gd
git commit -m "test: test_15_fstring — verify FormattedStringNode segments"
```

---

## Task 6: 回归 + 验收

- [ ] **Step 1: 运行 test_symbol_resolver.tscn** — Test 1-15 全 PASS
- [ ] **Step 2: 双击 analysis_demo.gd** — 确认调用图/def-use 不受影响（demo 无 f-string）
- [ ] **Step 3: 双击 parser_edge_cases.gd** — 确认 f-string 正常解析
- [ ] **Step 4: 提交（如有调整）**

---

## 完成检查清单

- [ ] `gds_ast_nodes.gd` — FormattedStringNode
- [ ] `gds_parser.gd` — _parse_fstring_expr + _parse_atom FORMAT_STRING_LITERAL
- [ ] `gds_symbol_resolver.gd` — _resolve_expression FormattedStringNode 分支
- [ ] test_15_fstring — FormattedStringNode segments 断言
- [ ] Test 1-15 全 PASS
- [ ] analysis_demo / parser_edge_cases 回归通过
