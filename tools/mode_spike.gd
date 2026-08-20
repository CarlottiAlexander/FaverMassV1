extends Node
## SPIKE: ¿se puede compilar y ejecutar GDScript que NO está en res://?
##
## Es la pregunta que decide si los mods pueden traer su propio código. Nada del
## sistema de modos con scripts se puede planificar en serio hasta que esto esté
## contestado, y contestado en el entorno que importa.
##
## OJO CON EL FALSO VERDE: corriendo desde fuente, `ModPaths.resolve_dir()`
## devuelve `res://mods`, así que una ruta "de mod" se localiza sola y el spike da
## verde sin haber probado nada. Por eso escribe sus archivos en una carpeta que se
## le pasa por parámetro, y hay que correrlo apuntando FUERA del proyecto:
##
##   Godot --headless --path . tools/mode_spike.tscn
##   Godot --headless --path . tools/mode_spike.tscn -- --dir=C:/Temp/spike
##
## El caso que de verdad importa es el tercero —un build exportado— y ese necesita
## los export templates instalados.

const VALIDO := """extends GameMode
var marca := 0
func _setup(params):
	marca = int(params.get("n", 7))
func sumar(a, b):
	return a + b
"""

const ROTO := """extends GameMode
func _setup(params)
	var x = 1
"""

const BASE_EQUIVOCADA := """extends Node
func _setup(params):
	pass
"""

## Tiene que COMPILAR bien y explotar recién al ejecutarse. Ojo: `_tick` está
## declarado `-> void` en GameMode, así que devolver un valor sería un error de
## COMPILACIÓN y estaríamos midiendo otra cosa (me pasó en la primera corrida).
const REVIENTA := """extends GameMode
func _tick(delta):
	var d = null
	d.metodo_que_no_existe()
"""

var _dir := ""
var _pasa := 0
var _falla := 0

func _ready() -> void:
	_dir = _resolver_dir()
	print("SPIKE de scripts de mod")
	print("carpeta: %s" % _dir)
	print("entorno: %s" % ("EDITOR/fuente" if OS.has_feature("editor") else "EXPORTADO (template)"))
	print("dentro del proyecto: %s" % ("SI — este verde MIENTE" if _dentro_del_proyecto(_dir) else "no"))
	print("")

	if DirAccess.make_dir_recursive_absolute(_dir) != OK and not DirAccess.dir_exists_absolute(_dir):
		print("ABORTADO: no se pudo crear %s" % _dir)
		get_tree().quit()
		return

	_caso_1_leer()
	_caso_2_compilar_valido()
	_caso_3_compilar_roto()
	_caso_4_base_equivocada()
	_caso_5_instanciar_y_llamar()
	_caso_6_error_de_runtime()
	_caso_7_load_directo()
	_caso_8_recompilar_editado()

	print("")
	print("=".repeat(58))
	print("RESULTADO: %d pasan, %d fallan" % [_pasa, _falla])
	if _dentro_del_proyecto(_dir):
		print("⚠ Corrido DENTRO del proyecto: no prueba el caso real.")
		print("  Repetir con  -- --dir=<ruta absoluta fuera del proyecto>")
	if OS.has_feature("editor"):
		print("⚠ Corrido desde fuente. El veredicto que vale es el del build EXPORTADO.")
	get_tree().quit()

# --- casos ------------------------------------------------------------------

func _caso_1_leer() -> void:
	# Control: este eslabón ya está probado en producción (ModModelLoader lee los
	# .glb con rutas absolutas). Si falla acá, no tiene sentido seguir.
	var p := _escribir("control.txt", "hola")
	var txt := FileAccess.get_file_as_string(p)
	_chequear("1. leer un archivo por ruta absoluta", txt.strip_edges() == "hola", txt.length())

func _caso_2_compilar_valido() -> void:
	var r := _compilar(_escribir("valido.gd", VALIDO))
	_chequear("2. compilar un script válido", r["err"] == OK, "err=%d" % r["err"])

func _caso_3_compilar_roto() -> void:
	# EL CASO MÁS IMPORTANTE DE TODOS. GDScript no tiene try/catch, así que la
	# única defensa contra un mod roto es que `reload()` devuelva un Error en vez
	# de tumbar el proceso. Si esto no se cumple, un mod con una coma de más se
	# lleva puesto el juego del jugador.
	var r := _compilar(_escribir("roto.gd", ROTO))
	_chequear("3. un script ROTO devuelve error (y el juego sigue)", r["err"] != OK, "err=%d" % r["err"])

func _caso_4_base_equivocada() -> void:
	var r := _compilar(_escribir("base_mala.gd", BASE_EQUIVOCADA))
	if r["err"] != OK:
		_chequear("4. rechazar `extends Node`", false, "ni siquiera compiló")
		return
	var inst = r["script"].new()
	var es_modo: bool = inst is GameMode
	_chequear("4. rechazar `extends Node` (no es GameMode)", not es_modo, "is GameMode=%s" % es_modo)

func _caso_5_instanciar_y_llamar() -> void:
	var r := _compilar(_escribir("valido2.gd", VALIDO))
	if r["err"] != OK:
		_chequear("5. instanciar y llamar", false, "no compiló")
		return
	var s: GDScript = r["script"]
	if not s.can_instantiate():
		_chequear("5. instanciar y llamar", false, "can_instantiate=false")
		return
	var inst = s.new()
	var es_modo: bool = inst is GameMode
	inst.call("_setup", {"n": 42})
	var suma = inst.call("sumar", 2, 3)
	_chequear("5. instanciar, es GameMode, y responde",
		es_modo and int(inst.get("marca")) == 42 and int(suma) == 5,
		"isGameMode=%s marca=%s suma=%s" % [es_modo, inst.get("marca"), suma])

func _caso_6_error_de_runtime() -> void:
	# Compila bien pero explota al ejecutarse. Marca el LÍMITE del aislamiento: el
	# error se imprime, pero queremos saber si el proceso sobrevive al frame.
	var r := _compilar(_escribir("revienta.gd", REVIENTA))
	if r["err"] != OK:
		_chequear("6. error de runtime en un hook", false, "no compiló")
		return
	var inst = r["script"].new()
	inst.call("_tick", 0.016)
	_chequear("6. error de runtime en un hook NO mata el proceso", true, "seguimos vivos")

func _caso_7_load_directo() -> void:
	# El plan B: load() sobre ruta absoluta. Interesa saber si funciona y, sobre
	# todo, si distingue "no compila" de "no existe" (spoiler: devuelve null en los
	# dos casos, por eso no es la opción principal).
	var p := _escribir("porload.gd", VALIDO)
	var res = load(p)
	_chequear("7. load() por ruta absoluta", res != null and res is GDScript,
		"tipo=%s" % ("null" if res == null else res.get_class()))

func _caso_8_recompilar_editado() -> void:
	# Si el modder edita su script y vuelve a entrar, ¿ve su cambio? Con
	# set_source_code no hay caché de por medio, así que tiene que dar el valor
	# nuevo. Con load() habría que forzar CACHE_MODE_IGNORE.
	var p := _escribir("editable.gd", VALIDO)
	var r1 := _compilar(p)
	var i1 = r1["script"].new(); i1.call("_setup", {"n": 1})
	_escribir("editable.gd", VALIDO.replace("a + b", "a + b + 100"))
	var r2 := _compilar(p)
	if r2["err"] != OK:
		_chequear("8. recompilar el mismo archivo editado", false, "no compiló")
		return
	var i2 = r2["script"].new()
	var suma = i2.call("sumar", 1, 1)
	_chequear("8. recompilar el mismo archivo editado ve el cambio", int(suma) == 102, "suma=%s" % suma)

# --- infraestructura --------------------------------------------------------

## El mecanismo recomendado. `reload()` es lo único de todo el abanico que
## devuelve un Error chequeable ante un fallo de compilación.
func _compilar(ruta: String) -> Dictionary:
	if not FileAccess.file_exists(ruta):
		return {"err": ERR_FILE_NOT_FOUND, "script": null}
	var txt := FileAccess.get_file_as_string(ruta)
	var s := GDScript.new()
	s.source_code = txt
	var err := s.reload()
	return {"err": err, "script": s}

func _escribir(nombre: String, contenido: String) -> String:
	var p: String = _dir.path_join(nombre)
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(contenido)
		f.close()
	return p

func _chequear(etiqueta: String, ok: bool, detalle) -> void:
	if ok:
		_pasa += 1
	else:
		_falla += 1
	print("  [%s] %-52s %s" % ["PASA" if ok else "FALLA", etiqueta, detalle])

func _resolver_dir() -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--dir="):
			# Se ABSOLUTIZA igual que en ModPaths. Sin esto, pasar `res://algo`
			# dejaba la ruta sin resolver y la detección de "estás adentro del
			# proyecto" —que es la advertencia central de este spike— decía que no.
			var d := s.substr(6)
			if d.begins_with("res://") or d.begins_with("user://"):
				return ProjectSettings.globalize_path(d).simplify_path()
			return d.simplify_path()
	return ProjectSettings.globalize_path("user://mode_spike").simplify_path()

func _dentro_del_proyecto(d: String) -> bool:
	return d.begins_with(ProjectSettings.globalize_path("res://"))
