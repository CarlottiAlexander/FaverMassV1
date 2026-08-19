extends Node
## Sistema de oleadas — composición, ritmo de spawn, posicionamiento, chaos_level.
## Ver sección 7 de la especificación.

@export var enemy_scene: PackedScene

var wave := 0
var alive_count := 0
var spawn_queue: Array = []
var spawn_timer := 0.0
var wave_active := false
var announce_timer := 2.0
var first_alpha_assigned := false
var total_this_wave := 0

signal wave_changed
signal wave_announced(wave: int)
signal chaos_changed(level: float)

func _ready() -> void:
	add_to_group("wave_manager")

func _process(delta: float) -> void:
	if not wave_active:
		announce_timer -= delta
		if announce_timer <= 0.0:
			start_wave()
		return

	if spawn_queue.size() > 0:
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			spawn_timer = GameData.spawn_interval(wave)
			# Red de seguridad de rendimiento: se cuentan los NODOS reales, no
			# `alive_count`. Los cráneos que invoca la Sorceress y los murciélagos
			# que escupe el Blood Lord al morir tienen `counts_for_wave = false`,
			# así que no figuran ahí — pero cuestan FPS igual.
			if get_tree().get_nodes_in_group("enemy").size() < GameData.MAX_ALIVE_ENEMIES:
				_spawn_next()

	if spawn_queue.is_empty() and alive_count <= max(0, int(total_this_wave * 0.2)):
		wave_active = false
		announce_timer = 1.5

func start_wave() -> void:
	wave += 1
	wave_active = true
	first_alpha_assigned = false
	GameState.run_wave = wave

	# La oleada se recorta al techo de enemigos y lo que se pierde en CANTIDAD se
	# devuelve en vida/velocidad/daño. La composición cruda se pide UNA sola vez
	# (tiene `randi_range()` adentro) y de ahí salen los dos totales que definen
	# el multiplicador — así lo que se anuncia es exactamente lo que se manda.
	var raw := GameData.wave_composition(wave)
	var comp := GameData.cap_composition(raw)
	GameState.wave_surplus = GameData.surplus_of(GameData.total_of(raw), GameData.total_of(comp))
	GameState.wave_hp_mult = GameData.hp_mult_of(GameState.wave_surplus)
	GameState.wave_speed_mult = GameData.speed_mult_of(GameState.wave_surplus)
	GameState.wave_damage_mult = GameData.damage_mult_of(GameState.wave_surplus)

	spawn_queue.clear()
	for enemy_type in comp:
		for i in comp[enemy_type]:
			spawn_queue.append(enemy_type)
	spawn_queue.shuffle()
	total_this_wave = spawn_queue.size()
	alive_count = 0
	spawn_timer = 0.0

	wave_changed.emit()
	wave_announced.emit(wave)
	chaos_changed.emit(GameData.chaos_level(wave))

func _spawn_next() -> void:
	if not enemy_scene or spawn_queue.is_empty():
		return
	var etype: String = spawn_queue.pop_front()
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node3D = players[0]

	var is_alpha := false
	if wave % 5 == 0 and not first_alpha_assigned:
		is_alpha = true
		first_alpha_assigned = true

	# A qué distancia nace sale de la tabla de spawn, no de un `if` por nombre: la
	# Capra necesita 46-58 porque carga a 8 u/s y a 40 m no daba tiempo a reaccionar,
	# y un tipo de mod igual de rápido va a necesitar lo mismo.
	var sd: Array = GameData.spawn_dist_of(etype)
	var dist_min: float = sd[0]
	var dist_max: float = sd[1]

	var angle: float
	if randf() < 0.7:
		var behind := player.rotation.y + PI
		var arc := deg_to_rad(140.0)
		angle = behind + randf_range(-arc * 0.5, arc * 0.5)
	else:
		angle = randf() * TAU

	var dist := randf_range(dist_min, dist_max)
	var dir := Vector3(sin(angle), 0.0, cos(angle))
	var pos := player.global_position + dir * dist

	# Recorte RADIAL a los límites de la arena (no por eje: clampear x/z por
	# separado podía mandar el spawn a una esquina del mapa muy cerca del
	# jugador si este estaba pegado al borde — el enemigo aparecía "de la
	# nada" en vez de a 40-50 unidades). Si igual queda demasiado cerca
	# después del recorte, se empuja a un piso mínimo de distancia.
	var max_from_center := GameData.ARENA_RADIUS - 3.0
	var flat := Vector2(pos.x, pos.z)
	if flat.length() > max_from_center:
		flat = flat.normalized() * max_from_center
		pos.x = flat.x
		pos.z = flat.y

	var min_player_dist := 15.0
	if pos.distance_to(player.global_position) < min_player_dist:
		var away := pos - player.global_position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else dir
		pos = player.global_position + away * min_player_dist
		flat = Vector2(pos.x, pos.z)
		if flat.length() > max_from_center:
			flat = flat.normalized() * max_from_center
			pos.x = flat.x
			pos.z = flat.y

	pos.y = randf_range(2.0, 5.0) if GameData.enemy_stats_of(etype).get("flying", false) else 0.3

	var e = enemy_scene.instantiate()
	e.enemy_type = etype
	e.is_alpha = is_alpha
	get_tree().current_scene.add_child(e)
	# El origen del enemigo es el CENTRO de su forma de colisión, así que apoyarlo
	# en el piso es medio cuerpo — no 0.3. Con 0.3 un Hollow (2.35 de alto) nacía
	# enterrado hasta el pecho y salía a los tirones cuando la física lo
	# despenetraba. `body_height` ya viene ajustado al modelo real por su _ready(),
	# que corrió recién en el add_child de arriba, y contempla el tamaño alpha.
	if not GameData.enemy_stats_of(etype).get("flying", false):
		pos.y = e.body_height * 0.5 + 0.05
	e.global_position = pos
	alive_count += 1
	e.died.connect(func(_p, _d, _h): _on_enemy_died())

func _on_enemy_died() -> void:
	alive_count -= 1

func reset() -> void:
	wave = 0
	alive_count = 0
	spawn_queue.clear()
	wave_active = false
	announce_timer = 2.0
	total_this_wave = 0
