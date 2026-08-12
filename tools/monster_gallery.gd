extends Node3D
## Herramienta: muestra en grilla los 45 monstruos del "Ultimate Monsters Pack"
## de Quaternius (CC0) con su ID de archivo debajo, para poder elegir cuáles
## usar como enemigos. Los GLB no traen el nombre del bicho, solo el ID.
##
## Se guarda a sí misma como PNG (ver §3 del CLAUDE.md).
## Correr SIN --headless:  Godot --path . tools/monster_gallery.tscn

const DIR_PATH := "res://assets/monsters_q"
const COLS := 9
const SPACING_X := 2.0
const SPACING_Y := 2.4

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
	key.light_energy = 1.5
	add_child(key)

	var dir := DirAccess.open(DIR_PATH)
	if not dir:
		print("[MON] no se pudo abrir ", DIR_PATH)
		get_tree().quit()
		return
	var files: Array = []
	for f in dir.get_files():
		if f.ends_with(".glb"):
			files.append(f)
	files.sort()

	var rows := int(ceil(float(files.size()) / COLS))
	for i in files.size():
		var col := i % COLS
		var row := i / COLS
		var pos := Vector3(
			(col - (COLS - 1) * 0.5) * SPACING_X,
			-row * SPACING_Y,
			0.0)

		var scene: PackedScene = load(DIR_PATH + "/" + files[i])
		if not scene:
			continue
		# El modelo va dentro de un contenedor: así `_fit_to_height` puede
		# recentrarlo/apoyarlo libremente sin pelearse con la posición de grilla,
		# que se aplica al contenedor.
		var holder := Node3D.new()
		holder.position = pos
		add_child(holder)
		var inst: Node3D = scene.instantiate()
		inst.rotation_degrees = Vector3(0, 20, 0)
		holder.add_child(inst)
		# Normalizar: los modelos vienen en tamaños MUY distintos (hay uno que es
		# 10x otro) y sin esto los grandes tapan a los chicos en la grilla.
		_fit_to_height(inst, 1.3)
		var ap := _find_anim(inst)
		if ap:
			for cand in ["Idle", "Idle_A", "Walk", "Flying_Idle"]:
				if ap.has_animation(cand):
					ap.play(cand)
					break

		var label := Label3D.new()
		label.text = files[i].replace(".glb", "")
		label.font_size = 48
		label.pixel_size = 0.0032
		label.position = pos + Vector3(0, -0.28, 0.7)
		label.modulate = Color(1, 0.92, 0.4)
		add_child(label)

	var cam := Camera3D.new()
	cam.position = Vector3(0, -(rows - 1) * SPACING_Y * 0.5 + 0.4, 17.0)
	cam.fov = 62.0
	cam.current = true
	add_child(cam)

	for i in 8:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := "user://monster_gallery.png"
	img.save_png(out)
	print("[MON] guardado: ", ProjectSettings.globalize_path(out), "  (", files.size(), " modelos)")
	get_tree().quit()

## Escala el modelo para que mida `target` de alto, lo centra horizontalmente y
## lo apoya sobre el y=0 de su contenedor.
##
## OJO: hay que medir en el espacio del CONTENEDOR, no en espacio de mundo. Si
## se usa `m.global_transform` a secas, el AABB incluye la posición de grilla del
## contenedor y al descontarla se arrastran todos los modelos al centro de la
## escena (pasó: la grilla quedaba amontonada en el medio).
func _fit_to_height(inst: Node3D, target: float) -> void:
	var meshes := _all_meshes(inst)
	if meshes.is_empty():
		return
	var holder := inst.get_parent() as Node3D
	var to_local := holder.global_transform.affine_inverse()
	var box: AABB
	var first := true
	for m in meshes:
		var a: AABB = (to_local * m.global_transform) * m.mesh.get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	if box.size.y <= 0.001:
		return
	var s: float = target / box.size.y
	inst.scale = Vector3(s, s, s)
	inst.position = Vector3(-box.get_center().x * s, -box.position.y * s, -box.get_center().z * s)

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
