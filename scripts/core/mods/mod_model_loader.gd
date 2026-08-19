class_name ModModelLoader
extends RefCounted
## Convierte un .glb suelto del disco en un PackedScene instanciable, SIN pasar
## por el importador de Godot.
##
## Por qué no `load("res://...")`: eso sólo funciona con recursos que el editor ya
## importó. Un jugador que copia un archivo a una carpeta no dispara ninguna
## importación, así que la única forma de que su modelo entre al juego es parsear
## el GLTF en tiempo de ejecución.
##
## Lo que se pierde al no pasar por el importador, y hay que tener presente:
## no hay LOD, no hay shadow mesh, y las texturas quedan sin comprimir ni mipmaps.
## Por eso los presupuestos de abajo no son burocracia: un modelo pesado de la
## comunidad se paga en VRAM y en FPS, y este juego ya pone 50 enemigos en pantalla.

## 64 MB. Se chequea ANTES de parsear: un archivo enorme no debe llegar nunca al
## parser, porque para entonces ya se pagó la memoria.
const MAX_FILE_BYTES := 64 * 1024 * 1024
## Por encima de esto el modelo se acepta igual pero se avisa. El presupuesto real
## es "esto x 50 enemigos vivos".
const WARN_TRIANGLES := 60000
const WARN_TEXTURE_PX := 1024

## Devuelve {scene: PackedScene, error: String, warnings: Array[String], tris: int}.
## `scene` es null si y sólo si `error` no está vacío. NUNCA tira una excepción ni
## deja un nodo colgado: GDScript no tiene try/catch, así que cada paso que puede
## fallar se chequea a mano.
static func load_glb(abs_path: String) -> Dictionary:
	var out := {"scene": null, "error": "", "warnings": [], "tris": 0}

	if not FileAccess.file_exists(abs_path):
		out["error"] = "no existe el archivo"
		return out

	var size := _file_size(abs_path)
	if size > MAX_FILE_BYTES:
		out["error"] = "pesa %.0f MB y el tope es %d MB" % [
			size / 1048576.0, MAX_FILE_BYTES / 1048576]
		return out

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	# El `base_path` es OBLIGATORIO: hay packs que referencian su textura por URI
	# relativa (los de Kenney piden "Textures/colormap.png"). Sin esto el modelo
	# carga igual pero se ve BLANCO, que es un síntoma confuso de diagnosticar.
	var err: int = doc.append_from_file(abs_path, state, 0, abs_path.get_base_dir())
	if err != OK:
		out["error"] = "el GLTF no se pudo leer (código %d); ¿está completo el archivo?" % err
		return out

	var root: Node = doc.generate_scene(state)
	if root == null:
		out["error"] = "el archivo se leyó pero no contiene ninguna escena"
		return out

	var stats := _inspect(root)
	out["tris"] = stats["tris"]
	if stats["tris"] > WARN_TRIANGLES:
		out["warnings"].append("%d triángulos: pesado para un juego que pone 50 enemigos a la vez" % stats["tris"])
	if stats["max_tex"] > WARN_TEXTURE_PX:
		out["warnings"].append("textura de %dpx sin comprimir: ocupa bastante VRAM" % stats["max_tex"])
	if stats["meshes"] == 0:
		out["error"] = "el modelo no tiene ninguna malla visible"
		root.free()
		return out
	if stats["skeletons"] == 0:
		out["warnings"].append("sin esqueleto: el modelo no se va a animar, se desliza")
	elif stats["anims"] == 0:
		out["warnings"].append("tiene esqueleto pero ninguna animación: se queda quieto")

	# `pack()` sólo guarda los nodos que tienen `owner`, y `generate_scene()` los
	# devuelve TODOS sin owner. Sin esto el prototipo queda con la raíz pelada y el
	# enemigo sale invisible, sin ningún error de por medio.
	_set_owner_recursive(root, root)

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		out["error"] = "no se pudo empaquetar el modelo"
		return out

	# free() y no queue_free(): este nodo nunca entró al árbol.
	root.free()
	out["scene"] = packed
	return out

static func _file_size(abs_path: String) -> int:
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n

static func _set_owner_recursive(node: Node, owner: Node) -> void:
	for c in node.get_children():
		if c != owner:
			c.owner = owner
		_set_owner_recursive(c, owner)

static func _inspect(root: Node) -> Dictionary:
	var st := {"tris": 0, "meshes": 0, "skeletons": 0, "anims": 0, "max_tex": 0}
	_walk(root, st)
	return st

static func _walk(n: Node, st: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			st["meshes"] = int(st["meshes"]) + 1
			for s in mi.mesh.get_surface_count():
				# Indexado o no: se cuenta lo que corresponda en cada caso.
				# Tipado explícito: estas dos no están declaradas en `Mesh` sino en
				# `ArrayMesh`, así que se resuelven como Variant y Godot trata como
				# ERROR (no warning) inferir `:=` desde un Variant.
				var idx: int = mi.mesh.surface_get_array_index_len(s)
				var verts: int = mi.mesh.surface_get_array_len(s)
				st["tris"] = int(st["tris"]) + int((idx if idx > 0 else verts) / 3.0)
				var mat := mi.mesh.surface_get_material(s)
				if mat is StandardMaterial3D:
					var tex: Texture2D = (mat as StandardMaterial3D).albedo_texture
					if tex:
						st["max_tex"] = maxi(int(st["max_tex"]), maxi(tex.get_width(), tex.get_height()))
	elif n is Skeleton3D:
		st["skeletons"] = int(st["skeletons"]) + 1
	elif n is AnimationPlayer:
		st["anims"] = int(st["anims"]) + (n as AnimationPlayer).get_animation_list().size()
	for c in n.get_children():
		_walk(c, st)
