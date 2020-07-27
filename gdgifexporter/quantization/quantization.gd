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

class AxisSection:
	var start: float
	var end: float

	func _init(_start: float, _end: float):
		start = _start
		end = _end

	func length() -> float:
		return abs(end - start)

	func has_color(color: int) -> bool:
		return start <= color and color <= end

	func to_string() -> String:
		return "AxisSection: start = %f, end = %f" % [start, end]

class VisibleRectangle:
	var r_visible_section: AxisSection = null
	var g_visible_section: AxisSection = null
	var b_visible_section: AxisSection = null
	var a_visible_section: AxisSection = null

	func has_color(color: PixelColor) -> bool:
		if not r_visible_section.has_color(color.r):
			return false
		if not g_visible_section.has_color(color.g):
			return false
		if not b_visible_section.has_color(color.b):
			return false
		if not a_visible_section.has_color(color.a):
			return false
		return true

	func to_string() -> String:
		var res: String = 'VisibleRectangle:\n'
		if r_visible_section == null:
			res += 'NULL\n'
		else:
			res += "%s\n" % [r_visible_section.to_string()]
		if g_visible_section == null:
			res += 'NULL\n'
		else:
			res += "%s\n" % [g_visible_section.to_string()]
		if b_visible_section == null:
			res += 'NULL\n'
		else:
			res += "%s\n" % [b_visible_section.to_string()]
		if a_visible_section == null:
			res += 'NULL\n'
		else:
			res += "%s\n" % [a_visible_section.to_string()]
		return res

class ColorBlock extends VisibleRectangle:
	var colors: Array = []
	var average_color: PixelColor

	func add_color(color: PixelColor) -> void:
		colors.append(color)

	func calculate_average_color() -> void:
		average_color = PixelColor.new(0, 0, 0, 0)
		for v in colors:
			average_color.add(v)
		average_color.div(colors.size())

	func to_string() -> String:
		var res: String = 'ColorBlock:\n'
		res += 'colors_count: %d\n' % [colors.size()]
		return res + .to_string()

func how_many_divisions(how_many_total_boxes: float) -> int:
	return int(ceil( pow(how_many_total_boxes, 1.0 / 4.0) ))

func division_size(axis_length: float, divisions: int) -> float:
	return axis_length / divisions

func calculate_visible_rectangle(image: Image) -> VisibleRectangle:
	# find visible rectangle (rectangle of used colors).
	var total_visible_section: VisibleRectangle = VisibleRectangle.new()
	var r_total_visible_section: AxisSection = null
	var g_total_visible_section: AxisSection = null
	var b_total_visible_section: AxisSection = null
	var a_total_visible_section: AxisSection = null
	var image_data: PoolByteArray = image.get_data()

	var i: int = 0
	while i < image_data.size() - 4:
		var r: int = image_data[i]
		var g: int = image_data[i + 1]
		var b: int = image_data[i + 2]
		var a: int = image_data[i + 3]

		if r_total_visible_section == null:
			r_total_visible_section = AxisSection.new(r, r)
		else:
			r_total_visible_section.start = min(r_total_visible_section.start, r)
			r_total_visible_section.end = max(r_total_visible_section.end, r)

		if g_total_visible_section == null:
			g_total_visible_section = AxisSection.new(g, g)
		else:
			g_total_visible_section.start = min(g_total_visible_section.start, g)
			g_total_visible_section.end = max(g_total_visible_section.end, g)

		if b_total_visible_section == null:
			b_total_visible_section = AxisSection.new(b, b)
		else:
			b_total_visible_section.start = min(b_total_visible_section.start, b)
			b_total_visible_section.end = max(b_total_visible_section.end, b)

		if a_total_visible_section == null:
			a_total_visible_section = AxisSection.new(a, a)
		else:
			a_total_visible_section.start = min(a_total_visible_section.start, a)
			a_total_visible_section.end = max(a_total_visible_section.end, a)

		i += 4

	total_visible_section.r_visible_section = r_total_visible_section
	total_visible_section.g_visible_section = g_total_visible_section
	total_visible_section.b_visible_section = b_total_visible_section
	total_visible_section.a_visible_section = a_total_visible_section

	return total_visible_section

func create_color_boxes(visible_sections: VisibleRectangle, divisions_per_axis: int) -> Array:
	var boxes: Array = []

	var r_axis_division_size = division_size(
			visible_sections.r_visible_section.length(),
			divisions_per_axis)
	var g_axis_division_size = division_size(
			visible_sections.g_visible_section.length(),
			divisions_per_axis)
	var b_axis_division_size = division_size(
			visible_sections.b_visible_section.length(),
			divisions_per_axis)
	var a_axis_division_size = division_size(
			visible_sections.a_visible_section.length(),
			divisions_per_axis)

	for a in range(divisions_per_axis):
		for b in range(divisions_per_axis):
			for g in range(divisions_per_axis):
				for r in range(divisions_per_axis):
					var new_color_box: ColorBlock = ColorBlock.new()
					if r_axis_division_size == 0:
						new_color_box.r_visible_section = visible_sections.r_visible_section
					else:
						new_color_box.r_visible_section = AxisSection.new(
							r * r_axis_division_size,
							r * r_axis_division_size + r_axis_division_size)
					if g_axis_division_size == 0:
						new_color_box.g_visible_section = visible_sections.g_visible_section
					else:
						new_color_box.g_visible_section = AxisSection.new(
							g * g_axis_division_size,
							g * g_axis_division_size + g_axis_division_size)
					if b_axis_division_size == 0:
						new_color_box.b_visible_section = visible_sections.b_visible_section
					else:
						new_color_box.b_visible_section = AxisSection.new(
							b * b_axis_division_size,
							b * b_axis_division_size + b_axis_division_size)
					if a_axis_division_size == 0:
						new_color_box.a_visible_section = visible_sections.a_visible_section
					else:
						new_color_box.a_visible_section = AxisSection.new(
							a * a_axis_division_size,
							a * a_axis_division_size + a_axis_division_size)
					boxes.append(new_color_box)

	return boxes

func calculate_average_colors(image: Image, _boxes: Array) -> Array:
	var boxes: Array = _boxes
	var average_colors: Array = []
	var image_data: PoolByteArray = image.get_data()

	var i: int = 0
	while i < image_data.size() - 4:
		var r: int = image_data[i]
		var g: int = image_data[i + 1]
		var b: int = image_data[i + 2]
		var a: int = image_data[i + 3]
		var color: PixelColor = PixelColor.new(r, g, b, a)

		for bi in range(boxes.size()):
			if boxes[bi].has_color(color):
				boxes[bi].add_color(color)

		i += 4

	for bi in range(boxes.size()):
		boxes[bi].calculate_average_color()
		var v3: Vector3 = Vector3(boxes[bi].average_color.r, boxes[bi].average_color.g, boxes[bi].average_color.b)
		average_colors.append([v3, boxes[bi].average_color.a])

	return average_colors

func change_colors(image: Image, average_colors: Array) -> PoolByteArray:
	var result_image_data: PoolByteArray
	var image_data: PoolByteArray = image.get_data()
	var table: Dictionary = {}

	for i in range(0, image_data.size(), 4):
		var v3: Vector3 = Vector3(int(image_data[i]), int(image_data[i + 1]), int(image_data[i + 2]))
		var nearest_color: int = 0
		if v3 in table:
			nearest_color = table[v3]
		else:
			for ci in range(1, average_colors.size()):
				if v3.distance_squared_to(average_colors[ci][0]) < v3.distance_squared_to(average_colors[nearest_color][0]):
					nearest_color = ci
			table[v3] = nearest_color

		result_image_data.append(nearest_color)

	return result_image_data

func convert_pixel_colors_to_array_colors(colors: Array) -> Array:
	var result := []
	for v in colors:
		result.append([v[0].x, v[0].y, v[0].z, v[1]])
	return result

func quantize_and_convert_to_codes(
		image: Image, use_fast_color_detection_trick: bool = true) -> Array:
	image.lock()

	var total_boxes_count: int = 256
	var divisions_per_axis = how_many_divisions(total_boxes_count)
	var result_image: PoolByteArray
	var average_colors: Array

	if use_fast_color_detection_trick:
		var tmp_image: Image = Image.new()
		tmp_image.copy_from(image)
		if image.get_width() > 32 or image.get_height() > 32:
			tmp_image.resize(32, 32)
		tmp_image.lock()

		var visible_sections: VisibleRectangle = calculate_visible_rectangle(tmp_image)

		var boxes: Array = create_color_boxes(visible_sections, divisions_per_axis)

		average_colors = calculate_average_colors(tmp_image, boxes)

		result_image = change_colors(image, average_colors)

		tmp_image.unlock()
	else:
		var visible_sections: VisibleRectangle = calculate_visible_rectangle(image)

		var boxes: Array = create_color_boxes(visible_sections, divisions_per_axis)

		average_colors = calculate_average_colors(image, boxes)

		result_image = change_colors(image, average_colors)
	image.unlock()
	return [result_image, convert_pixel_colors_to_array_colors(average_colors)]
