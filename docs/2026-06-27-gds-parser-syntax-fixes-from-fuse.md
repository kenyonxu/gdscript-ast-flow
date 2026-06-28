# GDScript Parser 语法修复（来自 Fuse codegen 探索）

**日期:** 2026-06-27
**来源:** Fuse 项目 Stage 6.5 codegen 探索（[project-juicy-godot](https://github.com/kenyonxu/project-juicy-godot)）
**状态:** 已在 Fuse 本地副本验证；待应用到本仓库源码
**关联:** [2026-06-25-gds-parser-syntax-enhancements.md](2026-06-25-gds-parser-syntax-enhancements.md)（前一批 v2.1 语法增强）

---

## 背景

在 Fuse 项目尝试用 gdscript-ast-flow 作为 codegen 后端（扫描 Fuse 组件源码提取属性）时，发现 parser 对 **GDScript 4.x 的三类合法语法**解析失败，fail-soft 导致后续成员丢失、提取为空。

Fuse 组件大量使用这三类语法，属于真实项目常见模式，应当修复。本文档记录三处修复，供同步到本仓库 `addons/gdscript_ast/gds_parser.gd`。

**修复当前状态：** 已在 Fuse 项目的本地副本 `project-juicy-godot/addons/gdscript_ast/gds_parser.gd`（.gitignore，不进远程）验证通过。本仓库源码尚未应用。

---

## 修复 1：限定类型 `Class.NestedType`

**症状：** 解析 `@export var x: BaseVariable.VariableScope = ...` 报 `非预期的令牌: PERIOD`，fail-soft 在类型注解处停止，丢失后续所有成员。

**根因：** `TypeNode.type_name` 是单 `String`，`_parse_type()` 只吃一个 IDENTIFIER，遇到 `.`（限定类型路径）即失败。

**GDScript 合法性：** `Class.NestedEnum` / `Class.NestedType` 是 GDScript 4.x 常见语法（枚举访问、嵌套类类型注解）。

**位置：** `gds_parser.gd` `_parse_type()`（约 587 行）

**Before:**
```gdscript
elif _peek() and _peek().type == GDScriptToken.Type.IDENTIFIER:
	node.type_name = _advance().literal
```

**After:**
```gdscript
elif _peek() and _peek().type == GDScriptToken.Type.IDENTIFIER:
	# 限定类型路径: BaseVariable.VariableScope / Node2D 等
	var parts: Array = [_advance().literal]
	while _peek() and _peek().type == GDScriptToken.Type.PERIOD:
		_advance()  # consume PERIOD
		if _peek() and _peek().type == GDScriptToken.Type.IDENTIFIER:
			parts.append(_advance().literal)
		else:
			break
	var type_str := ""
	for p in parts:
		if type_str != "":
			type_str += "."
		type_str += str(p)
	node.type_name = type_str
```

**设计说明：** 沿用 `TypeNode.type_name: String` 结构（不改 AST 节点），把限定路径拼成 `"BaseVariable.VariableScope"` 存入 type_name。消费方按需 split。低风险，不改节点 schema。

---

## 修复 2：字典等号语法 `{ key = value }`

**症状：** 解析 `properties.append({ name = "Emit Signal", type = TYPE_NIL })` 报 `字典需要 key: value (COMMA)`。

**根因：** `_parse_dictionary()` 用 `_parse_expression()` 解析 key，但 GDScript 等号语法 `{ key = value }` 中，`_parse_expression()` 把 `key = value` **整个当赋值表达式吃掉**（返回 `AssignmentNode`），随后期望 COLON 却遇到 COMMA。

**GDScript 合法性：** GDScript 4.x 字典两种语法：冒号 `{"k": v}` 与等号 `{ key = v }`（标识符 key）。等号语法在 `_get_property_list` 等动态属性声明中极常见。

**位置：** `gds_parser.gd` `_parse_dictionary()`（约 1140 行）

**Before:**
```gdscript
while _peek() and _peek().type != GDScriptToken.Type.TK_EOF:
	var pair = {"key": _parse_expression(), "value": null}
	_expect(GDScriptToken.Type.COLON, "字典需要 key: value")
	pair["value"] = _parse_expression()
	node.pairs.append(pair)
	if not _match(GDScriptToken.Type.COMMA):
		break
```

**After:**
```gdscript
while _peek() and _peek().type != GDScriptToken.Type.TK_EOF:
	var pair = {"key": _parse_expression(), "value": null}
	# GDScript 4.x 等号语法 {key = v}: _parse_expression 把 "key = v" 解析成 AssignmentNode → 拆分
	if pair["key"] is GDScriptToken.AssignmentNode:
		var assign: GDScriptToken.AssignmentNode = pair["key"]
		pair["key"] = assign.target
		pair["value"] = assign.value
	elif _match(GDScriptToken.Type.COLON):
		pair["value"] = _parse_expression()
	else:
		_set_error("字典需要 key: value 或 key = value")
	node.pairs.append(pair)
	if not _match(GDScriptToken.Type.COMMA):
		break
```

**设计说明：** 利用现有 `_parse_expression()` 对赋值的解析能力（返回 AssignmentNode），检测到则拆分为 target/value。兼容冒号与等号两种语法，不改 dict pair 结构。

---

## 修复 3：`static var`（静态变量）

**症状：** 解析 `static var _cached_search_types: Array[String] = []` 报 `static 只能用于函数 (VAR)`。

**根因：** `_parse_class_member()` 的 STATIC 分支只接受 FUNC，遇到 VAR 报错。

**GDScript 合法性：** `static var` 是 GDScript 4.x 的静态实例变量语法（4.0+ 支持），用于类级缓存/单例字段。

**位置：** `gds_parser.gd` `_parse_class_member()` STATIC 分支（约 295 行）

**Before:**
```gdscript
GDScriptToken.Type.STATIC:
	_advance()
	if _peek() and _peek().type == GDScriptToken.Type.FUNC:
		var f = _parse_function([])
		f.is_static = true
		return f
	_set_error("static 只能用于函数")
	return null
```

**After:**
```gdscript
GDScriptToken.Type.STATIC:
	_advance()
	var _st = _peek()
	if _st and _st.type == GDScriptToken.Type.FUNC:
		var f = _parse_function([])
		f.is_static = true
		return f
	elif _st and _st.type == GDScriptToken.Type.VAR:
		# static var (GDScript 4.x 静态变量) — 当普通变量解析
		return _parse_variable([])
	_set_error("static 只能用于函数或变量")
	return null
```

**设计说明：** `VariableNode` 当前无 `is_static` 字段，static var 当普通变量解析（丢失 static 标记）。消费方（如 call_graph/def_use）若需区分 static var，后续可给 `VariableNode` 加 `is_static: bool`。当前最小修复让 parser 不报错、能继续解析后续成员。

---

## 验证

在 Fuse 本地副本验证（Fuse Stage 6.5 codegen dry-run）：

| 组件 | 涉及语法 | 修复前 | 修复后 |
|---|---|---|---|
| `set_int_variable.gd` | 限定类型 `BaseVariable.VariableScope` | fail-soft，漏 from_variable + condition | 完整提取 6 个 @export + mode/condition |
| `emit_signal.gd` | 字典等号 `{ name = "x" }` | fail-soft，提取空 | 解析通过 |
| `find_node.gd` | `static var _cached_*` | fail-soft，提取空 | 解析通过 |

---

## 建议应用

1. 把三处 After 代码应用到本仓库 `addons/gdscript_ast/gds_parser.gd` 对应位置
2. 跑 `tests/test_parser.gd` 等验收测试确认无回归
3. 考虑给 `VariableNode` 加 `is_static` 字段以精确记录 static var（当前修复丢弃该标记）
4. 考虑给 `TypeNode` 加 `type_path: Array[String]` 替代拼字符串（当前修复用 type_name 拼 `.`，消费方需 split）

修复均向后兼容（仅扩展解析能力，不改现有 AST schema），回归风险低。
