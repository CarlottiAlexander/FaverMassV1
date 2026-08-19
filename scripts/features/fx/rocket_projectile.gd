extends Node3D
## Cohete de "La Maleducada": proyectil real que viaja y detona al impactar.
## Usa el mismo BARRIDO por rayo que `bullet.gd` en vez de solapamiento de
## Area3D — ver el comentario largo de ese archivo. Acá importa menos (el radio
## de explosión es 7.5 m y perdona), pero de paso la explosión queda centrada en
## el punto de impacto exacto y no hasta 0.75 m más allá de la superficie.

const SPEED := 45.0
const LIFETIME := 4.0
const HIT_MASK := 3  # capa 1 (mundo) + capa 2 (actores)

var dir := Vector3.FORWARD
var damage := 300.0
var hs_mult := 1.5
var shooter: Node = null
var life := LIFETIME
var exploded := false
var _prev_pos := Vector3.ZERO

func setup(_dir: Vector3, _damage: float, _hs_mult: float, _shooter: Node, _sweep_from: Vector3 = Vector3.INF) -> void:
	dir = _dir
	damage = _damage
	hs_mult = _hs_mult
	shooter = _shooter
	_prev_pos = _sweep_from if _sweep_from.is_finite() else global_position
	look_at(global_position + dir, Vector3.UP)

func _physics_process(delta: float) -> void:
	if exploded:
		return
	life -= delta
	var next_pos := global_position + dir * SPEED * delta
	_sweep(_prev_pos, next_pos)
	if exploded:
		return
	global_position = next_pos
	_prev_pos = next_pos
	if life <= 0.0 or global_position.length() > GameData.arena_radius * 2.0 or global_position.y < -5.0:
		_explode()

func _sweep(from: Vector3, to: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if shooter is CollisionObject3D:
		exclude.append(shooter.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK, exclude)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var body = hit["collider"]
	global_position = hit["position"]
	if body.is_in_group("enemy") and body.has_method("take_damage"):
		var is_hs: bool = body.is_headshot_hit(global_position) if body.has_method("is_headshot_hit") else false
		var dmg := damage
		if is_hs:
			dmg *= hs_mult
		body.take_damage(dmg, is_hs, global_position)
		FxManager.spawn_damage_number(global_position, dmg, is_hs)
	_explode()

func _explode() -> void:
	if exploded:
		return
	exploded = true
	FxManager.spawn_explosion(global_position, GameData.ROCKET_EXPLOSION_RADIUS, GameData.ROCKET_EXPLOSION_VISUAL_RADIUS)
	queue_free()
