class_name UILayout
extends RefCounted
## Helpers de posicionamiento compartidos por `hud.gd` y `menus.gd`. Son estáticos
## y sin estado a propósito: el HUD y los menús no se conocen entre sí, lo único
## que comparten es la forma de colocar controles.

## Único punto de verdad para posicionar un Control con anclaje de esquina.
## `Control.position`/`.size` con anclajes que no son full-rect (0,0,1,1)
## pasan por una conversión relativa al anchor que da resultados
## contraintuitivos al leer/copiar el valor entre controles (confirmado a mano:
## escribir position.y=-66 con anchor inferior y releerlo después da un
## número que corresponde a "alto_del_padre - 66", no -66). `offset_left/top/
## right/bottom` son los valores CANÓNICOS sin ambigüedad — todo el HUD y los
## menús se posicionan a través de esta función, nunca tocando position/size
## directo en un control anclado a una esquina.
static func rect(control: Control, preset: int, x: float, y: float, w: float, h: float) -> void:
	control.set_anchors_preset(preset)
	control.offset_left = x
	control.offset_top = y
	control.offset_right = x + w
	control.offset_bottom = y + h

static func label(text: String, preset: int, x: float, y: float, w: float, h: float, font_size: int = 18, color: Color = Color.WHITE, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	rect(l, preset, x, y, w, h)
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l
