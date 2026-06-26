# 测试: 不支持语法不导致死循环
# 此文件包含 parser 不支持的语法片段，验证解析器不会死循环
extends Node

# 使用一些不常见或边缘语法
func test():
	var x = 1
	# ; 空语句
	;
	# 连续分号
	;;
	# 混合
	var y = 2; var z = 3
