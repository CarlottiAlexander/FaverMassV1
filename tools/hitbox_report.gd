extends Node
## Herramienta de diagnóstico: para cada tipo de enemigo instancia `enemy.tscn`
## igual que el juego y compara la FORMA DE COLISIÓN contra el volumen real del
## modelo visible y contra la cabeza real. Es la única forma de saber si la
## hitbox coincide con lo que ve el jugador sin tener que jugar a ciegas.
##
## Correr:  Godot --headless --path . tools/hitbox_report.tscn

const TYPES := ["hollow", "thrall", "dire_bat", "blood_lord", "knight", "capra", "sorceress", "demon_skull"]

func _ready() -> void:
	await get_tree().process_frame
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	for t in TYPES:
		var e = scene.instantiate()
		e.enemy_type = t
		add_child(e)
		await get_tree().process_frame

		var shape: Shape3D = e.get_node("CollisionShape3D").shape
		var sh_bottom := 0.0
		var sh_top := 0.0
		var sh_desc := ""
		if shape is CapsuleShape3D:
			sh_bottom = -shape.height * 0.5
			sh_top = shape.height * 0.5
			sh_desc = "cápsula r=%.2f h=%.2f" % [shape.radius, shape.height]
		elif shape is SphereShape3D:
			sh_bottom = -shape.radius
			sh_top = shape.radius
			sh_desc = "esfera  r=%.2f" % shape.radius

		print("=== %-12s %s   cubre Y %.2f..%.2f" % [t, sh_desc, sh_bottom, sh_top])

		var body := _aabb(e, [], EnemyModelImport.EQUIPMENT_KEYWORDS)
		print("   cuerpo visible : Y %6.2f..%6.2f   ancho X %.2f Z %.2f" % [
			body.position.y, body.end.y, body.size.x, body.size.z])
		print("   desfase        : pies %+.3f   techo %+.3f   (0 = alineado)" % [
			body.position.y - sh_bottom, body.end.y - sh_top])

		# El GLB trae el set entero montado en las manos; acá tiene que quedar sólo
		# lo que declara EQUIPMENT_KEEP.
		var carried: Array = []
		var hidden := 0
		for m in _all_meshes_including_hidden(e):
			if not _matches(m.name.to_lower(), EnemyModelImport.EQUIPMENT_KEYWORDS):
				continue
			if m.is_visible_in_tree():
				carried.append(m.name)
			else:
				hidden += 1
		if not carried.is_empty() or hidden > 0:
			print("   equipamiento   : lleva %s  (ocultas %d del pack)" % [
				"nada" if carried.is_empty() else ", ".join(carried), hidden])

		var head := _aabb(e, EnemyModelImport.HEAD_KEYWORDS, [])
		if e.head_hit_radius > 0.0:
			var hc: Vector3 = e.head_center
			var floor_y: float = e.head_floor_y
			print("   headshot       : esfera centro Y=%.2f r=%.2f  -> cubre Y %.2f..%.2f  | piso torso Y=%s" % [
				hc.y, e.head_hit_radius, maxf(hc.y - e.head_hit_radius, floor_y), hc.y + e.head_hit_radius,
				"(ninguno)" if floor_y == -INF else "%.2f" % floor_y])
			if head.size != Vector3.ZERO:
				var head_names: Array = []
				for m in _all_meshes(e):
					if _matches(m.name.to_lower(), EnemyModelImport.HEAD_KEYWORDS):
						head_names.append(m.name)
				print("   mallas cabeza  : %s" % ", ".join(head_names))
				# Los ojos delatan hacia dónde mira la cabeza: tienen que dar a -Z
				# (el frente), igual que en el modelo del que salieron.
				for m in _all_meshes(e):
					if m.name.to_lower().contains("eyes"):
						var ea: AABB = (e.global_transform.affine_inverse() * m.global_transform) * m.mesh.get_aabb()
						print("   ojos           : Z %6.2f..%6.2f  -> mira hacia %s" % [
							ea.position.z, ea.end.z, "-Z (adelante) OK" if ea.get_center().z < 0.0 else "+Z (AL REVÉS)"])
				print("   cabeza visible : Y %6.2f..%6.2f  %s" % [
					head.position.y, head.end.y,
					"OK" if hc.y - e.head_hit_radius <= head.position.y + 0.02 and hc.y + e.head_hit_radius >= head.end.y - 0.02 else "NO CUBRE TODA LA CABEZA"])
			else:
				print("   cabeza visible : sin mallas con nombre de cabeza (esfera desde el hueso del rig)")
		else:
			print("   headshot       : SIN medir -> banda de altura (top 15%)")
		e.queue_free()
		await get_tree().process_frame
	get_tree().quit()

func _aabb(root: Node3D, include: Array, exclude: Array) -> AABB:
	var box := AABB()
	var first := true
	var to_local: Transform3D = root.global_transform.affine_inverse()
	for m in _all_meshes(root):
		var n: String = m.name.to_lower()
		if not include.is_empty() and not _matches(n, include):
			continue
		if not exclude.is_empty() and _matches(n, exclude):
			continue
		var a: AABB = (to_local * m.global_transform) * m.mesh.get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return box

func _matches(n: String, keywords: Array) -> bool:
	for k in keywords:
		if n.contains(k):
			return true
	return false

## Como _all_meshes pero SIN filtrar por visibilidad — hace falta para poder
## contar justamente las que se ocultaron.
func _all_meshes_including_hidden(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and node.mesh and node.name != "Aura":
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_meshes_including_hidden(c))
	return out

func _all_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and node.mesh and node.is_visible_in_tree() and node.name != "Aura":
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_meshes(c))
	return out
