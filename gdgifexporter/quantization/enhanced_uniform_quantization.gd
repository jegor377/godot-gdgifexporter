extends Reference

func how_many_divisions(colors_count: int) -> int:
	return int(ceil( pow(colors_count, 1.0 / 4.0) ))


func get_colors(colors_count: int) -> Array:
	var divisions_count: int = how_many_divisions(colors_count)
	var colors: Array = []

	for a in range(divisions_count):
		for b in range(divisions_count):
			for g in range(divisions_count):
				for r in range(divisions_count):
					colors.append([Vector3(
							(255.0 / divisions_count) * r,
							(255.0 / divisions_count) * g,
							(255.0 / divisions_count) * b),
							(255.0 / divisions_count) * a])

	return colors


func change_colors(image: Image, average_colors: Array) -> PoolByteArray:
	var result_image_data: PoolByteArray
	var image_data: PoolByteArray = image.get_data()
	var table: Dictionary = {}

	for i in range(0, image_data.size(), 4):
		var v3: Vector3 = Vector3(floor(image_data[i]), floor(image_data[i + 1]), floor(image_data[i + 2]))
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

func find_nearest_color(palette_color: Vector3, image_data: PoolByteArray, palette: Array) -> Array:
	var nearest_color = null
	var nearest_alpha = null
	for i in range(0, image_data.size(), 4):
			var color = Vector3(image_data[i], image_data[i + 1], image_data[i + 2])
			if (nearest_color == null) or (palette_color.distance_squared_to(color) < palette_color.distance_squared_to(nearest_color)):
				nearest_color = color
				nearest_alpha = image_data[i + 3]
	return [nearest_color, nearest_alpha]

func find_color(color: Array, palette: Array) -> int:
	for i in range(palette.size()):
		if palette[i][0] == color[0] and palette[i][1] == color[1]:
			return i
	return -1

# moves every color from palette colors to the nearest found color in image
func enhance_colors(image: Image, palette_colors: Array) -> Array:
	var result_palette: Array = []
	var image_data: PoolByteArray = image.get_data()

	for c in palette_colors:
		var nearest_color: Array = []
		var tmp_palette: Array = palette_colors.duplicate(true) # deep copy
		while true:
			if tmp_palette.empty():
				break
			nearest_color = find_nearest_color(c[0], image_data, tmp_palette)
			if find_color(nearest_color, result_palette) == -1:
				break # we've found nearest color
			else:
				var nearest_color_in_tmp_index: int = find_color(nearest_color, tmp_palette)
				if nearest_color_in_tmp_index != -1:
					tmp_palette.remove(nearest_color_in_tmp_index)
				else:
					nearest_color = []
					break

		if not nearest_color.empty():
			result_palette.append(nearest_color)

	return result_palette


func convert_pixel_colors_to_array_colors(colors: Array) -> Array:
	var result := []
	for v in colors:
		result.append([v[0].x, v[0].y, v[0].z, v[1]])
	return result


func quantize_and_convert_to_codes(image: Image) -> Array:
	image.lock()

	var colors: Array = get_colors(256)
	var tmp_image: Image = Image.new()
	tmp_image.copy_from(image)
	tmp_image.resize(32, 32)
	tmp_image.lock()
	colors = enhance_colors(tmp_image, colors)
	tmp_image.unlock()
	var result: PoolByteArray = change_colors(image, colors)

	image.unlock()
	return [result, convert_pixel_colors_to_array_colors(colors)]
