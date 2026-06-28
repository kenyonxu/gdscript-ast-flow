# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/) style. Version numbers follow [Semantic Versioning](https://semver.org/).

## [2.1.1] - 2026-06-27

### Added
- `TypeNode.type_path: Array` — qualified type path (e.g. `["BaseVariable","VariableScope"]`), consumers no longer split type_name
- `VariableNode.is_static: bool` — static var marker

### Fixed
- **Qualified type `Class.NestedType`** — `_parse_type` loops `.` + IDENTIFIER (was single IDENTIFIER, failed on `.`)
- **Dictionary equals syntax `{key = value}`** — `_parse_dictionary` detects AssignmentNode and splits (was `_parse_expression` eating assignment, expected COLON)
- **`static var`** — `_parse_class_member` STATIC branch accepts VAR (was FUNC only)

> Source: Fuse project codegen exploration ([project-juicy-godot](https://github.com/kenyonxu/project-juicy-godot)) — three GDScript 4.x legal syntax failures.

## [2.1.0] - 2026-06-26

### Added
- **Scene visualization main screen**: new "Scene" mode alongside "Code Analysis", three-view visualization of `.tscn`/`.tres`
  - **Node tree view**: scene list + node tree + node detail (type / script / groups / signal connections + click script to jump to editor)
  - **Script lookup view**: script aggregation list (by reference count) + cross-scene mount points + view linking
  - **Signal graph view**: GraphEdit rendering node-to-node signal connections (same-scene blue / cross-scene orange) + scene filter dropdown + middle-button drag pan + double-click node to jump
  - **View linking**: click node in lookup/signal graph → jump to node tree view
- **Instance sub-scene expansion**: `instance=ExtResource(...)` recursive sub-scene parsing, merge node tree (type/script inheritance + override node attachment + cycle detection)
- **tscn/tres parser enhancements**:
  - UID reference resolution (`uid://`, including uid-only without path)
  - `@export` override value extraction (associates script variable declarations)
  - SubResource inline property parsing (Vector2/Color etc. common type structuring)
  - `.tres` SubResource reference chain expansion + cycle detection
  - ScanConfig UX (`.tscn`/`.tres` toggles + incremental re-analysis)
- **GDScript parser syntax enhancements**:
  - Expression suffixes (member access `a.b` / method call `a.b()` / index `a[b]`) — fixes if/elif/while conditions with method calls
  - `%NodeName` scene unique node
  - `;` semicolon statement separator
  - `extends "res://path"` string path
  - `true`/`false`/`null` literals (previously parsed as IDENTIFIER)
  - Line continuation (`\` + newline)
- **UI improvements**: node tree / script lookup view region borders + three-color subtle background

### Changed
- Default scan include empty → return `res://` (scan whole project out of box, `addons` etc. excluded)
- ScanConfig **include priority over exclude** (specificity comparison: supports exclude parent + include child, e.g. `exclude res://addons` + `include res://addons/my_plugin`)

### Fixed
- ScanConfig persistence (missing `ProjectSettings.save()`, config lost on restart)
- limboai behavior tree `.tres` parsing (Array of SubResource literal caused `str_to_var` mis-load + kv out-of-bounds)
- Instance sub-scene `parent="."` nodes attach to real root (previously scattered as roots, sub-scene structure not expanded)
- Signal parameter matching (`ItemList.item_selected` with index / `LineEdit.text_changed` no param)
- Godot 4.7 compatibility (`GraphEdit.pannable` removed)
- Parser error recovery fallback (unsupported syntax deadloop → record error and skip)
- Signal graph node slug containing `:` caused `connect_node` NodePath parse failure (no connections)

## [1.0.0] - 2026-06-24

- Godot 4.7 AST rewrite initial release (Phase 1-3: Tokenizer + Parser + SymbolResolver + EditorPlugin integration)
