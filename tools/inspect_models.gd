extends Node
## Herramienta: imprime, para cada modelo de enemigo, su altura nativa y la
## lista de animaciones. Necesario porque los packs (KayKit vs Quaternius) usan
## nombres de animación y escalas distintas.
##
## Correr:  Godot --headless --path . tools/inspect_models.tscn

func _ready() -> void:
	var dir := DirAccess.open("res://assets/enemies")
	var files := dir.get_files()
	files.sort()
	for f in files:
		if not f.ends_with(".glb"):
			continue
		var scene: PackedScene = load("res://assets/enemies/" + f)
		if not scene:
			continue
		var inst: Node3D = scene.instantiate()
		add_child(inst)
		var h := _height(inst)
		var ap := _find_anim(inst)
		var anims := ""
		if ap:
			var list := ap.get_animation_list()
			anims = "%d anims: %s" % [list.size(), ", ".join(Array(list).slice(0, 14))]
		else:
			anims = "SIN AnimationPlayer"
		print("--- %s  (alto nativo %.3f)" % [f, h])
		print("    ", anims)
		inst.queue_free()
	get_tree().quit()

func _height(node: Node3D) -> float:
	var meshes := _all_meshes(node)
	if meshes.is_empty():
		return 0.0
	var box: AABB
	var first := true
	for m in meshes:
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return box.size.y

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
