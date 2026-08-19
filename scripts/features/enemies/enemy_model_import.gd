class_name EnemyModelImport
extends RefCounted
## Carga del modelo `.glb` de un enemigo y todo lo que hace falta para que un
## personaje ajeno entre en las medidas del juego: escala, alineación contra la
## cápsula de colisión, esfera de headshot, ocultado del arsenal que el pack trae
## montado en las manos y el trasplante de cabeza.
##
## Está separado de `enemy.gd` porque se toca por una razón muy distinta: acá se
## corrige cómo se MIDE un modelo importado (que es donde aparecen los bugs de
## hitbox), y allá cómo se COMPORTA el enemigo. `tools/hitbox_report.tscn` y
## `tools/inspect_models.tscn` viven de las constantes y los helpers de este
## archivo.
##
## Las funciones reciben el enemigo como parámetro (`e: Enemy`) en vez de vivir
## adentro de él. La referencia cruzada entre `Enemy` y esta clase es cíclica y
## Godot 4 la resuelve bien mientras sea por `class_name` (un `preload()` cruzado
## sí rompería).

## Los personajes de KayKit traen adentro TODO el equipamiento del set montado en
## las manos (el Knight carga 3 espadas y 4 escudos a la vez, el Blood Lord dos
## ballestas). Cuentan para lo que se ve, pero NO para el volumen del cuerpo: un
## escudo a 1.8 m del eje corría el centro del modelo y estiraba la hitbox.
## Medido con tools/hitbox_report.tscn.
const EQUIPMENT_KEYWORDS := [
	"sword", "shield", "axe", "knife", "dagger", "crossbow", "bow", "throwable",
	"mug", "staff", "spear", "hammer", "wand", "quiver", "offhand",
]
## Qué pieza de equipamiento se le deja VISIBLE a cada tipo. Todo lo demás de
## EQUIPMENT_KEYWORDS se oculta: el GLB trae el set entero montado en las manos y
## sin esto el Knight sale cargando 3 espadas y 4 escudos a la vez.
## Los nombres se comparan EXACTOS (no por substring) justamente para poder
## quedarse con "1H_Sword" sin quedarse también con "1H_Sword_Offhand".
## Todas son armas de una mano a propósito: la animación de ataque que termina
## eligiendo ANIM_ATTACK es "1H_Melee_Attack_Chop", así que un arma a dos manos
## se vería empuñada con una. Los esqueletos (Hollow/Thrall/Sorceress) no traen
## equipamiento en su GLB, por eso no figuran acá.
const EQUIPMENT_KEEP := {
	"knight": ["1H_Sword", "Rectangle_Shield"],
	# El Knight es el único que quedó con equipamiento adentro: los personajes del
	# pack de esqueletos (Hollow, Thrall, Capra, Sorceress, Blood Lord) vienen
	# limpios, sin armas montadas en las manos.
}
## Trasplante de cabeza entre modelos: <tipo>: GLB donante. Se le ocultan al
## modelo sus propias mallas de cabeza y se le injertan las del donante colgadas
## de su hueso "head", escaladas para ocupar el mismo lugar que la que se sacó.
## Pedido textual: "arrancarle la cabeza al caballero y ponerle una de las
## cabezas de los esqueletos". Cambiar de calavera es cambiar esta ruta.
const HEAD_SWAP := {
	"knight": "res://assets/enemies/hollow.glb",  # la calavera pelada del Minion
}
## Mallas que forman la cabeza. Los modelos son chibi: la cabeza del Hollow ocupa
## casi el 45% de su altura, así que la banda de altura fija de antes (top 15%)
## dejaba los ojos y la mandíbula fuera de la zona de headshot.
const HEAD_KEYWORDS := ["head", "skull", "helmet", "hood", "jaw", "eyes", "hat"]
## Margen sobre la esfera de cabeza medida. 1.0 = exactamente la cabeza visible.
const HEAD_HITBOX_MULT := 1.0
## Un bicho más ancho que alto (murciélago con alas, cráneo volador) no se parece
## en nada a una cápsula vertical: esos van con esfera. El factor decide cuánto de
## la envergadura cuenta como cuerpo — las alas son membrana, no se cobran enteras.
const WIDE_RATIO := 1.5
const WIDE_SPAN_FACTOR := 0.45

## Instancia el `.glb`, lo mide y lo deja calzado en la cápsula del enemigo.
## Devuelve el AnimationPlayer del rig (o null): quien llama decide qué hacer con
## él, porque el escalonado de animación por distancia vive en `enemy.gd`.
static func build(e: Enemy, path: String) -> AnimationPlayer:
	var scene: PackedScene = load(path)
	if not scene:
		return null
	return build_from_scene(e, scene)

## Igual que `build()` pero recibe la escena ya cargada. Existe porque los modelos
## de la comunidad NO vienen de `res://`: se parsean del disco en tiempo de
## ejecución (ver ModModelLoader) y nunca pasan por `load()`. Todo lo que sigue
## —medir, escalar, centrar, ajustar cápsula y cabeza— es idéntico venga de donde
## venga el modelo, que es justamente lo que hace que un .glb ajeno funcione solo.
static func build_from_scene(e: Enemy, scene: PackedScene) -> AnimationPlayer:
	if not scene:
		return null
	var inst_any: Node = scene.instantiate()
	if not (inst_any is Node3D):
		# Un GLTF cuya raíz no es 3D no se puede colgar del enemigo. Devolver null
		# hace que `enemy.gd` caiga al modelo procedural en vez de quedar invisible.
		inst_any.free()
		return null
	var inst: Node3D = inst_any
	# Los modelos miran hacia +Z, pero `look_at()` orienta el -Z del nodo hacia el
	# objetivo. Sin este giro de 180° los enemigos caminan hacia el jugador
	# dándole la espalda.
	inst.rotation_degrees.y = 180.0
	e.model_root.add_child(inst)
	_hide_extra_equipment(e, inst)
	_swap_head(e, inst)

	# 1) ESCALA. Se mide el alto real del cuerpo, no una constante fija: los packs
	#    vienen en tamaños muy distintos (KayKit 2.17-2.63, los monstruos de
	#    Quaternius 1.68-3.10). Así cada enemigo respeta su `height` de GameData.
	var box := body_aabb(e, inst)
	if box.size.y > 0.01:
		var s := e.body_height / box.size.y
		inst.scale = Vector3(s, s, s)
		box = body_aabb(e, inst)

	# 2) ALINEACIÓN. El origen del CharacterBody3D es el centro de la forma de
	#    colisión, así que el centro del cuerpo VISIBLE tiene que caer ahí. No
	#    alcanza con bajar medio cuerpo asumiendo que el modelo tiene el origen en
	#    los pies: cada artista lo pone donde quiere. Medido: el Dire Bat volaba
	#    0.37 m por encima de su propia cápsula (que mide 0.55 de alto) — se le
	#    disparaba al bicho y se le pegaba al aire.
	if box.size != Vector3.ZERO:
		inst.position -= box.get_center()
		box.position -= box.get_center()
		_fit_collision(e, box)
	_fit_head(e, inst)

	return find_animation_player(inst)

## Deja una sola pieza de equipamiento por tipo (ver EQUIPMENT_KEEP) y oculta el
## resto del arsenal que el GLB trae montado en las manos.
## Va ANTES de medir el cuerpo: all_mesh_nodes() filtra por visibilidad, así que
## lo que se oculte acá ya no cuenta para nada. Lo que se deja tampoco engorda la
## hitbox — body_aabb() descarta el equipamiento por nombre, esté visible o no.
static func _hide_extra_equipment(e: Enemy, inst: Node3D) -> void:
	var keep: Array = EQUIPMENT_KEEP.get(e.enemy_type, [])
	for m in all_mesh_nodes(inst):
		var n: String = m.name.to_lower()
		if not name_matches(n, EQUIPMENT_KEYWORDS):
			continue
		m.visible = false
		for k in keep:
			if n == String(k).to_lower():
				m.visible = true
				break

## Piezas del injerto ya resueltas, por tipo de enemigo: malla + transformada
## RELATIVA al hueso del cuello. Se cachea porque armarlo obliga a instanciar el
## GLB donante entero (4.8 MB y 90+ animaciones) sólo para medirle la cabeza —
## hacerlo en cada spawn era un tirón garantizado con varios Knights por oleada.
## La transformada es la misma para todas las instancias de un tipo: al momento
## del injerto el rig está en pose de reposo, igual en todas.
static var _head_graft_cache: Dictionary = {}

## Lo llama ModManager al aplicar cambios. Este caché es ESTÁTICO: sobrevive a
## `reload_current_scene()`, así que sin vaciarlo un enemigo al que un mod le
## cambió el modelo se quedaría con el injerto medido sobre el modelo VIEJO.
static func clear_caches() -> void:
	_head_graft_cache.clear()
	_warned_head.clear()

## Tipos a los que ya se les avisó que su hueso de cabeza no sirve. Sólo para no
## repetir el mismo aviso en cada spawn.
static var _warned_head: Dictionary = {}

## Le saca la cabeza al modelo y le injerta la de otro GLB (ver HEAD_SWAP).
##
## Va ANTES de medir y escalar el cuerpo, a propósito: la cabeza nueva puede ser
## más baja o más alta que la que se sacó, y así esa diferencia entra en el
## cálculo de escala, alineación, cápsula y esfera de headshot — todo se acomoda
## solo sin un número escrito a mano.
##
## Las mallas donantes se injertan SIN esqueleto, colgadas de un BoneAttachment3D
## en el hueso del cuello: una calavera es rígida, no necesita deformarse, y así
## acompaña la animación de la cabeza sin tener que emparentar dos rigs distintos
## (que es un problema bastante peor).
static func _swap_head(e: Enemy, inst: Node3D) -> void:
	var donor_path: String = HEAD_SWAP.get(e.enemy_type, "")
	if donor_path == "" or not ResourceLoader.exists(donor_path):
		return
	var sk := find_skeleton(inst)
	if not sk:
		return
	var head_bone := find_bone_index(sk, "head")
	if head_bone < 0:
		return

	if not _head_graft_cache.has(e.enemy_type):
		_head_graft_cache[e.enemy_type] = _resolve_head_graft(e, inst, sk, head_bone, donor_path)
	var parts: Array = _head_graft_cache[e.enemy_type]
	if parts.is_empty():
		return

	# La cabeza vieja se OCULTA, no se borra: sacando la entrada de HEAD_SWAP
	# vuelve sola.
	for m in all_mesh_nodes(inst):
		if name_matches(m.name.to_lower(), HEAD_KEYWORDS):
			m.visible = false

	var attach := BoneAttachment3D.new()
	attach.name = "HeadGraft"
	sk.add_child(attach)
	attach.bone_idx = head_bone
	for part in parts:
		var mi := MeshInstance3D.new()
		mi.name = part["name"]
		mi.mesh = part["mesh"]
		var mats: Array = part["mats"]
		for s in mats.size():
			if mats[s]:
				mi.set_surface_override_material(s, mats[s])
		attach.add_child(mi)
		mi.transform = part["xform"]

## Instancia el donante, le mide la cabeza y devuelve las piezas listas para
## colgar del hueso del cuello. Corre UNA sola vez por tipo (ver el caché).
static func _resolve_head_graft(e: Enemy, inst: Node3D, sk: Skeleton3D, head_bone: int, donor_path: String) -> Array:
	# Se mide la cabeza original ANTES de taparla: es el molde al que se ajusta la
	# nueva, así el trasplante funciona entre cualquier par de modelos.
	var own_head := mesh_aabb(e, inst, HEAD_KEYWORDS)
	if own_head.size.y < 0.001:
		return []
	var donor: Node3D = load(donor_path).instantiate()
	# El MISMO giro de 180° que se le da al modelo receptor. Sin esto el donante
	# queda mirando al revés que el cuerpo, y como el ajuste de abajo sólo escala
	# y traslada (no rota), la calavera terminaba puesta de espaldas.
	donor.rotation_degrees.y = 180.0
	e.model_root.add_child(donor)
	var donor_head := mesh_aabb(e, donor, HEAD_KEYWORDS)
	if donor_head.size.y < 0.001:
		donor.visible = false
		donor.queue_free()
		return []

	var fit := own_head.size.y / donor_head.size.y
	# Mapa afín que lleva la cabeza donante al tamaño y al lugar exactos de la
	# original, en espacio local de este enemigo.
	var place := Transform3D(
		Basis.IDENTITY.scaled(Vector3.ONE * fit),
		own_head.get_center() - donor_head.get_center() * fit)
	# Se calcula a mano dónde va a quedar el BoneAttachment en vez de leerle la
	# transformada: recién se acomoda cuando el esqueleto avisa que cambió la
	# pose, que puede ser un frame más tarde.
	var attach_global: Transform3D = sk.global_transform * sk.get_bone_global_pose(head_bone)
	var to_attach: Transform3D = attach_global.affine_inverse()
	var to_local: Transform3D = e.global_transform.affine_inverse()

	var parts: Array = []
	for dm in all_mesh_nodes(donor):
		if not name_matches(dm.name.to_lower(), HEAD_KEYWORDS):
			continue
		var mats: Array = []
		for s in dm.mesh.get_surface_count():
			mats.append(dm.get_surface_override_material(s))
		parts.append({
			"name": dm.name,
			"mesh": dm.mesh,
			"mats": mats,
			"xform": to_attach * e.global_transform * place * (to_local * dm.global_transform),
		})
	donor.visible = false
	donor.queue_free()
	return parts

static func find_bone_index(sk: Skeleton3D, bone_name: String) -> int:
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).to_lower() == bone_name:
			return i
	return -1

## Ajusta la forma de colisión al volumen que el jugador realmente ve.
static func _fit_collision(e: Enemy, box: AABB) -> void:
	e.body_height = box.size.y
	if box.size.x > box.size.y * WIDE_RATIO:
		# Bicho ancho y chato (murciélago, cráneo volador): esfera.
		var sph := SphereShape3D.new()
		sph.radius = 0.5 * maxf(maxf(box.size.y, box.size.z), box.size.x * WIDE_SPAN_FACTOR)
		e.collision_shape.shape = sph
		e.body_radius = sph.radius
		return
	# Humanoide: se conserva el radio de la tabla (está afinado contra el torso,
	# verificado modelo por modelo) y sólo se corrige la altura contra el modelo.
	# El ancho del AABB no sirve como radio: los rigs se miden en pose de reposo,
	# con los brazos en cruz — el Hollow "mide" 2.10 de ancho por los brazos.
	var cap := CapsuleShape3D.new()
	cap.height = maxf(box.size.y, 0.1)
	cap.radius = minf(e.body_radius, cap.height * 0.5)
	e.collision_shape.shape = cap
	e.body_radius = cap.radius

## Esfera de headshot ajustada a la cabeza real del modelo. Se prueba primero por
## nombre de malla (KayKit los nombra: *_Head, *_Helmet, *_Skull...) y si el pack
## no los nombra así, por el hueso "head" del rig.
static func _fit_head(e: Enemy, inst: Node3D) -> void:
	var box := mesh_aabb(e, inst, HEAD_KEYWORDS)
	if box.size != Vector3.ZERO:
		e.head_center = box.get_center()
		e.head_hit_radius = 0.5 * maxf(box.size.x, maxf(box.size.y, box.size.z)) * HEAD_HITBOX_MULT
		# Techo del torso = frontera real cabeza/cuerpo de ESTE modelo. Si no hay
		# torso (el Demon Skull es una calavera y nada más), no hay piso: todo el
		# bicho es cabeza, que es exactamente lo que se ve.
		var torso := mesh_aabb(e, inst, [], EQUIPMENT_KEYWORDS + HEAD_KEYWORDS)
		if torso.size != Vector3.ZERO:
			e.head_floor_y = torso.end.y
		return
	var sk := find_skeleton(inst)
	if not sk:
		return
	var idx := find_bone_index(sk, "head")
	if idx < 0:
		return
	var to_local: Transform3D = e.global_transform.affine_inverse()
	var centro := (to_local * sk.global_transform * sk.get_bone_global_pose(idx)).origin

	# CONTROL DE SENSATEZ. El camino del hueso no valida nada: se fía de que el rig
	# tenga un hueso llamado "head" y de que su pose esté donde uno espera. Con los
	# dos packs del juego base funciona, pero un modelo cualquiera de la comunidad
	# puede tener el hueso nombrado igual y puesto en cualquier lado — medido con un
	# monstruo del banco, la esfera caía en Y=-0.54, o sea en las patas: se le
	# disparaba a las piernas y contaba como headshot instakill.
	#
	# Una cabeza por debajo del centro vertical del cuerpo no es una cabeza. Ante la
	# duda se deja `head_hit_radius` en 0, que hace caer la detección a la banda de
	# altura de `HEADSHOT_HEIGHT_FRACTION` — menos preciso, pero nunca absurdo.
	var radio := e.head_radius * 1.5 * HEAD_HITBOX_MULT

	# CONTROL DE ALCANZABILIDAD. El camino del hueso no valida nada: se fía de que
	# el rig tenga un hueso llamado "head" y de que su pose esté donde uno espera.
	# Con los dos packs del juego base funciona, pero un modelo cualquiera de la
	# comunidad puede tenerlo en cualquier lado.
	#
	# El criterio NO es "está muy abajo" sino algo geométrico: las balas impactan en
	# la SUPERFICIE de la forma de colisión, así que una esfera de cabeza que no
	# asoma por encima de la silueta queda enterrada adentro del cuerpo y es
	# IMPOSIBLE de tocar. Medido con un monstruo del banco: esfera de r=0.45 sobre
	# una cápsula de r=0.52 centrada en el eje — `hit_test` daba cabeza 0/1 a las
	# tres distancias, o sea headshots que nunca podían ocurrir.
	#
	# Si no llega arriba, se deja `head_hit_radius` en 0 y la detección cae a la
	# banda de altura (HEADSHOT_HEIGHT_FRACTION): menos precisa, pero alcanzable —
	# apuntarle a la cabeza visible funciona.
	var cuerpo := body_aabb(e, inst)
	if cuerpo.size.y > 0.01 and centro.y + radio < cuerpo.end.y * 0.8:
		if not _warned_head.has(e.enemy_type):
			_warned_head[e.enemy_type] = true
			push_warning("%s: el hueso \"head\" no llega a la parte alta del cuerpo; el headshot usa la banda de altura" % e.enemy_type)
		return

	e.head_center = centro
	e.head_hit_radius = radio

## AABB del CUERPO (todo lo visible menos el equipamiento del pack), en el espacio
## local del enemigo.
static func body_aabb(e: Enemy, inst: Node3D) -> AABB:
	return mesh_aabb(e, inst, [], EQUIPMENT_KEYWORDS)

## AABB de las mallas visibles cuyo nombre contiene alguna palabra de `include`
## (vacío = todas) y ninguna de `exclude`.
static func mesh_aabb(e: Enemy, inst: Node3D, include: Array, exclude: Array = []) -> AABB:
	var box := AABB()
	var first := true
	var to_local: Transform3D = e.global_transform.affine_inverse()
	for m in all_mesh_nodes(inst):
		var n: String = m.name.to_lower()
		if not include.is_empty() and not name_matches(n, include):
			continue
		if not exclude.is_empty() and name_matches(n, exclude):
			continue
		var a: AABB = (to_local * m.global_transform) * m.mesh.get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return box

static func name_matches(lower_name: String, keywords: Array) -> bool:
	for k in keywords:
		if lower_name.contains(k):
			return true
	return false

## Recorre el árbol y junta las mallas VISIBLES. Lo usa también `enemy.gd` para el
## corte de dibujado por distancia, que tiene que alcanzar tanto al modelo
## importado como al procedural.
static func all_mesh_nodes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and node.mesh and node.is_visible_in_tree():
		out.append(node)
	for c in node.get_children():
		out.append_array(all_mesh_nodes(c))
	return out

static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var s := find_skeleton(c)
		if s:
			return s
	return null

static func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := find_animation_player(child)
		if found:
			return found
	return null
