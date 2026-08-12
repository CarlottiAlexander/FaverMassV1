extends Node3D
## Herramienta de un solo uso: muestra los 25 modelos de arma en una grilla con
## su nombre de archivo debajo, para poder identificar cuál es cuál de un
## vistazo (los GLB de Quaternius no traen el nombre del arma).

## En PÁGINAS de pocos modelos: con los 33 juntos en una sola imagen los IDs
## quedaban ilegibles, y el ID es justamente lo único que sirve para elegir.
const COLS := 4
const ROWS := 3
const SPACING_X := 9.0
const SPACING_Y := 6.0

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.12, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.6
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -40, 0)
	sun.light_energy = 1.5
	add_child(sun)

	var dir := DirAccess.open("res://assets/weapons_q")
	var files := dir.get_files()
	files.sort()
	var models: Array = []
	for f in files:
		if f.ends_with(".glb"):
			models.append(f)

	var cam := Camera3D.new()
	cam.position = Vector3(0, -(ROWS - 1) * SPACING_Y * 0.5, 30.0)
	cam.current = true
	add_child(cam)

	var per_page := COLS * ROWS
	var pages := int(ceil(float(models.size()) / per_page))
	for page in pages:
		var holders: Array[Node] = []
		for slot in per_page:
			var idx := page * per_page + slot
			if idx >= models.size():
				break
			var f: String = models[idx]
			var col := slot % COLS
			var row := slot / COLS
			var origin := Vector3(col * SPACING_X - (COLS - 1) * SPACING_X * 0.5, -row * SPACING_Y, 0.0)

			var scene: PackedScene = load("res://assets/weapons_q/" + f)
			var inst: Node3D = scene.instantiate()
			var holder := Node3D.new()
			holder.position = origin
			holder.rotation_degrees = Vector3(0, -25, 0)
			holder.add_child(inst)
			add_child(holder)
			holders.append(holder)

			var label := Label3D.new()
			label.text = f.replace(".glb", "")
			label.font_size = 96
			label.pixel_size = 0.012
			label.position = origin + Vector3(0, -2.4, 0)
			label.modulate = Color(1, 0.9, 0.3)
			add_child(label)
			holders.append(label)

		# Guardarse a sí misma como PNG en vez de depender de capturar la pantalla
		# de Windows (que falla si el usuario tiene otra ventana adelante, y encima
		# le roba el foco). Ver también tools/weapon_pov.gd.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "user://gun_gallery_%d.png" % (page + 1)
		img.save_png(path)
		print("[GALLERY] guardado: ", ProjectSettings.globalize_path(path))
		for h in holders:
			h.free()
	get_tree().quit()
