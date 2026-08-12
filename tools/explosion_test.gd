extends Node3D
## Herramienta: dispara varias explosiones seguidas y guarda un PNG de cada una
## en distintos momentos, para verificar que el feedback visual se ve (y que la
## segunda explosión no queda invisible por materiales compartidos — bug real
## que tuvo este sistema).
##
## Correr SIN --headless:  Godot --path . tools/explosion_test.tscn

func _ready() -> void:
	# El autoload GameState arranca en TITLE y eso deja `get_tree().paused = true`.
	# Sin esto los Tween no avanzan y la explosión queda congelada en su primer
	# frame (pasó: las capturas salían todas idénticas).
	GameState.change_state(GameState.State.PLAYING)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.08, 0.1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.5
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.glow_bloom = 0.2
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	add_child(env)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	floor_mesh.mesh = plane
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.3, 0.28, 0.27)
	floor_mesh.set_surface_override_material(0, fmat)
	add_child(floor_mesh)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 6, 20)
	cam.rotation_degrees = Vector3(-12, 0, 0)
	cam.current = true
	add_child(cam)

	DirAccess.make_dir_recursive_absolute("user://explosion_test")
	# dos explosiones seguidas: la segunda es la que detectaría el bug de
	# materiales compartidos
	for round_i in 2:
		FxManager.spawn_explosion(Vector3(0, 0.5, 0), GameData.ROCKET_EXPLOSION_RADIUS)
		for shot in 4:
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png("user://explosion_test/r%d_f%d.png" % [round_i, shot])
		await get_tree().create_timer(0.8).timeout
	print("[EXPL] listo: ", ProjectSettings.globalize_path("user://explosion_test/"))
	get_tree().quit()
