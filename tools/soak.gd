extends Node
## Herramienta de estrés: corre el juego REAL en oleada alta, apuntando y
## disparando al enemigo más cercano en cada frame. Sirve para detectar errores
## de script que sólo aparecen con todos los sistemas andando a la vez (oleadas,
## IA de los 8 tipos, gibs, explosiones, auto-ciclo de armas, éxtasis).
##
## Correr:  Godot --headless --path . tools/soak.tscn
## Ojo: headless NO prueba mouse/teclado ni nada visual — sólo que no reviente.
##
## `soak.tscn` es una INSTANCIA de main.tscn con este driver colgado como hijo,
## no una escena aparte que carga main. Tiene que ser así: varios scripts
## (world.gd) resuelven nodos vía `get_tree().current_scene`, y cargar main como
## hijo de otra escena deja ese puntero apuntando al lugar equivocado. Cambiar de
## escena con change_scene_to_file() tampoco sirve: libera al propio driver.

const FRAMES := 1800
const START_WAVE := 24  # arranca la 25 enseguida

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	GameState.change_state(GameState.State.PLAYING)

	var wm = get_tree().get_first_node_in_group("wave_manager")
	var player = get_tree().get_first_node_in_group("player")
	if not player or not wm:
		print("SOAK: no se encontró jugador o wave_manager")
		get_tree().quit()
		return
	wm.wave = START_WAVE
	wm.announce_timer = 0.1

	var peak := 0
	var shots := 0
	# Diccionario y no un int suelto: las lambdas de GDScript capturan las
	# variables locales por VALOR, así que `hits += 1` adentro de la lambda
	# incrementaba una copia y el contador de afuera quedaba siempre en 0.
	var tally := {"hits": 0}
	player.hit_confirmed.connect(func(_hs): tally["hits"] += 1)
	for f in FRAMES:
		await get_tree().physics_frame
		# Jugador inmortal: acá interesa el motor, no si sobrevive la oleada 25
		# parado en el medio del mapa.
		player.health = GameData.MAX_HEALTH
		var enemies := get_tree().get_nodes_in_group("enemy")
		peak = maxi(peak, enemies.size())
		var target: Node3D = null
		var best := INF
		for e in enemies:
			if not is_instance_valid(e) or e.dead:
				continue
			var d: float = player.global_position.distance_squared_to(e.global_position)
			if d < best:
				best = d
				target = e
		if target:
			var to: Vector3 = (target.global_position - player.camera.global_position).normalized()
			player.rotation.y = atan2(-to.x, -to.z)
			player.pitch = asin(clampf(to.y, -1.0, 1.0))
			player.camera.rotation.x = player.pitch
		# A mitad de camino se fuerza el Railgun: nunca sale del pool aleatorio, así
		# que si no se equipa a mano su haz continuo no se ejercita nunca.
		if f == FRAMES / 2:
			player.equip_weapon("railgun", GameData.Rarity.LEGENDARY)
		if player.current_weapon == "railgun":
			if player.railgun_beam_remaining > 0.0:
				player.railgun_beam_remaining = maxf(0.0, player.railgun_beam_remaining - get_physics_process_delta_time())
				player.ballistics.railgun_sweep()
				if player.railgun_beam_remaining <= 0.0:
					player._railgun_exhaust()
		elif player.ammo > 0 and player.fire_timer <= 0.0 and f % 6 == 0:
			# Con cadencia: llamar _do_shot todos los frames dispara 60 veces por
			# segundo, algo que ninguna arma permite, y satura el screen shake
			# (±9° de bamboleo de cámara) — el porcentaje de acierto que salía de
			# ahí no medía las hitboxes, medía el temblor.
			player._do_shot(GameData.WEAPONS[player.current_weapon], false, false)
			shots += 1

	# El muro crece con el chaos_level: la malla y la COLISIÓN tienen que medir lo
	# mismo y quedar apoyadas en el piso. Antes sólo crecía la malla y el muro se
	# veía de 9 m frenando hasta 3 m.
	var walls = get_tree().current_scene.get_node_or_null("World/Walls")
	if walls and walls.get_child_count() > 0:
		var w = walls.get_child(0)
		var mh: float = (w.get_node("Mesh").mesh as BoxMesh).size.y
		var ch: float = (w.get_node("Col").shape as BoxShape3D).size.y
		print("MURO: malla %.2f | colisión %.2f | base en Y %.2f  -> %s" % [
			mh, ch, w.position.y - ch * 0.5,
			"OK" if is_equal_approx(mh, ch) and absf(w.position.y - ch * 0.5) < 0.01 else "DESAJUSTADO"])

	print("SOAK ok: %d frames | oleada %d | pico %d enemigos vivos | %d disparos, %d impactos (%.0f%%) | kills %d (headshots %d)" % [
		FRAMES, wm.wave, peak, shots, tally["hits"], 100.0 * tally["hits"] / maxi(shots, 1),
		GameState.run_kills, GameState.run_headshots])
	get_tree().quit()
