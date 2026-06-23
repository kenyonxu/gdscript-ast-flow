# 可配置项目扫描 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 项目扫描从硬编码改为用户可配置——显式开关 + 多 include 目录（递归可选）+ 自定义 exclude 目录。首次安装不扫描，用户配置后显式开启。

**Architecture:** GDSScanConfig 读写 ProjectSettings；ProjectAnalyzer 读配置扫描；Settings 弹窗编辑配置；Bootstrap 按 enabled 开关决定是否扫描 + Output 提示。

**Tech Stack:** Godot 4.7, GDScript, ProjectSettings API, DirAccess, AcceptDialog

**Spec reference:** `docs/superpowers/specs/2026-06-23-configurable-scan.md`

---

## 文件结构

```
addons/gdscript_util/editor/
├── gds_scan_config.gd               # [新增] ProjectSettings 配置读写
├── gds_project_analyzer.gd          # [修改] scan_project 读配置 + _is_excluded 优先级
├── gds_analysis_bridge.gd           # [修改] run_project_analysis 不再传 root
├── gds_editor_bootstrap.gd          # [修改] 按 enabled 决定扫描 + 启动提示
└── panels/
    └── gds_scan_settings_dialog.gd  # [新增] 配置编辑弹窗
    └── gds_project_panel.gd         # [修改] 加 Settings 按钮 + 禁用态提示
```

---

## Chunk A: 配置层

### Task A1: 创建 GDSScanConfig

**Files:** Create: `addons/gdscript_util/editor/gds_scan_config.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/gds_scan_config.gd
# 项目扫描配置读写 — 存储在 ProjectSettings，持久化跨编辑器重启

class_name GDSScanConfig
extends RefCounted

const SETTING_ENABLED := "gdscript_util/scan/enabled"
const SETTING_INCLUDE := "gdscript_util/scan/include_dirs"
const SETTING_EXCLUDE := "gdscript_util/scan/exclude_dirs"

const DEFAULT_EXCLUDE := ["res://addons", "res://.godot", "res://.git"]

static func is_enabled() -> bool:
	return ProjectSettings.get_setting(SETTING_ENABLED, false)

static func get_include_dirs() -> Array:
	return ProjectSettings.get_setting(SETTING_INCLUDE, [])

static func get_exclude_dirs() -> Array:
	return ProjectSettings.get_setting(SETTING_EXCLUDE, DEFAULT_EXCLUDE)

# Settings 弹窗 Save 调用 — 保存配置 + 自动关闭扫描
static func save_config(p_include: Array, p_exclude: Array) -> void:
	ProjectSettings.set_setting(SETTING_INCLUDE, p_include)
	ProjectSettings.set_setting(SETTING_EXCLUDE, p_exclude)
	ProjectSettings.set_setting(SETTING_ENABLED, false)
	# 注册到 ProjectSettings 使其在编辑器 Settings 面板可见
	if not ProjectSettings.has_setting(SETTING_ENABLED):
		ProjectSettings.set_initial_value(SETTING_ENABLED, false)
	ProjectSettings.save()

# Enable 勾选调用 — 显式开启扫描
static func enable_scan() -> void:
	ProjectSettings.set_setting(SETTING_ENABLED, true)
	ProjectSettings.save()

static func disable_scan() -> void:
	ProjectSettings.set_setting(SETTING_ENABLED, false)
	ProjectSettings.save()
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_scan_config.gd
git commit -m "feat: GDSScanConfig — ProjectSettings read/write for scan config"
```

---

### Task A2: ProjectAnalyzer 读配置扫描

**Files:** Modify: `addons/gdscript_util/editor/gds_project_analyzer.gd`

- [ ] **Step 1: 替换硬编码 scan_project + _scan_dir**

替换 `SKIP_DIRS` 常量和 `scan_project(p_root)` / `_scan_dir` 方法：

```gdscript
# 删除: const SKIP_DIRS := [...]
# 删除: func scan_project(p_root: String) -> Array:

# 新: 按配置扫描
func scan_project() -> Array:
	var includes = GDSScanConfig.get_include_dirs()
	var excludes = GDSScanConfig.get_exclude_dirs()
	var list: Array = []
	for entry in includes:
		var path: String = entry.get("path", "")
		var recursive: bool = entry.get("recursive", true)
		if path != "":
			_scan_dir(path, list, excludes, recursive)
	return list

func _scan_dir(p_dir: String, p_list: Array, p_excludes: Array, p_recursive: bool) -> void:
	var da = DirAccess.open(p_dir)
	if da == null:
		return
	da.list_dir_begin()
	var name = da.get_next()
	while name != "":
		if name in [".", ".."]:
			name = da.get_next()
			continue
		var full = p_dir.path_join(name)
		if _is_excluded(full, p_excludes):
			name = da.get_next()
			continue
		if da.current_is_dir():
			if p_recursive:
				_scan_dir(full, p_list, p_excludes, true)
		elif name.ends_with(".gd"):
			p_list.append(full)
		name = da.get_next()
	da.list_dir_end()

# include (更具体) 覆盖 exclude (更宽泛)
func _is_excluded(p_path: String, p_excludes: Array) -> bool:
	var excluded := false
	for excl in p_excludes:
		if p_path == excl or p_path.begins_with(excl + "/"):
			excluded = true
			break
	if not excluded:
		return false
	# 检查是否有更深的 include 覆盖
	var includes = GDSScanConfig.get_include_dirs()
	for entry in includes:
		var inc_path: String = entry.get("path", "")
		if inc_path == "" or inc_path == "res://":
			continue  # 最浅的不算显式覆盖
		if p_path == inc_path or p_path.begins_with(inc_path + "/"):
			# include 比 exclude 深 → 覆盖
			# 但确认没有更深的 exclude 仍排除
			for excl in p_excludes:
				if excl.length() > inc_path.length() and p_path.begins_with(excl + "/"):
					return true  # 更深的 exclude 优先
			return false  # include 覆盖生效
	return true  # 排除且无 include 覆盖
```

- [ ] **Step 2: 修改 analyze_full 不再传 root**

```gdscript
# 当前: func analyze_full(p_root: String) -> GDScriptProjectResult:
# 改为:
func analyze_full() -> GDScriptProjectResult:
	var result = GDScriptProjectResult.new()
	result.root_path = "res://"
	var paths = scan_project()  # 不传参，读配置
	for path in paths:
		var file_result = _analyze_file(path)
		if file_result != null:
			result.files[path] = file_result
	_build_class_registry(result)
	resolve_cross_file(result)
	return result
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/editor/gds_project_analyzer.gd
git commit -m "feat: ProjectAnalyzer — read scan config, include overrides exclude"
```

---

## Chunk B: 桥接层

### Task B1: Bridge 适配

**Files:** Modify: `addons/gdscript_util/editor/gds_analysis_bridge.gd`

- [ ] **Step 1: run_project_analysis 不再传 root**

```gdscript
# 当前: func run_project_analysis(p_root: String = "res://") -> void:
# 改为:
func run_project_analysis() -> void:
	project_analysis_started.emit()
	call_deferred("_do_project_analysis")

func _do_project_analysis() -> void:
	if _project_analyzer == null:
		_project_analyzer = GDScriptProjectAnalyzer.new()
	_project_result = _project_analyzer.analyze_full()  # 不传 root
	project_analysis_completed.emit(_project_result)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_analysis_bridge.gd
git commit -m "refactor: bridge run_project_analysis — no root param, reads config"
```

---

### Task B2: Bootstrap 按开关扫描 + 启动提示

**Files:** Modify: `addons/gdscript_util/editor/gds_editor_bootstrap.gd`

- [ ] **Step 1: _initial_project_scan 检查 enabled**

```gdscript
func _initial_project_scan() -> void:
	if GDSScanConfig.is_enabled():
		_bridge.run_project_analysis()
		print("[GDScriptUtil] Project scan: ON — analyzing...")
	else:
		print("[GDScriptUtil] Project scan: OFF. Configure in Analysis tab → Project → Settings.")
```

- [ ] **Step 2: 焦点 Timer 里 refresh_file_in_project 也检查 enabled**

```gdscript
# _run_queued_analysis 内已有的 refresh_file_in_project 调用前加:
	if GDSScanConfig.is_enabled():
		_bridge.refresh_file_in_project(path)
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/editor/gds_editor_bootstrap.gd
git commit -m "feat: bootstrap — conditional scan based on GDSScanConfig.is_enabled() + startup Output"
```

---

## Chunk C: UI

### Task C1: 创建 GDSScanSettingsDialog — 配置弹窗

**Files:** Create: `addons/gdscript_util/editor/panels/gds_scan_settings_dialog.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/panels/gds_scan_settings_dialog.gd
# 项目扫描配置弹窗 — include/exclude 目录管理 + Enable 开关

class_name GDSScanSettingsDialog
extends AcceptDialog

var _enabled_check: CheckBox = null
var _include_tree: Tree = null
var _exclude_tree: Tree = null
var _file_dialog: FileDialog = null
var _editing_include := true  # FileDialog 回调区分 include/exclude

func _ready() -> void:
	title = "Project Scan Settings"
	# 由于 AcceptDialog 内部布局，用 VBoxContainer 组织
	var vbox = VBoxContainer.new()
	add_child(vbox)

	# Enable 开关
	_enabled_check = CheckBox.new()
	_enabled_check.text = "Enable Project Scan"
	_enabled_check.button_pressed = GDSScanConfig.is_enabled()
	vbox.add_child(_enabled_check)

	# Include 区
	vbox.add_child(_make_section_label("Include Directories (scan these):"))
	_include_tree = _make_dir_tree()
	vbox.add_child(_include_tree)
	var inc_btns = HBoxContainer.new()
	var inc_add = Button.new()
	inc_add.text = "Add..."
	inc_add.pressed.connect(func(): _editing_include = true; _open_file_dialog())
	inc_btns.add_child(inc_add)
	var inc_del = Button.new()
	inc_del.text = "Remove"
	inc_del.pressed.connect(func(): _remove_selected(_include_tree))
	inc_btns.add_child(inc_del)
	vbox.add_child(inc_btns)

	# Exclude 区
	vbox.add_child(_make_section_label("Exclude Directories (skip these):"))
	_exclude_tree = _make_dir_tree()
	vbox.add_child(_exclude_tree)
	var exc_btns = HBoxContainer.new()
	var exc_add = Button.new()
	exc_add.text = "Add..."
	exc_add.pressed.connect(func(): _editing_include = false; _open_file_dialog())
	exc_btns.add_child(exc_add)
	var exc_del = Button.new()
	exc_del.text = "Remove"
	exc_del.pressed.connect(func(): _remove_selected(_exclude_tree))
	exc_btns.add_child(exc_del)
	vbox.add_child(exc_btns)

	# 加载现有配置到 Tree
	_populate_include_tree()
	_populate_exclude_tree()

	# confirmed 信号 = Save 按钮
	confirmed.connect(_on_save)

	# 隐藏的 FileDialog
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_file_dialog.dir_selected.connect(_on_dir_selected)
	add_child(_file_dialog)
	custom_minimum_size = Vector2(600, 500)

func _make_section_label(p_text: String) -> Label:
	var l = Label.new()
	l.text = p_text
	l.add_theme_font_size_override("font_size", 13)
	return l

func _make_dir_tree() -> Tree:
	var t = Tree.new()
	t.size_flags_vertical = SIZE_EXPAND_FILL
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	t.hide_root = true
	t.columns = 2
	t.set_column_title(0, "Directory")
	t.set_column_title(1, "Recursive")
	return t

func _populate_include_tree() -> void:
	_include_tree.clear()
	var root = _include_tree.create_item()
	for entry in GDSScanConfig.get_include_dirs():
		var item = _include_tree.create_item(root)
		item.set_text(0, entry.get("path", ""))
		item.set_checked(1, entry.get("recursive", true))
		item.set_editable(1, true)

func _populate_exclude_tree() -> void:
	_exclude_tree.clear()
	var root = _exclude_tree.create_item()
	for path in GDSScanConfig.get_exclude_dirs():
		var item = _exclude_tree.create_item(root)
		item.set_text(0, path)

func _open_file_dialog() -> void:
	_file_dialog.popup_centered()

func _on_dir_selected(p_path: String) -> void:
	var tree = _include_tree if _editing_include else _exclude_tree
	var root = tree.get_root()
	if root == null:
		root = tree.create_item()
	var item = tree.create_item(root)
	item.set_text(0, p_path)
	if _editing_include:
		item.set_checked(1, true)
		item.set_editable(1, true)

func _remove_selected(p_tree: Tree) -> void:
	var item = p_tree.get_selected()
	if item:
		item.queue_free()

func _on_save() -> void:
	# 收集 include
	var includes: Array = []
	var inc_root = _include_tree.get_root()
	if inc_root:
		var item = inc_root.get_first_child()
		while item:
			includes.append({"path": item.get_text(0), "recursive": item.is_checked(1)})
			item = item.get_next()
	# 收集 exclude
	var excludes: Array = []
	var exc_root = _exclude_tree.get_root()
	if exc_root:
		var item = exc_root.get_first_child()
		while item:
			excludes.append(item.get_text(0))
			item = item.get_next()
	# 保存 — save_config 自动关闭扫描
	GDSScanConfig.save_config(includes, excludes)
	# 如果用户勾了 Enable，再显式开启
	if _enabled_check.button_pressed:
		GDSScanConfig.enable_scan()
		print("[GDScriptUtil] Project scan: ENABLED. Starting analysis...")
	else:
		print("[GDScriptUtil] Project scan: OFF after config save.")
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/panels/gds_scan_settings_dialog.gd
git commit -m "feat: GDSScanSettingsDialog — include/exclude dir editor + Enable toggle"
```

---

### Task C2: Project tab 加 Settings 按钮 + 禁用态

**Files:** Modify: `addons/gdscript_util/editor/panels/gds_project_panel.gd`

- [ ] **Step 1: toolbar 加 Settings 按钮**

```gdscript
# _build_ui() 内，Rebuild 按钮之后加:
	var settings_btn = Button.new()
	settings_btn.text = "Settings"
	settings_btn.pressed.connect(_on_settings)
	toolbar.add_child(settings_btn)
```

- [ ] **Step 2: _on_settings 打开弹窗**

```gdscript
var _settings_dialog: GDSScanSettingsDialog = null

func _on_settings() -> void:
	if _settings_dialog == null:
		_settings_dialog = GDSScanSettingsDialog.new()
		_settings_dialog.confirmed.connect(_on_settings_saved)
		EditorInterface.get_base_control().add_child(_settings_dialog)
	_settings_dialog.popup_centered()

func _on_settings_saved() -> void:
	# 配置保存后若 enabled，触发重建
	if GDSScanConfig.is_enabled():
		_bridge.run_project_analysis()
	_refresh(_bridge.get_project_result())
```

- [ ] **Step 3: 禁用态提示**

修改 `_refresh`，检查 enabled 状态：

```gdscript
func _refresh(p_result: GDScriptProjectResult) -> void:
	_rebuild_btn.disabled = false
	_tree.clear()
	if not GDSScanConfig.is_enabled():
		var root = _tree.create_item()
		var item = _tree.create_item(root)
		item.set_text(0, "Project scan is OFF")
		item.set_custom_color(0, Color.GRAY)
		var hint = _tree.create_item(root)
		hint.set_text(0, "Click Settings to configure and enable.")
		hint.set_custom_color(0, Color.GRAY)
		return
	if p_result == null:
		return
	# ... 原有渲染逻辑
```

- [ ] **Step 4: 提交**

```bash
git add addons/gdscript_util/editor/panels/gds_project_panel.gd
git commit -m "feat: project panel — Settings button + disabled-state message"
```

---

## Chunk D: 验收

### Task D1: 验收

- [ ] **Step 1: 首次安装模拟** — 删除 ProjectSettings 中的 scan 配置 → 重启 → 确认不扫描 + Output 提示
- [ ] **Step 2: 配置流程** — Project tab → Settings → 加 `res://samples` 到 include → 勾 Enable → Save → 确认项目图出现 samples 下文件
- [ ] **Step 3: 排除优先级** — 默认排除 `addons/`，加 `res://addons/gdscript_util` 到 include → 确认自身代码出现在项目图
- [ ] **Step 4: 修改配置自动关** — 改 include 后 Save → 确认 Output 提示 scan paused → 重新 Enable → 确认扫描恢复
- [ ] **Step 5: 重启持久化** — Enable 后重启编辑器 → 确认自动扫描（enabled=true 持久化）
- [ ] **Step 6: Phase 1-3 回归** — 确认单文件分析不受影响（单文件不依赖项目扫描开关）

- [ ] **Step 7: 提交**

```bash
git add -A
git commit -m "test: configurable scan acceptance pass"
```

---

## 完成检查清单

- [ ] `gds_scan_config.gd` — ProjectSettings enabled/include/exclude 读写
- [ ] `gds_project_analyzer.gd` — scan_project 读配置 + include 覆盖 exclude 优先级
- [ ] `gds_analysis_bridge.gd` — run_project_analysis 不传 root
- [ ] `gds_editor_bootstrap.gd` — 按 enabled 条件扫描 + Output 提示
- [ ] `gds_scan_settings_dialog.gd` — include/exclude 编辑 + Enable 勾选
- [ ] `gds_project_panel.gd` — Settings 按钮 + 禁用态提示
- [ ] 首次安装不扫描
- [ ] 配置后 Enable → 扫描
- [ ] 改配置自动关闭 → 重新 Enable
- [ ] 重启持久化
- [ ] 单文件分析不受影响
