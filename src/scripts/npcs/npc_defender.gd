@tool
extends "res://scripts/base_mob.gd"
class_name NPCDefender

enum WeaponType {
	UNARMED,
	SWORD
}

@export var weapon_type: WeaponType = WeaponType.UNARMED:
	set(val):
		weapon_type = val
		if is_node_ready():
			_update_weapon_display()

@export var npc_name: String = "Защитник":
	set(val):
		npc_name = val
		mob_name = val
@export var npc_role: String = "🛡️ Защитник"

@export var model_scene: PackedScene = null:
	set(val):
		model_scene = val
		_update_model()

@export var detection_radius: float = 12.0
@export var attack_radius: float = 2.5
@export var attack_damage: float = 25.0
@export var attack_cooldown_time: float = 1.4
@export var rotation_speed: float = 12.0
@export var people_material: Material = preload("res://assets/models/people/textures/people_material.tres")

var is_attacking: bool = false
var attack_cooldown: float = 0.0
var target_mob: Node3D = null
var nearby_mobs: Array[Node3D] = []
var anim_player: AnimationPlayer = null

@onready var visuals: Node3D = $Visuals

func _ready() -> void:
	mob_name = npc_name
	max_health = 120.0
	mob_color = Color(0.2, 0.6, 0.95)
	reward_type = StatRewardType.ATK
	reward_amount = 5.0
	super._ready()
	
	_update_model()
	_apply_material()
	_setup_animation()
	_update_weapon_display()
	if Engine.is_editor_hint():
		return
		
	var detection_area = get_node_or_null("DetectionArea") as Area3D
	if detection_area:
		detection_area.collision_layer = 1
		detection_area.collision_mask = 7
		detection_area.body_entered.connect(_on_detection_body_entered)
		detection_area.body_exited.connect(_on_detection_body_exited)

	var interact_area = get_node_or_null("InteractArea") as Area3D
	if interact_area:
		interact_area.body_entered.connect(_on_interact_body_entered)
		interact_area.body_exited.connect(_on_interact_body_exited)

func _update_model() -> void:
	if not is_node_ready():
		await ready
	var visuals_node = get_node_or_null("Visuals")
	if not visuals_node or not model_scene:
		return

	for child in visuals_node.get_children():
		visuals_node.remove_child(child)
		child.queue_free()

	var inst = model_scene.instantiate()
	if model_scene and "peasant" in model_scene.resource_path.to_lower():
		inst.rotation.y = PI
	visuals_node.add_child(inst)
	_apply_material()
	_setup_animation()
	_update_weapon_display()

func _apply_material() -> void:
	if not people_material:
		return
	for child in find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D:
			child.material_override = people_material

func _update_weapon_display() -> void:
	var skel = find_child("Skeleton3D", true, false) as Skeleton3D
	if not skel:
		return
		
	var existing_attachment = skel.get_node_or_null("RightHandWeaponSlot")
	if weapon_type == WeaponType.SWORD:
		if not existing_attachment:
			var bone_name = "Hand_R"
			if skel.find_bone(bone_name) != -1:
				var attachment = BoneAttachment3D.new()
				attachment.name = "RightHandWeaponSlot"
				attachment.bone_name = bone_name
				skel.add_child(attachment)
				
				var sword_scn = load("res://scenes/weapons/sword.tscn") as PackedScene
				if sword_scn:
					var sword_inst = sword_scn.instantiate()
					attachment.add_child(sword_inst)
		attack_damage = 50.0
	else:
		if existing_attachment:
			existing_attachment.queue_free()
		attack_damage = 25.0

func _setup_animation() -> void:
	var visuals_node = get_node_or_null("Visuals")
	if not visuals_node or visuals_node.get_child_count() == 0:
		return

	var model_inst = visuals_node.get_child(0)
	var skel = model_inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if not skel:
		return

	anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not anim_player:
		anim_player = AnimationPlayer.new()
		anim_player.name = "AnimationPlayer"
		visuals_node.add_child(anim_player)
		
	anim_player.root_node = anim_player.get_path_to(model_inst)

	var char_anim_folder = "res://assets/models/people/rich_citizzens_2/animations"
	if model_scene and model_scene.resource_path != "":
		var candidate_folder = model_scene.resource_path.get_base_dir().path_join("animations")
		if DirAccess.dir_exists_absolute(candidate_folder):
			char_anim_folder = candidate_folder

	var possible_anims = {
		"Idle": [
			char_anim_folder.path_join("Standing Idle.fbx"),
			char_anim_folder.path_join("Dwarf Idle.fbx"),
			char_anim_folder.path_join("rich_citizzens_2_idle.fbx"),
			char_anim_folder.path_join("idle.fbx")
		],
		"Attack_Hook": [
			char_anim_folder.path_join("Hook Punch (1).fbx"),
			char_anim_folder.path_join("Hook Punch.fbx"),
			char_anim_folder.path_join("attack_hook.fbx")
		],
		"Attack_Downward": [
			char_anim_folder.path_join("Sword And Shield Slash (1).fbx"),
			char_anim_folder.path_join("Standing Melee Attack Downward (1).fbx"),
			char_anim_folder.path_join("attack_downward.fbx")
		],
		"Run": [
			char_anim_folder.path_join("Running (2).fbx"),
			char_anim_folder.path_join("run.fbx"),
			"res://assets/models/people/rich_citizzens_2/animations/Running (2).fbx",
			"res://assets/player/Standing Run Forward.fbx"
		]
	}

	var anim_sources = {}
	for anim_key in possible_anims:
		for full_path in possible_anims[anim_key]:
			if FileAccess.file_exists(full_path):
				anim_sources[anim_key] = full_path
				break

	if anim_sources.is_empty():
		return

	var lib = AnimationLibrary.new()
	for anim_name in anim_sources:
		var scn = load(anim_sources[anim_name]) as PackedScene
		if scn:
			var inst = scn.instantiate()
			var src_ap = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if src_ap and src_ap.has_animation("mixamo_com"):
				var anim = src_ap.get_animation("mixamo_com").duplicate() as Animation
				if anim_name == "Idle" or anim_name == "Run":
					anim.loop_mode = Animation.LOOP_LINEAR

				_sanitize_animation_tracks(anim, skel)
				lib.add_animation(anim_name, anim)
				
	if anim_player.has_animation_library(""):
		anim_player.remove_animation_library("")
	anim_player.add_animation_library("", lib)
	
	if anim_player.has_animation("Idle"):
		play_animation("Idle")

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

func play_animation(anim_name: String, custom_speed: float = 1.0) -> void:
	if anim_player and anim_player.has_animation(anim_name):
		anim_player.speed_scale = custom_speed
		if anim_player.current_animation != anim_name:
			anim_player.play(anim_name)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or is_dead:
		return

	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0

	attack_cooldown = max(0.0, attack_cooldown - delta)
	_clean_mobs()

	target_mob = _find_nearest_target()

	if target_mob and is_instance_valid(target_mob) and not ("is_dead" in target_mob and target_mob.is_dead) and not (target_mob.has_method("is_dead_state") and target_mob.is_dead_state()):
		var dir_to_mob = (target_mob.global_position - global_position)
		dir_to_mob.y = 0
		var dist_to_mob = dir_to_mob.length()

		if dir_to_mob.length_squared() > 0.01:
			var target_angle = atan2(dir_to_mob.x, dir_to_mob.z)
			visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, rotation_speed * delta)

		if dist_to_mob > attack_radius and not is_attacking:
			var move_dir = dir_to_mob.normalized()
			velocity.x = move_dir.x * 3.5
			velocity.z = move_dir.z * 3.5
			move_and_slide()
			play_animation("Run")
		elif dist_to_mob <= attack_radius and attack_cooldown <= 0.0 and not is_attacking:
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			_perform_attack()
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			if not is_attacking:
				play_animation("Idle")
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		if not is_attacking:
			play_animation("Idle")

func _perform_attack() -> void:
	is_attacking = true
	attack_cooldown = attack_cooldown_time

	var attack_anim = "Attack_Downward" if weapon_type == WeaponType.SWORD else "Attack_Hook"
	play_animation(attack_anim, 1.6)

	get_tree().create_timer(0.35).timeout.connect(func():
		if is_instance_valid(self) and target_mob and is_instance_valid(target_mob) and not ("is_dead" in target_mob and target_mob.is_dead) and not (target_mob.has_method("is_dead_state") and target_mob.is_dead_state()):
			var dist = global_position.distance_to(target_mob.global_position)
			if dist <= attack_radius + 1.2:
				if target_mob.has_method("take_damage"):
					target_mob.take_damage(attack_damage)
					print("NPCDefender attacked target for ", attack_damage, " damage!")
	)

	get_tree().create_timer(attack_cooldown_time).timeout.connect(func():
		if is_instance_valid(self):
			is_attacking = false
			play_animation("Idle")
	)

func _on_death() -> void:
	if visuals:
		visuals.visible = false

func _on_respawn() -> void:
	if visuals:
		visuals.visible = true

func _clean_mobs() -> void:
	var valid_mobs: Array[Node3D] = []
	for m in nearby_mobs:
		if is_instance_valid(m) and not ("is_dead" in m and m.is_dead) and not (m.has_method("is_dead_state") and m.is_dead_state()):
			valid_mobs.append(m)
	nearby_mobs = valid_mobs

func _find_nearest_target() -> Node3D:
	_clean_mobs()
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p = players[0] as Node3D
		if is_instance_valid(p) and not (p.has_method("is_dead_state") and p.is_dead_state()):
			var dist = global_position.distance_to(p.global_position)
			if dist <= detection_radius:
				return p

	var nearest: Node3D = null
	var min_dist: float = detection_radius

	for m in nearby_mobs:
		var d = global_position.distance_to(m.global_position)
		if d < min_dist:
			min_dist = d
			nearest = m

	return nearest

func _on_detection_body_entered(body: Node) -> void:
	if body != self and (body.is_in_group("player") or body.is_in_group("monsters")) and not ("is_dead" in body and body.is_dead) and not (body.has_method("is_dead_state") and body.is_dead_state()):
		if not nearby_mobs.has(body):
			nearby_mobs.append(body as Node3D)

func _on_detection_body_exited(body: Node) -> void:
	if body.is_in_group("player") or body.is_in_group("monsters"):
		nearby_mobs.erase(body)
		if target_mob == body:
			target_mob = null

func _on_interact_body_entered(body: Node) -> void:
	if body.is_in_group("player") or body.has_method("set_nearby_npc"):
		if body.has_method("set_nearby_npc"):
			var weapon_desc = " (С мечом)" if weapon_type == WeaponType.SWORD else " (Кулачный бой)"
			body.set_nearby_npc(npc_role + ": " + npc_name + weapon_desc, true)

func _on_interact_body_exited(body: Node) -> void:
	if body.is_in_group("player") or body.has_method("set_nearby_npc"):
		if body.has_method("set_nearby_npc"):
			body.set_nearby_npc("", false)
