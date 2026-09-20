extends CharacterBody3D

@export var move_speed: float = 6.5
@export var attack_range: float = 25.0
@export var attack_cooldown: float = 2.4 # Attack every 2.4s
@export_range(0.0, 1.0) var attack_cast_point_ratio: float = 0.40 # 0.50 = 50% into attack animation
@export var magic_sphere_scene: PackedScene = preload("res://scenes/magic_sphere.tscn")

# Camera Zoom Parameters
@export var min_fov: float = 30.0
@export var max_fov: float = 90.0
@export var zoom_speed: float = 5.0
var target_fov: float = 70.0

@onready var visuals: Node3D = $Visuals
@onready var vampire_model: Node3D = $Visuals/VampireModel
@onready var spell_cast_point: Node3D = $Visuals/SpellCastPoint
@onready var camera: Camera3D = $Camera3D

var anim_player: AnimationPlayer = null
var anim_tree: AnimationTree = null
var is_attacking: bool = false

var current_target: Node3D = null
var attack_timer: float = 0.0
var current_locomotion_state: String = ""

# Relative movement direction vector (X = right/left strafe, Y = forward/back relative to facing)
var relative_move_dir: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("player")
	Engine.time_scale = 1.0
	_setup_character_texture()
	_setup_animation_library()
	_setup_animation_tree()

func _unhandled_input(event: InputEvent) -> void:
	# Mouse scroll wheel camera zoom
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_fov = clamp(target_fov - zoom_speed, min_fov, max_fov)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_fov = clamp(target_fov + zoom_speed, min_fov, max_fov)

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

func _setup_animation_tree() -> void:
	if not vampire_model or not anim_player:
		return
		
	anim_tree = AnimationTree.new()
	vampire_model.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)
	
	# Simple StateMachine: idle, run_forward, run_back, run_left, run_right, attack
	var state_machine = AnimationNodeStateMachine.new()
	
	var all_anims = ["idle", "run_forward", "run_back", "run_left", "run_right", "attack"]
	for anim_name in all_anims:
		var node = AnimationNodeAnimation.new()
		node.animation = anim_name
		state_machine.add_node(anim_name, node)
	
	# Connect all states to each other (any -> any transitions)
	for from_state in all_anims:
		for to_state in all_anims:
			if from_state != to_state:
				var trans = AnimationNodeStateMachineTransition.new()
				trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
				trans.xfade_time = 0.15
				state_machine.add_transition(from_state, to_state, trans)
	
	# In Godot 4, set start by transitioning from built-in "Start" node
	var start_trans = AnimationNodeStateMachineTransition.new()
	start_trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	start_trans.xfade_time = 0.0
	state_machine.add_transition("Start", "idle", start_trans)
	
	anim_tree.tree_root = state_machine
	anim_tree.active = true
	print("AnimationTree (StateMachine, full-body) set up successfully")

func _physics_process(delta: float) -> void:
	# 0. Smooth Camera Zoom FOV
	if camera:
		camera.fov = lerp(camera.fov, target_fov, delta * 10.0)

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

	# 5. Update Locomotion State
	_update_locomotion()

	# 6. Automatic Spell Casting
	attack_timer += delta
	if current_target and is_instance_valid(current_target) and attack_timer >= attack_cooldown:
		attack_timer = 0.0
		_trigger_spell_cast()

func _update_locomotion() -> void:
	if not anim_tree or is_attacking:
		return
		
	var target_state = "idle"
	
	if velocity.length() > 0.2:
		if abs(relative_move_dir.x) > abs(relative_move_dir.y):
			target_state = "run_right" if relative_move_dir.x > 0 else "run_left"
		else:
			target_state = "run_forward" if relative_move_dir.y > 0 else "run_back"

	if current_locomotion_state != target_state:
		current_locomotion_state = target_state
		var playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if playback:
			playback.travel(target_state)

func _trigger_spell_cast() -> void:
	if not current_target or not is_instance_valid(current_target):
		return
	if is_attacking:
		return
		
	is_attacking = true
	current_locomotion_state = ""
	
	if anim_tree:
		var playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if playback:
			playback.travel("attack")
		
	# Get actual animation duration to wait the right amount
	var attack_duration: float = 2.3  # fallback
	if anim_player and anim_player.has_animation("attack"):
		attack_duration = anim_player.get_animation("attack").length
	
	# Spawn fireball at configured ratio of animation duration
	var cast_ratio = clamp(attack_cast_point_ratio, 0.0, 1.0)
	var cast_time = attack_duration * cast_ratio
	var recovery_time = max(0.0, attack_duration - cast_time)
	
	await get_tree().create_timer(cast_time).timeout
	if is_instance_valid(current_target):
		_spawn_magic_sphere()
	
	# Wait for remainder of animation to complete
	await get_tree().create_timer(recovery_time).timeout
	
	is_attacking = false
	current_locomotion_state = ""
	# Return to locomotion
	_update_locomotion()

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
