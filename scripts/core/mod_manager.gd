extends Node
## AUTOLOAD. Encuentra la carpeta de mods, la lee, y expone lo que encontró.
##
## REGLA QUE MANDA SOBRE TODO LO DEMÁS: ningún mod puede impedir que el juego
## arranque ni tirar una partida. GDScript no tiene try/catch, así que "aislar"
## acá significa validar antes de tocar el motor, chequear el retorno de todo lo
## que devuelve Error, y no indexar nunca a ciegas. Cada mod se procesa en su
## propia pasada: si uno falla, se cae él solo y el resto sigue.
##
## Va DESPUÉS de GameData y Config en el orden de autoloads, y eso es a propósito:
## GameData ya dejó armado el registro con los 8 tipos base, así que si esto
## explotara entero el juego arranca igual con el juego base intacto.

signal mods_reloaded

## Carpeta resuelta (absoluta). La muestra el menú: el jugador no tiene que
## adivinar dónde poner los archivos.
var mods_dir := ""
## Si es true, no se pudo escribir donde correspondía y se está usando user://.
var using_fallback_dir := false
## Problema al resolver/crear la carpeta. Vacío = todo bien.
var dir_error := ""

## Una entrada por carpeta encontrada. Forma:
##   id, name, path, enabled, errors: Array, warnings: Array,
##   replacements: Dictionary {enemy_type: ruta_glb}, summary: String
var entries: Array = []

## enemy_type -> PackedScene ya parseado. Se arma una sola vez por arranque:
## parsear un GLB por spawn sería un tirón garantizado con 50 enemigos.
var _models: Dictionary = {}
## Ids deshabilitados por el jugador. Se guardan los DESHABILITADOS y no los
## habilitados para que un mod recién copiado esté prendido sin tocar nada.
var _disabled: Dictionary = {}
## id -> {warnings: Array, summary: String} de la última CARGA. Sobrevive a los
## re-escaneos, que sólo miran nombres de archivo y no saben si el .glb se leyó.
var _load_notes: Dictionary = {}

func _ready() -> void:
	var res := ModPaths.ensure_dir()
	mods_dir = res["dir"]
	using_fallback_dir = res["fallback"]
	dir_error = res["error"]
	_load_disabled()
	scan()
	commit()

# --- Escaneo ---------------------------------------------------------------

## Lee la carpeta y arma `entries`. NO carga modelos todavía: separar el escaneo
## (barato) de la carga (cara) permite que el menú liste mods deshabilitados sin
## pagar el parseo de sus GLB.
func scan() -> void:
	entries.clear()
	if dir_error != "":
		return
	var d := DirAccess.open(mods_dir)
	if d == null:
		dir_error = "no se pudo abrir %s" % mods_dir
		return

	var ids: Array = []
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir() and not name.begins_with("."):
			ids.append(name)
		name = d.get_next()
	d.list_dir_end()
	# Orden alfabético: con dos mods peleando por el mismo enemigo tiene que ganar
	# siempre el mismo, corrida tras corrida. Un orden de sistema de archivos no
	# garantiza eso.
	ids.sort()

	for id: String in ids:
		entries.append(_scan_one(id))
	_flag_conflicts()
	_apply_load_notes()

## Vuelve a pegar lo que se supo al CARGAR (modelos que fallaron, cuántos entraron)
## sobre las entradas recién escaneadas.
##
## Hace falta porque `scan()` reconstruye las entradas de cero y el escaneo sólo
## mira nombres de archivo: no sabe si el .glb se pudo leer. Sin esto, abrir la
## pantalla de Mods hacía que un mod con el modelo corrupto pasara de mostrar su
## aviso a decir "listo" — el panel mentía.
func _apply_load_notes() -> void:
	for e: Dictionary in entries:
		var n: Dictionary = _load_notes.get(e["id"], {})
		if n.is_empty():
			continue
		e["summary"] = n.get("summary", "")
		for w: String in n.get("warnings", []):
			e["warnings"].append(w)

func _scan_one(id: String) -> Dictionary:
	var path: String = mods_dir.path_join(id)
	var e := {
		"id": id, "name": id, "path": path,
		"enabled": not _disabled.has(id),
		"errors": [], "warnings": [], "replacements": {}, "summary": "",
	}

	var rep_dir: String = path.path_join("reemplazos")
	if not DirAccess.dir_exists_absolute(rep_dir):
		e["errors"].append("no tiene carpeta \"reemplazos\"")
		return e

	var d := DirAccess.open(rep_dir)
	if d == null:
		e["errors"].append("no se pudo leer la carpeta \"reemplazos\"")
		return e

	var known: Array = GameData.enemy_types()
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and f.to_lower().ends_with(".glb"):
			var etype := f.get_basename()
			if known.has(etype):
				e["replacements"][etype] = rep_dir.path_join(f)
			else:
				# No es un error del jugador que se equivoque de nombre: es LO más
				# fácil de equivocar. Se le dice cuáles valen.
				e["warnings"].append("\"%s\" no es un enemigo conocido (hay: %s)" % [
					f, ", ".join(known)])
		f = d.get_next()
	d.list_dir_end()

	if e["replacements"].is_empty() and e["errors"].is_empty():
		e["errors"].append("no encontré ningún .glb con nombre de enemigo")
	return e

## Dos mods que pisan el mismo enemigo: gana el último alfabético y se avisa en
## LAS DOS filas. Que uno gane en silencio es peor que el conflicto en sí.
func _flag_conflicts() -> void:
	var winner: Dictionary = {}
	for e: Dictionary in entries:
		if not e["enabled"]:
			continue
		for t: String in e["replacements"]:
			winner[t] = e["id"]
	for e: Dictionary in entries:
		if not e["enabled"]:
			continue
		for t: String in e["replacements"]:
			if winner[t] != e["id"]:
				e["warnings"].append("\"%s\" lo pisa el mod \"%s\"" % [t, winner[t]])

# --- Carga y publicación ---------------------------------------------------

## Parsea los GLB de los mods habilitados y publica el resultado.
##
## No se llama con una partida en curso: los enemigos vivos ya resolvieron su
## modelo y su hitbox en su `_ready()`, así que cambiar el registro debajo de
## ellos los deja inconsistentes. El menú aplica los cambios al empezar una
## partida nueva, no en caliente.
func commit() -> void:
	# Estos dos cachés son ESTÁTICOS y sobreviven a reload_current_scene(). Sin
	# limpiarlos, un reskin se queda con el trasplante de cabeza y las animaciones
	# resueltas del modelo anterior — y el síntoma es dificilísimo de atribuir.
	EnemyModelImport.clear_caches()
	Enemy.clear_anim_cache()

	_models.clear()
	_load_notes.clear()
	for e: Dictionary in entries:
		if not e["enabled"] or not e["errors"].is_empty():
			continue
		var loaded := 0
		var notas: Array = []
		for t: String in e["replacements"]:
			var r := ModModelLoader.load_glb(e["replacements"][t])
			for w: String in r["warnings"]:
				notas.append("%s: %s" % [t, w])
			if r["error"] != "":
				# El modelo falla, el mod sigue vivo: los otros reemplazos que
				# traiga tienen que entrar igual, y ese enemigo se queda con el
				# modelo original en vez de desaparecer.
				notas.append("%s: %s (se usa el modelo original)" % [t, r["error"]])
				continue
			_models[t] = r["scene"]
			loaded += 1
		var resumen := "%d modelo%s" % [loaded, "" if loaded == 1 else "s"]
		# Se guardan aparte para que un re-escaneo (abrir la pantalla de Mods) no
		# los pierda y el panel deje de decir la verdad.
		_load_notes[e["id"]] = {"warnings": notas, "summary": resumen}
		e["summary"] = resumen
		for w: String in notas:
			e["warnings"].append(w)

	# Etapa 1 no toca stats: un reemplazo cambia el modelo y nada más. Se llama
	# igual para dejar el registro en un estado conocido.
	GameData.rebuild_enemy_registry({}, {}, {})
	mods_reloaded.emit()

## El modelo que le corresponde a este tipo, o null si ningún mod lo pisa.
## Lo consulta `enemy.gd` antes de mirar en res://.
func model_scene_for(enemy_type: String) -> PackedScene:
	return _models.get(enemy_type, null)

func has_any() -> bool:
	return not entries.is_empty()

# --- Habilitar / deshabilitar ----------------------------------------------

## Hay cambios marcados que todavía no se aplicaron. Lo lee el menú para mostrar
## "se aplican al empezar una partida nueva".
var pending := false

func set_enabled(id: String, enabled: bool) -> void:
	if enabled:
		_disabled.erase(id)
	else:
		_disabled[id] = true
	for e: Dictionary in entries:
		if e["id"] == id:
			e["enabled"] = enabled
	pending = true
	_save_disabled()

## La llama `GameState.start_run()`. Si nadie tocó nada no hace nada: volver a
## parsear todos los GLB al empezar cada partida sería pagar el arranque de nuevo
## sin motivo.
func commit_if_needed() -> void:
	if not pending:
		return
	scan()
	commit()
	pending = false

func _load_disabled() -> void:
	_disabled.clear()
	for id in Config.mods_disabled:
		_disabled[String(id)] = true

func _save_disabled() -> void:
	Config.mods_disabled = _disabled.keys()
	Config.save_config()
