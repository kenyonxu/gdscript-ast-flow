# 场景 instance 子场景展开 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: 使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 按任务逐个实现。步骤用 `- [ ]` 复选框跟踪。

**Goal:** instance 子场景（`instance=ExtResource(...)`）递归展开 + 节点详情标注，让 instance 化场景（demo `tutorial_*.tscn` instance `agent_base.tscn`）节点树完整显示——子场景节点（HitBox）+ 覆盖节点（LegL）+ instance 节点 type/script 继承。

**Architecture:** `SceneNodeData` 加 `instance_resource` 字段；`_parse_node` 提取 `instance=`；`_build_node_tree` 后置 instance 展开（递归 parse 子场景 + 合并 children + 覆盖节点挂载）；详情 UI 标注 instance。

**Tech Stack:** Godot 4.7 GDScript，复用 `GDScriptTscnParser` 递归 + `_uid_map`。
**SPEC:** [tscn spec P2 #15](../specs/2026-06-25-tscn-tres-parser-spec.md) + 本 plan 新增 A（instance 标注）
**状态:** ✅ PLAN 完成（2026-06-26）

---

## 问题来源（demo 验证）

`tutorial_01_welcome.tscn`:
```
[node name="TutorialWelcome" instance=ExtResource("1_2vrmp")]   ← instance agent_base.tscn
[node name="LegL" parent="Root/Rig" ...]                        ← 覆盖子场景内 Root/Rig/LegL
[node name="BTPlayer" type="BTPlayer" parent="."]
```
当前：TutorialWelcome type/script 空、LegL 找不到父（Root 在 agent_base.tscn）散落、HitBox（在 agent_base.tscn）不显示。

---

## File Structure

**改动**：
- `addons/gdscript_ast/gds_scene_resource_result.gd` — `SceneNodeData` 加 `instance_resource` 字段 + to_dict
- `addons/gdscript_ast/gds_tscn_parser.gd` — `_parse_node` 提取 `instance=`；新增 `_expand_instances` 递归展开 + 覆盖节点合并 + 环检测
- `addons/gdscript_ast/editor/scene/scene_node_tree_view.gd` — 节点详情标注「子场景实例 →」

**测试**：扩展 `tests/test_tscn_tres_parser.gd` + 新 fixture `test_scene_instance.tscn`（instance 子场景 + 覆盖节点）

---

## Chunk A: instance 数据层 + 详情标注

### Task A1: SceneNodeData 加 instance_resource 字段
**Files:** Modify `gds_scene_resource_result.gd`
- [ ] `SceneNodeData` 加字段：
```gdscript
var instance_resource: String = ""  # instance=ExtResource(...) 指向的子场景路径
```
- [ ] `to_dict` 输出 `instance`（子场景路径或空）。
- [ ] `is_instance()` 便捷方法：`return instance_resource != ""`

### Task A2: _parse_node 提取 instance=
**Files:** Modify `gds_tscn_parser.gd::_parse_node`
- [ ] header 解析 `instance=ExtResource("id")`：
```gdscript
if params.has("instance"):
	var ref = _resolve_ext_resource_ref(params["instance"])
	if ref != null and ref.type == "PackedScene":
		node.instance_resource = ref.path  # 子场景 .tscn 路径
```
- [ ] **测试** `test_instance_extract`：解析 `test_scene_instance.tscn` → 根节点 `instance_resource == "res://tests/fixtures/test_sub_scene.tscn"`。

### Task A3: 节点详情标注 instance（UI）
**Files:** Modify `scene_node_tree_view.gd` 节点详情区
- [ ] 选中 instance 节点时，详情显示「**子场景实例 →** `<instance_resource>`」（可点击跳子场景）而非空白 type/script。
- [ ] Tree 中 instance 节点标 📦 图标（区分直接节点）。
- [ ] 手动验收：tutorial_01 的 TutorialWelcome 详情显示「子场景实例 → res://demo/agents/agent_base.tscn」。

---

## Chunk B: 递归展开子场景（#15 核心）

### Task B1: _expand_instances 入口
**Files:** Modify `gds_tscn_parser.gd`
- [ ] `parse` 末尾（_build_node_tree 后）调 `_expand_instances(result, {})`（visited set 防环）。
- [ ] `_expand_instances` 遍历所有节点，对 `is_instance()` 的节点调 `_expand_one(node, visited)`。

### Task B2: _expand_one 单节点展开
- [ ] instance 节点递归 parse 子场景：
```gdscript
func _expand_one(p_node, p_visited) -> void:
	if p_visited.has(p_node.instance_resource):
		# 环 → 标记，不递归
		p_node.properties["_circular_instance"] = p_node.instance_resource
		return
	if p_visited.size() >= 16:  # 深度兜底
		return
	p_visited[p_node.instance_resource] = true
	var sub_parser = GDScriptTscnParser.new()
	sub_parser.set_uid_map(_uid_map)
	var sub_result = sub_parser.parse(p_node.instance_resource)
	if sub_result == null or sub_result.root_nodes.is_empty():
		return
	# instance 节点继承子场景根的 type/script
	var sub_root = sub_result.root_nodes[0]
	if p_node.type == "": p_node.type = sub_root.type
	if p_node.script_resource == "": p_node.script_resource = sub_root.script_resource
	# 子场景根的 children → instance 节点的 children
	p_node.children = sub_root.children
	# 子场景 nodes_flat 合并进本场景（带前缀防冲突）+ 更新 parent_path
	_merge_sub_flat(p_node, sub_result, p_visited)
```
- [ ] 子场景内若再含 instance，递归展开（sub_parser.parse 已调 _expand_instances）。
- [ ] **测试** `test_instance_expand`：fixture instance 子场景后，根节点 type/script 继承子场景根 + children 含子场景节点。

---

## Chunk C: 覆盖节点合并

### Task C1: 覆盖节点挂展开树
- [ ] 展开子场景后，子场景节点进 `nodes_flat`（key 带前缀如 `<instance>/Root/Rig`）。本 .tscn 覆盖节点（`parent="Root/Rig"`）按相对路径挂到展开树的 Root/Rig：
```gdscript
# 展开后重跑覆盖节点挂载
for path in _nodes:
	var node = _nodes[path]
	if not node.is_instance() and not node.parent_path in [".", ""]:
		var parent = _find_in_expanded_tree(node.parent_path)
		if parent:
			parent.children.append(node)
```
- [ ] `_find_in_expanded_tree`：在展开后的节点树（含子场景节点）按 NodePath 查找。
- [ ] **测试** `test_override_attach`：fixture 覆盖节点（parent 指子场景路径）展开后挂到子场景对应节点下。

---

## Chunk D: 验收

### Task D1: 测试套
- [ ] `test_scene_instance.tscn` fixture：instance 一个含 HitBox + Rig 的子场景 + 覆盖 Rig/LegL。
- [ ] 测试：`test_instance_extract` / `test_instance_expand`（type/script 继承 + children 含子场景节点）/ `test_override_attach`（覆盖节点挂载）/ `test_instance_cycle`（环检测不无限递归）。

### Task D2: demo 真实验证
- [ ] 重扫 demo，解析 `tutorial_01_welcome.tscn`：TutorialWelcome type/script 继承 agent_base、children 含 Root/HitBox/Hurtbox（子场景）+ LegL/Body（覆盖）+ BTPlayer（直接）。
- [ ] 编辑器场景模式选 tutorial_01 → 节点树完整显示。

---

## 集成检查点

```
GDScriptTscnParser.parse(file)
 ├─ _read_sections + _parse_*（含 _parse_node 提取 instance=）  ← A2
 ├─ _build_node_tree（节点树）                                   ← 现有
 └─ _expand_instances(result, visited={})                        ← B1
     └─ _expand_one(node)                                        ← B2
         ├─ sub_parser.parse(子场景)  → 递归（sub 内又 _expand_instances）
         ├─ instance 节点继承子场景根 type/script + children
         └─ _merge_sub_flat + 覆盖节点挂载                       ← C1
详情 UI：is_instance → 「子场景实例 → <path>」+ 📦               ← A3
```

## 跑测命令（headless，Godot 4.7）

```bash
"E:/Godot/Godot_v4.7-stable_mono_win64/Godot_v4.7-stable_mono_win64_console.exe" \
  --headless --path "e:/GitHub/gdscript-ast-flow" \
  --quit "res://tests/test_tscn_tres_parser.tscn"
```

## 验收标准

- [ ] instance 节点提取 instance_resource（A2）
- [ ] 详情标注「子场景实例 →」+ 📦 图标（A3）
- [ ] instance 展开：type/script 继承子场景根 + children 含子场景节点（B2）
- [ ] 覆盖节点（parent 指子场景路径）挂展开树（C1）
- [ ] 环检测：A instance B instance A 不无限递归（B2 visited）
- [ ] demo tutorial_01 节点树完整（TutorialWelcome → Root/HitBox + LegL 覆盖 + BTPlayer）（D2）

## 风险

| 风险 | 缓解 |
|------|------|
| 子场景路径在 _uid_map 缺（uid-only）| _expand_one 失败时跳过（保留 instance_resource 标注，不展开）|
| 覆盖节点 parent 路径与展开树不匹配 | _find_in_expanded_tree 多策略匹配（精确 → 按名字）|
| 递归深度爆炸（长 instance 链）| visited + 深度上限 16 |
| 覆盖节点属性合并（Godot 覆盖语义）| MVP 只挂节点，属性合并留后续 |
