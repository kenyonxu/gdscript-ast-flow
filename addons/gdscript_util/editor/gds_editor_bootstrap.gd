# addons/gdscript_util/editor/gds_editor_bootstrap.gd
# 模块化启动 — 将 plugin.gd 的 Phase 3 初始化拆分为独立类
# 参考: project-juicy-godot/addons/fuse/editor/bootstrap/fuse_editor_bootstrap.gd

class_name GDSEditorBootstrap
extends RefCounted

var _plugin: EditorPlugin = null
var _l10n: GDSL10n = null
var _bridge: GDSAnalysisBridge = null
var _main_panel: GDSAnalysisMainPanel = null
var _analysis_queued: String = ""  # 待分析路径（非空表示有待执行）
var _is_analyzing: bool = false    # 重入保护
var _graph_main_screen: GDSGraphMainScreen = null  # Phase 3.3: 主屏 tab
var _focus_timer: Timer = null              # 轮询当前脚本焦点
var _last_script_path: String = ""          # 上次分析的脚本路径（用于检测切换）

func setup(p_plugin: EditorPlugin, p_l10n: GDSL10n = null) -> void:
	_plugin = p_plugin
	_l10n = p_l10n if p_l10n else GDSL10n.new()
	_bridge = GDSAnalysisBridge.new()

	# 底部面板 — 含 4 个子 tab（Summary / Call Graph / Signal Flow / Def-Use）
	_main_panel = GDSAnalysisMainPanel.new()
	_main_panel.setup(_bridge, _l10n)
	_plugin.add_control_to_bottom_panel(_main_panel, "GDScript Analysis")

	_plugin.resource_saved.connect(_on_resource_saved)

	# 迁移旧格式配置（Array<Dictionary> → PackedStringArray）
	GDSScanConfig.migrate_if_needed()

	# Phase 3.2: 首次启动 deferred 全量项目分析
	call_deferred("_initial_project_scan")

	# Phase 3.3: 注册主屏 tab
	_graph_main_screen = GDSGraphMainScreen.new()
	_graph_main_screen.setup(_bridge, _l10n)
	EditorInterface.get_editor_main_screen().add_child(_graph_main_screen)
	_graph_main_screen.visible = false  # 默认隐藏，切到 Analysis tab 才显示

	# 焦点跟随: 500ms 轮询当前脚本，切换时自动分析（双击打开/切 Tab 即触发，无需 save）
	_focus_timer = Timer.new()
	_focus_timer.wait_time = 0.5
	_focus_timer.autostart = true
	_focus_timer.timeout.connect(_on_focus_tick)
	_plugin.add_child(_focus_timer)

func teardown() -> void:
	if _plugin.resource_saved.is_connected(_on_resource_saved):
		_plugin.resource_saved.disconnect(_on_resource_saved)

	if _focus_timer and is_instance_valid(_focus_timer):
		_focus_timer.stop()
		_focus_timer.queue_free()

	if _main_panel and is_instance_valid(_main_panel):
		_plugin.remove_control_from_bottom_panel(_main_panel)
		_main_panel.queue_free()

	if _graph_main_screen and is_instance_valid(_graph_main_screen):
		_graph_main_screen.queue_free()

func _on_resource_saved(resource: Resource) -> void:
	if resource is GDScript and resource.resource_path.ends_with(".gd"):
		# 不在 save 回调里同步跑重活（会阻塞编辑器）—— 延迟到下一帧
		# 连续保存只保留最后一次目标（去抖）
		_analysis_queued = resource.resource_path
		if not _is_analyzing:
			call_deferred("_run_queued_analysis")

func _run_queued_analysis() -> void:
	if _analysis_queued == "":
		return
	_is_analyzing = true
	var path = _analysis_queued
	_analysis_queued = ""
	_bridge.run_analysis(path)
	# Phase 3.2 增量: 若已有项目结果且扫描开启，重分析该文件 + 重解析跨文件边
	if GDSScanConfig.is_enabled():
		_bridge.refresh_file_in_project(path)
	_is_analyzing = false
	# 若期间又有新保存请求，继续处理
	if _analysis_queued != "":
		call_deferred("_run_queued_analysis")

func set_main_screen_visible(p_visible: bool) -> void:
	if _graph_main_screen and is_instance_valid(_graph_main_screen):
		_graph_main_screen.visible = p_visible
		if p_visible:
			_graph_main_screen._rebuild()
			# 切到 Analysis tab 时自动整理布局（deferred 等 GraphEdit 节点就绪）
			_graph_main_screen.call_deferred("_on_relayout")

func _initial_project_scan() -> void:
	if GDSScanConfig.is_enabled():
		_bridge.run_project_analysis()
		print("[GDScriptUtil] Project scan: ON — analyzing...")
	else:
		print("[GDScriptUtil] Project scan: OFF. Configure in Project Settings → GDScript Util → Scan.")

# 焦点跟随: 检测当前脚本编辑器焦点是否变化，变了就触发分析
func _on_focus_tick() -> void:
	var se = _plugin.get_editor_interface().get_script_editor()
	if se == null:
		return
	var current = se.get_current_script()
	if current == null:
		return
	var path: String = current.resource_path
	if path != _last_script_path and path.ends_with(".gd"):
		_last_script_path = path
		# 直接分析（bridge 内部有 timestamp 缓存，未修改的会秒回）
		_bridge.run_analysis(path)
