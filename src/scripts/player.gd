extends CharacterBody3D

@export var move_speed: float = 6.5
@export var attack_range: float = 25.0
@export var attack_cooldown: float = 0.75
@export var magic_sphere_scene: PackedScene = preload("res://scenes/magic_sphere.tscn")

@onready var visuals: Node3D = $Visuals
@onready var vampire_model: Node3D = $Visuals/VampireModel
@onready var spell_cast_point: Node3D = $Visuals/SpellCastPoint
@onready var camera: Camera3D = $Camera3D

var anim_player: AnimationPlayer = null
var current_target: Node3D = null
var attack_timer: float = 0.0
var current_locomotion_anim: String = ""
var is_casting_spell: bool = false

# Relative movement direction vector (X = right/left strafe, Y = forward/back relative to facing)
var relative_move_dir: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("player")
	_setup_character_texture()
	_setup_animation_library()

func _setup_character_texture() -> void:
	if not vampire_model:
		return
		
	var tex: Texture2D = load("res://assets/player/Meshy_AI__0920153324_texture_obj/Meshy_AI__0920153324_texture.png")
	var mesh_inst: MeshInstance3D = vampire_model.find_child("Meshy_AI__0920153324_texture", true, false)
	
	if mesh_inst and tex:
		var mat = StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.roughness = 0.6
		mesh_inst.set_surface_override_material(0, mat)
		print("Vampire texture applied successfully!")

func _setup_animation_library() -> void:
	if not vampire_model:
		return
		
	anim_player = vampire_model.find_child("AnimationPlayer", true, false)
	if not anim_player:
		print("AnimationPlayer not found in vampire model!")
		return
		
	var library = anim_player.get_animation_library("")
	if not library:
		library = AnimationLibrary.new()
		anim_player.add_animation_library("", library)
		
	var anim_paths = {
		"idle": "res://assets/player/standing idle.fbx",
		"run_forward": "res://assets/player/Standing Run Forward.fbx",
		"run_back": "res://assets/player/Standing Run Back.fbx",
		"run_left": "res://assets/player/Standing Run Left.fbx",
		"run_right": "res://assets/player/Standing Run Right.fbx",
		"attack": "res://assets/player/Standing 1H Magic Attack 01.fbx"
	}
	
	for anim_name in anim_paths:
		var path = anim_paths[anim_name]
		var scene: PackedScene = load(path)
		if scene:
			var inst = scene.instantiate()
			var source_ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
			if source_ap and source_ap.has_animation("mixamo_com"):
				var anim = source_ap.get_animation("mixamo_com").duplicate()
				anim.loop_mode = Animation.LOOP_LINEAR if anim_name != "attack" else Animation.LOOP_NONE
				
				_make_animation_in_place(anim)
				
				if anim_name == "attack":
					# Filter out lower body tracks so attack only affects upper body
					_filter_upper_body_only(anim)
					
				library.add_animation(anim_name, anim)
				print("Registered animation: ", anim_name)
			inst.queue_free()

func _make_animation_in_place(anim: Animation) -> void:
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			var path_str = String(anim.track_get_path(i))
			if "Hips" in path_str or "hips" in path_str or "Root" in path_str or "root" in path_str:
				var key_count = anim.track_get_key_count(i)
				if key_count > 0:
					var initial_pos: Vector3 = anim.track_get_key_value(i, 0)
					for k in range(key_count):
						var current_pos: Vector3 = anim.track_get_key_value(i, k)
						var in_place_pos = Vector3(initial_pos.x, current_pos.y, initial_pos.z)
						anim.track_set_key_value(i, k, in_place_pos)

func _filter_upper_body_only(anim: Animation) -> void:
	# Removes lower body tracks so attack animation overlays seamlessly on legs
	var lower_body_keywords = [
		"Hips", "hips",
		"LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "LeftToe_End",
		"RightUpLeg", "RightLeg", "RightFoot", "RightToeBase", "RightToe_End"
	]
	
	var tracks_to_remove = []
	for i in range(anim.get_track_count()):
		var path_str = String(anim.track_get_path(i))
		for kw in lower_body_keywords:
			if kw in path_str:
				tracks_to_remove.append(i)
				break
				
	tracks_to_remove.reverse()
	for idx in tracks_to_remove:
		anim.remove_track(idx)

func _physics_process(delta: float) -> void:
	# 1. Handle Movement Input
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1.0
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_backward"):
		input_dir.y += 1.0
	if Input.is_action_pressed("move_forward"):
		input_dir.y -= 1.0
		
	input_dir = input_dir.normalized()
	
	var move_direction := Vector3(input_dir.x, 0, input_dir.y).normalized()
	
	if move_direction != Vector3.ZERO:
		velocity.x = move_direction.x * move_speed
		velocity.z = move_direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
		
	move_and_slide()
	
	# 2. Acquire Target Dummy
	current_target = _find_nearest_target()
	
	# 3. Handle Facing Direction
	var facing_dir := Vector3.ZERO
	if current_target and is_instance_valid(current_target):
		facing_dir = (current_target.global_position - global_position)
		facing_dir.y = 0.0
		facing_dir = facing_dir.normalized()
	elif move_direction != Vector3.ZERO:
		facing_dir = move_direction
		
	if facing_dir != Vector3.ZERO:
		var target_rotation_y = atan2(-facing_dir.x, -facing_dir.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_rotation_y, delta * 12.0)
		
	# 4. Calculate Strafe Vectors
	if move_direction != Vector3.ZERO and facing_dir != Vector3.ZERO:
		var char_forward = -visuals.global_transform.basis.z
		var char_right = visuals.global_transform.basis.x
		relative_move_dir.y = move_direction.dot(char_forward)
		relative_move_dir.x = move_direction.dot(char_right)
	else:
		relative_move_dir = Vector2.ZERO

	# Subtle procedural lean
	visuals.rotation.z = lerp(visuals.rotation.z, -relative_move_dir.x * 0.12, delta * 10.0)
	visuals.rotation.x = lerp(visuals.rotation.x, relative_move_dir.y * 0.08, delta * 10.0)

	# 5. Update Locomotion Animation
	_update_locomotion()

	# 6. Automatic Spell Casting
	attack_timer += delta
	if current_target and is_instance_valid(current_target) and attack_timer >= attack_cooldown:
		attack_timer = 0.0
		_trigger_spell_cast()

func _update_locomotion() -> void:
	if not anim_player or is_casting_spell:
		return
		
	var target_anim = "idle"
	
	if velocity.length() > 0.2:
		if abs(relative_move_dir.x) > abs(relative_move_dir.y):
			target_anim = "run_right" if relative_move_dir.x > 0 else "run_left"
		else:
			target_anim = "run_forward" if relative_move_dir.y > 0 else "run_back"

	if current_locomotion_anim != target_anim:
		current_locomotion_anim = target_anim
		if anim_player.has_animation(target_anim):
			anim_player.play(target_anim, 0.2)

func _trigger_spell_cast() -> void:
	if not current_target or not is_instance_valid(current_target):
		return
		
	is_casting_spell = true
	
	# Play fast upper-body magic attack animation (2.2x speed)
	if anim_player and anim_player.has_animation("attack"):
		anim_player.play("attack", 0.1, 2.2) # custom_speed = 2.2x
		
	# Wait for cast gesture completion (fireball releases right at forward arm extension)
	await get_tree().create_timer(0.25).timeout
	
	# Spawn magic sphere projectile at cast point
	if is_instance_valid(current_target):
		_spawn_magic_sphere()
		
	await get_tree().create_timer(0.15).timeout
	is_casting_spell = false
	
	# Return to running/idle locomotion smoothly
	if anim_player and anim_player.has_animation(current_locomotion_anim):
		anim_player.play(current_locomotion_anim, 0.2)

func _spawn_magic_sphere() -> void:
	if not magic_sphere_scene or not current_target:
		return
		
	var sphere = magic_sphere_scene.instantiate()
	get_parent().add_child(sphere)
	
	var spawn_pos = spell_cast_point.global_position if spell_cast_point else global_position + Vector3(0, 1.2, 0)
	sphere.global_position = spawn_pos
	
	var target_center = current_target.global_position + Vector3(0, 1.0, 0)
	var shoot_dir = (target_center - spawn_pos).normalized()
	
	if sphere.has_method("set_target_direction"):
		sphere.set_target_direction(shoot_dir)

func _find_nearest_target() -> Node3D:
	var dummies = get_tree().get_nodes_in_group("dummies")
	var nearest: Node3D = null
	var min_dist: float = attack_range
	
	for dummy in dummies:
		if not is_instance_valid(dummy):
			continue
		var dist = global_position.distance_to(dummy.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = dummy
			
	return nearest
