extends SceneTree


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		push_error("usage: godot --headless --path . -s tools/sprite_baker/inspect_model.gd -- <model-path>")
		quit(2)
		return
	var packed := load(arguments[0]) as PackedScene
	if packed == null:
		push_error("could not load model: %s" % arguments[0])
		quit(2)
		return
	var model := packed.instantiate()
	root.add_child(model)
	for player in _animation_players(model):
		print("AnimationPlayer: %s" % player.name)
		for animation_name in player.get_animation_list():
			var animation := player.get_animation(animation_name)
			print("  %s length=%.3f loop=%d" % [animation_name, animation.length, animation.loop_mode])
	_print_materials(model)
	quit(0)


func _animation_players(node: Node) -> Array[AnimationPlayer]:
	var players: Array[AnimationPlayer] = []
	if node is AnimationPlayer:
		players.append(node)
	for child in node.get_children():
		players.append_array(_animation_players(child))
	return players


func _print_materials(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface_index in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(surface_index)
			if material is BaseMaterial3D:
				print("Material: node=%s surface=%d name=%s color=%s texture=%s" % [node.name, surface_index, material.resource_name, material.albedo_color, material.albedo_texture.resource_path if material.albedo_texture != null else "none"])
	for child in node.get_children():
		_print_materials(child)
