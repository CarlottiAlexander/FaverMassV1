extends CanvasLayer
## Orquestador de la capa de presentación. No dibuja nada: encuentra al jugador y
## al gestor de oleadas por grupo, arma el HUD y los menús, y cablea las señales.
##
## Es el ÚNICO punto donde la UI se entera de que existen `player` y
## `wave_manager`: `hud.gd` y `menus.gd` reciben las referencias ya resueltas y
## nunca hacen `get_tree().get_nodes_in_group(...)` por su cuenta. Si aparece una
## señal nueva, se conecta acá.

var player: Node = null
var wave_manager: Node = null

var hud: Hud
var menus: Menus

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
	var wms := get_tree().get_nodes_in_group("wave_manager")
	if wms.size() > 0:
		wave_manager = wms[0]

	# El HUD va primero para que los menús queden dibujados encima.
	hud = Hud.new()
	hud.player = player
	hud.wave_manager = wave_manager
	add_child(hud)

	menus = Menus.new()
	menus.player = player
	add_child(menus)

	if player:
		player.health_changed.connect(hud.update_health)
		player.ammo_changed.connect(hud.update_weapon)
		player.weapon_changed.connect(hud.update_weapon)
		player.ecstasy_changed.connect(hud.update_ecstasy)
		player.hit_confirmed.connect(hud.on_hit_confirmed)
		player.damage_taken.connect(hud.on_damage_taken)
		player.kill_feed_entry.connect(hud.on_kill_feed)

	if wave_manager:
		wave_manager.wave_changed.connect(hud.update_wave)
		wave_manager.wave_announced.connect(hud.on_wave_announced)

	GameState.state_changed.connect(_on_state_changed)
	_on_state_changed(GameState.state)

	hud.refresh_all()

func _on_state_changed(new_state: int) -> void:
	menus.apply_state(new_state)
	# El HUD se esconde en cualquier pantalla superpuesta, no sólo en Opciones.
	hud.visible = new_state == GameState.State.PLAYING or new_state == GameState.State.PAUSED or new_state == GameState.State.DEAD
