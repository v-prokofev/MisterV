extends Area3D

@export var speed: float = 14.0
@export var damage: float = 25.0
@export var max_lifetime: float = 3.0

var direction: Vector3 = Vector3.FORWARD
var lifetime: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func set_target_direction(dir: Vector3) -> void:
	direction = dir.normalized()
	if direction != Vector3.ZERO:
		look_at(global_position + direction, Vector3.UP)

func _process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime += delta
	if lifetime >= max_lifetime:
		queue_free()

func _on_body_entered(body: Node) -> void:
	_handle_hit(body)

func _on_area_entered(area: Area3D) -> void:
	_handle_hit(area)

func _handle_hit(target: Node) -> void:
	if target.is_in_group("player"):
		return
	
	if target.has_method("take_damage"):
		target.take_damage(damage)
	elif target.get_parent() and target.get_parent().has_method("take_damage"):
		target.get_parent().take_damage(damage)
		
	# Simple visual impact before destruction
	queue_free()
