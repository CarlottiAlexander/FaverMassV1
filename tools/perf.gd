extends Node
## Herramienta de MEDICIÓN de rendimiento. Corre el juego real en oleada 25 con
## el jugador inmortal y quieto en el medio, deja que se junte toda la oleada, y
## después muestrea los contadores del motor durante unos segundos.
##
## Correr SIN --headless:
##   Godot_v4.6.3-stable_win64_console.exe --path . tools/perf.tscn
##
## **Headless NO sirve acá**: no rasteriza, así que los draw calls darían cero y
## los FPS no medirían nada real. Es la única herramienta del repo que necesita
## ventana de verdad.
##
## `perf.tscn` es una INSTANCIA de main.tscn con este driver colgado como hijo,
## igual que soak.tscn — varios scripts (world.gd) resuelven nodos vía
## `get_tree().current_scene`.
##
## No dispara a propósito: matar enemigos baja el conteo y ensucia la medición.
## Lo que interesa es el peor caso estable — toda la oleada encima del jugador.

## Composición fija (proporciones de la oleada 25) y semilla fija. NO se usa el
## WaveManager: su composición es aleatoria y los enemigos se le mueren solos,
## así que el conteo variaba entre corridas y las mediciones no eran comparables.
## Acá el escenario es idéntico en cada corrida — que es lo único que permite
## atribuirle una mejora a un cambio.
const ENEMY_MIX := {
	"hollow": 78, "thrall": 24, "dire_bat": 18, "blood_lord": 16,
	"knight": 6, "capra": 13, "sorceress": 10, "demon_skull": 12,
}
const SPAWN_SEED := 1234
const WARMUP_SEC := 4.0
const SAMPLE_SEC := 15.0

var deaths: Dictionary = {}

## Modos de aislamiento, por línea de comandos:
##   ... tools/perf.tscn -- noanim   apaga animación y `_process` de los enemigos
##   ... tools/perf.tscn -- noui     apaga el HUD (el minimapa redibuja todo cada frame)
##   ... tools/perf.tscn -- nofx     apaga los enemigos por completo (piso de referencia)
##   ... tools/perf.tscn -- n=60     usa 60 enemigos en vez de los ~177 de la mezcla
## Correr los tres y restar es la única forma de saber a quién culpar.
var flags: PackedStringArray = OS.get_cmdline_user_args()

## Cantidad pedida por línea de comandos (`n=60`), o 0 = la mezcla completa.
## Sirve para barrer cantidades y encontrar con cuántos enemigos se sostienen los
## 100 FPS — que es el número del que sale el tope de oleada.
func _requested_count() -> int:
	for f in flags:
		if f.begins_with("n="):
			return int(f.substr(2))
	return 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	GameState.change_state(GameState.State.PLAYING)
	var wm = get_tree().get_first_node_in_group("wave_manager")
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		print("PERF: no se encontró el jugador")
		get_tree().quit()
		return
	if wm and not flags.has("wave"):
		wm.set_process(false)  # sin oleadas: el escenario lo arma esta herramienta
	if flags.has("wave"):
		# Prueba REALISTA: deja correr el WaveManager de verdad en oleada 25, con
		# su techo de enemigos, sus invocaciones y su ritmo de spawn. Es lo único
		# que dice si el juego sostiene los FPS jugando, y no en un escenario
		# armado a mano.
		if wm:
			wm.set_process(true)
			wm.wave = 24
			wm.announce_timer = 0.1
	elif not flags.has("nofx"):
		_spawn_fixed_mix()
	await get_tree().physics_frame
	if flags.has("noui"):
		var ui = get_tree().current_scene.get_node_or_null("UI")
		if ui:
			ui.process_mode = Node.PROCESS_MODE_DISABLED
			ui.visible = false
	print("PERF modo: %s" % ("normal" if flags.is_empty() else ", ".join(flags)))

	var t := 0.0
	while t < WARMUP_SEC:
		t += await _tick(player)
	print("PERF: escenario listo, %d enemigos vivos" % get_tree().get_nodes_in_group("enemy").size())

	var fps: Array[float] = []
	var cpu_proc: Array[float] = []
	var cpu_phys: Array[float] = []
	var draws: Array[float] = []
	var prims: Array[float] = []
	var alive: Array[float] = []
	t = 0.0
	while t < SAMPLE_SEC:
		t += await _tick(player)
		fps.append(Performance.get_monitor(Performance.TIME_FPS))
		cpu_proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		cpu_phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		alive.append(float(get_tree().get_nodes_in_group("enemy").size()))

	print("=== PERF (%.0f s de muestra, mezcla fija) ===" % SAMPLE_SEC)
	_report("FPS", fps, "")
	_report("CPU _process", cpu_proc, " ms")
	_report("CPU _physics_process", cpu_phys, " ms")
	_report("draw calls", draws, "")
	_report("primitivas", prims, "")
	_report("enemigos vivos", alive, "")
	print("  bajas sin que nadie dispare: %s | de esas, muertes reales (run_kills): %d" % [
		deaths, GameState.run_kills])
	get_tree().quit()

## Anillo de enemigos alrededor del jugador, con semilla fija.
func _spawn_fixed_mix() -> void:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var rng := RandomNumberGenerator.new()
	rng.seed = SPAWN_SEED
	# Se escala la mezcla entera, así las proporciones entre tipos no cambian al
	# barrer cantidades (un Knight cuesta bastante más que un Dire Bat).
	var total := 0
	for etype in ENEMY_MIX:
		total += ENEMY_MIX[etype]
	var want := _requested_count()
	var factor := 1.0 if want <= 0 else float(want) / float(total)
	for etype in ENEMY_MIX:
		for i in maxi(1, int(round(ENEMY_MIX[etype] * factor))):
			var e = scene.instantiate()
			e.enemy_type = etype
			get_tree().current_scene.add_child(e)
			var a := rng.randf() * TAU
			var d := rng.randf_range(8.0, 44.0)
			var y: float = rng.randf_range(2.0, 5.0) if GameData.enemy_stats_of(etype).get("flying", false) else e.body_height * 0.5 + 0.05
			e.global_position = Vector3(sin(a) * d, y, cos(a) * d)
			# Diagnóstico: acá nadie dispara, así que TODA baja es sospechosa.
			# `_die()` cuenta en GameState.run_kills; la red de FALL_KILL_Y no.
			e.died.connect(_on_any_death.bind(e.enemy_type))
			if flags.has("noanim"):
				e.set_process(false)
				if e.anim_player:
					e.anim_player.active = false

func _on_any_death(_p: Vector3, _d: Vector3, _h: bool, etype: String) -> void:
	deaths[etype] = deaths.get(etype, 0) + 1

## Un frame: mantiene vivo al jugador y devuelve el delta transcurrido.
func _tick(player) -> float:
	await get_tree().process_frame
	if is_instance_valid(player):
		player.health = GameData.MAX_HEALTH
		# Sin munición no hay disparo. Es obligatorio: la ventana captura el mouse
		# de verdad, así que un clic real del usuario entraba al juego y mataba
		# enemigos en pleno benchmark. Se descubrió porque el conteo caía de 180 a
		# 40 "solo" — y `GameState.run_kills` delató que eran muertes reales.
		player.ammo = 0
	return get_process_delta_time()

## Promedio, mínimo y percentil 5 (el 5% de frames PEORES — es lo que se siente
## como tirón, más honesto que el promedio).
func _report(label: String, v: Array[float], unit: String) -> void:
	if v.is_empty():
		return
	var sorted := v.duplicate()
	sorted.sort()
	var sum := 0.0
	for x in v:
		sum += x
	var p5: float = sorted[int(sorted.size() * 0.05)]
	var p95: float = sorted[mini(int(sorted.size() * 0.95), sorted.size() - 1)]
	print("  %-22s prom %8.1f%s | mín %8.1f | p5 %8.1f | p95 %8.1f" % [
		label, sum / v.size(), unit, sorted[0], p5, p95])
