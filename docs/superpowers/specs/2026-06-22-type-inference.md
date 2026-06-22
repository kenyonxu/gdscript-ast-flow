# 类型推断 设计规范

> 日期: 2026-06-22 | 状态: 设计中 | 依赖: Phase 3.2 跨文件分析 + Phase 2 SymbolResolver

## 一、目标

当前跨文件解析只认**显式标注**的类型（`var x: Player`、`func f(p: Enemy)`）。大量**未标注**变量的 `obj.method()` 无法解析 → 跨文件调用图覆盖率低。

类型推断让未标注变量也能推出类型，提升跨文件边覆盖率。

**核心问题：**
```gdscript
var player := Player.new()       # 当前: 未标注 → 跳过。推断后: player: Player
var x = get_player()              # 当前: 跳过。推断后: 从返回类型推
func get_player() -> Player: ...  # 返回类型表驱动
```

## 二、范围

### 做（L1 简单推断，覆盖常见模式）：

1. **`T.new()` 推断** — `var x := T.new()` 或 `var x = T.new()` → x 类型 = T
2. **函数返回类型推断** — 建函数返回类型表（`func get_x() -> T`），`var x := get_x()` → x: T
3. **`$Node` 推断** — `@onready var n: T = $Path` 已有标注；`var n = $Path` 无标注的暂不推（需场景树，超范围）
4. **preload 推断** — `var x = preload("res://a.gd")` → x 是 a.gd 的类
5. **推断结果填 type_table** — 让 Phase 3.2 的 `resolve_cross_file` 能解析更多边

### 不做（L2+ 复杂，后续）：

- ❌ **流敏感推断** — `if cond: x = A.new() else: x = B.new()` 合并类型
- ❌ **表达式传播** — `var a = b` 其中 b 也未标注，链式追踪
- ❌ **容器元素类型** — `var arr: Array[Player]` 元素
- ❌ **运行时类型** — `get_node()`/`get_child()` 动态结果
- ❌ **完整类型系统** — Godot 内置类的方法返回类型

## 三、为什么是 L1（务实边界）

GDScript 是动态语言，完整类型推断工程量巨大且覆盖率天花板低（大量运行时决定的类型推不出）。L1 只做**静态可确定、模式清晰**的推断（`.new()`/返回类型/preload），用 ~20% 工作量拿 ~70% 可推断变量的覆盖。ROI 合理。

剩余的未标注变量（动态、流敏感）接受跳过——这本来就是动态语言的固有局限。

## 四、架构

```
addons/gdscript_util/
├── gds_type_inferrer.gd          # [新增] L1 类型推断器
├── gds_symbol_resolver.gd        # [修改] 填 type_table 时调推断器
└── gds_analysis_result.gd        # [不变] type_table 已有（Phase 3.2）
```

### 4.1 推断流程

类型推断是 **resolver 的增强**，在变量解析时：

```
_resolve_variable(node):
    var vtype = _type_to_string(node.datatype)  # 显式标注（已有）
    if vtype == "" and node.initializer != null:
        vtype = GDS_TypeInferrer.infer(node.initializer, return_type_table)  # L1 推断
    if vtype != "":
        result.type_table[node.name] = vtype
```

### 4.2 GDS_TypeInferrer

```gdscript
# gds_type_inferrer.gd
class_name GDS_TypeInferrer
extends RefCounted

# p_expr: 变量 initializer 表达式 AST
# p_return_table: {func_name: return_type_string} 函数返回类型表（预建）
# 返回类型名字符串，推不出返回 ""
static func infer(p_expr, p_return_table: Dictionary) -> String:
    if p_expr == null:
        return ""
    # T.new() → T
    if p_expr is GDScriptToken.CallNode:
        var callee = p_expr.callee
        if callee is GDScriptToken.AttributeNode and callee.name == "new":
            if callee.base is GDScriptToken.IdentifierNode:
                return callee.base.name
    # preload("res://a.gd") → a.gd 的类名（或路径）
    if p_expr is GDScriptToken.PreloadNode:
        return p_expr.path
    # func() 调用 → 查返回类型表
    if p_expr is GDScriptToken.CallNode and p_expr.callee is GDScriptToken.IdentifierNode:
        var fn_name = p_expr.callee.name
        if p_return_table.has(fn_name):
            return p_return_table[fn_name]
    return ""
```

### 4.3 返回类型表预建

resolver 第一遍建 `{func_name: return_type_string}`（从 FunctionNode.return_type），第二遍推断变量时查。由于变量初始化器可能调用同文件其他函数，需先扫完所有函数返回类型再推断变量——**两遍**（类似 Phase 3.2 跨文件的两遍）。

## 五、交付物

| 文件 | 类型 | 说明 |
|------|------|------|
| `gds_type_inferrer.gd` | 新增 | L1 推断器（.new/返回类型/preload） |
| `gds_symbol_resolver.gd` | 修改 | 变量解析调推断器 + 返回类型表两遍 |

## 六、验收标准

- [ ] `var x := Player.new()` → type_table["x"] = "Player" → 跨文件 x.method() 可解析
- [ ] `var p = get_player()`（`func get_player() -> Player`）→ type_table["p"] = "Player"
- [ ] `var c = preload("res://a.gd")` → type_table 含 a.gd
- [ ] 未标注 + 不可推断的变量仍跳过（不报错）
- [ ] Phase 3.2 跨文件测试仍过 + 新增推断用例
- [ ] 跨文件边覆盖率提升（可量化：推断前后 cross_edges 数）

## 七、风险

| 风险 | 缓解 |
|------|------|
| 覆盖率天花板低（动态语言） | 接受 L1 边界；不可推断的不强求 |
| 返回类型表两遍增加复杂度 | 仅同文件两遍，不跨文件；resolver 已有遍历结构 |
| preload 路径≠类名 | 推断返回路径，class_registry 需兼容路径查找（或 resolve 时路径→类名转换） |
| 工作量 vs ROI | L1 限定 `.new`/返回/preload 三模式，边界清晰，不大 |

## 八、与图强化的关系

类型推断提升 type_table 覆盖 → Phase 3.2 `resolve_cross_file` 解析更多 `obj.method()` → 跨文件边更多 → 图（Phase 3.3 + 图强化）更完整。是数据层增强，不直接改 UI。
