extends Node
## Prueba aislada en la ESCENA REAL: un solo enemigo, un solo disparo, por el
## camino de disparo del jugador (no instanciando balas a mano como hit_test).
## Sirve para separar "la bala no detecta" de "el jugador apunta mal".

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	GameState.change_state(GameState.State.PLAYING)
	var wm = get_tree().get_first_node_in_group("wave_manager")
	if wm:
		wm.set_process(false)  # sin oleadas: sólo el enemigo de la prueba
	var player = get_tree().get_first_node_in_group("player")
	await get_tree().physics_frame

	for dist in [3.0, 10.0, 30.0]:
		var e = load("res://scenes/enemy.tscn").instantiate()
		e.enemy_type = "hollow"
		get_tree().current_scene.add_child(e)
		e.global_position = player.global_position + Vector3(0.0, 0.0, -1.0) * dist + Vector3.UP * 0.6
		e.max_health = 100000.0
		e.health = 100000.0
		e.set_physics_process(false)  # que no camine ni se caiga
		await get_tree().physics_frame
		await get_tree().physics_frame

		var to: Vector3 = (e.global_position - player.camera.global_position).normalized()
		player.rotation.y = atan2(-to.x, -to.z)
		player.pitch = asin(clampf(to.y, -1.0, 1.0))
		player.camera.rotation.x = player.pitch
		player.camera.rotation.y = 0.0
		player.equip_weapon("pistol", GameData.Rarity.COMMON)

		var before: float = e.health
		var cam_dir: Vector3 = -player.camera.global_transform.basis.z
		player._do_shot(GameData.WEAPONS["pistol"], false, false)
		var dmg := 0.0
		for f in 30:
			await get_tree().physics_frame
			if not is_instance_valid(e):
				dmg = before  # murió: fue headshot
				break
			if e.health < before:
				dmg = before - e.health
				break
		print("dist %.0f m | dir cámara %s vs dir al enemigo %s (dot %.4f) | daño %.0f" % [
			dist, cam_dir, to, cam_dir.dot(to), dmg])
		if is_instance_valid(e):
			e.queue_free()
		await get_tree().process_frame
	get_tree().quit()
