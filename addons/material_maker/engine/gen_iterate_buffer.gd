tool
extends MMGenTexture
class_name MMGenIterateBuffer

"""
Iterate buffers, that render their input in a specific resolution and apply
a loop n times on the result.
"""

var exiting : bool = false

var material : ShaderMaterial = null
var loop_material : ShaderMaterial = null
var is_paused : bool = false
var current_iteration : int = 0

var current_renderer = null

var buffer_names : Array
var iteration_param_name : String
var used_named_parameters : Array = []
var pending_textures = [[], []]

func get_buffer_size():
	var buff_size = int(pow(2, get_parameter("size")))
	buff_size = buff_size >> mm_globals_custom.global_scale
	return buff_size

func _init():
	texture.flags = Texture.FLAG_REPEAT
	material = ShaderMaterial.new()
	material.shader = Shader.new()
	loop_material = ShaderMaterial.new()
	loop_material.shader = Shader.new()
	if !parameters.has("size"):
		parameters.size = 9
	buffer_names = [
		"o%d_input_init" % get_instance_id(),
		"o%d_input_loop" % get_instance_id(),
		"o%d_loop_tex" % get_instance_id(),
		"o%d_tex" % get_instance_id()
	]
	iteration_param_name = "o%d_iteration" % get_instance_id()
	mm_deps.create_buffer(buffer_names[3], self)
	mm_deps.create_buffer(buffer_names[0], self)
	mm_deps.create_buffer(buffer_names[1], self)
	set_current_iteration(0)

func _exit_tree() -> void:
	exiting = true
	if current_renderer != null and ! (current_renderer is GDScriptFunctionState):
		current_renderer.release(self)

func get_type() -> String:
	return "iterate_buffer"

func get_type_name() -> String:
	return "Iterate Buffer"

func set_paused(v : bool) -> void:
	if v == is_paused:
		return
	is_paused = v
	if ! v:
		mm_deps.update()

func get_buffers(flags : int = BUFFERS_ALL) -> Array:
	if ( is_paused and flags == BUFFERS_RUNNING ) or ( ! is_paused and flags == BUFFERS_PAUSED ):
		return []
	return [ self ]

func get_parameter_defs() -> Array:
	return [
		{ name="size", type="size", first=4, last=13, default=4 },
		{ name="shrink", type="boolean", default=false },
		{ name="autostop", type="boolean", default=false },
		{ name="iterations", type="float", min=1, max=50, step=1, default=5 },
		{ name="filter", type="boolean", default=true },
		{ name="mipmap", type="boolean", default=true }
	]

func get_input_defs() -> Array:
	return [ { name="in", type="rgba" }, { name="loop_in", type="rgba" } ]

func get_output_defs(_show_hidden : bool = false) -> Array:
	return [ { type="rgba" }, { type="rgba" } ]

func source_changed(input_port_index : int) -> void:
	update_shader(input_port_index)

func all_sources_changed() -> void:
	update_shader(0)
	update_shader(1)

func follow_input(input_index : int) -> Array:
	if input_index == 1:
		return [ OutputPort.new(self, 0) ]
	else:
		return .follow_input(input_index)

var required_shader_updates : int = 0

func update_shader(input_port_index : int) -> void:
	if required_shader_updates == 0:
		call_deferred("do_update_shaders")
	required_shader_updates = required_shader_updates | (1 << input_port_index)

func do_update_shaders() -> void:
	if ! is_instance_valid(self) or exiting:
		return
	for i in range(2):
		if required_shader_updates & (1 << i):
			do_update_shader(i)
	required_shader_updates = 0

func do_update_shader(input_port_index : int) -> void:
	var context : MMGenContext = MMGenContext.new()
	var source = {}
	var source_output = get_source(input_port_index)
	if source_output != null:
		source = source_output.generator.get_shader_code("uv", source_output.output_index, context)
		assert(! source is GDScriptFunctionState)
	if source.empty():
		source = DEFAULT_GENERATED_SHADER
	var m : ShaderMaterial = [ material, loop_material ][input_port_index]
	var buffer_name : String = buffer_names[input_port_index]
	assert(m != null && m.shader != null)
	mm_deps.buffer_create_shader_material(buffer_name, m, mm_renderer.generate_shader(source))
	set_current_iteration(0)

func set_parameter(n : String, v) -> void:
	.set_parameter(n, v)
	set_current_iteration(0)

func on_dep_update_value(buffer_name, parameter_name, value) -> bool:
	if parameter_name != buffer_names[2] and parameter_name != iteration_param_name and (buffer_name != buffer_names[1] or ! value is Texture):
		set_current_iteration(0)
	if value != null:
		if buffer_name == buffer_names[0]:
			material.set_shader_param(parameter_name, value)
		elif buffer_name == buffer_names[1]:
			loop_material.set_shader_param(parameter_name, value)
	return false

func on_dep_buffer_invalidated(buffer_name : String):
	if !exiting and (buffer_name == buffer_names[0] or buffer_name == buffer_names[1]):
		mm_deps.buffer_invalidate(buffer_names[3])

func on_dep_update_buffer(buffer_name : String) -> bool:
	if is_paused:
		return false
	if current_renderer != null:
		return false
	if buffer_name == buffer_names[3]:
		return false
	var m : Material = material if current_iteration == 0 else loop_material
	# Calculate iteration count
	var iterations = calculate_float_parameter("iterations")
	if iterations.has("used_named_parameters"):
		used_named_parameters = iterations.used_named_parameters
	if iterations.has("value"):
		iterations = iterations.value
	else:
		iterations = 1
	if current_iteration > iterations:
		yield(get_tree(), "idle_frame")
		mm_deps.dependency_update(buffer_name, null, true)
		return false
	var check_current_iteration : int = current_iteration
	var autostop : bool = get_parameter("autostop")
	var previous_hash_value : int = 0 if ( not autostop or current_iteration == 0 or texture == null or texture.get_data() == null ) else hash(texture.get_data().get_data())
	current_renderer = mm_renderer.request(self)
	while current_renderer is GDScriptFunctionState:
		current_renderer = yield(current_renderer, "completed")
	if check_current_iteration != current_iteration:
		print("Iteration changed")
		current_renderer.release(self)
		current_renderer = null
		mm_deps.dependency_update(buffer_name, texture, true)
		return false
	var time = OS.get_ticks_msec()
	var size = get_buffer_size()
	if get_parameter("shrink"):
		size = int(size)
		size >>= current_iteration
		if size < 4:
			size = 4
	current_renderer = current_renderer.render_material(self, m, size)
	while current_renderer is GDScriptFunctionState:
		current_renderer = yield(current_renderer, "completed")
	if check_current_iteration != current_iteration:
		current_renderer.release(self)
		current_renderer = null
		mm_deps.dependency_update(buffer_name, texture, true)
		return false
	current_renderer.copy_to_texture(texture)
	texture.flags = 0
	current_renderer.release(self)
	current_renderer = null
	# Calculate iteration index
	var hash_value : int = 1 if ( not autostop or current_iteration == 0 or texture == null or texture.get_data() == null ) else hash(texture.get_data().get_data())
	if autostop and hash_value == previous_hash_value:
		set_current_iteration(iterations+1)
	else:
		set_current_iteration(current_iteration+1)
	if current_iteration <= iterations:
		mm_deps.dependency_update("o%d_loop_tex" % get_instance_id(), texture, true)
	else:
		mm_deps.dependency_update("o%d_tex" % get_instance_id(), texture, true)
	mm_deps.dependency_update(buffer_name, texture, true)
	return true

func set_current_iteration(i : int) -> void:
	if i == current_iteration:
		return
	current_iteration = i
	mm_deps.dependency_update(iteration_param_name, current_iteration, true)
	if current_iteration == 0:
		mm_deps.buffer_invalidate(buffer_names[3])

func get_globals(texture_name : String) -> Array:
	var texture_globals : String = "uniform sampler2D %s;\nuniform float o%d_tex_size = %d.0;\nuniform float o%d_iteration = 0.0;\n" % [ texture_name, get_instance_id() 	, get_buffer_size(), get_instance_id() ]
	return [ texture_globals ]

func _get_shader_code(uv : String, output_index : int, context : MMGenContext) -> Dictionary:
	var shader_code = _get_shader_code_lod(uv, output_index, context, -1.0, "_tex" if output_index == 0 else "_loop_tex")
	match output_index:
		1:
			shader_code.global = [ "uniform int o%d_iteration = 0;" % get_instance_id() ]
	return shader_code

func get_output_attributes(output_index : int) -> Dictionary:
	var attributes : Dictionary = {}
	match output_index:
		0:
			attributes.texture = "o%d_tex" % get_instance_id()
			attributes.texture_size = "o%d_tex_size" % get_instance_id()
		1:
			attributes.texture = "o%d_loop_tex" % get_instance_id()
			attributes.texture_size = "o%d_tex_size" % get_instance_id()
			attributes.iteration = iteration_param_name
	return attributes

func _serialize(data: Dictionary) -> Dictionary:
	data.type = "iterate_buffer"
	return data
