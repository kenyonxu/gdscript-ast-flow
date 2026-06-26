# 变更记录

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/) 风格，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [2.1.0] - 2026-06-26

### 新增
- **场景可视化主屏**：主屏新增「场景」mode（与「代码分析」并列），三视角可视化 `.tscn`/`.tres`
  - **节点树视角**：场景列表 + 节点树 + 节点详情（type / script / groups / 信号连接 + 点 script 跳转编辑器）
  - **脚本反查视角**：脚本聚合列表（按引用数）+ 跨场景挂载点 + 视角联动
  - **信号图视角**：GraphEdit 渲染节点间信号连接（同场景蓝 / 跨场景橙）+ 场景筛选下拉 + 中键拖动平移 + 双击节点跳转
  - **视角联动**：反查/信号图点击节点 → 跳节点树视角定位
- **instance 子场景展开**：`instance=ExtResource(...)` 递归解析子场景，合并节点树（type/script 继承 + 覆盖节点挂载 + 环检测）
- **tscn/tres 解析器增强**：
  - UID 引用解析（`uid://`，含 uid-only 无 path 场景）
  - `@export` 填充值提取（关联脚本变量声明）
  - 子资源内联属性解析（Vector2/Color 等常用类型结构化）
  - `.tres` 子资源引用链展开 + 环检测
  - 扫描 ScanConfig UX（`.tscn`/`.tres` 开关 + 增量重分析）
- **GDScript 解析器语法增强**：
  - 表达式后缀（成员访问 `a.b` / 方法调用 `a.b()` / 索引 `a[b]`）—— 解决 if/elif/while 条件含方法调用
  - `%NodeName` 场景唯一节点
  - `;` 分号语句分隔
  - `extends "res://path"` 字符串路径
  - `true`/`false`/`null` 字面量（原当 IDENTIFIER）
  - 行续接（`\` + 换行）
- **UI 改进**：节点树 / 脚本反查视角区域边框 + 三色微差底色

### 变更
- 默认扫描 include 空时返回 `res://`（开箱扫全项目，`addons` 等由 exclude 排除）
- ScanConfig **include 优先于 exclude**（具体性比较：支持 exclude 父目录 + include 子目录，如 `exclude res://addons` + `include res://addons/my_plugin`）

### 修复
- ScanConfig 持久化（`ProjectSettings.save()` 调用缺失，配置重启丢失）
- limboai 行为树 `.tres` 解析（Array of SubResource 字面量致 `str_to_var` 误 load + kv 越界）
- instance 子场景 `parent="."` 节点挂真根（原当根散落，子场景结构不展开）
- 信号参数匹配（`ItemList.item_selected` 带 index / `LineEdit.text_changed` 无参）
- Godot 4.7 兼容（`GraphEdit.pannable` 已移除）
- 解析器错误恢复兜底（遇不支持语法死循环 → 记错并跳过）
- 信号图节点 slug 含 `:` 致 `connect_node` NodePath 解析失败（无连线）

## [1.0.0] - 2026-06-24

- Godot 4.7 AST 重写初版（Phase 1-3：Tokenizer + Parser + SymbolResolver + EditorPlugin 集成）
