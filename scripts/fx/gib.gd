extends RigidBody3D

const LIFETIME_MIN := 5.0
const LIFETIME_MAX := 8.0

var settled := false

func _ready() -> void:
	gravity_scale = 1.15
	angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(randf_range(LIFETIME_MIN, LIFETIME_MAX)).timeout.connect(
		func():
			if is_instance_valid(self):
				queue_free()
	)

func launch(impulse: Vector3) -> void:
	apply_central_impulse(impulse)

func _on_body_entered(_body: Node) -> void:
	if settled:
		return
	settled = true
	linear_velocity.y *= -0.34
	linear_velocity.x *= 0.55
	linear_velocity.z *= 0.55
	if randf() < 0.6:
		FxManager._spawn_decal(global_position)
