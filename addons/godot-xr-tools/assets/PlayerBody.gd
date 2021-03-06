tool
class_name PlayerBody
extends Node

##
## Player Physics Body Script
##
## @desc:
##     This script works with the PlayerBody asset to provide the player with
##     a PlayerBody. This PlayerBody is a capsule tracking the players hear
##     via the ARVRCamera node.
##
##     The PlayerBody can detect when the player is in the air, on the ground, 
##     or on a steep slope.
##
##     The PlayerBody works with movement providers to allow the player to move
##     around the environment.
##
##     At the end of each physics process step the ARVROrigin is updated to 
##     track any movement to the PlayerBody.
##

## PlayerBody enabled flag
export var enabled := true setget set_enabled, get_enabled

## Player radius
export var player_radius := 0.4

## Eyes forward offset from center of body in player_radius units
export (float, 0.0, 1.0) var eye_forward_offset := 0.66

## Ground drag factor
export var drag_factor := 0.1

## Maximum slope that can be walked up
export (float, 0.0, 85.0) var max_slope := 45.0

## Force of gravity on the player
export var gravity := -9.8

## Lets the player push rigid bodies
export var push_rigid_bodies := true

## Path to the ARVROrigin node
export (NodePath) var origin = null

## Path to the ARVRCamera node
export (NodePath) var camera = null

## ARVROrigin node
var origin_node: ARVROrigin = null

## ARVRCamera node
var camera_node: ARVRCamera = null

## Player KinematicBody node
onready var kinematic_node: KinematicBody = $KinematicBody

## Player Velocity - modifiable by MovementProvider nodes
var velocity := Vector3.ZERO

## Player On Ground flag - used by MovementProvider nodes
var on_ground := true

## Ground 'up' vector - used by MovementProvider nodes
var ground_vector := Vector3.UP

## Ground slope angle - used by MovementProvider nodes
var ground_angle := 0.0

## Ground control velocity - modified by MovementProvider nodes
var ground_control_velocity := Vector2.ZERO

# Movement providers
var _movement_providers := Array()

# Collision node
onready var _collision_node: CollisionShape = $KinematicBody/CollisionShape

# Horizontal vector (multiply by this to get only the horizontal components
const horizontal := Vector3(1.0, 0.0, 1.0)

# Class to sort movement providers by order
class SortProviderByOrder:
	static func sort_by_order(a, b) -> bool:
		return true if a.order < b.order else false

# Called when the node enters the scene tree for the first time.
func _ready():
	# Get the origin and camera nodes
	origin_node = get_node(origin) if origin else get_parent()
	camera_node = get_node(camera) if camera else origin_node.get_node("ARVRCamera")

	# Get the movement providers ordered by increasing order
	_movement_providers = get_tree().get_nodes_in_group("movement_providers")
	_movement_providers.sort_custom(SortProviderByOrder, "sort_by_order")

func set_enabled(new_value):
	enabled = new_value

	# Update collision_shape
	if _collision_node:
		_collision_node.disabled = !enabled

	# Update physics processing
	if enabled:
		set_physics_process(true)

func get_enabled():
	return enabled

func _physics_process(delta):
	# Do not run physics if in the editor
	if Engine.editor_hint:
		return

	# If disabled then turn of physics processing and bail out
	if !enabled:
		set_physics_process(false)
		return

	# Update the kinematic body to be under the camera
	_update_body_under_camera()

	# Update the ground information
	_update_ground_information()

	# Get the player body location before movement occurs
	var position_before_movement := kinematic_node.global_transform.origin

	# Run the movement providers in order. The providers can:
	# - Move the kinematic node around (to move the player)
	# - Rotate the ARVROrigin around the camera (to rotate the player)
	# - Read and modify the player velocity
	# - Read and modify the ground-control velocity
	# - Perform exclusive updating of the player (bypassing other movement providers)
	ground_control_velocity = Vector2.ZERO
	var exclusive := false
	for p in _movement_providers:
		if p.enabled:
			if p.physics_movement(delta, self):
				exclusive = true
				break

	# If no controller has performed an exclusive-update then apply gravity and
	# perform any ground-control
	if !exclusive:
		velocity.y += gravity * delta
		_apply_velocity_and_control()

	# Apply the player-body movement to the ARVR origin
	var movement := kinematic_node.global_transform.origin - position_before_movement
	origin_node.global_transform.origin += movement

# Perform a move_and_slide on the kinematic node
func move_and_slide(var velocity: Vector3) -> Vector3:
	return kinematic_node.move_and_slide(velocity, Vector3.UP, false, 4, 0.785398, push_rigid_bodies)
	
# This method updates the body to match the player position
func _update_body_under_camera():
	# Calculate the player height based on the origin and camera position
	var player_height := camera_node.transform.origin.y + player_radius
	if player_height < player_radius:
		player_height = player_radius

	# Adjust the collision shape to match the player geometry
	_collision_node.shape.radius = player_radius
	_collision_node.shape.height = player_height - (player_radius * 2.0)
	_collision_node.transform.origin.y = (player_height / 2.0)

	# Center the kinematic body on the ground under the camera
	var curr_transform := kinematic_node.global_transform
	var camera_transform := camera_node.global_transform
	curr_transform.origin = camera_transform.origin
	curr_transform.origin.y = origin_node.global_transform.origin.y

	# The camera/eyes are towards the front of the body, so move the body back slightly
	var forward_dir := -camera_transform.basis.z * horizontal
	if forward_dir.length() > 0.01:
		curr_transform.origin -= forward_dir.normalized() * eye_forward_offset * player_radius

	# Set the body position
	kinematic_node.global_transform = curr_transform

# This method updates the information about the ground under the players feet
func _update_ground_information():
	# Update the ground information
	var ground_collision := kinematic_node.move_and_collide(Vector3(0.0, -0.05, 0.0), true, true, true)
	if !ground_collision:
		on_ground = false
		ground_vector = Vector3.UP
		ground_angle = 0.0
	else:
		on_ground = true
		ground_vector = ground_collision.normal
		ground_angle = rad2deg(ground_collision.get_angle())

		# Detect if we're sliding on a wall
		# TODO: consider reworking this magic angle
		if ground_angle > 85:
			on_ground = false

# This method applies the player velocity and ground-control velocity to the physical body
func _apply_velocity_and_control():
	# Split the velocity into horizontal and vertical components
	var horizontal_velocity := velocity * horizontal
	var vertical_velocity := velocity * Vector3.UP

	# If the player is on the ground then give them control
	if on_ground:
		# Apply the ground drag
		horizontal_velocity *= 1.0 - drag_factor

		# If ground control is being supplied then update the horizontal velocity
		if abs(ground_control_velocity.x) > 0.1 or abs(ground_control_velocity.y) > 0.1:
			var camera_transform := camera_node.global_transform
			var dir_forward := (camera_transform.basis.z * horizontal).normalized()
			var dir_right := (camera_transform.basis.x * horizontal).normalized()
			horizontal_velocity = (dir_forward * -ground_control_velocity.y + dir_right * ground_control_velocity.x) * ARVRServer.world_scale

		# Prevent the player from moving up steep slopes
		if ground_angle > max_slope:
			# Get a vector in the down-hill direction
			var down_direction := ground_vector * horizontal
			var vdot = down_direction.dot(horizontal_velocity)
			if vdot < 0:
				horizontal_velocity -= down_direction * vdot

	# Apply the horizontal and vertical velocities to the player body
	horizontal_velocity = move_and_slide(horizontal_velocity)
	vertical_velocity = move_and_slide(vertical_velocity)

	# Update the players velocity
	velocity.x = horizontal_velocity.x
	velocity.y = vertical_velocity.y
	velocity.z = horizontal_velocity.z

# This method verifies the PlayerBody has a valid configuration. Specifically it
# checks the following:
# - ARVROrigin can be identified
# - ARVRCamera can be identified
# - Player radius is valid
# - Maximum slope is valid
func _get_configuration_warning():
	# Check the origin node
	var test_origin_node = get_node_or_null(origin) if origin else get_parent()
	if !test_origin_node or !test_origin_node is ARVROrigin:
		return "Unable to find ARVR Origin node"

	# Check the camera node
	var test_camera_node = get_node_or_null(camera) if camera else test_origin_node.get_node("ARVRCamera")
	if !test_camera_node or !test_camera_node is ARVRCamera:
		return "Unable to find ARVR Camera node"

	# Verify the player radius is valid
	if player_radius <= 0:
		return "Player radius must be configured"

	# Verify eye forwards range
	if eye_forward_offset < 0 || eye_forward_offset > 1:
		return "Player eye forward offset invalid [0..1]"

	# Verify the player radius is valid
	if max_slope <= 0 || max_slope >= 85:
		return "Invalid maximum slope (0..85)"

	# Verify eye-forward does not allow near-clip-plane look through
	var eyes_to_collider = (1.0 - eye_forward_offset) * player_radius
	if eyes_to_collider < test_camera_node.near:
		return "Eyes too far forwards. Move eyes back or decrease camera near clipping plane"

	# Passed basic validation
	return ""
