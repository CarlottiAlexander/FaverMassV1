extends Node
## Inspector de la carpeta de mods: qué encontró el juego, qué cargó, qué rechazó
## y por qué. Es la herramienta del modder — el equivalente de `inspect_models`
## para contenido de la comunidad.
##
## Correr contra el fixture del repo (no toca la carpeta real del jugador):
##   Godot --headless --path . tools/mod_report.tscn -- --mods=tools/mods_fixture
## Correr contra la carpeta de verdad:
##   Godot --headless --path . tools/mod_report.tscn

func _ready() -> void:
	print("CARPETA : %s" % ModManager.mods_dir)
	if ModManager.using_fallback_dir:
		print("  OJO   : no se pudo escribir donde correspondía, se usó una alternativa")
	if ModManager.dir_error != "":
		print("  ERROR : %s" % ModManager.dir_error)

	if not ModManager.has_any():
		print("\nNo hay ningún mod. Para probar: crear <carpeta>/reemplazos/hollow.glb")
		get_tree().quit()
		return

	print("\n%d mod(s) encontrados\n" % ModManager.entries.size())
	for e: Dictionary in ModManager.entries:
		_print_mod(e)

	print("=".repeat(64))
	print("MODELOS EFECTIVAMENTE EN USO")
	var used := false
	for t: String in GameData.enemy_types():
		var sc: PackedScene = ModManager.model_scene_for(t)
		if sc:
			used = true
			print("  %-14s <- mod" % t)
	if not used:
		print("  (ninguno: todos los enemigos usan su modelo original)")
	get_tree().quit()

func _print_mod(e: Dictionary) -> void:
	var estado := "ACTIVO" if e["enabled"] else "APAGADO"
	if not e["errors"].is_empty():
		estado = "DESCARTADO"
	print("=".repeat(64))
	print("%s   [%s]" % [e["name"], estado])
	print("  ruta      : %s" % e["path"])
	if e["summary"] != "":
		print("  cargó     : %s" % e["summary"])

	for err: String in e["errors"]:
		print("  ERROR     : %s" % err)
	for w: String in e["warnings"]:
		print("  aviso     : %s" % w)

	for t: String in e["types"]:
		var d: Dictionary = e["types"][t]
		if d.has("stats"):
			var s: Dictionary = d["stats"]
			var sp: Dictionary = d["spawn"]
			var etiqueta := "reemplaza" if d.get("existia", false) else "TIPO NUEVO"
			print("  --- %s  [%s]" % [t, etiqueta])
			print("      %s | hp %.0f  vel %.1f  daño %.0f  alto %.2f  %s" % [
				s.get("name", t), s.get("hp", 0.0), s.get("speed", 0.0),
				s.get("damage", 0.0), s.get("height", 0.0),
				"vuela" if s.get("flying", false) else "camina"])
			print("      aparece desde la oleada %d   preset: %s" % [
				int(sp.get("min_wave", 1)), d.get("preset", "chaser")])
			var op: Dictionary = d.get("opts", {})
			if not op.is_empty():
				var oo: Array = []
				for k: String in op:
					oo.append("%s=%s" % [k, op[k]])
				print("      ajustes de modelo: %s" % ", ".join(PackedStringArray(oo)))
			var tr: Dictionary = d.get("traits", {})
			if not tr.is_empty():
				var partes: Array = []
				for n: String in tr:
					var ps: Dictionary = tr[n]
					partes.append(n if ps.is_empty() else "%s(%s)" % [n, ", ".join(PackedStringArray(ps.keys()))])
				print("      rasgos: %s" % ", ".join(PackedStringArray(partes)))
		if String(d.get("model", "")) != "":
			_print_model(t, d["model"])

	for mid: String in (e.get("maps", {}) as Dictionary):
		_print_map(mid, e["maps"][mid])
	print("")

## Qué trae un mapa: la arena y —lo nuevo— a qué se juega en él.
func _print_map(id: String, p: Dictionary) -> void:
	print("  --- mapa \"%s\": %s" % [id, p.get("name", id)])
	print("      arena radio %.0f   obstáculos %d (semilla %d)   muros %.1f+%.1f" % [
		float(p.get("arena_radius", 0.0)),
		int((p.get("obstacles", {}) as Dictionary).get("count", 0)),
		int((p.get("obstacles", {}) as Dictionary).get("seed", 0)),
		float((p.get("walls", {}) as Dictionary).get("base_height", 0.0)),
		float((p.get("walls", {}) as Dictionary).get("extra_height", 0.0))])
	var m: Dictionary = p.get("mode", {})
	if m.is_empty():
		print("      modo: (ninguno) -> oleadas infinitas, se termina al morir")
		return
	print("      modo: %s  [%s]%s" % [
		m.get("name", "?"), m.get("builtin", "survival"),
		"   SIN OLEADAS" if not bool(m.get("waves", true)) else ""])
	if String(m.get("description", "")) != "":
		print("            \"%s\"" % m["description"])
	if not (m.get("params", {}) as Dictionary).is_empty():
		print("            parámetros: %s" % m["params"])

## Se vuelve a parsear el GLB acá a propósito, en vez de reusar lo que cacheó
## ModManager: lo que interesa reportar son los datos CRUDOS del archivo (nombres
## de animación reales, triángulos), que es lo que el modder necesita para saber
## por qué su bicho no se mueve. El costo no importa: esto es una herramienta.
func _print_model(etype: String, path: String) -> void:
	print("  --- %s  (%s)" % [etype, path.get_file()])
	var r := ModModelLoader.load_glb(path)
	if r["error"] != "":
		print("      RECHAZADO: %s" % r["error"])
		print("      -> ese enemigo se queda con su modelo original")
		return

	print("      triángulos: %d" % r["tris"])
	var inst: Node = r["scene"].instantiate()
	add_child(inst)

	var ap := EnemyModelImport.find_animation_player(inst)
	if ap == null:
		print("      animaciones: NINGUNA (el modelo no se va a mover)")
	else:
		var list := ap.get_animation_list()
		print("      animaciones (%d): %s" % [list.size(), ", ".join(list)])
		# Lo que de verdad importa no es cuántas hay sino si alguna matchea lo que
		# el juego busca: un modelo con 30 animaciones y ningún nombre reconocible
		# se queda igual de quieto que uno sin ninguna.
		_print_slot(ap, "idle  ", Enemy.ANIM_IDLE)
		_print_slot(ap, "correr", Enemy.ANIM_RUN)
		_print_slot(ap, "atacar", Enemy.ANIM_ATTACK)

	print("      alto nativo: %.2f   (el juego lo escala al alto del tipo)" % _native_height(inst))
	_print_head(inst)
	inst.queue_free()

## Lo que necesita el modder cuando el headshot no le funciona: si alguna malla
## matchea las palabras que el juego busca, y si no, cómo se llaman las mallas y
## el hueso más parecido a una cabeza — que es lo que hay que poner en
## `head.keywords` o `head.bone`.
func _print_head(inst: Node) -> void:
	var mallas: Array = []
	for m in EnemyModelImport.all_mesh_nodes(inst):
		mallas.append(String(m.name))

	var matchean: Array = []
	for n: String in mallas:
		if EnemyModelImport.name_matches(n.to_lower(), EnemyModelImport.HEAD_KEYWORDS):
			matchean.append(n)

	if not matchean.is_empty():
		print("      cabeza: por malla -> %s" % ", ".join(PackedStringArray(matchean)))
		return

	print("      cabeza: NINGUNA malla matchea %s" % ", ".join(PackedStringArray(EnemyModelImport.HEAD_KEYWORDS)))
	print("              mallas del modelo: %s" % ", ".join(PackedStringArray(mallas)))

	var sk := EnemyModelImport.find_skeleton(inst)
	if sk == null:
		print("              sin esqueleto: el headshot va a usar la banda de altura")
		return
	# Se listan los huesos ALTOS: en cualquier rig la cabeza es de los que están más
	# arriba en pose de reposo, así que ordenar por Y deja el candidato a la vista.
	var huesos: Array = []
	for i in sk.get_bone_count():
		huesos.append({"n": sk.get_bone_name(i), "y": sk.get_bone_global_rest(i).origin.y})
	huesos.sort_custom(func(a, b): return a["y"] > b["y"])
	var top: Array = []
	for i in mini(6, huesos.size()):
		top.append("%s (Y=%.2f)" % [huesos[i]["n"], huesos[i]["y"]])
	print("              huesos más altos: %s" % ", ".join(PackedStringArray(top)))
	print("              -> poner el que corresponda en \"head\": { \"bone\": \"...\" }")

## `EnemyModelImport.mesh_aabb` pide un Enemy para poder medir en SU espacio local,
## y acá no hay ninguno. Como el modelo se cuelga en el origen sin transformar, el
## espacio global sirve igual para lo único que interesa: cuánto mide de alto.
func _native_height(inst: Node) -> float:
	var box := AABB()
	var first := true
	for m in EnemyModelImport.all_mesh_nodes(inst):
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return box.size.y

## Reporta lo MISMO que va a resolver el juego: primero el nombre exacto, y si no
## está, la deducción por palabra clave (`Enemy.guess_anim`). Si esto informara
## distinto de lo que pasa en la partida, sería peor que no reportar nada.
func _print_slot(ap: AnimationPlayer, etiqueta: String, candidatos: Array) -> void:
	for c: String in candidatos:
		if ap.has_animation(c):
			print("      %s -> %s" % [etiqueta, c])
			return
	var g := Enemy.guess_anim(ap, candidatos)
	if g != "":
		print("      %s -> %s  (deducida por nombre)" % [etiqueta, g])
	else:
		print("      %s -> NO RESUELVE (probó: %s)" % [etiqueta, ", ".join(candidatos)])
