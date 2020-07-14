extends Node


var little_endian = preload('./little_endian.gd').new()
var lzw = preload('./gif-lzw/lzw.gd').new()
var used_proc_count: int = 4


class GraphicControlExtension:
	var extension_introducer: int = 0x21
	var graphic_control_label: int = 0xf9

	var block_size: int = 4
	var packed_fields: int = 0b00001000
	var delay_time: int = 0
	var transparent_color_index: int = 0

	func _init(_delay_time: int, use_transparency: bool = false, _transparent_color_index: int = 0):
		delay_time = _delay_time
		transparent_color_index = _transparent_color_index
		if use_transparency:
			packed_fields = 0b00001001

	func to_bytes() -> PoolByteArray:
		var little_endian = preload('./little_endian.gd').new()
		var result: PoolByteArray = PoolByteArray([])

		result.append(extension_introducer)
		result.append(graphic_control_label)

		result.append(block_size)
		result.append(packed_fields)
		result += little_endian.int_to_2bytes(delay_time)
		result.append(transparent_color_index)

		result.append(0)

		return result

class ImageDescriptor:
	var image_separator: int = 0x2c
	var image_left_position: int = 0
	var image_top_position: int = 0
	var image_width: int
	var image_height: int
	var packed_fields: int = 0b10000000

	func _init(_image_left_position: int,
			_image_top_position: int,
			_image_width: int,
			_image_height: int,
			size_of_local_color_table: int):
		image_left_position = _image_left_position
		image_top_position = _image_top_position
		image_width = _image_width
		image_height = _image_height
		packed_fields = packed_fields | (0b111 & size_of_local_color_table)

	func to_bytes() -> PoolByteArray:
		var little_endian = preload('./little_endian.gd').new()
		var result: PoolByteArray = PoolByteArray([])

		result.append(image_separator)
		result += little_endian.int_to_2bytes(image_left_position)
		result += little_endian.int_to_2bytes(image_top_position)
		result += little_endian.int_to_2bytes(image_width)
		result += little_endian.int_to_2bytes(image_height)
		result.append(packed_fields)

		return result

class LocalColorTable:
	var colors: Array = []

	func log2(value: float) -> float:
		return log(value) / log(2.0)

	func get_size() -> int:
		return int(ceil(log2(colors.size()) - 1))

	func to_bytes() -> PoolByteArray:
		var result: PoolByteArray = PoolByteArray([])

		for v in colors:
			result.append(v[0])
			result.append(v[1])
			result.append(v[2])

		if colors.size() != int(pow(2, get_size() + 1)):
			for i in range(int(pow(2, get_size() + 1)) - colors.size()):
				result += PoolByteArray([0, 0, 0])

		return result

class ApplicationExtension:
	var extension_introducer: int = 0x21
	var extension_label: int = 0xff

	var block_size: int = 11
	var application_identifier: PoolByteArray
	var appl_authentication_code: PoolByteArray

	var application_data: PoolByteArray

	func _init(_application_identifier: String,
			_appl_authentication_code: String):
		application_identifier = _application_identifier.to_ascii()
		appl_authentication_code = _appl_authentication_code.to_ascii()

	func to_bytes() -> PoolByteArray:
		var result: PoolByteArray = PoolByteArray([])

		result.append(extension_introducer)
		result.append(extension_label)
		result.append(block_size)
		result += application_identifier
		result += appl_authentication_code

		result.append(application_data.size())
		result += application_data

		result.append(0)

		return result

class ImageData:
	var lzw_minimum_code_size: int
	var image_data: PoolByteArray

	func to_bytes() -> PoolByteArray:
		var result: PoolByteArray = PoolByteArray([])
		var image_data_stream: PoolByteArray = PoolByteArray([]) + image_data

		result.append(lzw_minimum_code_size)

		var block_size_index: int = 0
		var i: int = 0
		while not image_data_stream.empty():
			if i == 0:
				result.append(0)
				block_size_index = result.size() - 1
			result.append(image_data_stream[0])
			image_data_stream.remove(0)
			result[block_size_index] += 1
			i += 1
			if i == 254:
				i = 0

		if not image_data.empty():
			result.append(0)

		return result


# File data and Header
var data: PoolByteArray = 'GIF'.to_ascii() + '89a'.to_ascii()

func _init(_width: int, _height: int):
	# Logical Screen Descriptor
	var width: int = _width
	var height: int = _height
	# not Global Color Table Flag
	# Color Resolution = 8 bits
	# Sort Flag = 0, not sorted.
	# Size of Global Color Table set to 0
	# because we'll use only Local Tables
	var packed_fields: int = 0b01110000
	var background_color_index: int = 0
	var pixel_aspect_ratio: int = 0

	data += little_endian.int_to_2bytes(width)
	data += little_endian.int_to_2bytes(height)
	data.append(packed_fields)
	data.append(background_color_index)
	data.append(pixel_aspect_ratio)

	var application_extension: ApplicationExtension = ApplicationExtension.new(
			"NETSCAPE",
			"2.0")
	application_extension.application_data = PoolByteArray([1, 0, 0])
	data += application_extension.to_bytes()

func color_table_to_indexes(colors: Array) -> PoolByteArray:
	var result: PoolByteArray = PoolByteArray([])
	for i in range(colors.size()):
		result.append(i)
	return result

func find_colors_thread(args: Dictionary) -> bool:
	# args = data: PoolByteArray, start: int, stop: int
	var result: Array = args['result']
	var result_mutex: Mutex = args['result_mutex']
	var start: int = args['start'] * 4
	var stop: int = args['stop'] * 4
	var max_colors_per_chunk: int = args['max_colors_per_chunk']
	var data: PoolByteArray = args['data']

	var i: int = start
	while i < stop:
		var r: int = data[i]
		var g: int = data[i + 1]
		var b: int = data[i + 2]
		var a: int = data[i + 3]

		result_mutex.lock()
		if result.find([r, g, b, a]) == -1:
			result.append([r, g, b, a])
		result_mutex.unlock()

		result_mutex.lock()
		if result.size() > 256:
			return false
		result_mutex.unlock()

		i += 4

	return true

# if has more than 256 colors then return [].
func find_color_table_if_has_less_than_256_colors(image: Image) -> Array:
	image.lock()
	var result: Array = []
	var result_mutex: Mutex = Mutex.new()

	var image_pixels_count: int = image.get_data().size() / 4
	var image_pixels_count_per_chunk: int = int(ceil(float(image_pixels_count) / used_proc_count))
	var max_colors_per_chunk: int = int(ceil(256.0 / used_proc_count))

	var thread_pool: Array = []
	for i in range(used_proc_count):
		var new_thread: Thread = Thread.new()
		var start: int = i * image_pixels_count_per_chunk
		var stop: int = (i + 1) * image_pixels_count_per_chunk
		if i == (used_proc_count - 1):
			stop = image_pixels_count
		thread_pool.append(new_thread)
		new_thread.start(self, 'find_colors_thread', {
			'data': image.get_data(),
			'start': start,
			'stop': stop + 1,
			'max_colors_per_chunk': max_colors_per_chunk,
			'result': result,
			'result_mutex': result_mutex})

	for v in thread_pool:
		var thread_result = (v as Thread).wait_to_finish()
		if thread_result == false:
			return []

	image.unlock()
	return result

func change_colors_to_codes_thread(args: Dictionary) -> PoolByteArray:
	var result: PoolByteArray = PoolByteArray([])
	var data: PoolByteArray = args['data']
	var start: int = args['start'] * 4
	var stop: int = args['stop'] * 4
	var color_palette: Array = args['color_palette']
	var transparency_color_index: int = args['transparency_color_index']

	var i: int = start
	while i < stop - 4:
		var r: int = data[i]
		var g: int = data[i + 1]
		var b: int = data[i + 2]
		var a: int = data[i + 3]

		var color_index: int = color_palette.find([r, g, b, a])
		if color_index != -1:
			if a == 0 and transparency_color_index != -1:
				result.append(transparency_color_index)
			else:
				result.append(color_index)
		else:
			result.append(0)
			print('change_colors_to_codes_thread: color not found! [%d, %d, %d, %d]' % [r, g, b, a])

		i += 4

	return result

func change_colors_to_codes(image: Image,
		color_palette: Array,
		transparency_color_index: int) -> PoolByteArray:
	var image_data: PoolByteArray = image.get_data()
	var image_pixels_count: int = image_data.size() / 4
	var image_pixels_count_per_chunk: int = int(ceil(float(image_pixels_count) / used_proc_count))

	var result: PoolByteArray = PoolByteArray([])

	var thread_pool: Array = []
	for i in range(used_proc_count):
		var new_thread: Thread = Thread.new()
		var start: int = i * image_pixels_count_per_chunk
		var stop: int = (i + 1) * image_pixels_count_per_chunk
		if i == (used_proc_count - 1):
			stop = image_pixels_count
		thread_pool.append(new_thread)
		new_thread.start(self, 'change_colors_to_codes_thread', {
			'data': image_data,
			'start': start,
			'stop': stop + 1,
			'color_palette': color_palette,
			'transparency_color_index': transparency_color_index})

	for v in thread_pool:
		var thread_result: PoolByteArray = (v as Thread).wait_to_finish()
		result += thread_result

	return result

func find_transparency_color_index(color_table: Array) -> int:
	for i in range(color_table.size()):
		if color_table[i][3] == 0:
			return i
	return -1

func write_frame(image: Image,
		frame_delay: float,
		quantizator) -> void:
	var delay_time: int = int(ceil(frame_delay / 0.01))

	var found_color_table: Array = find_color_table_if_has_less_than_256_colors(
			image)

	var image_converted_to_codes: PoolByteArray
	var transparency_color_index: int = -1
	var color_table: Array
	if found_color_table != []: # we don't need to quantize the image.
		# exporter images always try to include transparency because I'm lazy.
		transparency_color_index = find_transparency_color_index(found_color_table)
		if transparency_color_index == -1 and found_color_table.size() != 256:
			found_color_table.append([0, 0, 0, 0])
			transparency_color_index = found_color_table.size() - 1
		image_converted_to_codes = change_colors_to_codes(
				image, found_color_table, transparency_color_index)
		color_table = found_color_table
	else: # we have to quantize the image.
		var quantization_result: Array = quantizator.quantize_and_convert_to_codes(image)
		image_converted_to_codes = quantization_result[0]
		color_table = quantization_result[1]
		transparency_color_index = find_transparency_color_index(color_table)

	var color_table_indexes = color_table_to_indexes(color_table)
	var compressed_image_result: Array = lzw.compress_lzw(
		image_converted_to_codes, color_table_indexes)
	var compressed_image_data: PoolByteArray = compressed_image_result[0]
	var lzw_min_code_size: int = compressed_image_result[1]

	var table_image_data_block: ImageData = ImageData.new()
	table_image_data_block.lzw_minimum_code_size = lzw_min_code_size
	table_image_data_block.image_data = compressed_image_data

	var local_color_table: LocalColorTable = LocalColorTable.new()
	local_color_table.colors = color_table

	var image_descriptor: ImageDescriptor = ImageDescriptor.new(
			0, 0, image.get_width(), image.get_height(), local_color_table.get_size())

	var graphic_control_extension: GraphicControlExtension
	if transparency_color_index != -1:
		graphic_control_extension = GraphicControlExtension.new(
				delay_time, true, transparency_color_index)
	else:
		graphic_control_extension = GraphicControlExtension.new(
				delay_time, false, 0)

	data += graphic_control_extension.to_bytes()
	data += image_descriptor.to_bytes()
	data += local_color_table.to_bytes()
	data += table_image_data_block.to_bytes()

func export_file_data() -> PoolByteArray:
	return data + PoolByteArray([0x3b])
