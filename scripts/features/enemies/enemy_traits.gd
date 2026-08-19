class_name EnemyTraits
extends RefCounted
## Rasgos que un mod puede componer sobre un enemigo, además de su `preset` de
## movimiento. El preset es UNO (cómo se mueve); los traits son cero o más y son
## ortogonales entre sí (qué le pasa además).
##
## **El estado de los traits NO va como campos de `Enemy`.** Hoy todo enemigo ya
## carga `knight_dash_timer`, `capra_state`, `orbit_*`, `skull_timer` aunque no sea
## de ese tipo; sumar 2-3 campos por trait multiplicaría eso por los 50 enemigos
## vivos. Van todos en un solo `e.trait_state`.
##
## Lo que NO se puede hacer con esto, dicho de frente: lógica condicional propia
## ("si el jugador está bajo de vida, huye"), jefes multifase, contadores del
## modder, armas nuevas. Eso necesitaría ejecutar código de terceros, que es
## justamente lo que este sistema evita. El registro está armado para que el día
## que se decida lo contrario sea agregar una entrada, no rehacerlo.

## Nombre -> parámetros aceptados con su default y su rango. `ModManifest` valida
## contra esta tabla, así que agregar un trait es agregar una fila acá y su
## enganche en `enemy.gd`.
const REGISTRO := {
	# Generaliza el `enemy_type == "knight"` de `is_headshot_immune()`.
	"headshot_immune": {},

	# El Blood Lord ya explotaba en 2 murciélagos con código propio; esto es lo
	# mismo para cualquier tipo y cualquier invocado.
	"summon_on_death": {
		"type": ["", null], "count": [2, [1, 20]], "spread": [0.6, [0.0, 10.0]],
	},

	# Nuevo. Reusa `explosion.tscn`, o sea el mismo efecto y la misma caída de daño
	# que La Maleducada.
	"explode_on_death": {
		"radius": [8.0, [0.5, 40.0]], "damage": [40.0, [0.0, 5000.0]],
	},

	# Nuevo. Absorbe daño antes que la vida y se recarga si lo dejan tranquilo.
	"shield": {
		"amount": [50.0, [1.0, 100000.0]],
		"regen_delay": [3.0, [0.0, 60.0]], "regen_rate": [10.0, [0.0, 1000.0]],
	},

	# Nuevo. Al recibir un golpe acelera un rato. Es lo contrario del frenón que ya
	# tiene el juego, así que un enemigo con esto se siente muy distinto.
	"on_hit_speed_burst": {
		"mult": [1.5, [1.0, 5.0]], "time": [1.0, [0.1, 10.0]],
	},

	# Nuevo. Invisible hasta que te le acercás. No lo saca del minimapa salvo que
	# se pida: que no se vea NI en el minimapa es bastante cruel.
	"cloak": {
		"reveal_distance": [12.0, [1.0, 100.0]], "hide_on_minimap": [false, null],
	},
}

## ¿Este tipo tiene el trait? Barato: `trait_state` no se toca acá.
static func has(e: Enemy, nombre: String) -> bool:
	return e.traits.has(nombre)

## Parámetro del trait, ya validado por `ModManifest`. El default sale del REGISTRO
## para que no haya dos fuentes de verdad.
static func param(e: Enemy, nombre: String, clave: String, alterno = null):
	var t: Dictionary = e.traits.get(nombre, {})
	if t.has(clave):
		return t[clave]
	var spec: Dictionary = REGISTRO.get(nombre, {})
	if spec.has(clave):
		return (spec[clave] as Array)[0]
	return alterno

# --- Enganches --------------------------------------------------------------
# Cada uno se llama desde un punto de `enemy.gd`. Todos empiezan con un `has()`
# que sale al toque, así que un enemigo sin traits (o sea, los 8 base) paga una
# búsqueda en un diccionario vacío y nada más.

## Al nacer. Deja el escudo cargado.
static func on_spawn(e: Enemy) -> void:
	if has(e, "shield"):
		e.trait_state["shield"] = float(param(e, "shield", "amount"))
		e.trait_state["shield_cd"] = 0.0

## Absorbe daño con el escudo y devuelve lo que le queda para la vida.
static func absorb(e: Enemy, dmg: float) -> float:
	if not has(e, "shield"):
		return dmg
	var esc: float = e.trait_state.get("shield", 0.0)
	# El retardo se reinicia con CADA golpe, incluso si el escudo ya está en cero:
	# si no, un enemigo bajo fuego sostenido regeneraría escudo mientras le pegan.
	e.trait_state["shield_cd"] = float(param(e, "shield", "regen_delay"))
	if esc <= 0.0:
		return dmg
	var absorbido: float = minf(esc, dmg)
	e.trait_state["shield"] = esc - absorbido
	return dmg - absorbido

## Por frame. Recarga de escudo y vencimiento de la ráfaga de velocidad.
static func tick(e: Enemy, delta: float) -> void:
	if e.traits.is_empty():
		return
	if has(e, "shield"):
		var cd: float = e.trait_state.get("shield_cd", 0.0)
		if cd > 0.0:
			e.trait_state["shield_cd"] = cd - delta
		else:
			var tope: float = float(param(e, "shield", "amount"))
			var esc: float = e.trait_state.get("shield", 0.0)
			if esc < tope:
				e.trait_state["shield"] = minf(tope, esc + float(param(e, "shield", "regen_rate")) * delta)
	if has(e, "on_hit_speed_burst"):
		var t: float = e.trait_state.get("burst", 0.0)
		if t > 0.0:
			e.trait_state["burst"] = t - delta

## Multiplicador de velocidad que aportan los traits. 1.0 = no tocan nada.
static func speed_mult(e: Enemy) -> float:
	if has(e, "on_hit_speed_burst") and float(e.trait_state.get("burst", 0.0)) > 0.0:
		return float(param(e, "on_hit_speed_burst", "mult"))
	return 1.0

## Al recibir un golpe (dentro del cooldown de acuse, así que no se dispara varias
## veces por frame con las automáticas).
static func on_hit(e: Enemy) -> void:
	if has(e, "on_hit_speed_burst"):
		e.trait_state["burst"] = float(param(e, "on_hit_speed_burst", "time"))

## Al morir. Va ANTES del `queue_free()` de quien llama.
static func on_death(e: Enemy) -> void:
	if e.traits.is_empty():
		return
	if has(e, "explode_on_death"):
		var r: float = float(param(e, "explode_on_death", "radius"))
		# Le pega AL JUGADOR, no a los otros enemigos: una oleada de bichos
		# explosivos se mataría sola en cadena.
		FxManager.spawn_explosion(e.global_position, r, r,
			float(param(e, "explode_on_death", "damage")), "player")
	if has(e, "summon_on_death"):
		var tipo := String(param(e, "summon_on_death", "type"))
		# Se valida acá y no sólo al parsear porque el tipo invocado puede venir de
		# OTRO mod que el jugador apagó después. Invocar un tipo inexistente
		# spawnearía un enemigo con las stats del Hollow y el modelo de nadie.
		if tipo != "" and GameData.enemy_stats.has(tipo):
			_summon(e, tipo,
				int(param(e, "summon_on_death", "count")),
				float(param(e, "summon_on_death", "spread")))

static func _summon(e: Enemy, tipo: String, cantidad: int, disp: float) -> void:
	var escena: PackedScene = load("res://scenes/enemy.tscn")
	for i in cantidad:
		var n = escena.instantiate()
		n.enemy_type = tipo
		# Igual que los murciélagos del Blood Lord: lo invocado NO cuenta para el
		# total de la oleada, o sea que un mod no puede hacer que la oleada no
		# termine nunca invocando en cadena.
		n.counts_for_wave = false
		e.get_tree().current_scene.add_child(n)
		n.global_position = e.global_position + Vector3(
			randf_range(-disp, disp), 0.4, randf_range(-disp, disp))

## A qué distancia deja de dibujarse. Sin `cloak` es el LOD normal del juego; con
## `cloak`, la distancia de revelado (que siempre es menor, si no no ocultaría nada).
static func cull_distance(e: Enemy, por_defecto: float) -> float:
	if not has(e, "cloak"):
		return por_defecto
	return minf(por_defecto, float(param(e, "cloak", "reveal_distance")))

## ¿Se dibuja en el minimapa? Un `cloak` sin `hide_on_minimap` sí: que no se vea
## por ningún lado es bastante cruel.
static func on_minimap(e: Enemy) -> bool:
	if not has(e, "cloak"):
		return true
	if not bool(param(e, "cloak", "hide_on_minimap")):
		return true
	var d: float = float(param(e, "cloak", "reveal_distance"))
	return e.dist_to_player_sq <= d * d
