# Phase 3.2: 跨文件分析 设计规范

> 日期: 2026-06-21 | 状态: 设计中 | 依赖: Phase 3 v1 (已完成 ✅)

## 一、目标

将分析能力从**单文件**扩展到**项目级**：编辑一个文件时，能看到其他文件里的代码如何引用它——谁跨文件调用了这个函数、谁连接了这个信号、谁实例化了这个类。

**核心问题（Phase 3 v1 无法回答）：**
- "我改了 `Player.take_damage()`，哪些其他文件的代码调用了它？"
- "`health_changed` 信号在 `Enemy.gd` 里被 connect，emit 在 `Player.gd`——跨文件链路"
- "`Player` 类被哪些文件实例化/继承？"

## 二、范围

### Phase 3.2 做：

1. **项目扫描** — 发现 `res://` 下所有 `.gd` 文件
2. **批量分析** — 对每个文件跑 Phase 1+2 单文件管道，缓存结果
3. **类注册表** — 扫描所有文件的 `class_name` 声明，建 `{class_name → file_path}` 映射
4. **类型表** — 每个文件记录变量/参数的**声明类型**（静态可知）
5. **跨文件调用解析** — `obj.method()` 当 `obj` 类型静态已知且为用户类时，解析到目标文件
6. **跨文件信号流** — `obj.connect("sig", OtherFile.func)` / `obj.emit("sig")` 跨文件
7. **增量分析** — 仅重新分析变更文件 + 受影响的跨文件边
8. **UI** — 底部面板新增 "Project" tab

### Phase 3.2 不做（Phase 3.3 / 后续）：

- ❌ **动态分派** — `var x = get_node("..")` 运行时类型，无法静态解析
- ❌ **完整类型推断** — `var x := some_func()` 的返回类型推断（需函数返回类型分析，Phase 3.3）
- ❌ **主屏图可视化** — 项目级 GraphEdit 调用图（Phase 3.3）
- ❌ **热路径 custom-draw**（依赖调用频率统计，Phase 3.3）
- ❌ **f-string `{expr}` 真解析**（独立小项，可并行，不阻塞）

## 三、架构

```
addons/gdscript_util/
├── [Phase 1-3v1 不变] 单文件管道
├── editor/
│   ├── gds_analysis_bridge.gd          # [修改] 增加 project 分析入口
│   ├── gds_project_analyzer.gd         # [新增] 项目级分析器
│   └── panels/
│       └── gds_project_panel.gd        # [新增] Project tab 面板
├── gds_project_result.gd               # [新增] 项目级结果容器
├── gds_cross_file_edge.gd              # [新增] 跨文件调用/信号边
├── gds_analysis_result.gd              # [修改] 增加类型表字段
└── gds_symbol_resolver.gd              # [修改] 记录变量声明类型到类型表
```

### 3.1 分析流程

```
GDScriptProjectAnalyzer
│
├─ 1. scan_project(root)          → [file_path] 列表
├─ 2. analyze_all()               → 每文件跑单文件管道，缓存 AnalysisResult
├─ 3. build_class_registry()      → {class_name: file_path}（扫各文件 classname_id）
├─ 4. build_type_tables()         → 每文件 {var/param name: 类型字符串}
└─ 5. resolve_cross_file()        → 第二遍扫描，用类注册表+类型表解析跨文件调用/信号
                                    → 产出 CrossFileEdge 列表
```

**两遍设计**：第一遍建单文件结果 + 全局类注册表；第二遍才能解析跨文件引用（因为目标文件可能还没分析）。

### 3.2 增量分析

```
保存文件 A.gd:
  1. 重分析 A.gd（单文件管道）— 复用 Phase 3 时间戳缓存
  2. 若 A.gd 的 class_name 变了 → 重建类注册表
  3. 重解析所有"引用 A 的类"的文件的跨文件边
     （反向索引：{target_class → [引用它的文件]}，避免全扫）
```

## 四、数据结构

### 4.1 类型表（加到 GDScriptAnalysisResult）

```gdscript
# gds_analysis_result.gd 新增字段
var type_table: Dictionary = {}  # String(var/param name) → String(类型名)
# 来源: var x: Player / func f(p: Enemy) / @onready var n: Node = $X
```

由 `GDScriptSymbolResolver` 在解析变量/参数时填充 `datatype`（已有字段，Phase 2 存了但单文件没用）。

### 4.2 跨文件边

```gdscript
# gds_cross_file_edge.gd
class_name GDScriptCrossFileEdge
extends RefCounted

enum Kind { CALL, SIGNAL_EMIT, SIGNAL_CONNECT, INSTANCE, EXTENDS }

var kind: int
var source_file: String       # 调用方/连接方文件
var source_symbol: String     # 调用函数名 / 连接回调名
var target_file: String       # 被调用/被连接的类所在文件
var target_class: String      # 目标类名
var target_symbol: String     # 目标方法/信号名
var line: int
```

### 4.3 项目结果容器

```gdscript
# gds_project_result.gd
class_name GDScriptProjectResult
extends RefCounted

var root_path: String
var files: Dictionary = {}           # String(path) → GDScriptAnalysisResult
var class_registry: Dictionary = {}  # String(class_name) → String(file_path)
var reverse_index: Dictionary = {}   # String(file_path) → [引用它的 file_path]
var cross_edges: Array = []          # of GDScriptCrossFileEdge

# 查询 API
func get_callers_across_files(p_class: String, p_method: String) -> Array
func get_signal_flow_across_files(p_signal: String) -> Array
func get_files_referencing(p_file: String) -> Array
```

## 五、跨文件调用解析策略

### 5.1 类型来源（静态可知）

| 语法 | 类型来源 | 示例 |
|------|---------|------|
| `var x: T = ...` | 显式标注 | `var player: Player` |
| `func f(p: T)` | 参数标注 | `func hit(e: Enemy)` |
| `@onready var n: T = $N` | onready 标注 | `@onready var ui: UI = $UI` |
| `T.new()` | 实例化 | `Player.new()` → T=Player |
| `preload("x.gd")` | preload 路径 | 直接得到 file_path |
| `extends T` | 继承 | self 的父类 |

### 5.2 解析 `obj.method()`

```
obj.method() 出现在文件 F:
  1. 查 F 的类型表: obj 的类型 T = type_table["obj"]
  2. 若 T == null → 跳过（动态类型，Phase 3.3）
  3. 查类注册表: T 的文件 TF = class_registry[T]
  4. 若 TF == null → T 是内置类（Node/Object 等），跳过
  5. 查 TF 的 symbol_table: 有没有 method
  6. 有 → 产出 CrossFileEdge(CALL, F→TF, target=T.method)
```

### 5.3 解析 `obj.connect("sig", cb)` / `obj.emit("sig")`

同 5.2，但 Kind = SIGNAL_CONNECT / SIGNAL_EMIT，target_symbol = "sig"。

### 5.4 解析 `T.new()` / `extends T`

- `T.new()` → CrossFileEdge(INSTANCE, F→TF)
- `extends T` → CrossFileEdge(EXTENDS, F→TF)

## 六、UI 集成

### 6.1 Project tab（底部面板第 5 个 tab）

```
[Summary] [Call Graph] [Signal Flow] [Def-Use] [Project]
                                              ↑ 新增
Project tab 内容:
┌─ Project: res:// (42 files analyzed) ──────┐
│ [搜索: ________] [Rebuild]                 │
├────────────────────────────────────────────┤
│ Tree (双列: 文件 / 引用数):                │
│  ├ Player.gd           ← 5 files ref       │
│  ├ Enemy.gd            ← 3 files ref       │
│  ├ ▼ health_changed (signal, cross-file)   │
│  │   ├ EMIT  Player.gd:take_damage         │
│  │   └ CONNECT Enemy.gd:_ready             │
│  └ UI.gd               ← 2 files ref       │
└────────────────────────────────────────────┘
```

- 点文件 → 展开显示"谁引用它"（reverse_index）+ 跨文件边
- 点信号 → 展开跨文件 emit/connect
- "Rebuild" 按钮 → 强制全量重分析

### 6.2 现有 tab 增强

- **Call Graph tab**：跨文件调用边用不同颜色（如虚线感/灰色）+ 标注 `(→ OtherFile.gd)`
- **Signal Flow tab**：跨文件 connect/emit 标注来源文件

## 七、增量与性能

| 场景 | 处理 |
|------|------|
| 保存文件 A | 重分析 A；若 class_name 变则重建注册表；重解析引用 A 的文件的反向边 |
| 大项目（100+ 文件） | 首次全量分析可能慢——用后台 deferred 分批，UI 显示进度 |
| 未变更文件 | 时间戳缓存跳过（Phase 3 已有，复用） |
| 删除文件 | 从 files/class_registry 移除，清理指向它的边 |

**性能目标（Phase 3.2）：**
- 单文件重分析：< 50ms（Phase 3.2 验证）
- 项目首扫 100 文件：< 3s（deferred 分批，不阻塞编辑器）
- 增量（保存触发）：< 200ms（仅重分析 1 文件 + 反向边重解析）

## 八、交付物

| 文件 | 类型 | 说明 |
|------|------|------|
| `editor/gds_project_analyzer.gd` | 新增 | 项目扫描 + 批量分析 + 跨文件解析 |
| `gds_project_result.gd` | 新增 | 项目级结果容器 + 查询 API |
| `gds_cross_file_edge.gd` | 新增 | 跨文件边数据结构 |
| `editor/panels/gds_project_panel.gd` | 新增 | Project tab 面板 |
| `gds_analysis_result.gd` | 修改 | 加 type_table 字段 |
| `gds_symbol_resolver.gd` | 修改 | 填充 type_table |
| `editor/gds_analysis_bridge.gd` | 修改 | 增加 project 分析入口 + 增量触发 |
| `editor/panels/gds_analysis_main_panel.gd` | 修改 | 加第 5 tab "Project" |

## 九、验收标准

- [ ] Phase 1/2/3v1 回归全通过
- [ ] 项目扫描能发现 `res://` 下所有 `.gd`（含子目录）
- [ ] 类注册表正确：`Player` → `res://.../player.gd`
- [ ] 跨文件调用：`Enemy.gd` 里 `player.take_damage()` 解析为 CrossFileEdge → Player.gd
- [ ] 跨文件信号：`health_changed` 的 emit 和 connect 在不同文件时能关联
- [ ] 增量：保存单文件仅触发该文件 + 反向边重分析（不全扫）
- [ ] Project tab 显示文件列表 + 引用数 + 跨文件边
- [ ] 大项目 deferred 分批，不阻塞编辑器
- [ ] 单文件重分析 < 50ms

## 十、风险与边界

| 风险 | 缓解 |
|------|------|
| 类型推断不全导致大量 `obj.method()` 无法解析 | 接受——只解析静态标注类型，未标注的跳过并记录（"X 处调用因无类型标注未解析"） |
| 循环依赖（A extends B, B 引用 A） | 两遍设计：先全建注册表再解析，无环问题 |
| 增量反向边漏更新 | 用 reverse_index 显式维护，变更文件时同步更新 |
| 大项目内存 | AnalysisResult 已是 RefCounted；不活跃文件可 LRU 淘汰（Phase 3.3） |
| `load()` 在 `resource_saved` 里死锁（Phase 3 教训） | 项目扫描用 `DirAccess` + `FileAccess.get_as_text` 读源码，**不用 `load()`** |

## 十一、与 Phase 3.3 的边界

Phase 3.2 产出**数据**（跨文件调用/信号关系），Phase 3.3 消费**可视化**：
- 主屏 GraphEdit 项目调用图
- 热路径 custom-draw（需 Phase 3.2 的调用频率统计作为前置——但频率统计本身可放 3.2 或 3.3）
- 完整类型推断（让更多 `obj.method()` 可解析）
