class_name BaseMob
extends CharacterBody3D

enum StatRewardType { HP, ATK, SPD, REGEN }

@export var mob_name: String = "Mob"
@export var max_health: float = 100.0
@export var respawn_time: float = 10.0
@export var mob_color: Color = Color(0.9, 0.15, 0.25)
@export var reward_type: StatRewardType = StatRewardType.HP
@export var reward_amount: float = 5.0

var current_health: float = 100.0
var is_dead: bool = false
var respawn_timer: float = 0.0
var initial_spawn_pos: Vector3

var health_bar = null

signal mob_damaged(amount: float, current_hp: float)
signal mob_died()
signal mob_respawned()

func _ready() -> void:
	initial_spawn_pos = global_position
	add_to_group("dummies")
	add_to_group("targets")
	add_to_group("mobs")
	current_health = max_health
	_setup_health_bar()

func _setup_health_bar() -> void:
	var bar_script = preload("res://scripts/floating_health_bar.gd")
	health_bar = bar_script.new()
	add_child(health_bar)
	health_bar.setup(max_health, mob_name, mob_color, 2.3, false, reward_type, reward_amount)

func is_targetable() -> bool:
	return not is_dead

func take_damage(amount: float) -> void:
	if is_dead:
		return
	current_health = max(0.0, current_health - amount)
	print("Mob ", mob_name, " took ", amount, " damage! Current HP: ", current_health)
	mob_damaged.emit(amount, current_health)
	
	if health_bar and health_bar.has_method("update_hp"):
		health_bar.update_hp(current_health, max_health)
		
	_on_hit_flash()
	
	if current_health <= 0:
		die()

func _on_hit_flash() -> void:
	pass

func die() -> void:
	if is_dead:
		return
	is_dead = true
	
	var col_shape = find_child("CollisionShape3D", true, false) as CollisionShape3D
	if col_shape:
		col_shape.set_deferred("disabled", true)
		
	mob_died.emit()
	print("Mob ", mob_name, " defeated! Respawning in ", respawn_time, " seconds...")
	_on_death()
	_spawn_vampire_soul_orb()
	
	global_position = initial_spawn_pos
	velocity = Vector3.ZERO
	
	if health_bar and health_bar.has_method("start_respawn_clock"):
		health_bar.start_respawn_clock(respawn_time)
		
	get_tree().create_timer(respawn_time).timeout.connect(respawn)

func _spawn_vampire_soul_orb() -> void:
	var soul_script = preload("res://scripts/vampire_soul_orb.gd")
	var soul = soul_script.new()
	var scene_root = get_tree().current_scene if get_tree() and get_tree().current_scene else get_parent()
	scene_root.add_child(soul)
	soul.global_position = global_position + Vector3(0, 0.8, 0)
	soul.setup_reward(reward_type, reward_amount)
	soul.start_flight()

func respawn() -> void:
	global_position = initial_spawn_pos
	velocity = Vector3.ZERO
	current_health = max_health
	is_dead = false
	
	var col_shape = find_child("CollisionShape3D", true, false) as CollisionShape3D
	if col_shape:
		col_shape.set_deferred("disabled", false)
		
	mob_respawned.emit()
	
	if health_bar and health_bar.has_method("show_hp_bar"):
		health_bar.show_hp_bar(current_health, max_health)
		
	_on_respawn()
	print("Mob ", mob_name, " HAS RESPAWNED!")

func _on_death() -> void:
	pass

func _on_respawn() -> void:
	pass
