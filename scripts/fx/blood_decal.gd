extends MeshInstance3D

func start_fade(duration: float) -> void:
	var mat := get_surface_override_material(0)
	scale = Vector3.ONE * randf_range(0.6, 1.3)
	rotate_y(randf_range(0.0, TAU))
	var tween := create_tween()
	tween.tween_interval(duration * 0.6)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration * 0.4)
	tween.tween_callback(queue_free)
