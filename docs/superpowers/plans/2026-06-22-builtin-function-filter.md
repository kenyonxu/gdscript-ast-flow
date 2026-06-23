# 内置函数过滤 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** resolver 不再为 `print()`/`range()`/`push_error()` 等 GDScript 内置函数生成调用边或累加度数，同时保留前向引用（未声明的用户函数）的边与度数。

**Architecture:** `_resolve_call` 隐式调用分支（模式 1b）追加内置名查表：`sym == null` 时查 `GDSBuiltinFunctions.is_builtin(callee_name)`，命中跳过记边。新增 `GDSBuiltinFunctions` 常量表（80 项 @GlobalScope 函数），resolver 加 `filter_builtin_calls` 开关（默认 true）。

**Tech Stack:** Godot 4.7, GDScript

**Spec reference:** `docs/superpowers/specs/2026-06-22-builtin-function-filter.md`

---

## 文件结构

```
addons/gdscript_util/
├── gds_builtin_functions.gd     # [新增] 80 项内置函数名表 + is_builtin
├── gds_symbol_resolver.gd       # [修改] _resolve_call 模式 1b 过滤内置
└── tests/
    └── test_symbol_resolver.gd  # [修改] 新增 test_11_builtin_filter
```

---

## Chunk C0: 核心实现

### Task C0-1: 创建 GDSBuiltinFunctions — 内置函数名表

**Files:** Create: `addons/gdscript_util/gds_builtin_functions.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/gds_builtin_functions.gd
# GDScript 4.7 内置全局函数名表 — 供 resolver 过滤非用户调用噪声
# 来源: Godot 源码 modules/gdscript/gdscript_utility_functions.cpp + @GlobalScope 文档

class_name GDSBuiltinFunctions
extends RefCounted

const NAMES := {
	# 输出
	"print": true, "print_rich": true, "printerr": true, "printraw": true,
	"push_error": true, "push_warning": true,
	# 数学
	"abs": true, "absf": true, "absi": true,
	"acos": true, "asin": true, "atan": true, "atan2": true,
	"ceil": true, "ceilf": true, "ceili": true,
	"clamp": true, "clampf": true, "clampi": true,
	"cos": true, "cosh": true, "sin": true, "sinh": true, "tan": true, "tanh": true,
	"exp": true, "floor": true, "floorf": true, "floori": true,
	"fmod": true, "fposmod": true,
	"is_equal_approx": true, "is_finite": true, "is_inf": true, "is_nan": true,
	"is_zero_approx": true,
	"lerp": true, "lerpf": true,
	"log": true, "max": true, "min": true, "move_toward": true,
	"pow": true, "round": true, "roundf": true, "roundi": true,
	"sign": true, "signf": true, "signi": true,
	"snapped": true, "snappedf": true, "snappedi": true,
	"sqrt": true,
	"wrap": true, "wrapf": true, "wrapi": true,
	# 集合/转换
	"range": true, "len": true, "str": true,
	"var_to_str": true, "str_to_var": true,
	"bytes_to_var": true, "var_to_bytes": true,
	"type_string": true,
	# 反射
	"typeof": true, "type_exists": true, "is_instance_of": true,
	"get_stack": true, "instance_from_id": true,
}

static func is_builtin(p_name: String) -> bool:
	return NAMES.has(p_name)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_builtin_functions.gd
git commit -m "feat: GDSBuiltinFunctions — 80 GDScript builtin function names for noise filtering"
```

---

### Task C0-2: resolver 过滤内置函数

**Files:** Modify: `addons/gdscript_util/gds_symbol_resolver.gd`

在 `_resolve_call` 的模式 1b（隐式 self 调用，`sym == null` 分支）中，追加内置名查表。同时添加 `filter_builtin_calls` 开关。

- [ ] **Step 1: 添加开关成员**

在 `GDScriptSymbolResolver` 类顶部加：

```gdscript
# Phase 3.4: 内置函数过滤开关（默认 true；调试时可设 false 看全量调用图）
var filter_builtin_calls := true
```

- [ ] **Step 2: 修改 _resolve_call 模式 1b**

将当前模式 1b（`sym == null or sym.kind == FUNCTION` 记边）拆成三步：

**当前代码**（Phase 2 forward-ref 修后）：
```gdscript
		# 1b: 隐式 self 调用 foo()
		var sym = p_scope.resolve(callee.name)
		if sym == null or sym.kind == GDScriptSymbol.Kind.FUNCTION:
			_add_call_edge(p_current_function, callee.name, callee.line, GDScriptCallEdge.CallType.SELF, "", p_node.arguments)
```

**改为**：
```gdscript
		# 1b: 隐式 self 调用 foo()
		var sym = p_scope.resolve(callee.name)
		if sym != null and sym.kind == GDScriptSymbol.Kind.FUNCTION:
			# 已声明的用户函数 → 记边（不变）
			_add_call_edge(p_current_function, callee.name, callee.line, GDScriptCallEdge.CallType.SELF, "", p_node.arguments)
		elif sym == null:
			# 未解析 — 可能是内置函数或前向引用
			if not (filter_builtin_calls and GDSBuiltinFunctions.is_builtin(callee.name)):
				# 非内置 → 前向引用，记边
				_add_call_edge(p_current_function, callee.name, callee.line, GDScriptCallEdge.CallType.SELF, "", p_node.arguments)
			# 内置 → 不记边、不计度数
```

- [ ] **Step 3: 确保已声明函数分支不受影响**

模式 1b 的前一个分支（`sym != null and FUNC`）保留原逻辑不动——已声明用户函数调用正常记边。

- [ ] **Step 4: 提交**

```bash
git add addons/gdscript_util/gds_symbol_resolver.gd
git commit -m "feat: resolver — filter builtin function calls (print/range/…) via GDSBuiltinFunctions"
```

---

### Task C0-3: 验收测试

**Files:** Modify: `tests/test_symbol_resolver.gd`

- [ ] **Step 1: 追加 test_11_builtin_filter**

在测试文件末尾追加：

```gdscript
func test_11_builtin_filter():
	print("Test 11: builtin function filter...")
	var resolver = GDScriptSymbolResolver.new()

	# 1. filter ON: print/range 不记边
	resolver.filter_builtin_calls = true
	var tok = GDScriptTokenizer.new()
	var ast = GDScriptParser.new().parse(tok.tokenize("func _a():\n\tprint(\"x\")\n\trange(5)\n"))
	var full = resolver.resolve(ast, "")
	assert(full.call_graph.edges.is_empty(), "with filter ON, print/range should produce no edges")
	assert(full.call_in_degree.get("print", 0) == 0, "print in-degree should be 0")
	assert(full.call_out_degree.get("_a", 0) == 0, "_a out-degree should be 0")

	# 2. 前向引用（未声明的用户函数）仍记边
	resolver.filter_builtin_calls = true
	var tok2 = GDScriptTokenizer.new()
	var ast2 = GDScriptParser.new().parse(tok2.tokenize("func _b():\n\thelper()\n"))
	var full2 = resolver.resolve(ast2, "")
	assert(full2.call_graph.edges.size() >= 1, "forward ref helper() should produce an edge")
	assert(full2.call_in_degree.get("helper", 0) >= 1, "helper in-degree should be >=1")

	# 3. filter OFF: print 记边（回归验证）
	resolver.filter_builtin_calls = false
	var tok3 = GDScriptTokenizer.new()
	var ast3 = GDScriptParser.new().parse(tok3.tokenize("func _c():\n\tprint(\"x\")\n"))
	var full3 = resolver.resolve(ast3, "")
	assert(full3.call_graph.edges.size() >= 1, "with filter OFF, print should produce an edge")
	assert(full3.call_in_degree.get("print", 0) >= 1, "print in-degree should be >=1 with filter OFF")
	print("  PASS")
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/tests/test_symbol_resolver.gd
git commit -m "test: test_11_builtin_filter — builtin calls produce no CallEdge/degree; forward refs retained"
```

---

## Chunk V: 验收

### Task V-1: 验收

- [ ] **Step 1: 跑测试** — 在 Godot 编辑器运行 `tests/test_symbol_resolver.tscn`，确认 Test 1–11 全部 PASS（含 test_11 PASS）
- [ ] **Step 2: 真实样本回归** — 对项目内任一含大量 `print`/`range` 的脚本跑分析，确认：
  - 调用图节点中不再出现 `print` / `range` 节点
  - `print` 不再是高入度"枢纽"（橙红高亮消失）
  - 用户定义的 `foo()` / `_ready()` 调用边与度数不变
- [ ] **Step 3: 开关验证** — 临时在 analyzer/bridge 处置 `resolver.filter_builtin_calls = false`，确认内置边回归（验证后还原）
- [ ] **Step 4: 提交（若有文档/小修）**

```bash
git add -A
git commit -m "test: builtin-function-filter acceptance pass"
```

---

## 验收标准（对照 spec 第六节）

- [x] `print(...)`/`range(...)` 不产生 CallEdge、不计度数（Task C0-2 实现 + C0-3 断言）
- [x] 用户函数（未声明/前向引用）仍记边（`helper` 断言）
- [x] 已声明用户函数调用不受影响（`sym != null and FUNCTION` 分支保留）
- [x] Phase 2 回归测试全过（Task V-1 Step 1，Test 1–11 PASS）
- [x] 调用图节点数减少、`print` 枢纽噪声消失（Task V-1 Step 2）

---

## 完成检查清单

C0:
- [x] GDSBuiltinFunctions — 80 项名表 + `is_builtin`
- [x] resolver — `filter_builtin_calls` 开关（默认 true）
- [x] resolver — 模式 1b：已声明用户函数记边 / 未声明且非内置记边 / 内置跳过
- [x] test_11_builtin_filter — 4 组断言（内置无边/度、前向引用保留、helper 无 callee、开关 OFF 回归）

V:
- [x] Test 1–11 全 PASS
- [x] 真实样本无 `print`/`range` 节点、度数失真消除
- [x] 开关 OFF 时内置边回归

## 已知限制 / 风险（对照 spec 第七节）

- **用户 shadow 内置**（自定义 `func print(...)`）：`sym != null` → 按用户函数记边，不查内置表，符合预期
- **名表不全**：顶多多记几条边，不致命；后续可按 Godot 版本更新 `NAMES`
- **仅过滤裸调用**：`obj.print()` 属性形式（模式 2f，`EXTERNAL`）不在范围内，按 spec「不做」保留
