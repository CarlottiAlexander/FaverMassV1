class_name ModSoundLoader
extends RefCounted
## Convierte un archivo de audio suelto del disco en un `AudioStream`, SIN pasar
## por el importador de Godot. Es el espejo exacto de `ModModelLoader`: mismo
## contrato, mismos presupuestos, misma promesa de no romper nunca.
##
## Por qué no `load("res://...")`: igual que con los `.glb`, eso sólo funciona con
## recursos que el editor ya importó, y un jugador que copia un archivo a una
## carpeta no dispara ninguna importación.
##
## Lo que se pierde al no pasar por el importador: **no hay bucle configurado ni
## reencodeo**. Un OGG con silencio al principio va a sonar con silencio al
## principio, y eso en un disparo se nota muchísimo.

## 8 MB por archivo. Mucho más bajo que el de los modelos a propósito: un efecto de
## sonido de 8 MB ya es sospechoso (son ~45 segundos de WAV sin comprimir), y acá
## los archivos se cargan de a decenas, no de a uno.
const MAX_FILE_BYTES := 8 * 1024 * 1024
## Los LECHOS (ambiente y música) tienen su propio tope, mucho más alto. Un efecto
## de 8 MB es sospechoso; una música de 5 minutos son 14 MB y es completamente
## normal. El tope existe igual: es un colchón contra un archivo absurdo, no contra
## un archivo grande.
const MAX_LECHO_BYTES := 32 * 1024 * 1024
## Por encima de esto se acepta igual pero se avisa. Un golpe de enemigo que dura
## 3 segundos se solapa consigo mismo hasta volverse ruido: la Minigun hace
## impactar 60 balas por segundo.
const WARN_SEGUNDOS := 2.5
## Extensiones soportadas. Se recomienda OGG en el LEEME: el WAV sin comprimir se
## come el tope de tamaño enseguida, y el MP3 suele traer un silencio de relleno al
## inicio que arruina cualquier sonido percusivo.
const EXTENSIONES := ["ogg", "wav", "mp3"]

## Devuelve {stream: AudioStream, error: String, warnings: Array[String], segundos: float}.
## `stream` es null si y sólo si `error` no está vacío. NUNCA tira una excepción:
## GDScript no tiene try/catch, así que cada paso que puede fallar se chequea a mano.
## `max_bytes` distingue un EFECTO de un LECHO (ambiente/música): no sólo cambia el
## tope de tamaño, también apaga el aviso de "dura demasiado" — un colchón de cinco
## minutos es correcto y un golpe de cinco minutos no.
static func load_sound(abs_path: String, max_bytes := MAX_FILE_BYTES) -> Dictionary:
	var out := {"stream": null, "error": "", "warnings": [], "segundos": 0.0}

	var ext := abs_path.get_extension().to_lower()
	if not EXTENSIONES.has(ext):
		out["error"] = "extensión \"%s\" no soportada (usar %s)" % [ext, ", ".join(EXTENSIONES)]
		return out

	if not FileAccess.file_exists(abs_path):
		out["error"] = "no existe el archivo"
		return out

	# El tope se chequea ANTES de cargar: un archivo enorme no debe llegar nunca al
	# decodificador, porque para entonces ya se pagó la memoria.
	var size := _file_size(abs_path)
	if size > max_bytes:
		out["error"] = "pesa %.1f MB y el tope es %d MB" % [
			size / 1048576.0, max_bytes / 1048576]
		return out

	var st: AudioStream = null
	match ext:
		"ogg":
			st = AudioStreamOggVorbis.load_from_file(abs_path)
		"mp3":
			st = AudioStreamMP3.load_from_file(abs_path)
		"wav":
			st = AudioStreamWAV.load_from_file(abs_path)
	if st == null:
		out["error"] = "el archivo no se pudo decodificar; ¿está completo?"
		return out

	var seg := st.get_length()
	out["segundos"] = seg
	# Duración cero = archivo truncado. Godot decodifica el encabezado, devuelve un
	# stream válido y no falla, pero ese stream no suena NADA. Se rechaza en vez de
	# avisar: heredar el sonido del tipo base es estrictamente mejor que un silencio
	# que el modder va a leer como "mi sonido no funciona" sin más pistas.
	if seg <= 0.0:
		out["error"] = "dura 0 segundos: el archivo está truncado o incompleto"
		return out
	if seg > WARN_SEGUNDOS and max_bytes == MAX_FILE_BYTES:
		out["warnings"].append("dura %.1f s: para un efecto es largo y se va a solapar consigo mismo" % seg)

	out["stream"] = st
	return out

static func _file_size(abs_path: String) -> int:
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n
