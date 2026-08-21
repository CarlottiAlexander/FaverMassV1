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
##   types: Dictionary {enemy_type: {model, stats?, spawn?, color?, opts?, preset?}},
##   summary: String, declara: bool
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
## Foto de lo que había en disco la última vez que se cargó de verdad. Sirve para
## darse cuenta de que el jugador copió, borró o apagó algo.
var _committed_signature := ""
## tipo -> ajustes del pipeline de modelo declarados por el mod.
var _opts: Dictionary = {}
## tipo -> preset de movimiento.
var _presets: Dictionary = {}
## tipo -> rasgos componibles.
var _traits: Dictionary = {}
## id de mapa -> perfil ya fusionado y validado.
var _maps: Dictionary = {}
## tipo -> {ranura: AudioStream|Array, _silent, _inherit, _volume}. Los sonidos son
## PROPIEDAD DE LA ENTIDAD: viajan adentro del mod, igual que el .glb.
var _sounds: Dictionary = {}

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

	# Si lo que hay en disco dejó de coincidir con lo que está cargado, queda
	# PENDIENTE. Sin esto, copiar una carpeta con el juego abierto la mostraba en
	# la lista pero no la cargaba nunca: sólo `set_enabled` marcaba pendiente, así
	# que un mod nuevo se veía y no hacía nada — el peor de los dos mundos.
	if _signature() != _committed_signature:
		pending = true

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
		# `types` unifica los dos caminos: un reskin trae sólo {"model": ruta} y un
		# tipo declarado en mod.json trae además stats/spawn/color/opts/preset. De
		# acá para abajo nadie necesita saber de cuál de los dos vino.
		"errors": [], "warnings": [], "types": {}, "maps": {}, "summary": "", "declara": false,
	}

	# El mod.json manda. Si está, la carpeta `reemplazos` no se mira: tener las dos
	# fuentes decidiendo lo mismo es pedir que se contradigan.
	var json_path: String = path.path_join("mod.json")
	if FileAccess.file_exists(json_path):
		e["declara"] = true
		var m := ModManifest.parse(json_path, path)
		for w: String in m["warnings"]:
			e["warnings"].append(w)
		if not m["ok"]:
			e["errors"].append(m["error"])
			return e
		if String(m["name"]) != "":
			e["name"] = m["name"]
		if String(m["author"]) != "":
			e["name"] = "%s — por %s" % [e["name"], m["author"]]
		for t: String in m["enemies"]:
			e["types"][t] = m["enemies"][t]
		e["maps"] = m["maps"]
		return e

	var rep_dir: String = path.path_join("reemplazos")
	if not DirAccess.dir_exists_absolute(rep_dir):
		e["errors"].append("no tiene mod.json ni carpeta \"reemplazos\"")
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
				e["types"][etype] = {"model": rep_dir.path_join(f)}
			else:
				# No es un error del jugador que se equivoque de nombre: es LO más
				# fácil de equivocar. Se le dice cuáles valen.
				e["warnings"].append("\"%s\" no es un enemigo conocido (hay: %s)" % [
					f, ", ".join(known)])
		f = d.get_next()
	d.list_dir_end()

	if e["types"].is_empty() and e["errors"].is_empty():
		e["errors"].append("no encontré ningún .glb con nombre de enemigo")
	return e

## Dos mods que pisan el mismo enemigo: gana el último alfabético y se avisa en
## LAS DOS filas. Que uno gane en silencio es peor que el conflicto en sí.
func _flag_conflicts() -> void:
	var winner: Dictionary = {}
	for e: Dictionary in entries:
		if not e["enabled"]:
			continue
		for t: String in e["types"]:
			winner[t] = e["id"]
	for e: Dictionary in entries:
		if not e["enabled"]:
			continue
		for t: String in e["types"]:
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
	# El caché de sonidos vive en un autoload y sobrevive al reinicio de escena:
	# sin vaciarlo, un mod recién activado seguiría sonando como el anterior.
	Audio.clear_cache()

	_models.clear()
	_load_notes.clear()
	_opts.clear()
	_presets.clear()
	_traits.clear()
	_maps.clear()
	_sounds.clear()
	var stats_ov: Dictionary = {}
	var spawn_ov: Dictionary = {}
	var color_ov: Dictionary = {}

	for e: Dictionary in entries:
		if not e["enabled"] or not e["errors"].is_empty():
			continue
		var loaded := 0
		var nuevos := 0
		var notas: Array = []
		for t: String in e["types"]:
			var d: Dictionary = e["types"][t]

			# Los datos entran ANTES que el modelo, a propósito: si el .glb falla, el
			# tipo tiene que existir igual con sus stats y caer al cuerpo de respaldo.
			# Al revés, un modelo roto borraría al enemigo del juego.
			if d.has("stats"):
				stats_ov[t] = d["stats"]
				spawn_ov[t] = d["spawn"]
				if d.get("declara_color", false):
					color_ov[t] = d["color"]
				_presets[t] = d["preset"]
				if d.has("traits"):
					_traits[t] = d["traits"]
				if not d.get("existia", true):
					nuevos += 1
			var op: Dictionary = d.get("opts", {})
			if not op.is_empty():
				_opts[t] = op

			# Los sonidos van con los DATOS y no con el modelo: un sonido que falla
			# no puede impedir que el enemigo exista, y un modelo que falla no puede
			# dejarlo mudo. Son dos fallas independientes.
			var sc: Dictionary = d.get("sounds", {})
			if not sc.is_empty():
				_sounds[t] = _cargar_sonidos(t, sc, notas)

			var ruta := String(d.get("model", ""))
			if ruta == "":
				continue
			var r := ModModelLoader.load_glb(ruta)
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
		for mid: String in (e.get("maps", {}) as Dictionary):
			_maps[mid] = e["maps"][mid]
		# El resumen enumera sólo lo que el mod SÍ trae. Un mod que únicamente aporta
		# un mapa decía "0 modelos", que es cierto y no informa nada.
		var partes: Array = []
		if loaded > 0:
			partes.append("%d modelo%s" % [loaded, "" if loaded == 1 else "s"])
		if nuevos > 0:
			partes.append("%d enemigo%s nuevo%s" % [nuevos, "" if nuevos == 1 else "s", "" if nuevos == 1 else "s"])
		var nmapas: int = (e.get("maps", {}) as Dictionary).size()
		if nmapas > 0:
			partes.append("%d mapa%s" % [nmapas, "" if nmapas == 1 else "s"])
		var resumen := "listo" if partes.is_empty() else ", ".join(PackedStringArray(partes))
		# Se guardan aparte para que un re-escaneo (abrir la pantalla de Mods) no
		# los pierda y el panel deje de decir la verdad.
		_load_notes[e["id"]] = {"warnings": notas, "summary": resumen}
		e["summary"] = resumen
		for w: String in notas:
			e["warnings"].append(w)

	GameData.rebuild_enemy_registry(stats_ov, spawn_ov, color_ov)
	_committed_signature = _signature()
	pending = false
	mods_reloaded.emit()

## Qué mods habilitados hay y qué reemplazan. Dos estados con la misma firma
## producen exactamente el mismo juego, así que no hace falta recargar.
func _signature() -> String:
	var partes: Array = []
	for e: Dictionary in entries:
		if not e["enabled"] or not e["errors"].is_empty():
			continue
		var claves: Array = e["types"].keys()
		claves.sort()
		for t: String in claves:
			partes.append("%s:%s" % [e["id"], t])
	return "|".join(PackedStringArray(partes))

## El modelo que le corresponde a este tipo, o null si ningún mod lo pisa.
## Lo consulta `enemy.gd` antes de mirar en res://.
func model_scene_for(enemy_type: String) -> PackedScene:
	return _models.get(enemy_type, null)

## Ajustes del pipeline de modelo que declaró el mod (yaw, palabras de la cabeza,
## hueso, forma de la hitbox, equipamiento, animaciones). Vacío = todo por defecto,
## que es exactamente el comportamiento de los 8 base.
func model_opts_of(enemy_type: String) -> Dictionary:
	return _opts.get(enemy_type, {})

## Preset de movimiento, o "" si este tipo no viene de un mod. `EnemyBehaviors`
## despacha por preset cuando hay uno, y por el `match` de siempre cuando no.
func preset_of(enemy_type: String) -> String:
	return _presets.get(enemy_type, "")

## Rasgos declarados para este tipo: {nombre: {parámetros}}. Vacío para los 8 base.
func traits_of(enemy_type: String) -> Dictionary:
	return _traits.get(enemy_type, {})

# --- Sonidos ----------------------------------------------------------------
# El contrato que consume `Audio.resolver()`. Un tipo sin nada declarado devuelve
# los valores neutros, que hacen que todo caiga al sonido del juego base.

## Carga las rutas que resolvió `ModManifest` y devuelve la misma estructura con
## streams en lugar de rutas.
##
## Un archivo que falla se descarta CON AVISO y las demás variantes de esa misma
## ranura entran igual: que un `.ogg` truncado deje mudo a todo el bicho sería una
## falla desproporcionada. Si se caen todas, la ranura no queda en la lista y la
## cadena de `Audio.resolver()` la hereda del tipo base sola.
func _cargar_sonidos(tipo: String, decl: Dictionary, notas: Array) -> Dictionary:
	var out := {}
	for k in decl:
		var clave := String(k)
		if clave.begins_with("_"):
			out[clave] = decl[clave]   # _silent / _inherit / _volume pasan tal cual
			continue
		var streams: Array[AudioStream] = []
		for ruta in (decl[clave] as Array):
			var r := ModSoundLoader.load_sound(String(ruta))
			for w: String in r["warnings"]:
				notas.append("%s/%s: %s" % [tipo, clave, w])
			if r["error"] != "":
				notas.append("%s/%s: %s (se hereda el sonido base)" % [tipo, clave, r["error"]])
				continue
			streams.append(r["stream"])
		if not streams.is_empty():
			out[clave] = streams
	return out

## TODAS las variantes que el mod declaró para esta ranura, o vacío.
##
## Devuelve la lista COMPLETA y no una ya elegida a propósito: quien elige es
## `Audio`, que tiene su propio RNG. Si acá se llamara a `pick_random()` se estaría
## consumiendo el RNG GLOBAL, y en este proyecto esa secuencia es un invariante de
## balance — la composición de oleada pasaría a depender de cuántos golpes sonaron.
func sounds_for(enemy_type: String, ranura: String) -> Array:
	var s: Dictionary = _sounds.get(enemy_type, {})
	var v = s.get(ranura, null)
	return (v as Array) if v is Array else []

## El mod pidió quedarse MUDO a propósito. Distinto de "no declaró nada", que
## hereda del tipo base.
func sound_is_silent(enemy_type: String) -> bool:
	return bool((_sounds.get(enemy_type, {}) as Dictionary).get("_silent", false))

## De qué tipo base heredar lo que el mod no declaró.
func sound_inherit_of(enemy_type: String) -> String:
	return String((_sounds.get(enemy_type, {}) as Dictionary).get("_inherit", enemy_type))

func sound_volume_of(enemy_type: String) -> float:
	return float((_sounds.get(enemy_type, {}) as Dictionary).get("_volume", 1.0))

# --- Mapas ------------------------------------------------------------------

## id -> nombre para mostrar, con la arena del juego base siempre primera.
func maps_available() -> Dictionary:
	var out := {"": String(MapProfile.DEFECTO["name"])}
	for id: String in _maps:
		out[id] = String((_maps[id] as Dictionary).get("name", id))
	return out

## El perfil que tiene que usar `world.gd`. Si el mapa elegido ya no existe (el
## jugador apagó o borró ese mod), se cae al del juego base en vez de romper.
func map_profile() -> Dictionary:
	return _maps.get(map_seleccionado(), MapProfile.DEFECTO)

## `--map=<id>` pisa lo guardado, para que las herramientas de tools/ puedan probar
## un mapa sin escribirle la configuración al jugador. Mismo criterio que `--mods=`.
func map_seleccionado() -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--map="):
			return s.substr(6)
	return Config.map_id

func set_map(id: String) -> void:
	Config.map_id = id if _maps.has(id) else ""
	Config.save_config()

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
## Devuelve `true` si de verdad hubo un cambio. `GameState.start_run()` lo usa para
## decidir si recarga la escena: el mapa se construye en `world._ready()`, así que
## sin recarga un mapa recién elegido no se aplicaría.
func commit_if_needed() -> bool:
	if not pending:
		return false
	scan()
	commit()   # deja `pending` en false
	return true

func _load_disabled() -> void:
	_disabled.clear()
	for id in Config.mods_disabled:
		_disabled[String(id)] = true

func _save_disabled() -> void:
	Config.mods_disabled = _disabled.keys()
	Config.save_config()
