class_name Ballistics
extends RefCounted
## De dónde sale un tiro, hacia dónde va y a qué le pega. Es la mitad "geométrica"
## de las armas; la otra mitad (qué arma está equipada, munición, cadencia,
## spin-up, éxtasis) se queda en `player.gd`.
##
## Se separó porque son dos cosas que se tocan por razones distintas: acá se
## corrigen problemas de PUNTERÍA (convergencia, dispersión, punto ciego del
## caño) y allá se corrige el MANEJO del arma. Guarda `shooter` y `camera` una
## sola vez en vez de recibirlos por parámetro en cada llamada.

const SHOOT_RANGE := 100.0

var shooter: CharacterBody3D
var camera: Camera3D
## El viewmodel, para saber dónde está la boca del caño. Puede ser null.
var muzzle_source: Node3D = null

func _init(p_shooter: CharacterBody3D, p_camera: Camera3D) -> void:
	shooter = p_shooter
	camera = p_camera

## Punto al que le apunta la MIRA. Los proyectiles salen de la boca del arma pero
## tienen que converger acá, no volar paralelos a la vista: el caño está unos 30
## cm a la derecha y abajo de la cámara, así que un disparo paralelo le erraría
## por esa distancia a todo lo que esté cerca.
func aim_point() -> Vector3:
	var from := camera.global_position
	var to := from + (-camera.global_transform.basis.z) * SHOOT_RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to, 3, [shooter.get_rid()])
	var hit := shooter.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else to

func muzzle_position() -> Vector3:
	if muzzle_source and is_instance_valid(muzzle_source):
		return muzzle_source.get_muzzle_global()
	return camera.global_position

func spread_direction(spread: float, base_dir: Vector3 = Vector3.INF) -> Vector3:
	var base := base_dir if base_dir.is_finite() else -camera.global_transform.basis.z
	if spread <= 0.0:
		return base
	var right := camera.global_transform.basis.x
	var up := camera.global_transform.basis.y
	var ox := randf_range(-1.0, 1.0) * spread
	var oy := randf_range(-1.0, 1.0) * spread
	return (base + right * ox + up * oy).normalized()

func fire_pellets(w: Dictionary, damage: float, sprinting: bool, crouching: bool, force_crit: bool, spread_extra_mult: float = 1.0) -> void:
	var spread_mult := 1.0
	if crouching:
		spread_mult = 0.6
	elif sprinting:
		spread_mult = 1.5
	var spread: float = w["spread"] * spread_mult * spread_extra_mult
	var pellets: int = w["pellets"]
	# Un solo rayo por disparo (no uno por perdigón) para saber a qué le apunta la
	# mira; de ahí salen las direcciones de todos los perdigones.
	var aim := aim_point()
	var muzzle := muzzle_position()
	var base := (aim - muzzle).normalized()
	for i in pellets:
		var dir := spread_direction(spread, base)
		fire_bullet(dir, w, damage, force_crit, muzzle)

func fire_bullet(dir: Vector3, w: Dictionary, damage: float, force_crit: bool = false, muzzle: Vector3 = Vector3.INF) -> void:
	var scene: PackedScene = load("res://scenes/fx/bullet.tscn")
	var bullet = scene.instantiate()
	shooter.get_tree().current_scene.add_child(bullet)
	# El tracer NACE EN LA BOCA DEL ARMA, pero el barrido de colisión sigue
	# arrancando en la cámara: si arrancara en la boca, el tramo entre la cámara y
	# el caño sería un punto ciego y un enemigo pegado al jugador se comería los
	# tiros. El barrido siempre puede ser más generoso que el dibujo.
	bullet.global_position = muzzle if muzzle.is_finite() else camera.global_position + dir * 1.0
	bullet.setup(dir, damage, w["hs_mult"], w.get("pierce", 0), shooter, force_crit, camera.global_position)

func fire_rocket(w: Dictionary, damage: float) -> void:
	# Igual que las balas: sale de la boca y converge al punto de la mira.
	var muzzle := muzzle_position()
	var dir := (aim_point() - muzzle).normalized()
	var scene: PackedScene = load("res://scenes/fx/rocket_projectile.tscn")
	var rocket = scene.instantiate()
	shooter.get_tree().current_scene.add_child(rocket)
	rocket.global_position = muzzle
	rocket.setup(dir, damage, w["hs_mult"], shooter, camera.global_position)

## Haz del Railgun: hitscan que ATRAVIESA enemigos encadenando rayos. No es un
## proyectil, por eso no comparte nada con `fire_bullet`.
func railgun_sweep() -> void:
	var space_state := shooter.get_world_3d().direct_space_state
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	# `exclude` de la física son RIDs, no nodos: pasarle nodos no excluye nada
	# (funcionaba de casualidad porque un rayo que nace dentro de una forma no la
	# reporta). Con RIDs el haz atraviesa de verdad lo que ya mató.
	var exclude: Array[RID] = [shooter.get_rid()]
	var origin := from
	for i in 20:
		var to := origin + dir * SHOOT_RANGE
		var query := PhysicsRayQueryParameters3D.create(origin, to)
		query.exclude = exclude
		var result := space_state.intersect_ray(query)
		if result.is_empty():
			break
		var collider = result.collider
		if collider.is_in_group("enemy") and collider.has_method("railgun_kill"):
			collider.railgun_kill(from)
			exclude.append(collider.get_rid())
			origin = result.position + dir * 0.01
		else:
			break
