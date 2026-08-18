extends Node3D
## Viewmodel de arma en primera persona: las 10 armas usan modelos del pack
## Quaternius "Ultimate Guns" (CC0 — ver assets/weapons/LICENSE_quaternius_guns.txt).
##
## Se probaron los blasters sci-fi de Kenney para Railgun y Rocket Launcher
## (temáticamente encajaban mejor) pero se descartaron: su malla visible es
## mucho más chica que el volumen que declaran, así que en pantalla aparecían
## como una manchita de pocos píxeles. Quedaron dos rifles largos en su lugar.

var model_root: Node3D
var current_weapon := ""
## Punta del caño en espacio de este nodo, medida del modelo (cada arma tiene su
## largo). De acá salen los proyectiles — ver `get_muzzle_global()`.
var muzzle_local := Vector3(0.0, 0.0, -0.35)
var base_position: Vector3
var kick := 0.0
var bob_t := 0.0
var player: CharacterBody3D = null

## ESCALA POR PACK, NO POR ARMA.
##
## El intento anterior escalaba cada arma para que TODAS ocuparan el mismo largo
## en pantalla. Estaba mal: una pistola estirada al largo de un rifle queda
## gordísima ("se ve enorme") y un francotirador encogido queda fino y parece
## lejano. En un FPS real (Counter-Strike, etc.) las armas conservan su tamaño
## RELATIVO: la pistola es chica, el rifle es largo.
##
## Como cada pack modela sus armas a una escala coherente entre sí, alcanza con
## un único factor por pack. Calibrado para que el AK (5.422 nativo) quede en
## ~0.70u, que es un largo de viewmodel típico.
const QUATERNIUS_SCALE := 0.129

## Los modelos de Quaternius apuntan por +X y la cámara mira hacia -Z, así que
## van girados 90° en Y. `yaw` es por arma y no global porque el pack no es 100%
## consistente: hubo un francotirador modelado al revés (apuntaba al jugador) y
## se terminó cambiando por otro en vez de compensarlo con la rotación.
const WEAPON_CONFIG := {
	"pistol":   {"scale": QUATERNIUS_SCALE, "yaw": 90.0},
	"revolver": {"scale": QUATERNIUS_SCALE, "yaw": 90.0},
	"smg":      {"scale": QUATERNIUS_SCALE, "yaw": 90.0},
	"ak47":     {"scale": QUATERNIUS_SCALE, "yaw": 90.0},
	"shotgun":  {"scale": QUATERNIUS_SCALE, "yaw": 90.0},
	"sniper":   {"scale": QUATERNIUS_SCALE, "yaw": 90.0},
	"lmg":      {"scale": QUATERNIUS_SCALE, "yaw": 90.0},
	"minigun":  {"scale": QUATERNIUS_SCALE, "yaw": 90.0},
	"railgun":  {"scale": QUATERNIUS_SCALE, "yaw": 90.0},
	# "La Maleducada" va 1.5x más grande que el resto a pedido del usuario: es el
	# arma más destructiva del juego y tiene que imponer en pantalla.
	"rocket":   {"scale": QUATERNIUS_SCALE * 1.5, "yaw": 90.0},
}

func _ready() -> void:
	base_position = position

func _process(delta: float) -> void:
	kick = lerpf(kick, 0.0, 12.0 * delta)
	var offset := Vector3(0.0, 0.0, kick)
	if player and is_instance_valid(player):
		var moving := Vector2(player.velocity.x, player.velocity.z).length() > 0.3
		if moving:
			bob_t += delta * 9.0
			offset.y += sin(bob_t) * 0.008
			offset.x += cos(bob_t * 0.5) * 0.004
	position = base_position + offset

func on_fire() -> void:
	kick = 0.07

func set_weapon(id: String, rarity: int) -> void:
	current_weapon = id
	if model_root and is_instance_valid(model_root):
		model_root.queue_free()
	model_root = Node3D.new()
	add_child(model_root)

	var scene: PackedScene = load("res://assets/weapons/%s.glb" % id)
	if scene:
		var mesh_inst: Node3D = scene.instantiate()
		var cfg: Dictionary = WEAPON_CONFIG.get(id, {"scale": QUATERNIUS_SCALE, "yaw": 90.0})
		mesh_inst.scale = Vector3.ONE * float(cfg["scale"])
		mesh_inst.rotation_degrees = Vector3(0.0, cfg["yaw"], 0.0)
		model_root.add_child(mesh_inst)
		_center_model(mesh_inst)

	_add_rarity_accent(rarity)

## Cada modelo trae su origen donde quiso el artista (la punta del caño, la
## culata, el centro...). Sin corregirlo, dos armas con la misma posición de
## nodo aparecen en lugares completamente distintos de la pantalla — pasó con
## las de Kenney, que quedaban directamente fuera de cuadro.
##
## Se mide el volumen real ya transformado (escala + rotación aplicadas) y se
## desplaza el modelo para que ese volumen quede centrado en el nodo. Así
## cualquier modelo de cualquier pack cae siempre en el mismo lugar.
func _center_model(inst: Node3D) -> void:
	var meshes := _all_mesh_instances(inst)
	if meshes.is_empty():
		return
	# AABB de todo el modelo en espacio de mundo (ya con escala y rotación)
	var world_aabb: AABB
	var first := true
	for m in meshes:
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		if first:
			world_aabb = a
			first = false
		else:
			world_aabb = world_aabb.merge(a)
	# llevar el centro al espacio del padre y descontarlo
	var parent := inst.get_parent() as Node3D
	var local_center: Vector3 = parent.global_transform.affine_inverse() * world_aabb.get_center()
	inst.position -= local_center

	_measure_muzzle(meshes)

## Encuentra la punta del caño de ESTA arma. Se mide por arma porque una pistola
## y un francotirador no tienen ni cerca el mismo largo.
##
## NO alcanza con el centro del AABB: el cargador y la culata cuelgan bastante
## por debajo del caño y arrastran ese centro hacia abajo, así que los proyectiles
## salían de abajo del arma en vez de la boca (reportado jugando).
##
## Lo que sí funciona es mirar la GEOMETRÍA: se toman los vértices del frente del
## modelo (la rodaja más adelantada) y se promedian. Esa rodaja es la boca del
## caño, así que su promedio cae sobre el eje del caño. Corre una vez por cambio
## de arma, no por frame.
func _measure_muzzle(meshes: Array) -> void:
	var to_self: Transform3D = global_transform.affine_inverse()
	var box := AABB()
	var box_empty := true
	for m in meshes:
		var b: AABB = (to_self * m.global_transform) * m.mesh.get_aabb()
		if box_empty:
			box = b
			box_empty = false
		else:
			box = box.merge(b)
	if box_empty:
		return

	# La cámara mira hacia -Z y el `yaw` de WEAPON_CONFIG deja todas las armas con
	# el caño para ese lado, así que el frente es el mínimo en Z.
	var tip_z := box.position.z
	var slab: float = maxf(box.size.z * 0.06, 0.01)
	var acc := Vector3.ZERO
	var count := 0
	for m in meshes:
		var xf: Transform3D = to_self * m.global_transform
		for v in m.mesh.get_faces():
			var p: Vector3 = xf * v
			if p.z <= tip_z + slab:
				acc += p
				count += 1
	if count > 0:
		muzzle_local = Vector3(acc.x / count, acc.y / count, tip_z)
	else:
		muzzle_local = Vector3(box.get_center().x, box.get_center().y, tip_z)

## Posición mundial de la boca del arma. Es de donde salen los proyectiles.
func get_muzzle_global() -> Vector3:
	return global_transform * muzzle_local

func _all_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and node.mesh:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_mesh_instances(c))
	return out

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _part(mesh: Mesh, pos: Vector3, color: Color, parent: Node3D, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

func _box(size: Vector3, pos: Vector3, color: Color, parent: Node3D = null, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _part(m, pos, color, parent if parent else model_root, rot_deg)

func _add_rarity_accent(rarity: int) -> void:
	var col: Color = GameData.RARITY_COLOR[rarity]
	var accent := _box(Vector3(0.006, 0.006, 0.16), Vector3(0.026, 0.015, -0.12), col, model_root)
	var mat: StandardMaterial3D = accent.get_surface_override_material(0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.5
