extends Node3D
class_name FloatingHealthBar

var max_hp: float = 100.0
var current_hp: float = 100.0
var bar_color: Color = Color(0.15, 0.85, 0.3)
var is_dark_text: bool = false

var sprite3d: Sprite3D
var viewport: SubViewport
var hp_container: Control
var progress_bar: ProgressBar
var hp_label: Label

# Respawn clock components
var clock_container: Control
var respawn_duration: float = 10.0
var respawn_elapsed: float = 0.0
var is_respawning: bool = false

var reward_type: int = 0
var reward_amount: float = 5.0
var stat_badge_label: Label

var is_player_bar: bool = false

func setup(p_max_hp: float, _p_title: String = "", p_color: Color = Color(0.15, 0.85, 0.3), height_offset: float = 2.2, p_is_dark_text: bool = false, p_reward_type: int = 0, p_reward_amount: float = 5.0, p_is_player_bar: bool = false) -> void:
	max_hp = p_max_hp
	current_hp = p_max_hp
	bar_color = p_color
	is_dark_text = p_is_dark_text
	reward_type = p_reward_type
	reward_amount = p_reward_amount
	is_player_bar = p_is_player_bar
	position = Vector3(0, height_offset, 0)
	_build_ui()

func update_hp(new_hp: float, new_max_hp: float = -1.0) -> void:
	if new_max_hp > 0:
		max_hp = new_max_hp
	current_hp = clamp(new_hp, 0.0, max_hp)
	if progress_bar:
		progress_bar.max_value = max_hp
		progress_bar.value = current_hp
	if hp_label:
		hp_label.text = "%d" % int(ceil(current_hp))

func start_respawn_clock(duration: float) -> void:
	respawn_duration = max(0.1, duration)
	respawn_elapsed = 0.0
	is_respawning = true
	if hp_container:
		hp_container.visible = false
	if clock_container:
		clock_container.visible = true
		clock_container.queue_redraw()

func show_hp_bar(new_hp: float = -1.0, new_max_hp: float = -1.0) -> void:
	is_respawning = false
	if new_hp >= 0:
		update_hp(new_hp, new_max_hp)
	if clock_container:
		clock_container.visible = false
	if hp_container:
		hp_container.visible = true

func _process(delta: float) -> void:
	if is_respawning:
		respawn_elapsed += delta
		if clock_container:
			clock_container.queue_redraw()

func _build_ui() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(200, 200)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	
	var root_control = Control.new()
	root_control.size = Vector2(200, 200)
	viewport.add_child(root_control)
	
	# ── 1. HP Bar Container ──────────────────────────────────────────────────
	hp_container = Control.new()
	hp_container.size = Vector2(190, 42)
	hp_container.position = Vector2(5, 79)
	root_control.add_child(hp_container)
	
	var bg_panel = StyleBoxFlat.new()
	bg_panel.bg_color = Color(0.05, 0.06, 0.09, 0.55)
	bg_panel.corner_radius_top_left = 12
	bg_panel.corner_radius_top_right = 12
	bg_panel.corner_radius_bottom_left = 12
	bg_panel.corner_radius_bottom_right = 12
	bg_panel.border_width_left = 0
	bg_panel.border_width_top = 0
	bg_panel.border_width_right = 0
	bg_panel.border_width_bottom = 0
	
	var panel = Panel.new()
	panel.size = Vector2(190, 42)
	panel.add_theme_stylebox_override("panel", bg_panel)
	hp_container.add_child(panel)
	
	var fill_color = Color(bar_color.r, bar_color.g, bar_color.b, 0.75)
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.corner_radius_top_left = 10
	fill_style.corner_radius_top_right = 10
	fill_style.corner_radius_bottom_left = 10
	fill_style.corner_radius_bottom_right = 10
	
	var back_style = StyleBoxFlat.new()
	back_style.bg_color = Color(0.1, 0.12, 0.16, 0.45)
	back_style.corner_radius_top_left = 10
	back_style.corner_radius_top_right = 10
	back_style.corner_radius_bottom_left = 10
	back_style.corner_radius_bottom_right = 10
	
	progress_bar = ProgressBar.new()
	progress_bar.position = Vector2(4, 4)
	progress_bar.size = Vector2(182, 34)
	progress_bar.show_percentage = false
	progress_bar.add_theme_stylebox_override("background", back_style)
	progress_bar.add_theme_stylebox_override("fill", fill_style)
	progress_bar.max_value = max_hp
	progress_bar.value = current_hp
	hp_container.add_child(progress_bar)
	
	hp_label = Label.new()
	hp_label.position = Vector2(4, 4)
	hp_label.size = Vector2(182, 34)
	hp_label.text = "%d" % int(ceil(current_hp))
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_label.add_theme_font_size_override("font_size", 30)
	
	if is_dark_text:
		hp_label.add_theme_color_override("font_color", Color(0.04, 0.1, 0.06, 0.95))
		hp_label.add_theme_color_override("font_outline_color", Color(0.85, 1.0, 0.88, 0.8))
		hp_label.add_theme_constant_override("outline_size", 4)
	else:
		hp_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
		hp_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
		hp_label.add_theme_constant_override("outline_size", 7)
		
	hp_container.add_child(hp_label)
	
	# ── 1b. Stat Reward Badge (Only for mobs, not player) ───────────────────
	if not is_player_bar:
		var badge_icon = "[color=#ff3344]♥[/color]"
		var badge_amount_str = ""
		match reward_type:
			0: # HP
				badge_icon = "[color=#ff3344]♥[/color]" # Red heart for HP
				badge_amount_str = "%d" % int(reward_amount)
			1: # ATK
				badge_icon = "[color=#ffcc00]⚔[/color]" # Gold/orange swords for ATK
				badge_amount_str = "%d" % int(reward_amount)
			2: # SPD
				badge_icon = "[color=#33ccff]⚡[/color]" # Cyan lightning for SPD
				badge_amount_str = "%.1f" % reward_amount
			3: # REGEN
				badge_icon = "[color=#00ff88]💖[/color]" # Emerald glowing heart for HP REGEN
				badge_amount_str = "+%.1f/s" % reward_amount
				
		var rich_badge = RichTextLabel.new()
		rich_badge.size = Vector2(190, 70)
		rich_badge.position = Vector2(0, -65)
		rich_badge.bbcode_enabled = true
		rich_badge.scroll_active = false
		rich_badge.autowrap_mode = TextServer.AUTOWRAP_OFF
		rich_badge.text = "[center][outline_size=8][outline_color=#000000][font_size=40]%s %s[/font_size][/outline_color][/outline_size][/center]" % [badge_icon, badge_amount_str]
		hp_container.add_child(rich_badge)
	
	# ── 2. Respawn Clock Container ───────────────────────────────────────────
	clock_container = Control.new()
	clock_container.size = Vector2(130, 130)
	clock_container.position = Vector2(35, 35)
	clock_container.visible = false
	clock_container.draw.connect(_draw_respawn_clock)
	root_control.add_child(clock_container)
	
	# Billboard Sprite3D
	sprite3d = Sprite3D.new()
	sprite3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite3d.no_depth_test = true
	sprite3d.pixel_size = 0.0075
	sprite3d.texture = viewport.get_texture()
	add_child(sprite3d)

func _draw_respawn_clock() -> void:
	if not clock_container:
		return
		
	var center = Vector2(65, 65)
	var radius = 46.0
	var thickness = 14.0
	
	# 1. Dark background disc
	clock_container.draw_circle(center, radius + 7.0, Color(0.05, 0.06, 0.09, 0.7))
	
	# 2. Base RED ring (100% RED at death)
	clock_container.draw_arc(center, radius, 0.0, TAU, 64, Color(0.9, 0.15, 0.2, 0.95), thickness, true)
	
	# 3. Clockwise GREEN sector (grows from top -PI/2 clockwise as time elapses)
	var ratio = clamp(respawn_elapsed / respawn_duration, 0.0, 1.0)
	if ratio > 0.005:
		var start_angle = -PI / 2.0
		var end_angle = start_angle + ratio * TAU
		clock_container.draw_arc(center, radius, start_angle, end_angle, 64, Color(0.15, 0.85, 0.35, 0.98), thickness, true)
		
	# 4. Countdown seconds label in center
	var font = ThemeDB.fallback_font
	var remaining_sec = max(0, ceil(respawn_duration - respawn_elapsed))
	var text_str = "%d" % int(remaining_sec)
	var font_size = 28
	
	var string_size = font.get_string_size(text_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = center + Vector2(-string_size.x / 2.0, string_size.y / 3.0)
	
	# Text outline
	clock_container.draw_string_outline(font, text_pos, text_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, 5, Color(0, 0, 0, 0.9))
	# Text fill
	clock_container.draw_string(font, text_pos, text_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(1, 1, 1, 0.95))
