class_name EnemyModelProcedural
extends RefCounted
## Modelos armados POR CÓDIGO con piezas simples (cajas/cápsulas/conos): una
## silueta reconocible por tipo en vez de una cápsula genérica. Es el camino de
## respaldo para los tipos que no tienen `.glb` propio (ver `enemy_model_import.gd`).
##
## No es un port de la geometría procedural de FaverMass (esa vive en renderer.cpp,
## sombreada a mano en CPU porque raylib no emite normales para primitivas — acá
## Godot ilumina de verdad, no hace falta ese workaround), es una traducción
## liviana del mismo plan corporal por tipo.
##
## TODO ACÁ ES ESTÁTICO Y NO SABE QUE EXISTE `Enemy`: se le pasan el nodo raíz y
## las tres medidas del cuerpo, y devuelve un diccionario con los pivotes que hay
## que animar. Esa es la razón de que sea un archivo aparte y no un pedazo de
## `enemy.gd`: se puede llamar desde una herramienta (`tools/enemy_gallery.tscn`)
## sin instanciar un enemigo con IA, física y grupo.

## Claves del diccionario que devuelve `build()`. Las que un tipo no tenga
## simplemente no aparecen (un murciélago no tiene piernas). `enemy.gd` las lee
## con `.get(clave, null)`.
const PIVOTS := [
	"l_arm", "r_arm", "l_leg", "r_leg", "l_leg2", "r_leg2",
	"l_wing", "r_wing", "head", "jaw", "tail",
]

enum Surf { FLESH, BONE, METAL, CLOTH, HORN }

## Materiales PBR compartidos por (color, tipo-de-superficie) — se cachean para
## no crear un StandardMaterial3D nuevo por cada pieza de cada enemigo (una
## oleada 25 con 100+ enemigos de ~20 piezas cada uno serían miles de
## materiales únicos, y cada material único es un draw call que no se batchea).
static var _mat_cache: Dictionary = {}

## Arma el modelo de `type` colgado de `root` y devuelve los pivotes animables.
## `h`/`w`/`hr` son alto, radio y radio de cabeza del cuerpo YA resueltos por
## `enemy.gd` (tabla de GameData + multiplicadores de alpha).
static func build(type: String, root: Node3D, col: Color, h: float, w: float, hr: float) -> Dictionary:
	match type:
		"hollow":
			return _humanoid(root, col, h, w, hr, 0.0, false)
		"thrall":
			return _humanoid(root, col, h, w, hr, 14.0, false)
		"blood_lord":
			return _humanoid(root, col, h, w, hr, 0.0, true)
		"knight":
			return _knight(root, col, h, w, hr)
		"dire_bat":
			return _bat(root, col, h, w)
		"capra":
			return _capra(root, col, h, w, hr)
		"sorceress":
			return _witch(root, col, h, w, hr)
		"demon_skull":
			return _skull(root, col, hr)
	return _humanoid(root, col, h, w, hr, 0.0, false)

# --- primitivas -------------------------------------------------------------

static func surface_material(color: Color, surf: int) -> StandardMaterial3D:
	var key := "%s_%d" % [color.to_html(), surf]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	match surf:
		Surf.FLESH:
			mat.roughness = 0.62
			mat.metallic = 0.0
			mat.metallic_specular = 0.42
			mat.clearcoat_enabled = true
			mat.clearcoat = 0.25
			mat.clearcoat_roughness = 0.55
			mat.rim_enabled = true
			mat.rim = 0.35
			mat.rim_tint = 0.4
		Surf.BONE:
			mat.roughness = 0.45
			mat.metallic = 0.0
			mat.metallic_specular = 0.55
		Surf.METAL:
			mat.roughness = 0.34
			mat.metallic = 0.92
			mat.metallic_specular = 0.85
		Surf.CLOTH:
			mat.roughness = 0.95
			mat.metallic = 0.0
			mat.metallic_specular = 0.12
			mat.rim_enabled = true
			mat.rim = 0.5
			mat.rim_tint = 0.7
		Surf.HORN:
			mat.roughness = 0.38
			mat.metallic = 0.15
			mat.metallic_specular = 0.6
	_mat_cache[key] = mat
	return mat

static func part(mesh: Mesh, pos: Vector3, color: Color, rot_deg: Vector3, parent: Node3D, surf: int = Surf.FLESH) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, surface_material(color, surf))
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

static func box(size: Vector3, pos: Vector3, color: Color, parent: Node3D, rot_deg: Vector3 = Vector3.ZERO, surf: int = Surf.FLESH) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	# subdividir da vértices para que SSAO/SSIL y las luces tengan dónde variar
	m.subdivide_width = 2
	m.subdivide_height = 2
	m.subdivide_depth = 2
	return part(m, pos, color, rot_deg, parent, surf)

static func sphere(radius: float, pos: Vector3, color: Color, parent: Node3D, surf: int = Surf.FLESH) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 32
	m.rings = 16
	return part(m, pos, color, Vector3.ZERO, parent, surf)

static func limb(radius: float, length: float, pos: Vector3, color: Color, parent: Node3D, rot_deg: Vector3 = Vector3.ZERO, surf: int = Surf.FLESH) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = max(length, radius * 2.0 + 0.01)
	m.radial_segments = 24
	m.rings = 8
	return part(m, pos, color, rot_deg, parent, surf)

static func cone(radius: float, height: float, pos: Vector3, color: Color, parent: Node3D, rot_deg: Vector3 = Vector3.ZERO, surf: int = Surf.HORN) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 20
	m.rings = 4
	return part(m, pos, color, rot_deg, parent, surf)

static func pivot(pos: Vector3, parent: Node3D) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p

# --- cuerpos por tipo -------------------------------------------------------

static func _humanoid(root: Node3D, col: Color, H: float, W: float, HR: float, lean_deg: float, caped: bool) -> Dictionary:
	var piv := {}
	var dark := col.darkened(0.25)
	var bone := Color(0.75, 0.7, 0.6)

	root.rotation_degrees.x = -lean_deg

	# piernas
	piv["l_leg"] = pivot(Vector3(-W * 0.32, H * 0.46, 0.0), root)
	limb(W * 0.11, H * 0.46, Vector3(0.0, -H * 0.23, 0.0), dark, piv["l_leg"])
	piv["r_leg"] = pivot(Vector3(W * 0.32, H * 0.46, 0.0), root)
	limb(W * 0.11, H * 0.46, Vector3(0.0, -H * 0.23, 0.0), dark, piv["r_leg"])

	# torso
	limb(W * 0.34, H * 0.42, Vector3(0.0, H * 0.72, 0.0), col, root)

	# costillas expuestas — piel estirada sobre el hueso (Hollow/Thrall gaunt; el
	# vampiro las tapa con la capa, no hacen falta ahí)
	if not caped:
		for i in 3:
			var ry := H * (0.62 + i * 0.075)
			box(Vector3(W * 0.5, H * 0.03, W * 0.08), Vector3(0.0, ry, W * 0.16), bone, root, Vector3.ZERO, Surf.BONE)

	# brazos (siempre un poco extendidos hacia adelante — la pose "reaching" del Hollow)
	piv["l_arm"] = pivot(Vector3(-W * 0.42, H * 0.86, 0.0), root)
	limb(W * 0.09, H * 0.40, Vector3(0.0, -H * 0.20, W * 0.05), col, piv["l_arm"], Vector3(60, 0, 0))
	piv["r_arm"] = pivot(Vector3(W * 0.42, H * 0.86, 0.0), root)
	limb(W * 0.09, H * 0.40, Vector3(0.0, -H * 0.20, W * 0.05), col, piv["r_arm"], Vector3(60, 0, 0))

	# cabeza
	piv["head"] = pivot(Vector3(0.0, H * 0.97, 0.0), root)
	sphere(HR, Vector3.ZERO, col, piv["head"])
	sphere(HR * 0.28, Vector3(-HR * 0.5, HR * 0.1, HR * 0.85), Color(0.02, 0.02, 0.02), piv["head"])
	sphere(HR * 0.28, Vector3(HR * 0.5, HR * 0.1, HR * 0.85), Color(0.02, 0.02, 0.02), piv["head"])

	# mandíbula colgando, se abre y cierra (ver el bamboleo en `enemy.gd`)
	piv["jaw"] = pivot(Vector3(0.0, -HR * 0.35, HR * 0.55), piv["head"])
	box(Vector3(HR * 0.7, HR * 0.22, HR * 0.5), Vector3(0.0, -HR * 0.1, HR * 0.15), dark, piv["jaw"])

	if caped:
		# capa: varios paneles angulados en vez de una sola placa plana, más
		# collar — el vampiro banca (roll) todo el cuerpo al caminar
		var cape_col := dark.darkened(0.3)
		for i in 3:
			var a := float(i - 1) * 12.0
			box(Vector3(W * 0.55, H * 0.6, 0.05), Vector3(sin(deg_to_rad(a)) * W * 0.3, H * 0.6, -W * 0.32), cape_col, root, Vector3(0.0, a, 0.0), Surf.CLOTH)
		box(Vector3(W * 0.5, H * 0.08, W * 0.2), Vector3(0.0, H * 0.9, -W * 0.15), cape_col, root, Vector3.ZERO, Surf.CLOTH)
	return piv

static func _knight(root: Node3D, col: Color, H: float, W: float, HR: float) -> Dictionary:
	var piv := {}
	var metal := Color(0.35, 0.36, 0.4)
	var rust := Color(0.4, 0.18, 0.08)
	var dark_metal := Color(0.12, 0.12, 0.14)

	piv["l_leg"] = pivot(Vector3(-W * 0.34, H * 0.42, 0.0), root)
	limb(W * 0.16, H * 0.42, Vector3(0.0, -H * 0.21, 0.0), metal, piv["l_leg"], Vector3.ZERO, Surf.METAL)
	piv["r_leg"] = pivot(Vector3(W * 0.34, H * 0.42, 0.0), root)
	limb(W * 0.16, H * 0.42, Vector3(0.0, -H * 0.21, 0.0), metal, piv["r_leg"], Vector3.ZERO, Surf.METAL)

	# falda de malla: anillo de placas chicas colgando de la cintura
	for i in 10:
		var a := TAU * float(i) / 10.0
		box(Vector3(W * 0.12, W * 0.22, W * 0.06), Vector3(cos(a) * W * 0.4, H * 0.42, sin(a) * W * 0.4), dark_metal, root, Vector3(0.0, -rad_to_deg(a), 0.0), Surf.METAL)

	box(Vector3(W * 0.9, H * 0.5, W * 0.55), Vector3(0.0, H * 0.68, 0.0), col, root)
	box(Vector3(W * 0.2, H * 0.22, W * 0.12), Vector3(0.0, H * 0.86, W * 0.28), rust, root, Vector3.ZERO, Surf.METAL)

	# hombreras: placas apiladas + pincho
	for side in [-1.0, 1.0]:
		for l in 2:
			box(Vector3(W * (0.3 - l * 0.04), H * 0.05, W * (0.32 - l * 0.03)), Vector3(side * W * (0.55 + l * 0.05), H * (0.88 - l * 0.05), 0.0), metal, root, Vector3(0.0, 0.0, side * (10.0 + l * 8.0)), Surf.METAL)
		cone(W * 0.05, W * 0.2, Vector3(side * W * 0.62, H * 0.98, -W * 0.06), dark_metal, root, Vector3(-70.0, 0.0, side * 20.0), Surf.METAL)

	piv["l_arm"] = pivot(Vector3(-W * 0.55, H * 0.85, 0.0), root)
	limb(W * 0.14, H * 0.4, Vector3(0.0, -H * 0.2, 0.0), col, piv["l_arm"])
	piv["r_arm"] = pivot(Vector3(W * 0.55, H * 0.85, 0.0), root)
	limb(W * 0.14, H * 0.4, Vector3(0.0, -H * 0.2, 0.0), col, piv["r_arm"])

	piv["head"] = pivot(Vector3(0.0, H * 0.98, 0.0), root)
	box(Vector3(HR * 1.7, HR * 1.9, HR * 1.7), Vector3.ZERO, metal, piv["head"], Vector3.ZERO, Surf.METAL)
	box(Vector3(HR * 1.2, HR * 0.3, HR * 0.1), Vector3(0.0, 0.0, HR * 0.85), Color(0.03, 0.03, 0.03), piv["head"])
	var visor_glow := StandardMaterial3D.new()
	visor_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visor_glow.emission_enabled = true
	visor_glow.emission = Color(0.9, 0.15, 0.05)
	visor_glow.emission_energy_multiplier = 2.0
	visor_glow.albedo_color = Color(0.9, 0.2, 0.1)
	var visor_l := sphere(HR * 0.1, Vector3(-HR * 0.35, 0.0, HR * 0.82), Color(0.9, 0.2, 0.1), piv["head"])
	visor_l.set_surface_override_material(0, visor_glow)
	var visor_r := sphere(HR * 0.1, Vector3(HR * 0.35, 0.0, HR * 0.82), Color(0.9, 0.2, 0.1), piv["head"])
	visor_r.set_surface_override_material(0, visor_glow)

	# cuernos curvos hacia atrás
	for side in [-1.0, 1.0]:
		limb(HR * 0.13, HR * 0.7, Vector3(side * HR * 0.55, HR * 1.2, -HR * 0.2), dark_metal, piv["head"], Vector3(-25.0, 0.0, side * 12.0), Surf.METAL)
		cone(HR * 0.09, HR * 0.5, Vector3(side * HR * 0.75, HR * 1.75, -HR * 0.55), dark_metal, piv["head"], Vector3(-55.0, 0.0, side * 10.0), Surf.METAL)
	return piv

static func _bat(root: Node3D, col: Color, H: float, W: float) -> Dictionary:
	var piv := {}
	sphere(W, Vector3(0.0, H * 0.5, 0.0), col, root)
	piv["l_wing"] = pivot(Vector3(-W * 0.6, H * 0.55, 0.0), root)
	box(Vector3(W * 1.8, W * 0.06, W * 1.1), Vector3(-W * 0.85, 0.0, 0.0), col.darkened(0.35), piv["l_wing"])
	piv["r_wing"] = pivot(Vector3(W * 0.6, H * 0.55, 0.0), root)
	box(Vector3(W * 1.8, W * 0.06, W * 1.1), Vector3(W * 0.85, 0.0, 0.0), col.darkened(0.35), piv["r_wing"])
	cone(W * 0.22, W * 0.5, Vector3(-W * 0.35, H * 0.85, 0.0), col, root, Vector3(0, 0, 20))
	cone(W * 0.22, W * 0.5, Vector3(W * 0.35, H * 0.85, 0.0), col, root, Vector3(0, 0, -20))

	# ojos brillantes + colmillos
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.9, 0.05, 0.05)
	eye_mat.emission_energy_multiplier = 2.5
	eye_mat.albedo_color = Color(0.9, 0.1, 0.1)
	for side in [-1.0, 1.0]:
		var eye := sphere(W * 0.09, Vector3(side * W * 0.28, H * 0.58, W * 0.55), Color(0.9, 0.1, 0.1), root)
		eye.set_surface_override_material(0, eye_mat)
		cone(W * 0.04, W * 0.18, Vector3(side * W * 0.12, H * 0.4, W * 0.58), Color(0.85, 0.8, 0.75), root, Vector3(180.0, 0.0, 0.0))
	return piv

static func _capra(root: Node3D, col: Color, H: float, W: float, HR: float) -> Dictionary:
	var piv := {}
	var horn := Color(0.15, 0.1, 0.08)
	var dark := col.darkened(0.3)

	var torso := box(Vector3(W * 1.7, W * 0.75, W * 0.85), Vector3(0.0, H * 0.42, 0.0), col, root)
	torso.rotation_degrees.x = -8.0

	# melena de púas a lo largo del lomo
	for i in 6:
		var u := float(i) / 5.0
		cone(W * 0.07, W * 0.22, Vector3(0.0, H * 0.62 - u * H * 0.08, W * 0.55 - u * W * 1.1), dark, root, Vector3(70.0, 0.0, 0.0))

	var leg_y := H * 0.42 - W * 0.3
	piv["l_leg"] = pivot(Vector3(-W * 0.55, leg_y, W * 0.35), root)
	limb(W * 0.11, H * 0.42, Vector3(0.0, -H * 0.2, 0.0), dark, piv["l_leg"])
	piv["r_leg"] = pivot(Vector3(W * 0.55, leg_y, W * 0.35), root)
	limb(W * 0.11, H * 0.42, Vector3(0.0, -H * 0.2, 0.0), dark, piv["r_leg"])
	piv["l_leg2"] = pivot(Vector3(-W * 0.5, leg_y, -W * 0.35), root)
	limb(W * 0.11, H * 0.42, Vector3(0.0, -H * 0.2, 0.0), dark, piv["l_leg2"])
	piv["r_leg2"] = pivot(Vector3(W * 0.5, leg_y, -W * 0.35), root)
	limb(W * 0.11, H * 0.42, Vector3(0.0, -H * 0.2, 0.0), dark, piv["r_leg2"])

	# cola
	piv["tail"] = pivot(Vector3(0.0, H * 0.5, -W * 0.42), root)
	limb(W * 0.06, W * 0.4, Vector3(0.0, 0.0, -W * 0.18), col, piv["tail"], Vector3(70.0, 0.0, 0.0))

	piv["head"] = pivot(Vector3(0.0, H * 0.62, W * 0.7), root)
	sphere(HR, Vector3.ZERO, col, piv["head"])
	cone(HR * 0.22, HR * 0.7, Vector3(-HR * 0.4, HR * 0.6, 0.0), horn, piv["head"], Vector3(-20, 0, 15))
	cone(HR * 0.22, HR * 0.7, Vector3(HR * 0.4, HR * 0.6, 0.0), horn, piv["head"], Vector3(-20, 0, -15))
	# lengua colgando
	box(Vector3(HR * 0.15, HR * 0.35, HR * 0.1), Vector3(0.0, -HR * 0.6, HR * 0.6), Color(0.5, 0.05, 0.1), piv["head"])
	return piv

static func _witch(root: Node3D, col: Color, H: float, W: float, HR: float) -> Dictionary:
	var piv := {}
	var skin := Color(0.75, 0.68, 0.6)
	cone(W * 0.85, H * 0.75, Vector3(0.0, H * 0.38, 0.0), col, root, Vector3(180, 0, 0))

	# escoba: vuela montada en ella
	limb(W * 0.05, H * 0.9, Vector3(0.0, H * 0.3, 0.0), Color(0.35, 0.22, 0.11), root, Vector3(75.0, 0.0, 0.0))
	for i in 8:
		var a := TAU * float(i) / 8.0
		limb(W * 0.015, W * 0.3, Vector3(cos(a) * W * 0.12, H * -0.08, sin(a) * W * 0.12 - W * 0.7), Color(0.55, 0.45, 0.2), root, Vector3(80.0, 0.0, 0.0))

	piv["head"] = pivot(Vector3(0.0, H * 0.85, 0.0), root)
	sphere(HR, Vector3.ZERO, skin, piv["head"])
	cone(HR * 0.2, HR * 0.5, Vector3(0.0, -HR * 0.1, HR * 0.85), skin, piv["head"], Vector3(90.0, 0.0, 0.0))

	# pelo lacio colgando
	for side in [-1.0, 1.0]:
		limb(HR * 0.05, HR * 0.9, Vector3(side * HR * 0.7, -HR * 0.3, -HR * 0.2), Color(0.2, 0.18, 0.2), piv["head"], Vector3(15.0, 0.0, side * 8.0))

	# sombrero cónico
	cone(HR * 1.15, HR * 1.4, Vector3(0.0, HR * 1.0, 0.0), col.darkened(0.3), piv["head"])
	return piv

static func _skull(root: Node3D, col: Color, HR: float) -> Dictionary:
	var piv := {}
	piv["head"] = pivot(Vector3.ZERO, root)
	sphere(HR, Vector3.ZERO, col, piv["head"])

	# cuencas + brillo cian
	sphere(HR * 0.32, Vector3(-HR * 0.4, HR * 0.15, HR * 0.75), Color(0.03, 0.03, 0.05), piv["head"])
	sphere(HR * 0.32, Vector3(HR * 0.4, HR * 0.15, HR * 0.75), Color(0.03, 0.03, 0.05), piv["head"])
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.2, 0.8, 1.0)
	eye_mat.emission_energy_multiplier = 3.0
	eye_mat.albedo_color = Color(0.2, 0.8, 1.0)
	for side in [-1.0, 1.0]:
		var eye := sphere(HR * 0.14, Vector3(side * HR * 0.4, HR * 0.15, HR * 0.9), Color(0.2, 0.8, 1.0), piv["head"])
		eye.set_surface_override_material(0, eye_mat)

	# mandíbula fija de arriba (dientes)
	box(Vector3(HR * 1.1, HR * 0.2, HR * 0.3), Vector3(0.0, -HR * 0.42, HR * 0.6), col.darkened(0.2), piv["head"])

	# mandíbula inferior, pivote propio — se abre y cierra en el bamboleo
	piv["jaw"] = pivot(Vector3(0.0, -HR * 0.58, HR * 0.55), piv["head"])
	box(Vector3(HR * 0.95, HR * 0.22, HR * 0.32), Vector3(0.0, -HR * 0.08, HR * 0.1), col.darkened(0.3), piv["jaw"])

	# capucha violeta drapeada
	var hood_col := Color(0.28, 0.12, 0.32)
	sphere(HR * 1.2, Vector3(0.0, HR * 0.55, -HR * 0.3), hood_col, piv["head"], Surf.CLOTH)
	for i in 4:
		var a := -0.9 + i * 0.6
		box(Vector3(HR * 0.3, HR * 1.0, HR * 0.06), Vector3(sin(a) * HR * 0.9, -HR * 0.2, cos(a) * HR * 0.3 - HR * 0.5), hood_col, piv["head"], Vector3(0.0, rad_to_deg(a), 0.0), Surf.CLOTH)
	return piv
