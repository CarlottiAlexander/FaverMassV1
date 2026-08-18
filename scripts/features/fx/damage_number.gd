extends Label3D

const RISE_SPEED := 1.2
const LIFETIME := 1.0

var t := 0.0

func setup(amount: float, is_headshot: bool) -> void:
	text = str(int(round(amount)))
	modulate = Color(1.0, 0.15, 0.1) if is_headshot else Color(1.0, 0.9, 0.2)
	font_size = 72 if is_headshot else 48
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true

func _process(delta: float) -> void:
	t += delta
	global_position.y += RISE_SPEED * delta
	modulate.a = clampf(1.0 - (t / LIFETIME), 0.0, 1.0)
	if t >= LIFETIME:
		queue_free()
