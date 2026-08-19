extends Node
## Autoload. Constantes globales + tablas de datos (armas, rareza, enemigos, oleadas).
## Fuente: ../FaverMass_Especificacion_Godot.docx

# --- 1. Constantes globales ---
const ARENA_RADIUS := 50.0
const GRAVITY := 20.0
const PLAYER_HEIGHT_STAND := 1.7
const PLAYER_HEIGHT_CROUCH := 1.0
const PLAYER_SPEED := 7.0
const SPRINT_MULT := 1.6
const CROUCH_MULT := 0.5
const JUMP_FORCE := 8.0
const MAX_HEALTH := 100.0
const MAX_ECSTASY := 100.0
## Más allá de esta distancia los enemigos NO se dibujan ni se animan. Va de la
## mano con la pared de niebla de `main.tscn` (opaca a 30): el corte tiene que
## caer detrás de la niebla para que no se vea aparecer nada de la nada.
## Si se mueve una, se mueve la otra.
const ENEMY_LOD_DISTANCE := 32.0
const RAILGUN_SPEED_MULT := 1.3

# --- 3.3 Rareza ---
enum Rarity { COMMON, RARE, EPIC, LEGENDARY, CURSED }

const RARITY_DAMAGE_MULT := {
	Rarity.COMMON: 1.0, Rarity.RARE: 1.3, Rarity.EPIC: 1.7, Rarity.LEGENDARY: 2.5, Rarity.CURSED: 3.5,
}
const RARITY_AMMO_MULT := {
	Rarity.COMMON: 1.0, Rarity.RARE: 1.3, Rarity.EPIC: 1.5, Rarity.LEGENDARY: 2.0, Rarity.CURSED: 0.5,
}
const RARITY_COLOR := {
	Rarity.COMMON: Color(0.8, 0.8, 0.8),
	Rarity.RARE: Color(0.3, 0.5, 1.0),
	Rarity.EPIC: Color(0.62, 0.22, 0.9),
	Rarity.LEGENDARY: Color(1.0, 0.84, 0.2),
	Rarity.CURSED: Color(0.55, 0.05, 0.05),
}
const RARITY_NAME := {
	Rarity.COMMON: "Common", Rarity.RARE: "Rare", Rarity.EPIC: "Epic",
	Rarity.LEGENDARY: "Legendary", Rarity.CURSED: "Cursed",
}

# Rareza mínima para que un arma pueda salir en el pool aleatorio (Cursed cuenta como Legendary)
const WEAPON_MIN_RARITY := {
	"pistol": Rarity.COMMON, "smg": Rarity.COMMON, "ak47": Rarity.COMMON, "shotgun": Rarity.COMMON,
	"revolver": Rarity.RARE, "sniper": Rarity.RARE, "lmg": Rarity.RARE,
	"minigun": Rarity.EPIC,
	"rocket": Rarity.LEGENDARY,
	# "railgun" excluida a propósito: nunca sale del pool aleatorio.
}

# --- 3. Armas (stats BASE, sin rareza) ---
# auto: dispara mientras se mantiene click. semi: un disparo por click físico.
# pierce: cantidad de enemigos que atraviesa una misma bala (0 = se detiene en el primero).
#
# no_cooldown: NO hay tiempo mínimo entre disparos — el único límite es lo rápido
# que el jugador pueda clickear. Va en Pistol, Revolver, Sniper y Shotgun por
# pedido explícito del usuario: son "a click puro". Si a alguna de esas cuatro se
# le vuelve a poner un `fire_rate` sin `no_cooldown`, se rompe esa sensación.
# La Pistol además dejó de ser `auto`: mantener el botón ya no tira sola.
#
# spinup: el arma "se calienta" con el fuego sostenido — cadencia Y daño suben
# progresivamente hasta SPINUP_MAX mientras se mantenga el gatillo, y bajan al
# soltarlo. Va en SMG, LMG y Minigun (las de spray). Ver player.gd.
const WEAPONS := {
	"pistol": {
		"name": "Pistol", "damage": 40.0, "hs_mult": 3.0, "fire_rate": 0.0, "ammo": 15,
		"spread": 0.02, "pellets": 1, "auto": false, "pierce": 0,
		"no_cooldown": true,
	},
	"revolver": {
		"name": "Revolver", "damage": 55.0, "hs_mult": 3.5, "fire_rate": 0.0, "ammo": 6,
		"spread": 0.01, "pellets": 1, "auto": false, "pierce": 10,
		"fixed_ammo": true, "exp_damage": true, "no_cooldown": true,
	},
	"smg": {
		"name": "SMG", "damage": 14.0, "hs_mult": 2.5, "fire_rate": 14.0, "ammo": 35,
		"spread": 0.04, "pellets": 1, "auto": true, "pierce": 0, "spinup": true,
	},
	"ak47": {
		"name": "AK-47", "damage": 30.0, "hs_mult": 3.0, "fire_rate": 9.0, "ammo": 30,
		"spread": 0.03, "pellets": 1, "auto": true, "pierce": 0,
	},
	"shotgun": {
		"name": "Shotgun", "damage": 18.0, "hs_mult": 2.0, "fire_rate": 0.0, "ammo": 8,
		"spread": 0.08, "pellets": 8, "auto": false, "pierce": 0,
		"no_cooldown": true,
	},
	"sniper": {
		"name": "Sniper", "damage": 120.0, "hs_mult": 5.0, "fire_rate": 0.0, "ammo": 10,
		"spread": 0.005, "pellets": 1, "auto": false, "pierce": 10,
		"no_cooldown": true,
	},
	"lmg": {
		"name": "LMG", "damage": 18.0, "hs_mult": 2.5, "fire_rate": 11.0, "ammo": 100,
		"spread": 0.05, "pellets": 1, "auto": true, "pierce": 0, "spinup": true,
	},
	"minigun": {
		"name": "Minigun", "damage": 10.0, "hs_mult": 3.0, "fire_rate": 25.0, "ammo": 250,
		"spread": 0.07, "pellets": 1, "auto": true, "pierce": 0, "spinup": true,
	},
	"rocket": {
		"name": "La Maleducada", "damage": 300.0, "hs_mult": 1.5, "fire_rate": 0.7, "ammo": 4,
		"spread": 0.02, "pellets": 1, "auto": false, "pierce": 0, "explosive": true,
	},
	"railgun": {
		"name": "Railgun", "damage": 0.0, "hs_mult": 0.0, "fire_rate": 0.0, "ammo": 0,
		"spread": 0.0, "pellets": 0, "auto": false, "pierce": 0, "beam": true,
	},
}

const PISTOL_BURST_COOLDOWN := 0.42
const PISTOL_BURST_SPREAD_MULT := 1.6
const RAILGUN_BEAM_DURATION := 5.0
# El radio de DAÑO y el de la ANIMACIÓN son distintos a propósito.
#
# Antes eran el mismo (7.5) y el usuario reportó que "la animación es más grande
# que el área en la que hace daño". No era un error de geometría —la cáscara
# llega exactamente al radio— sino la CAÍDA LINEAL del daño: un enemigo envuelto
# en la bola de fuego a 6 m se comía 42 de daño sobre 341 de vida, o sea nada.
#
# Ahora el área de daño es el doble que la visible. El usuario lo aprobó
# explícitamente ("no pasa nada si es al revés"): es preferible que mate un poco
# más allá de las llamas a que perdone adentro de ellas.
const ROCKET_EXPLOSION_RADIUS := 15.0
const ROCKET_EXPLOSION_VISUAL_RADIUS := 7.5
const ROCKET_CENTER_DAMAGE_MULT := 0.7

# --- 6. Enemigos ---
const ENEMY_STATS := {
	"hollow": {"name": "Hollow", "hp": 100.0, "speed": 3.8, "damage": 10.0, "atk_cd": 1.0,
		"xp": 5, "regen": 2.0, "radius": 0.52, "height": 2.35, "head_radius": 0.30, "flying": false},
	"thrall": {"name": "Thrall", "hp": 50.0, "speed": 7.5, "damage": 8.0, "atk_cd": 0.6,
		"xp": 5, "regen": 1.0, "radius": 0.42, "height": 2.05, "head_radius": 0.25, "flying": false},
	"dire_bat": {"name": "Dire Bat", "hp": 1.0, "speed": 8.0, "damage": 5.0, "atk_cd": 0.4,
		"xp": 2, "regen": 1.0, "radius": 0.30, "height": 0.55, "head_radius": 0.18, "flying": true},
	"blood_lord": {"name": "Blood Lord", "hp": 80.0, "speed": 5.0, "damage": 12.0, "atk_cd": 0.8,
		"xp": 7, "regen": 2.0, "radius": 0.48, "height": 2.30, "head_radius": 0.28, "flying": false},
	"knight": {"name": "Knight", "hp": 500.0, "speed": 2.6, "damage": 25.0, "atk_cd": 1.5,
		"xp": 15, "regen": 3.0, "radius": 0.95, "height": 3.30, "head_radius": 0.36, "flying": false},
	# Capra y Thrall comparten modelo (Skeleton_Warrior, el del casco con cuernos),
	# así que lo ÚNICO que los distingue en pantalla es el tamaño: la Capra va
	# 1.5x el Thrall a propósito. Si algún día se les cambia la altura, mantener
	# esa distancia o se vuelven indistinguibles en pleno combate.
	"capra": {"name": "Capra", "hp": 120.0, "speed": 8.0, "damage": 18.0, "atk_cd": 1.2,
		"xp": 10, "regen": 2.0, "radius": 0.64, "height": 3.10, "head_radius": 0.38, "flying": false},
	"sorceress": {"name": "Sorceress", "hp": 1.0, "speed": 3.5, "damage": 8.0, "atk_cd": 0.5,
		"xp": 2, "regen": 1.0, "radius": 0.42, "height": 2.05, "head_radius": 0.25, "flying": true},
	"demon_skull": {"name": "Demon Skull", "hp": 30.0, "speed": 6.0, "damage": 10.0, "atk_cd": 0.7,
		"xp": 4, "regen": 1.0, "radius": 0.38, "height": 0.85, "head_radius": 0.28, "flying": true},
}

const ALPHA_HP_MULT := 5.0
const ALPHA_DAMAGE_MULT := 2.0
const ALPHA_RADIUS_MULT := 1.5
const ALPHA_HEIGHT_MULT := 1.4
const ALPHA_HEAD_MULT := 1.3
const ALPHA_XP_MULT := 3.0
const ALPHA_REGEN := 3.0

const ENEMY_COLOR := {
	"hollow": Color(0.55, 0.12, 0.1), "thrall": Color(0.65, 0.35, 0.1),
	"dire_bat": Color(0.15, 0.1, 0.2), "blood_lord": Color(0.5, 0.02, 0.1),
	"knight": Color(0.25, 0.25, 0.3), "capra": Color(0.3, 0.05, 0.05),
	"sorceress": Color(0.35, 0.05, 0.45), "demon_skull": Color(0.7, 0.3, 0.05),
}

# --- 7.0 Reglas de aparición ---
## CUÁNDO y CUÁNTOS aparecen, separado de ENEMY_STATS, que dice qué ES un enemigo.
## Cada fila se evalúa así (ver `wave_composition`):
##     n = int(base * share) + flat
##     if rand: n += randi_range(rand[0], rand[1])
##     if step: n *= (1 + wave / step)          ← división ENTERA
##
## Las 8 filas de abajo REPRODUCEN EXACTAMENTE las fórmulas que antes estaban
## escritas a mano una por una. `knight` es el caso que parece no encajar y encaja:
## `1 + wave/5` es `flat` 1 multiplicado por `(1 + wave/5)`.
##
## ⚠ EL ORDEN DE ESTE DICCIONARIO ES PARTE DEL BALANCE. `wave_composition` consume
## el RNG global al recorrerlo, así que reordenar las filas —o agregar una en el
## medio— corre la secuencia de `randi_range` y cambia TODAS las oleadas. Los tipos
## que vengan de mods se agregan al final, nunca intercalados.
##
## `spawn_dist` es a qué distancia del jugador nace. La Capra nace más lejos porque
## carga a 8 u/s: apareciendo a 40 m no daba tiempo a reaccionar.
const ENEMY_SPAWN := {
	"hollow":      {"min_wave": 1, "share": 0.5},
	"thrall":      {"min_wave": 2, "share": 0.15, "flat": 1},
	"dire_bat":    {"min_wave": 3, "rand": [3, 5], "step": 5},
	"blood_lord":  {"min_wave": 4, "share": 0.1, "flat": 1},
	"knight":      {"min_wave": 5, "flat": 1, "step": 5},
	"capra":       {"min_wave": 6, "share": 0.08, "flat": 1, "spawn_dist": [46.0, 58.0]},
	"sorceress":   {"min_wave": 7, "rand": [2, 4], "step": 8},
	"demon_skull": {"min_wave": 8, "rand": [2, 3], "step": 6},
}

const SPAWN_DIST_DEFAULT := [40.0, 50.0]

# --- Registro EN CALIENTE (base + mods) ---
## `ENEMY_STATS`/`ENEMY_SPAWN`/`ENEMY_COLOR` son `const`: son la tabla de balance
## del juego base y tienen que seguir siendo inmutables y legibles como tal. Lo que
## el juego CONSUME son estas tres copias, que un mod puede pisar.
##
## Nadie fuera de este archivo debería tocarlas directo: usar los accesores de abajo,
## que toleran un tipo inexistente en vez de romper.
var enemy_stats: Dictionary = {}
var enemy_spawn: Dictionary = {}
var enemy_color: Dictionary = {}

func _ready() -> void:
	rebuild_enemy_registry({}, {}, {})

## La llama ModManager DESPUÉS de leer la carpeta de mods, con diccionarios YA
## validados. Este archivo no sabe que existen los mods ni dónde viven.
func rebuild_enemy_registry(stats_ov: Dictionary, spawn_ov: Dictionary, color_ov: Dictionary) -> void:
	# duplicate(true) de un `const` devuelve una copia ESCRIBIBLE; el const en sí es
	# de sólo lectura y `.merge()` sobre él falla en silencio.
	enemy_stats = ENEMY_STATS.duplicate(true)
	enemy_spawn = ENEMY_SPAWN.duplicate(true)
	enemy_color = ENEMY_COLOR.duplicate(true)
	if enemy_stats.is_read_only():
		push_error("GameData: la copia del registro salió de sólo lectura; los mods no van a poder pisar nada")

	# Merge campo por campo: un mod que sólo trae `hp` no borra el resto de la fila.
	for t: String in stats_ov:
		var row: Dictionary = enemy_stats.get(t, ENEMY_STATS["hollow"]).duplicate(true)
		row.merge(stats_ov[t], true)
		enemy_stats[t] = row
	for t: String in spawn_ov:
		var row: Dictionary = enemy_spawn.get(t, {}).duplicate(true)
		row.merge(spawn_ov[t], true)
		enemy_spawn[t] = row
	for t: String in color_ov:
		enemy_color[t] = color_ov[t]

## Fila de stats de un tipo. Un tipo desconocido cae al Hollow en vez de romper:
## `wave_manager` lo indexaba directo y un tipo sin fila tiraba la partida entera.
func enemy_stats_of(t: String) -> Dictionary:
	return enemy_stats.get(t, enemy_stats.get("hollow", ENEMY_STATS["hollow"]))

## El `fallback` es parámetro porque cada consumidor quiere uno distinto: el modelo
## procedural cae a rojo oscuro y el minimapa a blanco. Aplanarlos cambiaría cómo se
## ve el minimapa de un tipo sin color declarado.
func enemy_color_of(t: String, fallback: Color = Color(0.5, 0.1, 0.1)) -> Color:
	return enemy_color.get(t, fallback)

## Nombre para mostrar. Un tipo desconocido devuelve su propio id en vez del nombre
## del Hollow: en el kill feed es preferible leer `goblin` a que mienta "Hollow".
func enemy_name_of(t: String) -> String:
	return enemy_stats.get(t, {}).get("name", t)

func enemy_spawn_of(t: String) -> Dictionary:
	return enemy_spawn.get(t, {})

## Todos los tipos que existen HOY (base + mods). Es la lista que tienen que
## recorrer las herramientas de tools/ en vez de su propio array hardcodeado.
func enemy_types() -> Array:
	return enemy_stats.keys()

## A qué distancia del jugador nace este tipo.
func spawn_dist_of(t: String) -> Array:
	var r: Array = enemy_spawn.get(t, {}).get("spawn_dist", SPAWN_DIST_DEFAULT)
	return r if r.size() == 2 else SPAWN_DIST_DEFAULT

# --- 3.4 Daño final de un disparo ---
## Daño base del arma pasado por rareza y por spin-up. Vive acá y no en
## `player.gd` porque es una FÓRMULA DE BALANCE igual que `hp_mult_of` o
## `roll_rarity`: cambiar cuánto pega un arma legendaria tiene que ser tocar este
## archivo y ninguno más.
static func weapon_damage(w: Dictionary, rarity: int, spinup: float = 1.0) -> float:
	var dmg: float = w["damage"]
	if w.get("exp_damage", false):
		# `exp_damage`: la rareza DUPLICA por escalón en vez de usar la tabla.
		dmg = dmg * pow(2.0, rarity)
	else:
		dmg = dmg * RARITY_DAMAGE_MULT[rarity]
	if w.get("spinup", false):
		dmg *= spinup
	return dmg

# --- 5. Éxtasis ---
static func ecstasy_manual_tier(xp: float) -> int:
	# devuelve -1 (nada), o Rarity a otorgar. Railgun se maneja aparte (>=100 y no equipado).
	if xp >= 75.0:
		return Rarity.LEGENDARY
	if xp >= 50.0:
		return Rarity.RARE
	if xp >= 25.0:
		return Rarity.COMMON
	return -1

static func ecstasy_autocycle_tier(xp: float) -> int:
	if xp >= 75.0:
		return Rarity.LEGENDARY
	if xp >= 50.0:
		return Rarity.RARE
	return Rarity.COMMON

# --- 3.3 Roll de rareza al generar un arma ---
static func roll_rarity(wave: int) -> int:
	var roll := randf()
	var cursed_p := 0.01 + wave * 0.002
	var legendary_p := 0.02 + wave * 0.003
	var epic_p := 0.08 + wave * 0.005
	var rare_p := 0.22 + wave * 0.005
	if roll < cursed_p:
		return Rarity.CURSED
	roll -= cursed_p
	if roll < legendary_p:
		return Rarity.LEGENDARY
	roll -= legendary_p
	if roll < epic_p:
		return Rarity.EPIC
	roll -= epic_p
	if roll < rare_p:
		return Rarity.RARE
	return Rarity.COMMON

static func random_weapon_for_rarity(rarity: int) -> String:
	var effective := rarity
	if rarity == Rarity.CURSED:
		effective = Rarity.LEGENDARY
	var pool: Array = []
	for wid in WEAPON_MIN_RARITY:
		if WEAPON_MIN_RARITY[wid] <= effective:
			pool.append(wid)
	return pool[randi() % pool.size()]

# --- 7. Oleadas ---
static func wave_base(wave: int) -> int:
	return 5 + wave * 3 + (wave * wave) / 8

# --- 7.1 Techo de enemigos y compensación por dificultad ---
#
# La cantidad de enemigos VIVOS es lo que decide el rendimiento: medido, 42
# enemigos dan ~300 FPS y 125 dan 20. Ninguna optimización de código cambia eso
# — son cuerpos físicos y draw calls. Así que la oleada se recorta y la
# dificultad que se pierde se devuelve en vida, velocidad y daño.
#
# **Los multiplicadores dependen SOLO de la oleada, nunca de los FPS medidos.**
# Es a propósito: si las stats reaccionaran al rendimiento, la misma oleada sería
# más difícil en una PC peor o con el navegador abierto atrás, el balance dejaría
# de ser reproducible, y encima se realimenta (bajan los FPS → enemigos más duros
# → tardás más en matarlos → más vivos → bajan más los FPS).
const WAVE_MAX_ENEMIES := 50

## Tope de enemigos VIVOS a la vez, contando los que no cuentan para la oleada
## (cráneos de la Sorceress, murciélagos del Blood Lord). Con el techo de arriba
## casi nunca se activa; está para que una Sorceress inspirada no llene la
## pantalla. Un poco más alto que WAVE_MAX_ENEMIES justamente para dejarle lugar
## a esos invocados sin frenar el spawn de la oleada.
const MAX_ALIVE_ENEMIES := 70

# Topes de los multiplicadores. El de velocidad es el delicado: el jugador corre
# a 7 u/s y el Thrall ya va a 7.5 — pasarse de 1.35 significa que no se puede
# escapar de nada.
const DIFF_HP_CAP := 4.0
const DIFF_SPEED_PER_SURPLUS := 0.20
const DIFF_SPEED_CAP := 1.35
const DIFF_DAMAGE_PER_SURPLUS := 0.35
const DIFF_DAMAGE_CAP := 2.0

## Recorta la composición al techo, proporcionalmente para que la mezcla de tipos
## no cambie, con mínimo 1 por tipo presente: si no, a oleadas altas
## desaparecerían los tipos poco frecuentes (el Knight es 1 solo y se iría a 0).
static func cap_composition(comp: Dictionary) -> Dictionary:
	var total := total_of(comp)
	if total <= WAVE_MAX_ENEMIES:
		return comp.duplicate()
	var factor := float(WAVE_MAX_ENEMIES) / float(total)
	var out: Dictionary = {}
	for k in comp:
		out[k] = maxi(1, int(round(comp[k] * factor)))
	return out

static func total_of(comp: Dictionary) -> int:
	var total := 0
	for n in comp.values():
		total += n
	return total

## Cuántas veces más enemigos QUERÍA mandar la oleada de los que realmente manda.
## Vale exactamente 1.0 mientras la oleada entre en el techo, así que las oleadas
## tempranas no cambian en NADA.
##
## Recibe los dos totales ya calculados en vez de recalcular la composición: la
## composición tiene `randi_range()` adentro, así que llamarla dos veces daría
## números distintos y el multiplicador no coincidiría con lo que se mandó.
static func surplus_of(raw_total: int, sent_total: int) -> float:
	if sent_total <= 0:
		return 1.0
	return maxf(1.0, float(raw_total) / float(sent_total))

static func hp_mult_of(surplus: float) -> float:
	return minf(surplus, DIFF_HP_CAP)

static func speed_mult_of(surplus: float) -> float:
	return minf(1.0 + (surplus - 1.0) * DIFF_SPEED_PER_SURPLUS, DIFF_SPEED_CAP)

static func damage_mult_of(surplus: float) -> float:
	return minf(1.0 + (surplus - 1.0) * DIFF_DAMAGE_PER_SURPLUS, DIFF_DAMAGE_CAP)

## Composición SIN techo: lo que la oleada pediría idealmente. El que la consume
## es `wave_manager.start_wave()`, que la recorta y de paso saca el multiplicador.
## Recorre `enemy_spawn` en ORDEN DE INSERCIÓN, que es lo que preserva el balance:
## las tres llamadas a `randi_range` (dire_bat, sorceress, demon_skull) tienen que
## caer en la misma secuencia del RNG global que cuando esto eran ocho `if` escritos
## a mano. Por eso el `continue` de `min_wave` va ANTES del `randi_range`: en la
## oleada 3 el original tiraba el dado del murciélago pero NO el de la bruja, y ese
## corto-circuito es parte del resultado.
##
## Dejó de ser `static` porque lee el registro en caliente. Todos los llamadores ya
## usaban el prefijo `GameData.`, así que no cambia nada para ellos.
func wave_composition(wave: int) -> Dictionary:
	var base := wave_base(wave)
	var comp: Dictionary = {}
	for t: String in enemy_spawn:
		var r: Dictionary = enemy_spawn[t]
		if wave < int(r.get("min_wave", 1)):
			continue
		var n := int(base * float(r.get("share", 0.0))) + int(r.get("flat", 0))
		var rnd: Array = r.get("rand", [])
		if rnd.size() == 2:
			n += randi_range(int(rnd[0]), int(rnd[1]))
		var step := int(r.get("step", 0))
		if step > 0:
			n *= (1 + wave / step)   # división ENTERA a propósito
		# Los 8 tipos base NUNCA dan 0 (todos tienen piso: `flat` 1 o `rand` >= 2, y
		# hollow es int(base*0.5) con base >= 8), así que este filtro no los toca.
		# Está para los mods: `cap_composition` hace maxi(1, ...) por cada clave
		# presente, o sea que un tipo en 0 se convertiría en 1 enemigo real.
		if n > 0:
			comp[t] = n
	return comp

static func spawn_interval(wave: int) -> float:
	return max(0.08, 0.5 - wave * 0.02)

static func chaos_level(wave: int) -> float:
	return min(wave / 10.0, 3.0)

# La configuración que el jugador cambia (volumen, sensibilidad, FOV, pantalla
# completa) NO vive acá: está en el autoload `Config` (scripts/core/config.gd).
# Escribía a disco y tocaba el DisplayServer, y este archivo tiene que poder
# leerse como una tabla de balance pura — sin estado de sesión y sin depender de
# la plataforma. Las constantes FOV_MIN / FOV_MAX / FOV_DEFAULT se fueron con
# ella, porque son los límites de ese ajuste y no números de balance.
