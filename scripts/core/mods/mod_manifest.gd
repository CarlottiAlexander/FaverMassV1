class_name ModManifest
extends RefCounted
## Lee y valida un `mod.json`. Devuelve datos ya normalizados y recortados, listos
## para entrar al registro: nadie aguas abajo debería tener que volver a
## desconfiar de un número.
##
## Se eligió JSON sobre el formato clave=valor de `config.gd` por una razón
## concreta: `JSON.get_error_line()` permite decirle al modder "mod.json:12 —
## Expected ','" en el menú. El parser de `config.gd` ignora en silencio, que para
## configuración del juego está bien y para contenido de terceros es inservible.

## Tope de tolerancia de cada campo. No es burocracia: `height: 0` da escala 0 y el
## enemigo sale INVISIBLE, y `speed: 999` lo hace atravesar la arena entera en un
## paso de física. Un mod mal hecho tiene que quedar raro, no romper la partida.
const LIMITES := {
	"hp": [1.0, 100000.0], "speed": [0.0, 30.0], "damage": [0.0, 10000.0],
	"atk_cd": [0.05, 10.0], "xp": [0.0, 1000.0], "regen": [0.0, 100.0],
	"radius": [0.05, 5.0], "height": [0.2, 12.0], "head_radius": [0.02, 5.0],
}
const LIMITES_SPAWN := {
	"min_wave": [1.0, 999.0], "share": [0.0, 2.0], "flat": [0.0, 200.0], "step": [0.0, 99.0],
}

## Comportamientos que un mod puede elegir. Son los que YA existen en
## `EnemyBehaviors`: no se inventa nada, se expone lo que hay.
const PRESETS := ["chaser", "flyer", "weaver", "wobbler", "brute", "stalker", "orbiter"]

## Campos que se copian tal cual a la fila de stats.
const CAMPOS_STATS := ["hp", "speed", "damage", "atk_cd", "xp", "regen", "radius", "height", "head_radius"]

## Ranuras de sonido que un mod puede declarar. Es una lista CERRADA a propósito:
## así un `"deat"` mal escrito se avisa en vez de guardarse en silencio y dejar al
## modder buscando por qué su bicho no suena.
const RANURAS_SONIDO := ["attack", "hit", "death", "spawn", "step"]
## Tope de variantes por ranura. Más que esto no aporta variación audible y sí
## memoria: cada una es un stream cargado y residente.
const MAX_VARIANTES_SONIDO := 8

## Devuelve {ok, error, name, author, version, enemies, warnings}.
## `enemies` es {tipo: {stats, spawn, color, model, opts, preset, declara_color}}.
static func parse(json_path: String, mod_dir: String) -> Dictionary:
	var out := {"ok": false, "error": "", "name": "", "author": "", "version": "",
		"enemies": {}, "maps": {}, "warnings": []}

	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		out["error"] = "no se pudo abrir mod.json"
		return out
	var txt := f.get_as_text()
	f.close()

	# El Notepad de Windows escribe BOM y `parse_string` se atraganta con un error
	# críptico en la línea 1. Es la falla más probable de todas y cuesta tres líneas.
	if txt.begins_with("﻿"):
		txt = txt.substr(1)
	if txt.begins_with("ÿþ") or txt.begins_with("þÿ"):
		out["error"] = "el archivo está en UTF-16; guardalo como UTF-8"
		return out

	var j := JSON.new()
	if j.parse(txt) != OK:
		out["error"] = "mod.json:%d — %s" % [j.get_error_line(), j.get_error_message()]
		return out
	if typeof(j.data) != TYPE_DICTIONARY:
		out["error"] = "mod.json tiene que ser un objeto { ... }"
		return out

	var raiz: Dictionary = j.data
	out["name"] = String(raiz.get("name", ""))
	out["author"] = String(raiz.get("author", ""))
	out["version"] = String(raiz.get("version", ""))

	# Se avisa pero no se rechaza: un `format` futuro puede traer campos que este
	# juego ignore, y descartar el mod entero por eso sería peor que cargarlo a medias.
	var formato := int(raiz.get("format", 1))
	if formato > 1:
		out["warnings"].append("hecho para un formato más nuevo (%d); puede que algo se ignore" % formato)

	# --- mapas ---
	var mapas := {}
	var mc = raiz.get("maps", {})
	if typeof(mc) == TYPE_DICTIONARY:
		for id: String in mc:
			if typeof(mc[id]) != TYPE_DICTIONARY:
				out["warnings"].append("mapa \"%s\": se ignoró, no es un objeto" % id)
				continue
			var r := MapProfile.merge(mc[id])
			for w: String in r["warnings"]:
				out["warnings"].append("mapa \"%s\": %s" % [id, w])
			mapas[id] = r["perfil"]
	out["maps"] = mapas

	# Un mod puede traer SÓLO mapas, sin enemigos. Por eso la exigencia de declarar
	# enemigos se relaja si trajo al menos un mapa.
	if not raiz.has("enemies") or typeof(raiz["enemies"]) != TYPE_DICTIONARY:
		if not mapas.is_empty():
			out["ok"] = true
			return out
		out["error"] = "mod.json no declara ningún enemigo ni mapa"
		return out

	for tipo: String in raiz["enemies"]:
		var crudo = raiz["enemies"][tipo]
		if typeof(crudo) != TYPE_DICTIONARY:
			out["warnings"].append("\"%s\": se ignoró, no es un objeto" % tipo)
			continue
		var r := _un_enemigo(tipo, crudo, mod_dir)
		for w: String in r["warnings"]:
			out["warnings"].append(w)
		if r["error"] != "":
			out["warnings"].append("\"%s\": %s" % [tipo, r["error"]])
			continue
		out["enemies"][tipo] = r["data"]

	if out["enemies"].is_empty() and (out["maps"] as Dictionary).is_empty():
		out["error"] = "nada del mod.json se pudo usar"
		return out

	out["ok"] = true
	return out

static func _un_enemigo(tipo: String, c: Dictionary, mod_dir: String) -> Dictionary:
	var res := {"error": "", "warnings": [], "data": {}}
	var existe: bool = GameData.ENEMY_STATS.has(tipo)

	# --- modelo ---
	var modelo := ""
	if c.has("model"):
		var rel := String(c["model"])
		modelo = mod_dir.path_join(rel).simplify_path()
		# Un mod no puede leer fuera de su carpeta. Sin esto, `"model":
		# "../../../Windows/..."` sería una ruta válida.
		if not modelo.begins_with(mod_dir):
			res["error"] = "la ruta del modelo sale de la carpeta del mod"
			return res
		if not FileAccess.file_exists(modelo):
			res["error"] = "no existe el modelo \"%s\"" % rel
			return res
	elif not existe:
		# Un tipo NUEVO sin modelo caería al de primitivas y saldría genérico. Se
		# permite igual, pero avisando: es casi seguro un error del modder.
		res["warnings"].append("\"%s\": sin modelo; va a usar el cuerpo de respaldo" % tipo)

	# --- stats ---
	# Base: la fila que ya existe si es un reemplazo, o la del Hollow si es nuevo.
	# Así un mod que sólo declara `hp` no pierde el resto de los campos.
	var stats: Dictionary = (GameData.ENEMY_STATS.get(tipo, GameData.ENEMY_STATS["hollow"]) as Dictionary).duplicate(true)
	stats.erase("min_wave")   # por si quedara alguna copia vieja: eso vive en spawn
	for campo: String in CAMPOS_STATS:
		if not c.has(campo):
			continue
		var lim: Array = LIMITES[campo]
		var v := float(c[campo])
		var v2 := clampf(v, lim[0], lim[1])
		if not is_equal_approx(v, v2):
			res["warnings"].append("\"%s\": %s=%s quedó fuera de rango, se ajustó a %s" % [tipo, campo, v, v2])
		stats[campo] = v2
	if c.has("flying"):
		stats["flying"] = bool(c["flying"])
	# Un tipo NUEVO que no declara nombre usa su propio id, no el del Hollow, del
	# que hereda la fila. Sin esto el kill feed decía "Hollow" al matar a otra cosa.
	var nombre_base: String = String(stats.get("name", tipo)) if existe else tipo
	stats["name"] = String(c.get("name", nombre_base))

	# --- regla de aparición ---
	var spawn: Dictionary = (GameData.ENEMY_SPAWN.get(tipo, {}) as Dictionary).duplicate(true)
	if spawn.is_empty():
		# Default de un tipo nuevo: aparece desde la oleada 3 y en poca cantidad.
		# Es deliberadamente tímido — un mod no debería inundar la partida por
		# olvidarse de declarar la regla.
		spawn = {"min_wave": 3, "flat": 1}
	var sc = c.get("spawn", {})
	if typeof(sc) == TYPE_DICTIONARY:
		for campo: String in LIMITES_SPAWN:
			if not sc.has(campo):
				continue
			var lim: Array = LIMITES_SPAWN[campo]
			spawn[campo] = clampf(float(sc[campo]), lim[0], lim[1])
		if sc.has("min_wave"):
			spawn["min_wave"] = int(spawn["min_wave"])
		if sc.has("rand") and typeof(sc["rand"]) == TYPE_ARRAY and (sc["rand"] as Array).size() == 2:
			var a := clampi(int((sc["rand"] as Array)[0]), 0, 200)
			var b := clampi(int((sc["rand"] as Array)[1]), 0, 200)
			spawn["rand"] = [mini(a, b), maxi(a, b)]
		if sc.has("dist") and typeof(sc["dist"]) == TYPE_ARRAY and (sc["dist"] as Array).size() == 2:
			spawn["spawn_dist"] = [
				clampf(float((sc["dist"] as Array)[0]), 10.0, 200.0),
				clampf(float((sc["dist"] as Array)[1]), 10.0, 200.0)]

	# Un tipo que no puede aparecer nunca es casi siempre un error de tipeo.
	if int(spawn.get("share", 0)) == 0 and float(spawn.get("share", 0.0)) == 0.0 \
			and int(spawn.get("flat", 0)) == 0 and not spawn.has("rand"):
		res["warnings"].append("\"%s\": con estas reglas de aparición nunca va a spawnear" % tipo)

	# --- comportamiento ---
	var preset := String(c.get("preset", "chaser"))
	if not PRESETS.has(preset):
		res["warnings"].append("\"%s\": preset \"%s\" no existe, se usa \"chaser\" (hay: %s)" % [
			tipo, preset, ", ".join(PRESETS)])
		preset = "chaser"

	# --- color de minimapa ---
	var color := Color(0.5, 0.1, 0.1)
	var declara_color := false
	if c.has("color") and typeof(c["color"]) == TYPE_ARRAY and (c["color"] as Array).size() >= 3:
		var arr: Array = c["color"]
		color = Color(clampf(float(arr[0]), 0.0, 1.0), clampf(float(arr[1]), 0.0, 1.0), clampf(float(arr[2]), 0.0, 1.0))
		declara_color = true

	# --- rasgos componibles ---
	var traits := {}
	var tc = c.get("traits", {})
	if typeof(tc) == TYPE_DICTIONARY:
		for nombre: String in tc:
			if not EnemyTraits.REGISTRO.has(nombre):
				res["warnings"].append("\"%s\": el rasgo \"%s\" no existe (hay: %s)" % [
					tipo, nombre, ", ".join(EnemyTraits.REGISTRO.keys())])
				continue
			traits[nombre] = _un_trait(tipo, nombre, tc[nombre], res)

	res["data"] = {
		"stats": stats, "spawn": spawn, "color": color, "declara_color": declara_color,
		"model": modelo, "preset": preset, "opts": _opciones_modelo(c),
		"traits": traits, "existia": existe,
		"sounds": _sonidos(tipo, c, mod_dir, res, existe),
	}
	return res

## Resuelve la sección `"sounds"` a RUTAS, no a streams: cargarlas es tarea de
## `ModManager` con `ModSoundLoader`, igual que con los modelos. Acá sólo se valida
## que las rutas estén adentro de la carpeta del mod y que las ranuras existan.
##
## Forma esperada:
##     "sounds": {
##       "attack": "audio/mordida.ogg",
##       "hit":    ["audio/dolor1.ogg", "audio/dolor2.ogg"],
##       "volume": 0.8, "inherit": "hollow", "silent": false
##     }
##
## Una LISTA es variación al azar. No es un lujo: escuchar exactamente el mismo
## alarido doscientas veces por partida es la fatiga auditiva más barata de evitar,
## y sale gratis.
static func _sonidos(tipo: String, c: Dictionary, mod_dir: String, res: Dictionary, existe: bool) -> Dictionary:
	var out := {}
	var sc = c.get("sounds", {})
	if typeof(sc) != TYPE_DICTIONARY:
		if c.has("sounds"):
			res["warnings"].append("\"%s\": \"sounds\" se ignoró, no es un objeto" % tipo)
		return out

	# `silent` es el opt-out explícito: mudo A PROPÓSITO, sin heredar nada. Es
	# distinto de "no declaró nada", que hereda del tipo base — las dos intenciones
	# tienen que ser expresables o el sistema decide por el modder.
	if bool(sc.get("silent", false)):
		out["_silent"] = true
	# De qué tipo base sacar lo que no declaró. Por defecto el tipo que reemplaza;
	# si es nuevo, el Hollow, que es el enemigo más neutro que hay.
	out["_inherit"] = String(sc.get("inherit", tipo if existe else "hollow"))
	# Los packs vienen con niveles dispares y normalizarlos a mano no es razonable.
	var vol := float(sc.get("volume", 1.0))
	var vol2 := clampf(vol, 0.0, 2.0)
	if not is_equal_approx(vol, vol2):
		res["warnings"].append("\"%s\": volume=%s quedó fuera de rango, se ajustó a %s" % [tipo, vol, vol2])
	out["_volume"] = vol2

	for clave in sc:
		var k := String(clave)
		if k in ["silent", "inherit", "volume"]:
			continue
		if not RANURAS_SONIDO.has(k):
			res["warnings"].append("\"%s\": la ranura de sonido \"%s\" no existe (hay: %s)" % [
				tipo, k, ", ".join(RANURAS_SONIDO)])
			continue
		var crudo = sc[k]
		var relativas: Array = crudo if typeof(crudo) == TYPE_ARRAY else [crudo]
		var rutas: Array = []
		for r in relativas:
			if rutas.size() >= MAX_VARIANTES_SONIDO:
				res["warnings"].append("\"%s\": \"%s\" tiene más de %d variantes; se usan las primeras" % [
					tipo, k, MAX_VARIANTES_SONIDO])
				break
			var rel := String(r)
			var abs := mod_dir.path_join(rel).simplify_path()
			# Un mod no puede leer fuera de su carpeta. Misma regla que el modelo:
			# sin esto, `"../../../Windows/..."` sería una ruta válida.
			if not abs.begins_with(mod_dir):
				res["warnings"].append("\"%s\": la ruta de sonido \"%s\" sale de la carpeta del mod" % [tipo, rel])
				continue
			if not FileAccess.file_exists(abs):
				res["warnings"].append("\"%s\": no existe el sonido \"%s\"" % [tipo, rel])
				continue
			# La extensión se rechaza ACÁ y no recién al cargar. Si no, el manifiesto
			# guarda una ruta que después falla, y `mod_report` — que lee el
			# manifiesto — anuncia una ranura que en realidad quedó muerta. Una
			# herramienta que miente sobre lo que cargó es peor que no tenerla.
			if not ModSoundLoader.EXTENSIONES.has(abs.get_extension().to_lower()):
				res["warnings"].append("\"%s\": \"%s\" no es un formato de audio soportado (usar %s)" % [
					tipo, rel, ", ".join(ModSoundLoader.EXTENSIONES)])
				continue
			rutas.append(abs)
		if not rutas.is_empty():
			out[k] = rutas

	# Declarar sonidos Y pedir silencio a la vez es contradictorio, y casi seguro
	# quedó `silent` de una prueba anterior. Gana el silencio (es lo explícito),
	# pero se avisa, porque si no el modder ve sus archivos ignorados sin motivo.
	if out.get("_silent", false) and out.size() > 3:
		res["warnings"].append("\"%s\": declara sonidos pero también \"silent\": true; queda MUDO" % tipo)
	return out

## Valida los parámetros de un rasgo contra `EnemyTraits.REGISTRO`, que es la única
## fuente de verdad de qué acepta cada uno y entre qué valores.
static func _un_trait(tipo: String, nombre: String, crudo, res: Dictionary) -> Dictionary:
	var spec: Dictionary = EnemyTraits.REGISTRO[nombre]
	var out := {}
	# `"headshot_immune": true` es la forma natural de escribir un rasgo sin
	# parámetros; obligar a poner `{}` sería innecesariamente ceremonioso.
	if typeof(crudo) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = crudo
	for clave: String in d:
		if not spec.has(clave):
			res["warnings"].append("\"%s\": \"%s\" no tiene parámetro \"%s\"" % [tipo, nombre, clave])
			continue
		var rango = (spec[clave] as Array)[1]
		if rango == null:
			# Sin rango declarado: es texto o booleano, se toma tal cual.
			out[clave] = d[clave]
			continue
		var v := float(d[clave])
		var v2 := clampf(v, float((rango as Array)[0]), float((rango as Array)[1]))
		if not is_equal_approx(v, v2):
			res["warnings"].append("\"%s\": %s.%s=%s fuera de rango, se ajustó a %s" % [
				tipo, nombre, clave, v, v2])
		out[clave] = v2
	return out

## Lo que hoy está hardcodeado contra los dos packs del juego y un modelo ajeno
## necesita poder pisar. Todos los defaults son el valor actual, así que un mod que
## no declara nada se comporta exactamente como antes.
static func _opciones_modelo(c: Dictionary) -> Dictionary:
	var o := {}
	if c.has("model_yaw"):
		o["yaw"] = float(c["model_yaw"])

	var h = c.get("head", {})
	if typeof(h) == TYPE_DICTIONARY:
		if h.has("keywords") and typeof(h["keywords"]) == TYPE_ARRAY:
			o["head_keywords"] = _a_minusculas(h["keywords"])
		if h.has("bone"):
			o["head_bone"] = String(h["bone"]).to_lower()
		if h.has("mult"):
			o["head_mult"] = clampf(float(h["mult"]), 0.1, 4.0)
		# Desde qué fracción de la altura para arriba cuenta como cabeza, cuando no
		# se pudo medir una esfera. 0.85 = el 15% superior (el default del juego).
		# Es la perilla que de verdad sirve para los modelos de la comunidad: casi
		# ninguno tiene una submalla de cabeza que aislar.
		if h.has("band"):
			o["head_band"] = clampf(float(h["band"]), 0.3, 0.98)
		if h.has("use_torso_floor"):
			o["head_torso_floor"] = bool(h["use_torso_floor"])

	var hb = c.get("hitbox", {})
	if typeof(hb) == TYPE_DICTIONARY and hb.has("shape"):
		var s := String(hb["shape"]).to_lower()
		if s == "capsule" or s == "sphere" or s == "auto":
			o["shape"] = s

	var eq = c.get("equipment", {})
	if typeof(eq) == TYPE_DICTIONARY:
		if eq.has("hide") and typeof(eq["hide"]) == TYPE_ARRAY:
			o["equip_hide"] = _a_minusculas(eq["hide"])
		if eq.has("keep") and typeof(eq["keep"]) == TYPE_ARRAY:
			o["equip_keep"] = _a_strings(eq["keep"])

	var an = c.get("anim", {})
	if typeof(an) == TYPE_DICTIONARY:
		var mapa := {}
		for ranura: String in ["idle", "run", "attack", "death", "hit"]:
			if not an.has(ranura):
				continue
			# Se acepta tanto una cadena suelta como una lista: el modder no tiene
			# por qué saber que internamente son candidatos en orden.
			if typeof(an[ranura]) == TYPE_ARRAY:
				mapa[ranura] = _a_strings(an[ranura])
			else:
				mapa[ranura] = [String(an[ranura])]
		if not mapa.is_empty():
			o["anim"] = mapa
	return o

static func _a_strings(a: Array) -> Array:
	var out: Array = []
	for x in a:
		out.append(String(x))
	return out

static func _a_minusculas(a: Array) -> Array:
	var out: Array = []
	for x in a:
		out.append(String(x).to_lower())
	return out
