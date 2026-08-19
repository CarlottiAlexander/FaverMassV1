class_name ModPaths
extends RefCounted
## Dónde vive la carpeta de mods y cómo se crea la primera vez.
##
## NO se usa `user://` como primera opción a propósito: en Windows resuelve a
## %APPDATA%\Godot\app_userdata\<proyecto>\, que el jugador al que apunta esto no
## va a encontrar nunca. Se prefiere una carpeta al lado del juego, y si no se
## puede escribir ahí (instalado en Program Files, carpeta de sólo lectura) se cae
## a `user://` y el menú lo dice en pantalla — nunca en silencio.

const LEEME := """CARPETA DE MODS DE FAVER MASS
=============================

Todo lo que pongas acá adentro lo carga el juego al arrancar.

LO MAS FACIL: CAMBIAR EL MODELO DE UN ENEMIGO
---------------------------------------------
Crea una carpeta con el nombre que quieras y adentro otra llamada
"reemplazos". Pone ahi un .glb con el nombre del enemigo:

    mods/
      mi_pack/
        reemplazos/
          hollow.glb

Los nombres de enemigo que existen hoy son:

    hollow        thrall        dire_bat      blood_lord
    knight        capra         sorceress     demon_skull

El tamano y la hitbox se ajustan SOLOS al modelo nuevo: el juego mide el
modelo, lo escala a la altura que le corresponde a ese enemigo, lo centra
en su colision, y arma la esfera de la cabeza para los headshots. No hay
ningun numero que configurar.

Lo que NO cambia es el comportamiento: si reemplazas al Hollow, tu bicho
va a perseguirte igual que un Hollow. Es un cambio de piel.

CREAR UN ENEMIGO NUEVO
----------------------
Para algo mas que cambiar la piel, pone un archivo "mod.json" en tu carpeta:

    mods/
      mi_pack/
        mod.json
        modelos/
          goblin.glb

Y adentro del mod.json:

    {
      "format": 1,
      "name": "Goblins de Fulano",
      "author": "fulano",

      "enemies": {
        "goblin": {
          "name": "Goblin",
          "model": "modelos/goblin.glb",

          "hp": 60, "speed": 6.0, "damage": 9, "atk_cd": 0.8,
          "xp": 6, "regen": 1.5,
          "radius": 0.40, "height": 1.80, "head_radius": 0.24,
          "flying": false,
          "color": [0.25, 0.60, 0.20],

          "spawn": { "min_wave": 3, "share": 0.12, "flat": 1 },
          "preset": "chaser"
        }
      }
    }

Lo UNICO obligatorio es "model". Todo lo demas tiene valor por defecto.

Si usas un nombre de enemigo que ya existe (por ejemplo "hollow"), lo estas
REEMPLAZANDO: se pisan solo los campos que declares y el resto queda como
estaba.

CUANDO APARECE Y CUANTOS ("spawn")
    min_wave   desde que oleada puede aparecer
    share      cuantos, en proporcion al tamano de la oleada (0.12 = 12%)
    flat       cuantos fijos, siempre
    rand       [min, max] cuantos al azar, ej. [2, 4]
    step       se multiplica por (1 + oleada/step). Ojo que crece rapido.
    dist       [min, max] a que distancia del jugador nace

COMO SE COMPORTA ("preset") — uno de estos siete:
    chaser     va derecho al jugador (por defecto)
    flyer      igual pero volando
    weaver     zigzaguea mientras persigue
    wobbler    vuela tambaleandose
    brute      embiste cada tantos segundos y agarra a otros enemigos
    stalker    se queda quieto hasta que lo miras, despues carga y salta
    orbiter    se acerca y orbita alrededor tuyo

RASGOS ("traits") — se pueden combinar todos los que quieras
    "traits": {
      "explode_on_death":   { "radius": 8.0, "damage": 40 },
      "shield":             { "amount": 50, "regen_delay": 3.0, "regen_rate": 10 },
      "on_hit_speed_burst": { "mult": 1.5, "time": 1.0 },
      "summon_on_death":    { "type": "dire_bat", "count": 2, "spread": 0.6 },
      "cloak":              { "reveal_distance": 12.0, "hide_on_minimap": false },
      "headshot_immune":    {}
    }

    explode_on_death    explota al morir. Le pega AL JUGADOR, no a los otros
                        enemigos (si no, una oleada de estos se mata sola).
    shield              absorbe dano antes que la vida y se recarga si lo
                        dejas tranquilo. Un headshot lo saltea igual.
    on_hit_speed_burst  se acelera cuando lo golpeas, en vez de frenarse.
    summon_on_death     invoca otros enemigos al morir. Lo invocado NO cuenta
                        para terminar la oleada.
    cloak               invisible hasta que te acercas.
    headshot_immune     no muere de un headshot.

No se puede escribir comportamiento propio: los mods NO ejecutan codigo. Si
necesitas logica condicional ("si el jugador esta bajo de vida, huye"), jefes
multifase o armas nuevas, eso hoy no se puede.

SI TU MODELO NO SE VE BIEN
--------------------------
    "model_yaw": 0          si camina de espaldas (por defecto 180)
    "hitbox": { "shape": "sphere" }     o "capsule", o "auto"
    "head": { "keywords": ["cabeza"], "bone": "mixamorig:Head" }
        si el juego no encuentra la cabeza para los headshots
    "anim": { "idle": "Idle", "run": ["Correr", "Walk"], "attack": "Morder" }
        si tus animaciones se llaman distinto. El juego intenta adivinarlas
        por nombre, asi que muchas veces no hace falta.

QUE PASA SI ALGO SALE MAL
-------------------------
Nada grave. Un archivo roto o un modelo que el juego no puede leer se
descarta solo: se sigue jugando con el modelo original y el menu de Mods
te muestra que fallo y por que. Un mod malo nunca impide que el juego
arranque.

COSAS A TENER EN CUENTA
-----------------------
- Formato .glb (binario). El .gltf suelto con archivos al lado no sirve.
- Si tu modelo trae la textura en un archivo aparte, ponela al lado del
  .glb respetando la ruta que el modelo espera.
- Tope de 64 MB por archivo. Los modelos de la comunidad se cargan sin
  pasar por el importador de Godot, asi que no tienen LOD ni texturas
  comprimidas: uno muy pesado se nota en el rendimiento.
- Si tu modelo camina de espaldas, esta mirando para el otro lado. Por
  ahora la unica solucion es girarlo en tu programa de 3D y exportarlo
  de nuevo (mas adelante va a poder configurarse desde un archivo).

SEGURIDAD
---------
Los mods NO ejecutan codigo: son modelos y datos, nada mas. Aun asi,
segui bajando cosas solo de gente en la que confies.
"""

## Orden de búsqueda. Gana el primero que se pueda usar; el elegido se muestra en
## el menú de Mods, así el jugador nunca tiene que adivinar dónde quedó.
static func resolve_dir() -> String:
	# 1) --mods=<ruta>: lo usan las herramientas de tools/ para correr contra su
	#    fixture sin depender de la carpeta real del jugador.
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--mods="):
			return _absolutize(s.substr(7))

	# 2) Variable de entorno, para quien quiera tener sus mods en otro disco.
	var env := OS.get_environment("FAVERMASS_MODS")
	if env != "":
		return env.simplify_path()

	# 3) Corriendo desde fuente. OJO: al lado del PROYECTO, no del ejecutable —
	#    jugar.bat usa el binario del editor, que vive en Tools/Godot/, y ahí la
	#    carpeta no tendría nada que ver con el juego.
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://mods").simplify_path()

	# 4) Build exportado: al lado del .exe, que es donde el jugador descomprime.
	return OS.get_executable_path().get_base_dir().path_join("mods").simplify_path()

## Acepta las tres formas en que a alguien se le puede ocurrir escribir una ruta:
## `res://algo`, una absoluta del disco, o una relativa al proyecto (que es lo que
## uno tipea sin pensar al pasar `--mods=tools/mods_fixture`).
static func _absolutize(p: String) -> String:
	if p.begins_with("res://") or p.begins_with("user://"):
		return ProjectSettings.globalize_path(p).simplify_path()
	if p.is_absolute_path():
		return p.simplify_path()
	return ProjectSettings.globalize_path("res://".path_join(p)).simplify_path()

## Crea la carpeta si no existe y deja el LEEME. Devuelve
## {dir: String, fallback: bool, error: String}.
## `fallback` en true significa que no se pudo escribir donde correspondía y se
## usó `user://` — el menú tiene que decirlo, porque el jugador va a estar mirando
## la carpeta equivocada.
static func ensure_dir() -> Dictionary:
	var dir := resolve_dir()
	if _try_make(dir):
		_write_leeme(dir)
		return {"dir": dir, "fallback": false, "error": ""}

	var alt := ProjectSettings.globalize_path("user://mods").simplify_path()
	if _try_make(alt):
		_write_leeme(alt)
		return {"dir": alt, "fallback": true,
			"error": "No se pudo escribir en %s; usando %s" % [dir, alt]}

	return {"dir": dir, "fallback": false,
		"error": "No se pudo crear la carpeta de mods en %s ni en %s" % [dir, alt]}

static func _try_make(dir: String) -> bool:
	if DirAccess.dir_exists_absolute(dir):
		return true
	return DirAccess.make_dir_recursive_absolute(dir) == OK

## El LEEME se REESCRIBE en cada arranque a propósito: es documentación generada,
## no un archivo del jugador. Si mañana se agregan campos nuevos, el que ya tenía
## la carpeta creada se entera igual.
static func _write_leeme(dir: String) -> void:
	var f := FileAccess.open(dir.path_join("LEEME.txt"), FileAccess.WRITE)
	if f:
		f.store_string(LEEME)
		f.close()
