# Graph Report - .  (2026-06-20)

## Corpus Check
- Corpus is ~199 words - fits in a single context window. You may not need a graph.

## Summary
- 51 nodes · 59 edges · 11 communities (8 shown, 3 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_AST 树节点类型|AST 树节点类型]]
- [[_COMMUNITY_字节码解析核心|字节码解析核心]]
- [[_COMMUNITY_语句解析器|语句解析器]]
- [[_COMMUNITY_顶层解析入口|顶层解析入口]]
- [[_COMMUNITY_表达式类型|表达式类型]]
- [[_COMMUNITY_编辑器插件|编辑器插件]]
- [[_COMMUNITY_运算符定义|运算符定义]]
- [[_COMMUNITY_运算符类型枚举|运算符类型枚举]]

## God Nodes (most connected - your core abstractions)
1. `TreeBase` - 13 edges
2. `_parse_expr(lv)` - 11 edges
3. `GDScriptByteCodeParser (extends Node)` - 9 edges
4. `_parse_block()` - 8 edges
5. `parse(code: PoolByteArray)` - 6 edges
6. `_parse_class_block(indent)` - 6 edges
7. `ExprBase` - 5 edges
8. `_parse_tokens(stream, count)` - 3 edges
9. `GDScriptASTParser (extends Node)` - 3 edges
10. `_parse_var()` - 3 edges

## Surprising Connections (you probably didn't know these)
- `GDScriptASTParser (extends Node)` --defines--> `TreeBase`  [EXTRACTED]
  addons/gdscript_util/gds_ast_parser.gd → addons/gdscript_util/gds_ast_parser.gd  _Bridges community 4 → community 0_
- `_parse_class_block(indent)` --calls--> `_parse_var()`  [EXTRACTED]
  addons/gdscript_util/gds_ast_parser.gd → addons/gdscript_util/gds_ast_parser.gd  _Bridges community 3 → community 2_

## Import Cycles
- None detected.

## Communities (11 total, 3 thin omitted)

### Community 0 - "AST 树节点类型"
Cohesion: 0.15
Nodes (13): TreeBase, TreeBlock, TreeClass, TreeConst, TreeEnum, TreeFor, TreeFunction, TreeIf (+5 more)

### Community 1 - "字节码解析核心"
Cohesion: 0.39
Nodes (9): GDScriptByteCodeParseResult, GDScriptByteCodeParser (extends Node), GDScriptToken, Token (enum), parse(code: PoolByteArray), _parse_constants(stream, count), _parse_identifiers(stream, count), _parse_lines(stream, count) (+1 more)

### Community 2 - "语句解析器"
Cohesion: 0.50
Nodes (8): _parse_block(), _parse_expr(lv), _parse_for(), _parse_if(), _parse_match(), _parse_return(), _parse_var(), _parse_while()

### Community 3 - "顶层解析入口"
Cohesion: 0.29
Nodes (5): parse(_token_list: Array), _parse_class_block(indent), _parse_const(), _parse_enum(), _parse_function()

### Community 4 - "表达式类型"
Cohesion: 0.33
Nodes (6): ExprBase, ExprBinOp, ExprCallFunc, ExprConstant, ExprIdentifier, GDScriptASTParser (extends Node)

## Knowledge Gaps
- **19 isolated node(s):** `Token (enum)`, `TreeClass`, `TreeBlock`, `TreeFunction`, `TreeVar` (+14 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `TreeBase` connect `AST 树节点类型` to `表达式类型`?**
  _High betweenness centrality (0.201) - this node is a cross-community bridge._
- **Why does `GDScriptASTParser (extends Node)` connect `表达式类型` to `AST 树节点类型`, `字节码解析核心`?**
  _High betweenness centrality (0.185) - this node is a cross-community bridge._
- **Why does `GDScriptByteCodeParser (extends Node)` connect `字节码解析核心` to `表达式类型`?**
  _High betweenness centrality (0.138) - this node is a cross-community bridge._
- **What connects `Token (enum)`, `TreeClass`, `TreeBlock` to the rest of the system?**
  _19 weakly-connected nodes found - possible documentation gaps or missing edges._