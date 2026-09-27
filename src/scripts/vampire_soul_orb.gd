extends Node3D

var speed: float = 12.0
var is_homing: bool = false
var start_pos: Vector3
var peak_pos: Vector3
var target_player: CharacterBody3D = null

var orb_mesh: MeshInstance3D
var particles: CPUParticles3D
var lifetime_timer: float = 0.0

var reward_type: int = 0
var reward_amount: float = 5.0

func setup_reward(p_type: int, p_amount: float) -> void:
	reward_type = p_type
	reward_amount = p_amount

func start_flight() -> void:
	start_pos = global_position
	peak_pos = start_pos + Vector3(0, 1.4, 0)
	_build_visuals()
	_animate_soul()

func _build_visuals() -> void:
	orb_mesh = MeshInstance3D.new()
	var s_mesh = SphereMesh.new()
	s_mesh.radius = 0.18
	s_mesh.height = 0.36
	orb_mesh.mesh = s_mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.15, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.15, 0.25)
	mat.emission_energy_multiplier = 5.0
	mat.roughness = 0.1
	orb_mesh.material_override = mat
	add_child(orb_mesh)
	
	particles = CPUParticles3D.new()
	particles.amount = 25
	particles.lifetime = 0.4
	particles.direction = Vector3(0, 0, 0)
	particles.spread = 180.0
	particles.gravity = Vector3(0, -1.0, 0)
	particles.initial_velocity_min = 0.5
	particles.initial_velocity_max = 1.5
	particles.scale_amount_min = 0.08
	particles.scale_amount_max = 0.2
	
	var p_mesh = SphereMesh.new()
	p_mesh.radius = 0.06
	p_mesh.height = 0.12
	var p_mat = StandardMaterial3D.new()
	p_mat.albedo_color = Color(1.0, 0.2, 0.3, 0.8)
	p_mat.emission_enabled = true
	p_mat.emission = Color(1.0, 0.2, 0.3)
	p_mat.emission_energy_multiplier = 4.0
	p_mesh.material = p_mat
	particles.mesh = p_mesh
	add_child(particles)

func _animate_soul() -> void:
	var tween = create_tween()
	tween.tween_property(self, "global_position", peak_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished
	
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0 and is_instance_valid(players[0]):
		target_player = players[0]
	is_homing = true

func _process(delta: float) -> void:
	lifetime_timer += delta
	if lifetime_timer > 5.0:
		queue_free()
		return
		
	if is_homing and target_player and is_instance_valid(target_player):
		var target_pos = target_player.global_position + Vector3(0, 1.1, 0)
		var dir = (target_pos - global_position)
		var dist = dir.length()
		
		if dist < 0.4:
			_on_absorb_impact()
			return
			
		global_position = global_position.move_toward(target_pos, speed * delta)
		speed = min(24.0, speed + delta * 20.0)

func _on_absorb_impact() -> void:
	is_homing = false
	if target_player and is_instance_valid(target_player):
		if target_player.has_method("absorb_stat"):
			target_player.absorb_stat(reward_type, reward_amount)
		elif target_player.has_method("heal"):
			target_player.heal(15.0)
	queue_free()
