extends Node3D
class_name FloatingHealthBar

var max_hp: float = 100.0
var current_hp: float = 100.0
var bar_color: Color = Color(0.15, 0.85, 0.3)
var is_dark_text: bool = false

var sprite3d: Sprite3D
var viewport: SubViewport
var progress_bar: ProgressBar
var hp_label: Label

func setup(p_max_hp: float, _p_title: String = "", p_color: Color = Color(0.15, 0.85, 0.3), height_offset: float = 2.2, p_is_dark_text: bool = false) -> void:
	max_hp = p_max_hp
	current_hp = p_max_hp
	bar_color = p_color
	is_dark_text = p_is_dark_text
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

func _build_ui() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(190, 42)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	
	var container = Control.new()
	container.custom_minimum_size = Vector2(190, 42)
	container.size = Vector2(190, 42)
	viewport.add_child(container)
	
	# Background panel (Semi-transparent 55%, Rounded 12px pill, No border)
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
	container.add_child(panel)
	
	# Fill Stylebox for ProgressBar (Semi-transparent 75%, Rounded 10px fill)
	var fill_color = Color(bar_color.r, bar_color.g, bar_color.b, 0.75)
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.corner_radius_top_left = 10
	fill_style.corner_radius_top_right = 10
	fill_style.corner_radius_bottom_left = 10
	fill_style.corner_radius_bottom_right = 10
	fill_style.border_width_left = 0
	fill_style.border_width_top = 0
	fill_style.border_width_right = 0
	fill_style.border_width_bottom = 0
	
	var back_style = StyleBoxFlat.new()
	back_style.bg_color = Color(0.1, 0.12, 0.16, 0.45)
	back_style.corner_radius_top_left = 10
	back_style.corner_radius_top_right = 10
	back_style.corner_radius_bottom_left = 10
	back_style.corner_radius_bottom_right = 10
	back_style.border_width_left = 0
	back_style.border_width_top = 0
	back_style.border_width_right = 0
	back_style.border_width_bottom = 0
	
	progress_bar = ProgressBar.new()
	progress_bar.position = Vector2(4, 4)
	progress_bar.size = Vector2(182, 34)
	progress_bar.show_percentage = false
	progress_bar.add_theme_stylebox_override("background", back_style)
	progress_bar.add_theme_stylebox_override("fill", fill_style)
	progress_bar.max_value = max_hp
	progress_bar.value = current_hp
	container.add_child(progress_bar)
	
	# Crisp numeric HP label (Font size 22)
	hp_label = Label.new()
	hp_label.position = Vector2(4, 4)
	hp_label.size = Vector2(182, 34)
	hp_label.text = "%d" % int(ceil(current_hp))
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_label.add_theme_font_size_override("font_size", 22)
	
	if is_dark_text:
		hp_label.add_theme_color_override("font_color", Color(0.04, 0.1, 0.06, 0.95))
		hp_label.add_theme_color_override("font_outline_color", Color(0.85, 1.0, 0.88, 0.8))
		hp_label.add_theme_constant_override("outline_size", 3)
	else:
		hp_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
		hp_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		hp_label.add_theme_constant_override("outline_size", 5)
		
	container.add_child(hp_label)
	
	# Billboard Sprite3D
	sprite3d = Sprite3D.new()
	sprite3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite3d.no_depth_test = true
	sprite3d.pixel_size = 0.0075
	sprite3d.texture = viewport.get_texture()
	add_child(sprite3d)
