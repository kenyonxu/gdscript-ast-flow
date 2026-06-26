# 测试: %NodeName 场景唯一节点
extends Node

func test():
	%HealthBar.value = 100
	var hp = %HealthBar.value
	print(hp)
