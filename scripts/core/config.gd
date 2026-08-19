extends Node
## Autoload. Ajustes que el jugador cambia y que sobreviven a cerrar el juego
## (sección 11). Vive aparte de `GameData` a propósito: `GameData` es una tabla de
## balance de sólo lectura, sin estado ni contacto con el sistema operativo,
## mientras que esto ESCRIBE a disco y toca el `DisplayServer`. Mezclarlos hacía
## que el archivo de balance dependiera de la plataforma.

const CONFIG_PATH := "user://config.cfg"

const FOV_DEFAULT := 90.0
const FOV_MIN := 60.0
const FOV_MAX := 110.0

var master_volume := 0.8
var sfx_volume := 1.0
var mouse_sensitivity := 0.002
var fov := 90.0
var fullscreen := false
## Ids de mods que el jugador APAGÓ. Se guardan los apagados y no los prendidos a
## propósito: así un mod recién copiado a la carpeta arranca habilitado, sin que
## haya que entrar al menú a prenderlo. La lista es sólo de excepciones.
var mods_disabled: Array = []

func _ready() -> void:
	load_config()

func load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or not line.contains("="):
			continue
		var parts := line.split("=", true, 1)
		var key := parts[0].strip_edges()
		var value := parts[1].strip_edges()
		match key:
			"master_volume": master_volume = clampf(value.to_float(), 0.0, 1.0)
			"sfx_volume": sfx_volume = clampf(value.to_float(), 0.0, 1.0)
			"mouse_sensitivity": mouse_sensitivity = clampf(value.to_float(), 0.0005, 0.01)
			"fov": fov = clampf(value.to_float(), FOV_MIN, FOV_MAX)
			"fullscreen": fullscreen = value == "true"
			# Lista separada por comas. Un id vacío ensuciaría el filtro, así que
			# se descartan; y si la clave no está, la lista queda vacía = todo
			# habilitado, que es el estado correcto para una instalación nueva.
			"mods_disabled":
				mods_disabled = []
				for part in value.split(",", false):
					var id := String(part).strip_edges()
					if id != "":
						mods_disabled.append(id)
			_: pass  # claves desconocidas se ignoran

func save_config() -> void:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	f.store_line("master_volume=%s" % master_volume)
	f.store_line("sfx_volume=%s" % sfx_volume)
	f.store_line("mouse_sensitivity=%s" % mouse_sensitivity)
	f.store_line("fov=%s" % fov)
	f.store_line("fullscreen=%s" % ("true" if fullscreen else "false"))
	f.store_line("mods_disabled=%s" % ",".join(PackedStringArray(mods_disabled)))

func apply_fullscreen() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
