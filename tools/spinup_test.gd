extends Node
## Verifica numéricamente la mecánica de spin-up sin necesidad de jugar:
## simula fuego sostenido y después soltar el gatillo, e imprime cómo evoluciona
## el multiplicador, la cadencia efectiva y el daño. Útil para balancear.
##
## Correr:  Godot --headless --path . tools/spinup_test.tscn
## (como escena y no con --script, porque necesita los autoloads GameData/GameState)

const P := preload("res://scripts/player.gd")

func _ready() -> void:
	var w: Dictionary = GameData.WEAPONS["smg"]
	var base_dmg: float = w["damage"]
	var base_rate: float = w["fire_rate"]
	var ramp: float = (P.SPINUP_MAX - 1.0) / P.SPINUP_RAMP_TIME
	var dt := 0.1

	print("=== SMG: fuego sostenido (base %.0f dmg, %.0f disparos/s) ===" % [base_dmg, base_rate])
	var s := 1.0
	var t := 0.0
	while t <= 4.0:
		if fmod(t, 0.5) < dt * 0.5:
			print("  t=%.1fs  x%.2f  ->  %.1f dmg, %.1f disp/s  (DPS x%.1f)" % [
				t, s, base_dmg * s, base_rate * s, s * s])
		s = min(P.SPINUP_MAX, s + ramp * dt)
		t += dt

	print("=== soltando el gatillo (decae %.1fx más rápido) ===" % P.SPINUP_DECAY_MULT)
	t = 0.0
	while s > 1.001 and t <= 4.0:
		if fmod(t, 0.4) < dt * 0.5:
			print("  t=%.1fs  x%.2f" % [t, s])
		s = max(1.0, s - ramp * P.SPINUP_DECAY_MULT * dt)
		t += dt
	print("  vuelve a x1.00 en ~%.1fs" % t)

	print("=== armas con spinup ===")
	for id in GameData.WEAPONS:
		if GameData.WEAPONS[id].get("spinup", false):
			print("  ", GameData.WEAPONS[id]["name"])
	get_tree().quit()
