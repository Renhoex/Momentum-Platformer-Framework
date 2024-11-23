extends CharacterBody3D

const SPEED = 25.0
const JUMP_VELOCITY = 12.5

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")*3.0
var gravity_vector = ProjectSettings.get_setting("physics/3d/default_gravity_vector")

var angle = 0.0
var stick = true

var ground_length = 1.0
var airLength = 0.5
var margin = 0.1

@onready var casters = [$Pivot/FrontCheck,$Pivot/BackCheck,$Pivot/BackCheck2]

var ground_timer = 0.0

var speed_margin = 10.0

@onready var animation_tree = $AnimationTree

@onready var camera = $"../Camera3D" # this is used for movement reference

func _ready():
	# pull casters in
	for i in casters:
		i.position -= i.position.normalized()*margin

func _process(delta):
	# animation related stuff
	# states
	if is_on_floor():
		# do idle animation
		if velocity.length() < 1.0:
			if animation_tree.get("parameters/States/current_state") != "Idle":
				animation_tree.set("parameters/States/transition_request","Idle")
		# if velocity greater then 1, go into the walk state
		else:
			if animation_tree.get("parameters/States/current_state") != "Move":
				animation_tree.set("parameters/States/transition_request","Move")
	else:
		if animation_tree.get("parameters/States/current_state") != "Air":
			animation_tree.set("parameters/States/transition_request","Air")
		animation_tree.set("parameters/JumpTransition/blend_amount",lerp(animation_tree.get("parameters/JumpTransition/blend_amount"),clamp(velocity.dot(gravity_vector),0.0,1.0),delta*15.0))
	# set speed
	animation_tree.set("parameters/MoveSpeed/scale",lerp(animation_tree.get("parameters/MoveSpeed/scale"),max(0.5,velocity.length()*0.1),delta*15.0))
	# set walking animation blend
	animation_tree.set("parameters/Speed/blend_amount",lerp(animation_tree.get("parameters/Speed/blend_amount"),clamp(-2.0+velocity.length()*0.1,0.0,1.0),delta))


func _physics_process(delta):
	# Add the gravity.
	velocity += gravity * delta * Vector3.DOWN

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	# calculate the forward direction based on input and direction from the floor and the camera
	var calcForward = camera.global_position.direction_to(global_position).slide(up_direction)
	# 
	var direction = ((calcForward.rotated(up_direction,deg_to_rad(90))*-input_dir.x)+(calcForward*-input_dir.y)).normalized()
	
	# keep a copy of the previous velocity
	var previous_velocity = velocity.dot(up_direction)
	
	# direction check (check that direction is being pressed)
	if direction:
		# if below speed or input direction is toward the camera then move the velocity toward the input direction
		if velocity.slide(up_direction).length() < SPEED or -$Pivot.global_basis.z.dot(calcForward) < -0.5:
			velocity = velocity.slide(up_direction).move_toward(-$Pivot.global_basis.z*SPEED,SPEED * delta * max(1.0,velocity.length()/10.0))+previous_velocity*up_direction
		else:
		# otherwise, keep the velocity and change it's direction using slerp
			velocity = velocity.slide(up_direction).slerp(-$Pivot.global_basis.z*velocity.slide(up_direction).length(),delta*2.0)+previous_velocity*up_direction
	else:
		velocity = velocity.slide(up_direction).move_toward(Vector3.ZERO,delta)+previous_velocity*up_direction

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept"):# and is_on_floor(): #(re enable this part to disable moon jumping)
		velocity += up_direction*JUMP_VELOCITY
	
	var wasOnFloor = is_on_floor()
	move_and_slide()
	var disconect = velocity.dot(up_direction) >= 1
	velocity = get_real_velocity()
	
	# ground casting
	for i in casters:
		i.target_position.y = -ground_length if ground_timer > 0 else -airLength
		i.force_raycast_update()
	
	# check that all floor casteres are colliding
	if $Pivot/FrontCheck.is_colliding() and $Pivot/BackCheck.is_colliding() and $Pivot/BackCheck2.is_colliding() and !disconect:
		# detect if velocity is over speed margin
		if velocity.length() >= speed_margin:
			up_direction = calculate_normal($Pivot/FrontCheck.get_collision_point(),$Pivot/BackCheck.get_collision_point(),$Pivot/BackCheck2.get_collision_point()).normalized()
		else:
			up_direction = -gravity_vector
		
		# realign with floor
		global_transform = align_with_y(global_transform, up_direction)
		# remove any vertical velocity
		velocity = velocity.slide(up_direction)
		
		# snap to floor (prevents air hovering)
		if is_on_floor() or stick:
			stick = true
			apply_floor_snap()
	# if the raycasts fail but we're still on the floor then use
	# godots built in ground detection
	elif is_on_floor() and !disconect:
		if !wasOnFloor:
			up_direction = get_floor_normal()
		stick = true # enable stick for our floor snapping logic
		apply_floor_snap()
		# remove vertical velocity
		velocity = velocity.slide(up_direction)
	# in the air
	else:
		# reset up direction and align ourselves to our up direction
		up_direction = Vector3.UP
		global_transform = align_with_y(global_transform, up_direction)
		stick = false
	
	# camera settings (look at and follow, feel free to implament your own camera logic here)
	camera.look_at(global_position)
	camera.global_position = camera.global_position.lerp(global_position+Vector3.UP*2,delta*(camera.global_position.distance_to(global_position)-8.0)/4.0)
	
	# calculate the looking angle (if direction has any influence)
	if direction:
		angle = -direction.signed_angle_to(-global_basis.z,global_transform.basis.y)
	# rotate the model to look at the angle
	$Pivot.rotation.y = angle
	
	# ground check related (buffer time for landing)
	if is_on_floor():
		ground_timer = 1.0
	else:
		ground_timer = move_toward(ground_timer,0.0,4.0*delta)

func align_with_y(xform, new_y):
	xform.basis.y = new_y
	xform.basis.x = -xform.basis.z.cross(new_y)
	xform.basis = xform.basis.orthonormalized()
	return xform

func calculate_normal(a = Vector3.ZERO, b = Vector3.ZERO, c = Vector3.ZERO):
	var u = b - a
	var v = c - a
	return u.cross(v)
