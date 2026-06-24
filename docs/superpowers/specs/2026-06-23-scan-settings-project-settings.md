# 扫描设置设计规范

> 日期: 2026-06-23 | 修订: 2026-06-24 | 状态: 已完成 ✅ | 依赖: 可配置项目扫描 (已完成 ✅)

## 修订历史

| 日期 | 变更 |
|------|------|
| 2026-06-23 | 初版：扫描配置迁移到 Project Settings 对话框 |
| 2026-06-24 | **方向修正**：Project Settings 仅作静默存储，用户通过可视化弹窗编辑目录（浏览添加/删除）。原因：PackedStringArray 在 Project Settings 中只能手写路径，无法浏览目录，体验差。同时工具菜单改为二级结构 `GDScript AST Flow → Parse Current / Scan Settings...`。 |

## 一、目标

把扫描配置从 Project tab 的自定义弹窗（GDSScanSettingsDialog）迁移到 **Godot 编辑器的 Project Settings 对话框**——这是用户查找项目级配置的标准位置，符合编辑器惯例。

**核心问题：**
- 用户想改扫描配置时，不知道要去 Analysis tab → Project 子 tab → Settings 按钮
- 不符合 Godot 插件惯例——项目级设置应在 Project Settings
- 自定义弹窗重复造轮子（Tree + FileDialog），维护成本高

## 二、范围

### 做：

1. **简化数据模型** — 从 `Array<Dictionary>` 改为 `PackedStringArray`（纯路径字符串数组）
2. **静默存储到 ProjectSettings** — 用 `set_setting` 存储，不调 `set_initial_value`（配置不显示在 Project Settings 对话框）
3. **重建 GDSScanSettingsDialog** — 可视化目录浏览弹窗：Browse 添加目录、Remove 删除、Enable 开关
4. **Project tab 加 Scan Settings 按钮** — 打开上述弹窗
5. **工具菜单** — `GDScript AST Flow → Scan Settings...` + `Parse Current`
6. **兼容桥接** — `save_config()` + `enable_scan()` 兼容旧测试 API

### 不做：

- ❌ **在 Project Settings 对话框显示配置** — PackedStringArray 无目录浏览 UI，手写体验差
- ❌ **保留每目录递归开关** — YAGNI，改为全部递归（绝大多数场景）

## 三、数据模型变更

### 之前（Array of Dictionary）：

```
gdscript_util/scan/include_dirs = [{path: "res://src", recursive: true}, ...]
gdscript_util/scan/exclude_dirs = ["res://addons", ...]
```

ProjectSettings 对 Array<Dictionary> 无原生编辑器 → 必须自定义 UI

### 之后（PackedStringArray）：

```
gdscript_util/scan/enabled = false
gdscript_util/scan/include = PackedStringArray("res://src", "res://addons/gdscript_util")
gdscript_util/scan/exclude = PackedStringArray("res://addons", "res://.godot")
```

PackedStringArray 在 ProjectSettings 原生显示为多行文本编辑器（每行一个路径）。

**递归开关简化：** 全部 include 目录默认递归。不做非递归（极少需要）。

## 四、ProjectSettings 静默存储

配置通过 `ProjectSettings.set_setting()` 静默存储，**不调 `set_initial_value`**，因此不在 Project Settings 对话框显示。用户通过可视化弹窗编辑。

```gdscript
# GDSScanSettingsDialog._on_save() — 写入，不注册到 UI
ProjectSettings.set_setting(GDSScanConfig.SETTING_INCLUDE, inc_arr)
ProjectSettings.set_setting(GDSScanConfig.SETTING_EXCLUDE, exc_arr)
ProjectSettings.set_setting(GDSScanConfig.SETTING_ENABLED, _enabled_check.button_pressed)
```

配置键（隐藏，不显示在 Project Settings 对话框）：

```
gdscript_util/scan/enabled   = false          (bool)
gdscript_util/scan/include   = PackedStringArray(...)  (目录路径列表)
gdscript_util/scan/exclude   = PackedStringArray(["res://addons"])
```

**为什么不注册到 Project Settings？** PackedStringArray 的原生编辑器是多行文本框，用户只能手写路径字符串，无法浏览目录。改为自定义弹窗（`GDSScanSettingsDialog`）提供 FileDialog 浏览目录 + Tree 列表管理。

## 五、GDSScanConfig 适配

```gdscript
class_name GDSScanConfig
extends RefCounted

const SETTING_ENABLED := "gdscript_util/scan/enabled"
const SETTING_INCLUDE := "gdscript_util/scan/include"
const SETTING_EXCLUDE := "gdscript_util/scan/exclude"

static var DEFAULT_EXCLUDE: PackedStringArray = PackedStringArray(["res://addons", "res://.godot", "res://.git"])

static func is_enabled() -> bool:
    return ProjectSettings.get_setting(SETTING_ENABLED, false)

static func get_include_dirs() -> Array:
    var arr: PackedStringArray = ProjectSettings.get_setting(SETTING_INCLUDE, PackedStringArray())
    return Array(arr)

static func get_exclude_dirs() -> Array:
    var arr: PackedStringArray = ProjectSettings.get_setting(SETTING_EXCLUDE, DEFAULT_EXCLUDE)
    return Array(arr)

# 兼容旧测试 API — 桥接到 ProjectSettings
static func save_config(p_include: Array, p_exclude: Array = []) -> void:
    # 将旧格式 Array[Dict] 或 Array[String] 转为 PackedStringArray 写入

static func enable_scan() -> void:
    ProjectSettings.set_setting(SETTING_ENABLED, true)

# 迁移旧格式（Array<Dictionary> → PackedStringArray）
static func migrate_if_needed() -> void: ...
```

> **注意**: `save_config` 和 `enable_scan` 是为旧测试兼容保留的桥接函数。新代码应直接用可视化弹窗或 `ProjectSettings.set_setting`。

## 六、迁移兼容

已有配置（Array<Dictionary> 格式）需自动迁移：

```gdscript
static func _migrate_old_format() -> void:
    var old_include = ProjectSettings.get_setting("gdscript_util/scan/include_dirs", null)
    if old_include != null and old_include is Array:
        # 旧格式 → 新格式
        var new_arr := PackedStringArray()
        for entry in old_include:
            new_arr.append(entry.get("path", ""))
        ProjectSettings.set_setting("gdscript_util/scan/include", new_arr)
        ProjectSettings.set_setting("gdscript_util/scan/include_dirs", null)  # 清除旧键
    # exclude_dirs → exclude
    var old_exclude = ProjectSettings.get_setting("gdscript_util/scan/exclude_dirs", null)
    if old_exclude != null and old_exclude is Array:
        ProjectSettings.set_setting("gdscript_util/scan/exclude", PackedStringArray(old_exclude))
        ProjectSettings.set_setting("gdscript_util/scan/exclude_dirs", null)
```

## 七、交付物

| 文件 | 类型 | 说明 |
|------|------|------|
| `plugin.gd` | 修改 | 工具子菜单 `GDScript AST Flow → Parse Current / Scan Settings...`；不注册扫描配置到 Project Settings 对话框 |
| `gds_scan_config.gd` | 修改 | PackedStringArray API + 迁移 + `save_config`/`enable_scan` 桥接 |
| `gds_project_analyzer.gd` | 修改 | `_scan_dir` 简化（全部递归） |
| `gds_project_panel.gd` | 修改 | 加 "Scan Settings" 按钮 → 打开可视化弹窗 |
| `gds_scan_settings_dialog.gd` | **新建** | 目录浏览弹窗（Browse 添加 + Remove 删除 + Enable 开关），读写 ProjectSettings |
| `test_phase3_2_cross_file.gd` | 不变 | 通过桥接函数 `save_config`/`enable_scan` 继续工作 |
| `test_phase3_3_graph.gd` | 不变 | 同上 |

## 八、验收标准

- [ ] Project Settings → GDScript Util → Scan 出现三个配置项
- [ ] enabled 是 checkbox
- [ ] include/exclude 是多行文本编辑器
- [ ] 改配置 → 关闭 Project Settings → 触发 rebuild
- [ ] 旧格式（Array<Dictionary>）自动迁移到 PackedStringArray
- [ ] Project tab 不再有 Settings 按钮
- [ ] GDSScanSettingsDialog 文件删除
- [ ] 首次安装默认 enabled=false, include=空, exclude=addons

## 九、风险

| 风险 | 缓解 |
|------|------|
| PackedStringArray 编辑器体验差 | Godot 原生多行文本，比自定义 Tree 简单够用 |
| 用户不知改后要 rebuild | Project tab 保留 Rebuild 按钮 + Output 提示 |
| 迁移丢数据 | _migrate_old_format 先读旧值再写新值，最后清旧键 |
| add_property_info 时机 | 在 _enter_tree 调用，确保编辑器启动就注册 |
