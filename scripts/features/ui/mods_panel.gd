class_name ModsPanel
extends Control
## Pantalla de Mods: qué encontró el juego en la carpeta, con una palomita por mod
## y el motivo cuando algo falló.
##
## Vive aparte de `menus.gd` porque ese archivo ya tiene las cuatro pantallas y
## esto suma bastante (scroll, filas, errores). Misma división que ya existe entre
## `hud.gd` y `menus.gd`.
##
## Es de sólo lectura sobre el estado de los mods salvo por la palomita: quién
## carga qué es cosa de `ModManager`.

const ROJO := Color(0.85, 0.2, 0.2)
const GRIS := Color(0.55, 0.5, 0.5)
const AMBAR := Color(0.85, 0.65, 0.2)

var _lista: VBoxContainer
var _pie: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.015, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(620, 0)
	center.add_child(col)

	var titulo := Label.new()
	titulo.text = "MODS"
	titulo.add_theme_font_size_override("font_size", 40)
	titulo.add_theme_color_override("font_color", Color(0.82, 0.06, 0.06))
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(titulo)

	# La ruta va SIEMPRE visible, no escondida en un tooltip: el problema número
	# uno de un sistema de mods es que el jugador no sabe dónde poner los archivos.
	var ruta := Label.new()
	ruta.text = ModManager.mods_dir
	ruta.add_theme_font_size_override("font_size", 12)
	ruta.add_theme_color_override("font_color", GRIS)
	ruta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ruta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(ruta)

	if ModManager.using_fallback_dir or ModManager.dir_error != "":
		var aviso := Label.new()
		aviso.text = ModManager.dir_error
		aviso.add_theme_font_size_override("font_size", 12)
		aviso.add_theme_color_override("font_color", AMBAR)
		aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		aviso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(aviso)

	var abrir := Button.new()
	abrir.text = "Abrir carpeta"
	Menus.style_button(abrir)
	# Esto es lo que de verdad resuelve "no la encuentro": abre el Explorador en la
	# carpeta correcta y el jugador deja de tener que interpretar una ruta.
	abrir.pressed.connect(func(): OS.shell_open(ModManager.mods_dir))
	var fila_abrir := CenterContainer.new()
	fila_abrir.add_child(abrir)
	col.add_child(fila_abrir)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_lista = VBoxContainer.new()
	_lista.add_theme_constant_override("separation", 10)
	_lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_lista)

	_pie = Label.new()
	_pie.add_theme_font_size_override("font_size", 13)
	_pie.add_theme_color_override("font_color", AMBAR)
	_pie.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_pie)

	var volver := Button.new()
	volver.text = "Volver"
	Menus.style_button(volver)
	volver.pressed.connect(func(): GameState.close_overlay())
	var fila_volver := CenterContainer.new()
	fila_volver.add_child(volver)
	col.add_child(fila_volver)

	refrescar()
	ModManager.mods_reloaded.connect(refrescar)

## Se llama al abrir la pantalla: si el jugador copió una carpeta con el juego
## abierto, la ve sin tener que reiniciar.
func refrescar() -> void:
	for c in _lista.get_children():
		c.queue_free()

	if not ModManager.has_any():
		# El caso que ve el 90% la primera vez. Una lista vacía no explica nada;
		# esto es el onboarding entero.
		var vacio := Label.new()
		vacio.text = "No hay mods todavía.\n\nCreá una carpeta acá adentro con esta forma:\n\n    mi_mod/reemplazos/hollow.glb\n\ny ese enemigo va a usar tu modelo.\nEl tamaño y la hitbox se ajustan solos."
		vacio.add_theme_font_size_override("font_size", 15)
		vacio.add_theme_color_override("font_color", GRIS)
		vacio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lista.add_child(vacio)
		_pie.text = ""
		return

	for e: Dictionary in ModManager.entries:
		_lista.add_child(_fila(e))
	_actualizar_pie()

func _actualizar_pie() -> void:
	if ModManager.pending:
		_pie.text = "Los cambios se aplican al empezar una partida nueva."
	else:
		_pie.text = ""

func _fila(e: Dictionary) -> Control:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 12)

	var check := CheckBox.new()
	check.button_pressed = e["enabled"]
	# Un mod que ni siquiera se pudo leer no se puede "activar": dejar la palomita
	# clickeable sería prometer algo que no va a pasar.
	check.disabled = not e["errors"].is_empty()
	var id: String = e["id"]
	check.toggled.connect(func(v: bool):
		ModManager.set_enabled(id, v)
		_actualizar_pie())
	fila.add_child(check)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.custom_minimum_size = Vector2(520, 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var nombre := Label.new()
	nombre.text = String(e["name"])
	nombre.add_theme_font_size_override("font_size", 17)
	nombre.add_theme_color_override("font_color", Color(0.85, 0.8, 0.8))
	col.add_child(nombre)

	col.add_child(_detalle(e))
	fila.add_child(col)
	return fila

## Una sola línea de detalle, priorizando lo que el jugador necesita: primero el
## error (por qué no anda), después los avisos, y recién si está todo bien, qué
## cargó. El resto va al tooltip para no convertir la lista en un muro de texto.
func _detalle(e: Dictionary) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var errores: Array = e["errors"]
	var avisos: Array = e["warnings"]
	if not errores.is_empty():
		lbl.text = String(errores[0])
		lbl.add_theme_color_override("font_color", ROJO)
		lbl.tooltip_text = "\n".join(PackedStringArray(errores + avisos))
	elif not avisos.is_empty():
		lbl.text = avisos[0] if avisos.size() == 1 else "%s  (+%d avisos más)" % [avisos[0], avisos.size() - 1]
		lbl.add_theme_color_override("font_color", AMBAR)
		lbl.tooltip_text = "\n".join(PackedStringArray(avisos))
	else:
		lbl.text = String(e["summary"]) if e["summary"] != "" else "listo"
		lbl.add_theme_color_override("font_color", GRIS)
	return lbl
