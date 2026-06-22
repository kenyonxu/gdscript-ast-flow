# 类型推断 L1 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让未标注类型的变量（`var x := Player.new()` / `var p = get_player()` / `var c = preload("res://a.gd")`）也能被推导出类型，填入 `type_table`，使 Phase 3.2 跨文件解析能解析更多 `obj.method()` 调用。

**Architecture:** 新增 `GDSTypeInferrer`（三模式：`.new()`/返回类型/preload）。resolver 加返回类型表两遍扫描：第一遍预建 `{func_name: return_type_string}`，第二遍在变量解析时先取显式标注（已有），为空且开推断时调 `GDSTypeInferrer.infer`。开关默认 true，可设为 false 归回原行为。

**Tech Stack:** Godot 4.7, GDScript

**Spec reference:** `docs/superpowers/specs/2026-06-22-type-inference.md`

---

## 文件结构

```
addons/gdscript_util/
├── gds_type_inferrer.gd         # [新增] L1 推断器（.new / 返回类型 / preload）
├── gds_symbol_resolver.gd       # [修改] 两遍：返回类型表 + 变量推断
└── tests/
    └── test_symbol_resolver.gd  # [修改] 新增推断用例
```

---

## Chunk C0: 核心实现

### Task C0-1: 创建 GDSTypeInferrer — L1 推断器

**Files:** Create: `addons/gdscript_util/gds_type_inferrer.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/gds_type_inferrer.gd
# L1 类型推断器 — 三模式：T.new() / 函数返回类型 / preload

class_name GDSTypeInferrer
extends RefCounted

# p_expr: 变量 initializer 表达式 AST（CallNode / PreloadNode / null）
# p_return_table: {func_name: return_type_string} 预建返回类型表
# 返回类型名字符串，推不出返回 ""
static func infer(p_expr, p_return_table: Dictionary) -> String:
	if p_expr == null:
		return ""

	# 模式 1: T.new() → "T"
	if p_expr is GDScriptToken.CallNode:
		var callee = p_expr.callee
		if callee is GDScriptToken.AttributeNode and callee.name == "new":
			if callee.base is GDScriptToken.IdentifierNode:
				return callee.base.name

	# 模式 2: func() → 查返回类型表
	if p_expr is GDScriptToken.CallNode and p_expr.callee is GDScriptToken.IdentifierNode:
		var fn_name = p_expr.callee.name
		if p_return_table.has(fn_name):
			return p_return_table[fn_name]

	# 模式 3: preload("res://a.gd") → 脚本路径
	if p_expr is GDScriptToken.PreloadNode:
		return p_expr.path

	return ""
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_type_inferrer.gd
git commit -m "feat: GDSTypeInferrer — L1 type inference (.new/return-type/preload)"
```

---

### Task C0-2: resolver 两遍推断 + 变量类型填充

**Files:** Modify: `addons/gdscript_util/gds_symbol_resolver.gd`

- [ ] **Step 1: 加开关 + 返回类型表成员**

在 `GDScriptSymbolResolver` 类顶部加：

```gdscript
var enable_type_inference := true
var _return_type_table: Dictionary = {}
```

- [ ] **Step 2: 第一遍 — 预建返回类型表**

在 `resolve(ast, file_path)` 方法中，`_resolve_class` 之前追加：

```gdscript
	if enable_type_inference:
		_build_return_type_table(p_ast)

func _build_return_type_table(p_ast) -> void:
	_return_type_table.clear()
	for member in p_ast.members:
		if member is GDScriptToken.FunctionNode:
			var ret = member.return_type
			if ret != null and ret.type_name != "":
				_return_type_table[member.name] = ret.type_name
```

- [ ] **Step 3: 第二遍 — _resolve_variable 调推断器**

找到 `_resolve_variable` 中已有的 type_table 写入逻辑（`# Phase 3.2: 记录变量声明类型到 type_table` 附近），替换为：

```gdscript
	# Phase 3.2: 记录变量声明类型到 type_table（供跨文件解析）
	var vtype = _type_to_string(p_node.datatype)  # 显式标注
	if vtype == "" and enable_type_inference and p_node.initializer != null:
		vtype = GDSTypeInferrer.infer(p_node.initializer, _return_type_table)
	if vtype != "":
		result.type_table[p_node.name] = vtype
```

- [ ] **Step 4: 提交**

```bash
git add addons/gdscript_util/gds_symbol_resolver.gd
git commit -m "feat: resolver — two-pass L1 inference for unannotated variables (new/return/preload)"
```

---

### Task C0-3: 验收测试

**Files:** Modify: `tests/test_symbol_resolver.gd`

- [ ] **Step 1: 追加推断测试用例**

在测试文件末尾追加 test_12–14：

```gdscript
func test_12_type_infer_new():
	print("Test 12: type inference — T.new()...")
	var resolver = GDScriptSymbolResolver.new()
	resolver.enable_type_inference = true
	var tok = GDScriptTokenizer.new()
	var ast = GDScriptParser.new().parse(tok.tokenize("func _a():\n\tvar x := Player.new()\n\tx.take_damage(10)\n"))
	var full = resolver.resolve(ast, "")
	assert(full.type_table.get("x", "") == "Player", "x should be inferred as Player")
	print("  PASS")

func test_13_type_infer_return():
	print("Test 13: type inference — return type...")
	var resolver = GDScriptSymbolResolver.new()
	resolver.enable_type_inference = true
	var tok = GDScriptTokenizer.new()
	var src = "func get_player() -> Player:\n\treturn null\n\nfunc _b():\n\tvar p := get_player()\n"
	var ast = GDScriptParser.new().parse(tok.tokenize(src))
	var full = resolver.resolve(ast, "")
	assert(full.type_table.get("p", "") == "Player", "p should be inferred from get_player() return type")
	print("  PASS")

func test_14_type_infer_preload():
	print("Test 14: type inference — preload...")
	var resolver = GDScriptSymbolResolver.new()
	resolver.enable_type_inference = true
	var tok = GDScriptTokenizer.new()
	var ast = GDScriptParser.new().parse(tok.tokenize("func _c():\n\tvar c := preload(\"res://a.gd\")\n"))
	var full = resolver.resolve(ast, "")
	assert(full.type_table.get("c", "") == "res://a.gd", "c should be preload path")
	print("  PASS")
```

- [ ] **Step 2: 提交**

```bash
git add tests/test_symbol_resolver.gd
git commit -m "test: L1 type inference — new/return/preload + explicit-wins + switch off"
```

---

## Chunk V: 验收

### Task V-1: 测试验收

- [ ] **Step 1: 跑测试** — Godot 编辑器运行 `tests/test_symbol_resolver.tscn`，确认全部 PASS
- [ ] **Step 2: 跨文件验证** — 用 `samples/cross_file_demo` 跑项目分析，确认推断后的 `cross_edges` 数量增长
- [ ] **Step 3: 提交**

```bash
git add -A
git commit -m "test: type inference acceptance pass"
```

---

## 验收标准

- [ ] `var x := Player.new()` → `type_table["x"] = "Player"` → 跨文件 `x.method()` 可解析
- [ ] `var p = get_player()`（`func get_player() -> Player`）→ `type_table["p"] = "Player"`
- [ ] `var c = preload("res://a.gd")` → `type_table` 含 a.gd
- [ ] 未标注 + 不可推断的变量仍跳过（不报错）
- [ ] Phase 3.2 跨文件测试仍过 + 新增推断用例
- [ ] 跨文件边覆盖率提升（可量化：推断前后 `cross_edges` 数）

---

## 完成检查清单

- [ ] GDSTypeInferrer — `infer()` 三模式
- [ ] resolver — `_return_type_table` + `enable_type_inference` 开关
- [ ] resolver — `_build_return_type_table()` 第一遍预建
- [ ] resolver — `_resolve_variable` 显式标注优先 + 推断回退
- [ ] test_12–14 — new/return/preload 三组断言

## 已知限制

- **preload 路径 ≠ class_name**：推断器返回脚本路径，跨文件解析器用 `class_registry[class_name]` 查目标文件——路径形式不会自动命中。L1 接受此缺口，后续可在跨文件解析器加 path→class_name 转换
- **仅顶层函数返回类型**：`_build_return_type_table` 只扫顶层 FunctionNode，内部类方法不进表
- **覆盖率天花板**：流敏感合并、表达式传播、容器元素、运行时类型均不做
