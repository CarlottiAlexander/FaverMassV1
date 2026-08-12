extends Node3D
## Herramienta: renderiza el viewmodel de cada arma desde la MISMA cámara que
## usa el jugador y guarda un PNG por arma en user://weapon_pov/.
##
## Existe porque capturar la pantalla de Windows no sirve cuando hay otra
## ventana encima (o el usuario está usando la máquina): acá el juego se
## fotografía a sí mismo desde su propio framebuffer, así que no importa qué
## haya arriba. Correr con:
##   Godot --path . tools/weapon_pov.tscn
## (SIN --headless: headless no rasteriza nada.)

const WEAPONS := ["pistol", "revolver", "smg", "ak47", "shotgun",
	"sniper", "lmg", "minigun", "railgun", "rocket"]

var weapon_view: Node3D
var camera: Camera3D

func _ready() -> void:
	# Suelo y fondo neutro para que se lea la silueta del arma
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.3
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.4
	add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, -1.7, 0)
	add_child(floor_mesh)

	# Cámara igual a la del jugador (mismo FOV y altura)
	camera = Camera3D.new()
	camera.fov = GameData.fov
	camera.current = true
	add_child(camera)

	# Mismo viewmodel y misma posición que player.gd
	weapon_view = preload("res://scripts/weapon_view.gd").new()
	weapon_view.position = Vector3(0.20, -0.19, -0.28)
	camera.add_child(weapon_view)

	await _capture_all()

func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute("user://weapon_pov")
	for id in WEAPONS:
		weapon_view.set_weapon(id, GameData.Rarity.COMMON)
		# esperar a que el frame con el arma nueva esté realmente dibujado
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "user://weapon_pov/%s.png" % id
		img.save_png(path)
		print("[POV] guardado: ", ProjectSettings.globalize_path(path))
	print("[POV] listo")
	get_tree().quit()
