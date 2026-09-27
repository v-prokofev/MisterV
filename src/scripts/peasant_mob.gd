extends "res://scripts/base_mob.gd"

@export var mob_display_name: String = "Крестьянин":
	set(val):
		mob_display_name = val
		mob_name = val
@export var move_speed: float = 3.2
@export var aggro_range: float = 9.0
@export var attack_range: float = 1.8
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.4

var can_attack: bool = true
var is_attacking: bool = false

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visuals: Node3D = $Visuals

var anim_player: AnimationPlayer = null
var peasant_model_inst: Node3D = null

func _ready() -> void:
	mob_name = mob_display_name
	mob_color = Color(0.95, 0.7, 0.2) # Warm peasant yellow/orange
	reward_type = StatRewardType.REGEN # Grants HP REGEN +1.0/s
	reward_amount = 1.0
	super._ready()
	add_to_group("monsters")
	add_to_group("peasants")
	_setup_model_and_animations()

func _setup_model_and_animations() -> void:
	if not visuals:
		return
		
	peasant_model_inst = visuals.find_child("PeasantModel", true, false)
	if not peasant_model_inst:
		peasant_model_inst = visuals.get_child(0) if visuals.get_child_count() > 0 else null
		
	if not peasant_model_inst:
		var path = "res://assets/models/peasant/peasant_1.fbx"
		if ResourceLoader.exists(path):
			var model_scene = load(path) as PackedScene
			if model_scene:
				peasant_model_inst = model_scene.instantiate()
				visuals.add_child(peasant_model_inst)
			
	if peasant_model_inst:
		peasant_model_inst.rotation.y = PI
		anim_player = peasant_model_inst.find_child("AnimationPlayer", true, false)
		if not anim_player:
			anim_player = AnimationPlayer.new()
			anim_player.name = "AnimationPlayer"
			visuals.add_child(anim_player)
		_setup_peasant_anim_library()

func _find_skeleton(node: Node) -> Skeleton3D:
	if not node:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var skel = _find_skeleton(child)
		if skel:
			return skel
	return null

func _setup_peasant_anim_library() -> void:
	if not anim_player:
		return
		
	var anim_sources = {
		"idle":   "res://assets/models/peasant/animations/Standing Idle.fbx",
		"walk":   "res://assets/models/peasant/animations/Standing Idle.fbx", # Use peasant's own idle/walk rig
		"attack": "res://assets/models/peasant/animations/Hook Punch (1).fbx", # Hand punch attack
	}
	
	var target_skel = _find_skeleton(peasant_model_inst)
	
	var lib = AnimationLibrary.new()
	for anim_name in anim_sources:
		if ResourceLoader.exists(anim_sources[anim_name]):
			var scn = load(anim_sources[anim_name]) as PackedScene
			if scn:
				var inst = scn.instantiate()
				var src_ap = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
				if not src_ap:
					src_ap = inst.get_node_or_null("AnimationPlayer")
				if src_ap and src_ap.has_animation("mixamo_com"):
					var anim = src_ap.get_animation("mixamo_com").duplicate() as Animation
					if anim_name == "idle" or anim_name == "walk":
						anim.loop_mode = Animation.LOOP_LINEAR
						
					# Remove tracks that do not exist in target skeleton to prevent AnimationMixer warnings
					if target_skel:
						_sanitize_animation_tracks(anim, target_skel)
						
					lib.add_animation(anim_name, anim)
				inst.queue_free()
				
	for lib_name in anim_player.get_animation_library_list():
		anim_player.remove_animation_library(lib_name)
	anim_player.add_animation_library("", lib)
	_play_anim("idle")

func _sanitize_animation_tracks(anim: Animation, skel: Skeleton3D) -> void:
	if not skel or not anim_player:
		return
		
	var root_node_obj = anim_player.get_node_or_null(anim_player.root_node)
	if not root_node_obj:
		root_node_obj = anim_player.get_parent()
	var skel_path_str = String(root_node_obj.get_path_to(skel))
	
	for i in range(anim.get_track_count() - 1, -1, -1):
		var path_str = String(anim.track_get_path(i))
		var first_colon = path_str.find(":")
		if first_colon == -1:
			if not root_node_obj.has_node(NodePath(path_str)):
				anim.remove_track(i)
			continue
			
		var node_part = path_str.substr(0, first_colon)
		var sub_part = path_str.substr(first_colon + 1)
		
		var bone_parts = sub_part.split(":")
		var bone_name = bone_parts[0]
		
		if skel.find_bone(bone_name) != -1:
			if node_part != skel_path_str:
				var new_path_str = skel_path_str + ":" + sub_part
				anim.track_set_path(i, NodePath(new_path_str))
		else:
			if not root_node_obj.has_node(NodePath(node_part)):
				anim.remove_track(i)

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
		var target_pos = Vector3(player.global_position.x, global_position.y, player.global_position.z)
		if global_position.distance_squared_to(target_pos) > 0.01:
			look_at(target_pos, Vector3.UP)
			
		if dist > attack_range and not is_attacking:
			var dir = (target_pos - global_position).normalized()
			velocity.x = dir.x * move_speed
			velocity.z = dir.z * move_speed
			_play_anim("walk")
			move_and_slide()
		elif dist <= attack_range and can_attack and not is_attacking:
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			_perform_punch_attack(player)
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
	if anim_player.has_animation(anim_name):
		if anim_player.current_animation != anim_name:
			anim_player.play(anim_name)

func _perform_punch_attack(target_player: Node3D) -> void:
	is_attacking = true
	can_attack = false
	_play_anim("attack")
	
	await get_tree().create_timer(0.45).timeout
	if not is_dead and is_instance_valid(target_player):
		if target_player.has_method("take_damage"):
			target_player.take_damage(attack_damage)
			print("Peasant mob ", mob_name, " punched player with hands for ", attack_damage, " damage!")
				
	await get_tree().create_timer(0.55).timeout
	is_attacking = false
	
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func _on_death() -> void:
	if visuals:
		visuals.visible = false
	_create_death_particles()

func _on_respawn() -> void:
	if visuals:
		visuals.visible = true

func _create_death_particles() -> void:
	var scene_root = get_tree().current_scene if get_tree() and get_tree().current_scene else get_parent()
	var particles = CPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 30
	particles.lifetime = 1.0
	particles.explosiveness = 0.9
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 180.0
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 6.0
	particles.gravity = Vector3(0, -9.8, 0)
	
	var p_mesh = SphereMesh.new()
	p_mesh.radius = 0.07
	p_mesh.height = 0.14
	var p_mat = StandardMaterial3D.new()
	p_mat.albedo_color = Color(0.85, 0.65, 0.3)
	p_mat.emission_enabled = true
	p_mat.emission = Color(0.85, 0.65, 0.3)
	p_mesh.material = p_mat
	particles.mesh = p_mesh
	
	scene_root.add_child(particles)
	particles.global_position = global_position + Vector3(0, 1.0, 0)
	particles.restart()
	
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)
