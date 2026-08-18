extends Node
## Autoload. Centraliza spawn de feedback efímero (gibs, decals, números de daño,
## explosiones) y sus topes globales (sección 8).

const MAX_GIBS := 340
const MAX_DECALS := 80

var gib_scene: PackedScene = preload("res://scenes/fx/gib.tscn")
var decal_scene: PackedScene = preload("res://scenes/fx/blood_decal.tscn")
var damage_number_scene: PackedScene = preload("res://scenes/fx/damage_number.tscn")
var explosion_scene: PackedScene = preload("res://scenes/fx/explosion.tscn")

var gibs: Array = []
var decals: Array = []

func _container() -> Node:
	return get_tree().current_scene

func spawn_gibs(pos: Vector3, from_dir: Vector3, body_radius: float, is_alpha: bool, is_headshot: bool) -> void:
	var count := int(9 + body_radius * 9)
	if is_alpha:
		count = int(count * 1.6)
	if is_headshot:
		count += 4
	for i in count:
		_spawn_one_gib(pos, from_dir, is_headshot and i < 4)
	var drops := randi_range(14, 33)
	if is_headshot:
		drops += 6
	if is_alpha:
		drops += 6
	for i in drops:
		_spawn_decal(pos + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6)))

func _spawn_one_gib(pos: Vector3, from_dir: Vector3, headshot_biased: bool) -> void:
	if not _container():
		return
	var g := gib_scene.instantiate()
	_container().add_child(g)
	var spawn_pos := pos
	if headshot_biased:
		spawn_pos.y += 0.5
	g.global_position = spawn_pos
	var outward := (-from_dir).normalized() if from_dir.length() > 0.01 else Vector3.UP
	var jitter := Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.4), randf_range(-1.0, 1.0))
	var impulse := (outward * randf_range(2.0, 5.0) + jitter * 2.5)
	g.call_deferred("launch", impulse)
	gibs.append(g)
	if gibs.size() > MAX_GIBS:
		var old = gibs.pop_front()
		if is_instance_valid(old):
			old.queue_free()

func _spawn_decal(pos: Vector3) -> void:
	if not _container():
		return
	var d := decal_scene.instantiate()
	_container().add_child(d)
	d.global_position = Vector3(pos.x, 0.02, pos.z)
	d.call_deferred("start_fade", randf_range(9.0, 16.0))
	decals.append(d)
	if decals.size() > MAX_DECALS:
		var old = decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()

func spawn_damage_number(pos: Vector3, amount: float, is_headshot: bool) -> void:
	if not _container():
		return
	var n := damage_number_scene.instantiate()
	_container().add_child(n)
	n.global_position = pos
	n.call_deferred("setup", amount, is_headshot)

## `radius` es el de DAÑO; `visual_radius` el de la animación. Son distintos a
## propósito — ver GameData.ROCKET_EXPLOSION_RADIUS.
func spawn_explosion(pos: Vector3, radius: float, visual_radius: float = -1.0) -> void:
	if not _container():
		return
	var e := explosion_scene.instantiate()
	_container().add_child(e)
	e.global_position = pos
	e.call_deferred("detonate", radius, visual_radius if visual_radius > 0.0 else radius)
