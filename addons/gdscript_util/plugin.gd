@tool
extends EditorPlugin

func _enter_tree():
    add_tool_menu_item("GDScript Analysis – Parse Current", _on_parse_current)
    print("[GDScriptUtil v2.0] Plugin loaded")

func _exit_tree():
    remove_tool_menu_item("GDScript Analysis – Parse Current")
    print("[GDScriptUtil v2.0] Plugin unloaded")

func _on_parse_current():
    var editor = get_editor_interface()
    var script_editor = editor.get_script_editor()
    var current = script_editor.get_current_script()
    if current == null:
        print("[GDScriptUtil] No script open")
        return

    var source = current.source_code
    if source == "":
        print("[GDScriptUtil] Empty script")
        return

    # Phase 1 pipeline
    var tokenizer = GDScriptTokenizer.new()
    var tokens = tokenizer.tokenize(source)

    var parser = GDScriptParser.new()
    var ast = parser.parse(tokens)

    if parser.error != "":
        printerr("[GDScriptUtil] Parse error: %s" % parser.error)
    else:
        _print_ast_summary(ast, current.resource_path)

    # Phase 2: var result = GDScriptSymbolResolver.new().resolve(ast, path)

func _print_ast_summary(p_ast: GDScriptToken.ClassNode, p_path: String):
    var func_count = 0
    var var_count = 0
    var signal_count = 0

    for m in p_ast.members:
        if m is GDScriptToken.FunctionNode:
            func_count += 1
        elif m is GDScriptToken.VariableNode:
            var_count += 1
        elif m is GDScriptToken.SignalNode:
            signal_count += 1

    print("[GDScriptUtil] %s — %d functions, %d variables, %d signals" % [
        p_path, func_count, var_count, signal_count
    ])

func analyze_script(p_path: String):
    var source = load(p_path).source_code
    var tokenizer = GDScriptTokenizer.new()
    var tokens = tokenizer.tokenize(source)
    var parser = GDScriptParser.new()
    return parser.parse(tokens)
