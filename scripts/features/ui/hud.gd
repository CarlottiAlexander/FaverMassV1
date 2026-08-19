class_name Hud
extends Control
## Overlay de juego (sección 9): barras de vida y éxtasis, panel de arma, minimapa,
## contadores de oleada, kill feed y anuncios. Se construye por código.
##
## No busca nada por su cuenta: `ui.gd` le pasa `player` y `wave_manager` antes de
## agregarlo al árbol, y conecta las señales a los métodos públicos de acá. Así el
## HUD sólo LEE del jugador y del gestor de oleadas, nunca al revés.

var player: Node = null
var wave_manager: Node = null

var crosshair: HudWidgets.Crosshair
var minimap: HudWidgets.Minimap
var vignette: HudWidgets.Vignette
var damage_indicators: HudWidgets.DamageIndicators
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

const HEALTH_BAR_W := 250.0
const HEALTH_BAR_H := 18.0
const ECSTASY_BAR_H := 14.0

func _ready() -> void:
	# `set_anchors_and_offsets_preset` y NO `set_anchors_preset`: cuando el control
	# YA está en el árbol, `set_anchors_preset` recalcula los offsets para conservar
	# el rectángulo actual, y como acá el rectángulo todavía es de tamaño 0 el
	# resultado es left=0 / right=-ancho_del_viewport — o sea, sigue midiendo 0 y
	# todo lo anclado abajo o a la derecha se va de pantalla (comprobado con
	# `tools/ui_shot.tscn`: sólo sobrevivían los widgets anclados arriba a la
	# izquierda). Antes no pasaba porque el HUD se anclaba ANTES del `add_child`.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

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

# ---------------------------------------------------------------------------
# Construcción
# ---------------------------------------------------------------------------

func _build() -> void:
	crosshair = HudWidgets.Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crosshair)

	damage_indicators = HudWidgets.DamageIndicators.new()
	damage_indicators.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_indicators.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(damage_indicators)

	vignette = HudWidgets.Vignette.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	# Salud
	var health_bg := ColorRect.new()
	health_bg.color = Color(0.08, 0.08, 0.08, 0.75)
	UILayout.rect(health_bg, Control.PRESET_BOTTOM_LEFT, 20, -66, HEALTH_BAR_W, HEALTH_BAR_H)
	add_child(health_bg)
	health_fill = ColorRect.new()
	health_fill.color = Color(0.2, 0.75, 0.2)
	UILayout.rect(health_fill, Control.PRESET_BOTTOM_LEFT, 20, -66, HEALTH_BAR_W, HEALTH_BAR_H)
	add_child(health_fill)
	health_label = UILayout.label("100/100", Control.PRESET_BOTTOM_LEFT, 26, -68, HEALTH_BAR_W, HEALTH_BAR_H, 14)
	add_child(health_label)

	# Éxtasis
	var ecstasy_bg := ColorRect.new()
	ecstasy_bg.color = Color(0.08, 0.08, 0.08, 0.75)
	UILayout.rect(ecstasy_bg, Control.PRESET_BOTTOM_LEFT, 20, -66 - ECSTASY_BAR_H - 4, HEALTH_BAR_W, ECSTASY_BAR_H)
	add_child(ecstasy_bg)
	ecstasy_fill = ColorRect.new()
	ecstasy_fill.color = Color(0.5, 0.5, 0.5)
	UILayout.rect(ecstasy_fill, Control.PRESET_BOTTOM_LEFT, 20, -66 - ECSTASY_BAR_H - 4, HEALTH_BAR_W, ECSTASY_BAR_H)
	add_child(ecstasy_fill)
	ecstasy_label = UILayout.label("G", Control.PRESET_BOTTOM_LEFT, 20, -66 - ECSTASY_BAR_H - 4, HEALTH_BAR_W, ECSTASY_BAR_H, 12, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(ecstasy_label)

	# Panel de arma
	var weapon_bg := ColorRect.new()
	weapon_bg.color = Color(0.08, 0.08, 0.08, 0.75)
	UILayout.rect(weapon_bg, Control.PRESET_BOTTOM_RIGHT, -270, -90, 250, 70)
	add_child(weapon_bg)
	weapon_name_label = UILayout.label("Pistol", Control.PRESET_BOTTOM_RIGHT, -260, -86, 230, 24, 18)
	add_child(weapon_name_label)
	var ammo_bg := ColorRect.new()
	ammo_bg.color = Color(0.15, 0.15, 0.15, 0.8)
	UILayout.rect(ammo_bg, Control.PRESET_BOTTOM_RIGHT, -260, -56, 230, 16)
	add_child(ammo_bg)
	weapon_ammo_fill = ColorRect.new()
	weapon_ammo_fill.color = Color(0.7, 0.7, 0.2)
	UILayout.rect(weapon_ammo_fill, Control.PRESET_BOTTOM_RIGHT, -260, -56, 230, 16)
	add_child(weapon_ammo_fill)
	weapon_ammo_label = UILayout.label("15", Control.PRESET_BOTTOM_RIGHT, -260, -56, 230, 16, 12, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(weapon_ammo_label)

	# Minimapa (arriba del panel de arma)
	minimap = HudWidgets.Minimap.new()
	minimap.player = player
	UILayout.rect(minimap, Control.PRESET_BOTTOM_RIGHT, -140, -240, 120, 120)
	add_child(minimap)

	# Info de oleada
	wave_label = UILayout.label("WAVE 0", Control.PRESET_TOP_LEFT, 20, 20, 300, 40, 28)
	add_child(wave_label)
	enemies_label = UILayout.label("Enemies: 0", Control.PRESET_TOP_LEFT, 20, 58, 300, 24, 16, Color(0.8, 0.8, 0.8))
	add_child(enemies_label)

	# Kills/headshots
	kills_label = UILayout.label("Kills: 0   Headshots: 0", Control.PRESET_TOP_RIGHT, -320, 20, 300, 24, 16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(kills_label)

	kill_feed_container = VBoxContainer.new()
	UILayout.rect(kill_feed_container, Control.PRESET_TOP_RIGHT, -320, 50, 300, 160)
	kill_feed_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(kill_feed_container)

	# Anuncio de oleada
	wave_announce_label = Label.new()
	wave_announce_label.text = ""
	wave_announce_label.add_theme_font_size_override("font_size", 48)
	wave_announce_label.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15))
	wave_announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_announce_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UILayout.rect(wave_announce_label, Control.PRESET_CENTER, -260, -220, 520, 100)
	wave_announce_label.visible = false
	add_child(wave_announce_label)

	# FPS
	fps_label = UILayout.label("FPS: 0", Control.PRESET_BOTTOM_LEFT, 10, -24, 120, 20, 12, Color(0.6, 0.6, 0.6))
	add_child(fps_label)

	# El HUD es 100% decorativo — ningún hijo debe robarle eventos de mouse al
	# jugador. Sin esto, con Input.mouse_mode = CAPTURED, Godot igual arrastra
	# una posición virtual de cursor por toda la pantalla para el hit-test de la
	# GUI: cualquier Control con el filtro por defecto (STOP) que quede debajo
	# se come el motion event y la cámara deja de girar mientras el cursor
	# "invisible" pasa por encima (barras, panel de arma, minimapa, etc).
	_set_ignore_recursive(self)

func _set_ignore_recursive(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_ignore_recursive(child)

# ---------------------------------------------------------------------------
# Actualización (los conecta `ui.gd` a las señales del jugador y del WaveManager)
# ---------------------------------------------------------------------------

func refresh_all() -> void:
	update_health()
	update_ecstasy()
	update_weapon()
	update_wave()

func update_health() -> void:
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

func update_ecstasy() -> void:
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

func update_weapon() -> void:
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

func update_wave() -> void:
	if not wave_manager:
		return
	wave_label.text = "WAVE %d" % wave_manager.wave

func on_hit_confirmed(is_headshot: bool) -> void:
	crosshair.flash(is_headshot)

func on_damage_taken(attacker_pos: Vector3) -> void:
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

func on_wave_announced(wave: int) -> void:
	# Cuando la oleada viene recortada, los enemigos son menos pero más duros. Sin
	# avisarlo, que las balas "no hagan nada" parece un bug y no una decisión.
	if GameState.wave_hp_mult > 1.05:
		wave_announce_label.text = "WAVE %d\nENEMIES x%.1f" % [wave, GameState.wave_hp_mult]
	else:
		wave_announce_label.text = "WAVE %d\nSURVIVE" % wave
	wave_announce_timer = 2.0

func on_kill_feed(enemy_type: String, is_headshot: bool, is_alpha: bool) -> void:
	# Un tipo sin nombre declarado muestra su propio id, no el de otro enemigo.
	var txt := GameData.enemy_name_of(enemy_type)
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
