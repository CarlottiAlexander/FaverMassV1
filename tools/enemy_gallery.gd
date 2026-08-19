extends Node3D
## Herramienta: muestra TODOS los modelos de personaje disponibles (los packs
## KayKit descargados) en una fila, con su nombre y a qué enemigo está asignado
## hoy. Sirve para elegir/reasignar modelos de mobs.
##
## Se guarda a sí misma como PNG (ver §3 del CLAUDE.md: auto-renderizar en vez
## de capturar la pantalla).
## Correr SIN --headless:  Godot --path . tools/enemy_gallery.tscn

const SK := "res://assets_import/KayKit-Character-Pack-Skeletons-1.0-main/addons/kaykit_character_pack_skeletons/Characters/gltf/"
const AD := "res://assets_import/KayKit-Character-Pack-Adventures-1.0-main/addons/kaykit_character_pack_adventures/Characters/gltf/"

## modelo -> a qué enemigo del juego está asignado (o "" si está libre)
## Muestra lo que REALMENTE está asignado hoy (lee de assets/enemies/), así la
## galería no miente cuando se cambia un modelo.
const MODELS := [
	["res://assets/enemies/hollow.glb",      "hollow",      "Hollow (zombie)"],
	["res://assets/enemies/thrall.glb",      "thrall",      "Thrall (runner)"],
	["res://assets/enemies/dire_bat.glb",    "dire_bat",    "Dire Bat"],
	["res://assets/enemies/blood_lord.glb",  "blood_lord",  "Blood Lord (vampiro)"],
	["res://assets/enemies/knight.glb",      "knight",      "Knight (tank)"],
	["res://assets/enemies/capra.glb",       "capra",       "Capra (demonio)"],
	["res://assets/enemies/sorceress.glb",   "sorceress",   "Sorceress (bruja)"],
	["res://assets/enemies/demon_skull.glb", "demon_skull", "Demon Skull"],
]

const SPACING := 2.6

func _ready() -> void:
	GameState.change_state(GameState.State.PLAYING)  # destraba los AnimationPlayer

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.5
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -30, 0)
	key.light_energy = 1.6
	add_child(key)

	var n := MODELS.size()
	for i in n:
		var path: String = MODELS[i][0]
		var model_name: String = MODELS[i][1]
		var assigned: String = MODELS[i][2]
		var x := (i - (n - 1) * 0.5) * SPACING

		var scene: PackedScene = load(path)
		if not scene:
			push_warning("no se pudo cargar " + path)
			continue
		var inst: Node3D = scene.instantiate()
		inst.position = Vector3(x, 0, 0)
		# los modelos miran a +Z y la cámara está en +Z mirando a -Z, así que 0° ya
		# los deja de frente; 20° les da un 3/4 que se lee mejor
		inst.rotation_degrees = Vector3(0, 20, 0)
		# OJO: agregar al árbol ANTES de medir — `global_transform` no existe
		# fuera del árbol y devuelve identidad con un error por consola.
		add_child(inst)
		# escalar al tamaño REAL que tiene en el juego (body_height de GameData)
		var stats: Dictionary = GameData.enemy_stats.get(model_name, {})
		if stats.has("height"):
			var nat := _height_of(inst)
			if nat > 0.01:
				var sc: float = float(stats["height"]) / nat * 0.5
				inst.scale = Vector3(sc, sc, sc)
		var ap := _find_anim(inst)
		if ap:
			for cand in ["Idle", "CharacterArmature|Flying_Idle"]:
				if ap.has_animation(cand):
					ap.play(cand)
					break

		var label := Label3D.new()
		label.text = model_name
		label.font_size = 64
		label.pixel_size = 0.0035
		label.position = Vector3(x, -0.35, 0.6)
		label.modulate = Color(1, 0.92, 0.4)
		add_child(label)

		var sub := Label3D.new()
		sub.text = assigned
		sub.font_size = 52
		sub.pixel_size = 0.0035
		sub.position = Vector3(x, -0.62, 0.6)
		sub.modulate = Color(0.55, 0.85, 1.0) if assigned != "LIBRE" else Color(0.5, 1.0, 0.55)
		add_child(sub)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.9, 14.0)
	cam.fov = 58.0
	cam.current = true
	add_child(cam)

	# dejar que las animaciones se asienten antes de la foto
	for i in 6:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := "user://enemy_gallery.png"
	img.save_png(out)
	print("[ENEMY_GALLERY] guardado: ", ProjectSettings.globalize_path(out))
	get_tree().quit()

func _height_of(node: Node3D) -> float:
	var box: AABB
	var first := true
	var to_local := node.global_transform.affine_inverse()
	for m in _all_meshes(node):
		var a: AABB = (to_local * m.global_transform) * m.mesh.get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return 0.0 if first else box.size.y

func _all_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and node.mesh:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_meshes(c))
	return out

func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var f := _find_anim(c)
		if f:
			return f
	return null
