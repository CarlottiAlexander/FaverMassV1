extends Node
## Fotos de las cuatro pantallas de UI (título, opciones, juego, pausa) a user://ui/.
## El soak headless NO sirve para esto: carga los scripts sin rasterizar, así que
## un HUD entero fuera de pantalla le pasa por al lado. Con esta herramienta se
## detectó que anclar un Control YA agregado al árbol lo deja de tamaño 0
## (ver la nota en `scripts/features/ui/hud.gd`).
##
## Correr SIN --headless (headless no rasteriza).

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute("user://ui")

	await _shot("titulo")

	GameState.open_options(GameState.State.TITLE)
	await _shot("opciones")

	GameState.close_options()
	GameState.start_run()
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.health = 22.0
		player.ecstasy = 60.0
		player.health_changed.emit()
		player.ecstasy_changed.emit()
	await get_tree().create_timer(3.0).timeout
	await _shot("juego")

	GameState.change_state(GameState.State.PAUSED)
	await _shot("pausa")

	get_tree().quit()

func _shot(name: String) -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://ui/%s.png" % name)
	print("guardada %s" % name)
