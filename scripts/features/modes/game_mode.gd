class_name GameMode
extends Node
## Clase base de un modo de juego. La extiende tanto lo que shippeamos nosotros
## (`res://scripts/features/modes/`) como el script que traiga un mod.
##
## Es `Node` y no `RefCounted` a propósito: así hereda la pausa del árbol (un modo
## se congela solo fuera de PLAYING, igual que todo el resto del juego), puede
## colgar hijos propios, y recibe input.
##
## TODOS los hooks son opcionales. `ModeRunner` los despacha con `has_method()`,
## que es la convención duck-typed que ya usa el resto del proyecto — un modo que
## sólo quiere contar kills implementa un método y nada más.
##
## El fin de partida NO es un hook: es una llamada, `api.win()` / `api.lose()`.
## El modo decide cuándo se ganó; el juego no adivina.

## La API queda guardada acá para que el modo la use sin recibirla en cada hook.
## Sin tipar todavía: `ModeApi` se define en la etapa 1 y tiparlo antes hace que
## esta clase no compile, lo que a su vez impide que `GameMode` se registre como
## clase global — y eso rompe en cascada a cualquiera que haga `extends GameMode`.
var api = null

# --- Ciclo de vida ---------------------------------------------------------

## Una vez, ANTES del primer frame. Es el lugar para apagar las oleadas, declarar
## el objetivo en el HUD y pedir marcadores. `params` viene del `mod.json`.
func _setup(_params: Dictionary) -> void:
	pass

## La partida arrancó de verdad.
func _start() -> void:
	pass

## Cada frame, sólo mientras se está jugando.
func _tick(_delta: float) -> void:
	pass

func _teardown() -> void:
	pass

# --- Eventos del mundo -----------------------------------------------------

func _on_enemy_died(_info: Dictionary) -> void:
	pass

## Devolver `true` significa "yo me encargo" (respawn, vidas). Devolver `false` o
## no implementarlo hace que la partida se pierda, que es lo de siempre.
func _on_player_died(_slot: int) -> bool:
	return false

func _on_wave_started(_n: int) -> void:
	pass

## Se emite cuando la oleada N se dio por terminada. Ojo: eso pasa con hasta un 20%
## de enemigos todavía vivos — las oleadas se solapan a propósito.
func _on_wave_cleared(_n: int) -> void:
	pass

## Teclas o botones propios del modo.
func _on_input(_event: InputEvent) -> void:
	pass
