class_name EnemyBehaviors
extends RefCounted
## La IA de los 8 tipos de enemigo: qué hace cada uno con su `velocity` en cada
## frame de física. Es la mitad "decisión" del enemigo; la otra mitad (medidas,
## modelo, animación, daño, muerte) se queda en `enemy.gd`.
##
## Todo pasa por `run()`, que despacha por `enemy_type`. Sigue siendo UN solo
## match y UN solo archivo para los 8 tipos, a propósito: es mucho más fácil de
## comparar y balancear a mano que ocho scripts. Lo que se separó de `enemy.gd`
## no son los tipos, es la RESPONSABILIDAD.
##
## Funciones estáticas que reciben el enemigo (`e: Enemy`) en vez de métodos:
## así este archivo no tiene estado propio y se lo puede llamar desde una
## herramienta (`tools/throw_test.tscn` dispara `try_grab_zombie` a mano).

## Despacho por tipo. El `_` final es el mismo comportamiento que el Hollow: un
## tipo nuevo mal escrito camina derecho en vez de quedarse clavado.
static func run(e: Enemy, delta: float) -> void:
	match e.enemy_type:
		"hollow", "thrall":
			_direct_chase(e)
		"dire_bat":
			_flying_direct(e)
		"blood_lord":
			_weave_chase(e)
		"knight":
			_knight(e, delta)
		"capra":
			_capra(e, delta)
		"sorceress":
			_sorceress(e, delta)
		"demon_skull":
			_wobble_flight(e)
		_:
			_direct_chase(e)

static func _direct_chase(e: Enemy) -> void:
	var to_player := e.player.global_position - e.global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > e.body_radius + 1.0:
		var dir := to_player.normalized()
		e.velocity.x = dir.x * e.speed
		e.velocity.z = dir.z * e.speed
	else:
		e.velocity.x = 0.0
		e.velocity.z = 0.0
		try_melee_attack(e)

static func _flying_direct(e: Enemy) -> void:
	var to_player := e.player.global_position - e.global_position
	var dist := to_player.length()
	if dist > e.body_radius + 1.0:
		e.velocity = to_player.normalized() * e.speed
	else:
		e.velocity = Vector3.ZERO
		try_melee_attack(e)

static func _weave_chase(e: Enemy) -> void:
	var to_player := e.player.global_position - e.global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist <= e.body_radius + 1.0:
		e.velocity.x = 0.0
		e.velocity.z = 0.0
		try_melee_attack(e)
		return
	var fwd := to_player.normalized()
	var perp := Vector3(-fwd.z, 0.0, fwd.x)
	var t := Time.get_ticks_msec() / 1000.0 + e.weave_seed
	var wave := sin(t * 1.7) * 1.6 + sin(t * 3.1) * 1.3
	var move_dir := (fwd + perp * (wave * 0.3)).normalized()
	e.velocity.x = move_dir.x * e.speed
	e.velocity.z = move_dir.z * e.speed

static func _wobble_flight(e: Enemy) -> void:
	var to_player := e.player.global_position - e.global_position
	var dist := to_player.length()
	if dist <= e.body_radius + 1.0:
		e.velocity = Vector3.ZERO
		try_melee_attack(e)
		return
	var fwd := to_player.normalized()
	var t := Time.get_ticks_msec() / 1000.0
	var wobble := Vector3(
		sin(t * 2.3 + e.wobble_seed.x) * 1.6,
		sin(t * 3.7 + e.wobble_seed.y) * 1.2,
		sin(t * 1.9 + e.wobble_seed.z) * 1.6
	)
	e.velocity = (fwd * e.speed) + wobble

static func _knight(e: Enemy, delta: float) -> void:
	e.knight_dash_timer -= delta
	e.knight_grab_cooldown -= delta

	var to_player := e.player.global_position - e.global_position
	to_player.y = 0.0
	var dist := to_player.length()

	var base_vel := Vector3.ZERO
	if dist > e.body_radius + 1.0:
		base_vel = to_player.normalized() * e.speed
	else:
		try_melee_attack(e)

	if e.knight_dash_timer <= 0.0:
		e.knight_dash_timer = randf_range(3.0, 5.0)
		var side := 1.0 if randf() < 0.5 else -1.0
		var perp := Vector3(-to_player.normalized().z, 0.0, to_player.normalized().x) * side
		e.knight_dash_velocity = perp * 22.0

	e.knight_dash_velocity *= exp(-6.0 * delta)
	e.velocity.x = base_vel.x + e.knight_dash_velocity.x
	e.velocity.z = base_vel.z + e.knight_dash_velocity.z

	if e.knight_grab_cooldown <= 0.0:
		try_grab_zombie(e)

## El Knight levanta un Hollow cercano y se lo tira al jugador. Público porque lo
## dispara a mano `tools/throw_test.tscn` para medir el arco.
static func try_grab_zombie(e: Enemy) -> void:
	for other in e.get_tree().get_nodes_in_group("enemy"):
		if other == e or not is_instance_valid(other) or other.dead:
			continue
		if other.enemy_type != "hollow" or other.thrown:
			continue
		if e.global_position.distance_to(other.global_position) > 4.5:
			continue
		e.knight_grab_cooldown = randf_range(4.5, 7.0)
		var to_player: Vector3 = (e.player.global_position - other.global_position)
		to_player.y = 0.0
		var dir: Vector3 = to_player.normalized() if to_player.length() > 0.01 else Vector3.FORWARD
		other.thrown = true
		other.thrown_timer = 1.6
		other.thrown_velocity = dir * 20.0 + Vector3.UP * 9.0
		other.global_position += Vector3.UP * 0.5
		return

## Vuelo balístico del enemigo lanzado. Se llama desde `_physics_process` ANTES
## del despacho por tipo: mientras vuela, el Hollow no piensa.
static func process_thrown(e: Enemy, delta: float) -> void:
	e.thrown_timer -= delta
	e.thrown_velocity.y -= Enemy.GRAVITY * delta
	e.velocity = e.thrown_velocity
	# Sólo cuenta como aterrizado si YA viene CAYENDO. Sin la condición de
	# `thrown_velocity.y < 0`, el lanzamiento se cancelaba en su primer frame:
	# `is_on_floor()` devuelve el resultado del `move_and_slide()` ANTERIOR, y en
	# ese momento el enemigo estaba parado en el piso. O sea que el Knight
	# agarraba al Hollow, lo levantaba 0.5 m y lo soltaba ahí mismo — el arco
	# balístico no ocurría nunca.
	if e.thrown_timer <= 0.0 or (e.thrown_velocity.y < 0.0 and e.is_on_floor()):
		e.thrown = false
		e.velocity = Vector3.ZERO

static func _capra(e: Enemy, delta: float) -> void:
	match e.capra_state:
		"frozen":
			e.velocity = Vector3.ZERO
			if _player_sees_me(e):
				e.capra_state = "charge"
		"charge":
			var to_player := e.player.global_position - e.global_position
			to_player.y = 0.0
			var dist := to_player.length()
			e.velocity.x = 0.0
			e.velocity.z = 0.0
			if dist > e.body_radius + 1.0:
				var dir := to_player.normalized()
				e.velocity.x = dir.x * e.speed * 1.3
				e.velocity.z = dir.z * e.speed * 1.3
			else:
				try_melee_attack(e)
			e.capra_jump_cooldown -= delta
			if dist <= 10.0 and e.capra_jump_cooldown <= 0.0:
				e.capra_state = "jump"
				e.capra_jump_cooldown = randf_range(3.5, 5.5)
				var dir := to_player.normalized() if to_player.length() > 0.01 else Vector3.FORWARD
				e.capra_jump_velocity = dir * 13.0 + Vector3.UP * 8.0
		"jump":
			e.capra_jump_velocity.y -= Enemy.GRAVITY * delta
			e.velocity = e.capra_jump_velocity
			if e.is_on_floor():
				e.capra_state = "landed"
				e.capra_landed_timer = 1.0
				if e.player and e.player.has_method("add_shake"):
					e.player.add_shake(3.0)
		"landed":
			e.capra_landed_timer -= delta
			var to_player := e.player.global_position - e.global_position
			to_player.y = 0.0
			if to_player.length() > 0.01:
				e.velocity.x = to_player.normalized().x * e.speed * 0.35
				e.velocity.z = to_player.normalized().z * e.speed * 0.35
			if e.capra_landed_timer <= 0.0:
				e.capra_state = "charge"

static func _player_sees_me(e: Enemy) -> bool:
	if not e.player.has_node("Camera3D"):
		return false
	var cam: Camera3D = e.player.get_node("Camera3D")
	var to_self := e.global_position - cam.global_position
	if to_self.normalized().dot(-cam.global_transform.basis.z) <= 0.0:
		return false
	return cam.is_position_in_frustum(e.global_position)

static func _sorceress(e: Enemy, delta: float) -> void:
	var to_player := e.player.global_position - e.global_position
	var dist := to_player.length()
	if dist > 20.0:
		e.velocity = to_player.normalized() * e.speed
	else:
		e.orbit_radius = lerp(e.orbit_radius, 17.0, 1.0 * delta)
		var tangential_speed := e.speed * 1.8
		e.orbit_angle += e.orbit_dir * (tangential_speed / max(e.orbit_radius, 1.0)) * delta
		var target := e.player.global_position + Vector3(cos(e.orbit_angle), 0.0, sin(e.orbit_angle)) * e.orbit_radius
		target.y = e.player.global_position.y + 1.5
		e.velocity = (target - e.global_position)

	e.skull_timer -= delta
	if e.skull_timer <= 0.0:
		e.skull_timer = randf_range(3.0, 4.5)
		_spawn_skull(e)

static func _spawn_skull(e: Enemy) -> void:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var skull = scene.instantiate()
	skull.enemy_type = "demon_skull"
	skull.counts_for_wave = false
	e.get_tree().current_scene.add_child(skull)
	skull.global_position = e.global_position

static func try_melee_attack(e: Enemy) -> void:
	if e.enemy_type == "sorceress":
		return
	if e.attack_timer <= 0.0 and e.player.has_method("take_damage"):
		e.player.take_damage(e.damage, e.global_position)
		e.attack_timer = e.atk_cd
		e.play_anim(Enemy.ANIM_ATTACK, false, 1.3)
