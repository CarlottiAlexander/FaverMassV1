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

CAMBIAR EL MODELO DE UN ENEMIGO
-------------------------------
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
