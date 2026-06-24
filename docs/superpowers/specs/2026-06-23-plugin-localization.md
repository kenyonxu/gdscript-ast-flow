# 插件本地化方案 设计规范

> 日期: 2026-06-23 | 修订: 2026-06-24 | 状态: 已完成 ✅ | 依赖: 全部功能阶段 (已完成)

## 修订历史

| 日期 | 变更 |
|------|------|
| 2026-06-23 | 初版：基于 TranslationServer + CSV 的本地化方案 |
| 2026-06-24 | **实现修正**：Godot 4.7 无 `translation.message` 属性，改用 `TranslationDomain` 系统（`get_or_add_domain()` + `domain.add_translation()` + `domain.translate()`）。CSV 导入 `compress=0` 避免 `OptimizedTranslation`。`msg.scan_off_hint` 改为引导用户点击 "Scan Settings" 按钮。 |

## 一、目标

为 gdscript-ast-flow 插件提供**多语言支持**，当前所有 UI 字符串是硬编码中英混合。参考 clef-dev 的 TranslationDomain 模式，用 Godot 原生 CSV + TranslationServer 实现可扩展的本地化。

**核心问题：**
- UI 字符串散落在 20+ 个 .gd 文件里，硬编码中文/英文
- 无切换语言的机制
- 外部贡献者想翻译但找不到集中管理的地方

## 二、参考架构（clef-dev）

clef-dev 用 Godot 4.6 的 **TranslationDomain** 系统：

```
TranslationServer
├── "" (项目主域)           → 项目 tr()
└── "gdscript_util" (插件域) → 我们的 t() 调用
```

- **CSV 源文件** → Godot 编译成 `.translation` 资源
- **自定义域**：避免与项目翻译冲突
- **自动检测**：跟随 `EditorInterface.get_editor_settings().get_setting("interface/editor/editor_language")`
- **`t(key)` 函数**：所有 UI 字符串走 `l10n.t("KEY")`

## 三、范围

### 做：

1. **GDSL10n 辅助类** — 封装 TranslationServer + 自定义域
2. **CSV 翻译文件** — `locales/gdscript_util.en.csv`（源语言英文）+ `gdscript_util.zh_CN.csv`
3. **plugin.gd 初始化** — setup/cleanup l10n
4. **UI 字符串替换** — 所有硬编码 UI 文字改用 `t("KEY")`
5. **.pot 模板** — 供外部翻译者使用

### 不做：

- ❌ 完整翻译所有字符串（先做框架 + 核心路径，逐步覆盖）
- ❌ 运行时动态切换（跟随编辑器语言，重启生效）
- ❌ 翻译分析结果（AST 节点名/函数名不翻译）
- ❌ JSON key 翻译 — 导出的 CodeGraph JSON 中所有 key（函数名、节点名等）均为原始标识符，不受 UI 语言影响
- ❌ Output 日志翻译 — 编辑器 Output 面板的调试/错误日志保留英文，仅面向用户的 UI 字符串走翻译系统

## 四、架构

```
addons/gdscript_util/
├── locales/                          # [新增]
│   ├── gdscript_util.en.csv          # 源语言（英文 key→value）
│   └── gdscript_util.zh_CN.csv       # 中文翻译
├── editor/
│   └── gds_l10n.gd                   # [新增] 本地化辅助类
├── plugin.gd                          # [修改] 初始化 l10n
├── editor/gds_editor_bootstrap.gd    # [修改] l10n 引用
└── editor/panels/*.gd                # [修改] 硬编码字符串 → t()
```

### 4.1 GDSL10n 辅助类

> **实现修正 (2026-06-24)**：Godot 4.7 中 `Translation` 没有 `message` 属性。改用 `TranslationServer.get_or_add_domain()` → `TranslationDomain` 系统。`TranslationDomain.add_translation()` + `domain.translate()` 替代旧 API。

```gdscript
# addons/gdscript_util/editor/gds_l10n.gd
# 基于 Godot 4.7 TranslationDomain 系统
class_name GDSL10n
extends RefCounted

const DOMAIN := "gdscript_util"
const LOCALES_DIR := "res://addons/gdscript_util/locales/"

var _domain: TranslationDomain = null
var _loaded := false

func setup() -> void:
	if _loaded:
		return
	_domain = TranslationServer.get_or_add_domain(DOMAIN)
	var dir = DirAccess.open(LOCALES_DIR)
	if dir == null:
		push_warning("[GDSL10n] Cannot open locales dir: " + LOCALES_DIR)
		return
	dir.list_dir_begin()
	var file = dir.get_next()
	while file != "":
		if file.ends_with(".translation"):
			var translation = load(LOCALES_DIR + file) as Translation
			if translation:
				_domain.add_translation(translation)
		file = dir.get_next()
	dir.list_dir_end()
	_loaded = true

func t(p_key: String) -> String:
	if not _loaded:
		return p_key
	var result = _domain.translate(p_key)
	if result == null or result == "" or result == p_key:
		return p_key
	return result
```

> **注意**：CSV 导入必须设 `compress=0`（在 `.csv.import` 文件中）。`compress=1` 生成 `OptimizedTranslation`，其属性不可写且与 `TranslationDomain` 系统兼容性差。

### 4.2 CSV 格式

`gdscript_util.en.csv`（源语言，key = value）：

```csv
keys,en
"tab.summary","Summary"
"tab.call_graph","Call Graph"
"tab.signal_flow","Signal Flow"
"tab.def_use","Def-Use"
"tab.project","Project"
"btn.rebuild","Rebuild Project"
"btn.relayout","Re-layout"
"label.min_degree","Min degree:"
"msg.scan_off","Project scan is OFF"
"msg.scan_off_hint","Click Settings to configure and enable."
"msg.scan_on","Project scan: ON — analyzing..."
"legend.emit","■ emit"
"legend.connect","■ connect"
"legend.entry","▶ Entry function"
"legend.hub","● Hub (degree≥5)"
"msg.no_script","No script open"
"msg.empty_script","Empty script"
"msg.parse_error","Parse error: %s"
```

`gdscript_util.zh_CN.csv`：

```csv
keys,zh_CN
"tab.summary","摘要"
"tab.call_graph","调用图"
"tab.signal_flow","信号流"
"tab.def_use","变量读写"
"tab.project","项目"
"btn.rebuild","重新扫描项目"
"btn.relayout","重新布局"
"label.min_degree","最小度数:"
"msg.scan_off","项目扫描: 关闭"
"msg.scan_off_hint","点击设置配置并启用。"
"msg.scan_on","项目扫描: 开启 — 分析中..."
"legend.emit","■ 发射"
"legend.connect","■ 连接"
"legend.entry","▶ 入口函数"
"legend.hub","● 枢纽(度≥5)"
"msg.no_script","没有打开的脚本"
"msg.empty_script","空脚本"
"msg.parse_error","解析错误: %s"
```

### 4.3 使用方式

**plugin.gd：**
```gdscript
var _l10n: GDSL10n = null

func _enter_tree():
	_l10n = GDSL10n.new()
	_l10n.setup()
	_phase3_bootstrap = GDSEditorBootstrap.new()
	_phase3_bootstrap.setup(self, _l10n)
```

**panels/strings：**
```gdscript
# 之前:
_tab_bar.add_tab("Call Graph")
# 之后:
_tab_bar.add_tab(_l10n.t("tab.call_graph"))
```

### 4.4 翻译覆盖范围

| 优先级 | 覆盖 | 示例 |
|--------|------|------|
| **P0** | Tab 标题、按钮文字 | Call Graph / Summary / Rebuild / Re-layout / Export JSON |
| **P0** | 状态提示 | Scan ON/OFF / No script |
| **P0** | 对话框标题、导出日志 | Export Code Graph / Export OK / Export failed |
| **P1** | 图例 | emit / connect / Entry / Hub |
| **P1** | 面板标题 | Analysis / Min degree |
| **P2** | 错误消息 | Parse error / File not found |
| **P2** | graph 节点副文本 | ref / functions / signals（节点标签/提示） |
| **不做** | 技术术语 | AST 节点名、GDScript 关键字、函数名 |
| **不做** | JSON key | 导出 JSON 中所有标识符保持原始值，不受语言影响 |

## 五、交付物

| 文件 | 类型 | 说明 |
|------|------|------|
| `editor/gds_l10n.gd` | 新增 | 翻译辅助类（domain + t()） |
| `locales/gdscript_util.en.csv` | 新增 | 英文源语言 |
| `locales/gdscript_util.zh_CN.csv` | 新增 | 中文翻译 |
| `plugin.gd` | 修改 | 初始化 l10n |
| `editor/gds_editor_bootstrap.gd` | 修改 | 传递 l10n 给面板 |
| `editor/panels/*.gd` | 修改 | 硬编码 → t() |
| `editor/gds_graph_main_screen.gd` | 修改 | 硬编码 → t() |

## 六、验收标准

- [ ] GDSL10n 类加载 .translation 资源到自定义域
- [ ] `t("tab.call_graph")` 返回 "Call Graph"（英文）或 "调用图"（中文）
- [ ] 编辑器设为中文 → 所有 P0 字符串显示中文
- [ ] 编辑器设为英文 → 所有字符串显示英文
- [ ] 无翻译的 key → 返回 key 本身（优雅降级）
- [ ] 插件卸载不残留翻译
- [ ] Phase 1-3 回归测试全过

## 七、风险

| 风险 | 缓解 |
|------|------|
| CSV → .translation 编译需 Godot 编辑器 | .import 文件配置好，编辑器启动自动编译 |
| 翻译覆盖不全（先做框架） | P0 核心路径先做，P1/P2 逐步覆盖 |
| `t()` 调用散落各文件 | 统一通过 `_l10n` 实例访问，不全局 |
| Godot 4.7 TranslationServer API 差异 | ✅ 已确认：`Translation` 无 `message` 属性，改用 `TranslationDomain` 系统（`get_or_add_domain()` + `add_translation()` + `translate()`） |
| CSV 导入 compress=1 生成 OptimizedTranslation | ✅ 已修复：设 `compress=0`，生成普通 `Translation`，属性可写 |
