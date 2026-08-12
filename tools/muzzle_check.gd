extends Node
## Comprueba, arma por arma, dónde queda la boca del caño respecto del volumen
## del modelo. Existe porque el primer intento usaba el CENTRO del AABB y los
## disparos salían de abajo del arma: el cargador y la culata arrastran ese
## centro hacia abajo.
##
## Lo que hay que mirar es la columna "vs centro": tiene que dar POSITIVO en las
## armas de fuego, porque el caño va por ARRIBA del cuerpo del arma.
##
## Correr:  Godot --headless --path . tools/muzzle_check.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var view = preload("res://scripts/weapon_view.gd").new()
	add_child(view)
	await get_tree().process_frame

	print("arma       | boca (x, y, z)              | centro y | vs centro")
	for id in GameData.WEAPONS:
		if id == "railgun":
			pass  # tiene modelo igual, se mide como el resto
		view.set_weapon(id, GameData.Rarity.COMMON)
		await get_tree().process_frame
		var box := _model_box(view)
		var m: Vector3 = view.muzzle_local
		print("%-10s | (%6.3f, %6.3f, %6.3f) | %7.3f | %+.3f %s" % [
			id, m.x, m.y, m.z, box.get_center().y, m.y - box.get_center().y,
			"OK" if m.y > box.get_center().y else "<- POR DEBAJO DEL CENTRO"])
	get_tree().quit()

func _model_box(view: Node3D) -> AABB:
	var to_self: Transform3D = view.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for m in _meshes(view):
		var a: AABB = (to_self * m.global_transform) * m.mesh.get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return box

func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and node.mesh:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
