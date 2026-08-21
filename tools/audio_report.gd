extends Node
## Qué sonido resolvió cada entidad, con cuántas variantes, y si el pool aguanta.
##
## No se puede ESCUCHAR un test headless, así que esto afirma sobre el ESTADO: que
## el stream cargó, de dónde salió (propio / heredado / mudo), cuántas variantes
## tiene, y que el pool de voces nunca se pasó de su tope bajo carga.
##
## Es la respuesta a "mi bicho no suena": la fila del tipo dice exactamente qué
## ranura quedó vacía.
##
## Correr:  Godot --headless --path . tools/audio_report.tscn

const RANURAS := ["attack", "hit", "death"]

func _ready() -> void:
	print("BUSES")
	for i in AudioServer.bus_count:
		print("  %-10s %6.2f dB" % [AudioServer.get_bus_name(i), AudioServer.get_bus_volume_db(i)])
	print("  volumen guardado: master=%.2f  sfx=%.2f" % [Config.master_volume, Config.sfx_volume])

	print("\nENEMIGOS   (n = variantes; * = lo trajo el MOD; '—' = mudo)")
	for t: String in GameData.enemy_types():
		var linea := "  %-14s" % t
		for r: String in RANURAS:
			Audio.resolver(t, r)
			var n := Audio.variantes_de("%s|%s" % [t, r])
			# Distinguir "lo trajo el mod" de "lo heredó" es LA pregunta que esta
			# herramienta tiene que contestar: un modder que declaró un sonido y
			# escucha otro necesita ver que su archivo no entró.
			var propio := "*" if not ModManager.sounds_for(t, r).is_empty() else " "
			linea += "  %s:%s%s" % [r, str(n) if n > 0 else "—", propio]
		if ModManager.sound_is_silent(t):
			linea += "   [MUDO a propósito]"
		elif ModManager.sound_inherit_of(t) != t:
			linea += "   hereda de \"%s\"" % ModManager.sound_inherit_of(t)
		print(linea)

	print("\nARMAS      (muestra que le toca y a qué tono)")
	for w: String in GameData.WEAPONS:
		var cfg: Dictionary = Audio.ARMA_SONIDO.get(w, {})
		var src: String = cfg.get("src", w)
		var estado := "MUDA" if Audio.weapon_shot(w) == null else "%s x%.2f" % [src, cfg.get("tono", 1.0)]
		print("  %-10s %s" % [w, estado])

	print("\nOTROS")
	for n in ["impact", "impact_headshot", "explosion", "player_hurt", "player_death",
			"weapon_switch", "footsteps/step", "wave_start", "victory", "defeat"]:
		Audio.ui(n)
		var v := Audio.variantes_de("ui|" + n)
		print("  %-18s %s" % [n, "%d variante(s)" % v if v > 0 else "—  MUDO"])

	print("\nPOOL")
	print("  voces 3D: %d    planas: %d    intervalo mínimo: %.0f ms" % [
		Audio.VOCES_3D, Audio.VOCES_FLAT, Audio.INTERVALO_MIN * 1000.0])
	_estres()

## Dispara mucho más rápido de lo que el juego puede, para probar que el tope
## aguanta. Es el peor caso real: la Minigun a full spin-up son 60 disparos/s.
func _estres() -> void:
	var s := Audio.ui("impact")
	if s == null:
		print("  (sin sonido cargado, no se puede medir el estrés)")
		get_tree().quit()
		return
	for i in 400:
		# Sin clave: se saltea el intervalo mínimo a propósito, para castigar al pool.
		Audio.play_3d(s, Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)))
	print("  400 sonidos de golpe -> pico de voces 3D: %d (tope %d)" % [
		Audio.pico_voces_3d, Audio.VOCES_3D])
	print("  RESULTADO: %s" % ("el pool NUNCA se pasó del tope" if Audio.pico_voces_3d <= Audio.VOCES_3D else "FALLA: se desbordó"))
	print("  eventos: %d   descartados por intervalo: %d" % [Audio.eventos, Audio.descartados])
	get_tree().quit()
