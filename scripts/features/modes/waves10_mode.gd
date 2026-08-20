extends GameMode
## "Aguantá N oleadas": igual que el modo normal, pero con final. Es el primer
## contenido del juego que se puede GANAR.
##
## Parámetro: `oleadas` (por defecto 10).

var _meta := 10

func _setup(params: Dictionary) -> void:
	_meta = clampi(int(params.get("oleadas", 10)), 1, 999)
	api.set_objective("Sobreviví %d oleadas" % _meta)

func _on_wave_cleared(n: int) -> void:
	if n < _meta:
		# Aviso corto en las últimas tres, para que la meta se sienta cerca.
		if _meta - n <= 3:
			api.announce("Faltan %d" % (_meta - n))
		return
	api.add_stat("Oleadas completadas", _meta)
	api.win("VICTORIA", "Aguantaste las %d oleadas." % _meta)
