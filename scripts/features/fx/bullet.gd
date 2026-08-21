extends Node3D
## Proyectil de bala real (no hitscan) para las armas normales — viaja, puede
## perforar (`pierce`) hasta N enemigos para Sniper/Revolver, y se destruye al
## primer impacto contra mundo/enemigo para el resto.
##
## La detección es un BARRIDO (rayo del punto anterior al nuevo), no un
## solapamiento de Area3D. Motivo medido: a 150 u/s con la física a 60 Hz la
## bala avanza 2.5 m por paso, más del doble de lo que mide un enemigo de ancho
## (~1 m). Preguntando solo "¿estoy dentro de alguien?" en cada posición
## discreta, más de la mitad de los disparos bien apuntados atravesaban al
## enemigo sin registrar nada — era la causa principal de "las hitboxes están
## mal". El barrido además devuelve el PUNTO EXACTO de impacto, que es lo que
## decide si fue headshot y dónde va el número de daño.

const SPEED := 150.0
const LIFETIME := 2.5
## Capa 1 (mundo) + capa 2 (actores). Los gibs viven en la 5 y no se tocan.
const HIT_MASK := 3
## Tope de enemigos resueltos dentro de un mismo tramo de barrido (perforación).
const MAX_SWEEP_STEPS := 12

var dir := Vector3.FORWARD
var damage := 10.0
var hs_mult := 1.0
var pierce := 0
var force_crit := false
var shooter: Node = null
var life := LIFETIME
var hits := 0
var hit_bodies: Array = []
var finished := false

## Extremo trasero del barrido de este frame. Arranca en la boca del arma (la
## cámara), no en la posición visible de la bala: el tracer nace 1 m adelante
## para no dibujarse dentro del viewmodel, y sin esto ese primer metro era un
## punto ciego — un enemigo pegado al jugador se comía los tiros.
var _prev_pos := Vector3.ZERO

func setup(_dir: Vector3, _damage: float, _hs_mult: float, _pierce: int, _shooter: Node, _force_crit: bool = false, _sweep_from: Vector3 = Vector3.INF) -> void:
	dir = _dir
	damage = _damage
	hs_mult = _hs_mult
	pierce = _pierce
	shooter = _shooter
	force_crit = _force_crit
	_prev_pos = _sweep_from if _sweep_from.is_finite() else global_position
	look_at(global_position + dir, Vector3.UP)

func _physics_process(delta: float) -> void:
	if finished:
		return
	life -= delta
	var next_pos := global_position + dir * SPEED * delta
	_sweep(_prev_pos, next_pos)
	if finished:
		return
	global_position = next_pos
	_prev_pos = next_pos
	if life <= 0.0:
		_finish()

## Rayo de `from` a `to`. Si pega un enemigo y todavía queda perforación, sigue
## desde ese impacto con el enemigo ya excluido — así una sola bala atraviesa
## varios en el mismo tramo, que es lo que hacía la exclude-list del raycast viejo.
func _sweep(from: Vector3, to: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if shooter is CollisionObject3D:
		exclude.append(shooter.get_rid())
	for b in hit_bodies:
		if is_instance_valid(b) and b is CollisionObject3D:
			exclude.append(b.get_rid())

	var origin := from
	for _i in MAX_SWEEP_STEPS:
		if origin.distance_squared_to(to) < 0.000001:
			return
		var query := PhysicsRayQueryParameters3D.create(origin, to, HIT_MASK, exclude)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return
		var body = hit["collider"]
		var point: Vector3 = hit["position"]
		if body.is_in_group("enemy") and body.has_method("take_damage"):
			_hit_enemy(body, point)
			if finished:
				return
			exclude.append(body.get_rid())
			origin = point
		else:
			# Mundo (piso, obstáculos, paredes): la bala muere donde pegó.
			global_position = point
			_finish()
			return

func _hit_enemy(body: Node, point: Vector3) -> void:
	hit_bodies.append(body)
	var is_hs: bool = force_crit or (body.is_headshot_hit(point) if body.has_method("is_headshot_hit") else false)
	var dmg := damage
	if is_hs:
		dmg *= hs_mult
	body.take_damage(dmg, is_hs, point)
	FxManager.spawn_damage_number(point, dmg, is_hs)
	# Impacto: posicional, donde pegó. El headshot suena distinto porque es la
	# información más valiosa que el juego le puede dar al jugador sin mirar el HUD.
	Audio.play_3d(Audio.ui("impact_headshot" if is_hs else "impact"), point, "impact", 1.0, 0.85 if is_hs else 1.0)
	if shooter and shooter.has_signal("hit_confirmed"):
		shooter.hit_confirmed.emit(is_hs)
	hits += 1
	if hits > pierce:
		global_position = point
		_finish()

func _finish() -> void:
	if finished:
		return
	finished = true
	queue_free()
