extends Node
## Saca fotos del juego a distintos niveles de caos para ver la pared de niebla.
## El JUEGO se auto-fotografía (ver §3 del CLAUDE.md): no se captura la pantalla
## de Windows, así que no importa qué ventana esté adelante ni se le roba el foco
## a nadie.
##
## Correr SIN --headless (headless no rasteriza):
##   Godot_v4.6.3-stable_win64_console.exe --path . tools/fog_shot.tscn
## Las imágenes quedan en user://fog/  (%APPDATA%\Godot\app_userdata\Faver Mass v1)

const CHAOS_LEVELS := [0.0, 1.5, 3.0]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	GameState.change_state(GameState.State.PLAYING)
	var wm = get_tree().get_first_node_in_group("wave_manager")
	if wm:
		wm.set_process(false)
	var world = get_tree().current_scene.get_node_or_null("World")
	var player = get_tree().get_first_node_in_group("player")
	DirAccess.make_dir_recursive_absolute("user://fog")

	# Fila de enemigos a distancias conocidas, para leer en la foto dónde los
	# come la niebla y dónde los corta el culleo.
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	# En diagonal para que no se tapen entre ellos, y arrancando lejos: uno a 8 m
	# tapa toda la pantalla y no deja ver la niebla, que es lo que se quiere mirar.
	var slot := 0
	for d in [12.0, 18.0, 24.0, 30.0, 36.0, 44.0]:
		var e = scene.instantiate()
		e.enemy_type = "hollow"
		get_tree().current_scene.add_child(e)
		e.global_position = Vector3(-5.0 + slot * 2.0, e.body_height * 0.5 + 0.05, -d)
		e.set_physics_process(false)  # que no camine ni gire
		slot += 1
	player.rotation.y = 0.0
	player.camera.rotation = Vector3.ZERO

	print("jugador en %s, cámara en %s, fov %.1f, viewport %s" % [
		player.global_position, player.camera.global_position, player.camera.fov,
		get_viewport().get_visible_rect().size])
	for e in get_tree().get_nodes_in_group("enemy"):
		print("  enemigo %s en %s (dist %.2f)" % [
			e.enemy_type, e.global_position, e.global_position.distance_to(player.camera.global_position)])

	var env: Environment = get_tree().current_scene.get_node("WorldEnvironment").environment
	print("niebla: modo %d | begin %.1f | end %.1f | densidad %.2f | sky_affect %.2f" % [
		env.fog_mode, env.fog_depth_begin, env.fog_depth_end, env.fog_density, env.fog_sky_affect])

	for level in CHAOS_LEVELS:
		if world:
			world._on_chaos_changed(level)
		# Un segundo de reloj antes de cada foto: con la lectura de framebuffer
		# el juego cae a 1-2 FPS y capturar enseguida agarraba frames a medio
		# componer (salían negras).
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://fog/caos_%.1f.png" % level)
		print("guardada caos_%.1f (color de niebla %s)" % [level, env.fog_light_color])
	get_tree().quit()
