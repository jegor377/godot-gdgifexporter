extends Node


class PixelColor:
	var r: int
	var g: int
	var b: int
	var a: int

	func _init(_r: int, _g: int, _b: int, _a: int):
		r = _r
		g = _g
		b = _b
		a = _a

	func add(color: PixelColor) -> void:
		r += color.r
		g += color.g
		b += color.b
		a += color.a

	func div(value: float) -> void:
		if value == 0:
			r = 0
			g = 0
			b = 0
			a = 0
		else:
			r /= value
			g /= value
			b /= value
			a /= value

	func distance_to(color: PixelColor) -> float:
		var d_r: float = r - color.r
		var d_g: float = g - color.g
		var d_b: float = b - color.b
		var d_a: float = a - color.a
		return (d_r * d_r) + (d_g * d_g) + (d_b * d_b) + (d_a * d_a)

	func to_string() -> String:
		return 'PixelColor: r = %d, g = %d, b = %d, a = %d\n' % [r, g, b, a]

func how_many_divisions(colors_count: int) -> int:
	return int(ceil( pow(colors_count, 1.0 / 4.0) ))

func get_colors(colors_count: int) -> Array:
	var divisions_count: int = how_many_divisions(colors_count)
	var colors: Array = []

	for a in range(divisions_count):
		for b in range(divisions_count):
			for g in range(divisions_count):
				for r in range(divisions_count):
					colors.append(PixelColor.new(
							(255.0 / divisions_count) * r,
							(255.0 / divisions_count) * g,
							(255.0 / divisions_count) * b,
							(255.0 / divisions_count) * a))

	return colors

func change_colors_thread(args: Dictionary) -> PoolByteArray:
	# args = data: PoolByteArray, average_colors: Array, start: int, stop: int
	var result_image_data: PoolByteArray = PoolByteArray([])
	var start: int = args['start'] * 4
	var stop: int = args['stop'] * 4
	var data: PoolByteArray = args['data']
	var average_colors: Array = args['average_colors']

	# Change colors to average colors
	var i: int = start
	while i < stop:
		var r: int = data[i]
		var g: int = data[i + 1]
		var b: int = data[i + 2]
		var a: int = data[i + 3]
		var color: PixelColor = PixelColor.new(r, g, b, a)
		var nearest_color: int = -1

		for ci in range(average_colors.size()):
			if nearest_color == -1:
				nearest_color = ci
			if color.distance_to(average_colors[ci]) < color.distance_to(average_colors[nearest_color]):
				nearest_color = ci

		result_image_data.append(nearest_color)

		i += 4

	return result_image_data

func change_colors(image: Image, average_colors: Array) -> PoolByteArray:
	var result_image_data: PoolByteArray

	var image_pixels_count: int = image.get_data().size() / 4
	var image_pixels_count_per_chunk: int = int(ceil(float(image_pixels_count) / 4.0))

	var thread_1: Thread = Thread.new()
	var thread_2: Thread = Thread.new()
	var thread_3: Thread = Thread.new()
	var thread_4: Thread = Thread.new()

	thread_1.start(self, "change_colors_thread", {
			'data': image.get_data(),
			'average_colors': average_colors,
			'start': 0,
			'stop': image_pixels_count_per_chunk})
	thread_2.start(self, "change_colors_thread", {
			'data': image.get_data(),
			'average_colors': average_colors,
			'start': image_pixels_count_per_chunk,
			'stop': 2 * image_pixels_count_per_chunk})
	thread_3.start(self, "change_colors_thread", {
			'data': image.get_data(),
			'average_colors': average_colors,
			'start': 2 * image_pixels_count_per_chunk,
			'stop': 3 * image_pixels_count_per_chunk})
	thread_4.start(self, "change_colors_thread", {
			'data': image.get_data(),
			'average_colors': average_colors,
			'start': 3 * image_pixels_count_per_chunk,
			'stop': image_pixels_count})

	var thread_1_res: PoolByteArray = thread_1.wait_to_finish()
	var thread_2_res: PoolByteArray = thread_2.wait_to_finish()
	var thread_3_res: PoolByteArray = thread_3.wait_to_finish()
	var thread_4_res: PoolByteArray = thread_4.wait_to_finish()

	result_image_data = thread_1_res + thread_2_res + thread_3_res + thread_4_res

	return result_image_data

func convert_pixel_colors_to_array_colors(colors: Array) -> Array:
	var result := []
	for v in colors:
		result.append([v.r, v.g, v.b, v.a])
	return result

func quantize_and_convert_to_codes(image: Image) -> Array:
	image.lock()

	var colors: Array = get_colors(256)
	var result: PoolByteArray = change_colors(image, colors)

	image.unlock()
	return [result, convert_pixel_colors_to_array_colors(colors)]
