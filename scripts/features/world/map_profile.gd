class_name MapProfile
extends RefCounted
## Los números con los que `world.gd` genera la arena, sacados de sus constantes
## para que un mod pueda retunearlos.
##
## Un mapa acá NO es geometría: es este puñado de parámetros. Se eligió así porque
## `world.gd` ya generaba todo por código, así que exponerlo es barato y con quince
## números el mapa ya se siente otro (radio, densidad de cobertura, altura de los
## muros, paleta). Cargar un `.glb` como escenario es otra cosa y está bloqueado
## por algo concreto: `enemy.gd` asume PISO PLANO (los enemigos lejanos no llaman
## `move_and_slide()`, se les fija la Y), así que con desnivel todo lo que está a
## más de 32 m flota o se entierra. Ver §7 de CLAUDE.md.

## Todos los valores por defecto son EXACTAMENTE los que tenía el juego hardcodeados.
## Un mapa que no declara un campo se comporta igual que antes en ese campo.
const DEFECTO := {
	"name": "Arena",
	"arena_radius": 50.0,
	"obstacles": {
		"count": 20, "seed": 42, "size_min": 2.0, "size_max": 6.0,
		"height_min": 2.0, "height_max": 8.0, "keep_out": 5.0,
	},
	"walls": {"base_height": 3.0, "extra_height": 6.0},
	"sky": {
		"calm_top": [0.05, 0.03, 0.08], "calm_horizon": [0.16, 0.08, 0.12],
		"chaos_top": [0.25, 0.02, 0.03], "chaos_horizon": [0.55, 0.08, 0.05],
	},
	"fog": {"calm": [0.15, 0.08, 0.12], "chaos": [0.34, 0.13, 0.11], "begin": 20.0, "end": 30.0},
	"moon": {"enabled": true},
	"floor": {"color": []},
	## El modo de juego que trae el mapa. Vacío = el de siempre (oleadas infinitas).
	## `waves` es declarativo A PROPÓSITO: el menú puede decir "este mapa no tiene
	## oleadas" sin ejecutar nada, y el runner puede apagarlas antes del primer
	## frame aunque el modo no se pueda cargar.
	"mode": {},
}

## Modos que shippeamos nosotros. Se valida acá para que un `builtin` mal escrito
## se avise al cargar el mod y no falle en silencio al empezar la partida.
const BUILTIN_VALIDOS := ["survival", "waves10"]

## Rangos de validación. `arena_radius` tiene tope real: el spawn nace a 40-58 m
## del jugador y recorta contra el borde, así que una arena de 15 m dejaría a los
## enemigos naciendo encima tuyo.
const LIMITES := {
	"arena_radius": [25.0, 300.0],
	"count": [0.0, 200.0], "seed": [0.0, 4294967295.0],
	"size_min": [0.5, 30.0], "size_max": [0.5, 30.0],
	"height_min": [0.5, 40.0], "height_max": [0.5, 40.0], "keep_out": [0.0, 60.0],
	"base_height": [0.5, 40.0], "extra_height": [0.0, 60.0],
	"begin": [1.0, 500.0], "end": [2.0, 600.0],
}

## Fusiona lo que declaró el mod sobre los defaults, campo por campo y sin confiar
## en nada. Devuelve {perfil, warnings}.
static func merge(crudo: Dictionary) -> Dictionary:
	var p: Dictionary = DEFECTO.duplicate(true)
	var avisos: Array = []

	p["name"] = String(crudo.get("name", p["name"]))
	if crudo.has("arena_radius"):
		p["arena_radius"] = _num(crudo["arena_radius"], "arena_radius", avisos)

	for grupo: String in ["obstacles", "walls", "fog"]:
		var g = crudo.get(grupo, {})
		if typeof(g) != TYPE_DICTIONARY:
			continue
		for k: String in (p[grupo] as Dictionary):
			# Sólo las claves NUMÉRICAS. `fog` mezcla números (`begin`/`end`) con
			# colores (`calm`/`chaos`, que son arrays [r,g,b]) y los colores los
			# resuelve el bloque de abajo: pasarlos por `float()` tiraba
			# "Nonexistent 'float' constructor" en cada carga.
			var actual = (p[grupo] as Dictionary)[k]
			if typeof(actual) != TYPE_FLOAT and typeof(actual) != TYPE_INT:
				continue
			if g.has(k):
				(p[grupo] as Dictionary)[k] = _num(g[k], k, avisos)

	var sky = crudo.get("sky", {})
	if typeof(sky) == TYPE_DICTIONARY:
		for k: String in (p["sky"] as Dictionary):
			if sky.has(k):
				(p["sky"] as Dictionary)[k] = _rgb(sky[k], (p["sky"] as Dictionary)[k])

	var fog = crudo.get("fog", {})
	if typeof(fog) == TYPE_DICTIONARY:
		for k: String in ["calm", "chaos"]:
			if fog.has(k):
				(p["fog"] as Dictionary)[k] = _rgb(fog[k], (p["fog"] as Dictionary)[k])

	var moon = crudo.get("moon", {})
	if typeof(moon) == TYPE_DICTIONARY and moon.has("enabled"):
		(p["moon"] as Dictionary)["enabled"] = bool(moon["enabled"])

	var floor_c = crudo.get("floor", {})
	if typeof(floor_c) == TYPE_DICTIONARY and floor_c.has("color"):
		(p["floor"] as Dictionary)["color"] = _rgb(floor_c["color"], [])

	var modo = crudo.get("mode", {})
	if typeof(modo) == TYPE_DICTIONARY and not (modo as Dictionary).is_empty():
		p["mode"] = _modo(modo, avisos)

	# Coherencias que si no explotan más adelante y son dificilísimas de atribuir.
	var ob: Dictionary = p["obstacles"]
	if float(ob["size_min"]) > float(ob["size_max"]):
		avisos.append("size_min > size_max: se intercambiaron")
		var t = ob["size_min"]; ob["size_min"] = ob["size_max"]; ob["size_max"] = t
	if float(ob["height_min"]) > float(ob["height_max"]):
		avisos.append("height_min > height_max: se intercambiaron")
		var t2 = ob["height_min"]; ob["height_min"] = ob["height_max"]; ob["height_max"] = t2
	var fg: Dictionary = p["fog"]
	if float(fg["begin"]) >= float(fg["end"]):
		avisos.append("la niebla empieza donde termina; se corrió el final")
		fg["end"] = float(fg["begin"]) + 10.0

	return {"perfil": p, "warnings": avisos}

## Normaliza el modo declarado por el mapa. Nada de acá ejecuta código: es sólo
## qué modo built-in usar, con qué parámetros y si hay oleadas.
static func _modo(m: Dictionary, avisos: Array) -> Dictionary:
	var out := {
		"name": String(m.get("name", "")),
		"description": String(m.get("description", "")),
		"waves": bool(m.get("waves", true)),
		"builtin": String(m.get("builtin", "survival")),
		"params": {},
	}
	if not BUILTIN_VALIDOS.has(out["builtin"]):
		avisos.append("el modo \"%s\" no existe (hay: %s); se usa survival" % [
			out["builtin"], ", ".join(PackedStringArray(BUILTIN_VALIDOS))])
		out["builtin"] = "survival"

	# Los parámetros llegan tal cual al modo, así que sólo se aceptan escalares y
	# listas: un diccionario anidado sin límite es una puerta a datos raros.
	var ps = m.get("params", {})
	if typeof(ps) == TYPE_DICTIONARY:
		for k: String in ps:
			var v = ps[k]
			var t := typeof(v)
			if t == TYPE_FLOAT or t == TYPE_INT or t == TYPE_BOOL or t == TYPE_STRING or t == TYPE_ARRAY:
				(out["params"] as Dictionary)[k] = v
			else:
				avisos.append("el parámetro \"%s\" del modo se ignoró (tipo no admitido)" % k)

	if out["name"] == "":
		out["name"] = out["builtin"]
	return out

static func _num(v, clave: String, avisos: Array) -> float:
	var f := float(v)
	if not LIMITES.has(clave):
		return f
	var lim: Array = LIMITES[clave]
	var f2 := clampf(f, lim[0], lim[1])
	if not is_equal_approx(f, f2):
		avisos.append("%s=%s fuera de rango, se ajustó a %s" % [clave, f, f2])
	return f2

static func _rgb(v, alterno):
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
		var a: Array = v
		return [clampf(float(a[0]), 0.0, 1.0), clampf(float(a[1]), 0.0, 1.0), clampf(float(a[2]), 0.0, 1.0)]
	return alterno

## Los colores viajan como [r,g,b] para que el JSON sea legible; acá se convierten.
static func color_of(a) -> Color:
	if typeof(a) == TYPE_ARRAY and (a as Array).size() >= 3:
		var x: Array = a
		return Color(float(x[0]), float(x[1]), float(x[2]))
	return Color.WHITE
