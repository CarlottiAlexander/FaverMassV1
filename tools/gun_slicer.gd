extends Node
## Corta disparos sueltos de una grabación larga, y mide cuál sirve.
##
## Los packs CC0 de armas de fuego vienen como tomas de campo: varios disparos
## seguidos en un mismo archivo, con eco y ruido ambiente. Un FPS necesita lo
## contrario — un one-shot corto y seco por arma.
##
## POR QUÉ ES UNA HERRAMIENTA Y NO SE ELIGE A OJO: acá no se puede ESCUCHAR nada.
## La queja registrada sobre estos packs es "el ruido ambiente es muy pesado", así
## que la herramienta mide exactamente eso — pico del disparo contra el piso de
## ruido de justo antes — y ordena los cortes por esa relación. Elegir el mejor
## deja de ser opinión y pasa a ser un número.
##
## Correr:  Godot --headless --path . tools/gun_slicer.tscn -- --in=<wav> --out=<carpeta>

## Ventana del análisis de energía.
const VENTANA := 0.005
## Un disparo nuevo tiene que estar al menos esto después del anterior, o el eco
## de uno se cuenta como otro disparo.
const SEPARACION := 0.45
## Fracción del pico global a partir de la cual se considera que empezó un disparo.
const UMBRAL := 0.30
## Se toma un pelín ANTES del cruce: el ataque de un disparo es lo más importante
## que tiene, y cortarlo tarde le saca el golpe.
const PRE := 0.012
## Largo del corte. Alcanza para el golpe y algo de cola sin arrastrar el eco.
const LARGO := 0.55
## Desvanecido final, o el corte termina en un clic.
const FADE := 0.06

var _rate := 44100
var _muestras: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	var entrada := ""
	var salida := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--in="):
			entrada = a.substr(5)
		elif a.begins_with("--out="):
			salida = a.substr(6)
	if entrada == "" or salida == "":
		print("uso: --in=<wav> --out=<carpeta>")
		get_tree().quit()
		return

	var st := AudioStreamWAV.load_from_file(entrada)
	if st == null:
		print("no carga: %s" % entrada)
		get_tree().quit()
		return
	if st.format != AudioStreamWAV.FORMAT_16_BITS:
		print("formato %d no soportado (se esperaba PCM 16)" % st.format)
		get_tree().quit()
		return

	_rate = st.mix_rate
	_muestras = _a_mono(st.data, st.stereo)
	var nombre := entrada.get_file().get_basename()
	print("%s: %.2f s a %d Hz, %s" % [
		nombre, float(_muestras.size()) / _rate, _rate, "estéreo" if st.stereo else "mono"])

	var env := _envolvente()
	var pico_global := 0.0
	for v in env:
		pico_global = maxf(pico_global, v)
	var inicios := _detectar(env, pico_global)
	print("  %d disparos detectados" % inicios.size())

	DirAccess.make_dir_recursive_absolute(salida)
	var filas := []
	for i in inicios.size():
		var r := _cortar(nombre, i, inicios[i], salida, st.stereo)
		if not r.is_empty():
			filas.append(r)

	# Ordenado por limpieza: el que más se despega de su propio ruido de fondo.
	filas.sort_custom(func(a, b): return a["snr"] > b["snr"])
	print("  corte              pico   ruido   limpieza(dB)")
	for f in filas:
		print("    %-16s %5.3f  %5.4f   %6.1f" % [f["archivo"], f["pico"], f["ruido"], f["snr"]])
	if not filas.is_empty():
		print("  MEJOR: %s (%.1f dB sobre el ruido)" % [filas[0]["archivo"], filas[0]["snr"]])
	get_tree().quit()

## PCM 16 con signo, little endian. Si es estéreo se promedian los dos canales:
## el juego los reproduce posicionalmente y un one-shot mono es lo correcto.
func _a_mono(data: PackedByteArray, estereo: bool) -> PackedFloat32Array:
	var canales := 2 if estereo else 1
	var total := data.size() / (2 * canales)
	var out := PackedFloat32Array()
	out.resize(total)
	for i in total:
		var suma := 0.0
		for c in canales:
			suma += float(data.decode_s16((i * canales + c) * 2)) / 32768.0
		out[i] = suma / canales
	return out

## Energía RMS por ventana. Se trabaja sobre la envolvente y no sobre la muestra
## cruda porque una onda de audio cruza el cero todo el tiempo: buscar "dónde está
## fuerte" en la muestra directa daría miles de falsos positivos por disparo.
func _envolvente() -> PackedFloat32Array:
	var paso := int(VENTANA * _rate)
	var n := _muestras.size() / paso
	var out := PackedFloat32Array()
	out.resize(n)
	for w in n:
		var suma := 0.0
		for i in paso:
			var v := _muestras[w * paso + i]
			suma += v * v
		out[w] = sqrt(suma / paso)
	return out

func _detectar(env: PackedFloat32Array, pico: float) -> PackedInt32Array:
	var paso := int(VENTANA * _rate)
	var sep := int(SEPARACION / VENTANA)
	var umbral := pico * UMBRAL
	var out := PackedInt32Array()
	var ultimo := -sep * 2
	for w in env.size():
		if env[w] < umbral or w - ultimo < sep:
			continue
		ultimo = w
		out.append(w * paso)
	return out

func _cortar(nombre: String, idx: int, inicio: int, salida: String, _estereo: bool) -> Dictionary:
	var desde := maxi(0, inicio - int(PRE * _rate))
	var largo := int(LARGO * _rate)
	if desde + largo > _muestras.size():
		return {}

	# Piso de ruido: los 200 ms anteriores al disparo. Es literalmente "cuánto se
	# escucha el ambiente cuando no está pasando nada".
	var ruido := 0.0
	var n_ruido := mini(int(0.2 * _rate), desde)
	for i in n_ruido:
		ruido = maxf(ruido, absf(_muestras[desde - n_ruido + i]))

	var pico := 0.0
	var trozo := PackedFloat32Array()
	trozo.resize(largo)
	var fade := int(FADE * _rate)
	for i in largo:
		var v := _muestras[desde + i]
		if i > largo - fade:
			v *= float(largo - i) / fade
		trozo[i] = v
		pico = maxf(pico, absf(v))

	# Normalizado a -1.5 dBFS: los packs vienen con niveles dispares y el juego los
	# mezcla en el mismo bus. Sin esto una pistola taparía a una escopeta.
	var gan := (0.84 / pico) if pico > 0.0001 else 1.0
	var bytes := PackedByteArray()
	bytes.resize(largo * 2)
	for i in largo:
		bytes.encode_s16(i * 2, int(clampf(trozo[i] * gan, -1.0, 1.0) * 32767.0))

	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = _rate
	st.stereo = false
	st.data = bytes
	var archivo := "%s_%02d.wav" % [nombre, idx]
	st.save_to_wav(salida.path_join(archivo))
	return {
		"archivo": archivo, "pico": pico, "ruido": ruido,
		"snr": 20.0 * log(pico / maxf(ruido, 0.00001)) / log(10.0),
	}
