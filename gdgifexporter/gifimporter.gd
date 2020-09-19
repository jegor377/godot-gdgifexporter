class_name GIFImporter
extends GIFDataTypes


class Frame:
	var image: Image
	var delay: float
	var x: int
	var y: int

enum Error {
	OK,
	FILE_IS_EMPTY,
	FILE_SMALLER_MINIMUM,
	NOT_A_SUPPORTED_FILE
}


var little_endian = preload("res://gdgifexporter/little_endian.gd").new()

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

func handle_naked_image_descriptor() -> void:
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

func handle_extension_introducer() -> void:
	pass

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
		match block_intrudoction:
			0x2C: # Image Descriptor
				handle_naked_image_descriptor()
			0x21: # Extension Introducer
				handle_extension_introducer()
			0x3B: # Trailer
				break
	
	return Error.OK
