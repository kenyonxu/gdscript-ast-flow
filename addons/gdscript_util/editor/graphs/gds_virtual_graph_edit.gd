# addons/gdscript_util/editor/graphs/gds_virtual_graph_edit.gd
# 虚拟化 GraphEdit — 只实例化视口可见的节点，滚动/缩放动态增删

class_name GDSVirtualGraphEdit
extends GraphEdit

const MAX_NODES := 500
const MARGIN_RATIO := 0.2

var _logical_nodes: Dictionary = {}
var _logical_edges: Array = []
var _rendered: Dictionary = {}
var _dirty := true
var _throttle_timer: Timer = null
var _last_zoom: float = 1.0

func _init() -> void:
	_throttle_timer = Timer.new()
	_throttle_timer.wait_time = 0.05
	_throttle_timer.one_shot = true
	_throttle_timer.timeout.connect(_update_viewport)
	add_child(_throttle_timer)
	scroll_offset_changed.connect(_on_view_changed)
	# zoom 无直接信号，用 _process 轮询

func set_graph(p_nodes: Dictionary, p_edges: Array) -> void:
	for c in _rendered.values():
		c.queue_free()
	_rendered.clear()
	clear_connections()
	_logical_nodes = p_nodes
	_logical_edges = p_edges
	_dirty = true
	_update_viewport()

func _on_view_changed() -> void:
	_throttle_timer.start()

func _process(_delta: float) -> void:
	var current_zoom = zoom
	if not is_equal_approx(current_zoom, _last_zoom):
		_last_zoom = current_zoom
		_dirty = true
	if _dirty:
		_dirty = false
		_update_viewport()

func _update_viewport() -> void:
	var vis = _visible_rect()
	for name in _logical_nodes:
		if _rendered.has(name):
			continue
		var info = _logical_nodes[name]
		if vis.has_point(info.pos):
			_instantiate(name)
	# 收集要释放的节点（避免遍历时修改字典）
	var to_remove: Array = []
	for name in _rendered.keys():
		var node = _rendered[name]
		if not vis.has_point(node.position_offset):
			node.queue_free()
			to_remove.append(name)
	for name in to_remove:
		_rendered.erase(name)
	_connect_visible()

func _visible_rect() -> Rect2:
	var z = zoom
	var origin = scroll_offset / z
	var size = get_viewport_rect().size / z
	return Rect2(origin - size * MARGIN_RATIO, size * (1.0 + MARGIN_RATIO * 2))

func _instantiate(p_name: String) -> void:
	if _rendered.size() >= MAX_NODES:
		return
	var info = _logical_nodes[p_name]
	var gn = GDSGraphNode.new()
	gn.configure(info.kind, info.title, info.subtitle, info.degree, info.get("signature", ""), info.get("location", ""))
	gn.name = info.node_name
	gn.position_offset = info.pos
	if info.has("jump") and not info.jump.file.is_empty():
		gn.set_meta("jump", info.jump)
	# 应用自定义 slot 配置（信号图需要）
	if info.has("slot_config"):
		var sc = info.slot_config
		gn.set_slot(0, true, sc.left[0], sc.left[1], true, sc.right[0], sc.right[1])
	add_child(gn)
	_rendered[p_name] = gn

func _connect_visible() -> void:
	for edge in _logical_edges:
		if _rendered.has(edge[0]) and _rendered.has(edge[1]):
			var from_port = edge[2] if edge.size() > 2 else 0
			var to_port = edge[3] if edge.size() > 3 else 0
			if not is_node_connected(edge[0], from_port, edge[1], to_port):
				connect_node(edge[0], from_port, edge[1], to_port)
