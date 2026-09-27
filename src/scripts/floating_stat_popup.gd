extends Node3D
class_name FloatingStatPopup

var text_str: String = "+1 HP"
var text_color: Color = Color(0.2, 0.9, 0.4)
var lifetime: float = 0.6
var elapsed: float = 0.0

var sprite3d: Sprite3D
var viewport: SubViewport
var label: Label

func setup(p_text: String, p_color: Color, start_position: Vector3) -> void:
	text_str = p_text
	text_color = p_color
	global_position = start_position
	_build_ui()

func _build_ui() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(220, 60)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	
	var container = Control.new()
	container.size = Vector2(220, 60)
	viewport.add_child(container)
	
	var rich_label = RichTextLabel.new()
	rich_label.size = Vector2(260, 70)
	rich_label.bbcode_enabled = true
	rich_label.text = "[center][outline_size=9][outline_color=#000000][font_size=44]%s[/font_size][/outline_color][/outline_size][/center]" % text_str
	container.add_child(rich_label)
	
	sprite3d = Sprite3D.new()
	sprite3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite3d.no_depth_test = true
	sprite3d.pixel_size = 0.009
	sprite3d.texture = viewport.get_texture()
	add_child(sprite3d)

func _process(delta: float) -> void:
	elapsed += delta
	position.y += delta * 1.5
	
	if elapsed >= lifetime:
		queue_free()
		return
		
	var alpha = clamp((lifetime - elapsed) / 0.2, 0.0, 1.0)
	if sprite3d:
		sprite3d.modulate.a = alpha
