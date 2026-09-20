extends StaticBody3D

@export var max_health: float = 100.0
var current_health: float = 100.0

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
var original_material: StandardMaterial3D

func _ready() -> void:
	add_to_group("dummies")
	add_to_group("targets")
	current_health = max_health
	if mesh_instance and mesh_instance.get_active_material(0):
		original_material = mesh_instance.get_active_material(0).duplicate()

func take_damage(amount: float) -> void:
	current_health -= amount
	print("Dummy ", name, " took ", amount, " damage! Current HP: ", current_health)
	
	_flash_hit()
	
	if current_health <= 0:
		print("Dummy ", name, " reset HP for continuous training!")
		current_health = max_health

func _flash_hit() -> void:
	if not mesh_instance:
		return
		
	var flash_mat = StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 0.9, 0.2)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.8, 0.2)
	flash_mat.emission_energy_multiplier = 3.0
	mesh_instance.set_surface_override_material(0, flash_mat)
	
	var timer = get_tree().create_timer(0.15)
	await timer.timeout
	
	if is_instance_valid(mesh_instance):
		mesh_instance.set_surface_override_material(0, original_material)
