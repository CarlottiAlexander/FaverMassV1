class_name Enemy
extends CharacterBody3D
## Enemigo unificado: 8 tipos (sección 6) + variante alpha, seleccionados por `enemy_type`.
## Las stats base vienen del registro de GameData (`enemy_stats_of`), que es
## ENEMY_STATS mas lo que hayan pisado los mods.
##
## Este archivo es el NÚCLEO: estado, medidas, animación, visibilidad, separación,
## daño y muerte. Lo que varía por tipo vive en tres módulos al lado, cada uno con
## una razón distinta para cambiar:
##
##   `enemy_behaviors.gd`        qué hace cada tipo con su velocidad (la IA)
##   `enemy_model_import.gd`     carga y medición de los `.glb` (escala, hitbox, cabeza)
##   `enemy_model_procedural.gd` modelos de respaldo armados con primitivas
##
## Sigue sin haber 8 scripts, uno por enemigo: el despacho por tipo es UN match en
## `EnemyBehaviors.run()`. La división es por RESPONSABILIDAD, no por bicho — así
## se puede tocar el balance de la IA sin cargar 700 líneas de geometría al lado.

@export var enemy_type: String = "hollow"
@export var is_alpha: bool = false

const GRAVITY := 20.0
const SEPARATION_FORCE := 6.0
## Sólo se usa como último recurso, para modelos procedurales sin cabeza medible.
## Los modelos importados usan una ESFERA ajustada a la cabeza real
## (ver `EnemyModelImport._fit_head`).
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

## ACUSE DE RECIBO DEL IMPACTO: un destello rojo más un frenón breve. Los dos
## salen del mismo disparador (`_react_to_hit`) y comparten cooldown, así que se
## leen como un solo "tick" por golpe.
## El cooldown es la pieza importante: la Minigun mete ~15 balas por segundo y
## sin él el enemigo quedaba en estroboscopio y frenado de forma permanente.
## Pedido textual: "que estos ticks tengan un delay razonable uno entre otro".
const HIT_FLASH_TIME := 0.08
const HIT_SLOW_TIME := 0.12
const HIT_REACT_COOLDOWN := 0.18
## Cuánto de su velocidad conserva mientras acusa el golpe. Es un frenón, no un
## stun. Ojo que esto TOCA EL BALANCE: bajo fuego sostenido el tick se renueva
## cada 0.18 s y el enemigo pasa 2/3 del tiempo frenado, o sea que avanza a
## ~0.77x mientras le disparás. Bajarlo mucho más y las oleadas altas dejan de
## alcanzarte.
const HIT_SLOW_FACTOR := 0.65

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var aura: MeshInstance3D = $Aura

var model_root: Node3D
## Pivotes del modelo PROCEDURAL que se bambolean en `_process`. Los devuelve
## `EnemyModelProcedural.build()`; los tipos con `.glb` los dejan todos en null y
## animan con el rig importado.
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
## Rasgos declarados por un mod: {nombre: {parámetros}}. Vacío para los 8 base.
var traits: Dictionary = {}
## Estado en vivo de esos rasgos (escudo restante, ráfaga activa...). Va todo acá
## y no como campos nuevos del enemigo: cada trait sumaría 2-3 campos a los 50
## enemigos vivos, y el 90% de ellos no lo usaría.
var trait_state: Dictionary = {}

## Ajustes del pipeline de modelo declarados por un mod. Vacío = todo por defecto.
## Lo lee `EnemyModelImport` en vez de sus constantes, que están escritas contra los
## dos packs del juego base.
var model_opts: Dictionary = {}

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

# --- estado específico por tipo (lo lee y lo escribe `EnemyBehaviors`) ---
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

## Mallas del modelo (sin el aura del alpha), cacheadas en _apply_render_cull.
## El destello las recorre al encender y al apagar; volver a caminar el árbol
## por cada bala recibida no tenía sentido.
var _flash_meshes: Array = []
var _flash_time := 0.0
var _slow_time := 0.0
var _react_cd := 0.0

## Distancia al jugador y "está a mi espalda", calculados UNA vez por frame de
## física en `_physics_process` y reusados por todo lo demás. Antes cada sistema
## los recalculaba por su cuenta.
var dist_to_player_sq := 0.0
## Dentro del alcance de dibujado, mire para donde mire el jugador.
var near_player := true
## Además, delante de la cámara. Más restrictivo que `near_player`.
var visible_to_player := true

## Esfera de cabeza en espacio LOCAL del enemigo, medida del modelo real en
## `EnemyModelImport._fit_head`. `head_hit_radius == 0` significa "no se pudo
## medir" y se cae a la banda de altura de HEADSHOT_HEIGHT_FRACTION.
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

	# Los rasgos se resuelven antes que nada: `EnemyTraits.on_spawn` los inicializa
	# (el escudo arranca cargado) y varios se consultan durante el armado.
	traits = ModManager.traits_of(enemy_type)
	EnemyTraits.on_spawn(self)

	var stats: Dictionary = GameData.enemy_stats_of(enemy_type)
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
## la vuelve a ajustar `EnemyModelImport._fit_collision()` con las medidas del
## modelo real.
## El orden importa: si se asigna un radius mayor que height/2, Godot estira la
## height sola. Height primero, radius recortado después.
func _apply_collision() -> void:
	var shape := CapsuleShape3D.new()
	shape.height = maxf(body_height, 0.1)
	shape.radius = minf(body_radius, shape.height * 0.5)
	collision_shape.shape = shape
	body_radius = shape.radius

# --- modelo -----------------------------------------------------------------

func _color() -> Color:
	return GameData.enemy_color_of(enemy_type)

func _build_model() -> void:
	model_root = Node3D.new()
	model_root.name = "Model"
	add_child(model_root)

	# Modelo importado (CC0) si existe uno para este tipo; si no, se cae al modelo
	# procedural de piezas primitivas. El importado se alinea solo contra la
	# colisión (ver EnemyModelImport.build); el procedural no, así que hay que
	# bajarlo a mano: sus piezas se ubican asumiendo Y=0 -> pies, pero el origen
	# del CharacterBody3D es el CENTRO de la cápsula.
	# Un mod tiene prioridad sobre el asset del juego. Su modelo no vino de res://
	# sino parseado del disco en runtime, pero de acá en adelante el camino es el
	# mismo: se mide, se escala a la altura del tipo, se centra en la colisión y se
	# le arma la esfera de headshot. Por eso "las hitboxes se acomodan solas".
	# Ajustes que declaró el mod para este tipo (yaw, palabras de la cabeza, hueso,
	# forma de hitbox, equipamiento, animaciones). Vacío para los 8 base, así que
	# todo el pipeline usa sus defaults de siempre.
	model_opts = ModManager.model_opts_of(enemy_type)

	var mod_scene: PackedScene = ModManager.model_scene_for(enemy_type)
	if mod_scene:
		anim_player = EnemyModelImport.build_from_scene(self, mod_scene)
		if anim_player or model_root.get_child_count() > 0:
			_setup_anim_player()
			_apply_render_cull()
			return
		# El modelo del mod no se pudo montar: se sigue de largo al asset base en
		# vez de dejar al enemigo invisible.

	var model_path := "res://assets/enemies/%s.glb" % enemy_type
	if ResourceLoader.exists(model_path):
		anim_player = EnemyModelImport.build(self, model_path)
		_setup_anim_player()
		_apply_render_cull()
		return

	model_root.position.y = -body_height * 0.5
	var piv := EnemyModelProcedural.build(
		enemy_type, model_root, _color(), body_height, body_radius, head_radius)
	_anim_l_arm = piv.get("l_arm")
	_anim_r_arm = piv.get("r_arm")
	_anim_l_leg = piv.get("l_leg")
	_anim_r_leg = piv.get("r_leg")
	_anim_l_leg2 = piv.get("l_leg2")
	_anim_r_leg2 = piv.get("r_leg2")
	_anim_l_wing = piv.get("l_wing")
	_anim_r_wing = piv.get("r_wing")
	_anim_head = piv.get("head")
	_anim_jaw = piv.get("jaw")
	_anim_tail = piv.get("tail")
	_apply_render_cull()

func _setup_anim_player() -> void:
	if not anim_player:
		return
	# MANUAL: el mixer deja de avanzar solo. Lo avanza `_process` cuando le
	# toca según la distancia (ver ANIM_STRIDE_*). Es de lejos el ahorro más
	# grande que tiene el juego.
	anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_anim_phase = randi() % (ANIM_STRIDE_VERY_FAR * ANIM_STRIDE_FAR)
	play_anim(ANIM_IDLE)

## Corte de dibujado por distancia. Lo resuelve el RenderingServer, no GDScript:
## cero costo por frame. Corte SECO y no fundido — el fundido obliga a tratar el
## material como transparente durante la transición, y acá no hace falta: a esa
## distancia la pared de niebla ya es opaca, así que no se ve nada aparecer ni
## desaparecer. Va después del injerto de cabeza para alcanzarlo también.
func _apply_render_cull() -> void:
	var meshes := EnemyModelImport.all_mesh_nodes(self)
	# El trait `cloak` es, literalmente, un corte de dibujado más cercano: el
	# enemigo no se ve hasta que entrás en su distancia de revelado. Lo resuelve el
	# RenderingServer igual que el LOD, así que no cuesta un solo frame de GDScript.
	var corte := EnemyTraits.cull_distance(self, GameData.ENEMY_LOD_DISTANCE)
	for m in meshes:
		m.visibility_range_end = corte
		m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	# El aura del alpha queda AFUERA del destello: es su marca de identidad y
	# pintarla de rojo la borraría justo cuando más se le está disparando.
	_flash_meshes = meshes.filter(func(m: MeshInstance3D) -> bool: return m != aura)

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
## cachea porque `play_anim` se llama TODOS los frames por enemigo, y recorrer
## la lista preguntando `has_animation()` cada vez son cientos de búsquedas por
## frame que siempre dan el mismo resultado.
static var _anim_name_cache: Dictionary = {}

## Lo llama ModManager al aplicar cambios. Igual que el caché de injertos: es
## estático y sobrevive al reinicio de escena, así que un modelo nuevo con otros
## nombres de animación se quedaría con los resueltos para el modelo anterior.
static func clear_anim_cache() -> void:
	_anim_name_cache.clear()

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

## Palabras que identifican cada ranura cuando el nombre exacto no está en la
## lista de candidatos. El orden importa: se prueba palabra por palabra y gana la
## primera que aparezca en alguna animación del modelo.
const ANIM_HINTS := {
	"idle": ["idle", "stand", "breath"],
	"run": ["run", "walk", "fly", "move"],
	"attack": ["attack", "punch", "bite", "headbutt", "hit", "slash", "chop"],
	"death": ["death", "die", "dead"],
	"hitreact": ["hitreact", "hitrecieve", "hitreceive", "damage", "flinch"],
}

## Último recurso cuando ninguno de los nombres candidatos existe en el modelo.
##
## Hace falta de verdad, no es un lujo: las listas de candidatos están escritas
## contra los dos packs que usa el juego, y un modelo cualquiera de la comunidad
## nombra sus animaciones como se le ocurrió al autor. Medido con un monstruo del
## banco: trae `CharacterArmature|Idle` y `|Walk`, y las listas buscaban
## `|Flying_Idle` y `|Fast_Flying` — no resolvía NINGUNA ranura, o sea que el
## enemigo se deslizaba sin animarse. Con esto, la mayoría de los rigs andan sin
## que el modder configure nada.
## Estática y recibiendo el AnimationPlayer para que `tools/mod_report` pueda
## reportar EXACTAMENTE lo que el juego va a resolver. Un reporte que dijera algo
## distinto de lo que pasa en la partida sería peor que no tener reporte.
static func guess_anim(ap: AnimationPlayer, candidates: Array) -> String:
	var slot := ""
	for k: String in ANIM_HINTS:
		if candidates == _slot_list(k):
			slot = k
			break
	if slot == "":
		return ""
	var names := ap.get_animation_list()
	for hint: String in ANIM_HINTS[slot]:
		for n: String in names:
			# Se compara sobre el nombre PELADO: los packs prefijan con el nombre
			# del armature ("CharacterArmature|Idle"), y buscar "idle" adentro del
			# nombre completo daría falsos positivos con cualquier armature que se
			# llame así.
			var bare := n.get_slice("|", n.get_slice_count("|") - 1).to_lower()
			if bare.contains(hint):
				return n
	return ""

## Nombres que el mod declaró para la ranura a la que corresponden estos
## candidatos. Vacío si no hay mod o si no declaró esa ranura.
func _mod_anims(candidates: Array) -> Array:
	var mapa: Dictionary = model_opts.get("anim", {})
	if mapa.is_empty():
		return []
	for k: String in ANIM_HINTS:
		if candidates == _slot_list(k):
			return mapa.get(k if k != "hitreact" else "hit", [])
	return []

static func _slot_list(slot: String) -> Array:
	match slot:
		"idle": return ANIM_IDLE
		"run": return ANIM_RUN
		"attack": return ANIM_ATTACK
		"death": return ANIM_DEATH
		"hitreact": return ANIM_HIT
	return []

## Público: lo llama también `EnemyBehaviors.try_melee_attack()`.
func play_anim(candidates: Array, loop: bool = true, speed_scale: float = 1.0) -> bool:
	if not anim_player:
		return false
	var key := "%s|%s" % [enemy_type, candidates[0]]
	var anim_name: String = _anim_name_cache.get(key, "")
	if not _anim_name_cache.has(key):
		# Orden de prioridad: lo que declaró el mod, después los nombres de los
		# packs del juego, y como último recurso deducir por palabra clave.
		#
		# El mapa del mod va PRIMERO y se resuelve acá adentro (y no cambiando la
		# firma de esta función) porque `EnemyBehaviors.try_melee_attack()` llama
		# con la constante global `Enemy.ANIM_ATTACK`: si el mapa se aplicara sólo
		# en quien llama, ese camino se lo saltearía y el ataque de un enemigo de
		# mod usaría el nombre equivocado.
		for n: String in _mod_anims(candidates):
			if anim_player.has_animation(n):
				anim_name = n
				break
		if anim_name == "":
			for n in candidates:
				if anim_player.has_animation(n):
					anim_name = n
					break
		if anim_name == "":
			anim_name = guess_anim(anim_player, candidates)
		_anim_name_cache[key] = anim_name
	if anim_name == "":
		return false
	if anim_player.current_animation == anim_name:
		return true
	var anim := anim_player.get_animation(anim_name)
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	anim_player.speed_scale = speed_scale
	anim_player.play(anim_name)
	current_anim_locked = not loop
	return true

func _process(delta: float) -> void:
	if dead or not model_root:
		return

	# El destello se apaga ACÁ ARRIBA, antes de todos los cortes por distancia y
	# visibilidad que vienen abajo. Si se apagara después, a un enemigo golpeado
	# que sale de cámara o se mete en la niebla no le llegaba nunca el apagado y
	# volvía a aparecer rojo permanente.
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			_set_flash(false)

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
			play_anim(ANIM_RUN, true, clampf(speed_xz / 4.5, 0.6, 1.8))
		else:
			play_anim(ANIM_IDLE, true, 1.0)
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
	if _react_cd > 0.0:
		_react_cd -= delta
	if _slow_time > 0.0:
		_slow_time -= delta
	EnemyTraits.tick(self, delta)

	if thrown:
		EnemyBehaviors.process_thrown(self, delta)
		move_and_slide()
		return

	EnemyBehaviors.run(self, delta)

	# Frenón del impacto. Va ACÁ, sobre lo que dejó el comportamiento, y no
	# multiplicando `speed`: así alcanza también a los que no se mueven leyendo
	# `speed` (el dash del Knight, el salto de la Capra, la órbita de la
	# Sorceress) sin tener que tocar los siete comportamientos uno por uno.
	# No se acumula frame a frame porque todos reescriben `velocity` entera.
	# Sólo el plano horizontal: escalar la vertical le robaría altura a los
	# saltos y pelearía con la gravedad de más abajo.
	# El enemigo LANZADO por el Knight sale antes de llegar acá, a propósito —
	# frenarle el arco en el aire lo dejaba cayendo como una piedra.
	if _slow_time > 0.0:
		velocity.x *= HIT_SLOW_FACTOR
		velocity.z *= HIT_SLOW_FACTOR

	# El trait `on_hit_speed_burst` va DESPUÉS del frenón, a propósito: un enemigo
	# que acelera al recibir daño tiene que ganarle al frenón que acaba de comerse,
	# si no la mecánica se cancela sola y no se nota.
	var tm := EnemyTraits.speed_mult(self)
	if tm != 1.0:
		velocity.x *= tm
		velocity.z *= tm

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

# --- separación ---

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
	return enemy_type == "knight" or is_alpha or EnemyTraits.has(self, "headshot_immune")

func take_damage(amount: float, is_headshot: bool = false, hit_from: Vector3 = Vector3.ZERO) -> void:
	if dead:
		return
	if is_headshot and not is_headshot_immune():
		health = 0.0
	else:
		# El escudo del trait `shield` se come el daño ANTES que la vida. Un
		# headshot lo saltea, igual que saltea la vida: sigue siendo instakill.
		health -= EnemyTraits.absorb(self, amount)
	if health <= 0.0:
		_die(is_headshot, hit_from)
		return
	_react_to_hit()

## Un solo "tick" de acuse por golpe: destello + frenón, ambos detrás del mismo
## cooldown. Los golpes que caen dentro del cooldown se ignoran para el feedback
## (el DAÑO se aplica siempre, arriba) — si no, con las armas automáticas esto
## se disparaba varias veces por frame.
func _react_to_hit() -> void:
	if _react_cd > 0.0:
		return
	_react_cd = HIT_REACT_COOLDOWN
	_slow_time = HIT_SLOW_TIME
	EnemyTraits.on_hit(self)
	if _flash_time <= 0.0:
		_set_flash(true)
	_flash_time = HIT_FLASH_TIME

## UN material para todo el juego, no uno por enemigo. Duplicar materiales por
## instancia rompería el caché de `EnemyModelProcedural.surface_material()` y con
## él el batcheo — ver el comentario de `_mat_cache`. `material_override` PISA el
## material sin tocar el original, así que apagar el destello es volver a poner
## null.
static var _flash_material: StandardMaterial3D = null

static func _get_flash_material() -> StandardMaterial3D:
	if _flash_material == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.35, 0.02, 0.02)
		# Por encima del `glow_hdr_threshold` del entorno (1.25), así que el
		# destello además florece. Es lo que lo hace legible en una turba: se ve
		# CUÁL de los enemigos amontonados es el que estás golpeando.
		m.emission_enabled = true
		m.emission = Color(1.0, 0.08, 0.06)
		m.emission_energy_multiplier = 1.5
		_flash_material = m
	return _flash_material

func _set_flash(on: bool) -> void:
	var mat: StandardMaterial3D = _get_flash_material() if on else null
	for m in _flash_meshes:
		if is_instance_valid(m):
			m.material_override = mat

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
	# Va antes del queue_free(): los traits que invocan o explotan necesitan la
	# posición del enemigo y el árbol todavía vivo.
	EnemyTraits.on_death(self)
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
