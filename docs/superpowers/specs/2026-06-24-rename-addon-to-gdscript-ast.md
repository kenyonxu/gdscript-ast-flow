# 插件目录重命名：gdscript_util → gdscript_ast 设计规范

> 日期: 2026-06-24 | 状态: 待实施 📋 | 依赖: 无

## 修订历史

| 日期 | 变更 |
|------|------|
| 2026-06-24 | 初版：完整影响面分析 + 改动清单 + 实施步骤 |

## 一、动机

当前插件目录名 `addons/gdscript_util` 存在两个问题：

1. **语义不准确** — `util`（工具集）暗示杂项工具集合，但插件核心是 GDScript AST 解析 + 逻辑流分析，`ast` 更能表达项目本质
2. **与项目名不一致** — 仓库名为 `gdscript-ast-flow`，而插件目录叫 `gdscript_util`，用户在 Asset Library 看到的是 `gdscript_util`，与仓库名脱节

**目标**：将 `addons/gdscript_util/` 重命名为 `addons/gdscript_ast/`，同步更新所有硬编码引用。

## 二、原则

1. **class_name 不动** — 所有 `GDS*` / `GDScript*` class_name 不含目录名，无须更改
2. **最小影响范围** — 改动集中在常量定义处，不动数据结构与算法逻辑
3. **向后兼容** — ProjectSettings 旧键迁移逻辑保留（`include_dirs` → `include`），但**不**做 `gdscript_util/` → `gdscript_ast/` 的键名迁移（用户需在 Project Settings 中手动更新，或重新配置扫描设置）
4. **文档同步** — 不追求历史 spec/plan 文档完全一致（那是历史快照），但活跃文档（CLAUDE.md、README、dev_guide、user_guide）必须更新

## 三、范围

### 做：

1. 目录重命名：`addons/gdscript_util/` → `addons/gdscript_ast/`
2. 功能性代码改动（4 个 `.gd` 文件的关键常量/路径）
3. 本地化文件名联动（6 个文件）
4. 注释头批量替换（~25 个 `.gd` 文件）
5. 活跃文档更新（CLAUDE.md、readme.md、README.en.md、dev_guide、user_guide）
6. `release/` 重新打包

### 不做：

- ❌ class_name 改名（所有 class_name 已经是 `GDS*`，不含 `util`）
- ❌ ProjectSettings 键名自动迁移（`gdscript_util/scan/*` → `gdscript_ast/scan/*`）— 用户手动更新
- ❌ `graphify-out/` 重建 — 目录改名后重新运行 `graphify update .` 即可
- ❌ 历史 spec/plan 文档中的旧路径（它们是设计过程的历史快照）

## 四、改动清单

### 🔴 Tier 1 — 功能性（不改插件加载/运行必崩）

#### F1. plugin.cfg — 插件名

**文件**: `addons/gdscript_ast/plugin.cfg`

```diff
- name="gdscript_util"
+ name="gdscript_ast"
```

**影响**: Godot 编辑器中显示的插件名、Asset Library 注册名。**这是用户感知层面最重要的改动。**

#### F2. gds_l10n.gd — 本地化域 + 路径

**文件**: `addons/gdscript_ast/editor/gds_l10n.gd`

```diff
- const DOMAIN := "gdscript_util"
+ const DOMAIN := "gdscript_ast"

- const LOCALES_DIR := "res://addons/gdscript_util/locales/"
+ const LOCALES_DIR := "res://addons/gdscript_ast/locales/"
```

**影响**: 
- `DOMAIN` 决定 TranslationServer 中的域名 → 必须与 CSV 文件名前缀一致
- `LOCALES_DIR` 决定翻译文件加载路径 → 目录改名后旧路径失效

#### F3. gds_scan_config.gd — ProjectSettings 键名

**文件**: `addons/gdscript_ast/editor/gds_scan_config.gd`

```diff
- const SETTING_ENABLED := "gdscript_util/scan/enabled"
+ const SETTING_ENABLED := "gdscript_ast/scan/enabled"

- const SETTING_INCLUDE := "gdscript_util/scan/include"
+ const SETTING_INCLUDE := "gdscript_ast/scan/include"

- const SETTING_EXCLUDE := "gdscript_util/scan/exclude"
+ const SETTING_EXCLUDE := "gdscript_ast/scan/exclude"
```

**同时更新旧键迁移代码**（第 46、54、56、64 行）— 保持迁移逻辑引用的旧键名不变（那是从更早版本迁移用的），但新增的读写键名改为新前缀。

**⚠️ 破坏性变更**：已有项目的 `gdscript_util/scan/*` ProjectSettings 配置将失效，用户需重新配置。建议在 release notes 中明确说明。

#### F4. gds_analysis_result.gd — preload 路径

**文件**: `addons/gdscript_ast/gds_analysis_result.gd`

```diff
- const ENTRY_METHODS := preload("res://addons/gdscript_util/editor/gds_entry_methods.gd")
+ const ENTRY_METHODS := preload("res://addons/gdscript_ast/editor/gds_entry_methods.gd")
```

**影响**: 这是唯一的硬编码 `preload` 路径。其他 GDScript 文件通过 `class_name` 互相引用，无需路径。

### 🟡 Tier 2 — 本地化文件名联动（纯重命名）

| # | 旧文件名 | 新文件名 |
|---|---------|---------|
| L1 | `locales/gdscript_util.en.csv` | `locales/gdscript_ast.en.csv` |
| L2 | `locales/gdscript_util.en.csv.import` | `locales/gdscript_ast.en.csv.import` |
| L3 | `locales/gdscript_util.zh_CN.csv` | `locales/gdscript_ast.zh_CN.csv` |
| L4 | `locales/gdscript_util.zh_CN.csv.import` | `locales/gdscript_ast.zh_CN.csv.import` |
| L5 | `locales/gdscript_util.en.en.translation` | `locales/gdscript_ast.en.en.translation` |
| L6 | `locales/gdscript_util.zh_CN.zh_CN.translation` | `locales/gdscript_ast.zh_CN.zh_CN.translation` |

**注意**: `.csv.import` 和 `.translation` 文件由 Godot 自动生成。`.csv.import` 中包含对源 CSV 的引用，改名后 Godot 会重新导入生成新的 `.translation`。但为保持干净，建议手动同步改名。

### 🟢 Tier 3 — 注释头（批量替换）

**影响范围**: `addons/gdscript_ast/` 下所有 `.gd` 文件（含子目录），约 35 个文件。

每个文件第一行注释：
```diff
- # addons/gdscript_util/gds_xxx.gd
+ # addons/gdscript_ast/gds_xxx.gd
```

以及中间目录级文件：
```diff
- # addons/gdscript_util/editor/gds_xxx.gd
+ # addons/gdscript_ast/editor/gds_xxx.gd
```

**操作**: 一条正则批量替换即可：
```
查找: # addons/gdscript_util/
替换: # addons/gdscript_ast/
```

### 🔵 Tier 4 — 活跃文档

| 文件 | 改动量 | 说明 |
|------|--------|------|
| `CLAUDE.md` | ~1 处 | 项目结构图 |
| `readme.md` | ~3 处 | 安装说明中的路径 |
| `README.en.md` | ~3 处 | 英文安装说明 |
| `addons/gdscript_ast/docs/user_guide_cn.md` | ~1 处 | 用户指南安装步骤 |
| `addons/gdscript_ast/docs/user_guide_en.md` | ~1 处 | 英文用户指南 |
| `addons/gdscript_ast/docs/dev_guide_cn.md` | ~10 处 | 开发者指南中的文件路径引用 |
| `addons/gdscript_ast/docs/dev_guide_en.md` | ~8 处 | 英文开发者指南 |

### ⚫ 不在此次范围

| 项目 | 原因 |
|------|------|
| `graphify-out/graph.json` | 目录改名后重新运行 `graphify update .` 即可重建 |
| `graphify-out/graph.html` | 同上 |
| `release/gdscript_util_v1.0.0.zip` | 实施后重新打包为 `gdscript_ast_v1.0.0.zip` |
| `docs/superpowers/specs/*.md` | 历史设计快照，不改 |
| `docs/superpowers/plans/*.md` | 历史实施记录，不改 |
| 所有 `class_name` 声明 | 值中不含 `util`，不受影响 |

## 五、实施步骤

### Phase 1: 代码改动（先改内容）

```bash
# Step 1: 改 plugin.cfg
#   name="gdscript_util" → name="gdscript_ast"

# Step 2: 改 gds_l10n.gd
#   DOMAIN "gdscript_util" → "gdscript_ast"
#   LOCALES_DIR 路径更新

# Step 3: 改 gds_scan_config.gd
#   ProjectSettings 键名前缀更新

# Step 4: 改 gds_analysis_result.gd
#   preload 路径更新

# Step 5: 批量替换所有 .gd 文件注释头
#   # addons/gdscript_util/ → # addons/gdscript_ast/

# Step 6: 重命名 locale 文件
#   gdscript_util.* → gdscript_ast.*
```

### Phase 2: 目录重命名

```bash
mv addons/gdscript_util addons/gdscript_ast
```

### Phase 3: 文档更新

更新 Tier 4 中列出的所有活跃文档。

### Phase 4: 验证

1. Godot 编辑器中重新加载项目 → 插件应正常加载
2. 工具菜单显示 "GDScript AST Flow" → 能正常解析脚本
3. 扫描设置对话框正常弹出
4. 本地化切换中英文正常
5. git status 确认改动干净

### Phase 5: 重新打包

```bash
# 删除旧 zip
rm release/gdscript_util_v1.0.0.zip
# 打包新版本
cd addons && zip -r ../release/gdscript_ast_v1.0.0.zip gdscript_ast/
```

## 六、风险评估

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| Godot 编辑器缓存旧插件路径导致加载失败 | 中 | 高 | 实施后需在 Godot 中禁用→启用插件，或重启编辑器 |
| `.uid` 文件失效 | 低 | 低 | `.uid` 文件与脚本内容关联（基于 class_name），不依赖文件路径；即使失效 Godot 也会自动重建 |
| 已有用户的 ProjectSettings 配置丢失 | 高 | 中 | 在 release notes 中明确说明，旧键 `gdscript_util/scan/*` 不再生效，需重新配置 |
| 外部依赖（如 Asset Library）引用旧路径 | 低 | 低 | Asset Library 提交时更新即可 |
| `.translation` 文件路径嵌入了旧域名 | 中 | 低 | `.translation` 是 Godot 编译产物，重新导入 CSV 后自动更新；不手动改也无害（下次导入覆盖） |

## 七、向后兼容说明

### 对已安装用户的影响

1. **插件更新方式**：直接替换 `addons/gdscript_ast/` 目录即可。旧目录 `addons/gdscript_util/` 需手动删除（不然会有两个插件实例冲突）。
2. **ProjectSettings**：扫描配置键名变更。如果用户之前配置过 `gdscript_util/scan/*`，更新后这些设置不再被读取。用户需重新在 "Scan Settings" 对话框中配置。
3. **`.godot/` 缓存**：建议删除 `.godot/` 让 Godot 重新索引（编辑器会自动重建）。

### 版本号

建议在 `plugin.cfg` 中升级主版本号或至少标记为 breaking change：

```
version="1.1.0"  # 或 "2.0.0" 如果认为 ProjectSettings 键名变更是 breaking
```

## 八、完成标准

- [ ] 目录 `addons/gdscript_ast/` 存在，`addons/gdscript_util/` 不存在
- [ ] `git grep "gdscript_util" addons/` 在 `addons/` 下**零结果**（除了旧键迁移代码中的字符串值）
- [ ] Godot 编辑器中插件加载无报错
- [ ] "Parse Current" 功能正常
- [ ] "Scan Settings" 对话框正常
- [ ] 中英文切换正常
- [ ] `release/gdscript_ast_v1.0.0.zip` 存在且可解压
- [ ] CLAUDE.md、README、dev_guide、user_guide 中无旧路径引用
