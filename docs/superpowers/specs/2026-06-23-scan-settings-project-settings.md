# 扫描设置迁移到 Project Settings 设计规范

> 日期: 2026-06-23 | 状态: 设计中 | 依赖: 可配置项目扫描 (已完成 ✅)

## 一、目标

把扫描配置从 Project tab 的自定义弹窗（GDSScanSettingsDialog）迁移到 **Godot 编辑器的 Project Settings 对话框**——这是用户查找项目级配置的标准位置，符合编辑器惯例。

**核心问题：**
- 用户想改扫描配置时，不知道要去 Analysis tab → Project 子 tab → Settings 按钮
- 不符合 Godot 插件惯例——项目级设置应在 Project Settings
- 自定义弹窗重复造轮子（Tree + FileDialog），维护成本高

## 二、范围

### 做：

1. **简化数据模型** — 从 `Array<Dictionary>` 改为 `PackedStringArray`（Project Settings 原生支持多行文本编辑）
2. **注册到 ProjectSettings** — 用 `set_initial_value` + `set_property_info` 让配置出现在 Project Settings 对话框
3. **去掉 GDSScanSettingsDialog** — 不再需要自定义弹窗
4. **Project tab 简化** — 只保留 Rebuild 按钮 + Enable 快捷开关，去掉 Settings 按钮

### 不做：

- ❌ **自定义 EditorInspectorPlugin** — PackedStringArray 原生编辑器够用，不额外开发
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

## 四、ProjectSettings 注册

```gdscript
# plugin.gd _enter_tree 或 bootstrap setup:
func _register_scan_settings() -> void:
    # enabled
    if not ProjectSettings.has_setting("gdscript_util/scan/enabled"):
        ProjectSettings.set_setting("gdscript_util/scan/enabled", false)
    ProjectSettings.set_initial_value("gdscript_util/scan/enabled", false)
    ProjectSettings.add_property_info({
        "name": "gdscript_util/scan/enabled",
        "type": TYPE_BOOL,
    })
    # include
    if not ProjectSettings.has_setting("gdscript_util/scan/include"):
        ProjectSettings.set_setting("gdscript_util/scan/include", PackedStringArray())
    ProjectSettings.set_initial_value("gdscript_util/scan/include", PackedStringArray())
    ProjectSettings.add_property_info({
        "name": "gdscript_util/scan/include",
        "type": TYPE_PACKED_STRING_ARRAY,
    })
    # exclude
    if not ProjectSettings.has_setting("gdscript_util/scan/exclude"):
        ProjectSettings.set_setting("gdscript_util/scan/exclude", PackedStringArray("res://addons"))
    ProjectSettings.set_initial_value("gdscript_util/scan/exclude", PackedStringArray("res://addons"))
    ProjectSettings.add_property_info({
        "name": "gdscript_util/scan/exclude",
        "type": TYPE_PACKED_STRING_ARRAY,
    })
```

注册后 Project Settings 对话框显示：

```
▶ GDScript Util
    Scan/
      Enabled: [ ]
      Include: (多行文本，每行一个路径)
      Exclude: (多行文本，每行一个路径)
```

## 五、GDSScanConfig 适配

```gdscript
class_name GDSScanConfig
extends RefCounted

static func is_enabled() -> bool:
    return ProjectSettings.get_setting("gdscript_util/scan/enabled", false)

static func get_include_dirs() -> Array:
    # 返回 PackedStringArray 转为 Array<String>
    var arr: PackedStringArray = ProjectSettings.get_setting("gdscript_util/scan/include", PackedStringArray())
    return Array(arr)

static func get_exclude_dirs() -> Array:
    var arr: PackedStringArray = ProjectSettings.get_setting("gdscript_util/scan/exclude", PackedStringArray("res://addons"))
    return Array(arr)

# 用户在 Project Settings 改了配置后，Godot 自动 save
# 不需要 save_config/enable_scan/disable_scan — Project Settings 对话框管理
```

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
| `plugin.gd` | 修改 | `_enter_tree` 注册 ProjectSettings 属性 |
| `gds_scan_config.gd` | 修改 | PackedStringArray API + 迁移 + 去掉 save/enable/disable |
| `gds_project_analyzer.gd` | 修改 | `_scan_dir` 简化（全部递归） |
| `gds_project_panel.gd` | 修改 | 去掉 Settings 按钮 + 弹窗引用 |
| `gds_scan_settings_dialog.gd` | 删除 | 不再需要 |

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
