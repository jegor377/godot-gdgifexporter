class_name GIFImporter
extends GIFDataTypes


class Frame:
	var image: Image
	var delay: float
	var disposal_method: int
	var x: int
	var y: int
	var w: int
	var h: int

enum Error {
	OK,
	FILE_IS_EMPTY,
	FILE_SMALLER_MINIMUM,
	NOT_A_SUPPORTED_FILE
}


const R: int = 0
const G: int = 1
const B: int = 2

var little_endian = preload("res://gdgifexporter/little_endian.gd").new()
var lzw = preload("res://gdgifexporter/gif-lzw/lzw.gd").new()

var header: PoolByteArray
var logical_screen_descriptor: PoolByteArray

var import_file: File
var frames: Array
var background_color_index: int
var pixel_aspect_ratio: int
var global_color_table: Array

var last_graphic_control_extension: GraphicControlExtension = null


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

func load_data_subblocks() -> PoolByteArray:
	var result: PoolByteArray = PoolByteArray([])

	while true:
		var block_size: int = import_file.get_8()
		if block_size == 0:
			break
		result.append_array(import_file.get_buffer(block_size))

	return result

func load_encrypted_image_data(color_table: Array) -> PoolByteArray:
	var lzw_min_code_size: int = import_file.get_8()
	var image_data: PoolByteArray = PoolByteArray([])
	
	# loading data sub-blocks
	image_data = load_data_subblocks()
	
	var decompressed_image_data: PoolByteArray = lzw.decompress_lzw(
			image_data,
			lzw_min_code_size,
			PoolByteArray(color_table_to_index_table(color_table)))
	
	return decompressed_image_data

func decrypt_image_data(encrypted_img_data: PoolByteArray, color_table: Array, transparency_index: int) -> PoolByteArray:
	var result: PoolByteArray = PoolByteArray([])
	result.resize(encrypted_img_data.size() * 4) # because RGBA format
	
	for i in range(encrypted_img_data.size()):
		var j: int = 4 * i
		var color_index: int = encrypted_img_data[i]
		result[j] = color_table[color_index][R]
		result[j + 1] = color_table[color_index][G]
		result[j + 2] = color_table[color_index][B]
		# alpha channel
		if color_index == transparency_index:
			result[j + 3] = 0
		else:
			result[j + 3] = 255
	
	return result

func load_interlaced_image_data(color_table: Array, w: int, h: int, transparency_index: int = -1) -> Image:
	var image_data: PoolByteArray = load_encrypted_image_data(color_table)
	
	printerr('Interlaced images are not implemented yet.')
	
	return null

func load_progressive_image_data(color_table: Array, w: int, h: int, transparency_index: int = -1) -> Image:
	var result_image: Image = Image.new()
	
	var encrypted_image_data: PoolByteArray = load_encrypted_image_data(
			color_table)
	
	var decrypted_image_data: PoolByteArray = decrypt_image_data(
			encrypted_image_data, color_table, transparency_index)
	
	result_image.create_from_data(w, h, 
			false, Image.FORMAT_RGBA8,
			decrypted_image_data)
	
	return result_image

func handle_image_descriptor() -> int:
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
		image = load_interlaced_image_data(color_table, w, h)
	else:
		image = load_progressive_image_data(color_table, w, h)
	
	var new_frame = Frame.new()
	new_frame.image = image
	if last_graphic_control_extension != null:
		new_frame.delay = last_graphic_control_extension.delay_time
		new_frame.disposal_method = last_graphic_control_extension.disposal_method
		last_graphic_control_extension = null
	else:
		# -1 because Image Descriptor didn't have Graphics Control Extension
		# before it with frame delay value, so we want to set it as -1 because we
		# want to tell end user that this frame has no delay.
		new_frame.delay = -1
		new_frame.disposal_method = DisposalMethod.RESTORE_TO_BACKGROUND
	new_frame.x = x
	new_frame.y = y
	new_frame.w = w
	new_frame.h = h
	
	frames.append(new_frame)
	
	return Error.OK

func handle_graphics_control_extension() -> int:
	var block_size: int = import_file.get_8()
	var packed_fields: int = import_file.get_8()
	var delay_time: int = little_endian.word_to_int(import_file.get_buffer(2))
	var transparent_color_index: int = import_file.get_8()
	var block_terminator: int = import_file.get_8()
	
	var graphic_control_extension: GraphicControlExtension = GraphicControlExtension.new()
	graphic_control_extension.set_delay_time_from_export(delay_time)
	graphic_control_extension.set_packed_fields(packed_fields)
	graphic_control_extension.transparent_color_index = transparent_color_index
	
	last_graphic_control_extension = graphic_control_extension
	
	return Error.OK

func handle_application_extension() -> int:
	return Error.OK

func handle_comment_extension() -> int:
	return Error.OK

func handle_plain_text_extension() -> int:
	return Error.OK

func handle_extension_introducer() -> int:
	var extension_label: int = import_file.get_8()
	match extension_label:
		0xF9: # Graphics Control Extension
			return handle_graphics_control_extension()
		0xFF: # Application Extension
			return handle_application_extension()
		0xFE: # Comment Extension
			return handle_comment_extension()
		0x01: # Plain Text Extension
			return handle_plain_text_extension()
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
				error = handle_image_descriptor()
			0x21: # Extension Introducer
				error = handle_extension_introducer()
			0x3B: # Trailer
				break
		if error != Error.OK:
			return error
	
	return Error.OK
