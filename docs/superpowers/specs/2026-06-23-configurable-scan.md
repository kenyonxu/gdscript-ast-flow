# 可配置项目扫描 设计规范

> 日期: 2026-06-23 | 状态: 设计中 | 依赖: Phase 3.2 跨文件分析 (已完成 ✅)

## 一、目标

把项目扫描从硬编码 `res://` + 固定排除列表，改成**用户可配置**：自定义扫描目录（多个）+ 每个目录可选递归/非递归 + 自定义排除目录。

**核心问题：**
- `addons/` 被整体排除 → 无法自分析 `addons/gdscript_util` 自身代码
- 排除列表硬编码 `const` → 用户不能加项目特有的噪音目录（如 `vendor/`、`third_party/`）
- 扫描根固定 `res://` → 不能限定只看 `src/` 子树
- 第三方 addon 全扫 → 噪声大（如 limboai 几百个 .gd）

## 二、范围

### 做：

1. **ProjectSettings 配置项** — 在 Godot Project Settings 里暴露扫描配置（EditorPlugin 可读写）
2. **扫描目录列表** — 多个目录，每个标注是否递归
3. **排除目录列表** — 用户可增减；默认含 `.godot`/`.git` + 插件自身
4. **ProjectAnalyzer 读配置** — `scan_project` 改为按配置扫描
5. **UI 入口** — Project tab 加"Settings"按钮打开配置面板

### 不做：

- ❌ 文件级排除（按文件名 glob）——YAGNI，目录级够用
- ❌ 自动检测第三方 addon ——需要解析 plugin.cfg 依赖链，复杂；用户手动排
- ❌ 增量监听文件系统（watch）——当前 deferred + timestamp 缓存够用

## 三、配置模型

### 3.1 ProjectSettings 存储结构

```
gdscript_util/scan/include_dirs = [
    { "path": "res://src", "recursive": true },
    { "path": "res://addons/gdscript_util", "recursive": true },
]
gdscript_util/scan/exclude_dirs = [
    "res://addons/limboai",
    "res://.godot",
]
```

默认值（首次使用时）：

```
include_dirs = [
    { "path": "res://", "recursive": true }
]
exclude_dirs = [
    "res://addons",        # 第三方插件默认排除
    "res://.godot",
    "res://.git",
]
```

### 3.2 优先级

**include（更具体）覆盖 exclude（更宽泛）。** 类似 .gitignore 的 `!` 否定——显式 include 优先。

判断逻辑（对每个 .gd 文件）：
1. 先查 exclude —— 路径在排除列表中 → 标记排除
2. 再查 include —— 路径**显式**在 include 列表中 → **取消排除，纳入扫描**
3. 若 include 里只有宽泛的 `res://` → 不算"显式"（无法覆盖更具体的 exclude）

**示例：**

| include | exclude | 结果 |
|---------|---------|------|
| `res://` | `addons/` | 扫 res:// 全部，跳过所有 addon（默认行为） |
| `res://`, `addons/my_addon/` | `addons/` | 扫 res:// + **my_addon**（显式 include 覆盖） |
| `res://src/` | `addons/` | 只扫 src/，跳过 addons/ |

**"显式"判定：** include 路径比 exclude 路径**更深**（更具体）时算显式覆盖。`res://` 是最浅的，不能覆盖 `addons/`；`addons/my_addon/` 比 `addons/` 深，能覆盖。

## 四、架构

```
addons/gdscript_util/
├── editor/
│   ├── gds_scan_config.gd           # [新增] 读写 ProjectSettings 配置
│   ├── gds_project_analyzer.gd      # [修改] scan_project 读配置
│   └── panels/
│       └── gds_scan_settings_dialog.gd  # [新增] 配置编辑弹窗
```

### 4.1 GDSScanConfig — 配置读写

```gdscript
class_name GDSScanConfig
extends RefCounted

const SETTING_INCLUDE := "gdscript_util/scan/include_dirs"
const SETTING_EXCLUDE := "gdscript_util/scan/exclude_dirs"

static func get_include_dirs() -> Array:
    # 读 ProjectSettings，若无则返回默认值
    if ProjectSettings.has_setting(SETTING_INCLUDE):
        return ProjectSettings.get_setting(SETTING_INCLUDE)
    return [{ "path": "res://", "recursive": true }]

static func get_exclude_dirs() -> Array:
    if ProjectSettings.has_setting(SETTING_EXCLUDE):
        return ProjectSettings.get_setting(SETTING_EXCLUDE)
    return ["res://addons", "res://.godot", "res://.git"]

static func set_config(p_include: Array, p_exclude: Array) -> void:
    ProjectSettings.set_setting(SETTING_INCLUDE, p_include)
    ProjectSettings.set_setting(SETTING_EXCLUDE, p_exclude)
    ProjectSettings.save()
```

### 4.2 ProjectAnalyzer 改造

```gdscript
# 当前: scan_project(p_root) — 硬编码 res:// + SKIP_DIRS
# 改为: scan_project() — 读 GDSScanConfig

func scan_project() -> Array:
    var includes = GDSScanConfig.get_include_dirs()
    var excludes = GDSScanConfig.get_exclude_dirs()
	var list: Array = []
	for entry in includes:
		var path = entry.path
		var recursive = entry.get("recursive", true)
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
		# 排除目录检查
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

func _is_excluded(p_path: String, p_excludes: Array, p_includes: Array) -> bool:
	# 1. 先查 exclude
	var excluded := false
	for excl in p_excludes:
		if p_path == excl or p_path.begins_with(excl + "/"):
			excluded = true
			break
	if not excluded:
		return false
	# 2. 再查 include — 显式更深的 include 覆盖排除
	for entry in p_includes:
		var inc_path = entry.get("path", "")
		if inc_path == "res://" or inc_path == "":
			continue  # 最浅的 res:// 不算显式覆盖
		if p_path == inc_path or p_path.begins_with(inc_path + "/"):
			# 这个 include 比 exclude 更深 → 覆盖排除
			# 但要确认没有更深的 exclude 也排除它
			return _is_deeper_exclude(p_path, inc_path, p_excludes)
	return true  # 排除且无 include 覆盖

func _is_deeper_exclude(p_path: String, p_include: String, p_excludes: Array) -> bool:
	# 检查是否有比 include 更深的 exclude 仍然排除该路径
	for excl in p_excludes:
		if excl.length() > p_include.length() and p_path.begins_with(excl + "/"):
			return true  # 更深的 exclude 优先
	return false
```

### 4.3 配置编辑弹窗

Project tab 加 "Settings" 按钮 → 打开 `GDSscanSettingsDialog`（AcceptDialog）：

```
┌─ Scan Settings ────────────────────────────────┐
│ Include Directories:                            │
│   ┌─────────────────────┬──────────┐           │
│   │ res://src           │ ✓ Recursive │ [Remove]│
│   │ res://addons/gds... │ ✓ Recursive │ [Remove]│
│   └─────────────────────┴──────────┘           │
│   [Add Directory...]                            │
│                                                 │
│ Exclude Directories:                            │
│   ┌─────────────────────────┐                   │
│   │ res://addons             │ [Remove]         │
│   │ res://addons/limboai     │ [Remove]         │
│   └─────────────────────────┘                   │
│   [Add Directory...]                            │
│                                                 │
│              [Save]  [Cancel]                   │
└─────────────────────────────────────────────────┘
```

- Include 列表：Tree 两列（路径 + Recursive 复选框）+ Add/Remove 按钮
- Exclude 列表：Tree 一列（路径）+ Add/Remove 按钮
- Add 用 FileDialog 选目录
- Save → `GDSScanConfig.set_config(...)` → 触发 rebuild

## 五、交付物

| 文件 | 类型 | 说明 |
|------|------|------|
| `editor/gds_scan_config.gd` | 新增 | ProjectSettings 配置读写 |
| `editor/panels/gds_scan_settings_dialog.gd` | 新增 | 配置编辑弹窗 |
| `editor/gds_project_analyzer.gd` | 修改 | `scan_project()` 读配置替代硬编码 |
| `editor/gds_analysis_bridge.gd` | 修改 | `run_project_analysis` 不再传 root 参数 |
| `editor/panels/gds_project_panel.gd` | 修改 | 加 Settings 按钮 |

## 六、验收标准

- [ ] Project Settings → gdscript_util/scan/ 出现配置项
- [ ] 默认：include=`res://` 递归，exclude=`addons`/`.godot`/`.git`
- [ ] 加 `res://addons/gdscript_util` 到 include → 项目图出现自身代码
- [ ] 加 `res://addons/limboai` 到 exclude → 不扫 limboai
- [ ] 非递归目录：只扫顶层 .gd，不进子目录
- [ ] exclude 覆盖 include（同目录在两者中 → 排除）
- [ ] Settings 弹窗增删目录 → Save → 项目图刷新
- [ ] ProjectSettings.save() 持久化（重启编辑器配置不丢）

## 七、风险

| 风险 | 缓解 |
|------|------|
| ProjectSettings 存 Dictionary Array 序列化 | Godot 4 原生支持 Array/Dictionary 存入 ProjectSettings，已有先例 |
| 用户配错（include 空）→ 项目图空 | UI 验证：include 不能为空 |
| 配置变更后需重新全量扫描 | Save 时自动触发 `run_project_analysis` |
| 路径格式不一致（有/无尾斜杠） | 统一用 `path_join` + `begins_with(excl + "/")` 规范化 |
