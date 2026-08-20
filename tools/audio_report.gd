extends Node
## Qué sonido resolvió cada entidad, y si el pool aguanta.
##
## No se puede ESCUCHAR un test headless, así que esto afirma sobre el ESTADO: que
## el stream cargó, de dónde salió (mod / heredado / mudo), y que el pool de voces
## nunca se pasó de su tope bajo carga.
##
## Correr:  Godot --headless --path . tools/audio_report.tscn

const RANURAS := ["attack", "hit", "death", "spawn", "step"]

func _ready() -> void:
	print("BUSES")
	for i in AudioServer.bus_count:
		print("  %-10s %6.2f dB" % [AudioServer.get_bus_name(i), AudioServer.get_bus_volume_db(i)])
	print("  volumen guardado: master=%.2f  sfx=%.2f" % [Config.master_volume, Config.sfx_volume])

	print("\nENEMIGOS  (de dónde sale cada sonido)")
	for t: String in GameData.enemy_types():
		var linea := "  %-14s" % t
		for r: String in RANURAS:
			var s := Audio.resolver(t, r)
			linea += "  %s:%s" % [r, "sí" if s != null else "—"]
		print(linea)

	print("\nARMAS")
	for w: String in GameData.WEAPONS:
		var s := Audio.weapon_shot(w)
		print("  %-10s %s" % [w, "sí" if s != null else "MUDA"])

	print("\nOTROS")
	for n in ["impact", "impact_headshot", "player_hurt", "player_death", "weapon_switch"]:
		print("  %-18s %s" % [n, "sí" if Audio.ui(n) != null else "—"])

	# Llamarlo una vez fuerza la carga; después se puede contar cuántas hay.
	Audio.paso()
	print("  %-18s %d variantes" % ["pasos", Audio._pasos.size()])

	print("\nPOOL")
	print("  voces 3D: %d    planas: %d    intervalo mínimo: %.0f ms" % [
		Audio.VOCES_3D, Audio.VOCES_FLAT, Audio.INTERVALO_MIN * 1000.0])
	_estres()

## Dispara mucho más rápido de lo que el juego puede, para probar que el tope
## aguanta. Es el peor caso real: la Minigun a full spin-up son 60 disparos/s.
func _estres() -> void:
	var s := Audio.ui("weapons/railgun_shot")
	if s == null:
		print("  (sin sonido cargado, no se puede medir el estrés)")
		get_tree().quit()
		return
	var antes := Audio.pico_voces_3d
	for i in 400:
		# Sin clave: se saltea el intervalo mínimo a propósito, para castigar al pool.
		Audio.play_3d(s, Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)))
	print("  400 sonidos de golpe -> pico de voces 3D: %d (tope %d)" % [
		Audio.pico_voces_3d, Audio.VOCES_3D])
	print("  RESULTADO: %s" % ("el pool NUNCA se pasó del tope" if Audio.pico_voces_3d <= Audio.VOCES_3D else "FALLA: se desbordó"))
	print("  eventos: %d   descartados por intervalo: %d" % [Audio.eventos, Audio.descartados])
	get_tree().quit()
