# 扫描设置迁移到 Project Settings 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 扫描配置从自定义弹窗迁移到 Godot Project Settings 对话框，简化数据模型为 PackedStringArray。

**Architecture:** plugin.gd 注册属性 → GDSScanConfig 改用 PackedStringArray → 删除 GDSScanSettingsDialog → Project panel 去掉 Settings 按钮 → 迁移旧格式。

**Tech Stack:** Godot 4.7, GDScript, ProjectSettings API

**Spec reference:** `docs/superpowers/specs/2026-06-23-scan-settings-project-settings.md`

---

## Task 1: plugin.gd 注册 ProjectSettings 属性

**Files:** Modify: `addons/gdscript_util/plugin.gd`

- [ ] **Step 1: _enter_tree 末尾追加注册**

```gdscript
func _enter_tree():
	# ... 已有代码 ...

	# 注册扫描配置到 Project Settings
	_register_scan_settings()

func _register_scan_settings() -> void:
	# enabled
	if not ProjectSettings.has_setting("gdscript_util/scan/enabled"):
		ProjectSettings.set_setting("gdscript_util/scan/enabled", false)
	ProjectSettings.set_initial_value("gdscript_util/scan/enabled", false)

	# include (PackedStringArray)
	if not ProjectSettings.has_setting("gdscript_util/scan/include"):
		ProjectSettings.set_setting("gdscript_util/scan/include", PackedStringArray())
	ProjectSettings.set_initial_value("gdscript_util/scan/include", PackedStringArray())

	# exclude (PackedStringArray)
	if not ProjectSettings.has_setting("gdscript_util/scan/exclude"):
		ProjectSettings.set_setting("gdscript_util/scan/exclude", PackedStringArray("res://addons"))
	ProjectSettings.set_initial_value("gdscript_util/scan/exclude", PackedStringArray("res://addons"))
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/plugin.gd
git commit -m "feat: plugin.gd — register scan settings in ProjectSettings"
```

---

## Task 2: GDSScanConfig 改用 PackedStringArray + 迁移

**Files:** Modify: `addons/gdscript_util/editor/gds_scan_config.gd`

- [ ] **Step 1: 替换整个文件**

```gdscript
# addons/gdscript_util/editor/gds_scan_config.gd
# 项目扫描配置 — 存储在 ProjectSettings (PackedStringArray)，原生 Project Settings 编辑

class_name GDSScanConfig
extends RefCounted

const SETTING_ENABLED := "gdscript_util/scan/enabled"
const SETTING_INCLUDE := "gdscript_util/scan/include"
const SETTING_EXCLUDE := "gdscript_util/scan/exclude"

const DEFAULT_EXCLUDE := PackedStringArray("res://addons", "res://.godot", "res://.git")

static func is_enabled() -> bool:
	return ProjectSettings.get_setting(SETTING_ENABLED, false)

static func get_include_dirs() -> Array:
	var arr: PackedStringArray = ProjectSettings.get_setting(SETTING_INCLUDE, PackedStringArray())
	return Array(arr)

static func get_exclude_dirs() -> Array:
	var arr: PackedStringArray = ProjectSettings.get_setting(SETTING_EXCLUDE, DEFAULT_EXCLUDE)
	return Array(arr)

# 迁移旧格式（Array<Dictionary> → PackedStringArray）
static func migrate_if_needed() -> void:
	# include_dirs → include
	var old_include = ProjectSettings.get_setting("gdscript_util/scan/include_dirs", null)
	if old_include != null and old_include is Array and old_include.size() > 0:
		var new_arr := PackedStringArray()
		for entry in old_include:
			var path = entry.get("path", "") if entry is Dictionary else str(entry)
			if path != "":
				new_arr.append(path)
		ProjectSettings.set_setting(SETTING_INCLUDE, new_arr)
		ProjectSettings.set_setting("gdscript_util/scan/include_dirs", null)
	# exclude_dirs → exclude
	var old_exclude = ProjectSettings.get_setting("gdscript_util/scan/exclude_dirs", null)
	if old_exclude != null and old_exclude is Array and old_exclude.size() > 0:
		ProjectSettings.set_setting(SETTING_EXCLUDE, PackedStringArray(old_exclude))
		ProjectSettings.set_setting("gdscript_util/scan/exclude_dirs", null)
```

- [ ] **Step 2: bootstrap setup 里调迁移**

在 `_initial_project_scan` 之前加：

```gdscript
func setup(p_plugin):
	# ... 已有代码 ...
	GDSScanConfig.migrate_if_needed()
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/editor/gds_scan_config.gd addons/gdscript_util/editor/gds_editor_bootstrap.gd
git commit -m "refactor: GDSScanConfig — PackedStringArray API + old format migration"
```

---

## Task 3: ProjectAnalyzer 简化（全部递归）

**Files:** Modify: `addons/gdscript_util/editor/gds_project_analyzer.gd`

- [ ] **Step 1: scan_project 简化**

```gdscript
func scan_project() -> Array:
	var includes = GDSScanConfig.get_include_dirs()
	var excludes = GDSScanConfig.get_exclude_dirs()
	var list: Array = []
	for path in includes:
		if path != "":
			_scan_dir(path, list, excludes)
	return list

# 全部递归（去掉 recursive 参数）
func _scan_dir(p_dir: String, p_list: Array, p_excludes: Array) -> void:
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
			_scan_dir(full, p_list, p_excludes)
		elif name.ends_with(".gd"):
			p_list.append(full)
		name = da.get_next()
	da.list_dir_end()
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_project_analyzer.gd
git commit -m "refactor: ProjectAnalyzer — all dirs recursive (simplified from per-dir toggle)"
```

---

## Task 4: Project panel 去掉 Settings 按钮

**Files:** Modify: `addons/gdscript_util/editor/panels/gds_project_panel.gd`

- [ ] **Step 1: 删除 Settings 按钮相关代码**

删除：
- `_settings_dialog` 成员变量
- `_on_settings` 方法
- `_on_settings_saved` 方法
- toolbar 里的 Settings 按钮创建代码

保留 Rebuild 按钮。

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/panels/gds_project_panel.gd
git commit -m "refactor: project panel — remove Settings button (moved to Project Settings)"
```

---

## Task 5: 删除 GDSScanSettingsDialog

**Files:** Delete: `addons/gdscript_util/editor/panels/gds_scan_settings_dialog.gd`

- [ ] **Step 1: 删除文件**

```bash
git rm addons/gdscript_util/editor/panels/gds_scan_settings_dialog.gd
```

- [ ] **Step 2: 提交**

```bash
git commit -m "chore: delete GDSScanSettingsDialog (replaced by native Project Settings)"
```

---

## Task 6: 验收

- [ ] **Step 1: Project Settings 面板** — 打开 Project Settings → 搜索 "gdscript_util" 或翻到 GDScript Util 分类 → 确认 enabled/include/exclude 三项可见
- [ ] **Step 2: 配置流程** — 设 include = `res://samples` → 关闭对话框 → Project tab → Rebuild → 项目图显示 samples 文件
- [ ] **Step 3: 迁移** — 手动在 project.godot 写旧格式 `include_dirs=[{path:..., recursive:true}]` → 重启 → 确认自动迁移
- [ ] **Step 4: Project tab 无 Settings** — 确认 Project tab 只有 Rebuild 按钮
- [ ] **Step 5: 回归** — 单文件分析不受影响

---

## 完成检查清单

- [ ] plugin.gd — _register_scan_settings
- [ ] gds_scan_config.gd — PackedStringArray API + migrate_if_needed
- [ ] gds_project_analyzer.gd — scan_project 全部递归
- [ ] gds_project_panel.gd — 删除 Settings 按钮
- [ ] gds_scan_settings_dialog.gd — 删除
- [ ] bootstrap — 调 migrate_if_needed
- [ ] Project Settings 显示三项配置
- [ ] 旧格式自动迁移
- [ ] 单文件回归通过
