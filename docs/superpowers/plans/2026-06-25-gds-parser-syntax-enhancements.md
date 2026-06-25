# gds_parser 表达式 + 词法覆盖增强 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: 使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 按任务逐个实现。步骤用 `- [ ]` 复选框跟踪。

**Goal:** 补齐 GDScript 解析器的**表达式后缀 + 词法覆盖 + 错误恢复**，让"分析别人作品"用例能解析真实项目（demo 4 错 + 插件自身 bridge.gd）。

**Architecture:** 改 `gds_tokenizer`（词法）+ `gds_parser`（表达式后缀 + 错误恢复兜底）。**无新数据模型**——纯语法层覆盖。

**Tech Stack:** Godot 4.7 GDScript，自研 tokenizer + 递归下降 parser。

**来源:** demo + addons 扫描错误清单（2026-06-25）。无独立 spec——GDScript 4 语法即规范。
**状态:** ✅ PLAN 完成（2026-06-25）

---

## 错误清单（扫描来源）

| # | 错误 | 触发文件/行 | Chunk |
|---|------|------------|-------|
| 1 | **parse 死循环**（错误恢复失效） | `plugin.gd` 等卡死，扫描挂起 | A |
| 2 | **`%NodeName` 场景唯一节点** | demo/scenes/game.gd:32、showcase.gd:14 | C |
| 3 | **if/elif/while 条件含方法调用/成员访问** | bridge.gd:142 `elif p_path.ends_with(...)` | B |
| 4 | **`extends "res://path"` 字符串路径** | demo/agents/player/player.gd:11 | C |
| 5 | **`;` 分号语句分隔** | demo/agents/scripts/agent_base.gd:66 | C |

> tokenizer 已产 PERCENT/SEMICOLON token（错误信息的 `token: PERCENT/SEMICOLON` 证实）——是 parser 不认，非 tokenizer 不产。

---

## File Structure

**改动**：
- `addons/gdscript_ast/gds_tokenizer.gd` — `%` token（若缺）、`extends` 后字符串
- `addons/gdscript_ast/gds_parser.gd` — 表达式后缀（`.`/`(`/`[`）+ 错误恢复兜底 + primary 识别 `%Node` + 语句跳 `;` + extends 字符串

**测试**：新建 `tests/test_gds_parser_syntax.gd` + `.tscn`
**Fixtures**：从 demo 提取**最小语法片段**（非整文件，避免依赖 demo）放 `tests/fixtures/syntax/`：
- `method_call_condition.gd`（`if a.b():` / `elif x.y():`）
- `scene_unique_node.gd`（`%NodeName` 成员访问）
- `extends_string.gd`（`extends "res://path.gd"`）
- `semicolon.gd`（`var a = 1; var b = 2`）
- `dead_loop.gd`（含现不支持语法，验证不卡死）

---

## Chunk A: parse 错误恢复（🔴 阻塞，先修）

> plugin.gd 等文件含现不支持语法时，parser 死循环（错误恢复失效），扫描挂起。必须先修，否则无法完整扫任何项目。

### Task A1: 错误恢复兜底
**Files:** Modify `gds_parser.gd`（`_parse_statement` / `_parse_class_member` / `_parse_block` 的错误恢复路径）
- [ ] 现有 `_parse_statement` 行 613 注释提到"返回 null 且未消费 token 时强制推进"，但失效。修：解析失败 + `_peek() == 起始 token`（未消费）→ `_set_error(...)` + **强制 `_advance()`** + 返回错误节点，绝不原地踏步。
- [ ] 加循环保护：`parse()` 主循环记录已消费 token 数，若一轮未推进则强制 advance（防任何漏网的死循环）。
```gdscript
# parse() 主循环兜底
var consumed_before = pos
var stmt = _parse_statement()
if pos == consumed_before and stmt == null:
	# 未消费任何 token 却返回 null → 强制推进，避免死循环
	_set_error("无法恢复的语句，跳过 token: %s" % _peek().get_name())
	_advance()
```
- [ ] **测试** `test_no_dead_loop`：解析 `dead_loop.gd`（含现不支持语法）在 <5s 内返回（不死循环），AST 带 error 但函数返回。

---

## Chunk B: 表达式后缀（🔴 解决 #3）

> 一次性解决 if/elif/while/match 条件 + 赋值右侧 + return 等所有表达式位置的 `a.b` / `a.b()` / `a[b]`。

### Task B1: 后缀循环（`.` 成员访问 / `(` 调用 / `[` 索引）
**Files:** Modify `gds_parser.gd::_parse_expression`（或 primary 层）
- [ ] 解析 primary（标识符/字面量/括号）后，**循环消费后缀**直到无后缀：
```gdscript
# primary 解析后
while true:
	var t = _peek()
	if t.type == GDScriptToken.Type.PERIOD:  # a.b
		_advance()
		var member = _advance()  # 标识符
		left = MemberAccessNode.new(left, member.value)
	elif t.type == GDScriptToken.Type.PAREN_OPEN:  # a(...) / a.b(...)
		var args = _parse_call_args()
		left = CallNode.new(left, args)
	elif t.type == GDScriptToken.Type.BRACKET_OPEN:  # a[...]
		_advance()
		var index = _parse_expression()
		_consume(BRACKET_CLOSE)
		left = IndexNode.new(left, index)
	else:
		break
```
- [ ] 若 AST 节点类型缺（MemberAccessNode/CallNode/IndexNode），在 `gds_ast_nodes.gd` 补（最小字段）。
- [ ] **测试**：
  - `test_method_call_condition`：`if a.b():` / `elif x.y():` 解析为 IfNode，条件是 CallNode
  - `test_member_chain`：`var x = a.b.c` 解析为嵌套 MemberAccessNode
  - `test_index`：`a[0]`、`a[i]` 解析为 IndexNode

---

## Chunk C: 词法/语法覆盖（🟡🟢 #2 #4 #5）

### Task C1: `%NodeName` 场景唯一节点（#2）
**Files:** `gds_tokenizer.gd` + `gds_parser.gd`
- [ ] tokenizer：`%` 后跟标识符 → 产 PERCENT token（若已有则确认）；parser primary 识别 `PERCENT IDENTIFIER` → SceneUniqueNode（场景唯一节点访问）。
- [ ] **测试** `test_scene_unique_node`：`%HealthBar.value = 100` 解析正确。

### Task C2: `;` 分号语句分隔（#5）
**Files:** `gds_parser.gd`（语句层）
- [ ] tokenizer 已产 SEMICOLON；parser `_parse_statement` / `_parse_block` 跳过分号（一行多语句 `var a = 1; var b = 2`）。
- [ ] **测试** `test_semicolon`：`var a = 1; var b = 2` 解析为两条变量声明。

### Task C3: `extends "res://path"` 字符串路径（#4）
**Files:** `gds_parser.gd`（extends 解析）
- [ ] extends 后当前期望类名标识符；改为接受**字符串字面量**（`extends "res://..."`）→ extends_path 存字符串值。
- [ ] **测试** `test_extends_string`：`extends "res://path/to/base.gd"` 解析正确，extends_path == "res://path/to/base.gd"。

---

## Chunk D: 验收

### Task D1: 测试套 + 重扫 demo
- [ ] `tests/test_gds_parser_syntax.gd`（8 套）：no_dead_loop / method_call_condition / member_chain / index / scene_unique_node / semicolon / extends_string + 重扫 demo 确认 0 错误。
- [ ] headless 跑全绿（命令见下）。

### Task D2: 重扫 demo + addons 确认
- [ ] 用临时扫描脚本（或 ScanConfig）重扫 demo + addons，确认 demo 4 错全消失、addons 不卡死。

---

## 集成检查点

```
GDScript 源码
 → GDScriptTokenizer  ← C1: % NodeName token（若缺）
 → GDScriptParser
    ├─ _parse_expression ← B1: 后缀循环（. / ( / [）
    │   └─ primary ← C1: %Node 识别
    ├─ _parse_statement ← C2: 跳 ; 分号
    ├─ extends 解析 ← C3: 字符串路径
    ├─ if/elif/while 条件 ← B1（复用表达式后缀）
    └─ 错误恢复 ← A1: 死循环兜底
 → GDScriptAnalysisResult（数据层不变）
```

## 跑测命令（headless，Godot 4.7）

```bash
"E:/Godot/Godot_v4.7-stable_mono_win64/Godot_v4.7-stable_mono_win64_console.exe" \
  --headless --path "e:/GitHub/gdscript-ast-flow" \
  --quit "res://tests/test_gds_parser_syntax.tscn"
```

## 验收标准

- [ ] plugin.gd 解析不死循环（A1）
- [ ] `if a.b():` / `elif x.y():` 条件解析（B1）
- [ ] `a.b.c` 成员链 + `a[0]` 索引（B1）
- [ ] `%NodeName` 场景唯一节点（C1）
- [ ] `;` 分号一行多语句（C2）
- [ ] `extends "res://..."` 字符串路径（C3）
- [ ] 重扫 demo：4 错全消失（D2）
- [ ] 重扫 addons：bridge.gd:142 不报错、plugin.gd 不卡死（D2）
