extends CharacterBody3D
## Controlador del jugador: movimiento, las 10 armas + rareza, headshot, Railgun,
## Éxtasis, tech de salto cohete/escopeta. Ver secciones 2-5 de la especificación.
##
## La geometría del disparo (a dónde apunta la mira, dispersión, de dónde nace el
## proyectil, el haz del Railgun) vive en `ballistics.gd`; acá queda el MANEJO del
## arma: qué está equipado, munición, cadencia, spin-up y éxtasis.

const MOUSE_SENS_BASE := 1.0  # el sensible real viene de Config.mouse_sensitivity
const STAND_CAM_Y := 0.6
const CROUCH_CAM_Y := 0.2
## Por debajo de esto se considera que el jugador se cayó fuera del mapa.
## El piso vive entre Y -1 y 0, así que no hay forma de llegar acá jugando bien.
const FALL_RESCUE_Y := -6.0
const RECOIL_DECAY := 8.0
const SHAKE_DECAY := 12.0
const BOOST_DECAY := 5.0

## Spin-up (armas con `spinup` en GameData: SMG, LMG, Minigun).
## Manteniendo el gatillo, la cadencia Y el daño trepan de x1 a x5. Premia el
## fuego sostenido sobre las oleadas grandes, que es donde estas armas brillan.
const SPINUP_MAX := 5.0
const SPINUP_RAMP_TIME := 3.0   # segundos de fuego continuo para llegar al máximo
const SPINUP_DECAY_MULT := 2.5  # al soltar baja 2.5x más rápido de lo que subió

@onready var camera: Camera3D = $Camera3D

var weapon_view: Node3D
var ballistics: Ballistics

var pitch := 0.0
var health := GameData.MAX_HEALTH
var ecstasy := 0.0
var dead := false

var current_weapon := "pistol"
var current_rarity := GameData.Rarity.COMMON
var ammo := 0
var ammo_max := 0
var fire_timer := 0.0
var burst_cooldown := 0.0
var left_was_pressed := false
var spinup := 1.0  ## multiplicador actual de cadencia/daño (ver SPINUP_*)
var railgun_beam_remaining := 0.0
var railgun_boost_mult := 1.0
var railgun_boost_timer := 0.0

var recoil_pitch := 0.0
var recoil_yaw := 0.0
var screen_shake := 0.0
var move_boost := Vector3.ZERO

signal health_changed
signal ammo_changed
signal weapon_changed
signal ecstasy_changed
signal hit_confirmed(is_headshot: bool)
signal damage_taken(attacker_pos: Vector3)
signal kill_feed_entry(enemy_type: String, is_headshot: bool, is_alpha: bool)
signal died

func _ready() -> void:
	add_to_group("player")
	GameState.state_changed.connect(_on_state_changed)
	_on_state_changed(GameState.state)
	weapon_view = preload("res://scripts/features/player/weapon_view.gd").new()
	weapon_view.player = self
	# POV estilo Counter-Strike: arma bien pegada a la cámara, apoyada abajo a la
	# derecha. Z corto = cerca (si se aleja, "flota" en el medio de la pantalla).
	weapon_view.position = Vector3(0.20, -0.19, -0.28)
	camera.add_child(weapon_view)
	ballistics = Ballistics.new(self, camera)
	ballistics.muzzle_source = weapon_view
	equip_weapon("pistol", GameData.Rarity.COMMON)
	camera.fov = Config.fov

func _on_state_changed(new_state: int) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if new_state == GameState.State.PLAYING else Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	if dead:
		return

	var crouching := Input.is_key_pressed(KEY_CTRL)
	var sprinting := Input.is_key_pressed(KEY_SHIFT) and not crouching

	if not is_on_floor():
		velocity.y -= GameData.GRAVITY * delta
	elif Input.is_key_pressed(KEY_SPACE):
		velocity.y = GameData.JUMP_FORCE

	var input_dir := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	).normalized()
	var move_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var speed := GameData.PLAYER_SPEED
	if sprinting:
		speed *= GameData.SPRINT_MULT
	if crouching:
		speed *= GameData.CROUCH_MULT
	if current_weapon == "railgun":
		speed *= GameData.RAILGUN_SPEED_MULT
	if railgun_boost_timer > 0.0:
		speed *= railgun_boost_mult

	move_boost *= exp(-BOOST_DECAY * delta)
	velocity.x = move_dir.x * speed + move_boost.x
	velocity.z = move_dir.z * speed + move_boost.z

	camera.position.y = lerp(camera.position.y, CROUCH_CAM_Y if crouching else STAND_CAM_Y, 10.0 * delta)

	move_and_slide()
	_rescue_if_fell_off()

	if railgun_boost_timer > 0.0:
		railgun_boost_timer -= delta
		if railgun_boost_timer <= 0.0:
			railgun_boost_timer = 0.0
			railgun_boost_mult = 1.0

	recoil_pitch *= exp(-RECOIL_DECAY * delta)
	recoil_yaw *= exp(-RECOIL_DECAY * delta)
	screen_shake *= exp(-SHAKE_DECAY * delta)
	var shake_x := randf_range(-1.0, 1.0) * screen_shake * 0.01
	var shake_y := randf_range(-1.0, 1.0) * screen_shake * 0.01
	camera.rotation.x = pitch + recoil_pitch + shake_x
	camera.rotation.y = recoil_yaw + shake_y

	if GameState.state == GameState.State.PLAYING:
		_process_weapon(delta, sprinting, crouching)

## Red de seguridad del borde del mapa. El tech de salto de escopeta/cohete
## (sección 3.6) es deliberado y se puede ENCADENAR en el aire — cada disparo al
## piso vuelve a poner la velocidad vertical en 9.5 — así que tarde o temprano se
## pasa por encima del muro. Y afuera del muro no hay piso: se cae al vacío para
## siempre y la partida se pierde por un borde, no por los enemigos. Reportado
## jugando: "salté con el doble salto al lado del muro y me fui".
## No se le pone una pared invisible en el aire a propósito: el vuelo es lo
## divertido del tech. Se lo deja volar y se lo devuelve adentro cuando cae.
func _rescue_if_fell_off() -> void:
	if global_position.y > FALL_RESCUE_Y:
		return
	var limit := GameData.arena_radius - 2.0
	global_position = Vector3(
		clampf(global_position.x, -limit, limit),
		6.0,
		clampf(global_position.z, -limit, limit))
	velocity = Vector3.ZERO
	move_boost = Vector3.ZERO
	add_shake(8.0)

func add_shake(amount: float) -> void:
	screen_shake = min(screen_shake + amount, 40.0)

# --- armas ---

func equip_weapon(id: String, rarity: int) -> void:
	current_weapon = id
	current_rarity = rarity
	fire_timer = 0.0
	burst_cooldown = 0.0
	left_was_pressed = false
	spinup = 1.0  # el calentamiento no se hereda entre armas
	if id == "railgun":
		railgun_beam_remaining = GameData.RAILGUN_BEAM_DURATION
		ammo = 0
		ammo_max = 0
		add_shake(15.0)
	else:
		var w: Dictionary = GameData.WEAPONS[id]
		var base_ammo: int = w["ammo"]
		if w.get("fixed_ammo", false):
			ammo_max = base_ammo
		else:
			ammo_max = int(ceil(base_ammo * GameData.RARITY_AMMO_MULT[rarity]))
		ammo = ammo_max
	if weapon_view:
		weapon_view.set_weapon(id, rarity)
	weapon_changed.emit()
	ammo_changed.emit()

func _auto_cycle() -> void:
	var tier := GameData.ecstasy_autocycle_tier(ecstasy)
	var wid := GameData.random_weapon_for_rarity(tier)
	equip_weapon(wid, tier)

func try_spend_ecstasy() -> void:
	if current_weapon == "railgun" and ecstasy >= 100.0:
		var wid := GameData.random_weapon_for_rarity(GameData.Rarity.LEGENDARY)
		equip_weapon(wid, GameData.Rarity.LEGENDARY)
		ecstasy = 0.0
		ecstasy_changed.emit()
		return
	if ecstasy >= 100.0:
		equip_weapon("railgun", GameData.Rarity.LEGENDARY)
		ecstasy = 0.0
		ecstasy_changed.emit()
		return
	var tier := GameData.ecstasy_manual_tier(ecstasy)
	if tier == -1:
		return
	var wid := GameData.random_weapon_for_rarity(tier)
	equip_weapon(wid, tier)
	ecstasy = 0.0
	ecstasy_changed.emit()

func _process_weapon(delta: float, sprinting: bool, crouching: bool) -> void:
	if current_weapon == "railgun":
		_process_railgun(delta)
		return

	var w: Dictionary = GameData.WEAPONS[current_weapon]
	fire_timer -= delta
	burst_cooldown -= delta

	var held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	# Spin-up: sube mientras se sostenga el gatillo con munición, baja al soltar.
	var ramp := (SPINUP_MAX - 1.0) / SPINUP_RAMP_TIME
	if w.get("spinup", false) and held and ammo > 0:
		spinup = min(SPINUP_MAX, spinup + ramp * delta)
	else:
		spinup = max(1.0, spinup - ramp * SPINUP_DECAY_MULT * delta)

	if ammo > 0:
		if w.get("auto", false):
			if held and fire_timer <= 0.0:
				_do_shot(w, sprinting, crouching)
		else:
			if held and not left_was_pressed:
				if w.get("no_cooldown", false) or fire_timer <= 0.0:
					_do_shot(w, sprinting, crouching)
	left_was_pressed = held

	if current_weapon == "pistol" and ammo > 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and burst_cooldown <= 0.0:
		burst_cooldown = GameData.PISTOL_BURST_COOLDOWN
		for i in 3:
			if ammo <= 0:
				break
			ballistics.fire_pellets(w, GameData.weapon_damage(w, current_rarity, spinup),
				sprinting, crouching, _force_crit(), GameData.PISTOL_BURST_SPREAD_MULT)
			ammo -= 1
		ammo_changed.emit()
		_apply_recoil_and_shake(w)
		if ammo <= 0:
			_auto_cycle()

func _input(event: InputEvent) -> void:
	if GameState.state != GameState.State.PLAYING:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := Config.mouse_sensitivity
		rotate_y(-event.relative.x * sens)
		pitch = clamp(pitch - event.relative.y * sens, -1.4, 1.4)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G:
		try_spend_ecstasy()

func _process_railgun(delta: float) -> void:
	var firing := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and railgun_beam_remaining > 0.0
	if firing:
		railgun_beam_remaining = max(0.0, railgun_beam_remaining - delta)
		add_shake(0.3)
		ballistics.railgun_sweep()
		if railgun_beam_remaining <= 0.0:
			_railgun_exhaust()
	ammo_changed.emit()

func _railgun_exhaust() -> void:
	var xp := ecstasy
	var tier := GameData.ecstasy_autocycle_tier(xp)
	var wid := GameData.random_weapon_for_rarity(tier)
	equip_weapon(wid, tier)

	var heal_amount := xp * 0.5
	var actual_heal: float = min(heal_amount, GameData.MAX_HEALTH - health)
	health += actual_heal
	health_changed.emit()

	var overflow: float = heal_amount - actual_heal
	var speed_boost := 0.0
	if heal_amount > 0.0:
		speed_boost = 0.5 * (xp / 100.0) * (overflow / heal_amount)
	railgun_boost_mult = 1.0 + speed_boost
	railgun_boost_timer = 5.0

	ecstasy = 0.0
	ecstasy_changed.emit()

func _do_shot(w: Dictionary, sprinting: bool, crouching: bool) -> void:
	if not w.get("no_cooldown", false):
		# el spin-up acelera la cadencia: más multiplicador = menos espera
		var fr: float = w["fire_rate"] * (spinup if w.get("spinup", false) else 1.0)
		fire_timer = 1.0 / fr if fr > 0.0 else 0.0
	ammo -= 1
	ammo_changed.emit()
	_apply_recoil_and_shake(w)

	var dmg := GameData.weapon_damage(w, current_rarity, spinup)
	if w.get("explosive", false):
		ballistics.fire_rocket(w, dmg)
	else:
		ballistics.fire_pellets(w, dmg, sprinting, crouching, _force_crit())

	if ammo <= 0:
		_auto_cycle()

	_try_movement_tech()

## Escopeta disparada en el aire: cada perdigón pega crítico (mismo sistema que el
## headshot) — recompensa el salto de escopeta con daño a lo loco.
func _force_crit() -> bool:
	return current_weapon == "shotgun" and not is_on_floor()

func _apply_recoil_and_shake(w: Dictionary) -> void:
	var dmg: float = w["damage"]
	var kick := clampf(0.01 + dmg * 0.0003, 0.01, 0.08)
	recoil_pitch -= kick
	recoil_yaw += randf_range(-kick, kick) * 0.4
	add_shake(kick * 40.0)
	if weapon_view:
		weapon_view.on_fire()

func _try_movement_tech() -> void:
	if current_weapon != "shotgun" and current_weapon != "rocket":
		return
	if is_on_floor():
		return
	var look_dir := -camera.global_transform.basis.z
	if look_dir.y >= -0.35:
		return
	var from := camera.global_position
	if absf(look_dir.y) < 0.0001:
		return
	var t := -from.y / look_dir.y
	if t <= 0.0:
		return
	var impact := from + look_dir * t
	var horiz_dist := Vector2(impact.x - global_position.x, impact.z - global_position.z).length()
	if horiz_dist >= 6.0:
		return
	velocity.y = 9.5
	var horiz_dir := Vector3(look_dir.x, 0.0, look_dir.z).normalized()
	move_boost = horiz_dir * 14.0
	add_shake(4.0)

# --- daño / recompensas ---

func take_damage(amount: float, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	if dead:
		return
	health -= amount
	health_changed.emit()
	damage_taken.emit(attacker_pos)
	if health <= 0.0:
		health = 0.0
		health_changed.emit()
		_die()

func _die() -> void:
	dead = true
	died.emit()
	GameState.change_state(GameState.State.DEAD)

func grant_kill_reward(xp: int, regen: float, enemy_type: String = "", is_headshot: bool = false, is_alpha: bool = false) -> void:
	ecstasy = min(GameData.MAX_ECSTASY, ecstasy + xp)
	ecstasy_changed.emit()
	if not dead:
		health = min(GameData.MAX_HEALTH, health + regen)
		health_changed.emit()
	kill_feed_entry.emit(enemy_type, is_headshot, is_alpha)
