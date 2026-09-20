extends CharacterBody3D

@export var monster_name: String = "Makra Monster"
@export var max_health: float = 120.0
@export var move_speed: float = 3.5
@export var aggro_range: float = 10.0
@export var attack_range: float = 2.2
@export var attack_damage: float = 15.0
@export var attack_cooldown: float = 1.6
@export var respawn_time: float = 10.0

var current_health: float = 120.0
var is_dead: bool = false
var is_attacking: bool = false
var can_attack: bool = true

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visuals: Node3D = $Visuals

var health_bar = null
var anim_player: AnimationPlayer = null
var monster_model_inst: Node3D = null
var original_material: StandardMaterial3D = null

func _ready() -> void:
	add_to_group("dummies")
	add_to_group("targets")
	add_to_group("monsters")
	
	current_health = max_health
	_setup_model_and_animations()
	_setup_health_bar()

func _setup_model_and_animations() -> void:
	if not visuals:
		return
		
	monster_model_inst = visuals.find_child("MeshyModel", true, false)
	if not monster_model_inst and ResourceLoader.exists("res://assets/monsters/meshy_mob.glb"):
		var model_scene = load("res://assets/monsters/meshy_mob.glb") as PackedScene
		if model_scene:
			monster_model_inst = model_scene.instantiate()
			visuals.add_child(monster_model_inst)
			
	if monster_model_inst:
		anim_player = monster_model_inst.find_child("AnimationPlayer", true, false)
	
	if not anim_player:
		anim_player = find_child("AnimationPlayer", true, false)
		
	_play_anim("idle")

func _setup_health_bar() -> void:
	var bar_script = preload("res://scripts/floating_health_bar.gd")
	health_bar = bar_script.new()
	add_child(health_bar)
	health_bar.setup(max_health, monster_name, Color(0.9, 0.15, 0.25), 2.3)

func is_targetable() -> bool:
	return not is_dead

func _physics_process(delta: float) -> void:
	if is_dead:
		return
		
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0

	var players = get_tree().get_nodes_in_group("player")
	if players.size() == 0:
		_play_anim("idle")
		move_and_slide()
		return
		
	var player = players[0] as CharacterBody3D
	if not is_instance_valid(player) or (player.has_method("is_dead_state") and player.is_dead_state()):
		_play_anim("idle")
		move_and_slide()
		return

	var dist = global_position.distance_to(player.global_position)
	
	if dist <= aggro_range:
		# Face towards player
		var target_pos = Vector3(player.global_position.x, global_position.y, player.global_position.z)
		if global_position.distance_squared_to(target_pos) > 0.01:
			look_at(target_pos, Vector3.UP)
			
		if dist > attack_range and not is_attacking:
			# Chase player
			var dir = (target_pos - global_position).normalized()
			velocity.x = dir.x * move_speed
			velocity.z = dir.z * move_speed
			_play_anim("walk")
			move_and_slide()
		elif dist <= attack_range and can_attack and not is_attacking:
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			_perform_attack(player)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_play_anim("idle")
		move_and_slide()

func _play_anim(anim_name: String) -> void:
	if not anim_player:
		return
		
	var candidates = []
	match anim_name:
		"idle":
			candidates = ["Idle_5", "idle", "Standing Idle"]
		"walk", "run":
			candidates = ["Running", "Walking", "walk"]
		"attack":
			candidates = ["Right_Hand_Sword_Slash", "attack"]
		"death":
			candidates = ["dying_backwards", "death"]
		_:
			candidates = [anim_name]
			
	for target in candidates:
		if anim_player.has_animation(target):
			if anim_player.current_animation != target:
				anim_player.play(target)
			break

func _perform_attack(target_player: Node3D) -> void:
	is_attacking = true
	can_attack = false
	_play_anim("attack")
	
	# Attack hit point delay (0.45 seconds into attack animation)
	await get_tree().create_timer(0.45).timeout
	if is_instance_valid(target_player) and not is_dead:
		var current_dist = global_position.distance_to(target_player.global_position)
		if current_dist <= attack_range + 0.8:
			if target_player.has_method("take_damage"):
				target_player.take_damage(attack_damage)
				print("Monster ", monster_name, " attacked player for ", attack_damage, " damage!")
				
	await get_tree().create_timer(0.5).timeout
	is_attacking = false
	
	await get_tree().create_timer(attack_cooldown - 0.95).timeout
	can_attack = true

func take_damage(amount: float) -> void:
	if is_dead:
		return
		
	current_health -= amount
	print("Monster ", monster_name, " took ", amount, " damage! HP: ", current_health)
	
	if health_bar:
		health_bar.update_hp(current_health)
		
	_flash_hit()
	
	if current_health <= 0:
		_die()

func _flash_hit() -> void:
	if not monster_model_inst or is_dead:
		return
	var mesh_inst: MeshInstance3D = monster_model_inst.find_child("*", true, false) as MeshInstance3D
	if not mesh_inst:
		return
		
	var flash_mat = StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 1.0, 1.0)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 1.0, 1.0)
	flash_mat.emission_energy_multiplier = 4.0
	mesh_inst.set_surface_override_material(0, flash_mat)
	
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(mesh_inst) and not is_dead and original_material:
		mesh_inst.set_surface_override_material(0, original_material)

func _die() -> void:
	is_dead = true
	visible = false
	collision_shape.set_deferred("disabled", true)
	
	print("Monster ", monster_name, " defeated! Respawning in ", respawn_time, " seconds...")
	_create_death_debris()
	
	get_tree().create_timer(respawn_time).timeout.connect(_respawn)

func _respawn() -> void:
	current_health = max_health
	is_dead = false
	visible = true
	collision_shape.set_deferred("disabled", false)
	
	if health_bar:
		health_bar.update_hp(current_health)
		
	_animate_respawn_glow()
	print("Monster ", monster_name, " HAS RESPAWNED!")

func _animate_respawn_glow() -> void:
	if not monster_model_inst:
		return
	var mesh_inst: MeshInstance3D = monster_model_inst.find_child("*", true, false) as MeshInstance3D
	if not mesh_inst:
		return
		
	var respawn_mat = StandardMaterial3D.new()
	respawn_mat.roughness = 0.2
	respawn_mat.emission_enabled = true
	respawn_mat.albedo_color = Color(1.0, 1.0, 1.0)
	respawn_mat.emission = Color(1.0, 0.2, 0.2)
	respawn_mat.emission_energy_multiplier = 8.0
	mesh_inst.set_surface_override_material(0, respawn_mat)
	
	visuals.scale = Vector3(0.2, 0.2, 0.2)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(respawn_mat, "albedo_color", Color(1,1,1), 1.2)
	tween.tween_property(respawn_mat, "emission_energy_multiplier", 0.0, 1.2)
	tween.tween_property(visuals, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	await tween.finished
	if is_instance_valid(mesh_inst) and not is_dead and original_material:
		visuals.scale = Vector3.ONE
		mesh_inst.set_surface_override_material(0, original_material)

func _create_death_debris() -> void:
	var scene_root = get_tree().current_scene if get_tree() and get_tree().current_scene else get_parent()
	var particles = CPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 40
	particles.lifetime = 1.2
	particles.explosiveness = 0.95
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 180.0
	particles.initial_velocity_min = 3.0
	particles.initial_velocity_max = 8.0
	particles.gravity = Vector3(0, -9.8, 0)
	particles.scale_amount_min = 0.1
	particles.scale_amount_max = 0.35
	
	var p_mesh = SphereMesh.new()
	p_mesh.radius = 0.08
	p_mesh.height = 0.16
	var p_mat = StandardMaterial3D.new()
	p_mat.albedo_color = Color(0.9, 0.15, 0.2)
	p_mat.emission_enabled = true
	p_mat.emission = Color(0.9, 0.15, 0.2)
	p_mat.emission_energy_multiplier = 4.0
	p_mesh.material = p_mat
	particles.mesh = p_mesh
	
	scene_root.add_child(particles)
	particles.global_position = global_position + Vector3(0, 1.0, 0)
	particles.restart()
	
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)
