extends Area3D
@export var speed = 100

func _process(delta):
	$MeshInstance3D.rotate_x(-delta*30)

func _on_body_entered(body):
	body.velocity = -global_basis.z*speed
	body.angle = rotation.y
