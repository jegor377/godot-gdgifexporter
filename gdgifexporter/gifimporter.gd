class_name GIFImporter
extends GIFDataTypes


class Frame:
	var image: Image
	var delay: float
	var x: int
	var y: int
	var w: int
	var h: int

enum Error {
	OK,
	FILE_IS_EMPTY,
	FILE_SMALLER_MINIMUM,
	NOT_A_SUPPORTED_FILE,
	CANNOT_HANDLE_INTERLACED_FRAMES
}


var little_endian = preload("res://gdgifexporter/little_endian.gd").new()
var lzw = preload("res://gdgifexporter/gif-lzw/lzw.gd")

var header: PoolByteArray
var logical_screen_descriptor: PoolByteArray

var import_file: File
var frames: Array
var background_color_index: int
var pixel_aspect_ratio: int
var global_color_table: Array


func _init(file: File):
	import_file = file


func load_header() -> void:
	header = import_file.get_buffer(6)

func get_gif_ver() -> String:
	return header.get_string_from_ascii()

func load_logical_screen_descriptor() -> void:
	logical_screen_descriptor = import_file.get_buffer(7)

func get_logical_screen_width() -> int:
	return little_endian.word_to_int(logical_screen_descriptor.subarray(0, 1))

func get_logical_screen_height() -> int:
	return little_endian.word_to_int(logical_screen_descriptor.subarray(2, 3))

func get_packed_fields() -> int:
	return logical_screen_descriptor[4]

func has_global_color_table() -> bool:
	return (get_packed_fields() >> 7) == 1

func get_color_resolution() -> int:
	return ((get_packed_fields() >> 4) & 0b0111) + 1

func get_size_of_global_color_table() -> int:
	return int(pow(2, (get_packed_fields() & 0b111) + 1))

func get_background_color_index() -> int:
	return logical_screen_descriptor[5]

func get_pixel_aspect_ratio() -> int:
	return logical_screen_descriptor[6]

func load_global_color_table() -> void:
	global_color_table = []
	for i in range(get_size_of_global_color_table()):
		global_color_table.append([
			import_file.get_8(),
			import_file.get_8(),
			import_file.get_8()
		])

func load_local_color_table(size: int) -> Array:
	var result: Array = []
	for i in range(size):
		result.append([
			import_file.get_8(),
			import_file.get_8(),
			import_file.get_8()
		])
	return result

func color_table_to_index_table(color_table: Array) -> Array:
	var result: Array = []
	for i in range(color_table.size()):
		result.append(i)
	return result

func add_alpha_channel(original_image_data: PoolByteArray) -> PoolByteArray:
	var result: PoolByteArray = PoolByteArray([])
	
	for i in range(original_image_data.size()):
		result.append(original_image_data[i])
		if i % 3 == 0:
			result.append(255) # all have alpha equal to 255
	
	return result

func load_interlaced_frame_image(color_table: Array, w: int, h: int) -> Image:
	return Image.new()

func load_frame_image(color_table: Array, w: int, h: int) -> Image:
	var lzw_min_code_size: int = import_file.get_8()
	var image_data: PoolByteArray = PoolByteArray([])
	var result_image: Image = Image.new()
	
	# loading data sub-blocks
	while true:
		var block_size: int = import_file.get_8()
		if block_size == 0:
			break
		for i in range(block_size):
			image_data.append(import_file.get_8())
	
	var decompressed_image_data: PoolByteArray = lzw.decompress_lzw(
			image_data,
			lzw_min_code_size,
			PoolByteArray(color_table_to_index_table(color_table)))
	
	result_image.create_from_data(w, h, 
			false, Image.FORMAT_RGBA8,
			add_alpha_channel(decompressed_image_data))
	
	return result_image

func handle_naked_image_descriptor() -> int:
	var x: int = little_endian.word_to_int(import_file.get_buffer(2))
	var y: int = little_endian.word_to_int(import_file.get_buffer(2))
	var w: int = little_endian.word_to_int(import_file.get_buffer(2))
	var h: int = little_endian.word_to_int(import_file.get_buffer(2))
	var packed_field: int = import_file.get_8()
	
	var has_local_color_table: bool = (packed_field >> 7) == 1
	var is_interlace_flag_on: bool = ((packed_field >> 6) & 0b01) == 1
	# Skipping sort flag
	# Skipping reserved bits
	var size_of_local_color_table: int = pow(2, (packed_field & 0b111) + 1)
	var local_color_table: Array = []
	var color_table: Array
	var image: Image
	
	if has_local_color_table:
		local_color_table = load_local_color_table(size_of_local_color_table)
		color_table = local_color_table
	else:
		color_table = global_color_table
	
	if is_interlace_flag_on:
		#load_interlaced_frame_image(color_table)
		return Error.CANNOT_HANDLE_INTERLACED_FRAMES
	else:
		image = load_frame_image(color_table, w, h)
	
	var new_frame = Frame.new()
	new_frame.image = image
	# because Image Descriptor didn't have Graphics Extension before it
	# with frame delay value, we want to set it as -1 because we want to tell
	# end user that this frame has no delay.
	new_frame.delay = -1
	new_frame.x = x
	new_frame.y = y
	new_frame.w = w
	new_frame.h = h
	
	return Error.OK

func handle_graphics_extension() -> int:
	return Error.OK

func handle_application_extension() -> int:
	return Error.OK

func handle_comment_extension() -> int:
	return Error.OK

func handle_extension_introducer() -> int:
	var extension_label: int = import_file.get_8()
	match extension_label:
		0xF9: # Graphics Extension
			return handle_graphics_extension()
		0xFF: # Application Extension
			return handle_application_extension()
		0xFE: # Comment Extension
			return handle_comment_extension()
	return Error.OK

func import() -> int:
	# if file is empty return
	if import_file.get_len() == 0:
		return Error.FILE_IS_EMPTY
	# if file has smaller size than header and logical screen descriptor
	# then return error
	if import_file.get_len() < 13:
		return Error.FILE_SMALLER_MINIMUM
	
	# HEADER
	load_header()
	var gif_ver: String = get_gif_ver()
	if gif_ver != 'GIF87a' and gif_ver != 'GIF89a':
		printerr('Not a supported gif file.')
		return Error.NOT_A_SUPPORTED_FILE
	
	# LOGICAL SCREEN DESCRIPTOR
	# I skip the Sort Flag
	load_logical_screen_descriptor()
	if has_global_color_table():
		load_global_color_table()
	
	# LOADING FRAMES LOOP
	while not import_file.eof_reached():
		var block_intrudoction: int = import_file.get_8()
		var error: int
		match block_intrudoction:
			0x2C: # Image Descriptor
				error = handle_naked_image_descriptor()
			0x21: # Extension Introducer
				error = handle_extension_introducer()
			0x3B: # Trailer
				break
		if error != Error.OK:
			return error
	
	return Error.OK
