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
var anim_tree: AnimationTree = null

var current_target: Node3D = null
var attack_timer: float = 0.0
var current_locomotion_state: String = "idle"

# Relative movement direction vector (X = right/left strafe, Y = forward/back relative to facing)
var relative_move_dir: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("player")
	_setup_character_texture()
	_setup_animation_library()
	_setup_animation_tree()

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
	
	var blend_tree = AnimationNodeBlendTree.new()
	
	# 1. Locomotion Transition Node
	var trans = AnimationNodeTransition.new()
	trans.input_count = 5
	trans.set_input_name(0, "idle")
	trans.set_input_name(1, "run_forward")
	trans.set_input_name(2, "run_back")
	trans.set_input_name(3, "run_left")
	trans.set_input_name(4, "run_right")
	
	blend_tree.add_node("locomotion", trans)
	
	# Add animation nodes for locomotion
	var anim_names = ["idle", "run_forward", "run_back", "run_left", "run_right"]
	for i in range(anim_names.size()):
		var node_name = "anim_" + anim_names[i]
		var anim_node = AnimationNodeAnimation.new()
		anim_node.animation = anim_names[i]
		blend_tree.add_node(node_name, anim_node)
		blend_tree.connect_node("locomotion", i, node_name)
		
	# 2. Attack Animation & Speed Node
	var attack_node = AnimationNodeAnimation.new()
	attack_node.animation = "attack"
	blend_tree.add_node("attack_anim", attack_node)
	
	var timescale = AnimationNodeTimeScale.new()
	blend_tree.add_node("attack_speed", timescale)
	blend_tree.connect_node("attack_speed", 0, "attack_anim")
	
	# 3. OneShot Upper Body Overlay Node
	var oneshot = AnimationNodeOneShot.new()
	oneshot.fadein_time = 0.08
	oneshot.fadeout_time = 0.12
	oneshot.filter_enabled = true
	
	var upper_body_paths = [
		"Skeleton3D:mixamorig_Spine",
		"Skeleton3D:mixamorig_Spine1",
		"Skeleton3D:mixamorig_Spine2",
		"Skeleton3D:mixamorig_Neck",
		"Skeleton3D:mixamorig_Head",
		"Skeleton3D:mixamorig_HeadTop_End",
		"Skeleton3D:mixamorig_LeftShoulder",
		"Skeleton3D:mixamorig_LeftArm",
		"Skeleton3D:mixamorig_LeftForeArm",
		"Skeleton3D:mixamorig_LeftHand",
		"Skeleton3D:mixamorig_RightShoulder",
		"Skeleton3D:mixamorig_RightArm",
		"Skeleton3D:mixamorig_RightForeArm",
		"Skeleton3D:mixamorig_RightHand",
		"Skeleton3D:mixamorig_LeftHandThumb1", "Skeleton3D:mixamorig_LeftHandThumb2", "Skeleton3D:mixamorig_LeftHandThumb3", "Skeleton3D:mixamorig_LeftHandThumb4",
		"Skeleton3D:mixamorig_LeftHandIndex1", "Skeleton3D:mixamorig_LeftHandIndex2", "Skeleton3D:mixamorig_LeftHandIndex3", "Skeleton3D:mixamorig_LeftHandIndex4",
		"Skeleton3D:mixamorig_LeftHandMiddle1", "Skeleton3D:mixamorig_LeftHandMiddle2", "Skeleton3D:mixamorig_LeftHandMiddle3", "Skeleton3D:mixamorig_LeftHandMiddle4",
		"Skeleton3D:mixamorig_LeftHandRing1", "Skeleton3D:mixamorig_LeftHandRing2", "Skeleton3D:mixamorig_LeftHandRing3", "Skeleton3D:mixamorig_LeftHandRing4",
		"Skeleton3D:mixamorig_LeftHandPinky1", "Skeleton3D:mixamorig_LeftHandPinky2", "Skeleton3D:mixamorig_LeftHandPinky3", "Skeleton3D:mixamorig_LeftHandPinky4",
		"Skeleton3D:mixamorig_RightHandThumb1", "Skeleton3D:mixamorig_RightHandThumb2", "Skeleton3D:mixamorig_RightHandThumb3", "Skeleton3D:mixamorig_RightHandThumb4",
		"Skeleton3D:mixamorig_RightHandIndex1", "Skeleton3D:mixamorig_RightHandIndex2", "Skeleton3D:mixamorig_RightHandIndex3", "Skeleton3D:mixamorig_RightHandIndex4",
		"Skeleton3D:mixamorig_RightHandMiddle1", "Skeleton3D:mixamorig_RightHandMiddle2", "Skeleton3D:mixamorig_RightHandMiddle3", "Skeleton3D:mixamorig_RightHandMiddle4",
		"Skeleton3D:mixamorig_RightHandRing1", "Skeleton3D:mixamorig_RightHandRing2", "Skeleton3D:mixamorig_RightHandRing3", "Skeleton3D:mixamorig_RightHandRing4",
		"Skeleton3D:mixamorig_RightHandPinky1", "Skeleton3D:mixamorig_RightHandPinky2", "Skeleton3D:mixamorig_RightHandPinky3", "Skeleton3D:mixamorig_RightHandPinky4"
	]
	
	for p in upper_body_paths:
		oneshot.set_filter_path(NodePath(p), true)
		
	blend_tree.add_node("attack_shot", oneshot)
	
	# Connect locomotion -> slot 0 (base), attack_speed -> slot 1 (overlay)
	blend_tree.connect_node("attack_shot", 0, "locomotion")
	blend_tree.connect_node("attack_shot", 1, "attack_speed")
	blend_tree.connect_node("output", 0, "attack_shot")
	
	anim_tree.tree_root = blend_tree
	anim_tree.active = true
	anim_tree.set("parameters/attack_speed/scale", 2.2)
	print("AnimationTree successfully set up for dual-layer blending!")

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

	# 5. Update Locomotion State (Legs ALWAYS run locomotion!)
	_update_locomotion()

	# 6. Automatic Spell Casting
	attack_timer += delta
	if current_target and is_instance_valid(current_target) and attack_timer >= attack_cooldown:
		attack_timer = 0.0
		_trigger_spell_cast()

func _update_locomotion() -> void:
	if not anim_tree:
		return
		
	var target_state = "idle"
	
	if velocity.length() > 0.2:
		if abs(relative_move_dir.x) > abs(relative_move_dir.y):
			target_state = "run_right" if relative_move_dir.x > 0 else "run_left"
		else:
			target_state = "run_forward" if relative_move_dir.y > 0 else "run_back"

	if current_locomotion_state != target_state:
		current_locomotion_state = target_state
		anim_tree.set("parameters/locomotion/transition_request", target_state)

func _trigger_spell_cast() -> void:
	if not current_target or not is_instance_valid(current_target):
		return
		
	if anim_tree:
		anim_tree.set("parameters/attack_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		
	# Wait for cast gesture completion (fireball detaches right as hand thrusts forward)
	await get_tree().create_timer(0.24).timeout
	
	if is_instance_valid(current_target):
		_spawn_magic_sphere()

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
