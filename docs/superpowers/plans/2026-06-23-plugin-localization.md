# 插件本地化 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 参考 clef-dev 的 TranslationDomain 模式，为插件 UI 提供 CSV 驱动的多语言支持（英文源 + 中文翻译）。

**Architecture:** GDSL10n 辅助类管理自定义域 "gdscript_util"；CSV → .translation 资源；plugin.gd 初始化；面板字符串改用 `t("KEY")`。

**Tech Stack:** Godot 4.7, GDScript, TranslationServer, CSV

**Spec reference:** `docs/superpowers/specs/2026-06-23-plugin-localization.md`

---

## Task 1: 创建 CSV 翻译文件

**Files:** Create: `addons/gdscript_util/locales/gdscript_util.en.csv`, `addons/gdscript_util/locales/gdscript_util.zh_CN.csv`

- [ ] **Step 1: 创建英文源 CSV**

```csv
keys,en
"tab.summary","Summary"
"tab.call_graph","Call Graph"
"tab.signal_flow","Signal Flow"
"tab.def_use","Def-Use"
"tab.project","Project"
"btn.rebuild","Rebuild Project"
"btn.relayout","Re-layout"
"btn.settings","Settings"
"label.min_degree","Min degree:"
"label.scope","Scope:"
"label.graph","Graph:"
"scope.current_file","Current File"
"scope.project","Project"
"graph.call","Call"
"graph.signal","Signal"
"msg.scan_on","Project scan: ON — analyzing..."
"msg.scan_off","Project scan: OFF. Configure in Project Settings."
"msg.scan_off_hint","Project scan is OFF"
"msg.scan_off_hint2","Enable in Project Settings > GDScript Util > Scan"
"msg.no_script","No script open"
"msg.empty_script","Empty script"
"msg.parse_error","Parse error: %s"
"legend.emit","emit"
"legend.connect","connect"
"legend.emit_connect","emit+connect"
"legend.entry","Entry function"
"legend.hub","Hub (degree≥5)"
"legend.high_coupling","High coupling file"
"node.refs","ref"
"node.functions","functions"
"node.signals","signals"
```

- [ ] **Step 2: 创建中文 CSV**

```csv
keys,zh_CN
"tab.summary","摘要"
"tab.call_graph","调用图"
"tab.signal_flow","信号流"
"tab.def_use","变量读写"
"tab.project","项目"
"btn.rebuild","重新扫描"
"btn.relayout","重新布局"
"btn.settings","设置"
"label.min_degree","最小度数:"
"label.scope","范围:"
"label.graph","图表:"
"scope.current_file","当前文件"
"scope.project","项目"
"graph.call","调用"
"graph.signal","信号"
"msg.scan_on","项目扫描: 开启 — 分析中..."
"msg.scan_off","项目扫描: 关闭。在项目设置中配置。"
"msg.scan_off_hint","项目扫描: 关闭"
"msg.scan_off_hint2","在 项目设置 > GDScript Util > Scan 中启用"
"msg.no_script","没有打开的脚本"
"msg.empty_script","空脚本"
"msg.parse_error","解析错误: %s"
"legend.emit","发射"
"legend.connect","连接"
"legend.emit_connect","发射+连接"
"legend.entry","入口函数"
"legend.hub","枢纽(度≥5)"
"legend.high_coupling","高耦合文件"
"node.refs","引用"
"node.functions","函数"
"node.signals","信号"
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/locales/
git commit -m "feat: CSV translation files — en (source) + zh_CN"
```

---

## Task 2: 创建 GDSL10n 辅助类

**Files:** Create: `addons/gdscript_util/editor/gds_l10n.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/gds_l10n.gd
# 插件本地化辅助 — 基于 Godot TranslationServer 自定义域
# 参考: clef-dev/addons/clef/editor/clef_l10n.gd

class_name GDSL10n
extends RefCounted

const DOMAIN := "gdscript_util"
const LOCALES_DIR := "res://addons/gdscript_util/locales/"

var _loaded := false

func setup() -> void:
	if _loaded:
		return
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
				translation.message = DOMAIN
				TranslationServer.add_translation(translation)
		file = dir.get_next()
	dir.list_dir_end()
	_loaded = true

func t(p_key: String) -> String:
	if not _loaded:
		return p_key
	var result = TranslationServer.translate(p_key, DOMAIN)
	# translate 返回空串或 key 本身时降级
	if result == null or result == "" or result == p_key:
		return p_key
	return result

# 支持格式化: t("msg.parse_error") % "具体错误"
func tf(p_key: String, p_args: Array) -> String:
	return t(p_key) % p_args
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_l10n.gd
git commit -m "feat: GDSL10n — localization helper with custom translation domain"
```

---

## Task 3: plugin.gd + bootstrap 初始化 l10n

**Files:** Modify: `addons/gdscript_util/plugin.gd`, `addons/gdscript_util/editor/gds_editor_bootstrap.gd`

- [ ] **Step 1: plugin.gd _enter_tree 初始化**

```gdscript
var _l10n: GDSL10n = null

func _enter_tree():
	_l10n = GDSL10n.new()
	_l10n.setup()
	# ... 已有代码 ...
	_phase3_bootstrap = GDSEditorBootstrap.new()
	_phase3_bootstrap.setup(self, _l10n)
```

- [ ] **Step 2: bootstrap.setup 接收 l10n**

```gdscript
var _l10n: GDSL10n = null

func setup(p_plugin: EditorPlugin, p_l10n: GDSL10n = null) -> void:
	_plugin = p_plugin
	_l10n = p_l10n if p_l10n else GDSL10n.new()
	# ... 已有代码，面板创建时传 _l10n ...
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/plugin.gd addons/gdscript_util/editor/gds_editor_bootstrap.gd
git commit -m "feat: plugin + bootstrap — initialize GDSL10n and pass to panels"
```

---

## Task 4: 底部面板字符串替换（P0）

**Files:** Modify: `addons/gdscript_util/editor/panels/gds_analysis_main_panel.gd`, `gds_project_panel.gd`, `gds_analysis_summary.gd`

- [ ] **Step 1: main_panel TabBar 标题**

```gdscript
# 之前:
_tab_bar.add_tab("Summary")
_tab_bar.add_tab("Call Graph")
# 之后:
_tab_bar.add_tab(_l10n.t("tab.summary"))
_tab_bar.add_tab(_l10n.t("tab.call_graph"))
```

每个面板的 `setup` 方法加 `p_l10n` 参数。

- [ ] **Step 2: project_panel 按钮 + 提示**

```gdscript
_rebuild_btn.text = _l10n.t("btn.rebuild")
# 禁用态:
item.set_text(0, _l10n.t("msg.scan_off_hint"))
```

- [ ] **Step 3: summary 面板状态文字**

- [ ] **Step 4: 提交**

```bash
git add addons/gdscript_util/editor/panels/
git commit -m "feat: bottom panels — P0 strings localized (tabs/buttons/messages)"
```

---

## Task 5: 主屏图视图字符串替换（P0-P1）

**Files:** Modify: `addons/gdscript_util/editor/gds_graph_main_screen.gd`

- [ ] **Step 1: toolbar + legend 替换**

```gdscript
scope_box.add_item(_l10n.t("scope.current_file"), 0)
scope_box.add_item(_l10n.t("scope.project"), 1)
relayout.text = _l10n.t("btn.relayout")
# legend:
_add_legend_chip(_legend, _l10n.t("legend.emit"), Color.RED)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_graph_main_screen.gd
git commit -m "feat: graph main screen — toolbar + legend strings localized"
```

---

## Task 6: 验收

- [ ] **Step 1: 编辑器设英文** — Editor Settings → Language → English → 重启 → 确认所有 P0 字符串英文
- [ ] **Step 2: 编辑器设中文** — Editor Settings → Language → 简体中文 → 重启 → 确认 P0 字符串中文
- [ ] **Step 3: 无翻译的 key** — 确认显示 key 本身（不崩溃/不空白）
- [ ] **Step 4: Phase 1-3 回归** — 功能不受影响

---

## 完成检查清单

- [ ] CSV 文件（en + zh_CN）
- [ ] GDSL10n 辅助类
- [ ] plugin.gd + bootstrap 初始化
- [ ] 底部面板 P0 字符串替换
- [ ] 主屏图视图 P0-P1 字符串替换
- [ ] 英文/中文切换验证
- [ ] 优雅降级（无翻译 → key 本身）
