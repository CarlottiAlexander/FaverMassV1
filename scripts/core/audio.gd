extends Node
## AUTOLOAD. Todo el sonido del juego pasa por acá: los buses, la resolución de qué
## sonido le toca a cada entidad, y los reproductores.
##
## LA IDEA CENTRAL: **el sonido es propiedad de la ENTIDAD**, no de una base de
## datos del juego. Un enemigo de un mod trae sus sonidos adentro de su carpeta,
## igual que trae su `.glb`. Este archivo no conoce ningún sonido: sabe resolver
## `(tipo, ranura)` y reproducir.
##
## POR QUÉ POOLS Y NO UN REPRODUCTOR POR ENTIDAD. Los números del juego lo obligan:
## la Minigun a full spin-up dispara **60 veces por segundo** (nominal 125, pero
## `_process_weapon` corre en `_physics_process` a 60 Hz) durante ~6 segundos
## seguidos, y cada bala que pega es OTRO evento. Con 70 enemigos vivos, colgar un
## `AudioStreamPlayer3D` de cada uno son 70 nodos que además tienen `polyphony 1`,
## o sea que se cortan a sí mismos. Con un pool el costo queda ACOTADO — el mismo
## criterio que `FxManager` usa para gibs y decals.

## Voces simultáneas. 24 en el mundo alcanza de sobra: más allá de eso el oído no
## distingue nada y sólo se paga CPU.
const VOCES_3D := 24
## Las planas son las de mayor frecuencia (tu propia arma), pero también las más
## cortas.
const VOCES_FLAT := 8

## Intervalo mínimo entre dos reproducciones de la MISMA clave. Sin esto, los 8
## perdigones de la escopeta disparan 8 impactos idénticos en el mismo frame, que
## no suena a escopeta sino a distorsión.
const INTERVALO_MIN := 0.04

## Más allá de esto un enemigo no suena. Se apoya en el mismo criterio que el corte
## de dibujado: si no se ve porque la niebla es opaca, tampoco tiene que oírse.
const DIST_MAX_3D := 45.0

const BUS_SFX := "SFX"
const BUS_MUSICA := "Musica"
const BUS_AMBIENTE := "Ambiente"

var _p3d: Array = []
var _pflat: Array = []
## clave -> segundos del último disparo, para el intervalo mínimo.
var _ultimo: Dictionary = {}
## "tipo|ranura" -> AudioStream (o null si quedó mudo). Lo vacía `ModManager`.
var _cache: Dictionary = {}

## Contadores para poder verificar esto sin escuchar nada (ver tools/audio_report).
var pico_voces_3d := 0
var eventos := 0
var descartados := 0

func _ready() -> void:
	_crear_buses()
	Config.apply_volume()
	_crear_pools()

# --- Buses ------------------------------------------------------------------

## Se arman por código porque en esta máquina no hay editor gráfico y un
## `default_bus_layout.tres` escrito a mano es de lo más frágil que hay.
func _crear_buses() -> void:
	for nombre in [BUS_SFX, BUS_MUSICA, BUS_AMBIENTE]:
		if AudioServer.get_bus_index(nombre) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, nombre)
		AudioServer.set_bus_send(idx, "Master")

# --- Pools ------------------------------------------------------------------

func _crear_pools() -> void:
	for i in VOCES_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = BUS_SFX
		# El árbol se pausa fuera de PLAYING; un sonido que sigue sonando en la
		# pantalla de muerte quedaría colgado.
		p.max_distance = DIST_MAX_3D
		add_child(p)
		_p3d.append(p)
	for i in VOCES_FLAT:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_pflat.append(p)

# --- Reproducción -----------------------------------------------------------

## Sonido en una posición del mundo. `clave` sirve para el intervalo mínimo: dos
## llamadas con la misma clave muy seguidas se descartan.
func play_3d(stream: AudioStream, pos: Vector3, clave := "", volumen := 1.0) -> bool:
	if stream == null or not _pasa_intervalo(clave):
		return false
	# Recorte por distancia: se decide ACÁ y no en el reproductor para no gastar
	# una voz en algo que igual no se iba a oír.
	if _hay_jugador() and pos.distance_squared_to(_pos_jugador()) > DIST_MAX_3D * DIST_MAX_3D:
		return false

	var p: AudioStreamPlayer3D = _libre_3d()
	p.stream = stream
	p.global_position = pos
	p.volume_db = linear_to_db(clampf(volumen, 0.01, 2.0))
	p.play()
	eventos += 1
	pico_voces_3d = maxi(pico_voces_3d, _sonando_3d())
	return true

## Sonido sin posición: tu propia arma, tu propio dolor. No se atenúa con la
## distancia porque ocurre EN vos.
func play_flat(stream: AudioStream, clave := "", volumen := 1.0) -> bool:
	if stream == null or not _pasa_intervalo(clave):
		return false
	var p: AudioStreamPlayer = _libre_flat()
	p.stream = stream
	p.volume_db = linear_to_db(clampf(volumen, 0.01, 2.0))
	p.play()
	eventos += 1
	return true

## Atajo: resuelve el sonido de una entidad y lo reproduce donde está.
func play_entity(tipo: String, ranura: String, pos: Vector3, volumen := 1.0) -> bool:
	return play_3d(resolver(tipo, ranura), pos, "%s|%s" % [tipo, ranura], volumen)

# --- Resolución: de dónde sale el sonido de una entidad ---------------------

## Cadena: lo que declaró el MOD -> lo que tiene el tipo base -> silencio.
##
## Devuelve null cuando no hay nada, y eso NO es un error: un mod puede declararse
## mudo a propósito. `tools/audio_report.tscn` es el que muestra qué resolvió cada
## tipo, para que "mi bicho no suena" tenga una respuesta.
func resolver(tipo: String, ranura: String) -> AudioStream:
	var clave := "%s|%s" % [tipo, ranura]
	if _cache.has(clave):
		return _cache[clave]

	var s: AudioStream = ModManager.sound_for(tipo, ranura)
	if s == null and not ModManager.sound_is_silent(tipo):
		s = _base(ModManager.sound_inherit_of(tipo), ranura)
	_cache[clave] = s
	return s

## Sonidos del juego base, por convención de nombre de archivo. Van por `res://`
## porque son NUESTROS y sí pasan por el importador de Godot; los de los mods no.
func _base(tipo: String, ranura: String) -> AudioStream:
	for ext in ["ogg", "wav", "mp3"]:
		var p := "res://assets/audio/enemies/%s_%s.%s" % [tipo, ranura, ext]
		if ResourceLoader.exists(p):
			return load(p)
	# Familia: varios enemigos comparten sonido y no tiene sentido duplicar archivos.
	for ext in ["ogg", "wav", "mp3"]:
		var p := "res://assets/audio/enemies/generic_%s.%s" % [ranura, ext]
		if ResourceLoader.exists(p):
			return load(p)
	return null

## Disparo de un arma. Cae a un sonido de familia si el arma no tiene el suyo, así
## agregar un arma nueva no obliga a grabar nada.
func weapon_shot(id: String) -> AudioStream:
	var s := ui("weapons/%s_shot" % id)
	return s if s != null else ui("weapons/generic_shot")

## Sonido del juego base que no pertenece a un enemigo (armas, jugador, interfaz).
func ui(nombre: String) -> AudioStream:
	var clave := "ui|" + nombre
	if _cache.has(clave):
		return _cache[clave]
	var s: AudioStream = null
	for ext in ["ogg", "wav", "mp3"]:
		var p := "res://assets/audio/%s.%s" % [nombre, ext]
		if ResourceLoader.exists(p):
			s = load(p)
			break
	_cache[clave] = s
	return s

## La llama `ModManager.commit()`. El caché es de un autoload: sobrevive a
## `reload_current_scene()`, así que sin vaciarlo un mod recién activado seguiría
## sonando como el anterior. Es la misma trampa que ya mordió con el trasplante de
## cabeza y con los nombres de animación.
func clear_cache() -> void:
	_cache.clear()

# --- Interno ----------------------------------------------------------------

func _pasa_intervalo(clave: String) -> bool:
	if clave == "":
		return true
	var ahora := Time.get_ticks_msec() / 1000.0
	if ahora - float(_ultimo.get(clave, -99.0)) < INTERVALO_MIN:
		descartados += 1
		return false
	_ultimo[clave] = ahora
	return true

## Si están todas ocupadas se ROBA la más vieja. Es preferible cortar un sonido
## viejo que tragarse el nuevo: en una ráfaga, lo último que pasó es lo que importa.
func _libre_3d() -> AudioStreamPlayer3D:
	var mas_vieja: AudioStreamPlayer3D = _p3d[0]
	var mayor := -1.0
	for p: AudioStreamPlayer3D in _p3d:
		if not p.playing:
			return p
		var t := p.get_playback_position()
		if t > mayor:
			mayor = t
			mas_vieja = p
	return mas_vieja

func _libre_flat() -> AudioStreamPlayer:
	var mas_vieja: AudioStreamPlayer = _pflat[0]
	var mayor := -1.0
	for p: AudioStreamPlayer in _pflat:
		if not p.playing:
			return p
		var t := p.get_playback_position()
		if t > mayor:
			mayor = t
			mas_vieja = p
	return mas_vieja

func _sonando_3d() -> int:
	var n := 0
	for p: AudioStreamPlayer3D in _p3d:
		if p.playing:
			n += 1
	return n

## Devuelven tipos CONCRETOS y no `null`: Godot trata como ERROR inferir `:=` desde
## un Variant, y un helper que devuelve "Vector3 o null" contagia ese problema a
## todos sus llamadores.
func _hay_jugador() -> bool:
	return not get_tree().get_nodes_in_group("player").is_empty()

func _pos_jugador() -> Vector3:
	var ps := get_tree().get_nodes_in_group("player")
	return (ps[0] as Node3D).global_position if ps.size() > 0 else Vector3.ZERO

# --- Pasos --------------------------------------------------------------------

## Variantes de pisada del juego base. Se buscan por número (`step00`, `step01`, …)
## y NO listando la carpeta: bajo `res://` un `.ogg` pasa por el importador y en un
## build exportado el nombre del archivo en disco no es el que se ve acá.
const MAX_PASOS := 16

var _pasos: Array[AudioStream] = []
var _pasos_listos := false
var _paso_previo := -1

## Una pisada al azar, nunca la misma dos veces seguidas. Escuchar el MISMO golpe
## doscientas veces por partida es la fatiga auditiva más barata de evitar.
func paso() -> AudioStream:
	if not _pasos_listos:
		_cargar_pasos()
	if _pasos.is_empty():
		return null
	if _pasos.size() == 1:
		return _pasos[0]
	var i := _paso_previo
	while i == _paso_previo:
		i = randi() % _pasos.size()
	_paso_previo = i
	return _pasos[i]

func _cargar_pasos() -> void:
	_pasos_listos = true
	for n in MAX_PASOS:
		for ext in ["ogg", "wav", "mp3"]:
			var p := "res://assets/audio/footsteps/step%02d.%s" % [n, ext]
			if ResourceLoader.exists(p):
				_pasos.append(load(p))
				break
