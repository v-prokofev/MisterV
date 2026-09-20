extends CharacterBody3D

@export var move_speed: float = 6.5
@export var attack_range: float = 6
@export var attack_cooldown: float = 2.4
@export_range(0.0, 1.0) var attack_cast_point_ratio: float = 0.40
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
var is_moving: bool = false
var attack_ring_mesh_instance: MeshInstance3D = null

var current_target: Node3D = null
var attack_timer: float = 0.0
var current_locomotion_state: String = ""

var relative_move_dir: Vector2 = Vector2.ZERO

# Upper-body blend: smoothly fades attack overlay in/out.
# 0.0 = full locomotion (arms sway with run), 1.0 = upper body from attack SM.
var _upper_blend_target: float = 0.0
var _upper_blend_current: float = 0.0

# Lower-body Mixamo bone short-names to EXCLUDE from upper-blend
# (Blend2 filter: true = excluded from blend → always from locomotion input)
const LOWER_BODY_BONE_NAMES: Array[String] = [
	"Hips",
	"LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "LeftToe_End",
	"RightUpLeg", "RightLeg", "RightFoot", "RightToeBase", "RightToe_End",
]

@export var max_health: float = 100.0
var current_health: float = 100.0
var is_dead: bool = false

var health_bar_3d = null
var hud_canvas: CanvasLayer = null
var hud_progress_bar: ProgressBar = null
var hud_hp_label: Label = null

func _ready() -> void:
	add_to_group("player")
	Engine.time_scale = 1.0
	current_health = max_health
	_setup_character_texture()
	_setup_animation_library()
	_setup_animation_tree()
	_setup_attack_range_ring()
	_setup_player_health_ui()

func _unhandled_input(event: InputEvent) -> void:
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
		print("AnimationPlayer not found!")
		return

	var library = anim_player.get_animation_library("")
	if not library:
		library = AnimationLibrary.new()
		anim_player.add_animation_library("", library)

	var anim_paths = {
		"idle":        "res://assets/player/standing idle.fbx",
		"run_forward": "res://assets/player/Standing Run Forward.fbx",
		"run_back":    "res://assets/player/Standing Run Back.fbx",
		"run_left":    "res://assets/player/Standing Run Left.fbx",
		"run_right":   "res://assets/player/Standing Run Right.fbx",
		"attack":      "res://assets/player/Standing 1H Magic Attack 01.fbx",
	}

	for anim_name in anim_paths:
		var scene: PackedScene = load(anim_paths[anim_name])
		if not scene:
			continue
		var inst = scene.instantiate()
		var source_ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
		if source_ap and source_ap.has_animation("mixamo_com"):
			var anim = source_ap.get_animation("mixamo_com").duplicate()
			anim.loop_mode = Animation.LOOP_LINEAR if anim_name != "attack" else Animation.LOOP_NONE
			_make_animation_in_place(anim)
			library.add_animation(anim_name, anim)
			
			print("Registered animation: ", anim_name)
		inst.queue_free()

const BASELINE_HIPS_Y_RAD: float = deg_to_rad(-58.2)
const BASELINE_HIPS_POS_Y: float = 0.0055

func _make_animation_in_place(anim: Animation) -> void:
	for i in range(anim.get_track_count()):
		var path_str = String(anim.track_get_path(i))
		var is_hips = ("Hips" in path_str or "hips" in path_str or "Root" in path_str or "root" in path_str)

		if is_hips and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			var key_count = anim.track_get_key_count(i)
			if key_count > 0:
				for k in range(key_count):
					anim.track_set_key_value(i, k, Vector3(0.0, BASELINE_HIPS_POS_Y, 0.0))

		elif is_hips and anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			var key_count = anim.track_get_key_count(i)
			if key_count > 0:
				var q0: Quaternion = anim.track_get_key_value(i, 0)
				var initial_y: float = q0.get_euler().y
				var delta_y: float = angle_difference(initial_y, BASELINE_HIPS_Y_RAD)
				if abs(delta_y) > 0.01:
					var q_align := Quaternion(Vector3.UP, delta_y)
					for k in range(key_count):
						var cur_q: Quaternion = anim.track_get_key_value(i, k)
						anim.track_set_key_value(i, k, q_align * cur_q)

# ─────────────────────────────────────────────────────────────────────────────
# Animation Tree Architecture
#
#  BlendTree (root)
#  ├─ locomotion_sm  StateMachine (idle / run_*)         → full body base
#  ├─ upper_sm       StateMachine (idle_upper / attack)  → upper body override
#  └─ body_blend     AnimationNodeBlend2
#       blend_amount = 0.0  → everything from locomotion_sm (arms sway with run)
#       blend_amount = 1.0  → lower body filtered (from locomotion_sm),
#                              upper body from upper_sm (attack plays)
#
# Filter on body_blend: LOWER body bone tracks are excluded (true = excluded).
# Excluded tracks always take from input 0 (locomotion). Upper body not excluded
# → upper body blends to input 1 (upper_sm) when blend_amount → 1.0.
# ─────────────────────────────────────────────────────────────────────────────
func _setup_animation_tree() -> void:
	if not vampire_model or not anim_player:
		return

	anim_tree = AnimationTree.new()
	vampire_model.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)

	var blend_tree := AnimationNodeBlendTree.new()

	# ── Locomotion State Machine (legs / full body base) ──────────────────────
	var loco_sm := AnimationNodeStateMachine.new()
	var loco_anims := ["idle", "run_forward", "run_back", "run_left", "run_right"]
	for name in loco_anims:
		var node := AnimationNodeAnimation.new()
		node.animation = name
		loco_sm.add_node(name, node)
	for from_s in loco_anims:
		for to_s in loco_anims:
			if from_s == to_s:
				continue
			var t := AnimationNodeStateMachineTransition.new()
			t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			t.xfade_time = 0.15
			loco_sm.add_transition(from_s, to_s, t)
	var ls := AnimationNodeStateMachineTransition.new()
	ls.xfade_time = 0.0
	loco_sm.add_transition("Start", "idle", ls)

	# ── Upper Body State Machine (idle pose or attack) ────────────────────────
	# idle_upper: plays "idle" so upper body stays neutral when not attacking.
	# attack:     plays the actual attack animation.
	# When blend_amount = 0, this whole SM is invisible (full locomotion body).
	var upper_sm := AnimationNodeStateMachine.new()

	var idle_upper_node := AnimationNodeAnimation.new()
	idle_upper_node.animation = "idle"
	upper_sm.add_node("idle_upper", idle_upper_node)

	var attack_node := AnimationNodeAnimation.new()
	attack_node.animation = "attack"
	upper_sm.add_node("attack", attack_node)

	# idle_upper → attack: immediate
	var t_to_atk := AnimationNodeStateMachineTransition.new()
	t_to_atk.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	t_to_atk.xfade_time = 0.05
	upper_sm.add_transition("idle_upper", "attack", t_to_atk)

	# attack → idle_upper: after attack finishes (AT_END) with blend
	var t_to_idle := AnimationNodeStateMachineTransition.new()
	t_to_idle.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
	t_to_idle.xfade_time = 0.25
	upper_sm.add_transition("attack", "idle_upper", t_to_idle)

	var us := AnimationNodeStateMachineTransition.new()
	us.xfade_time = 0.0
	upper_sm.add_transition("Start", "idle_upper", us)

	# ── Blend2: overlays upper_sm on top of locomotion_sm ────────────────────
	var body_blend := AnimationNodeBlend2.new()
	body_blend.filter_enabled = true

	# Add all nodes to the tree
	blend_tree.add_node("locomotion_sm", loco_sm, Vector2(50,  200))
	blend_tree.add_node("upper_sm",      upper_sm, Vector2(50,  450))
	blend_tree.add_node("body_blend",    body_blend, Vector2(400, 320))

	# Wire: locomotion_sm → body_blend[0] (base / full body)
	blend_tree.connect_node("body_blend", 0, "locomotion_sm")
	# Wire: upper_sm → body_blend[1] (upper body override layer)
	blend_tree.connect_node("body_blend", 1, "upper_sm")
	# Wire: body_blend → output
	blend_tree.connect_node("output", 0, "body_blend")

	anim_tree.tree_root = blend_tree
	anim_tree.active = true

	# Apply filter after one frame so AnimationTree has fully initialised
	call_deferred("_apply_lower_body_filter")
	print("AnimationTree (BlendTree, dual-SM) set up successfully")

func _apply_lower_body_filter() -> void:
	if not anim_tree or not anim_tree.tree_root:
		return

	var body_blend: AnimationNodeBlend2 = anim_tree.tree_root.get_node("body_blend") as AnimationNodeBlend2
	if not body_blend:
		print("WARNING: body_blend node not found")
		return

	# Build lookup set for lower-body bone short-names
	var lower_set: Dictionary = {}
	for bname in LOWER_BODY_BONE_NAMES:
		lower_set[bname] = true

	# Use ACTUAL track paths from the attack animation.
	# This guarantees the filter path format matches exactly what AnimationTree
	# uses internally (e.g. "Armature/Skeleton3D:mixamorig:Hips").
	if not anim_player.has_animation("attack"):
		print("WARNING: 'attack' animation missing — filter not applied")
		return

	var atk_anim: Animation = anim_player.get_animation("attack")
	var filtered := 0
	var total := atk_anim.get_track_count()

	# Debug: show first few track paths so we can verify format in output log
	print("--- All Track Paths & Filter Status ---")
	for i in range(total):
		var track_path: NodePath = atk_anim.track_get_path(i)
		var path_str: String = String(track_path)

		var bone_short: String = path_str
		var colon_idx: int = path_str.rfind(":")
		if colon_idx >= 0:
			bone_short = path_str.substr(colon_idx + 1)

		var clean_bone: String = bone_short.trim_prefix("mixamorig_").trim_prefix("mixamorig:")

		var track_type = atk_anim.track_get_type(i)
		var is_upper: bool = false

		if clean_bone == "Hips":
			if track_type == Animation.TYPE_POSITION_3D:
				is_upper = false # Position (stride/bounce) comes from locomotion
			else:
				is_upper = true  # Rotation comes from upper_sm (keeps Hips & Spine facing target!)
		elif lower_set.has(clean_bone):
			is_upper = false     # Leg bones (stride steps) come from locomotion
		else:
			is_upper = true      # Torso, shoulders, arms, head come from upper_sm

		body_blend.set_filter_path(track_path, is_upper)
		if is_upper:
			filtered += 1
		print("  [%s] %s (clean: %s, type: %s) -> BLEND_UPPER=%s" % [i, path_str, clean_bone, track_type, is_upper])
	print("------------------------------------------")

	print("Upper-body filter applied: %d tracks assigned to upper blend out of %d total" % [filtered, total])

func _physics_process(delta: float) -> void:
	# 0. Camera zoom
	if camera:
		camera.fov = lerp(camera.fov, target_fov, delta * 10.0)

	# 1. Movement input
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_right"):    input_dir.x += 1.0
	if Input.is_action_pressed("move_left"):     input_dir.x -= 1.0
	if Input.is_action_pressed("move_backward"): input_dir.y += 1.0
	if Input.is_action_pressed("move_forward"):  input_dir.y -= 1.0
	input_dir = input_dir.normalized()

	var move_direction := Vector3(input_dir.x, 0, input_dir.y).normalized()
	if move_direction != Vector3.ZERO:
		velocity.x = move_direction.x * move_speed
		velocity.z = move_direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
	move_and_slide()

	# 2. Target
	current_target = _find_nearest_target()

	# 3. Facing
	var facing_dir := Vector3.ZERO
	if current_target and is_instance_valid(current_target):
		facing_dir = (current_target.global_position - global_position)
		facing_dir.y = 0.0
		facing_dir = facing_dir.normalized()
	elif move_direction != Vector3.ZERO:
		facing_dir = move_direction

	if facing_dir != Vector3.ZERO:
		var target_rot_y = atan2(-facing_dir.x, -facing_dir.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_rot_y, delta * 12.0)

	# 4. Strafe vectors
	if move_direction != Vector3.ZERO and facing_dir != Vector3.ZERO:
		var fwd = -visuals.global_transform.basis.z
		var rgt =  visuals.global_transform.basis.x
		relative_move_dir.y = move_direction.dot(fwd)
		relative_move_dir.x = move_direction.dot(rgt)
	else:
		relative_move_dir = Vector2.ZERO

	# Lean
	visuals.rotation.z = lerp(visuals.rotation.z, -relative_move_dir.x * 0.12, delta * 10.0)
	visuals.rotation.x = lerp(visuals.rotation.x, relative_move_dir.y * 0.08, delta * 10.0)

	# 5. Locomotion SM — runs ALWAYS, even during attack
	_update_locomotion(input_dir)

	# 6. Smooth upper-body blend weight & dynamic filtering
	# If we have a target or are attacking, keep upper body aimed at target!
	var has_target := (current_target != null and is_instance_valid(current_target))
	_upper_blend_target = 1.0 if (is_attacking or has_target) else 0.0

	is_moving = (input_dir != Vector2.ZERO and velocity.length() > 0.3)

	_upper_blend_current = lerp(_upper_blend_current, _upper_blend_target, delta * 14.0)
	if anim_tree:
		anim_tree.set("parameters/body_blend/blend_amount", _upper_blend_current)

	# 7. Auto-attack
	attack_timer += delta
	if current_target and is_instance_valid(current_target) and attack_timer >= attack_cooldown:
		attack_timer = 0.0
		_trigger_spell_cast()

func _update_locomotion(input_dir: Vector2) -> void:
	if not anim_tree:
		return
	var target_state = "idle"
	if input_dir != Vector2.ZERO and velocity.length() > 0.3:
		if abs(relative_move_dir.x) > abs(relative_move_dir.y):
			target_state = "run_right" if relative_move_dir.x > 0 else "run_left"
		else:
			target_state = "run_forward" if relative_move_dir.y > 0 else "run_back"

	if current_locomotion_state != target_state:
		current_locomotion_state = target_state
		var playback = anim_tree.get("parameters/locomotion_sm/playback") as AnimationNodeStateMachinePlayback
		if playback:
			playback.travel(target_state)

func _trigger_spell_cast() -> void:
	if not current_target or not is_instance_valid(current_target):
		return
	if is_attacking:
		return

	is_attacking = true

	# Start attack in upper-body SM
	var upper_pb = anim_tree.get("parameters/upper_sm/playback") as AnimationNodeStateMachinePlayback
	if upper_pb:
		upper_pb.start("attack")

	# Fade upper body IN
	_upper_blend_target = 1.0

	var attack_duration: float = 2.3
	if anim_player and anim_player.has_animation("attack"):
		attack_duration = anim_player.get_animation("attack").length

	var cast_time     = attack_duration * clamp(attack_cast_point_ratio, 0.0, 1.0)
	var recovery_time = max(0.0, attack_duration - cast_time)

	await get_tree().create_timer(cast_time).timeout
	if is_instance_valid(current_target):
		_spawn_magic_sphere()

	await get_tree().create_timer(recovery_time).timeout

	# Return upper-body SM to idle pose
	if anim_tree:
		var upper_pb2 = anim_tree.get("parameters/upper_sm/playback") as AnimationNodeStateMachinePlayback
		if upper_pb2:
			upper_pb2.travel("idle_upper")

	# Fade upper body OUT (arms go back to following locomotion)
	_upper_blend_target = 0.0
	is_attacking = false

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
		if dummy.has_method("is_targetable") and not dummy.is_targetable():
			continue
		var dist = global_position.distance_to(dummy.global_position)
		if dist <= min_dist:
			min_dist = dist
			nearest = dummy
	return nearest

func _setup_attack_range_ring() -> void:
	attack_ring_mesh_instance = MeshInstance3D.new()
	attack_ring_mesh_instance.name = "AttackRangeRing"
	add_child(attack_ring_mesh_instance)
	attack_ring_mesh_instance.position = Vector3(0, 0.04, 0)
	_update_attack_ring_mesh()

func _update_attack_ring_mesh() -> void:
	if not attack_ring_mesh_instance:
		return
	var torus := TorusMesh.new()
	torus.outer_radius = attack_range
	torus.inner_radius = max(0.1, attack_range - 0.15)
	torus.rings = 64
	torus.ring_segments = 8
	
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.95, 0.2, 0.35, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.2, 0.35)
	mat.emission_energy_multiplier = 2.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.5
	
	torus.material = mat
	attack_ring_mesh_instance.mesh = torus

func _setup_player_health_ui() -> void:
	var bar_script = preload("res://scripts/floating_health_bar.gd")
	health_bar_3d = bar_script.new()
	add_child(health_bar_3d)
	health_bar_3d.setup(max_health, "", Color(0.15, 0.85, 0.35), 2.2, true)

	hud_canvas = CanvasLayer.new()
	add_child(hud_canvas)
	
	var margin = MarginContainer.new()
	margin.position = Vector2(20, 20)
	margin.custom_minimum_size = Vector2(280, 80)
	hud_canvas.add_child(margin)
	
	var panel = Panel.new()
	var bg_panel = StyleBoxFlat.new()
	bg_panel.bg_color = Color(0.06, 0.07, 0.1, 0.85)
	bg_panel.corner_radius_top_left = 6
	bg_panel.corner_radius_top_right = 6
	bg_panel.corner_radius_bottom_left = 6
	bg_panel.corner_radius_bottom_right = 6
	bg_panel.border_width_left = 0
	bg_panel.border_width_top = 0
	bg_panel.border_width_right = 0
	bg_panel.border_width_bottom = 0
	panel.add_theme_stylebox_override("panel", bg_panel)
	panel.custom_minimum_size = Vector2(280, 80)
	margin.add_child(panel)
	
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.15, 0.85, 0.35)
	fill_style.corner_radius_top_left = 5
	fill_style.corner_radius_top_right = 5
	fill_style.corner_radius_bottom_left = 5
	fill_style.corner_radius_bottom_right = 5
	fill_style.border_width_left = 0
	fill_style.border_width_top = 0
	fill_style.border_width_right = 0
	fill_style.border_width_bottom = 0
	
	var back_style = StyleBoxFlat.new()
	back_style.bg_color = Color(0.12, 0.14, 0.18, 0.9)
	back_style.corner_radius_top_left = 5
	back_style.corner_radius_top_right = 5
	back_style.corner_radius_bottom_left = 5
	back_style.corner_radius_bottom_right = 5
	back_style.border_width_left = 0
	back_style.border_width_top = 0
	back_style.border_width_right = 0
	back_style.border_width_bottom = 0
	
	hud_progress_bar = ProgressBar.new()
	hud_progress_bar.position = Vector2(6, 6)
	hud_progress_bar.size = Vector2(268, 68)
	hud_progress_bar.show_percentage = false
	hud_progress_bar.add_theme_stylebox_override("background", back_style)
	hud_progress_bar.add_theme_stylebox_override("fill", fill_style)
	hud_progress_bar.max_value = max_health
	hud_progress_bar.value = current_health
	panel.add_child(hud_progress_bar)
	
	hud_hp_label = Label.new()
	hud_hp_label.position = Vector2(6, 6)
	hud_hp_label.size = Vector2(268, 68)
	hud_hp_label.text = "%d" % int(ceil(current_health))
	hud_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud_hp_label.add_theme_font_size_override("font_size", 42)
	hud_hp_label.add_theme_color_override("font_color", Color(0.06, 0.12, 0.08))
	hud_hp_label.add_theme_color_override("font_outline_color", Color(0.85, 1.0, 0.88))
	hud_hp_label.add_theme_constant_override("outline_size", 4)
	panel.add_child(hud_hp_label)

func take_damage(amount: float) -> void:
	if is_dead:
		return
	current_health = max(0.0, current_health - amount)
	print("Player took ", amount, " damage! HP: ", current_health)
	
	if health_bar_3d:
		health_bar_3d.update_hp(current_health)
	if hud_progress_bar:
		hud_progress_bar.value = current_health
	if hud_hp_label:
		hud_hp_label.text = "%d" % int(ceil(current_health))
		
	_flash_player_hit()
	
	if current_health <= 0:
		_on_player_die()

func is_dead_state() -> bool:
	return is_dead

func _flash_player_hit() -> void:
	if not vampire_model:
		return
	var mesh_inst: MeshInstance3D = vampire_model.find_child("Meshy_AI__0920153324_texture", true, false)
	if not mesh_inst:
		return
	var flash_mat = StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 0.2, 0.2)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.2, 0.2)
	flash_mat.emission_energy_multiplier = 3.0
	mesh_inst.set_surface_override_material(0, flash_mat)
	
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(mesh_inst):
		_setup_character_texture()

func _on_player_die() -> void:
	is_dead = true
	print("PLAYER WAS DEFEATED! Auto-respawning in 4 seconds...")
	await get_tree().create_timer(4.0).timeout
	current_health = max_health
	is_dead = false
	if health_bar_3d:
		health_bar_3d.update_hp(current_health)
	if hud_progress_bar:
		hud_progress_bar.value = current_health
	if hud_hp_label:
		hud_hp_label.text = "%d" % int(ceil(current_health))
	print("PLAYER HAS HEALED TO FULL HP!")

