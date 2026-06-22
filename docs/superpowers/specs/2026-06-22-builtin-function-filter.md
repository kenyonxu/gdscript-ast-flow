# 内置函数过滤 设计规范

> 日期: 2026-06-22 | 状态: 设计中 | 依赖: Phase 2 SymbolResolver

## 一、目标

resolver 当前把 `print()`/`range()`/`push_error()` 等 GDScript 内置函数也记成调用边（Phase 2 前向引用修复的副作用：`sym == null` 时也记边）。导致调用图/度数被内置函数污染——`print` 节点度数虚高，枢纽高亮误报。

**核心问题：**
- 调用图里到处是 `print`/`range` 节点，噪声压过真实业务调用
- 度数统计失真（`print` 成为"枢纽"）
- 跨文件解析可能把内置名误判（虽 class_registry 通常查不到）

## 二、范围

### 做：

1. **内置函数名表** — 维护 GDScript 4.7 全局/工具函数集合（print/range/push_error/len/var_to_str/...约 60+ 个）
2. **resolver 过滤** — `_resolve_call` 隐式 self 调用分支，`sym == null` 时查内置表，命中则不记 CallEdge、不计度数
3. **配置开关** — 可选保留内置（调试时看全量），默认过滤
4. **跨文件解析同步** — `obj.print()` 这种属性调用形式不受影响（base 是 IdentifierNode 但 print 不是用户 var）；仅过滤裸 `print()` 形式

### 不做：

- ❌ 内置**常量**过滤（PI/TAU 等，已在 BUILTIN_CONSTS 单独处理，不产生边）
- ❌ 全局单例方法（`get_tree()`/`get_node()`）过滤——这些是节点方法，不是全局函数，属于另一类（可能单独 spec）
- ❌ 动态识别（运行时判断）——纯静态名表

## 三、数据来源

GDScript 4.7 的全局函数（`@GlobalScope`）和工具函数（`GDScript` 静态方法）：

**@GlobalScope 函数（部分）：** print, print_rich, printerr, printraw, push_error, push_warning, range, len, str, var_to_str, str_to_var, bytes_to_var, var_to_bytes, type_exists, is_instance_of, get_stack, ...约 60 个。

**完整来源：** Godot 源码 `modules/gdscript/gdscript_utility_functions.cpp` 注册表 + `@GlobalScope` 文档。

## 四、架构

```
addons/gdscript_util/
├── gds_builtin_functions.gd     # [新增] 内置函数名表 + is_builtin()
└── gds_symbol_resolver.gd       # [修改] _resolve_call 隐式调用分支查表过滤
```

### 4.1 内置函数表

```gdscript
# gds_builtin_functions.gd
class_name GDSBuiltinFunctions
extends RefCounted

const NAMES := {
	# 输出
	"print": true, "print_rich": true, "printerr": true, "printraw": true,
	"push_error": true, "push_warning": true,
	# 集合/转换
	"range": true, "len": true, "str": true,
	"var_to_str": true, "str_to_var": true,
	"bytes_to_var": true, "var_to_bytes": true,
	# ... 完整 60+ 项（从源码补全）
	"abs": true, "clamp": true, "max": true, "min": true, "round": true, ...,
	# 反射
	"typeof": true, "type_exists": true, "is_instance_of": true,
	"get_stack": true, "instance_from_id": true, ...,
}

static func is_builtin(p_name: String) -> bool:
	return NAMES.has(p_name)
```

### 4.2 resolver 过滤

`_resolve_call` 隐式 self 调用分支（Phase 2 改的 `sym == null or kind==FUNCTION`）：

```gdscript
# 当前:
if sym == null or sym.kind == GDScriptSymbol.Kind.FUNCTION:
    _add_call_edge(...)  # 含内置噪声

# 改为:
if sym != null and sym.kind == GDScriptSymbol.Kind.FUNCTION:
    _add_call_edge(...)  # 已声明用户函数
elif sym == null:
    if not GDSBuiltinFunctions.is_builtin(callee.name):
        _add_call_edge(...)  # 非内置、非已声明 → 可能是前向引用，记边
    # 内置 → 不记边、不计度数
```

## 五、交付物

| 文件 | 类型 | 说明 |
|------|------|------|
| `gds_builtin_functions.gd` | 新增 | 60+ 内置函数名表 + is_builtin |
| `gds_symbol_resolver.gd` | 修改 | `_resolve_call` 过滤内置 |

## 六、验收标准

- [ ] `print(...)`/`range(...)` 不产生 CallEdge、不计度数
- [ ] 用户函数 `foo()`（未声明/前向引用）仍记边
- [ ] 已声明用户函数调用不受影响
- [ ] Phase 2 回归测试全过（test_symbol_resolver 调用图不含 print 等）
- [ ] 调用图节点数减少（噪声消失）

## 七、风险

| 风险 | 缓解 |
|------|------|
| 用户自定义了同名函数（shadow 内置） | 极罕见；若 sym != null（用户声明了）则按用户函数记，不查内置表 |
| 内置表不全（漏函数） | 从 Godot 源码 `gdscript_utility_functions.cpp` 完整抄录；漏的顶多多记几条边，不致命 |
