class_name Menus
extends Control
## Pantallas de menú (sección 10): título, pausa, opciones y muerte. Las cuatro se
## construyen de una y se muestran/ocultan por estado, en vez de crearlas y
## destruirlas: son baratas y así no hay parpadeo al pausar.
##
## Es la única parte de la UI que ESCRIBE — toca `Config` (y el `AudioServer` y la
## cámara a través de él). El HUD sólo lee.

var player: Node = null

var title_panel: Control
var pause_panel: Control
var options_panel: Control
var death_panel: Control
var death_stats_label: Label
var title_logo: Label
var title_pulse_t := 0.0

func _ready() -> void:
	# Ver la nota en `hud.gd`: estando ya en el árbol hay que usar la variante
	# `_and_offsets_`, si no el panel queda de tamaño 0 y los menús se descuadran.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	title_panel = _build_title_panel()
	pause_panel = _build_pause_panel()
	options_panel = _build_options_panel()
	death_panel = _build_death_panel()
	add_child(title_panel)
	add_child(pause_panel)
	add_child(options_panel)
	add_child(death_panel)

func _process(delta: float) -> void:
	title_pulse_t += delta
	if title_logo:
		title_logo.modulate.a = 0.75 + 0.25 * sin(title_pulse_t * 2.0)

func apply_state(new_state: int) -> void:
	title_panel.visible = new_state == GameState.State.TITLE
	pause_panel.visible = new_state == GameState.State.PAUSED
	options_panel.visible = new_state == GameState.State.OPTIONS
	death_panel.visible = new_state == GameState.State.DEAD

	if new_state == GameState.State.DEAD:
		death_stats_label.text = "Oleadas sobrevividas: %d\nKills: %d   Headshots: %d (%.0f%%)\nTiempo vivo: %ds" % [
			GameState.run_wave, GameState.run_kills, GameState.run_headshots,
			GameState.headshot_accuracy(), int(GameState.run_time_alive())
		]

# ---------------------------------------------------------------------------
# Fábricas
# ---------------------------------------------------------------------------

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
	UILayout.rect(title_logo, Control.PRESET_CENTER_TOP, -300, 130, 600, 80)
	panel.add_child(title_logo)

	var subtitle := UILayout.label("sobrevive a las oleadas", Control.PRESET_CENTER_TOP, -300, 205, 600, 30, 18, Color(0.55, 0.45, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
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

	var title := UILayout.label("PAUSED", Control.PRESET_CENTER_TOP, -300, 140, 600, 60, 40, Color(0.85, 0.1, 0.1), HORIZONTAL_ALIGNMENT_CENTER)
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

	var title := UILayout.label("OPCIONES", Control.PRESET_CENTER_TOP, -300, 60, 600, 50, 34, Color(0.85, 0.1, 0.1), HORIZONTAL_ALIGNMENT_CENTER)
	panel.add_child(title)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	vbox.add_theme_constant_override("separation", 18)
	center.add_child(vbox)

	vbox.add_child(_build_slider_row("Volumen Maestro", 0.0, 1.0, Config.master_volume, func(v):
		Config.master_volume = v
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(max(v, 0.0001)))
		Config.save_config()
	))
	vbox.add_child(_build_slider_row("Volumen de Efectos", 0.0, 1.0, Config.sfx_volume, func(v):
		Config.sfx_volume = v
		Config.save_config()
	))
	vbox.add_child(_build_slider_row("Sensibilidad del Mouse", 0.0005, 0.01, Config.mouse_sensitivity, func(v):
		Config.mouse_sensitivity = v
		Config.save_config()
	))
	vbox.add_child(_build_slider_row("Campo de Visión", Config.FOV_MIN, Config.FOV_MAX, Config.fov, func(v):
		Config.fov = v
		if player and player.has_node("Camera3D"):
			player.get_node("Camera3D").fov = v
		Config.save_config()
	))

	var fs_row := HBoxContainer.new()
	fs_row.add_theme_constant_override("separation", 12)
	var fs_label := Label.new()
	fs_label.text = "Pantalla Completa"
	fs_label.custom_minimum_size = Vector2(260, 0)
	fs_label.add_theme_font_size_override("font_size", 16)
	fs_row.add_child(fs_label)
	var fs_check := CheckBox.new()
	fs_check.button_pressed = Config.fullscreen
	fs_check.toggled.connect(func(pressed):
		Config.fullscreen = pressed
		Config.apply_fullscreen()
		Config.save_config()
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

	var title := UILayout.label("YOU DIED", Control.PRESET_CENTER_TOP, -300, 110, 600, 60, 44, Color(0.85, 0.1, 0.1), HORIZONTAL_ALIGNMENT_CENTER)
	panel.add_child(title)

	death_stats_label = UILayout.label("", Control.PRESET_CENTER_TOP, -260, 185, 520, 120, 18, Color(0.8, 0.75, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
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
