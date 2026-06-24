# 插件目录重命名：gdscript_util → gdscript_ast 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `addons/gdscript_util/` 目录重命名为 `addons/gdscript_ast/`，同步更新所有硬编码引用和文档。

**Architecture:** 纯重构任务——先改文件内容（常量、路径、注释），再重命名目录，最后更新文档和打包。无新功能、无新测试。

**Tech Stack:** Godot 4.7 GDScript、CSV 本地化、git mv

---

### Task 1: plugin.cfg — 插件名

**Files:**
- Modify: `addons/gdscript_util/plugin.cfg:3`

- [ ] **Step 1: 修改插件名**

将 `name` 从 `gdscript_util` 改为 `gdscript_ast`：

```
[plugin]

name="gdscript_ast"
description="GDScript AST Flow — AST Parser + Logic Flow Analyzer for Godot 4.7"
author="kenyonxu"
version="1.0.0"
script="plugin.gd"
```

> 同时更新 description 使其更准确地反映插件功能。

- [ ] **Step 2: 验证改动**

```bash
cat addons/gdscript_util/plugin.cfg
```

预期：`name="gdscript_ast"`

---

### Task 2: gds_l10n.gd — 本地化域 + 路径

**Files:**
- Modify: `addons/gdscript_util/editor/gds_l10n.gd:8-9`

- [ ] **Step 1: 修改 DOMAIN 和 LOCALES_DIR**

将第 8-9 行的域名和路径更新：

```gdscript
const DOMAIN := "gdscript_ast"
const LOCALES_DIR := "res://addons/gdscript_ast/locales/"
```

完整文件头部如下：

```gdscript
# addons/gdscript_ast/editor/gds_l10n.gd
class_name GDSL10n
extends RefCounted

const DOMAIN := "gdscript_ast"
const LOCALES_DIR := "res://addons/gdscript_ast/locales/"
```

- [ ] **Step 2: 验证改动**

```bash
grep -n "DOMAIN\|LOCALES_DIR\|gdscript_util" addons/gdscript_util/editor/gds_l10n.gd
```

预期输出中无 `gdscript_util`（除了注释头），DOMAIN 和 LOCALES_DIR 均指向 `gdscript_ast`。

---

### Task 3: gds_scan_config.gd — ProjectSettings 键名

**Files:**
- Modify: `addons/gdscript_util/editor/gds_scan_config.gd:7-9,46,54,56,64`

- [ ] **Step 1: 修改常量定义（第 7-9 行）**

```gdscript
const SETTING_ENABLED := "gdscript_ast/scan/enabled"
const SETTING_INCLUDE := "gdscript_ast/scan/include"
const SETTING_EXCLUDE := "gdscript_ast/scan/exclude"
```

- [ ] **Step 2: 保持旧键迁移逻辑不变（第 46、54、56、64 行）**

第 46 行的 `"gdscript_util/scan/include_dirs"` 和第 56 行的 `"gdscript_util/scan/exclude_dirs"` **不要改**——这是从更早版本迁移用的旧键名，改了就找不到旧数据了。确认：

```bash
grep -n "include_dirs\|exclude_dirs" addons/gdscript_util/editor/gds_scan_config.gd
```

应输出 4 行（第 46、54、56、64 行），均为 `gdscript_util/scan/include_dirs` 和 `gdscript_util/scan/exclude_dirs`（保持不变）。

- [ ] **Step 3: 验证常量定义**

```bash
grep -n "SETTING_" addons/gdscript_util/editor/gds_scan_config.gd
```

预期：所有三个 `SETTING_*` 常量值为 `gdscript_ast/scan/*`。

---

### Task 4: gds_analysis_result.gd — preload 路径

**Files:**
- Modify: `addons/gdscript_util/gds_analysis_result.gd:89`

- [ ] **Step 1: 修改 preload 路径**

```gdscript
const ENTRY_METHODS := preload("res://addons/gdscript_ast/editor/gds_entry_methods.gd")
```

- [ ] **Step 2: 验证无其他硬编码路径**

```bash
grep -rn '"res://addons/gdscript_util' addons/gdscript_util/
```

预期：零结果（这是唯一一处硬编码 `res://` 路径的 preload）。

---

### Task 5: 批量替换所有 .gd 文件注释头

**Files:**
- Modify: 46 个 `.gd` 文件（`addons/gdscript_util/` 下所有 `.gd` 文件）

- [ ] **Step 1: 批量替换注释头中的路径**

每个 `.gd` 文件第一行（或前几行）有 `# addons/gdscript_util/...` 注释头。批量替换：

```bash
find addons/gdscript_util -name "*.gd" -type f -exec sed -i 's|# addons/gdscript_util/|# addons/gdscript_ast/|g' {} +
```

- [ ] **Step 2: 验证替换完成**

```bash
grep -rn "# addons/gdscript_util/" addons/gdscript_util/
```

预期：**零结果**。

```bash
grep -rn "# addons/gdscript_ast/" addons/gdscript_util/ --include="*.gd" | wc -l
```

预期：约 44-46 行（每个 `.gd` 文件至少 1 处，部分文件有子目录级注释）。

- [ ] **Step 3: 顺便检查 gds_builtin_functions.gd 第 3 行**

```bash
head -5 addons/gdscript_util/gds_builtin_functions.gd
```

第 3 行有 `# 来源: Godot 源码 modules/gdscript/gdscript_utility_functions.cpp`——这是 Godot 引擎源码的路径引用，**不要改**。确认保持原样。

---

### Task 6: 重命名 locale 文件

**Files:**
- Rename: `addons/gdscript_util/locales/gdscript_util.en.csv` → `addons/gdscript_util/locales/gdscript_ast.en.csv`
- Rename: `addons/gdscript_util/locales/gdscript_util.en.csv.import` → `addons/gdscript_util/locales/gdscript_ast.en.csv.import`
- Rename: `addons/gdscript_util/locales/gdscript_util.en.en.translation` → `addons/gdscript_util/locales/gdscript_ast.en.en.translation`
- Rename: `addons/gdscript_util/locales/gdscript_util.zh_CN.csv` → `addons/gdscript_util/locales/gdscript_ast.zh_CN.csv`
- Rename: `addons/gdscript_util/locales/gdscript_util.zh_CN.csv.import` → `addons/gdscript_util/locales/gdscript_ast.zh_CN.csv.import`
- Rename: `addons/gdscript_util/locales/gdscript_util.zh_CN.zh_CN.translation` → `addons/gdscript_util/locales/gdscript_ast.zh_CN.zh_CN.translation`

- [ ] **Step 1: 执行重命名**

```bash
cd addons/gdscript_util/locales

# 英文文件
mv gdscript_util.en.csv gdscript_ast.en.csv
mv gdscript_util.en.csv.import gdscript_ast.en.csv.import
mv gdscript_util.en.en.translation gdscript_ast.en.en.translation

# 中文文件
mv gdscript_util.zh_CN.csv gdscript_ast.zh_CN.csv
mv gdscript_util.zh_CN.csv.import gdscript_ast.zh_CN.csv.import
mv gdscript_util.zh_CN.zh_CN.translation gdscript_ast.zh_CN.zh_CN.translation
```

- [ ] **Step 2: 验证重命名完成**

```bash
ls -1 addons/gdscript_util/locales/
```

预期输出：
```
gdscript_ast.en.csv
gdscript_ast.en.csv.import
gdscript_ast.en.en.translation
gdscript_ast.zh_CN.csv
gdscript_ast.zh_CN.csv.import
gdscript_ast.zh_CN.zh_CN.translation
```

- [ ] **Step 3: 更新 .csv.import 文件中的引用（如存在）**

检查 `.csv.import` 文件中是否有对旧文件名的引用：

```bash
grep "gdscript_util" addons/gdscript_util/locales/*.import
```

如有匹配，手动更新为 `gdscript_ast`。大概率无需修改——Godot 的 `.import` 文件引用的是源文件哈希，不包含文件名。

---

### Task 7: 目录重命名

**Files:**
- Rename: `addons/gdscript_util/` → `addons/gdscript_ast/`

- [ ] **Step 1: 确认 addons/ 下无其他 gdscript_util 引用**

```bash
grep -rn "gdscript_util" addons/gdscript_util/ --include="*.gd" --include="*.cfg" --include="*.csv" --include="*.import" | grep -v "//\|# 来源" | grep -v "include_dirs\|exclude_dirs"
```

预期只有两处残留：
- `gds_scan_config.gd` 第 46、54、56、64 行的旧键迁移（`gdscript_util/scan/include_dirs`、`gdscript_util/scan/exclude_dirs`）——这些是故意的
- `gds_builtin_functions.gd` 第 3 行 `modules/gdscript/gdscript_utility_functions.cpp`——Godot 引擎源码路径，不相关

- [ ] **Step 2: 执行目录重命名**

在 Git 中，用 `git mv` 而非普通 `mv` 以便 Git 正确跟踪文件历史：

```bash
git mv addons/gdscript_util addons/gdscript_ast
```

- [ ] **Step 3: 确认 git 状态**

```bash
git status --short addons/
```

预期：所有文件显示为 `R`（renamed），而非 `D` + `A`。

---

### Task 8: 重新扫描 addons/ 确认零泄漏

**Files:** (验证步骤，不修改文件)

- [ ] **Step 1: 扫描 addons/gdscript_ast/ 下所有源文件中是否还有旧名称**

```bash
grep -rn "gdscript_util" addons/gdscript_ast/ --include="*.gd" --include="*.cfg" --include="*.csv" --include="*.import" | grep -v "include_dirs\|exclude_dirs\|gdscript_utility_functions.cpp"
```

预期输出为空（除了上述 2 类故意的例外）。

如果 `git mv` 后 `addons/gdscript_util/` 仍有残留文件，说明重命名不完整——回到 Task 7 检查。

- [ ] **Step 2: 确认旧目录已不存在**

```bash
test -d addons/gdscript_util && echo "STILL EXISTS" || echo "OK: removed"
```

预期: `OK: removed`

---

### Task 9: 更新 CLAUDE.md

**Files:**
- Modify: `CLAUDE.md:21-37`

- [ ] **Step 1: 替换项目结构中的路径**

```diff
- addons/gdscript_util/
+ addons/gdscript_ast/
```

- [ ] **Step 2: 验证**

```bash
grep "gdscript_util" CLAUDE.md
```

预期：零结果。

---

### Task 10: 更新 addons/gdscript_ast/docs/ 下的文档

**Files:**
- Modify: `addons/gdscript_ast/docs/user_guide_cn.md`
- Modify: `addons/gdscript_ast/docs/user_guide_en.md`
- Modify: `addons/gdscript_ast/docs/dev_guide_cn.md`
- Modify: `addons/gdscript_ast/docs/dev_guide_en.md`

- [ ] **Step 1: 批量替换 4 个文档中的路径**

```bash
find addons/gdscript_ast/docs -name "*.md" -type f -exec sed -i 's|addons/gdscript_util|addons/gdscript_ast|g' {} +
```

- [ ] **Step 2: 替换 dev_guide_cn.md 中的 ProjectSettings 键名**

`dev_guide_cn.md` 中有 `gdscript_util/scan/*` 示例代码（第 254-256 行, 第 286 行），需更新：

```bash
sed -i 's|"gdscript_util/|"gdscript_ast/|g' addons/gdscript_ast/docs/dev_guide_cn.md
```

- [ ] **Step 3: 验证**

```bash
grep -rn "gdscript_util" addons/gdscript_ast/docs/
```

预期：零结果。

---

### Task 11: 更新根目录 README 文件

**Files:**
- Modify: `readme.md`（如含路径引用）
- Modify: `README.en.md`（如含路径引用）

- [ ] **Step 1: 检查是否有旧路径引用**

```bash
grep -n "gdscript_util" readme.md README.en.md 2>/dev/null
```

- [ ] **Step 2: 如有，替换之**

```bash
sed -i 's|addons/gdscript_util|addons/gdscript_ast|g' readme.md README.en.md 2>/dev/null
sed -i 's|gdscript_util|gdscript_ast|g' readme.md README.en.md 2>/dev/null
```

- [ ] **Step 3: 验证**

```bash
grep "gdscript_util" readme.md README.en.md 2>/dev/null
```

预期：零结果。

---

### Task 12: 重新打包 release

**Files:**
- Delete: `release/gdscript_util_v1.0.0.zip`
- Create: `release/gdscript_ast_v1.0.0.zip`

- [ ] **Step 1: 删除旧 zip**

```bash
rm release/gdscript_util_v1.0.0.zip
```

- [ ] **Step 2: 打包新版本**

```bash
cd addons && zip -r ../release/gdscript_ast_v1.0.0.zip gdscript_ast/
```

- [ ] **Step 3: 验证 zip 内容**

```bash
unzip -l release/gdscript_ast_v1.0.0.zip | head -20
```

预期：所有文件路径以 `gdscript_ast/` 开头，无 `gdscript_util`。

---

### Task 13: 最终全局验证

**Files:** (验证步骤，不修改文件)

- [ ] **Step 1: 全仓库扫描（排除 graphify-out 和 docs/superpowers 历史文档）**

```bash
grep -rn "gdscript_util" . --include="*.gd" --include="*.cfg" --include="*.md" --include="*.csv" --include="*.import" \
  | grep -v "graphify-out/" \
  | grep -v "docs/superpowers/" \
  | grep -v "include_dirs\|exclude_dirs" \
  | grep -v "gdscript_utility_functions.cpp" \
  | grep -v "\.git/"
```

预期输出：**零行**。

- [ ] **Step 2: 确认 .gitignore 和 release 目录状态**

```bash
cat .gitignore | grep -i "release"
ls -la release/
```

预期：`.gitignore` 中有 `release/` 忽略规则，release 目录下只有 `gdscript_ast_v1.0.0.zip`。

- [ ] **Step 3: git diff 概览**

```bash
git diff --stat
```

预期：大量 `R`（rename）行，少量 `M`（modify）行。无意外的新增或删除。

- [ ] **Step 4: 提交**

```bash
git add -A
git commit -m "refactor: rename addon gdscript_util → gdscript_ast

Breaking: ProjectSettings keys changed from gdscript_util/scan/* to
gdscript_ast/scan/*. Users must reconfigure scan settings after update.

- plugin.cfg: name gdscript_util → gdscript_ast
- gds_l10n.gd: DOMAIN + LOCALES_DIR updated
- gds_scan_config.gd: ProjectSettings key prefix updated
- gds_analysis_result.gd: preload path updated
- All .gd file header comments updated
- Locale files renamed (6 files)
- Active docs updated (CLAUDE.md, READMEs, guides)
- Old migration keys (include_dirs/exclude_dirs) intentionally preserved"
```

---

### 执行检查清单

| # | 检查项 | 预期 |
|---|--------|------|
| 1 | `plugin.cfg` 中 `name="gdscript_ast"` | ✓ |
| 2 | `gds_l10n.gd` DOMAIN = `"gdscript_ast"` | ✓ |
| 3 | `gds_l10n.gd` LOCALES_DIR 指向 `res://addons/gdscript_ast/locales/` | ✓ |
| 4 | `gds_scan_config.gd` 三个常量键名前缀为 `gdscript_ast/` | ✓ |
| 5 | `gds_scan_config.gd` 旧键迁移路径保持 `gdscript_util/` 不变 | ✓ |
| 6 | `gds_analysis_result.gd` preload 路径更新 | ✓ |
| 7 | 46 个 `.gd` 文件注释头均为 `# addons/gdscript_ast/...` | ✓ |
| 8 | `gds_builtin_functions.gd` 第 3 行 Godot 引擎路径未改 | ✓ |
| 9 | 6 个 locale 文件已重命名 | ✓ |
| 10 | `addons/gdscript_util/` 目录不存在 | ✓ |
| 11 | `addons/gdscript_ast/` 目录存在 | ✓ |
| 12 | `git status` 显示 rename + modify（非 delete + add） | ✓ |
| 13 | CLAUDE.md 中无旧路径 | ✓ |
| 14 | `addons/gdscript_ast/docs/` 下 4 个 md 无旧路径 | ✓ |
| 15 | README 文件中无旧路径 | ✓ |
| 16 | `release/gdscript_ast_v1.0.0.zip` 存在且内容正确 | ✓ |
| 17 | 全仓库全局扫描无残留（排除 graphify-out 和历史 spec/plan） | ✓ |
