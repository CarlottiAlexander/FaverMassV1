extends Node
## Mide DURACIÓN real de cada .ogg de una carpeta, cargándolos por el MISMO camino
## que va a usar un mod: `load_from_file()` sobre ruta absoluta, sin importador.
##
## Existe porque elegir un sonido por su NOMBRE es adivinar. Un "roar" de 3 segundos
## como sonido de golpe es una catástrofe: la Minigun hace impactar 60 balas por
## segundo y se solaparían 180 rugidos. La duración es el dato que decide en qué
## ranura puede ir cada archivo, y no se puede escuchar nada acá.
##
## Correr:  Godot --headless --path . tools/audio_probe.tscn -- --dir=<ruta absoluta>

func _ready() -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.substr(6)
	if dir == "":
		print("falta --dir=<ruta absoluta>")
		get_tree().quit()
		return

	var d := DirAccess.open(dir)
	if d == null:
		print("no se pudo abrir: %s" % dir)
		get_tree().quit()
		return

	var nombres := []
	for f in d.get_files():
		if f.get_extension().to_lower() == "ogg":
			nombres.append(f)
	nombres.sort()

	var fallos := 0
	print("archivo                  seg    canales")
	for n: String in nombres:
		var s := AudioStreamOggVorbis.load_from_file(dir.path_join(n))
		if s == null:
			print("  %-22s  NO CARGA" % n)
			fallos += 1
			continue
		print("  %-22s %5.2f" % [n, s.get_length()])
	print("\n%d archivos, %d fallaron" % [nombres.size(), fallos])
	get_tree().quit()
