extends Node3D
## Herramienta: dispara balas REALES contra un enemigo quieto y cuenta cuántas
## registran impacto. Existe porque el bug más gordo de las hitboxes era
## justamente ese — la bala avanzaba 2.5 m por paso de física y atravesaba
## enemigos sin tocarlos.
##
## Todos los tiros apuntan a puntos que están GARANTIZADAMENTE dentro de la forma
## de colisión (centro y ±40% del radio / ±35% de la altura), así que el
## resultado correcto es 5/5 en cuerpo y 1/1 en cabeza para cada tipo y cada
## distancia. Cualquier número menor es un bug real, no un tiro mal apuntado.
##
## Correr:  Godot --headless --path . tools/hit_test.tscn

const DISTANCES := [4.0, 15.0, 40.0]
## Sale del registro y no de un array acá, para que un tipo de la comunidad se
## pruebe con la misma vara: disparos reales contra puntos garantizados adentro de
## su forma. Cualquier resultado que no sea 5/5 y 1/1 es un bug (salvo el Knight,
## inmune a headshot por diseño).
const FULL_HP := 1000000.0
const DMG := 10.0
const HS_MULT := 2.0

func _ready() -> void:
	# Sin esto el árbol arranca pausado (GameState empieza en TITLE) y la física
	# no corre: las balas no se moverían nunca. Ver §6 del CLAUDE.md.
	GameState.change_state(GameState.State.PLAYING)
	await get_tree().process_frame

	for t in GameData.enemy_types():
		var line := "%-12s" % t
		for dist in DISTANCES:
			var body_ok := 0
			var body_total := 0
			var head_ok := 0
			var head_total := 0
			for aim in ["c", "x+", "x-", "y+", "y-", "head"]:
				var r := await _shoot(t, dist, aim)
				if aim == "head":
					head_total += 1
					if r == "headshot":
						head_ok += 1
				else:
					body_total += 1
					if r != "fallo":
						body_ok += 1
			line += "  | %.0fm cuerpo %d/%d cabeza %d/%d" % [dist, body_ok, body_total, head_ok, head_total]
		# El Knight es inmune al headshot por diseño (is_headshot_immune), así que
		# 0 en la columna de cabeza es el resultado correcto para él.
		if t == "knight":
			line += "   (inmune a headshot por diseño)"
		print(line)
	get_tree().quit()

## Devuelve "fallo" | "cuerpo" | "headshot".
func _shoot(enemy_type: String, dist: float, aim: String) -> String:
	var e = load("res://scenes/enemy.tscn").instantiate()
	e.enemy_type = enemy_type
	add_child(e)
	await get_tree().process_frame
	e.global_position = Vector3(0.0, 0.0, dist)
	e.health = FULL_HP
	e.max_health = FULL_HP
	# Mover un cuerpo físico y consultar el espacio en el mismo frame NO sirve: el
	# servidor de física recién aplica la transformada en el próximo paso, así que
	# los rayos seguían viendo al enemigo en el origen. Dos pasos de física de
	# margen antes de disparar.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var target: Vector3 = e.global_position
	match aim:
		"x+": target.x += e.body_radius * 0.4
		"x-": target.x -= e.body_radius * 0.4
		"y+": target.y += e.body_height * 0.35
		"y-": target.y -= e.body_height * 0.35
		"head":
			if e.head_hit_radius > 0.0:
				target = e.to_global(e.head_center)
			else:
				# Sin esfera medida, el juego detecta el headshot por BANDA DE
				# ALTURA (Enemy.HEADSHOT_HEIGHT_FRACTION). Esta rama no existía y
				# el disparo salía al CENTRO del cuerpo: el test informaba 0/1
				# aunque el juego anduviera bien, porque le estaba apuntando al
				# torso. Apuntar adentro de la banda es lo único que prueba lo que
				# el juego de verdad hace.
				target.y += e.body_height * (Enemy.HEADSHOT_HEIGHT_FRACTION - 0.5 + 0.07)

	var from := Vector3(0.0, 0.0, -1.0)
	var dir: Vector3 = (target - from).normalized()
	var b = load("res://scenes/fx/bullet.tscn").instantiate()
	add_child(b)
	b.global_position = from + dir * 1.0
	b.setup(dir, DMG, HS_MULT, 0, null, false, from)

	# A 150 u/s, 41 m son 0.28 s ≈ 17 pasos de física. 40 da margen de sobra.
	for f in 40:
		await get_tree().physics_frame
		if not is_instance_valid(b) or not is_instance_valid(e):
			break

	var result := "fallo"
	if not is_instance_valid(e):
		# Murió: sólo puede haber sido un headshot (instakill), con 1e6 de vida.
		result = "headshot"
	else:
		var taken: float = FULL_HP - e.health
		if taken >= DMG * HS_MULT - 0.01:
			result = "headshot"
		elif taken > 0.0:
			result = "cuerpo"
		e.queue_free()
	if is_instance_valid(b):
		b.queue_free()
	# Limpieza total: matar al Blood Lord de un headshot deja 2 Dire Bats
	# flotando en el aire (los escupe al morir) y esos se comían los disparos de
	# la ronda siguiente. Cada tiro tiene que estar solo con su blanco.
	for other in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(other):
			other.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	return result
