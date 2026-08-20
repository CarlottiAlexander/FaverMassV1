extends Node
## Autoload. Máquina de estados de pantallas (sección 10.1):
## TITLE -> PLAYING <-> PAUSED -> OPTIONS (vuelve a donde se abrió) | PLAYING -> DEAD

## MODS es una pantalla superpuesta igual que OPTIONS: se abre desde el título o
## desde la pausa y vuelve a donde se abrió.
## WON es terminal igual que DEAD. `change_state()` pausa el árbol para todo lo que
## no sea PLAYING, así que la victoria congela el juego sola.
enum State { TITLE, PLAYING, PAUSED, OPTIONS, DEAD, MODS, WON }

var state: int = State.TITLE
## A dónde vuelve la pantalla superpuesta que esté abierta (Opciones o Mods). Es
## una sola variable para las dos porque nunca pueden estar abiertas a la vez.
var overlay_return_state: int = State.TITLE

# stats de partida (sección 10.5)
var run_wave := 0
var run_kills := 0
var run_headshots := 0
var run_start_time := 0.0

## Compensación de dificultad de la oleada en curso. La oleada se recorta para no
## saturar la máquina (ver GameData.WAVE_MAX_ENEMIES) y lo que se pierde en
## cantidad se devuelve acá. Los calcula `wave_manager.start_wave()` UNA vez por
## oleada y los leen los enemigos al nacer.
## Valen 1.0 mientras la oleada entre en el techo — las primeras no cambian nada.
var wave_hp_mult := 1.0
var wave_speed_mult := 1.0
var wave_damage_mult := 1.0
var wave_surplus := 1.0

signal state_changed(new_state: int)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = state != State.PLAYING

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if state == State.PLAYING:
			change_state(State.PAUSED)
		elif state == State.PAUSED:
			change_state(State.PLAYING)
		elif state == State.OPTIONS or state == State.MODS:
			close_overlay()

func change_state(new_state: int) -> void:
	state = new_state
	get_tree().paused = new_state != State.PLAYING
	state_changed.emit(new_state)

func open_options(from_state: int) -> void:
	overlay_return_state = from_state
	change_state(State.OPTIONS)

func open_mods(from_state: int) -> void:
	overlay_return_state = from_state
	change_state(State.MODS)

func close_overlay() -> void:
	change_state(overlay_return_state)

## Compatibilidad: `tools/ui_shot.gd` y los botones "Volver" ya la llamaban.
func close_options() -> void:
	close_overlay()

func start_run() -> void:
	# Los cambios de mods se aplican ACÁ y no en caliente: un enemigo vivo ya
	# resolvió su modelo y su hitbox en su `_ready()`, así que cambiarle el registro
	# debajo lo deja inconsistente. Empezar partida es el único momento seguro.
	var cambio := ModManager.commit_if_needed()
	run_wave = 0
	run_kills = 0
	run_headshots = 0
	run_start_time = Time.get_ticks_msec() / 1000.0
	wave_hp_mult = 1.0
	wave_speed_mult = 1.0
	wave_damage_mult = 1.0
	wave_surplus = 1.0
	run_result = {}
	# `chaos_level` es de un autoload: sobrevive al reinicio de escena. Sin
	# resetearlo, una partida nueva arrancaba con el cielo rojo de la anterior.
	chaos_level = 0.0
	change_state(State.PLAYING)

	# El mundo se arma en `world._ready()`, que corre UNA vez al arrancar el motor.
	# El botón "Jugar" del título no recargaba la escena, así que elegir un mapa y
	# darle a Jugar NO aplicaba el mapa: recién entraba al morir una vez o al
	# reiniciar el juego. Los mods de enemigos sí funcionaban por ese camino
	# (se leen al spawnear); el mapa no, porque la arena ya estaba construida.
	if cambio:
		get_tree().reload_current_scene()

## Único árbitro del fin de partida. Hasta ahora sólo se salía muriendo, y la
## transición estaba enterrada en `player._die()`; ahora hay un solo lugar que
## decide y que sabe si se ganó o se perdió.
##
## `stats` son filas extra que el modo quiera mostrar en la pantalla final.
func end_run(win: bool, titulo := "", detalle := "", stats: Array = []) -> void:
	if state == State.DEAD or state == State.WON:
		return   # ya terminó; un modo que llama dos veces no rompe nada
	run_result = {"win": win, "titulo": titulo, "detalle": detalle, "stats": stats}
	change_state(State.WON if win else State.DEAD)

## Resultado de la partida terminada, para la pantalla final.
var run_result: Dictionary = {}

# --- Caos / atmósfera -------------------------------------------------------
## Cuán infernal se ve el mundo (0..3): cielo, niebla, altura de los muros,
## escombros y luna. Vivía en `wave_manager` y se emitía por señal, pero eso ataba
## TODA la atmósfera al número de oleada — un modo sin oleadas dejaba el mundo
## congelado en 0, que es exactamente el bug que este proyecto sufrió durante toda
## su vida. Acá es un autoload: siempre existe, y `world.gd` se conecta sin el
## `call_deferred()` frágil que hacía falta para encontrar al WaveManager.
var chaos_level := 0.0
signal chaos_changed(level: float)

func set_chaos(v: float) -> void:
	var nuevo := clampf(v, 0.0, 3.0)
	if is_equal_approx(nuevo, chaos_level):
		return
	chaos_level = nuevo
	chaos_changed.emit(nuevo)

func register_kill(is_headshot: bool) -> void:
	run_kills += 1
	if is_headshot:
		run_headshots += 1

func run_time_alive() -> float:
	return (Time.get_ticks_msec() / 1000.0) - run_start_time

func headshot_accuracy() -> float:
	if run_kills == 0:
		return 0.0
	return (float(run_headshots) / float(run_kills)) * 100.0
