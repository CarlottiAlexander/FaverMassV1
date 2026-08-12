extends CanvasLayer
## HUD + menús, construidos por código (sin depender de un .tscn de Control hecho a mano).
## Ver secciones 9, 10 y 11 de la especificación.

# ---------------------------------------------------------------------------
# Clases internas de dibujo (crosshair, minimapa, viñeta, indicadores de daño)
# ---------------------------------------------------------------------------

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
			var col: Color = GameData.ENEMY_COLOR.get(e.enemy_type, Color.WHITE)
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

# ---------------------------------------------------------------------------
# Estado
# ---------------------------------------------------------------------------

var player: Node = null
var wave_manager: Node = null

var hud_root: Control
var crosshair: Crosshair
var minimap: Minimap
var vignette: Vignette
var damage_indicators: DamageIndicators
var health_fill: ColorRect
var health_label: Label
var ecstasy_fill: ColorRect
var ecstasy_label: Label
var weapon_name_label: Label
var weapon_ammo_fill: ColorRect
var weapon_ammo_label: Label
var wave_label: Label
var enemies_label: Label
var kills_label: Label
var kill_feed_container: VBoxContainer
var wave_announce_label: Label
var fps_label: Label

var kill_feed_entries: Array = []
var wave_announce_timer := 0.0
## texto base del panel de arma, sin el sufijo de spin-up (que cambia por frame)
var weapon_base_text := ""

var menu_root: Control
var title_panel: Control
var pause_panel: Control
var options_panel: Control
var death_panel: Control
var death_stats_label: Label
var title_logo: Label
var title_pulse_t := 0.0

const HEALTH_BAR_W := 250.0
const HEALTH_BAR_H := 18.0
const ECSTASY_BAR_H := 14.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		player.health_changed.connect(_update_health)
		player.ammo_changed.connect(_update_weapon)
		player.weapon_changed.connect(_update_weapon)
		player.ecstasy_changed.connect(_update_ecstasy)
		player.hit_confirmed.connect(_on_hit_confirmed)
		player.damage_taken.connect(_on_damage_taken)
		player.kill_feed_entry.connect(_on_kill_feed)

	var wms := get_tree().get_nodes_in_group("wave_manager")
	if wms.size() > 0:
		wave_manager = wms[0]
		wave_manager.wave_changed.connect(_update_wave)
		wave_manager.wave_announced.connect(_on_wave_announced)

	_build_hud()
	_build_menus()

	GameState.state_changed.connect(_on_state_changed)
	_on_state_changed(GameState.state)

	_update_health()
	_update_ecstasy()
	_update_weapon()
	_update_wave()

func _process(delta: float) -> void:
	if player and is_instance_valid(player):
		var frac: float = player.health / GameData.MAX_HEALTH
		vignette.intensity = clampf(1.0 - frac / 0.3, 0.0, 1.0) if frac < 0.3 else 0.0
		var moving := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D)
		var sprinting := Input.is_key_pressed(KEY_SHIFT)
		var crouching := Input.is_key_pressed(KEY_CTRL)
		var target_gap := 8.0
		if crouching:
			target_gap = 5.0
		elif sprinting and moving:
			target_gap = 16.0
		elif moving:
			target_gap = 11.0
		crosshair.gap = lerpf(crosshair.gap, target_gap, 10.0 * delta)

	if wave_manager and is_instance_valid(wave_manager):
		enemies_label.text = "Enemies: %d" % wave_manager.alive_count

	kills_label.text = "Kills: %d   Headshots: %d" % [GameState.run_kills, GameState.run_headshots]

	if wave_announce_timer > 0.0:
		wave_announce_timer -= delta
		wave_announce_label.visible = true
		wave_announce_label.modulate.a = clampf(wave_announce_timer / 0.5, 0.0, 1.0)
	else:
		wave_announce_label.visible = false

	for entry in kill_feed_entries.duplicate():
		entry["t"] -= delta
		if entry["t"] <= 0.0:
			kill_feed_entries.erase(entry)
			if is_instance_valid(entry["label"]):
				entry["label"].queue_free()
		elif is_instance_valid(entry["label"]):
			entry["label"].modulate.a = clampf(entry["t"] / 0.4, 0.0, 1.0) if entry["t"] < 0.4 else 1.0

	# Indicador de spin-up: sin esto la mecánica de calentamiento de SMG/LMG/
	# Minigun sería invisible para el jugador. Solo aparece cuando está activo.
	if player and is_instance_valid(player) and weapon_base_text != "":
		if player.spinup > 1.05:
			var t: float = clampf((player.spinup - 1.0) / (player.SPINUP_MAX - 1.0), 0.0, 1.0)
			weapon_name_label.text = "%s  x%.1f" % [weapon_base_text, player.spinup]
			weapon_name_label.add_theme_color_override(
				"font_color", Color(1.0, 0.85, 0.3).lerp(Color(1.0, 0.25, 0.1), t))
		elif weapon_name_label.text != weapon_base_text:
			weapon_name_label.text = weapon_base_text
			weapon_name_label.add_theme_color_override(
				"font_color", GameData.RARITY_COLOR[player.current_rarity])

	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

	title_pulse_t += delta
	if title_logo:
		title_logo.modulate.a = 0.75 + 0.25 * sin(title_pulse_t * 2.0)

# ---------------------------------------------------------------------------
# Construcción del HUD
# ---------------------------------------------------------------------------

## Único punto de verdad para posicionar un Control con anclaje de esquina.
## `Control.position`/`.size` con anclajes que no son full-rect (0,0,1,1)
## pasan por una conversión relativa al anchor que da resultados
## contraintuitivos al leer/copiar el valor entre controles (confirmado a mano:
## escribir position.y=-66 con anchor inferior y releerlo después da un
## número que corresponde a "alto_del_padre - 66", no -66). `offset_left/top/
## right/bottom` son los valores CANÓNICOS sin ambigüedad — todo el HUD y los
## menús se posicionan a través de esta función, nunca tocando position/size
## directo en un control anclado a una esquina.
func _rect(control: Control, preset: int, x: float, y: float, w: float, h: float) -> void:
	control.set_anchors_preset(preset)
	control.offset_left = x
	control.offset_top = y
	control.offset_right = x + w
	control.offset_bottom = y + h

func _build_hud() -> void:
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_root)

	crosshair = Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(crosshair)

	damage_indicators = DamageIndicators.new()
	damage_indicators.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_indicators.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(damage_indicators)

	vignette = Vignette.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(vignette)

	# Salud
	var health_bg := ColorRect.new()
	health_bg.color = Color(0.08, 0.08, 0.08, 0.75)
	_rect(health_bg, Control.PRESET_BOTTOM_LEFT, 20, -66, HEALTH_BAR_W, HEALTH_BAR_H)
	hud_root.add_child(health_bg)
	health_fill = ColorRect.new()
	health_fill.color = Color(0.2, 0.75, 0.2)
	_rect(health_fill, Control.PRESET_BOTTOM_LEFT, 20, -66, HEALTH_BAR_W, HEALTH_BAR_H)
	hud_root.add_child(health_fill)
	health_label = _make_label("100/100", Control.PRESET_BOTTOM_LEFT, 26, -68, HEALTH_BAR_W, HEALTH_BAR_H, 14)
	hud_root.add_child(health_label)

	# Éxtasis
	var ecstasy_bg := ColorRect.new()
	ecstasy_bg.color = Color(0.08, 0.08, 0.08, 0.75)
	_rect(ecstasy_bg, Control.PRESET_BOTTOM_LEFT, 20, -66 - ECSTASY_BAR_H - 4, HEALTH_BAR_W, ECSTASY_BAR_H)
	hud_root.add_child(ecstasy_bg)
	ecstasy_fill = ColorRect.new()
	ecstasy_fill.color = Color(0.5, 0.5, 0.5)
	_rect(ecstasy_fill, Control.PRESET_BOTTOM_LEFT, 20, -66 - ECSTASY_BAR_H - 4, HEALTH_BAR_W, ECSTASY_BAR_H)
	hud_root.add_child(ecstasy_fill)
	ecstasy_label = _make_label("G", Control.PRESET_BOTTOM_LEFT, 20, -66 - ECSTASY_BAR_H - 4, HEALTH_BAR_W, ECSTASY_BAR_H, 12, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	hud_root.add_child(ecstasy_label)

	# Panel de arma
	var weapon_bg := ColorRect.new()
	weapon_bg.color = Color(0.08, 0.08, 0.08, 0.75)
	_rect(weapon_bg, Control.PRESET_BOTTOM_RIGHT, -270, -90, 250, 70)
	hud_root.add_child(weapon_bg)
	weapon_name_label = _make_label("Pistol", Control.PRESET_BOTTOM_RIGHT, -260, -86, 230, 24, 18)
	hud_root.add_child(weapon_name_label)
	var ammo_bg := ColorRect.new()
	ammo_bg.color = Color(0.15, 0.15, 0.15, 0.8)
	_rect(ammo_bg, Control.PRESET_BOTTOM_RIGHT, -260, -56, 230, 16)
	hud_root.add_child(ammo_bg)
	weapon_ammo_fill = ColorRect.new()
	weapon_ammo_fill.color = Color(0.7, 0.7, 0.2)
	_rect(weapon_ammo_fill, Control.PRESET_BOTTOM_RIGHT, -260, -56, 230, 16)
	hud_root.add_child(weapon_ammo_fill)
	weapon_ammo_label = _make_label("15", Control.PRESET_BOTTOM_RIGHT, -260, -56, 230, 16, 12, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER)
	hud_root.add_child(weapon_ammo_label)

	# Minimapa (arriba del panel de arma)
	minimap = Minimap.new()
	minimap.player = player
	_rect(minimap, Control.PRESET_BOTTOM_RIGHT, -140, -240, 120, 120)
	hud_root.add_child(minimap)

	# Info de oleada
	wave_label = _make_label("WAVE 0", Control.PRESET_TOP_LEFT, 20, 20, 300, 40, 28)
	hud_root.add_child(wave_label)
	enemies_label = _make_label("Enemies: 0", Control.PRESET_TOP_LEFT, 20, 58, 300, 24, 16, Color(0.8, 0.8, 0.8))
	hud_root.add_child(enemies_label)

	# Kills/headshots
	kills_label = _make_label("Kills: 0   Headshots: 0", Control.PRESET_TOP_RIGHT, -320, 20, 300, 24, 16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	hud_root.add_child(kills_label)

	kill_feed_container = VBoxContainer.new()
	_rect(kill_feed_container, Control.PRESET_TOP_RIGHT, -320, 50, 300, 160)
	kill_feed_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	hud_root.add_child(kill_feed_container)

	# Anuncio de oleada
	wave_announce_label = Label.new()
	wave_announce_label.text = ""
	wave_announce_label.add_theme_font_size_override("font_size", 48)
	wave_announce_label.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15))
	wave_announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_announce_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rect(wave_announce_label, Control.PRESET_CENTER, -260, -220, 520, 100)
	wave_announce_label.visible = false
	hud_root.add_child(wave_announce_label)

	# FPS
	fps_label = _make_label("FPS: 0", Control.PRESET_BOTTOM_LEFT, 10, -24, 120, 20, 12, Color(0.6, 0.6, 0.6))
	hud_root.add_child(fps_label)

	# El HUD es 100% decorativo — ningún hijo debe robarle eventos de mouse al
	# jugador. Sin esto, con Input.mouse_mode = CAPTURED, Godot igual arrastra
	# una posición virtual de cursor por toda la pantalla para el hit-test de la
	# GUI: cualquier Control con el filtro por defecto (STOP) que quede debajo
	# se come el motion event y la cámara deja de girar mientras el cursor
	# "invisible" pasa por encima (barras, panel de arma, minimapa, etc).
	_set_ignore_recursive(hud_root)

func _set_ignore_recursive(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_ignore_recursive(child)

func _make_label(text: String, preset: int, x: float, y: float, w: float, h: float, font_size: int = 18, color: Color = Color.WHITE, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	_rect(l, preset, x, y, w, h)
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

# ---------------------------------------------------------------------------
# Actualización del HUD
# ---------------------------------------------------------------------------

func _update_health() -> void:
	if not player:
		return
	var frac: float = clampf(player.health / GameData.MAX_HEALTH, 0.0, 1.0)
	health_fill.offset_right = health_fill.offset_left + HEALTH_BAR_W * frac
	health_label.text = "%d/%d" % [ceili(player.health), int(GameData.MAX_HEALTH)]
	if frac > 0.5:
		health_fill.color = Color(0.2, 0.75, 0.2)
	elif frac > 0.25:
		health_fill.color = Color(0.85, 0.55, 0.1)
	else:
		health_fill.color = Color(0.8, 0.15, 0.15)

func _update_ecstasy() -> void:
	if not player:
		return
	var xp: float = player.ecstasy
	var frac := clampf(xp / GameData.MAX_ECSTASY, 0.0, 1.0)
	ecstasy_fill.offset_right = ecstasy_fill.offset_left + HEALTH_BAR_W * frac
	if xp >= 100.0:
		ecstasy_fill.color = Color(0.85, 0.1, 0.1)
	elif xp >= 75.0:
		ecstasy_fill.color = Color(1.0, 0.84, 0.2)
	elif xp >= 50.0:
		ecstasy_fill.color = Color(0.3, 0.5, 1.0)
	elif xp >= 25.0:
		ecstasy_fill.color = Color(0.9, 0.9, 0.9)
	else:
		ecstasy_fill.color = Color(0.4, 0.4, 0.4)
	var pulse := 0.7 + 0.3 * sin(Time.get_ticks_msec() / 200.0)
	ecstasy_label.modulate.a = pulse

func _update_weapon() -> void:
	if not player:
		return
	var w: Dictionary = GameData.WEAPONS[player.current_weapon]
	var rarity_name: String = GameData.RARITY_NAME[player.current_rarity]
	var rarity_color: Color = GameData.RARITY_COLOR[player.current_rarity]
	weapon_base_text = "%s  [%s]" % [w["name"], rarity_name]
	weapon_name_label.text = weapon_base_text
	weapon_name_label.add_theme_color_override("font_color", rarity_color)

	if player.current_weapon == "railgun":
		weapon_ammo_label.text = "BEAM: %.1fs" % player.railgun_beam_remaining
		var frac: float = player.railgun_beam_remaining / GameData.RAILGUN_BEAM_DURATION
		weapon_ammo_fill.offset_right = weapon_ammo_fill.offset_left + 230.0 * clampf(frac, 0.0, 1.0)
		weapon_ammo_fill.color = Color(0.7, 0.2, 0.9)
	else:
		weapon_ammo_label.text = "%d / %d" % [player.ammo, player.ammo_max]
		var frac: float = float(player.ammo) / max(1.0, float(player.ammo_max))
		weapon_ammo_fill.offset_right = weapon_ammo_fill.offset_left + 230.0 * clampf(frac, 0.0, 1.0)
		if frac < 0.2:
			weapon_ammo_fill.color = Color(0.85, 0.15, 0.15)
		elif frac < 0.4:
			weapon_ammo_fill.color = Color(0.9, 0.55, 0.1)
		else:
			weapon_ammo_fill.color = Color(0.7, 0.7, 0.2)

func _update_wave() -> void:
	if not wave_manager:
		return
	wave_label.text = "WAVE %d" % wave_manager.wave

func _on_hit_confirmed(is_headshot: bool) -> void:
	crosshair.flash(is_headshot)

func _on_damage_taken(attacker_pos: Vector3) -> void:
	if attacker_pos == Vector3.ZERO or not player:
		return
	var to_attacker: Vector3 = attacker_pos - player.global_position
	to_attacker.y = 0.0
	if to_attacker.length() < 0.01:
		return
	to_attacker = to_attacker.normalized()
	var fwd: Vector3 = -player.transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right: Vector3 = player.transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var forward_dot := to_attacker.dot(fwd)
	var right_dot := to_attacker.dot(right)
	damage_indicators.add_mark(atan2(-forward_dot, right_dot))

func _on_wave_announced(wave: int) -> void:
	# Cuando la oleada viene recortada, los enemigos son menos pero más duros. Sin
	# avisarlo, que las balas "no hagan nada" parece un bug y no una decisión.
	if GameState.wave_hp_mult > 1.05:
		wave_announce_label.text = "WAVE %d\nENEMIES x%.1f" % [wave, GameState.wave_hp_mult]
	else:
		wave_announce_label.text = "WAVE %d\nSURVIVE" % wave
	wave_announce_timer = 2.0

func _on_kill_feed(enemy_type: String, is_headshot: bool, is_alpha: bool) -> void:
	var stats: Dictionary = GameData.ENEMY_STATS.get(enemy_type, {})
	var ename: String = stats.get("name", enemy_type)
	var txt := ename
	if is_alpha:
		txt = "ALPHA " + txt
	if is_headshot:
		txt += "  [HEADSHOT]"
	var lbl := Label.new()
	lbl.text = txt
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 15)
	var col := Color(0.85, 0.85, 0.85)
	if is_alpha:
		col = Color(1.0, 0.3, 0.3)
	elif is_headshot:
		col = Color(1.0, 0.85, 0.2)
	lbl.add_theme_color_override("font_color", col)
	kill_feed_container.add_child(lbl)
	kill_feed_entries.append({"label": lbl, "t": 2.0})
	if kill_feed_entries.size() > 5:
		var old = kill_feed_entries.pop_front()
		if is_instance_valid(old["label"]):
			old["label"].queue_free()

# ---------------------------------------------------------------------------
# Menús (sección 10)
# ---------------------------------------------------------------------------

func _build_menus() -> void:
	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu_root)

	title_panel = _build_title_panel()
	pause_panel = _build_pause_panel()
	options_panel = _build_options_panel()
	death_panel = _build_death_panel()
	menu_root.add_child(title_panel)
	menu_root.add_child(pause_panel)
	menu_root.add_child(options_panel)
	menu_root.add_child(death_panel)

func _panel_bg(alpha: float) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.015, alpha)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	return bg

func _style_button(b: Button) -> void:
	b.custom_minimum_size = Vector2(260, 46)
	b.add_theme_font_size_override("font_size", 20)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.09, 0.04, 0.05, 0.92)
	normal.border_color = Color(0.35, 0.06, 0.06)
	normal.set_border_width_all(1)
	normal.set_content_margin_all(10)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.2, 0.05, 0.06, 0.96)
	hover.border_color = Color(0.75, 0.12, 0.12)
	hover.set_border_width_all(2)
	hover.set_content_margin_all(10)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_color_override("font_color", Color(0.85, 0.8, 0.8))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))

func _build_title_panel() -> Control:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(_panel_bg(1.0))

	title_logo = Label.new()
	title_logo.text = "FAVER MASS"
	title_logo.add_theme_font_size_override("font_size", 64)
	title_logo.add_theme_color_override("font_color", Color(0.82, 0.06, 0.06))
	title_logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rect(title_logo, Control.PRESET_CENTER_TOP, -300, 130, 600, 80)
	panel.add_child(title_logo)

	var subtitle := _make_label("sobrevive a las oleadas", Control.PRESET_CENTER_TOP, -300, 205, 600, 30, 18, Color(0.55, 0.45, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
	panel.add_child(subtitle)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	var btn_play := Button.new()
	btn_play.text = "Jugar"
	_style_button(btn_play)
	btn_play.pressed.connect(func(): GameState.start_run())
	vbox.add_child(btn_play)

	var btn_options := Button.new()
	btn_options.text = "Opciones"
	_style_button(btn_options)
	btn_options.pressed.connect(func(): GameState.open_options(GameState.State.TITLE))
	vbox.add_child(btn_options)

	var btn_quit := Button.new()
	btn_quit.text = "Salir"
	_style_button(btn_quit)
	btn_quit.pressed.connect(func(): get_tree().quit())
	vbox.add_child(btn_quit)

	return panel

func _build_pause_panel() -> Control:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(_panel_bg(0.72))

	var title := _make_label("PAUSED", Control.PRESET_CENTER_TOP, -300, 140, 600, 60, 40, Color(0.85, 0.1, 0.1), HORIZONTAL_ALIGNMENT_CENTER)
	panel.add_child(title)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	var btn_resume := Button.new()
	btn_resume.text = "Reanudar"
	_style_button(btn_resume)
	btn_resume.pressed.connect(func(): GameState.change_state(GameState.State.PLAYING))
	vbox.add_child(btn_resume)

	var btn_options := Button.new()
	btn_options.text = "Opciones"
	_style_button(btn_options)
	btn_options.pressed.connect(func(): GameState.open_options(GameState.State.PAUSED))
	vbox.add_child(btn_options)

	var btn_quit := Button.new()
	btn_quit.text = "Salir al menú"
	_style_button(btn_quit)
	btn_quit.pressed.connect(_on_quit_to_menu)
	vbox.add_child(btn_quit)

	return panel

func _build_options_panel() -> Control:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(_panel_bg(1.0))

	var title := _make_label("OPCIONES", Control.PRESET_CENTER_TOP, -300, 60, 600, 50, 34, Color(0.85, 0.1, 0.1), HORIZONTAL_ALIGNMENT_CENTER)
	panel.add_child(title)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	vbox.add_theme_constant_override("separation", 18)
	center.add_child(vbox)

	vbox.add_child(_build_slider_row("Volumen Maestro", 0.0, 1.0, GameData.master_volume, func(v):
		GameData.master_volume = v
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(max(v, 0.0001)))
		GameData.save_config()
	))
	vbox.add_child(_build_slider_row("Volumen de Efectos", 0.0, 1.0, GameData.sfx_volume, func(v):
		GameData.sfx_volume = v
		GameData.save_config()
	))
	vbox.add_child(_build_slider_row("Sensibilidad del Mouse", 0.0005, 0.01, GameData.mouse_sensitivity, func(v):
		GameData.mouse_sensitivity = v
		GameData.save_config()
	))
	vbox.add_child(_build_slider_row("Campo de Visión", GameData.FOV_MIN, GameData.FOV_MAX, GameData.fov, func(v):
		GameData.fov = v
		if player and player.has_node("Camera3D"):
			player.get_node("Camera3D").fov = v
		GameData.save_config()
	))

	var fs_row := HBoxContainer.new()
	fs_row.add_theme_constant_override("separation", 12)
	var fs_label := Label.new()
	fs_label.text = "Pantalla Completa"
	fs_label.custom_minimum_size = Vector2(260, 0)
	fs_label.add_theme_font_size_override("font_size", 16)
	fs_row.add_child(fs_label)
	var fs_check := CheckBox.new()
	fs_check.button_pressed = GameData.fullscreen
	fs_check.toggled.connect(func(pressed):
		GameData.fullscreen = pressed
		GameData.apply_fullscreen()
		GameData.save_config()
	)
	fs_row.add_child(fs_check)
	vbox.add_child(fs_row)

	var btn_back := Button.new()
	btn_back.text = "Volver"
	_style_button(btn_back)
	btn_back.pressed.connect(func(): GameState.close_options())
	vbox.add_child(btn_back)

	return panel

func _build_slider_row(label_text: String, min_v: float, max_v: float, current: float, on_change: Callable) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 16)
	col.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = (max_v - min_v) / 200.0
	slider.value = current
	slider.custom_minimum_size = Vector2(420, 20)
	slider.value_changed.connect(func(v): on_change.call(v))
	col.add_child(slider)
	return col

func _build_death_panel() -> Control:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(_panel_bg(0.78))

	var title := _make_label("YOU DIED", Control.PRESET_CENTER_TOP, -300, 110, 600, 60, 44, Color(0.85, 0.1, 0.1), HORIZONTAL_ALIGNMENT_CENTER)
	panel.add_child(title)

	death_stats_label = _make_label("", Control.PRESET_CENTER_TOP, -260, 185, 520, 120, 18, Color(0.8, 0.75, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	panel.add_child(death_stats_label)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.custom_minimum_size = Vector2(0, 120)
	vbox.alignment = BoxContainer.ALIGNMENT_END
	center.add_child(vbox)

	var btn_again := Button.new()
	btn_again.text = "Jugar de nuevo"
	_style_button(btn_again)
	btn_again.pressed.connect(func():
		GameState.start_run()
		get_tree().reload_current_scene()
	)
	vbox.add_child(btn_again)

	var btn_quit := Button.new()
	btn_quit.text = "Salir al menú"
	_style_button(btn_quit)
	btn_quit.pressed.connect(_on_quit_to_menu)
	vbox.add_child(btn_quit)

	return panel

func _on_quit_to_menu() -> void:
	GameState.change_state(GameState.State.TITLE)
	get_tree().reload_current_scene()

func _on_state_changed(new_state: int) -> void:
	title_panel.visible = new_state == GameState.State.TITLE
	pause_panel.visible = new_state == GameState.State.PAUSED
	options_panel.visible = new_state == GameState.State.OPTIONS
	death_panel.visible = new_state == GameState.State.DEAD
	hud_root.visible = new_state != GameState.State.TITLE and new_state != GameState.State.OPTIONS

	if new_state == GameState.State.DEAD:
		death_stats_label.text = "Oleadas sobrevividas: %d\nKills: %d   Headshots: %d (%.0f%%)\nTiempo vivo: %ds" % [
			GameState.run_wave, GameState.run_kills, GameState.run_headshots,
			GameState.headshot_accuracy(), int(GameState.run_time_alive())
		]
