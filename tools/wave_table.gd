extends Node
## Imprime la tabla de oleadas: cuántos enemigos pediría cada una, cuántos manda
## de verdad después del techo, y con qué multiplicadores se compensa. Es la
## herramienta para tantear el balance sin tener que jugar 25 oleadas.
##
## Correr:  Godot --headless --path . tools/wave_table.tscn

const WAVES := 30

func _ready() -> void:
	# Semilla FIJA. `wave_composition()` llama `randi_range()` para dire_bat,
	# sorceress y demon_skull, así que sin esto la salida cambia en cada corrida y
	# la tabla no sirve para comparar un antes contra un después. Es lo que permite
	# exigir un diff VACÍO al refactorizar la composición de oleadas.
	seed(12345)
	print("oleada | pedía | manda | x cant | vida  veloc  daño | HP Hollow  HP Knight")
	for w in range(1, WAVES + 1):
		var raw := GameData.wave_composition(w)
		var comp := GameData.cap_composition(raw)
		var raw_n := GameData.total_of(raw)
		var sent_n := GameData.total_of(comp)
		var surplus := GameData.surplus_of(raw_n, sent_n)
		var hp := GameData.hp_mult_of(surplus)
		var sp := GameData.speed_mult_of(surplus)
		var dm := GameData.damage_mult_of(surplus)
		print("  %3d  |  %4d |  %4d | %5.2fx | %.2f  %.2f  %.2f | %8.0f  %8.0f" % [
			w, raw_n, sent_n, surplus, hp, sp, dm,
			GameData.enemy_stats_of("hollow")["hp"] * hp,
			GameData.enemy_stats_of("knight")["hp"] * hp])

	# Cuántos tiros hacen falta, que es lo que de verdad se siente.
	print("\nTiros para matar un Hollow (sin headshot, rareza común):")
	for w in [1, 10, 15, 20, 25, 30]:
		var raw := GameData.wave_composition(w)
		var hp: float = GameData.enemy_stats_of("hollow")["hp"] * GameData.hp_mult_of(
			GameData.surplus_of(GameData.total_of(raw), GameData.total_of(GameData.cap_composition(raw))))
		var line := "  oleada %2d (%4.0f HP): " % [w, hp]
		for wid in ["pistol", "ak47", "smg", "sniper"]:
			line += "%s %d   " % [wid, ceili(hp / GameData.WEAPONS[wid]["damage"])]
		print(line)
	# Velocidad, que es el multiplicador peligroso: el jugador corre a 7.0
	print("\nVelocidad del Thrall (el más rápido a pie) vs jugador a %.1f:" % GameData.PLAYER_SPEED)
	for w in [1, 15, 25, 30]:
		var raw := GameData.wave_composition(w)
		var sp: float = GameData.enemy_stats_of("thrall")["speed"] * GameData.speed_mult_of(
			GameData.surplus_of(GameData.total_of(raw), GameData.total_of(GameData.cap_composition(raw))))
		print("  oleada %2d: %.2f u/s" % [w, sp])
	get_tree().quit()
