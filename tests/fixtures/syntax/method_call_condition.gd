# 测试: if/elif 条件含方法调用和成员访问
extends Node

func test(p_path: String):
	if p_path.ends_with(".gd"):
		print("gd file")
	elif p_path.ends_with(".tscn"):
		print("scene file")
	else:
		print("other")
