# AST 行号填充 + class_name 修复 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** parser 创建 AST 节点时填 `.line`（当前全为 0）；排查内部类名误当文件级 class_name。

**Architecture:** 逐个 `_parse_atom` / `_parse_expression` 分支补 `node.line = t.start_line`。

**Tech Stack:** Godot 4.7, GDScript

**Spec reference:** `docs/superpowers/specs/2026-06-23-ast-line-numbers.md`

---

## Task 1: _parse_atom 简单节点填行号

**Files:** Modify: `addons/gdscript_util/gds_parser.gd`

- [ ] **Step 1: 逐个分支补 `.line`**

找到 `_parse_atom` 中以下分支，每个创建节点后加 `node.line = t.start_line`（t 是 `_peek()` 保存的当前 token）：

```gdscript
# IDENTIFIER:
    var node = GDScriptToken.IdentifierNode.new()
    node.name = t.literal
    node.line = t.start_line  # ← 加这行

# LITERAL:
    var node = GDScriptToken.LiteralNode.new()
    node.value = t.literal
    node.line = t.start_line  # ← 加这行

# FORMAT_STRING_LITERAL:
    var fsnode = GDScriptToken.FormattedStringNode.new()
    fsnode.line = t.start_line  # ← 加这行

# SELF:
    var sn = GDScriptSelfNode.new()
    sn.line = t.start_line  # ← 加这行

# SUPER:
    var sn = GDScriptSuperNode.new()
    sn.line = t.start_line  # ← 加这行

# PRELOAD:
    var node = GDScriptToken.PreloadNode.new()
    node.line = t.start_line  # ← 加这行

# CONST_PI/TAU/INF/NAN:
    var node = GDScriptToken.LiteralNode.new()
    node.line = t.start_line  # ← 加这行
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_parser.gd
git commit -m "fix: _parse_atom simple nodes — fill .line from token start_line"
```

---

## Task 2: _parse_atom 复合节点填行号

**Files:** Modify: `addons/gdscript_util/gds_parser.gd`

- [ ] **Step 1: CallNode/AttributeNode/SubscriptNode/ArrayNode/DictionaryNode/LambdaNode**

在 `_parse_atom` 和 `_parse_expression` postfix 分支中：

```gdscript
# CallNode:
    var call = GDScriptToken.CallNode.new()
    call.line = left.line if left != null else t.start_line  # ← 取 callee 行号

# AttributeNode:
    var attr = GDScriptToken.AttributeNode.new()
    attr.line = t.start_line  # ← 当前 token (.)的行号

# SubscriptNode:
    var sub = GDScriptToken.SubscriptNode.new()
    sub.line = t.start_line

# ArrayNode:
    var node = GDScriptToken.ArrayNode.new()
    node.line = t.start_line

# DictionaryNode:
    var node = GDScriptToken.DictionaryNode.new()
    node.line = t.start_line

# LambdaNode (_parse_lambda):
    var node = GDScriptToken.LambdaNode.new()
    node.line = t.start_line  # t 是 FUNC token
```

- [ ] **Step 2: BinaryOp/UnaryOp/Ternary/Assignment/Cast/TypeTest**

在 `_parse_expression` 各 assoc 分支：

```gdscript
# BinaryOpNode:
    var node = GDScriptToken.BinaryOpNode.new()
    node.line = left.line if left != null else 0

# UnaryOpNode:
    var node = GDScriptToken.UnaryOpNode.new()
    node.line = t.start_line  # 运算符 token

# TernaryOpNode:
    var node = GDScriptToken.TernaryOpNode.new()
    node.line = left.line if left != null else 0

# AssignmentNode:
    var node = GDScriptToken.AssignmentNode.new()
    node.line = left.line if left != null else 0

# CastNode:
    var node = GDScriptToken.CastNode.new()
    node.line = left.line if left != null else 0

# TypeTestNode:
    var node = GDScriptToken.TypeTestNode.new()
    node.line = left.line if left != null else 0
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/gds_parser.gd
git commit -m "fix: _parse_expression compound nodes — fill .line from left/callee"
```

---

## Task 3: 排查 class_name 误判

**Files:** Modify: `addons/gdscript_util/gds_parser.gd`（视排查结果）

- [ ] **Step 1: 加 debug 打印 token 流**

在 `parse()` 的 header 循环后加临时打印：

```gdscript
    _skip_newlines()
    print("[D parse] classname_id after header: '%s'" % root.classname_id)
    print("[D parse] first member token: %s" % (_peek().get_name() if _peek() else "null"))
```

- [ ] **Step 2: 双击 parser_edge_cases.gd 看输出**

确认 header 循环后 `classname_id` 是否为空。如果为空但最终 codegraph 显示 "InnerHelper"，问题在 resolver 或导出层。

- [ ] **Step 3: 根据排查结果修复**

可能原因：
- tokenizer 把 `class` 误识别为 `CLASS_NAME`（检查 KEYWORDS 表）
- resolver 从内部类 ClassNode 提取了 classname_id
- 导出层 `_function_to_dict` 引用了错误的 classname_id

- [ ] **Step 4: 提交**

```bash
git add addons/gdscript_util/gds_parser.gd
git commit -m "fix: class_name misidentification — internal class not leaking to file-level"
```

---

## Task 4: 验收

- [ ] **Step 1: 导出 codegraph.json** — 确认调用边的 `line` 非 0
- [ ] **Step 2: parser_edge_cases.gd** — 确认 `class_name` 为空
- [ ] **Step 3: player.gd** — 确认 `class_name: "Player"` 仍正确
- [ ] **Step 4: Test 1-15 全 PASS**
- [ ] **Step 5: 移除 debug 打印**

---

## 完成检查清单

- [ ] _parse_atom 简单节点填 .line（7 处）
- [ ] _parse_atom 复合节点填 .line（6 处）
- [ ] _parse_expression 运算节点填 .line（6 处）
- [ ] class_name 误判排查 + 修复
- [ ] codegraph.json line 非 0
- [ ] Test 1-15 全 PASS
