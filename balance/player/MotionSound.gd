extends AudioStreamPlayer

onready var _player = get_parent()
onready var _player_body = get_parent().get_node("PlayerBody")

export var when_grounded := true
export var when_falling := false

func _process(delta):
	if !_player_body \
	or ( when_grounded and !_player_body.on_ground ) \
	or (when_falling and _player_body.on_ground) :
		if playing:
			stop()
		return

	# checking components with abs helps fix comparing signed, negative 0 with Vector3.ZERO
	var moving_in_x = abs(_player_body.velocity.x) > 0.03
	var moving_in_z = abs(_player_body.velocity.z) > 0.03
	var falling_in_y = _player_body.velocity.y < 0.03
	var moving_horizontally = moving_in_x or moving_in_z or (falling_in_y and when_falling)

	if !playing and moving_horizontally :
		play()
	elif playing and !moving_horizontally :
		stop()

