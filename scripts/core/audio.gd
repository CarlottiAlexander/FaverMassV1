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

## Cuántas variantes numeradas se buscan por ranura (`_00` … `_15`).
const MAX_VARIANTES := 16
const EXTS := ["ogg", "wav", "mp3"]

const BUS_SFX := "SFX"
const BUS_MUSICA := "Musica"
const BUS_AMBIENTE := "Ambiente"

## Con qué muestra y a qué TONO suena cada arma.
##
## Hay cuatro grabaciones reales para diez armas, así que el resto se derivan
## cambiando el tono. No es un parche: es como se hace de verdad en audio de juegos.
## Bajar el tono agranda el arma y subirlo la achica, y esa es exactamente la
## diferencia que el oído usa para separar un revólver de una pistola.
##
## Las asignaciones tampoco son al azar: el SKS dispara el MISMO cartucho 7.62x39
## que el AK-47, y el Mosin Nagant es literalmente un rifle de cerrojo de
## francotirador. Donde se pudo, la muestra ES el arma.
const ARMA_SONIDO := {
	"pistol":   {"src": "pistol",  "tono": 1.00},
	"revolver": {"src": "pistol",  "tono": 0.72},  # más grave = más calibre
	"smg":      {"src": "pistol",  "tono": 1.14},  # mismo cartucho, cañón corto
	"ak47":     {"src": "rifle",   "tono": 1.00},
	"shotgun":  {"src": "shotgun", "tono": 1.00},
	"sniper":   {"src": "sniper",  "tono": 1.00},
	"lmg":      {"src": "rifle",   "tono": 0.86},
	"minigun":  {"src": "rifle",   "tono": 1.20},
	"rocket":   {"src": "shotgun", "tono": 0.55},  # el fogonazo del tubo, no la explosión
	"railgun":  {"src": "railgun", "tono": 1.00},
}

var _p3d: Array = []
var _pflat: Array = []
## clave -> segundos del último disparo, para el intervalo mínimo.
var _ultimo: Dictionary = {}
## clave -> Array[AudioStream] con TODAS las variantes. Lo vacía `ModManager`.
var _cache: Dictionary = {}
## clave -> índice de la última variante usada, para no repetirla.
var _ultima_variante: Dictionary = {}

## RNG PROPIO, no el global. En este proyecto la secuencia del RNG global es un
## invariante de balance: `wave_composition()` consume `randi_range` en un orden
## fijo y `tools/wave_table.gd` lo verifica con semilla. Si el audio robara números
## de ahí, la composición de oleada dependería de cuántos tiros sonaron — un
## acoplamiento absurdo y muy difícil de diagnosticar. Con un RNG aparte no puede
## pasar nunca.
var _rng := RandomNumberGenerator.new()

## Contadores para poder verificar esto sin escuchar nada (ver tools/audio_report).
var pico_voces_3d := 0
var eventos := 0
var descartados := 0

func _ready() -> void:
	_rng.randomize()
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
func play_3d(stream: AudioStream, pos: Vector3, clave := "", volumen := 1.0, tono := 1.0) -> bool:
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
	# Se asigna SIEMPRE, no sólo cuando difiere de 1: los reproductores del pool se
	# reciclan, así que un tono dejado por el sonido anterior se contagiaría al
	# siguiente. Es el mismo tipo de bug que los materiales compartidos de la
	# explosión, y en audio sería mucho más difícil de rastrear.
	p.pitch_scale = clampf(tono, 0.05, 4.0)
	p.play()
	eventos += 1
	pico_voces_3d = maxi(pico_voces_3d, _sonando_3d())
	return true

## Sonido sin posición: tu propia arma, tu propio dolor. No se atenúa con la
## distancia porque ocurre EN vos.
func play_flat(stream: AudioStream, clave := "", volumen := 1.0, tono := 1.0) -> bool:
	if stream == null or not _pasa_intervalo(clave):
		return false
	var p: AudioStreamPlayer = _libre_flat()
	p.stream = stream
	p.volume_db = linear_to_db(clampf(volumen, 0.01, 2.0))
	p.pitch_scale = clampf(tono, 0.05, 4.0)
	p.play()
	eventos += 1
	return true

## Atajo: resuelve el sonido de una entidad y lo reproduce donde está.
func play_entity(tipo: String, ranura: String, pos: Vector3, volumen := 1.0) -> bool:
	return play_3d(resolver(tipo, ranura), pos, "%s|%s" % [tipo, ranura], volumen)

## El disparo del arma equipada, con su muestra y su tono (ver ARMA_SONIDO). Va
## plano y no posicional: tu propia arma no tiene que atenuarse con la distancia.
func play_weapon(id: String) -> bool:
	var cfg: Dictionary = ARMA_SONIDO.get(id, {})
	var src: String = cfg.get("src", id)
	var s := ui("weapons/%s_shot" % src)
	if s == null:
		s = ui("weapons/generic_shot")
	return play_flat(s, "shot", 1.0, float(cfg.get("tono", 1.0)))

# --- Resolución: de dónde sale el sonido de una entidad ---------------------

## Cadena: lo que declaró el MOD -> lo que tiene el tipo base -> silencio.
##
## Devuelve null cuando no hay nada, y eso NO es un error: un mod puede declararse
## mudo a propósito. `tools/audio_report.tscn` es el que muestra qué resolvió cada
## tipo, para que "mi bicho no suena" tenga una respuesta.
func resolver(tipo: String, ranura: String) -> AudioStream:
	var clave := "%s|%s" % [tipo, ranura]
	if not _cache.has(clave):
		var lista: Array[AudioStream] = []
		var m: AudioStream = ModManager.sound_for(tipo, ranura)
		if m != null:
			lista.append(m)
		elif not ModManager.sound_is_silent(tipo):
			lista = _base(ModManager.sound_inherit_of(tipo), ranura)
		_cache[clave] = lista
	return _elegir(clave)

## Sonidos del juego base, por convención de nombre de archivo. Van por `res://`
## porque son NUESTROS y sí pasan por el importador de Godot; los de los mods no.
func _base(tipo: String, ranura: String) -> Array[AudioStream]:
	var propio := _variantes("res://assets/audio/enemies/%s_%s" % [tipo, ranura])
	if not propio.is_empty():
		return propio
	# Familia: varios enemigos comparten sonido y no tiene sentido duplicar archivos.
	return _variantes("res://assets/audio/enemies/generic_%s" % ranura)

## Qué muestra le toca a un arma, sin reproducirla. La usa `audio_report` para
## poder decir cuál quedó muda. Un arma sin entrada en `ARMA_SONIDO` busca su
## propio archivo y después el de familia, así que sumar un arma nueva no obliga a
## grabar ni a declarar nada.
func weapon_shot(id: String) -> AudioStream:
	var src: String = ARMA_SONIDO.get(id, {}).get("src", id)
	var s := ui("weapons/%s_shot" % src)
	return s if s != null else ui("weapons/generic_shot")

## Sonido del juego base que no pertenece a un enemigo (armas, jugador, interfaz,
## pasos). Acepta variantes numeradas igual que todo lo demás.
func ui(nombre: String) -> AudioStream:
	var clave := "ui|" + nombre
	if not _cache.has(clave):
		_cache[clave] = _variantes("res://assets/audio/" + nombre)
	return _elegir(clave)

## Un sonido puede ser UN archivo (`hollow_hit.ogg`) o VARIAS variantes numeradas
## (`hollow_hit_00.ogg`, `_01`, …), y se devuelven todas las que haya. Poner un
## archivo más en la carpeta alcanza para sumar variación: no hay que tocar código
## ni declarar nada.
func _variantes(base: String) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	for ext in EXTS:
		var p := "%s.%s" % [base, ext]
		if ResourceLoader.exists(p):
			out.append(load(p))
			break
	for n in MAX_VARIANTES:
		for ext in EXTS:
			var p := "%s_%02d.%s" % [base, n, ext]
			if ResourceLoader.exists(p):
				out.append(load(p))
				break
	return out

## Elige una variante al azar sin repetir la anterior. Escuchar EXACTAMENTE el mismo
## alarido doscientas veces por partida es la fatiga auditiva más barata de evitar,
## y el golpe es el caso extremo: la Minigun hace impactar 60 balas por segundo.
func _elegir(clave: String) -> AudioStream:
	var lista: Array = _cache[clave]
	if lista.is_empty():
		return null
	if lista.size() == 1:
		return lista[0]
	var prev: int = _ultima_variante.get(clave, -1)
	var i := prev
	while i == prev:
		i = _rng.randi_range(0, lista.size() - 1)
	_ultima_variante[clave] = i
	return lista[i]

## Cuántas variantes tiene una ranura ya resuelta. Sólo para `audio_report`.
func variantes_de(clave: String) -> int:
	return (_cache[clave] as Array).size() if _cache.has(clave) else 0

## La llama `ModManager.commit()`. El caché es de un autoload: sobrevive a
## `reload_current_scene()`, así que sin vaciarlo un mod recién activado seguiría
## sonando como el anterior. Es la misma trampa que ya mordió con el trasplante de
## cabeza y con los nombres de animación.
func clear_cache() -> void:
	_cache.clear()
	_ultima_variante.clear()

## Al salir hay que SOLTAR los streams. Si no, Godot cierra con
## "15 resources still in use at exit": el caché y los reproductores del pool los
## siguen referenciando pasado el punto en que el motor da los recursos por
## liberados. No rompe nada, pero la vara de este proyecto es "0 errores en el
## soak" y un mensaje que aparece siempre entrena a ignorar esa salida — que es
## justo lo que la hace inútil.
func _exit_tree() -> void:
	soltar()

## Suelta TODO stream que este autoload esté reteniendo. Hay que parar el
## reproductor antes de desengancharle el stream: mientras suena, la reproducción
## en curso lo sigue referenciando y asignar `null` no alcanza.
func soltar() -> void:
	for p: AudioStreamPlayer3D in _p3d:
		p.stop()
		p.stream = null
	for p: AudioStreamPlayer in _pflat:
		p.stop()
		p.stream = null
	clear_cache()

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
