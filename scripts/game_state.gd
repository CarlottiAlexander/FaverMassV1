extends Node
## Autoload. Máquina de estados de pantallas (sección 10.1):
## TITLE -> PLAYING <-> PAUSED -> OPTIONS (vuelve a donde se abrió) | PLAYING -> DEAD

enum State { TITLE, PLAYING, PAUSED, OPTIONS, DEAD }

var state: int = State.TITLE
var options_return_state: int = State.TITLE

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
		elif state == State.OPTIONS:
			close_options()

func change_state(new_state: int) -> void:
	state = new_state
	get_tree().paused = new_state != State.PLAYING
	state_changed.emit(new_state)

func open_options(from_state: int) -> void:
	options_return_state = from_state
	change_state(State.OPTIONS)

func close_options() -> void:
	change_state(options_return_state)

func start_run() -> void:
	run_wave = 0
	run_kills = 0
	run_headshots = 0
	run_start_time = Time.get_ticks_msec() / 1000.0
	wave_hp_mult = 1.0
	wave_speed_mult = 1.0
	wave_damage_mult = 1.0
	wave_surplus = 1.0
	change_state(State.PLAYING)

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
