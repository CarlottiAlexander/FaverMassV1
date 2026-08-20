extends Node
## Ejecuta el modo de juego de la partida en curso y le despacha los eventos.
##
## Va en `main.tscn` ENTRE `WaveManager` y `UI`, y esa posición no es casual: es la
## única que funciona. Necesita ver a Player y WaveManager en su `_ready()` (están
## antes, así que ya se metieron en sus grupos) y `ui.gd` necesita verlo a él
## (está antes que UI). Ver la trampa de grupos en CLAUDE.md §3.
##
## Se recrea con `reload_current_scene()`, que es exactamente la vida que queremos:
## un modo no sobrevive a la partida.
##
## Todos los hooks se despachan con `has_method()` — un modo implementa sólo los
## que le interesan. Es la misma convención duck-typed que usa el resto del juego
## para el daño.

## Modos que shippeamos nosotros. Un mapa los elige por nombre y no cuesta nada en
## seguridad: son nuestros, viven en res://.
const BUILTIN := {
	"survival": "res://scripts/features/modes/survival_mode.gd",
	"waves10": "res://scripts/features/modes/waves10_mode.gd",
}

var mode: GameMode = null
var mode_id := "survival"
var api: ModeApi = null
## Filas extra para la pantalla final, que el modo va agregando con `add_stat`.
var extra_stats: Array = []

var _wm: Node = null
var _players: Array = []

func _ready() -> void:
	add_to_group("mode_runner")
	_wm = _buscar("wave_manager")
	_players = get_tree().get_nodes_in_group("player")

	api = ModeApi.new(self)
	_cargar()
	if mode:
		add_child(mode)
		mode.api = api
		_llamar("_setup", [_params()])

	# El WaveManager arranca con `announce_timer = 2.0`, así que un modo que apaga
	# las oleadas en `_setup` llega a tiempo: todavía no se lanzó ninguna.
	if _wm and _wm.has_signal("wave_cleared"):
		_wm.wave_cleared.connect(func(n: int): _llamar("_on_wave_cleared", [n]))
		_wm.wave_announced.connect(func(n: int): _llamar("_on_wave_started", [n]))

	_llamar("_start", [])

func _process(delta: float) -> void:
	if GameState.state == GameState.State.PLAYING:
		_llamar("_tick", [delta])

## `_input` y NO `_unhandled_input`. Está documentado en CLAUDE.md §3: en este
## proyecto `InputEventMouseMotion` nunca llega a `_unhandled_input`, y costó una
## sesión entera de diagnóstico. Un modo con control propio dejaría de funcionar y
## parecería un bug del modder.
func _input(event: InputEvent) -> void:
	if GameState.state == GameState.State.PLAYING:
		_llamar("_on_input", [event])

# --- Eventos que le llegan de afuera ---------------------------------------

## Lo llama `player._die()`. Devolver `true` significa que el modo se hace cargo
## (respawn, vidas) y la partida NO termina.
func handle_player_death(slot: int) -> bool:
	if mode and mode.has_method("_on_player_died"):
		return bool(mode.call("_on_player_died", slot))
	return false

## Lo llama `enemy._die()`.
func notify_enemy_died(info: Dictionary) -> void:
	_llamar("_on_enemy_died", [info])

# --- Accesos que usa ModeApi ------------------------------------------------

func wave_manager() -> Node:
	return _wm

func player(slot := 0):
	# Se resuelve cada vez y no se cachea: el jugador puede no existir todavía, o
	# ser otro tras un respawn.
	var ps := get_tree().get_nodes_in_group("player")
	for p in ps:
		if int(p.get("slot")) == slot:
			return p
	return ps[0] if ps.size() > 0 else null

func hud():
	var uis := get_tree().get_nodes_in_group("hud")
	return uis[0] if uis.size() > 0 else null

# --- Interno ----------------------------------------------------------------

func _cargar() -> void:
	mode_id = _elegir_id()
	var ruta: String = BUILTIN.get(mode_id, "")
	if ruta == "" or not ResourceLoader.exists(ruta):
		push_warning("ModeRunner: no existe el modo \"%s\"; se usa survival" % mode_id)
		mode_id = "survival"
		ruta = BUILTIN["survival"]
	var s: GDScript = load(ruta)
	if s == null or not s.can_instantiate():
		return
	var inst = s.new()
	if inst is GameMode:
		mode = inst
	else:
		push_error("ModeRunner: %s no extiende GameMode" % ruta)

## Qué modo corre esta partida. Hoy sale del mapa elegido; si el mapa no declara
## ninguno, es el juego de siempre.
func _elegir_id() -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--mode="):
			return s.substr(7)
	var m: Dictionary = ModManager.map_profile().get("mode", {})
	return String(m.get("builtin", "survival"))

func _params() -> Dictionary:
	var m: Dictionary = ModManager.map_profile().get("mode", {})
	return m.get("params", {})

func _llamar(hook: String, args: Array) -> void:
	if mode and mode.has_method(hook):
		mode.callv(hook, args)

func _buscar(grupo: String) -> Node:
	var n := get_tree().get_nodes_in_group(grupo)
	return n[0] if n.size() > 0 else null
