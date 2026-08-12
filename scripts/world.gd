extends Node3D
## Genera el mundo/arena en código (sin depender de nodos pre-armados en el .tscn):
## 20 obstáculos con semilla fija, paredes de la arena, luna + escombros por chaos_level.
## Ver sección 12 de la especificación.

const OBSTACLE_COUNT := 20
const OBSTACLE_SEED := 42
const KEEP_OUT_RADIUS := 5.0
const WALL_BASE_HEIGHT := 3.0
const WALL_MAX_EXTRA_HEIGHT := 6.0

const SKY_CALM_TOP := Color(0.05, 0.03, 0.08)
const SKY_CALM_HORIZON := Color(0.16, 0.08, 0.12)
const SKY_CHAOS_TOP := Color(0.25, 0.02, 0.03)
const SKY_CHAOS_HORIZON := Color(0.55, 0.08, 0.05)
const FOG_CALM := Color(0.15, 0.08, 0.12)
# rojo infernal pero no saturado: con el post-proceso nuevo (bloom + tonemap
# ACES) un rojo puro lavaba toda la escena y tapaba los modelos
const FOG_CHAOS := Color(0.34, 0.13, 0.11)

@onready var world_environment: WorldEnvironment = get_tree().current_scene.get_node("WorldEnvironment")

var walls_root: Node3D
var moon: MeshInstance3D
var debris_root: Node3D
var debris_pieces: Array = []
var moon_orbit_t := 0.0

func _ready() -> void:
	_generate_obstacles()
	_generate_walls()
	_generate_sky_rig()
	# DIFERIDO a propósito. El WaveManager está DESPUÉS de World en main.tscn y se
	# mete en su grupo recién en su propio _ready, así que buscarlo acá devolvía
	# una lista VACÍA y la conexión no se hacía nunca: el mundo jamás reaccionaba
	# al chaos_level. Ni el cielo, ni la niebla, ni la luna, ni los escombros, ni
	# la altura del muro — todo se quedaba en el estado de oleada 0 para siempre.
	# Se descubrió midiendo el muro en oleada 26: seguía en 3 m en vez de 8.
	_connect_wave_manager.call_deferred()
	_on_chaos_changed(0.0)

func _connect_wave_manager() -> void:
	var wms := get_tree().get_nodes_in_group("wave_manager")
	if wms.size() > 0:
		wms[0].chaos_changed.connect(_on_chaos_changed)

func _generate_obstacles() -> void:
	var root := Node3D.new()
	root.name = "Obstacles"
	add_child(root)

	var rng := RandomNumberGenerator.new()
	rng.seed = OBSTACLE_SEED
	for i in OBSTACLE_COUNT:
		var w := rng.randf_range(2.0, 6.0)
		var h := rng.randf_range(2.0, 8.0)
		var d := rng.randf_range(2.0, 6.0)
		var pos := Vector3.ZERO
		var attempts := 0
		while attempts < 50:
			var x := rng.randf_range(-GameData.ARENA_RADIUS + w, GameData.ARENA_RADIUS - w)
			var z := rng.randf_range(-GameData.ARENA_RADIUS + d, GameData.ARENA_RADIUS - d)
			pos = Vector3(x, h * 0.5, z)
			if Vector2(x, z).length() >= KEEP_OUT_RADIUS:
				break
			attempts += 1

		var body := StaticBody3D.new()
		body.position = pos
		root.add_child(body)

		var mesh_instance := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(w, h, d)
		box.subdivide_width = 3
		box.subdivide_height = 3
		box.subdivide_depth = 3
		mesh_instance.mesh = box
		var mat := StandardMaterial3D.new()
		# piedra húmeda: variación de tono por bloque para que no se lean todos
		# como el mismo cubo clonado, más specular para que el bloom/SSR peguen
		var tint := rng.randf_range(-0.03, 0.05)
		mat.albedo_color = Color(0.13 + tint, 0.11 + tint * 0.7, 0.14 + tint)
		mat.roughness = rng.randf_range(0.55, 0.8)
		mat.metallic = 0.08
		mat.metallic_specular = 0.4
		mat.uv1_scale = Vector3(w * 0.5, h * 0.5, d * 0.5)
		mesh_instance.set_surface_override_material(0, mat)
		body.add_child(mesh_instance)

		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(w, h, d)
		collision.shape = shape
		body.add_child(collision)

func _generate_walls() -> void:
	walls_root = Node3D.new()
	walls_root.name = "Walls"
	add_child(walls_root)

	var r := GameData.ARENA_RADIUS
	var configs := [
		{"pos": Vector3(0, 0, -r), "size": Vector3(r * 2, WALL_BASE_HEIGHT, 0.5)},
		{"pos": Vector3(0, 0, r), "size": Vector3(r * 2, WALL_BASE_HEIGHT, 0.5)},
		{"pos": Vector3(-r, 0, 0), "size": Vector3(0.5, WALL_BASE_HEIGHT, r * 2)},
		{"pos": Vector3(r, 0, 0), "size": Vector3(0.5, WALL_BASE_HEIGHT, r * 2)},
	]
	for cfg in configs:
		var body := StaticBody3D.new()
		body.position = cfg["pos"] + Vector3(0, cfg["size"].y * 0.5, 0)
		walls_root.add_child(body)

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		var box := BoxMesh.new()
		box.size = cfg["size"]
		mesh_instance.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.05, 0.08, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_instance.set_surface_override_material(0, mat)
		body.add_child(mesh_instance)

		var collision := CollisionShape3D.new()
		collision.name = "Col"
		var shape := BoxShape3D.new()
		shape.size = cfg["size"]
		collision.shape = shape
		body.add_child(collision)

func _generate_sky_rig() -> void:
	var rig := Node3D.new()
	rig.name = "SkyRig"
	add_child(rig)

	moon = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 6.0
	sphere.height = 12.0
	moon.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.08, 0.06)
	mat.emission_energy_multiplier = 1.5
	mat.albedo_color = Color(0.5, 0.05, 0.05)
	moon.set_surface_override_material(0, mat)
	moon.visible = false
	rig.add_child(moon)

	debris_root = Node3D.new()
	debris_root.name = "Debris"
	debris_root.visible = false
	rig.add_child(debris_root)
	for i in 10:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.4, 0.08, 0.4)
		m.mesh = box
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = Color(0.18, 0.14, 0.16)
		m.set_surface_override_material(0, dmat)
		debris_root.add_child(m)
		m.position = Vector3(randf_range(-45.0, 45.0), randf_range(15.0, 25.0), randf_range(-45.0, 45.0))
		debris_pieces.append(m)

func _process(delta: float) -> void:
	moon_orbit_t += delta * 0.02
	moon.position = Vector3(cos(moon_orbit_t), 0.0, sin(moon_orbit_t)) * 80.0 + Vector3(0.0, 40.0, 0.0)
	for m in debris_pieces:
		m.position.x += 0.5 * delta
		m.position.z += 0.15 * delta
		if m.position.x > 45.0:
			m.position.x = -45.0
		if m.position.z > 45.0:
			m.position.z = -45.0

func _on_chaos_changed(level: float) -> void:
	var f := clampf(level / 3.0, 0.0, 1.0)
	var env: Environment = world_environment.environment
	var sky_mat: ProceduralSkyMaterial = env.sky.sky_material
	sky_mat.sky_top_color = SKY_CALM_TOP.lerp(SKY_CHAOS_TOP, f)
	sky_mat.sky_horizon_color = SKY_CALM_HORIZON.lerp(SKY_CHAOS_HORIZON, f)
	# La niebla es de PROFUNDIDAD, no exponencial: transparente hasta
	# `fog_depth_begin` y opaca en `fog_depth_end` (20 y 30, en main.tscn). Es una
	# pared a distancia fija, que es lo que se buscaba — y es gratis, se calcula
	# por píxel en el fondo. Nada que ver con la niebla VOLUMÉTRICA, que es la que
	# hubo que sacar por costo (ver §3).
	# Acá sólo cambia el COLOR con el caos; `fog_density` en modo profundidad es un
	# multiplicador global y se deja quieto en 1.0.
	env.fog_light_color = FOG_CALM.lerp(FOG_CHAOS, f)

	for wall in walls_root.get_children():
		var mesh_instance: MeshInstance3D = wall.get_node("Mesh")
		var box: BoxMesh = mesh_instance.mesh
		var h := WALL_BASE_HEIGHT + WALL_MAX_EXTRA_HEIGHT * f
		box.size.y = h
		# La COLISIÓN tiene que crecer con la pared. Antes sólo crecía la malla:
		# a oleada alta el muro se veía de 9 m pero seguía frenando hasta 3 m,
		# o sea que se podía pasar por encima de algo que se ve macizo.
		var col: CollisionShape3D = wall.get_node("Col")
		var col_box: BoxShape3D = col.shape
		col_box.size.y = h
		# Y la base tiene que quedar apoyada en el piso: el cuerpo estaba centrado
		# en 1.5 fijo, así que al crecer la pared también se hundía hacia abajo.
		wall.position.y = h * 0.5

	debris_root.visible = level > 0.5
	moon.visible = level > 1.0
