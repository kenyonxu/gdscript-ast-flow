# addons/gdscript_ast/editor/graphs/gds_cross_file_kinds.gd
# Call 图 4 Kind 的 port index 映射 + 配色（单一 source of truth）
# port index 固定：from/to 同 Kind 同 index，保证边色一致（多 port per Kind 机制）

class_name GDSCrossFileKinds
extends RefCounted

# Call 图参与的 4 种跨文件 Kind（SCRIPT_ATTACH 归场景 mode，不含）
const CALL_GRAPH_KINDS := [
	GDSCrossFileEdge.Kind.CALL,
	GDSCrossFileEdge.Kind.INSTANCE,
	GDSCrossFileEdge.Kind.EXTENDS,
	GDSCrossFileEdge.Kind.VARIABLE_ACCESS,
]

# Kind → port index（GraphNode slot 行号，固定映射）
const KIND_PORT := {
	GDSCrossFileEdge.Kind.CALL: 0,
	GDSCrossFileEdge.Kind.INSTANCE: 1,
	GDSCrossFileEdge.Kind.EXTENDS: 2,
	GDSCrossFileEdge.Kind.VARIABLE_ACCESS: 3,
}

# Kind → 边/port 配色
const KIND_COLORS := {
	GDSCrossFileEdge.Kind.CALL: Color.DODGER_BLUE,
	GDSCrossFileEdge.Kind.INSTANCE: Color.ORANGE,
	GDSCrossFileEdge.Kind.EXTENDS: Color.MEDIUM_PURPLE,
	GDSCrossFileEdge.Kind.VARIABLE_ACCESS: Color.CYAN,
}

# Kind → 中文标签（图例）
const KIND_LABELS := {
	GDSCrossFileEdge.Kind.CALL: "调用 CALL",
	GDSCrossFileEdge.Kind.INSTANCE: "实例化 T.new",
	GDSCrossFileEdge.Kind.EXTENDS: "继承 extends",
	GDSCrossFileEdge.Kind.VARIABLE_ACCESS: "字段 obj.field",
}

# 构造某 Kind 的单行 slot（多 port 结构中的一个 slot）
static func make_slot(p_kind: int) -> Dictionary:
	var c = KIND_COLORS.get(p_kind, Color.WHITE)
	return {"li": true, "lt": p_kind, "lc": c, "ri": true, "rt": p_kind, "rc": c}

# 构造多 port slot_config。Godot GraphNode connection port = enabled port 的密集序号
# （非 slot_index），故全 4 Kind slot 都 enabled，密集 0-3 = KIND_PORT，边 port=KIND_PORT 才不越界。
# 注：p_kinds 参数保留兼容，实际总产全 4 Kind slot（全 enabled）。
static func make_slot_config(p_kinds: Array = []) -> Dictionary:
	var slots: Array = []
	for k in CALL_GRAPH_KINDS:
		slots.append(make_slot(k))
	return {"slots": slots}
