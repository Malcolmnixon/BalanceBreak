extends AudioStreamPlayer3D


func _on_grab(what):
	if what is Object_climbable:
		play()
