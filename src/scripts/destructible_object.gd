extends StaticBody3D

@export var max_health: float = 60.0
@export var respawn_time: float = 10.0
@export var object_color: Color = Color(0.2, 0.85, 1.0) # Glowing Cyan/Blue Crystal

var current_health: float = 60.0
var is_destroyed: bool = false

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var original_material: StandardMaterial3D

func _ready() -> void:
	add_to_group("dummies")
	add_to_group("targets")
	current_health = max_health
	
	if mesh_instance:
		original_material = StandardMaterial3D.new()
		original_material.albedo_color = object_color
		original_material.roughness = 0.2
		original_material.metallic = 0.3
		original_material.emission_enabled = true
		original_material.emission = object_color
		original_material.emission_energy_multiplier = 1.5
		mesh_instance.set_surface_override_material(0, original_material)

func is_targetable() -> bool:
	return not is_destroyed

func take_damage(amount: float) -> void:
	if is_destroyed:
		return
		
	current_health -= amount
	print("Destructible ", name, " took ", amount, " damage! Current HP: ", current_health)
	
	_flash_hit()
	
	if current_health <= 0:
		_destroy_object()

func _flash_hit() -> void:
	if not mesh_instance or is_destroyed:
		return
		
	var flash_mat = StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 1.0, 1.0)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 1.0, 1.0)
	flash_mat.emission_energy_multiplier = 4.0
	mesh_instance.set_surface_override_material(0, flash_mat)
	
	await get_tree().create_timer(0.12).timeout
	
	if is_instance_valid(mesh_instance) and not is_destroyed:
		mesh_instance.set_surface_override_material(0, original_material)

func _destroy_object() -> void:
	is_destroyed = true
	visible = false
	collision_shape.set_deferred("disabled", true)
	
	print("Destructible ", name, " destroyed! Respawning in ", respawn_time, " seconds...")
	
	# Spawn visual explosion: 3D physical fragments + particle burst
	_create_shatter_debris()
	_create_particle_burst()
	
	# Schedule respawn in 10 seconds
	get_tree().create_timer(respawn_time).timeout.connect(_respawn_object)

func _respawn_object() -> void:
	current_health = max_health
	is_destroyed = false
	visible = true
	collision_shape.set_deferred("disabled", false)
	
	# Spawn respawn particle flash
	_create_particle_burst()
	print("Destructible ", name, " HAS RESPAWNED!")

func _create_shatter_debris() -> void:
	var num_chunks = 8
	var scene_root = get_tree().current_scene if get_tree() and get_tree().current_scene else get_parent()
	
	for i in range(num_chunks):
		var chunk = RigidBody3D.new()
		chunk.collision_layer = 0 # No collision with player to prevent physics push
		chunk.collision_mask = 1  # Collide with floor
		
		var mesh_inst = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(randf_range(0.15, 0.35), randf_range(0.2, 0.45), randf_range(0.15, 0.35))
		mesh_inst.mesh = box_mesh
		
		var chunk_mat = StandardMaterial3D.new()
		chunk_mat.albedo_color = object_color
		chunk_mat.emission_enabled = true
		chunk_mat.emission = object_color
		chunk_mat.emission_energy_multiplier = 2.0
		mesh_inst.material_override = chunk_mat
		chunk.add_child(mesh_inst)
		
		var col = CollisionShape3D.new()
		var box_shape = BoxShape3D.new()
		box_shape.size = box_mesh.size
		col.shape = box_shape
		chunk.add_child(col)
		
		scene_root.add_child(chunk)
		chunk.global_position = global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.4, 1.2), randf_range(-0.3, 0.3))
		
		var impulse = Vector3(randf_range(-3.5, 3.5), randf_range(3.0, 6.5), randf_range(-3.5, 3.5))
		chunk.apply_central_impulse(impulse)
		chunk.apply_torque_impulse(Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4)))
		
		# Fade and cleanup debris after 3 seconds
		_fade_and_cleanup_chunk(chunk, mesh_inst, chunk_mat)

func _create_particle_burst() -> void:
	var scene_root = get_tree().current_scene if get_tree() and get_tree().current_scene else get_parent()
	var particles = CPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 35
	particles.lifetime = 1.0
	particles.explosiveness = 0.9
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 180.0
	particles.initial_velocity_min = 2.5
	particles.initial_velocity_max = 7.0
	particles.gravity = Vector3(0, -9.8, 0)
	particles.scale_amount_min = 0.1
	particles.scale_amount_max = 0.3
	
	var p_mesh = SphereMesh.new()
	p_mesh.radius = 0.08
	p_mesh.height = 0.16
	var p_mat = StandardMaterial3D.new()
	p_mat.albedo_color = object_color
	p_mat.emission_enabled = true
	p_mat.emission = object_color
	p_mat.emission_energy_multiplier = 3.5
	p_mesh.material = p_mat
	particles.mesh = p_mesh
	
	scene_root.add_child(particles)
	particles.global_position = global_position + Vector3(0, 0.8, 0)
	particles.restart()
	
	get_tree().create_timer(2.5).timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)

func _fade_and_cleanup_chunk(chunk: RigidBody3D, mesh_inst: MeshInstance3D, mat: StandardMaterial3D) -> void:
	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(chunk) or not is_instance_valid(mesh_inst):
		return
		
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tween = create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 1.0)
	await tween.finished
	
	if is_instance_valid(chunk):
		chunk.queue_free()
