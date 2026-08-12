extends SceneTree
## Herramienta de un solo uso: mide el AABB de cada modelo de arma para poder
## identificar cuál es cuál (los GLB de Quaternius no traen el nombre del arma,
## solo nombres de material). Correr con:
##   Godot --headless --script tools/measure_guns.gd

func _init() -> void:
	var dir := DirAccess.open("res://assets/weapons_q")
	if not dir:
		print("no dir")
		quit()
		return
	var names := dir.get_files()
	names.sort()
	for f in names:
		if not f.ends_with(".glb"):
			continue
		var scene: PackedScene = load("res://assets/weapons_q/" + f)
		if not scene:
			continue
		var inst: Node3D = scene.instantiate()
		var aabb := _combined_aabb(inst)
		var s := aabb.size
		# largo = eje mayor; grosor = el resto
		var axes := [s.x, s.y, s.z]
		axes.sort()
		print("%s | size=(%.3f, %.3f, %.3f) | largo=%.3f grosor=%.3f alto=%.3f" % [
			f, s.x, s.y, s.z, axes[2], axes[0], axes[1]])
		inst.free()
	quit()

func _combined_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in _all_nodes(node):
		if child is MeshInstance3D and child.mesh:
			var a: AABB = child.mesh.get_aabb()
			# llevar al espacio del nodo raíz
			var t: Transform3D = child.global_transform if child.is_inside_tree() else child.transform
			a = t * a
			if first:
				result = a
				first = false
			else:
				result = result.merge(a)
	return result

func _all_nodes(node: Node) -> Array:
	var out: Array = [node]
	for c in node.get_children():
		out.append_array(_all_nodes(c))
	return out
