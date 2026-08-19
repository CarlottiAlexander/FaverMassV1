class_name HudWidgets
extends RefCounted
## Los cuatro controles del HUD que se dibujan a mano con `_draw()`: crosshair,
## minimapa, viñeta de vida baja e indicadores direccionales de daño. Viven en un
## solo archivo porque comparten el mismo rol (pintar, sin lógica de juego) y
## ninguno se usa fuera del HUD; `hud.gd` los instancia como `HudWidgets.Crosshair`.

class Crosshair extends Control:
	var flash_timer := 0.0
	var flash_color := Color.WHITE
	var gap := 8.0

	func _process(_delta: float) -> void:
		queue_redraw()

	func flash(is_headshot: bool) -> void:
		flash_timer = 0.15
		flash_color = Color(1.0, 0.2, 0.15) if is_headshot else Color(1.0, 1.0, 1.0)

	func _draw() -> void:
		if flash_timer > 0.0:
			flash_timer = max(0.0, flash_timer - get_process_delta_time())
		var c := size * 0.5
		var col := Color(1.0, 1.0, 1.0, 0.85)
		if flash_timer > 0.0:
			col = flash_color
			col.a = flash_timer / 0.15
		var g := gap
		var l := 6.0
		draw_line(c + Vector2(g, 0), c + Vector2(g + l, 0), col, 2.0)
		draw_line(c - Vector2(g + l, 0), c - Vector2(g, 0), col, 2.0)
		draw_line(c + Vector2(0, g), c + Vector2(0, g + l), col, 2.0)
		draw_line(c - Vector2(0, g + l), c - Vector2(0, g), col, 2.0)
		draw_circle(c, 1.5, Color(1.0, 1.0, 1.0, 0.9))

class Minimap extends Control:
	var player: Node3D = null
	var view_range := 40.0
	## El minimapa recorre TODOS los enemigos y dibuja un punto por cada uno. A
	## 60 Hz con 200 enemigos eso es caro y no aporta nada: los puntos se mueven
	## despacio. A 20 Hz se ve igual y cuesta un tercio.
	const REDRAW_HZ := 20.0
	var _redraw_t := 0.0

	func _process(delta: float) -> void:
		_redraw_t -= delta
		if _redraw_t <= 0.0:
			_redraw_t = 1.0 / REDRAW_HZ
			queue_redraw()

	func _draw() -> void:
		var r := size.x * 0.5
		draw_circle(Vector2(r, r), r, Color(0.0, 0.0, 0.0, 0.55))
		draw_arc(Vector2(r, r), r - 1.0, 0.0, TAU, 32, Color(0.55, 0.1, 0.1, 0.8), 2.0)
		if not player or not is_instance_valid(player):
			return
		var scale_f := r / view_range
		for e in get_tree().get_nodes_in_group("enemy"):
			if not is_instance_valid(e):
				continue
			var rel: Vector3 = e.global_position - player.global_position
			var pt := Vector2(rel.x, rel.z) * scale_f
			if pt.length() > r:
				continue
			if not EnemyTraits.on_minimap(e):
				continue
			var col: Color = GameData.enemy_color_of(e.enemy_type, Color.WHITE)
			var dot_r := 4.0 if e.is_alpha else 2.5
			draw_circle(Vector2(r, r) + pt, dot_r, col)
		draw_circle(Vector2(r, r), 3.0, Color.WHITE)
		var facing: Vector3 = -player.transform.basis.z
		var dir2 := Vector2(facing.x, facing.z).normalized() * 8.0
		draw_line(Vector2(r, r), Vector2(r, r) + dir2, Color.WHITE, 2.0)

class Vignette extends Control:
	var intensity := 0.0
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		if intensity <= 0.0:
			return
		var pulse := 0.6 + 0.4 * sin(t * 4.0)
		var a := intensity * 0.45 * pulse
		var col := Color(0.55, 0.02, 0.02, a)
		var th := 60.0 + 40.0 * intensity
		draw_rect(Rect2(0, 0, size.x, th), col)
		draw_rect(Rect2(0, size.y - th, size.x, th), col)
		draw_rect(Rect2(0, 0, th, size.y), col)
		draw_rect(Rect2(size.x - th, 0, th, size.y), col)

class DamageIndicators extends Control:
	var marks: Array = []

	func add_mark(angle: float) -> void:
		marks.append({"angle": angle, "t": 1.0})

	func _process(delta: float) -> void:
		for m in marks.duplicate():
			m["t"] -= delta
			if m["t"] <= 0.0:
				marks.erase(m)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := 120.0
		for m in marks:
			var a: float = m["t"]
			var pt: Vector2 = c + Vector2(cos(m["angle"]), sin(m["angle"])) * r
			draw_circle(pt, 10.0 * a + 4.0, Color(1.0, 0.1, 0.1, a * 0.8))
