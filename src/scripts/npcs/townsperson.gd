@tool
extends "res://scripts/base_mob.gd"
class_name Townsperson

@export var npc_name: String = "Житель деревни":
	set(val):
		npc_name = val
		mob_name = val
@export var npc_role: String = "Горожанин"
@export var model_scene: PackedScene = null:
	set(val):
		model_scene = val
		_update_model()

@export var people_material: Material = preload("res://assets/models/people/textures/people_material.tres")

@onready var visuals: Node3D = $Visuals

func _ready() -> void:
	mob_name = npc_name
	max_health = 80.0
	mob_color = Color(0.95, 0.45, 0.2)
	reward_type = StatRewardType.SPD
	reward_amount = 0.3
	super._ready()

	_update_model()
	if Engine.is_editor_hint():
		return

	var interact_area = get_node_or_null("InteractArea") as Area3D
	if interact_area:
		interact_area.body_entered.connect(_on_interact_body_entered)
		interact_area.body_exited.connect(_on_interact_body_exited)

func _on_death() -> void:
	if visuals:
		visuals.visible = false

func _on_respawn() -> void:
	if visuals:
		visuals.visible = true

func _update_model() -> void:
	if not is_node_ready():
		await ready
	var visuals = get_node_or_null("Visuals")
	if not visuals or not model_scene:
		return

	for child in visuals.get_children():
		visuals.remove_child(child)
		child.queue_free()

	var inst = model_scene.instantiate()
	visuals.add_child(inst)
	_apply_material()
	_setup_animation()

func _apply_material() -> void:
	if not people_material:
		return
	for child in find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D:
			child.material_override = people_material

func _setup_animation() -> void:
	var visuals = get_node_or_null("Visuals")
	if not visuals:
		return

	var skel = visuals.find_child("Skeleton3D", true, false) as Skeleton3D
	if not skel:
		return

	var anim_player = visuals.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not anim_player:
		anim_player = AnimationPlayer.new()
		anim_player.name = "AnimationPlayer"
		visuals.add_child(anim_player)

	anim_player.root_node = anim_player.get_path_to(skel.get_parent())

	var idle_fbx = load("res://assets/models/people/animations/rich_citizzens_2_idle.fbx") as PackedScene
	if idle_fbx:
		var idle_inst = idle_fbx.instantiate()
		var src_ap = idle_inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if src_ap and src_ap.has_animation("mixamo_com"):
			var anim = src_ap.get_animation("mixamo_com").duplicate() as Animation
			anim.loop_mode = Animation.LOOP_LINEAR

			var skel_name = skel.name
			var idx = 0
			while idx < anim.get_track_count():
				var p_str = String(anim.track_get_path(idx))
				var colon_pos = p_str.find(":")
				if colon_pos == -1:
					anim.remove_track(idx)
				else:
					var subpath = p_str.substr(colon_pos)
					var bone_name = subpath.substr(1)
					var track_type = anim.track_get_type(idx)

					if track_type == Animation.TYPE_POSITION_3D and not (bone_name in ["Root", "Hips", "Pelvis"]):
						anim.remove_track(idx)
						continue

					anim.track_set_path(idx, NodePath(skel_name + subpath))
					idx += 1

			var lib = AnimationLibrary.new()
			lib.add_animation("Idle", anim)
			if anim_player.has_animation_library(""):
				anim_player.remove_animation_library("")
			anim_player.add_animation_library("", lib)
			anim_player.play("Idle")

func _on_interact_body_entered(body: Node) -> void:
	if body.is_in_group("player") or body.has_method("set_nearby_npc"):
		if body.has_method("set_nearby_npc"):
			body.set_nearby_npc(npc_role + ": " + npc_name, true)

func _on_interact_body_exited(body: Node) -> void:
	if body.is_in_group("player") or body.has_method("set_nearby_npc"):
		if body.has_method("set_nearby_npc"):
			body.set_nearby_npc("", false)
