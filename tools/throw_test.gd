extends Node
## Prueba puntual: ¿el Knight realmente ARROJA al Hollow?
##
## Pone un Knight y un Hollow pegados, con el jugador enfrente, fuerza el agarre
## y mide cuánto se desplazó el Hollow. Si el lanzamiento funciona tiene que
## volar varios metros hacia el jugador; si sale ~0, no despegó.
##
## Correr:  Godot --headless --path . tools/throw_test.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	GameState.change_state(GameState.State.PLAYING)
	var wm = get_tree().get_first_node_in_group("wave_manager")
	if wm:
		wm.set_process(false)
	var player = get_tree().get_first_node_in_group("player")
	await get_tree().physics_frame

	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var knight = scene.instantiate()
	knight.enemy_type = "knight"
	get_tree().current_scene.add_child(knight)
	knight.global_position = Vector3(0.0, knight.body_height * 0.5, -14.0)

	var hollow = scene.instantiate()
	hollow.enemy_type = "hollow"
	get_tree().current_scene.add_child(hollow)
	hollow.global_position = Vector3(1.5, hollow.body_height * 0.5, -14.0)
	hollow.max_health = 100000.0
	hollow.health = 100000.0

	# Que se asienten en el piso antes de medir.
	for f in 10:
		await get_tree().physics_frame
	var start: Vector3 = hollow.global_position
	print("jugador en %s | knight en %s | hollow en %s (a %.1f m del knight)" % [
		player.global_position, knight.global_position, start,
		knight.global_position.distance_to(start)])

	knight.knight_grab_cooldown = 0.0
	knight._try_grab_zombie()
	print("tras el agarre: thrown=%s  thrown_velocity=%s" % [hollow.thrown, hollow.thrown_velocity])

	var peak_y := start.y
	for f in 120:
		await get_tree().physics_frame
		if not is_instance_valid(hollow):
			break
		peak_y = maxf(peak_y, hollow.global_position.y)
	var moved: float = Vector2(hollow.global_position.x - start.x, hollow.global_position.z - start.z).length()
	# OJO con el umbral horizontal: el Hollow CAMINA a 3.8 u/s, así que en 2 s
	# recorre 7.6 m solo. Sin arco vertical, "se movió" no prueba nada — el bug
	# original daba 7.54 m de puro caminar y parecía un lanzamiento.
	var arc: float = peak_y - start.y
	print("recorrió %.2f m en horizontal, subió %.2f m (caminando solo haría ~7.6 m y 0 de altura)" % [moved, arc])
	print(">>> %s" % ("ARROJA BIEN" if moved > 12.0 and arc > 1.0 else "NO ARROJA"))
	get_tree().quit()
