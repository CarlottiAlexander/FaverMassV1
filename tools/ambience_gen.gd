extends Node
## Genera los dos lechos de ambiente del juego base: el calmo y el infernal.
##
## POR QUÉ SINTETIZADO Y NO UN PACK. Un disparo o un rugido sintetizados suenan a
## juguete — por eso las armas salieron de grabaciones reales. Pero el viento y un
## drone grave son **ruido filtrado**, que es literalmente lo que un sintetizador
## hace bien. Acá no se pierde nada y se gana algo que ningún pack da gratis:
## **un bucle exactamente sin costura**.
##
## EL BUCLE ES EL PUNTO DIFÍCIL. Un ambiente suena en loop durante toda la partida,
## así que un clic en la unión se escucha decenas de veces y arruina todo. Se
## resuelve por dos vías al mismo tiempo:
##   1. El ruido se genera con COLA y después se cruza consigo mismo: el final se
##      funde sobre el principio, así que la unión ya viene resuelta.
##   2. Los tonos del drone usan sólo frecuencias que son múltiplo exacto de 1/L,
##      o sea que completan un número entero de ciclos dentro del bucle y empalman
##      solos.
##
## Correr:  Godot --headless --path . tools/ambience_gen.tscn

const RATE := 22050          ## El viento no tiene contenido agudo: 22 kHz sobra y pesa la mitad.
const LARGO := 8.0           ## Segundos de bucle.
const COLA := 1.5            ## Segundos de cruce para cerrar la costura.
const SEMILLA := 20260820    ## Fijo: dos corridas tienen que dar el MISMO archivo.

func _ready() -> void:
	var dir := "res://assets/audio"
	_generar(dir.path_join("ambience_calm.wav"), false)
	_generar(dir.path_join("ambience_chaos.wav"), true)
	get_tree().quit()

func _generar(destino: String, infernal: bool) -> void:
	var n := int(LARGO * RATE)
	var n_cola := int(COLA * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEMILLA + (1 if infernal else 0)

	# --- ruido marrón: ruido blanco integrado con fuga ---
	# El blanco es siseo de radio; el marrón tiene la energía cargada en los graves
	# y es lo que suena a viento y a sala grande.
	var total := n + n_cola
	var bruto := PackedFloat32Array()
	bruto.resize(total)
	var acum := 0.0
	# Un pasabajos de un polo encima, para sacarle el resto de aspereza. Más cerrado
	# en el infernal: cuanto menos agudo, más "abajo" y más opresivo suena.
	var corte := 0.06 if infernal else 0.14
	var lp := 0.0
	for i in total:
		acum = acum * 0.985 + rng.randfn(0.0, 1.0) * 0.06
		lp += (acum - lp) * corte
		bruto[i] = lp

	# --- cruce consigo mismo: acá se cierra la costura ---
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = bruto[i]
	for i in n_cola:
		var t := float(i) / n_cola
		# Potencia constante otra vez: con un cruce lineal el ruido pierde energía
		# en el medio y se escucha un bache justo en la unión.
		buf[i] = bruto[i] * sqrt(t) + bruto[n + i] * sqrt(1.0 - t)

	# --- ráfagas: modulación lenta de amplitud ---
	# Sin esto el ruido es un "shhh" plano de aspiradora. Los períodos dividen el
	# bucle en partes enteras, así que la modulación también empalma.
	for i in n:
		var f := float(i) / n
		var raf := 1.0 \
			+ 0.35 * sin(TAU * f * 1.0) \
			+ 0.22 * sin(TAU * f * 3.0 + 1.1) \
			+ 0.14 * sin(TAU * f * 7.0 + 2.3)
		buf[i] *= maxf(raf, 0.15)

	# --- drone: sólo en el infernal ---
	# Un bajo sostenido con su quinta apenas desafinada. La desafinación es lo que
	# genera el batido lento que da inquietud; dos tonos perfectamente afinados
	# suenan a tono de prueba.
	if infernal:
		var ciclos_base: float = round(38.0 * LARGO)      # ~38 Hz, ajustado a ciclo entero
		var ciclos_quinta: float = round(57.3 * LARGO)    # quinta justa, corrida
		for i in n:
			var f := float(i) / n
			buf[i] += 0.30 * sin(TAU * f * ciclos_base)
			buf[i] += 0.16 * sin(TAU * f * ciclos_quinta)
			# Latido lento, como una respiración enorme.
			buf[i] *= 1.0 + 0.18 * sin(TAU * f * 2.0)

	_guardar(buf, destino, 0.55 if infernal else 0.42)
	print("%s: %.1f s, %d muestras a %d Hz" % [destino.get_file(), LARGO, n, RATE])
	_medir_costura(buf)

## Mide si la unión del bucle CLICKEA, en vez de confiar en que el cruce funcionó.
##
## Un clic es una discontinuidad: el salto de la última muestra a la primera es
## mucho mayor que los saltos normales de la señal. Se compara justamente eso
## contra el salto típico de adentro del bucle. Si el salto de la costura no se
## despega del resto, no hay clic — y eso es verificable sin escuchar nada, que es
## la única forma que hay acá.
func _medir_costura(buf: PackedFloat32Array) -> void:
	var n := buf.size()
	var suma := 0.0
	var maximo := 0.0
	for i in range(1, n):
		var d := absf(buf[i] - buf[i - 1])
		suma += d
		maximo = maxf(maximo, d)
	var tipico := suma / (n - 1)
	var costura := absf(buf[0] - buf[n - 1])
	var veces := costura / maxf(tipico, 1e-9)
	print("   costura: salto %.6f | típico %.6f | máximo interno %.6f -> %.1fx el típico  %s" % [
		costura, tipico, maximo, veces,
		"OK, no clickea" if costura <= maximo else "OJO: el salto de la unión supera todo salto interno"])

## Normaliza al pico pedido y escribe PCM 16 mono. El pico se deja BAJO a propósito:
## esto es un colchón de fondo, no un efecto — si compite con los disparos, molesta.
func _guardar(buf: PackedFloat32Array, destino: String, pico_objetivo: float) -> void:
	var pico := 0.0
	for v in buf:
		pico = maxf(pico, absf(v))
	var gan := (pico_objetivo / pico) if pico > 0.0001 else 1.0

	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i] * gan, -1.0, 1.0) * 32767.0))

	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = bytes
	# El bucle se marca en el propio archivo: así vale aunque lo use otra cosa que
	# no sea el reproductor de ambiente.
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = buf.size()
	st.save_to_wav(ProjectSettings.globalize_path(destino))
