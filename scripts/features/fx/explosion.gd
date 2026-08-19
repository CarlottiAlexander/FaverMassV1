extends Node3D
## Explosión de "La Maleducada" (Rocket Launcher).
##
## El área de DAÑO es más grande que la animación (hoy el doble). Fue un pedido
## explícito: con los dos radios iguales, la caída lineal del daño hacía que un
## enemigo envuelto en las llamas sobreviviera casi intacto y pareciera que la
## explosión no llegaba hasta donde se veía. Ver GameData.ROCKET_EXPLOSION_RADIUS.

@onready var fireball: MeshInstance3D = $Fireball
@onready var shell: MeshInstance3D = $Shell

const DURATION := 0.5

var ground_ring: MeshInstance3D
var flash: OmniLight3D

## `radius` es el área de DAÑO; `visual_radius` el tamaño de la animación. No son
## el mismo número: ver GameData.ROCKET_EXPLOSION_RADIUS.
## `dmg_centro` < 0 usa el daño del cohete, que es el caso de siempre. `objetivo`
## es "enemies" (el cohete del jugador) o "player" (un enemigo que explota al
## morir, ver el trait `explode_on_death`).
##
## Un enemigo explosivo NO le pega a los otros enemigos a propósito: una oleada de
## bichos explosivos se mataría sola en cadena y el jugador miraría.
func detonate(radius: float, visual_radius: float = -1.0, dmg_centro: float = -1.0, objetivo: String = "enemies") -> void:
	if visual_radius <= 0.0:
		visual_radius = radius

	# --- daño en área, con caída lineal desde el centro ---
	var base: float = dmg_centro
	if base < 0.0:
		base = GameData.WEAPONS["rocket"]["damage"] * GameData.ROCKET_CENTER_DAMAGE_MULT

	if objetivo == "player":
		var p := get_tree().get_first_node_in_group("player")
		if p and p.has_method("take_damage"):
			var d: float = p.global_position.distance_to(global_position)
			if d <= radius:
				p.take_damage(base * maxf(0.0, 1.0 - d / radius), global_position)
	else:
		for e in get_tree().get_nodes_in_group("enemy"):
			if not is_instance_valid(e) or not e.has_method("take_damage"):
				continue
			var dist: float = e.global_position.distance_to(global_position)
			if dist > radius:
				continue
			var falloff: float = max(0.0, 1.0 - dist / radius)
			e.take_damage(base * falloff, false, global_position)

	# --- feedback visual ---
	# IMPORTANTE: duplicar los materiales. Vienen del .tscn como sub-recursos
	# COMPARTIDOS entre todas las instancias; sin duplicar, la primera explosión
	# los desvanece a alpha 0 y todas las siguientes quedan invisibles.
	var shell_mat: StandardMaterial3D = shell.get_surface_override_material(0).duplicate()
	shell.set_surface_override_material(0, shell_mat)
	var fire_mat: StandardMaterial3D = fireball.get_surface_override_material(0).duplicate()
	fireball.set_surface_override_material(0, fire_mat)

	_build_ground_ring(visual_radius)
	_build_flash(visual_radius)

	shell.scale = Vector3.ONE * 0.05
	fireball.scale = Vector3.ONE * 0.4

	var tween := create_tween()
	tween.set_parallel(true)

	# cáscara: se abre hasta el radio VISIBLE y se apaga
	tween.tween_property(shell, "scale", Vector3.ONE * visual_radius, DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(shell_mat, "albedo_color:a", 0.0, DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# bola de fuego: golpe seco al principio y se consume
	tween.tween_property(fireball, "scale", Vector3.ONE * visual_radius * 0.42, DURATION * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(fire_mat, "albedo_color:a", 0.0, DURATION * 0.75).set_delay(DURATION * 0.2)

	# anillo en el piso: marca el área de impacto
	var ring_mat: StandardMaterial3D = ground_ring.get_surface_override_material(0)
	tween.tween_property(ground_ring, "scale", Vector3(visual_radius, 1.0, visual_radius), DURATION * 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring_mat, "albedo_color:a", 0.0, DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# fogonazo de luz
	tween.tween_property(flash, "light_energy", 0.0, DURATION * 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

	tween.chain().tween_callback(queue_free)

## Disco plano a ras del suelo que se abre hasta el radio de daño. Es lo que
## mejor comunica "hasta acá llegó" porque queda apoyado sobre el piso, no
## flotando en el aire como la esfera.
func _build_ground_ring(radius: float) -> void:
	ground_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.86
	torus.outer_radius = 1.0
	torus.rings = 32
	ground_ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.12)
	mat.emission_energy_multiplier = 4.0
	mat.albedo_color = Color(1.0, 0.62, 0.2, 0.9)
	ground_ring.set_surface_override_material(0, mat)
	# a ras del piso, sin importar a qué altura detonó el proyectil
	ground_ring.position = Vector3(0.0, -global_position.y + 0.06, 0.0)
	ground_ring.scale = Vector3(0.05, 1.0, 0.05)
	add_child(ground_ring)

func _build_flash(radius: float) -> void:
	flash = OmniLight3D.new()
	flash.light_color = Color(1.0, 0.6, 0.25)
	flash.light_energy = 12.0
	flash.omni_range = radius * 2.5
	flash.shadow_enabled = false
	add_child(flash)
