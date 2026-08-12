extends CharacterBody3D
## Enemigo unificado: 8 tipos (sección 6) + variante alpha, seleccionados por `enemy_type`.
## Las stats base vienen de GameData.ENEMY_STATS; el comportamiento se resuelve por tipo
## en _physics_process (match). No hay 8 scripts separados a propósito: es más fácil de
## mantener a mano sin editor gráfico abierto.

@export var enemy_type: String = "hollow"
@export var is_alpha: bool = false

const GRAVITY := 20.0
const SEPARATION_FORCE := 6.0
## Sólo se usa como último recurso, para modelos procedurales sin cabeza medible.
## Los modelos importados usan una ESFERA ajustada a la cabeza real (ver _fit_head).
const HEADSHOT_HEIGHT_FRACTION := 0.85
const FLYING_MIN_ALTITUDE := 1.5
## Por debajo de esto el enemigo se cayó del mapa y se descarta.
const FALL_KILL_Y := -20.0
## Lado de la celda de la grilla de separación. Tiene que ser mayor que la suma
## de los dos radios más grandes que puedan tocarse (dos Knight alpha: 1.43+1.43
## = 2.85), porque sólo se mira el vecindario de 3x3 celdas.
const SEP_CELL := 3.0
## Un enemigo detrás de la cámara no se ve, así que no se anima ni se lo hace
## girar. Se usa producto punto y no el frustum a propósito: el frustum recorta
## justo en el borde de la pantalla y se notaría al mover el mouse; esto sólo
## saltea lo que está claramente a la espalda.
const BEHIND_CAMERA_DOT := -0.2

## Frecuencia de animación por distancia. Medido con `tools/perf.tscn`: mover los
## rigs eran **55 de los 70 ms** de `_process` con 200 enemigos — el 78% del
## costo de CPU del juego. Los `AnimationPlayer` pasan a modo MANUAL y este
## script los avanza sólo cuando les toca: los de cerca todos los frames, los del
## medio uno de cada dos, los lejanos uno de cada tres. A esas distancias, y con
## personajes de este tamaño, la diferencia no se ve.
## El tramo "todos los frames" es CHICO a propósito: en una turba, casi todos los
## enemigos terminan encima del jugador, así que un umbral generoso (8 m) dejaba
## a casi todos en velocidad completa y no ahorraba nada — medido, 70 → 56 ms.
## Con 5 m entran unos 40 como mucho (la separación los mantiene a ~1 m entre sí)
## y el resto anima a 30, 20 o 15 fps, que a esa distancia no se distingue.
const ANIM_NEAR_DIST := 5.0
const ANIM_MID_DIST := 12.0
const ANIM_FAR_DIST := 22.0
const ANIM_STRIDE_MID := 2
const ANIM_STRIDE_FAR := 3
const ANIM_STRIDE_VERY_FAR := 4

## PRESUPUESTO de animación. Los tramos por distancia solos no alcanzaban: en una
## turba todos terminan cerca, así que el costo seguía creciendo con la cantidad
## de enemigos. Con esto se ordenan por cercanía y sólo los primeros animan a
## velocidad completa — el costo queda ACOTADO, den 50 enemigos o 300.
const ANIM_BUDGET_FULL := 24    # estos animan todos los frames
const ANIM_BUDGET_HALF := 64    # estos, uno de cada dos

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

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var aura: MeshInstance3D = $Aura

var model_root: Node3D
var _anim_l_arm: Node3D
var _anim_r_arm: Node3D
var _anim_l_leg: Node3D
var _anim_r_leg: Node3D
var _anim_l_leg2: Node3D  # pata trasera (Capra, cuadrúpedo)
var _anim_r_leg2: Node3D
var _anim_l_wing: Node3D
var _anim_r_wing: Node3D
var _anim_head: Node3D
var _anim_jaw: Node3D
var _anim_tail: Node3D
var bob_phase := 0.0

## Modelos KayKit: AnimationPlayer del rig importado (null si este tipo usa el
## modelo procedural). `current_anim_locked` marca una animación de una sola
## pasada (ataque/golpe) que no debe interrumpirse por la de locomoción.
var anim_player: AnimationPlayer = null
var current_anim_locked := false
## Tiempo acumulado desde el último avance de animación, y desfasaje para que no
## todos los enemigos actualicen en el mismo frame (si no, cada 3 frames habría
## un pico que se sentiría como tirón).
var _anim_accum := 0.0
var _anim_phase := 0

var max_health := 100.0
var health := 100.0
var speed := 3.8
var damage := 10.0
var atk_cd := 1.0
var xp_reward := 5
var regen_reward := 2.0
var body_radius := 0.5
var body_height := 2.3
var head_radius := 0.3
var flying := false

var attack_timer := 0.0
var player: Node3D = null
var dead := false

# --- estado específico por tipo ---
var weave_seed := 0.0
var wobble_seed := Vector3.ZERO
var knight_dash_timer := 0.0
var knight_dash_velocity := Vector3.ZERO
var knight_grab_cooldown := 0.0
var thrown := false
var thrown_velocity := Vector3.ZERO
var thrown_timer := 0.0

var capra_state := "frozen"  # frozen | charge | jump | landed
var capra_jump_cooldown := 0.0
var capra_landed_timer := 0.0
var capra_jump_velocity := Vector3.ZERO

var orbit_dir := 1.0
var orbit_angle := 0.0
var orbit_radius := 25.0
var skull_timer := 0.0

var counts_for_wave := true

## Esfera de cabeza en espacio LOCAL del enemigo, medida del modelo real en
## _fit_head. `head_hit_radius == 0` significa "no se pudo medir" y se cae a la
## banda de altura de HEADSHOT_HEIGHT_FRACTION.
## Distancia al jugador y "está a mi espalda", calculados UNA vez por frame de
## física en `_physics_process` y reusados por todo lo demás. Antes cada sistema
## los recalculaba por su cuenta.
var dist_to_player_sq := 0.0
## Dentro del alcance de dibujado, mire para donde mire el jugador.
var near_player := true
## Además, delante de la cámara. Más restrictivo que `near_player`.
var visible_to_player := true

var head_center := Vector3.ZERO
var head_hit_radius := 0.0
## Además de caer dentro de la esfera, el impacto tiene que estar POR ENCIMA del
## torso. Hace falta porque en estos modelos chibi la malla de la cabeza baja
## hasta el cuello y se superpone con el pecho: sin este piso, un tiro al pecho
## de la Capra contaba como headshot (o sea, instakill).
var head_floor_y := -INF

signal died(pos: Vector3, from_dir: Vector3, is_headshot: bool)

func _ready() -> void:
	add_to_group("enemy")
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

	var stats: Dictionary = GameData.ENEMY_STATS.get(enemy_type, GameData.ENEMY_STATS["hollow"])
	max_health = stats["hp"]
	speed = stats["speed"]
	damage = stats["damage"]
	atk_cd = stats["atk_cd"]
	xp_reward = stats["xp"]
	regen_reward = stats["regen"]
	body_radius = stats["radius"]
	body_height = stats["height"]
	head_radius = stats["head_radius"]
	flying = stats["flying"]

	# Compensación de la oleada: se recortó la CANTIDAD de enemigos para no
	# saturar la máquina, y lo que se perdió vuelve como vida/velocidad/daño.
	# Se lee de GameState y no se recibe por parámetro a propósito: así lo
	# heredan también los cráneos que invoca la Sorceress y los murciélagos que
	# escupe el Blood Lord, sin tocar esos dos caminos de spawn.
	max_health *= GameState.wave_hp_mult
	speed *= GameState.wave_speed_mult
	damage *= GameState.wave_damage_mult

	if is_alpha:
		max_health *= GameData.ALPHA_HP_MULT
		damage *= GameData.ALPHA_DAMAGE_MULT
		body_radius *= GameData.ALPHA_RADIUS_MULT
		body_height *= GameData.ALPHA_HEIGHT_MULT
		head_radius *= GameData.ALPHA_HEAD_MULT
		xp_reward = int(xp_reward * GameData.ALPHA_XP_MULT)
		regen_reward = GameData.ALPHA_REGEN
		aura.visible = true
		# El aura es una esfera fija de 0.9 en la escena; se escala por nodo (no
		# tocando la malla) porque el mesh es un sub-recurso COMPARTIDO entre
		# todas las instancias — ver §3 del CLAUDE.md.
		aura.scale = Vector3.ONE * maxf(body_height / 2.3, 0.35)
	else:
		aura.visible = false

	health = max_health
	_apply_collision()
	_build_model()

	weave_seed = randf_range(0.0, TAU)
	wobble_seed = Vector3(randf_range(0.0, TAU), randf_range(0.0, TAU), randf_range(0.0, TAU))
	knight_dash_timer = randf_range(3.0, 5.0)
	knight_grab_cooldown = randf_range(0.0, 2.0)
	capra_jump_cooldown = randf_range(3.5, 5.5)
	orbit_dir = 1.0 if randf() < 0.5 else -1.0
	skull_timer = randf_range(3.0, 4.5)

## Cápsula base según la tabla de GameData. Para los tipos con modelo importado
## la vuelve a ajustar _fit_collision() con las medidas del modelo real.
## El orden importa: si se asigna un radius mayor que height/2, Godot estira la
## height sola. Height primero, radius recortado después.
func _apply_collision() -> void:
	var shape := CapsuleShape3D.new()
	shape.height = maxf(body_height, 0.1)
	shape.radius = minf(body_radius, shape.height * 0.5)
	collision_shape.shape = shape
	body_radius = shape.radius

# ---------------------------------------------------------------------------
# Modelos — piezas simples (cajas/cápsulas/conos) armadas por código, una
# silueta reconocible por tipo en vez de una cápsula genérica. No es un port
# de la geometría procedural de FaverMass (esa vive en renderer.cpp, sombreada
# a mano en CPU porque raylib no emite normales para primitivas — acá Godot
# ilumina de verdad, no hace falta ese workaround), es una traducción liviana
# del mismo plan corporal por tipo.
# ---------------------------------------------------------------------------

func _color() -> Color:
	return GameData.ENEMY_COLOR.get(enemy_type, Color(0.5, 0.1, 0.1))

## Materiales PBR compartidos por (color, tipo-de-superficie) — se cachean para
## no crear un StandardMaterial3D nuevo por cada pieza de cada enemigo (una
## oleada 25 con 100+ enemigos de ~20 piezas cada uno serían miles de
## materiales únicos, y cada material único es un draw call que no se batchea).
static var _mat_cache: Dictionary = {}

enum Surf { FLESH, BONE, METAL, CLOTH, HORN }

func _surface_material(color: Color, surf: int) -> StandardMaterial3D:
	var key := "%s_%d" % [color.to_html(), surf]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	match surf:
		Surf.FLESH:
			mat.roughness = 0.62
			mat.metallic = 0.0
			mat.metallic_specular = 0.42
			mat.clearcoat_enabled = true
			mat.clearcoat = 0.25
			mat.clearcoat_roughness = 0.55
			mat.rim_enabled = true
			mat.rim = 0.35
			mat.rim_tint = 0.4
		Surf.BONE:
			mat.roughness = 0.45
			mat.metallic = 0.0
			mat.metallic_specular = 0.55
		Surf.METAL:
			mat.roughness = 0.34
			mat.metallic = 0.92
			mat.metallic_specular = 0.85
		Surf.CLOTH:
			mat.roughness = 0.95
			mat.metallic = 0.0
			mat.metallic_specular = 0.12
			mat.rim_enabled = true
			mat.rim = 0.5
			mat.rim_tint = 0.7
		Surf.HORN:
			mat.roughness = 0.38
			mat.metallic = 0.15
			mat.metallic_specular = 0.6
	_mat_cache[key] = mat
	return mat

func _part(mesh: Mesh, pos: Vector3, color: Color, rot_deg: Vector3, parent: Node3D, surf: int = Surf.FLESH) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, _surface_material(color, surf))
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

func _box(size: Vector3, pos: Vector3, color: Color, parent: Node3D, rot_deg: Vector3 = Vector3.ZERO, surf: int = Surf.FLESH) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	# subdividir da vértices para que SSAO/SSIL y las luces tengan dónde variar
	m.subdivide_width = 2
	m.subdivide_height = 2
	m.subdivide_depth = 2
	return _part(m, pos, color, rot_deg, parent, surf)

func _sphere(radius: float, pos: Vector3, color: Color, parent: Node3D, surf: int = Surf.FLESH) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 32
	m.rings = 16
	return _part(m, pos, color, Vector3.ZERO, parent, surf)

func _limb(radius: float, length: float, pos: Vector3, color: Color, parent: Node3D, rot_deg: Vector3 = Vector3.ZERO, surf: int = Surf.FLESH) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = max(length, radius * 2.0 + 0.01)
	m.radial_segments = 24
	m.rings = 8
	return _part(m, pos, color, rot_deg, parent, surf)

func _cone(radius: float, height: float, pos: Vector3, color: Color, parent: Node3D, rot_deg: Vector3 = Vector3.ZERO, surf: int = Surf.HORN) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 20
	m.rings = 4
	return _part(m, pos, color, rot_deg, parent, surf)

func _pivot(pos: Vector3, parent: Node3D) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p


func _build_model() -> void:
	model_root = Node3D.new()
	model_root.name = "Model"
	add_child(model_root)

	# Modelo importado (CC0) si existe uno para este tipo; si no, se cae al modelo
	# procedural de piezas primitivas. El importado se alinea solo contra la
	# colisión (ver _build_imported_model); el procedural no, así que hay que
	# bajarlo a mano: sus piezas se ubican asumiendo Y=0 -> pies, pero el origen
	# del CharacterBody3D es el CENTRO de la cápsula.
	var model_path := "res://assets/enemies/%s.glb" % enemy_type
	if ResourceLoader.exists(model_path):
		_build_imported_model(model_path)
		_apply_render_cull()
		return

	model_root.position.y = -body_height * 0.5
	var col := _color()
	match enemy_type:
		"hollow":
			_build_humanoid(col, 0.0, false)
		"thrall":
			_build_humanoid(col, 14.0, false)
		"blood_lord":
			_build_humanoid(col, 0.0, true)
		"knight":
			_build_knight(col)
		"dire_bat":
			_build_bat(col)
		"capra":
			_build_capra(col)
		"sorceress":
			_build_witch(col)
		"demon_skull":
			_build_skull(col)
		_:
			_build_humanoid(col, 0.0, false)
	_apply_render_cull()

## Corte de dibujado por distancia. Lo resuelve el RenderingServer, no GDScript:
## cero costo por frame. Corte SECO y no fundido — el fundido obliga a tratar el
## material como transparente durante la transición, y acá no hace falta: a esa
## distancia la pared de niebla ya es opaca, así que no se ve nada aparecer ni
## desaparecer. Va después del injerto de cabeza para alcanzarlo también.
func _apply_render_cull() -> void:
	for m in _all_mesh_nodes(self):
		m.visibility_range_end = GameData.ENEMY_LOD_DISTANCE
		m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

func _build_imported_model(path: String) -> void:
	var scene: PackedScene = load(path)
	if not scene:
		return
	var inst: Node3D = scene.instantiate()
	# Los modelos miran hacia +Z, pero `look_at()` orienta el -Z del nodo hacia el
	# objetivo. Sin este giro de 180° los enemigos caminan hacia el jugador
	# dándole la espalda.
	inst.rotation_degrees.y = 180.0
	model_root.add_child(inst)
	_hide_extra_equipment(inst)
	_swap_head(inst)

	# 1) ESCALA. Se mide el alto real del cuerpo, no una constante fija: los packs
	#    vienen en tamaños muy distintos (KayKit 2.17-2.63, los monstruos de
	#    Quaternius 1.68-3.10). Así cada enemigo respeta su `height` de GameData.
	var box := _body_aabb(inst)
	if box.size.y > 0.01:
		var s := body_height / box.size.y
		inst.scale = Vector3(s, s, s)
		box = _body_aabb(inst)

	# 2) ALINEACIÓN. El origen del CharacterBody3D es el centro de la forma de
	#    colisión, así que el centro del cuerpo VISIBLE tiene que caer ahí. No
	#    alcanza con bajar medio cuerpo asumiendo que el modelo tiene el origen en
	#    los pies: cada artista lo pone donde quiere. Medido: el Dire Bat volaba
	#    0.37 m por encima de su propia cápsula (que mide 0.55 de alto) — se le
	#    disparaba al bicho y se le pegaba al aire.
	if box.size != Vector3.ZERO:
		inst.position -= box.get_center()
		box.position -= box.get_center()
		_fit_collision(box)
	_fit_head(inst)

	anim_player = _find_animation_player(inst)
	if anim_player:
		# MANUAL: el mixer deja de avanzar solo. Lo avanza `_process` cuando le
		# toca según la distancia (ver ANIM_STRIDE_*). Es de lejos el ahorro más
		# grande que tiene el juego.
		anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_anim_phase = randi() % (ANIM_STRIDE_VERY_FAR * ANIM_STRIDE_FAR)
		_play_anim(ANIM_IDLE)

## Deja una sola pieza de equipamiento por tipo (ver EQUIPMENT_KEEP) y oculta el
## resto del arsenal que el GLB trae montado en las manos.
## Va ANTES de medir el cuerpo: _all_mesh_nodes() filtra por visibilidad, así que
## lo que se oculte acá ya no cuenta para nada. Lo que se deja tampoco engorda la
## hitbox — _body_aabb() descarta el equipamiento por nombre, esté visible o no.
func _hide_extra_equipment(inst: Node3D) -> void:
	var keep: Array = EQUIPMENT_KEEP.get(enemy_type, [])
	for m in _all_mesh_nodes(inst):
		var n: String = m.name.to_lower()
		if not _name_matches(n, EQUIPMENT_KEYWORDS):
			continue
		m.visible = false
		for k in keep:
			if n == String(k).to_lower():
				m.visible = true
				break

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
## Piezas del injerto ya resueltas, por tipo de enemigo: malla + transformada
## RELATIVA al hueso del cuello. Se cachea porque armarlo obliga a instanciar el
## GLB donante entero (4.8 MB y 90+ animaciones) sólo para medirle la cabeza —
## hacerlo en cada spawn era un tirón garantizado con varios Knights por oleada.
## La transformada es la misma para todas las instancias de un tipo: al momento
## del injerto el rig está en pose de reposo, igual en todas.
static var _head_graft_cache: Dictionary = {}

func _swap_head(inst: Node3D) -> void:
	var donor_path: String = HEAD_SWAP.get(enemy_type, "")
	if donor_path == "" or not ResourceLoader.exists(donor_path):
		return
	var sk := _find_skeleton(inst)
	if not sk:
		return
	var head_bone := _find_bone_index(sk, "head")
	if head_bone < 0:
		return

	if not _head_graft_cache.has(enemy_type):
		_head_graft_cache[enemy_type] = _resolve_head_graft(inst, sk, head_bone, donor_path)
	var parts: Array = _head_graft_cache[enemy_type]
	if parts.is_empty():
		return

	# La cabeza vieja se OCULTA, no se borra: sacando la entrada de HEAD_SWAP
	# vuelve sola.
	for m in _all_mesh_nodes(inst):
		if _name_matches(m.name.to_lower(), HEAD_KEYWORDS):
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
func _resolve_head_graft(inst: Node3D, sk: Skeleton3D, head_bone: int, donor_path: String) -> Array:
	# Se mide la cabeza original ANTES de taparla: es el molde al que se ajusta la
	# nueva, así el trasplante funciona entre cualquier par de modelos.
	var own_head := _mesh_aabb(inst, HEAD_KEYWORDS)
	if own_head.size.y < 0.001:
		return []
	var donor: Node3D = load(donor_path).instantiate()
	# El MISMO giro de 180° que se le da al modelo receptor. Sin esto el donante
	# queda mirando al revés que el cuerpo, y como el ajuste de abajo sólo escala
	# y traslada (no rota), la calavera terminaba puesta de espaldas.
	donor.rotation_degrees.y = 180.0
	model_root.add_child(donor)
	var donor_head := _mesh_aabb(donor, HEAD_KEYWORDS)
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
	var to_local: Transform3D = global_transform.affine_inverse()

	var parts: Array = []
	for dm in _all_mesh_nodes(donor):
		if not _name_matches(dm.name.to_lower(), HEAD_KEYWORDS):
			continue
		var mats: Array = []
		for s in dm.mesh.get_surface_count():
			mats.append(dm.get_surface_override_material(s))
		parts.append({
			"name": dm.name,
			"mesh": dm.mesh,
			"mats": mats,
			"xform": to_attach * global_transform * place * (to_local * dm.global_transform),
		})
	donor.visible = false
	donor.queue_free()
	return parts

func _find_bone_index(sk: Skeleton3D, bone_name: String) -> int:
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).to_lower() == bone_name:
			return i
	return -1

## Ajusta la forma de colisión al volumen que el jugador realmente ve.
func _fit_collision(box: AABB) -> void:
	body_height = box.size.y
	if box.size.x > box.size.y * WIDE_RATIO:
		# Bicho ancho y chato (murciélago, cráneo volador): esfera.
		var sph := SphereShape3D.new()
		sph.radius = 0.5 * maxf(maxf(box.size.y, box.size.z), box.size.x * WIDE_SPAN_FACTOR)
		collision_shape.shape = sph
		body_radius = sph.radius
		return
	# Humanoide: se conserva el radio de la tabla (está afinado contra el torso,
	# verificado modelo por modelo) y sólo se corrige la altura contra el modelo.
	# El ancho del AABB no sirve como radio: los rigs se miden en pose de reposo,
	# con los brazos en cruz — el Hollow "mide" 2.10 de ancho por los brazos.
	var cap := CapsuleShape3D.new()
	cap.height = maxf(box.size.y, 0.1)
	cap.radius = minf(body_radius, cap.height * 0.5)
	collision_shape.shape = cap
	body_radius = cap.radius

## Esfera de headshot ajustada a la cabeza real del modelo. Se prueba primero por
## nombre de malla (KayKit los nombra: *_Head, *_Helmet, *_Skull...) y si el pack
## no los nombra así, por el hueso "head" del rig.
func _fit_head(inst: Node3D) -> void:
	var box := _mesh_aabb(inst, HEAD_KEYWORDS)
	if box.size != Vector3.ZERO:
		head_center = box.get_center()
		head_hit_radius = 0.5 * maxf(box.size.x, maxf(box.size.y, box.size.z)) * HEAD_HITBOX_MULT
		# Techo del torso = frontera real cabeza/cuerpo de ESTE modelo. Si no hay
		# torso (el Demon Skull es una calavera y nada más), no hay piso: todo el
		# bicho es cabeza, que es exactamente lo que se ve.
		var torso := _mesh_aabb(inst, [], EQUIPMENT_KEYWORDS + HEAD_KEYWORDS)
		if torso.size != Vector3.ZERO:
			head_floor_y = torso.end.y
		return
	var sk := _find_skeleton(inst)
	if not sk:
		return
	var idx := _find_bone_index(sk, "head")
	if idx < 0:
		return
	var to_local: Transform3D = global_transform.affine_inverse()
	head_center = (to_local * sk.global_transform * sk.get_bone_global_pose(idx)).origin
	head_hit_radius = head_radius * 1.5 * HEAD_HITBOX_MULT

## AABB del CUERPO (todo lo visible menos el equipamiento del pack), en el espacio
## local de este enemigo.
func _body_aabb(inst: Node3D) -> AABB:
	return _mesh_aabb(inst, [], EQUIPMENT_KEYWORDS)

## AABB de las mallas visibles cuyo nombre contiene alguna palabra de `include`
## (vacío = todas) y ninguna de `exclude`.
func _mesh_aabb(inst: Node3D, include: Array, exclude: Array = []) -> AABB:
	var box := AABB()
	var first := true
	var to_local: Transform3D = global_transform.affine_inverse()
	for m in _all_mesh_nodes(inst):
		var n: String = m.name.to_lower()
		if not include.is_empty() and not _name_matches(n, include):
			continue
		if not exclude.is_empty() and _name_matches(n, exclude):
			continue
		var a: AABB = (to_local * m.global_transform) * m.mesh.get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return box

func _name_matches(lower_name: String, keywords: Array) -> bool:
	for k in keywords:
		if lower_name.contains(k):
			return true
	return false

func _all_mesh_nodes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and node.mesh and node.is_visible_in_tree():
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_mesh_nodes(c))
	return out

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null

# --- reproducción de animaciones -------------------------------------------
# Se prueban en orden y se usa la primera que exista, así un modelo al que le
# falte una animación puntual no rompe.
#
# Conviven DOS convenciones de nombres porque los enemigos salen de dos packs:
#   - KayKit (humanoides):   "Idle", "Running_A", "Death_A"...
#   - Quaternius (monstruos): "CharacterArmature|Flying_Idle", "...|Death"...
# Al agregar un pack nuevo, correr `tools/inspect_models.tscn` para ver los
# nombres reales y sumarlos acá.

const ANIM_IDLE := [
	"Idle", "Idle_B",
	"CharacterArmature|Flying_Idle",
]
const ANIM_RUN := [
	"Running_A", "Running_B", "Running_C",
	"CharacterArmature|Fast_Flying",
]
const ANIM_ATTACK := [
	"1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Diagonal", "2H_Melee_Attack_Chop", "Unarmed_Melee_Attack_Punch_A",
	"CharacterArmature|Headbutt", "CharacterArmature|Punch",
]
const ANIM_DEATH := [
	"Death_A", "Death_B", "Death_C_Skeletons",
	"CharacterArmature|Death",
]
const ANIM_HIT := [
	"Hit_A", "Hit_B",
	"CharacterArmature|HitReact",
]

## Qué animación existe de verdad para cada (tipo, lista de candidatos). Se
## cachea porque `_play_anim` se llama TODOS los frames por enemigo, y recorrer
## la lista preguntando `has_animation()` cada vez son cientos de búsquedas por
## frame que siempre dan el mismo resultado.
static var _anim_name_cache: Dictionary = {}

## Ranking de cercanía al jugador, reconstruido UNA vez por frame y compartido.
## Mismo patrón que la grilla de separación: guarda con el número de frame.
static var _anim_rank: Dictionary = {}
static var _anim_rank_frame := -1

func _rebuild_anim_ranks() -> void:
	var f := Engine.get_process_frames()
	if _anim_rank_frame == f:
		return  # ya lo armó otro enemigo en este mismo frame
	_anim_rank_frame = f
	var visibles: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e.dead and e.visible_to_player and e.anim_player:
			visibles.append(e)
	visibles.sort_custom(func(a, b): return a.dist_to_player_sq < b.dist_to_player_sq)
	_anim_rank.clear()
	for i in visibles.size():
		_anim_rank[visibles[i].get_instance_id()] = i

func _play_anim(candidates: Array, loop: bool = true, speed: float = 1.0) -> bool:
	if not anim_player:
		return false
	var key := "%s|%s" % [enemy_type, candidates[0]]
	var anim_name: String = _anim_name_cache.get(key, "")
	if not _anim_name_cache.has(key):
		for n in candidates:
			if anim_player.has_animation(n):
				anim_name = n
				break
		_anim_name_cache[key] = anim_name
	if anim_name == "":
		return false
	if anim_player.current_animation == anim_name:
		return true
	var anim := anim_player.get_animation(anim_name)
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	anim_player.speed_scale = speed
	anim_player.play(anim_name)
	current_anim_locked = not loop
	return true

func _build_humanoid(col: Color, lean_deg: float, caped: bool) -> void:
	var H := body_height
	var W := body_radius
	var HR := head_radius
	var dark := col.darkened(0.25)
	var bone := Color(0.75, 0.7, 0.6)

	model_root.rotation_degrees.x = -lean_deg

	# piernas
	_anim_l_leg = _pivot(Vector3(-W * 0.32, H * 0.46, 0.0), model_root)
	_limb(W * 0.11, H * 0.46, Vector3(0.0, -H * 0.23, 0.0), dark, _anim_l_leg)
	_anim_r_leg = _pivot(Vector3(W * 0.32, H * 0.46, 0.0), model_root)
	_limb(W * 0.11, H * 0.46, Vector3(0.0, -H * 0.23, 0.0), dark, _anim_r_leg)

	# torso
	_limb(W * 0.34, H * 0.42, Vector3(0.0, H * 0.72, 0.0), col, model_root)

	# costillas expuestas — piel estirada sobre el hueso (Hollow/Thrall gaunt; el
	# vampiro las tapa con la capa, no hacen falta ahí)
	if not caped:
		for i in 3:
			var ry := H * (0.62 + i * 0.075)
			_box(Vector3(W * 0.5, H * 0.03, W * 0.08), Vector3(0.0, ry, W * 0.16), bone, model_root, Vector3.ZERO, Surf.BONE)

	# brazos (siempre un poco extendidos hacia adelante — la pose "reaching" del Hollow)
	_anim_l_arm = _pivot(Vector3(-W * 0.42, H * 0.86, 0.0), model_root)
	_limb(W * 0.09, H * 0.40, Vector3(0.0, -H * 0.20, W * 0.05), col, _anim_l_arm, Vector3(60, 0, 0))
	_anim_r_arm = _pivot(Vector3(W * 0.42, H * 0.86, 0.0), model_root)
	_limb(W * 0.09, H * 0.40, Vector3(0.0, -H * 0.20, W * 0.05), col, _anim_r_arm, Vector3(60, 0, 0))

	# cabeza
	_anim_head = _pivot(Vector3(0.0, H * 0.97, 0.0), model_root)
	_sphere(HR, Vector3.ZERO, col, _anim_head)
	_sphere(HR * 0.28, Vector3(-HR * 0.5, HR * 0.1, HR * 0.85), Color(0.02, 0.02, 0.02), _anim_head)
	_sphere(HR * 0.28, Vector3(HR * 0.5, HR * 0.1, HR * 0.85), Color(0.02, 0.02, 0.02), _anim_head)

	# mandíbula colgando, se abre y cierra (ver _process)
	_anim_jaw = _pivot(Vector3(0.0, -HR * 0.35, HR * 0.55), _anim_head)
	_box(Vector3(HR * 0.7, HR * 0.22, HR * 0.5), Vector3(0.0, -HR * 0.1, HR * 0.15), dark, _anim_jaw)

	if caped:
		# capa: varios paneles angulados en vez de una sola placa plana, más
		# collar — el vampiro banca (roll) todo el cuerpo al caminar (_process)
		var cape_col := dark.darkened(0.3)
		for i in 3:
			var a := float(i - 1) * 12.0
			_box(Vector3(W * 0.55, H * 0.6, 0.05), Vector3(sin(deg_to_rad(a)) * W * 0.3, H * 0.6, -W * 0.32), cape_col, model_root, Vector3(0.0, a, 0.0), Surf.CLOTH)
		_box(Vector3(W * 0.5, H * 0.08, W * 0.2), Vector3(0.0, H * 0.9, -W * 0.15), cape_col, model_root, Vector3.ZERO, Surf.CLOTH)

func _build_knight(col: Color) -> void:
	var H := body_height
	var W := body_radius
	var HR := head_radius
	var metal := Color(0.35, 0.36, 0.4)
	var rust := Color(0.4, 0.18, 0.08)
	var dark_metal := Color(0.12, 0.12, 0.14)

	_anim_l_leg = _pivot(Vector3(-W * 0.34, H * 0.42, 0.0), model_root)
	_limb(W * 0.16, H * 0.42, Vector3(0.0, -H * 0.21, 0.0), metal, _anim_l_leg, Vector3.ZERO, Surf.METAL)
	_anim_r_leg = _pivot(Vector3(W * 0.34, H * 0.42, 0.0), model_root)
	_limb(W * 0.16, H * 0.42, Vector3(0.0, -H * 0.21, 0.0), metal, _anim_r_leg, Vector3.ZERO, Surf.METAL)

	# falda de malla: anillo de placas chicas colgando de la cintura
	for i in 10:
		var a := TAU * float(i) / 10.0
		_box(Vector3(W * 0.12, W * 0.22, W * 0.06), Vector3(cos(a) * W * 0.4, H * 0.42, sin(a) * W * 0.4), dark_metal, model_root, Vector3(0.0, -rad_to_deg(a), 0.0), Surf.METAL)

	_box(Vector3(W * 0.9, H * 0.5, W * 0.55), Vector3(0.0, H * 0.68, 0.0), col, model_root)
	_box(Vector3(W * 0.2, H * 0.22, W * 0.12), Vector3(0.0, H * 0.86, W * 0.28), rust, model_root, Vector3.ZERO, Surf.METAL)

	# hombreras: placas apiladas + pincho
	for side in [-1.0, 1.0]:
		for l in 2:
			_box(Vector3(W * (0.3 - l * 0.04), H * 0.05, W * (0.32 - l * 0.03)), Vector3(side * W * (0.55 + l * 0.05), H * (0.88 - l * 0.05), 0.0), metal, model_root, Vector3(0.0, 0.0, side * (10.0 + l * 8.0)), Surf.METAL)
		_cone(W * 0.05, W * 0.2, Vector3(side * W * 0.62, H * 0.98, -W * 0.06), dark_metal, model_root, Vector3(-70.0, 0.0, side * 20.0), Surf.METAL)

	_anim_l_arm = _pivot(Vector3(-W * 0.55, H * 0.85, 0.0), model_root)
	_limb(W * 0.14, H * 0.4, Vector3(0.0, -H * 0.2, 0.0), col, _anim_l_arm)
	_anim_r_arm = _pivot(Vector3(W * 0.55, H * 0.85, 0.0), model_root)
	_limb(W * 0.14, H * 0.4, Vector3(0.0, -H * 0.2, 0.0), col, _anim_r_arm)

	_anim_head = _pivot(Vector3(0.0, H * 0.98, 0.0), model_root)
	_box(Vector3(HR * 1.7, HR * 1.9, HR * 1.7), Vector3.ZERO, metal, _anim_head, Vector3.ZERO, Surf.METAL)
	_box(Vector3(HR * 1.2, HR * 0.3, HR * 0.1), Vector3(0.0, 0.0, HR * 0.85), Color(0.03, 0.03, 0.03), _anim_head)
	var visor_glow := StandardMaterial3D.new()
	visor_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visor_glow.emission_enabled = true
	visor_glow.emission = Color(0.9, 0.15, 0.05)
	visor_glow.emission_energy_multiplier = 2.0
	visor_glow.albedo_color = Color(0.9, 0.2, 0.1)
	var visor_l := _sphere(HR * 0.1, Vector3(-HR * 0.35, 0.0, HR * 0.82), Color(0.9, 0.2, 0.1), _anim_head)
	visor_l.set_surface_override_material(0, visor_glow)
	var visor_r := _sphere(HR * 0.1, Vector3(HR * 0.35, 0.0, HR * 0.82), Color(0.9, 0.2, 0.1), _anim_head)
	visor_r.set_surface_override_material(0, visor_glow)

	# cuernos curvos hacia atrás
	for side in [-1.0, 1.0]:
		_limb(HR * 0.13, HR * 0.7, Vector3(side * HR * 0.55, HR * 1.2, -HR * 0.2), dark_metal, _anim_head, Vector3(-25.0, 0.0, side * 12.0), Surf.METAL)
		_cone(HR * 0.09, HR * 0.5, Vector3(side * HR * 0.75, HR * 1.75, -HR * 0.55), dark_metal, _anim_head, Vector3(-55.0, 0.0, side * 10.0), Surf.METAL)

func _build_bat(col: Color) -> void:
	var W := body_radius
	var H := body_height
	_sphere(W, Vector3(0.0, H * 0.5, 0.0), col, model_root)
	_anim_l_wing = _pivot(Vector3(-W * 0.6, H * 0.55, 0.0), model_root)
	_box(Vector3(W * 1.8, W * 0.06, W * 1.1), Vector3(-W * 0.85, 0.0, 0.0), col.darkened(0.35), _anim_l_wing)
	_anim_r_wing = _pivot(Vector3(W * 0.6, H * 0.55, 0.0), model_root)
	_box(Vector3(W * 1.8, W * 0.06, W * 1.1), Vector3(W * 0.85, 0.0, 0.0), col.darkened(0.35), _anim_r_wing)
	_cone(W * 0.22, W * 0.5, Vector3(-W * 0.35, H * 0.85, 0.0), col, model_root, Vector3(0, 0, 20))
	_cone(W * 0.22, W * 0.5, Vector3(W * 0.35, H * 0.85, 0.0), col, model_root, Vector3(0, 0, -20))

	# ojos brillantes + colmillos
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.9, 0.05, 0.05)
	eye_mat.emission_energy_multiplier = 2.5
	eye_mat.albedo_color = Color(0.9, 0.1, 0.1)
	for side in [-1.0, 1.0]:
		var eye := _sphere(W * 0.09, Vector3(side * W * 0.28, H * 0.58, W * 0.55), Color(0.9, 0.1, 0.1), model_root)
		eye.set_surface_override_material(0, eye_mat)
		_cone(W * 0.04, W * 0.18, Vector3(side * W * 0.12, H * 0.4, W * 0.58), Color(0.85, 0.8, 0.75), model_root, Vector3(180.0, 0.0, 0.0))

func _build_capra(col: Color) -> void:
	var H := body_height
	var W := body_radius
	var HR := head_radius
	var horn := Color(0.15, 0.1, 0.08)
	var dark := col.darkened(0.3)

	var torso := _box(Vector3(W * 1.7, W * 0.75, W * 0.85), Vector3(0.0, H * 0.42, 0.0), col, model_root)
	torso.rotation_degrees.x = -8.0

	# melena de púas a lo largo del lomo
	for i in 6:
		var u := float(i) / 5.0
		_cone(W * 0.07, W * 0.22, Vector3(0.0, H * 0.62 - u * H * 0.08, W * 0.55 - u * W * 1.1), dark, model_root, Vector3(70.0, 0.0, 0.0))

	var leg_y := H * 0.42 - W * 0.3
	_anim_l_leg = _pivot(Vector3(-W * 0.55, leg_y, W * 0.35), model_root)
	_limb(W * 0.11, H * 0.42, Vector3(0.0, -H * 0.2, 0.0), dark, _anim_l_leg)
	_anim_r_leg = _pivot(Vector3(W * 0.55, leg_y, W * 0.35), model_root)
	_limb(W * 0.11, H * 0.42, Vector3(0.0, -H * 0.2, 0.0), dark, _anim_r_leg)
	_anim_l_leg2 = _pivot(Vector3(-W * 0.5, leg_y, -W * 0.35), model_root)
	_limb(W * 0.11, H * 0.42, Vector3(0.0, -H * 0.2, 0.0), dark, _anim_l_leg2)
	_anim_r_leg2 = _pivot(Vector3(W * 0.5, leg_y, -W * 0.35), model_root)
	_limb(W * 0.11, H * 0.42, Vector3(0.0, -H * 0.2, 0.0), dark, _anim_r_leg2)

	# cola
	_anim_tail = _pivot(Vector3(0.0, H * 0.5, -W * 0.42), model_root)
	_limb(W * 0.06, W * 0.4, Vector3(0.0, 0.0, -W * 0.18), col, _anim_tail, Vector3(70.0, 0.0, 0.0))

	_anim_head = _pivot(Vector3(0.0, H * 0.62, W * 0.7), model_root)
	_sphere(HR, Vector3.ZERO, col, _anim_head)
	_cone(HR * 0.22, HR * 0.7, Vector3(-HR * 0.4, HR * 0.6, 0.0), horn, _anim_head, Vector3(-20, 0, 15))
	_cone(HR * 0.22, HR * 0.7, Vector3(HR * 0.4, HR * 0.6, 0.0), horn, _anim_head, Vector3(-20, 0, -15))
	# lengua colgando
	_box(Vector3(HR * 0.15, HR * 0.35, HR * 0.1), Vector3(0.0, -HR * 0.6, HR * 0.6), Color(0.5, 0.05, 0.1), _anim_head)

func _build_witch(col: Color) -> void:
	var H := body_height
	var W := body_radius
	var HR := head_radius
	var skin := Color(0.75, 0.68, 0.6)
	_cone(W * 0.85, H * 0.75, Vector3(0.0, H * 0.38, 0.0), col, model_root, Vector3(180, 0, 0))

	# escoba: vuela montada en ella
	_limb(W * 0.05, H * 0.9, Vector3(0.0, H * 0.3, 0.0), Color(0.35, 0.22, 0.11), model_root, Vector3(75.0, 0.0, 0.0))
	for i in 8:
		var a := TAU * float(i) / 8.0
		_limb(W * 0.015, W * 0.3, Vector3(cos(a) * W * 0.12, H * -0.08, sin(a) * W * 0.12 - W * 0.7), Color(0.55, 0.45, 0.2), model_root, Vector3(80.0, 0.0, 0.0))

	_anim_head = _pivot(Vector3(0.0, H * 0.85, 0.0), model_root)
	_sphere(HR, Vector3.ZERO, skin, _anim_head)
	_cone(HR * 0.2, HR * 0.5, Vector3(0.0, -HR * 0.1, HR * 0.85), skin, _anim_head, Vector3(90.0, 0.0, 0.0))

	# pelo lacio colgando
	for side in [-1.0, 1.0]:
		_limb(HR * 0.05, HR * 0.9, Vector3(side * HR * 0.7, -HR * 0.3, -HR * 0.2), Color(0.2, 0.18, 0.2), _anim_head, Vector3(15.0, 0.0, side * 8.0))

	# sombrero cónico
	_cone(HR * 1.15, HR * 1.4, Vector3(0.0, HR * 1.0, 0.0), col.darkened(0.3), _anim_head)

func _build_skull(col: Color) -> void:
	var HR := head_radius
	_anim_head = _pivot(Vector3.ZERO, model_root)
	_sphere(HR, Vector3.ZERO, col, _anim_head)

	# cuencas + brillo cian
	_sphere(HR * 0.32, Vector3(-HR * 0.4, HR * 0.15, HR * 0.75), Color(0.03, 0.03, 0.05), _anim_head)
	_sphere(HR * 0.32, Vector3(HR * 0.4, HR * 0.15, HR * 0.75), Color(0.03, 0.03, 0.05), _anim_head)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.2, 0.8, 1.0)
	eye_mat.emission_energy_multiplier = 3.0
	eye_mat.albedo_color = Color(0.2, 0.8, 1.0)
	for side in [-1.0, 1.0]:
		var eye := _sphere(HR * 0.14, Vector3(side * HR * 0.4, HR * 0.15, HR * 0.9), Color(0.2, 0.8, 1.0), _anim_head)
		eye.set_surface_override_material(0, eye_mat)

	# mandíbula fija de arriba (dientes)
	_box(Vector3(HR * 1.1, HR * 0.2, HR * 0.3), Vector3(0.0, -HR * 0.42, HR * 0.6), col.darkened(0.2), _anim_head)

	# mandíbula inferior, pivote propio — se abre y cierra en _process
	_anim_jaw = _pivot(Vector3(0.0, -HR * 0.58, HR * 0.55), _anim_head)
	_box(Vector3(HR * 0.95, HR * 0.22, HR * 0.32), Vector3(0.0, -HR * 0.08, HR * 0.1), col.darkened(0.3), _anim_jaw)

	# capucha violeta drapeada
	var hood_col := Color(0.28, 0.12, 0.32)
	_sphere(HR * 1.2, Vector3(0.0, HR * 0.55, -HR * 0.3), hood_col, _anim_head, Surf.CLOTH)
	for i in 4:
		var a := -0.9 + i * 0.6
		_box(Vector3(HR * 0.3, HR * 1.0, HR * 0.06), Vector3(sin(a) * HR * 0.9, -HR * 0.2, cos(a) * HR * 0.3 - HR * 0.5), hood_col, _anim_head, Vector3(0.0, rad_to_deg(a), 0.0), Surf.CLOTH)

func _process(delta: float) -> void:
	if dead or not model_root:
		return

	# Modelo KayKit: locomoción por animación real del rig, no por bamboleo de
	# pivotes. La velocidad de reproducción sigue la velocidad real del enemigo
	# para que no "patine" (pies moviéndose a distinto ritmo que el suelo).
	if anim_player:
		# Con el mixer en MANUAL, no avanzar es congelar la pose: gratis. Todo lo
		# que el jugador no ve —detrás de la niebla o a su espalda— no se anima.
		if player and is_instance_valid(player) and not visible_to_player:
			return
		_anim_accum += delta
		# Los de lejos se animan a menos frames por segundo. Ver ANIM_STRIDE_*.
		var stride := 1
		if dist_to_player_sq > ANIM_FAR_DIST * ANIM_FAR_DIST:
			stride = ANIM_STRIDE_VERY_FAR
		elif dist_to_player_sq > ANIM_MID_DIST * ANIM_MID_DIST:
			stride = ANIM_STRIDE_FAR
		elif dist_to_player_sq > ANIM_NEAR_DIST * ANIM_NEAR_DIST:
			stride = ANIM_STRIDE_MID
		# ...y encima el presupuesto, que es lo que impide que el costo escale.
		# Se toma el más restrictivo de los dos.
		_rebuild_anim_ranks()
		var rank: int = _anim_rank.get(get_instance_id(), 9999)
		if rank >= ANIM_BUDGET_HALF:
			stride = maxi(stride, ANIM_STRIDE_VERY_FAR)
		elif rank >= ANIM_BUDGET_FULL:
			stride = maxi(stride, ANIM_STRIDE_MID)
		if stride > 1 and (Engine.get_process_frames() + _anim_phase) % stride != 0:
			return
		anim_player.advance(_anim_accum)
		_anim_accum = 0.0
		if current_anim_locked and anim_player.is_playing():
			return
		current_anim_locked = false
		var speed_xz := Vector2(velocity.x, velocity.z).length()
		if speed_xz > 0.3:
			_play_anim(ANIM_RUN, true, clampf(speed_xz / 4.5, 0.6, 1.8))
		else:
			_play_anim(ANIM_IDLE, true, 1.0)
		return

	var moving := Vector2(velocity.x, velocity.z).length() > 0.3
	bob_phase += delta * (7.0 if moving else 2.0)
	var swing := 22.0 if moving else 4.0
	if _anim_l_leg:
		_anim_l_leg.rotation_degrees.x = sin(bob_phase) * swing
	if _anim_r_leg:
		_anim_r_leg.rotation_degrees.x = sin(bob_phase + PI) * swing
	if _anim_l_leg2:
		_anim_l_leg2.rotation_degrees.x = sin(bob_phase + PI) * swing
	if _anim_r_leg2:
		_anim_r_leg2.rotation_degrees.x = sin(bob_phase) * swing
	if _anim_l_arm:
		_anim_l_arm.rotation_degrees.x = sin(bob_phase + PI) * swing * 0.6
	if _anim_r_arm:
		_anim_r_arm.rotation_degrees.x = sin(bob_phase) * swing * 0.6
	if _anim_l_wing:
		_anim_l_wing.rotation_degrees.z = sin(bob_phase * 2.2) * 35.0
	if _anim_r_wing:
		_anim_r_wing.rotation_degrees.z = -sin(bob_phase * 2.2) * 35.0
	if _anim_head and (enemy_type == "sorceress" or enemy_type == "demon_skull"):
		_anim_head.rotation_degrees.y = sin(bob_phase * 0.8) * 30.0
	if _anim_jaw:
		# la mandíbula nunca se termina de cerrar del todo — siempre "masticando"
		_anim_jaw.rotation_degrees.x = 12.0 + (sin(bob_phase * 3.0) * 0.5 + 0.5) * 42.0
	if _anim_tail:
		_anim_tail.rotation_degrees.y = sin(bob_phase * 1.5) * 26.0
	if model_root and flying:
		model_root.position.y = sin(bob_phase * 1.6) * 0.15

	match enemy_type:
		"knight":
			# tambaleo de golem: hamaca lateral pesada al caminar
			model_root.rotation_degrees.z = sin(bob_phase * 0.6) * 6.5
		"blood_lord":
			# banca hacia los costados como un depredador acechando
			model_root.rotation_degrees.z = sin(bob_phase * 1.4) * 9.0
		"capra":
			if _anim_head:
				# cabeza girando errática, "como loco"
				_anim_head.rotation_degrees.y = sin(bob_phase * 3.5) * 24.0 + sin(bob_phase * 1.5) * 14.0

func _physics_process(delta: float) -> void:
	if dead:
		return
	if not player or not is_instance_valid(player):
		return

	# Red de seguridad: si algo lo sacó del mapa (el lanzamiento del Knight, un
	# empujón contra el borde) se descuenta y se va. Si no, `alive_count` lo sigue
	# contando vivo mientras cae para siempre y la oleada no termina nunca.
	if global_position.y < FALL_KILL_Y:
		dead = true
		died.emit(global_position, Vector3.UP, false)
		queue_free()
		return

	_update_visibility()
	# Girar a mirar al jugador es un `look_at` por enemigo por frame. Si no se lo
	# ve, no importa para dónde mire.
	if visible_to_player:
		_face_player()

	attack_timer -= delta

	if thrown:
		_process_thrown(delta)
		move_and_slide()
		return

	match enemy_type:
		"hollow", "thrall":
			_behavior_direct_chase(delta)
		"dire_bat":
			_behavior_flying_direct(delta)
		"blood_lord":
			_behavior_weave_chase(delta)
		"knight":
			_behavior_knight(delta)
		"capra":
			_behavior_capra(delta)
		"sorceress":
			_behavior_sorceress(delta)
		"demon_skull":
			_behavior_wobble_flight(delta)
		_:
			_behavior_direct_chase(delta)

	_resolve_separation(delta)

	if flying:
		global_position += velocity * delta
		if global_position.y < FLYING_MIN_ALTITUDE:
			global_position.y = FLYING_MIN_ALTITUDE
	elif near_player:
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		else:
			velocity.y = 0.0
		move_and_slide()
	else:
		# Lejos, del otro lado de la niebla: se integra la posición a mano en vez
		# de llamar a `move_and_slide()`. Los enemigos aparecen a 40-50 m y pasan
		# mucho tiempo caminando hacia el jugador; resolverles colisión contra el
		# mundo todo ese rato es carísimo y no se ve. Atraviesan obstáculos
		# mientras están en la niebla; al entrar en rango vuelve la física normal
		# y `move_and_slide()` los despenetra solo si quedaron dentro de algo.
		# El piso de la arena es plano, así que apoyarlos es fijar la altura.
		global_position.x += velocity.x * delta
		global_position.z += velocity.z * delta
		global_position.y = body_height * 0.5

## Distancia al jugador y visibilidad, una sola vez por frame. Todo lo que se
## saltea cuando `visible_to_player` es false (animar el rig, girar el modelo,
## separarse de los vecinos) es trabajo que nadie iba a ver.
func _update_visibility() -> void:
	dist_to_player_sq = global_position.distance_squared_to(player.global_position)
	var cull := GameData.ENEMY_LOD_DISTANCE
	near_player = dist_to_player_sq <= cull * cull
	if not near_player:
		visible_to_player = false
		return
	var cam: Camera3D = player.get_node_or_null("Camera3D")
	if not cam:
		visible_to_player = true
		return
	var to_self := global_position - cam.global_position
	visible_to_player = to_self.normalized().dot(-cam.global_transform.basis.z) > BEHIND_CAMERA_DOT

func _face_player() -> void:
	# El CharacterBody3D arranca sin rotación propia y nada la tocaba, así que
	# todos los enemigos quedaban mirando hacia el mismo eje del mundo sin
	# importar hacia dónde caminaban. Capra "congelado" es la única excepción
	# a propósito (inmóvil de verdad, estilo SCP-173, hasta que lo ven).
	if enemy_type == "capra" and capra_state == "frozen":
		return
	var look_target := Vector3(player.global_position.x, global_position.y, player.global_position.z)
	if look_target.distance_to(global_position) > 0.01:
		look_at(look_target, Vector3.UP)

# --- comportamientos ---

func _behavior_direct_chase(_delta: float) -> void:
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > body_radius + 1.0:
		var dir := to_player.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_try_melee_attack()

func _behavior_flying_direct(_delta: float) -> void:
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	if dist > body_radius + 1.0:
		velocity = to_player.normalized() * speed
	else:
		velocity = Vector3.ZERO
		_try_melee_attack()

func _behavior_weave_chase(_delta: float) -> void:
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist <= body_radius + 1.0:
		velocity.x = 0.0
		velocity.z = 0.0
		_try_melee_attack()
		return
	var fwd := to_player.normalized()
	var perp := Vector3(-fwd.z, 0.0, fwd.x)
	var t := Time.get_ticks_msec() / 1000.0 + weave_seed
	var wave := sin(t * 1.7) * 1.6 + sin(t * 3.1) * 1.3
	var move_dir := (fwd + perp * (wave * 0.3)).normalized()
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed

func _behavior_wobble_flight(_delta: float) -> void:
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	if dist <= body_radius + 1.0:
		velocity = Vector3.ZERO
		_try_melee_attack()
		return
	var fwd := to_player.normalized()
	var t := Time.get_ticks_msec() / 1000.0
	var wobble := Vector3(
		sin(t * 2.3 + wobble_seed.x) * 1.6,
		sin(t * 3.7 + wobble_seed.y) * 1.2,
		sin(t * 1.9 + wobble_seed.z) * 1.6
	)
	velocity = (fwd * speed) + wobble

func _behavior_knight(delta: float) -> void:
	knight_dash_timer -= delta
	knight_grab_cooldown -= delta

	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	var base_vel := Vector3.ZERO
	if dist > body_radius + 1.0:
		base_vel = to_player.normalized() * speed
	else:
		_try_melee_attack()

	if knight_dash_timer <= 0.0:
		knight_dash_timer = randf_range(3.0, 5.0)
		var side := 1.0 if randf() < 0.5 else -1.0
		var perp := Vector3(-to_player.normalized().z, 0.0, to_player.normalized().x) * side
		knight_dash_velocity = perp * 22.0

	knight_dash_velocity *= exp(-6.0 * delta)
	velocity.x = base_vel.x + knight_dash_velocity.x
	velocity.z = base_vel.z + knight_dash_velocity.z

	if knight_grab_cooldown <= 0.0:
		_try_grab_zombie()

func _try_grab_zombie() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self or not is_instance_valid(e) or e.dead:
			continue
		if e.enemy_type != "hollow" or e.thrown:
			continue
		if global_position.distance_to(e.global_position) > 4.5:
			continue
		knight_grab_cooldown = randf_range(4.5, 7.0)
		var to_player: Vector3 = (player.global_position - e.global_position)
		to_player.y = 0.0
		var dir: Vector3 = to_player.normalized() if to_player.length() > 0.01 else Vector3.FORWARD
		e.thrown = true
		e.thrown_timer = 1.6
		e.thrown_velocity = dir * 20.0 + Vector3.UP * 9.0
		e.global_position += Vector3.UP * 0.5
		return

func _process_thrown(delta: float) -> void:
	thrown_timer -= delta
	thrown_velocity.y -= GRAVITY * delta
	velocity = thrown_velocity
	# Sólo cuenta como aterrizado si YA viene CAYENDO. Sin la condición de
	# `thrown_velocity.y < 0`, el lanzamiento se cancelaba en su primer frame:
	# `is_on_floor()` devuelve el resultado del `move_and_slide()` ANTERIOR, y en
	# ese momento el enemigo estaba parado en el piso. O sea que el Knight
	# agarraba al Hollow, lo levantaba 0.5 m y lo soltaba ahí mismo — el arco
	# balístico no ocurría nunca.
	if thrown_timer <= 0.0 or (thrown_velocity.y < 0.0 and is_on_floor()):
		thrown = false
		velocity = Vector3.ZERO

func _behavior_capra(delta: float) -> void:
	match capra_state:
		"frozen":
			velocity = Vector3.ZERO
			if _player_sees_me():
				capra_state = "charge"
		"charge":
			var to_player := player.global_position - global_position
			to_player.y = 0.0
			var dist := to_player.length()
			velocity.x = 0.0
			velocity.z = 0.0
			if dist > body_radius + 1.0:
				var dir := to_player.normalized()
				velocity.x = dir.x * speed * 1.3
				velocity.z = dir.z * speed * 1.3
			else:
				_try_melee_attack()
			capra_jump_cooldown -= delta
			if dist <= 10.0 and capra_jump_cooldown <= 0.0:
				capra_state = "jump"
				capra_jump_cooldown = randf_range(3.5, 5.5)
				var dir := to_player.normalized() if to_player.length() > 0.01 else Vector3.FORWARD
				capra_jump_velocity = dir * 13.0 + Vector3.UP * 8.0
		"jump":
			capra_jump_velocity.y -= GRAVITY * delta
			velocity = capra_jump_velocity
			if is_on_floor():
				capra_state = "landed"
				capra_landed_timer = 1.0
				if player and player.has_method("add_shake"):
					player.add_shake(3.0)
		"landed":
			capra_landed_timer -= delta
			var to_player := player.global_position - global_position
			to_player.y = 0.0
			if to_player.length() > 0.01:
				velocity.x = to_player.normalized().x * speed * 0.35
				velocity.z = to_player.normalized().z * speed * 0.35
			if capra_landed_timer <= 0.0:
				capra_state = "charge"

func _player_sees_me() -> bool:
	if not player.has_node("Camera3D"):
		return false
	var cam: Camera3D = player.get_node("Camera3D")
	var to_self := global_position - cam.global_position
	if to_self.normalized().dot(-cam.global_transform.basis.z) <= 0.0:
		return false
	return cam.is_position_in_frustum(global_position)

func _behavior_sorceress(delta: float) -> void:
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	if dist > 20.0:
		velocity = to_player.normalized() * speed
	else:
		orbit_radius = lerp(orbit_radius, 17.0, 1.0 * delta)
		var tangential_speed := speed * 1.8
		orbit_angle += orbit_dir * (tangential_speed / max(orbit_radius, 1.0)) * delta
		var target := player.global_position + Vector3(cos(orbit_angle), 0.0, sin(orbit_angle)) * orbit_radius
		target.y = player.global_position.y + 1.5
		velocity = (target - global_position)

	skull_timer -= delta
	if skull_timer <= 0.0:
		skull_timer = randf_range(3.0, 4.5)
		_spawn_skull()

func _spawn_skull() -> void:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var skull = scene.instantiate()
	skull.enemy_type = "demon_skull"
	skull.counts_for_wave = false
	get_tree().current_scene.add_child(skull)
	skull.global_position = global_position

func _try_melee_attack() -> void:
	if enemy_type == "sorceress":
		return
	if attack_timer <= 0.0 and player.has_method("take_damage"):
		player.take_damage(damage, global_position)
		attack_timer = atk_cd
		_play_anim(ANIM_ATTACK, false, 1.3)

## Grilla espacial compartida, reconstruida UNA vez por frame de física.
## Antes cada enemigo recorría a TODOS los demás para separarse: con 200
## enemigos eran 40.000 comparaciones por frame (2,4 millones por segundo) más
## 200 arrays nuevos por frame, uno por enemigo. O(n²), y crecía con el cuadrado
## de la oleada. Medido antes del cambio: 29.7 ms de `_physics_process`.
static var _sep_grid: Dictionary = {}
static var _sep_frame := -1

static func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / SEP_CELL)), int(floor(p.z / SEP_CELL)))

func _rebuild_sep_grid() -> void:
	var f := Engine.get_physics_frames()
	if _sep_frame == f:
		return  # ya la armó otro enemigo en este mismo frame
	_sep_frame = f
	_sep_grid.clear()
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e.dead:
			continue
		var c := _cell_of(e.global_position)
		if not _sep_grid.has(c):
			_sep_grid[c] = []
		_sep_grid[c].append(e)

func _resolve_separation(delta: float) -> void:
	# Que dos enemigos se pisen del otro lado de la niebla no lo ve nadie, y se
	# reacomodan solos al acercarse.
	# Se usa `near_player` y NO `visible_to_player` a propósito: si se apagara
	# también para lo que está a la espalda, los que te persiguen desde atrás se
	# amontonarían en un solo bulto y se verían separarse de golpe al darse
	# vuelta. La distancia sí es segura — eso pasa detrás de la niebla.
	if not near_player:
		return
	_rebuild_sep_grid()
	var c := _cell_of(global_position)
	var moved := false
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var bucket: Variant = _sep_grid.get(Vector2i(c.x + dx, c.y + dz))
			if bucket == null:
				continue
			for e in bucket:
				if e == self or not is_instance_valid(e) or e.dead:
					continue
				var offset: Vector3 = global_position - e.global_position
				offset.y = 0.0
				var min_dist: float = body_radius + e.body_radius
				var d: float = offset.length()
				if d > 0.001 and d < min_dist:
					global_position += offset.normalized() * (min_dist - d) * SEPARATION_FORCE * delta
					moved = true
	# El empujón mueve la posición A MANO, sin pasar por la física, así que una
	# multitud apretada contra el borde podía meter enemigos ATRAVESANDO el muro
	# de la arena — y afuera no hay piso, se caían al vacío. Se veía en la
	# medición: 94 enemigos se convertían en 46 solos, sin que nadie disparara.
	if moved:
		var limit := GameData.ARENA_RADIUS - 1.5
		global_position.x = clampf(global_position.x, -limit, limit)
		global_position.z = clampf(global_position.z, -limit, limit)

# --- daño / muerte ---

## `hit_pos` es el punto EXACTO de impacto que devuelve el barrido del proyectil
## (ver bullet.gd) — no la posición discreta de la bala, que podía estar hasta
## 2.5 m más allá y convertía un tiro a la cabeza en un tiro al cuerpo.
func is_headshot_hit(hit_pos: Vector3) -> bool:
	if head_hit_radius > 0.0:
		# Esfera ajustada a la cabeza visible; acompaña el giro del enemigo. No
		# sigue el bamboleo de la animación, pero el radio (~0.5 en un humanoide)
		# es holgado de sobra frente a esos pocos centímetros.
		if hit_pos.y < global_position.y + head_floor_y:
			return false
		return hit_pos.distance_to(to_global(head_center)) <= head_hit_radius
	var bottom := global_position.y - body_height * 0.5
	var frac := (hit_pos.y - bottom) / body_height
	return frac >= HEADSHOT_HEIGHT_FRACTION

func is_headshot_immune() -> bool:
	return enemy_type == "knight" or is_alpha

func take_damage(amount: float, is_headshot: bool = false, hit_from: Vector3 = Vector3.ZERO) -> void:
	if dead:
		return
	if is_headshot and not is_headshot_immune():
		health = 0.0
	else:
		health -= amount
	if health <= 0.0:
		_die(is_headshot, hit_from)

func railgun_kill(hit_from: Vector3) -> void:
	if dead:
		return
	health = 0.0
	_die(false, hit_from)

func _die(is_headshot: bool, hit_from: Vector3) -> void:
	dead = true
	var from_dir := (global_position - hit_from).normalized() if hit_from != Vector3.ZERO else Vector3.UP
	if player and player.has_method("grant_kill_reward"):
		player.grant_kill_reward(xp_reward, regen_reward, enemy_type, is_headshot, is_alpha)
	if player and player.has_method("add_shake"):
		player.add_shake(6.0 if is_alpha else 1.2)
	GameState.register_kill(is_headshot)
	FxManager.spawn_gibs(global_position, from_dir, body_radius, is_alpha, is_headshot)
	if enemy_type == "blood_lord":
		_spawn_bats_on_death()
	died.emit(global_position, from_dir, is_headshot)
	queue_free()

func _spawn_bats_on_death() -> void:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	for i in 2:
		var bat = scene.instantiate()
		bat.enemy_type = "dire_bat"
		bat.counts_for_wave = false
		get_tree().current_scene.add_child(bat)
		bat.global_position = global_position + Vector3(randf_range(-0.6, 0.6), 0.4, randf_range(-0.6, 0.6))
