extends Node
## Prueba que una partida se pueda GANAR, que es lo que la etapa 1 agrega.
##
## Corre el juego real con el modo "aguantá N oleadas" forzado a un N chico y
## afirma que se llegó al estado WON. Antes de esto, el único final posible era
## morirse.
##
## Correr:  Godot --headless --path . tools/mode_soak.tscn -- --mode=waves10

const LIMITE_FRAMES := 5400   # ~90 s a 60 fps

var _frames := 0

func _ready() -> void:
	# Ganar pone el árbol en pausa (todo estado que no sea PLAYING lo hace), así
	# que sin esto el verificador deja de correr JUSTO cuando ocurre lo que está
	# esperando, y se cuelga para siempre. Mismo trato que tienen los menús.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_arrancar.call_deferred()

func _arrancar() -> void:
	await get_tree().process_frame
	# El modo se elige por --mode=; acá sólo se recorta la meta para no esperar 10
	# oleadas reales.
	var runners := get_tree().get_nodes_in_group("mode_runner")
	if runners.is_empty():
		print("FALLA: no hay ModeRunner en la escena")
		get_tree().quit()
		return
	var r = runners[0]
	print("modo: %s" % r.mode_id)
	if r.mode and "_meta" in r.mode:
		r.mode.set("_meta", 2)
		print("meta recortada a 2 oleadas para el test")
	GameState.start_run()
	# Inmortal: se prueba la VICTORIA, no la supervivencia.
	var ps := get_tree().get_nodes_in_group("player")
	if ps.size() > 0:
		ps[0].set("dead", false)

func _process(_d: float) -> void:
	var ps := get_tree().get_nodes_in_group("player")
	if ps.size() > 0:
		ps[0].health = GameData.MAX_HEALTH

	# Hay que MATAR enemigos o la oleada no termina nunca: sólo se da por
	# terminada cuando quedan vivos menos del 20% de los que mandó. Sin esto el
	# test se quedaba en la oleada 1 para siempre y parecía un bug del modo.
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.has_method("take_damage"):
			e.take_damage(999999.0, false, Vector3.ZERO)

	_frames += 1
	if GameState.state == GameState.State.WON:
		print("GANADA en el frame %d — oleada %d" % [_frames, GameState.run_wave])
		print("resultado: %s" % GameState.run_result)
		get_tree().quit()
	elif GameState.state == GameState.State.DEAD:
		print("FALLA: terminó en DERROTA")
		get_tree().quit()
	elif _frames > LIMITE_FRAMES:
		print("FALLA: %d frames sin ganar (oleada %d)" % [_frames, GameState.run_wave])
		get_tree().quit()
