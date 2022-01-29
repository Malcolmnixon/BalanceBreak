extends AudioStreamPlayer

onready var _player = get_parent()
onready var _player_body = get_parent().get_node("PlayerBody")

export var when_grounded := true
export var when_falling := false
export var delay_seconds := 1

var _timer : Timer = null

func _ready():
	if $Timer:
		_timer = $Timer
	else:
		_timer = Timer.new()
		add_child(_timer)
	_timer.connect("timeout", self, "play")

func _process(_delta):
	if !_player_body \
	or ( when_grounded and !_player_body.on_ground ) \
	or (when_falling and _player_body.on_ground) :
		if playing:
			_timer.stop()
			stop()
		return

	var x = _player_body.velocity.x
	var y = _player_body.velocity.y
	var z = _player_body.velocity.z

	# checking components with abs helps fix comparing signed, negative 0 with Vector3.ZERO
	var moving_in_x = abs(_player_body.velocity.x) > 1
	var moving_in_z = abs(_player_body.velocity.z) > 1
	var falling_in_y = _player_body.velocity.y < -5.0
	var moving_horizontally = moving_in_x or moving_in_z or (falling_in_y and when_falling)

	if !playing and moving_horizontally and _timer.is_stopped():
		_timer.start(delay_seconds)
	elif playing and !moving_horizontally :
		_timer.stop()
		stop()

