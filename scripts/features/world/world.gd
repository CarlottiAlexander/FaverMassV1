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

## Perfil del mapa en uso. Los defaults son los valores que estaban hardcodeados
## acá arriba, así que sin mods la arena sale idéntica.
var perfil: Dictionary = MapProfile.DEFECTO

var walls_root: Node3D
var moon: MeshInstance3D
var debris_root: Node3D
var debris_pieces: Array = []
var moon_orbit_t := 0.0

func _ready() -> void:
	perfil = ModManager.map_profile()
	GameData.arena_radius = float(perfil["arena_radius"])
	_apply_floor()
	_apply_fog()
	_generate_obstacles()
	_generate_walls()
	_generate_sky_rig()
	# El caos vive en el autoload `GameState`, que SIEMPRE existe.
	#
	# ANTES se buscaba al WaveManager por grupo y había que diferir la conexión,
	# porque está DESPUÉS de World en main.tscn y todavía no se había metido en su
	# grupo: la lista salía vacía, la conexión no se hacía NUNCA, y el mundo se
	# quedaba en estado de oleada 0 para siempre — sin cielo rojo, sin niebla
	# espesa, sin luna y con los muros bajos. Ese bug vivió toda la vida del
	# proyecto y se descubrió midiendo el muro en la oleada 26. Con un autoload no
	# puede volver a pasar, y además un modo sin oleadas puede manejar la atmósfera.
	GameState.chaos_changed.connect(_on_chaos_changed)
	_on_chaos_changed(GameState.chaos_level)

## El piso vive en `main.tscn`, no acá, así que se resuelve por la escena actual —
## mismo patrón que `world_environment`.
##
## ⚠ Hay que DUPLICAR la malla y el material antes de tocarlos: son sub-recursos
## del `.tscn`, que Godot cachea y reinstancia desde el mismo `PackedScene`. Sin
## duplicar, el color de un mapa se quedaría pegado entre partidas y al volver al
## mapa por defecto el piso seguiría del color anterior. Es la misma trampa que ya
## mordió con los materiales de la explosión y con los meshes de los enemigos.
func _apply_floor() -> void:
	var escena := get_tree().current_scene
	if not escena.has_node("Floor/MeshInstance3D"):
		return
	var mi: MeshInstance3D = escena.get_node("Floor/MeshInstance3D")
	var col: Array = perfil["floor"]["color"]

	# El piso se agranda con la arena, si no un mapa grande deja al jugador
	# caminando sobre el vacío.
	if mi.mesh is BoxMesh:
		var m: BoxMesh = mi.mesh.duplicate()
		m.size.x = GameData.arena_radius * 2.0
		m.size.z = GameData.arena_radius * 2.0
		mi.mesh = m
	if escena.has_node("Floor/CollisionShape3D"):
		var cs: CollisionShape3D = escena.get_node("Floor/CollisionShape3D")
		if cs.shape is BoxShape3D:
			var sh: BoxShape3D = cs.shape.duplicate()
			sh.size.x = GameData.arena_radius * 2.0
			sh.size.z = GameData.arena_radius * 2.0
			cs.shape = sh

	if col.is_empty():
		return
	var mat := mi.get_surface_override_material(0)
	if mat == null:
		mat = mi.mesh.surface_get_material(0)
	if mat == null:
		return
	var m2: StandardMaterial3D = mat.duplicate()
	m2.albedo_color = MapProfile.color_of(col)
	mi.set_surface_override_material(0, m2)

## La niebla es de PROFUNDIDAD y vive en `main.tscn`.
##
## ⚠ Va ATADA al corte de dibujado de los enemigos: el culleo es SECO, sin fundido,
## y sólo no se nota porque a esa distancia la niebla ya es opaca. Un mapa que
## corre la niebla más lejos sin correr el LOD haría que los enemigos aparezcan de
## la nada en el aire. Por eso se mueven juntos y no por separado.
func _apply_fog() -> void:
	var env: Environment = world_environment.environment
	var fg: Dictionary = perfil["fog"]
	env.fog_depth_begin = float(fg["begin"])
	env.fog_depth_end = float(fg["end"])
	GameData.enemy_lod_distance = float(fg["end"]) + 2.0

func _generate_obstacles() -> void:
	var root := Node3D.new()
	root.name = "Obstacles"
	add_child(root)

	var ob: Dictionary = perfil["obstacles"]
	var s_min := float(ob["size_min"])
	var s_max := float(ob["size_max"])
	var keep_out := float(ob["keep_out"])

	var rng := RandomNumberGenerator.new()
	rng.seed = int(ob["seed"])
	for i in int(ob["count"]):
		var w := rng.randf_range(s_min, s_max)
		var h := rng.randf_range(float(ob["height_min"]), float(ob["height_max"]))
		var d := rng.randf_range(s_min, s_max)
		var pos := Vector3.ZERO
		var attempts := 0
		while attempts < 50:
			var x := rng.randf_range(-GameData.arena_radius + w, GameData.arena_radius - w)
			var z := rng.randf_range(-GameData.arena_radius + d, GameData.arena_radius - d)
			pos = Vector3(x, h * 0.5, z)
			if Vector2(x, z).length() >= keep_out:
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
		# Piedra oscura sobre piso oscuro: reportado jugando, no se veía dónde
		# empezaba un bloque hasta chocarlo. La emisión es MUY baja a propósito —
		# alcanza para separar el volumen del fondo sin convertir el obstáculo en
		# una lámpara ni aplanar el sombreado. El contorno lo dibuja el `rim`, que
		# es lo que realmente lo DELIMITA: se enciende en los bordes vistos de
		# canto, justo donde termina la silueta.
		# Emisión y no una OmniLight por bloque: 20 luces con sombra costarían más
		# que todo el resto del mundo junto.
		mat.emission_enabled = true
		mat.emission = Color(0.42, 0.16, 0.20)
		mat.emission_energy_multiplier = 0.35
		mat.rim_enabled = true
		mat.rim = 0.55
		mat.rim_tint = 0.3
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

	var r := GameData.arena_radius
	var wh := float(perfil["walls"]["base_height"])
	var configs := [
		{"pos": Vector3(0, 0, -r), "size": Vector3(r * 2, wh, 0.5)},
		{"pos": Vector3(0, 0, r), "size": Vector3(r * 2, wh, 0.5)},
		{"pos": Vector3(-r, 0, 0), "size": Vector3(0.5, wh, r * 2)},
		{"pos": Vector3(r, 0, 0), "size": Vector3(0.5, wh, r * 2)},
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
		# El muro casi no se veía: con alpha 0.35 y un rojo oscuro se confundía con
		# el fondo, y se llegaba al borde de la arena sin saberlo. Ahora emite, así
		# que marca el límite por sí mismo.
		# El valor está MEDIDO con capturas, no elegido a ojo: al mezclar en alpha
		# el color emitido se escala por el alpha, así que la energía útil es
		# ~0.35 de la nominal. Con 3.0 el muro salía como una franja de neón que
		# blanqueaba media pantalla; 0.85 deja un rojo apagado que se lee contra
		# el fondo negro sin encandilar.
		mat.emission_enabled = true
		mat.emission = Color(0.85, 0.12, 0.15)
		mat.emission_energy_multiplier = 0.85
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
	sky_mat.sky_top_color = MapProfile.color_of(perfil["sky"]["calm_top"]).lerp(MapProfile.color_of(perfil["sky"]["chaos_top"]), f)
	sky_mat.sky_horizon_color = MapProfile.color_of(perfil["sky"]["calm_horizon"]).lerp(MapProfile.color_of(perfil["sky"]["chaos_horizon"]), f)
	# La niebla es de PROFUNDIDAD, no exponencial: transparente hasta
	# `fog_depth_begin` y opaca en `fog_depth_end` (20 y 30, en main.tscn). Es una
	# pared a distancia fija, que es lo que se buscaba — y es gratis, se calcula
	# por píxel en el fondo. Nada que ver con la niebla VOLUMÉTRICA, que es la que
	# hubo que sacar por costo (ver §3).
	# Acá sólo cambia el COLOR con el caos; `fog_density` en modo profundidad es un
	# multiplicador global y se deja quieto en 1.0.
	env.fog_light_color = MapProfile.color_of(perfil["fog"]["calm"]).lerp(MapProfile.color_of(perfil["fog"]["chaos"]), f)

	for wall in walls_root.get_children():
		var mesh_instance: MeshInstance3D = wall.get_node("Mesh")
		var box: BoxMesh = mesh_instance.mesh
		var h := float(perfil["walls"]["base_height"]) + float(perfil["walls"]["extra_height"]) * f
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
	moon.visible = level > 1.0 and bool(perfil["moon"]["enabled"])
