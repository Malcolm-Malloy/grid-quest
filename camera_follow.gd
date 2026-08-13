extends Camera2D

@export var target_path: NodePath = ^"../World/Player"
@onready var target := get_node(target_path) as Node2D

func _process(_delta: float) -> void:
	if target:
		global_position = target.global_position
