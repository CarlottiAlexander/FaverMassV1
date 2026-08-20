class_name ModeApi
extends RefCounted
## Lo que un modo de juego puede pedirle al juego. Es la superficie ESTABLE: el
## resto del árbol es alcanzable igual (`Engine.get_main_loop()` está al alcance de
## cualquier GDScript), pero no está documentado y va a cambiar.
##
## Dos reglas que valen para todo lo de acá:
##  1. **Nada explota.** Un tipo de enemigo que no existe, una posición absurda o
##     un modo llamando cosas fuera de tiempo se registran y se ignoran. Un modo
##     mal escrito tiene que quedar raro, no tirar la partida.
##  2. **Los topes son del juego, no de la buena fe del modder.** Spawnear respeta
##     `MAX_ALIVE_ENEMIES`, que es un número MEDIDO en esta máquina.
##
## Arranca chica a propósito: se agrega exactamente lo que pida el primer modo
## real, en vez de inventar una API grande en el vacío.

var _runner: Node = null

func _init(runner: Node) -> void:
	_runner = runner

# --- Fin de partida ---------------------------------------------------------

## Terminar ganando. El modo decide cuándo; el juego no adivina.
func win(titulo := "VICTORIA", detalle := "") -> void:
	GameState.end_run(true, titulo, detalle, _runner.extra_stats)

func lose(titulo := "YOU DIED", detalle := "") -> void:
	GameState.end_run(false, titulo, detalle, _runner.extra_stats)

## Una fila extra en la pantalla final ("Objetivos: 4/4").
func add_stat(etiqueta: String, valor) -> void:
	_runner.extra_stats.append("%s: %s" % [etiqueta, valor])

# --- HUD --------------------------------------------------------------------

## Cartel grande y efímero, arriba de la mira. Reusa el del anuncio de oleada, que
## es un slot ÚNICO: un anuncio nuevo pisa al anterior, no se encola.
func announce(texto: String, seg := 2.0) -> void:
	var hud = _runner.hud()
	if hud:
		hud.mode_announce(texto, seg)

## Línea fija debajo del contador de oleada. Vacío la esconde.
func set_objective(texto: String) -> void:
	var hud = _runner.hud()
	if hud:
		hud.mode_objective = texto

## Pisa el texto grande de arriba a la izquierda. Un modo sin oleadas no debería
## decir "WAVE 0".
func set_wave_label(texto: String) -> void:
	var hud = _runner.hud()
	if hud:
		hud.mode_wave_text = texto

# --- Oleadas ----------------------------------------------------------------

## Apagarlas deja al modo a cargo de spawnear. Ojo: también congela la dificultad
## y la atmósfera, que hoy se derivan del número de oleada — el modo pasa a ser
## responsable de `set_chaos()` y `set_difficulty()`.
func waves_enabled(b: bool) -> void:
	var wm = _runner.wave_manager()
	if wm:
		wm.enabled = b

func current_wave() -> int:
	var wm = _runner.wave_manager()
	return wm.wave if wm else 0

func enemies_alive() -> int:
	return _runner.get_tree().get_nodes_in_group("enemy").size()

## Spawnear en una posición elegida por el modo. Devuelve `false` si se rechazó.
## No cuenta para terminar la oleada.
func spawn_enemy(tipo: String, pos: Vector3, alpha := false) -> bool:
	if not GameData.enemy_stats.has(tipo):
		info("spawn_enemy: el tipo \"%s\" no existe" % tipo)
		return false
	if enemies_alive() >= GameData.MAX_ALIVE_ENEMIES:
		return false
	var wm = _runner.wave_manager()
	if not wm:
		return false
	# Recorte a la arena: una posición absurda dejaría al enemigo fuera del mapa,
	# donde no hay piso, y se caería al vacío.
	var plano := Vector2(pos.x, pos.z)
	if plano.length() > GameData.arena_radius - 2.0:
		plano = plano.normalized() * (GameData.arena_radius - 2.0)
		pos.x = plano.x
		pos.z = plano.y
	return wm.spawn_at(tipo, pos, alpha, false) != null

# --- Atmósfera y dificultad -------------------------------------------------

## 0..3. Maneja cielo, niebla, altura de los muros, escombros y luna.
func set_chaos(nivel: float) -> void:
	GameState.set_chaos(nivel)

## Multiplicadores que aplica cada enemigo AL NACER. No afecta a los que ya están
## vivos, igual que pasa con los de las oleadas.
func set_difficulty(hp: float, velocidad: float, danio: float) -> void:
	GameState.wave_hp_mult = clampf(hp, 0.1, 20.0)
	GameState.wave_speed_mult = clampf(velocidad, 0.1, 20.0)
	GameState.wave_damage_mult = clampf(danio, 0.1, 20.0)
	GameState.wave_surplus = GameState.wave_hp_mult

# --- Jugador ----------------------------------------------------------------
# `slot` está en todas las firmas desde ya: hoy siempre 0, pero agregarlo ahora
# cuesta cero y cambiarlas después rompería todos los mods publicados.

func player_position(slot := 0) -> Vector3:
	var p = _runner.player(slot)
	return p.global_position if p else Vector3.ZERO

func player_health(slot := 0) -> float:
	var p = _runner.player(slot)
	return p.health if p else 0.0

func player_count() -> int:
	return _runner.get_tree().get_nodes_in_group("player").size()

# --- Misceláneas ------------------------------------------------------------

## Segundos desde que arrancó la partida.
func elapsed() -> float:
	return GameState.run_time_alive()

func is_key_pressed(keycode: int) -> bool:
	return Input.is_key_pressed(keycode)

## Sale por consola con el id del modo adelante, y lo levanta `mod_report`.
## Se llama `info` y no `log` porque `log()` ya existe: es el logaritmo natural de
## Godot, y pisarlo da un error de tipos críptico en cada llamada.
func info(texto: String) -> void:
	print("[modo %s] %s" % [_runner.mode_id, texto])
