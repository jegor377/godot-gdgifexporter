extends Reference


var converter = preload('../converter.gd').new()
var color_table: Dictionary = {}
var transparency: bool = false
var tree: TreeNode
var leaf: Array = []


class TreeNode:
	var colors: Array
	var average_color: Array
	var axis: int
	var median: int
	var left
	var right


	func _init(_colors: Array):
		self.colors = _colors


	func median_cut() -> void:
		var start: Array = [255, 255, 255]
		var end: Array = [0, 0, 0]
		var delta: Array = [0, 0, 0]

		for color in colors:
			for i in 3:
				start[i] = min(start[i], color[i])
				end[i] = max(end[i], color[i])
		for i in 3:
			delta[i] = end[i] - start[i]
		axis = 0
		if delta[1] > delta[0]:
			axis = 1
		if delta[2] > delta[axis]:
			axis = 2

		var axis_sort: Array = []
		for i in colors.size():
			axis_sort.append(colors[i][axis])
		axis_sort.sort()
		var cut = colors.size() >> 1
		median = axis_sort[cut]

		var left_colors: Array = []
		var right_colors: Array = []
		for color in colors:
			if color[axis] < median:
				left_colors.append(color)
			else:
				right_colors.append(color)
		left = TreeNode.new(left_colors)
		right = TreeNode.new(right_colors)
		colors = []


	func calculate_average_color(color_table: Dictionary) -> void:
		average_color = [0, 0, 0]
		var total: int = 0
		for color in colors:
			var weight = color_table[color]
			for i in 3:
				average_color[i] += color[i] * weight
			total += weight
		for i in 3:
			average_color[i] /= max(total, 1)


func fill_color_table(image: Image) -> void:
	image.lock()
	var data: PoolByteArray = image.get_data()

	for i in range(0, data.size(), 4):
		if data[i + 3] == 0:
			transparency = true
			continue
		var color: Array = [data[i], data[i + 1], data[i + 2]]
		var count = color_table.get(color, 0)
		color_table[color] = count + 1
	image.unlock()


func quantize_and_convert_to_codes(image: Image) -> Array:
	color_table.clear()
	transparency = false
	fill_color_table(image)

	tree = TreeNode.new(color_table.keys())
	leaf = [tree]
	var num = 254 if transparency else 255
	while leaf.size() <= num:
		var node = leaf.pop_front()
		if node.colors.size() > 1:
			node.median_cut()
			leaf.append(node.left)
			leaf.append(node.right)
		if leaf.size() <= 0:
			break

	var color_quantized: Dictionary = {}
	for node in leaf:
		node.calculate_average_color(color_table)
		color_quantized[node.average_color] = color_quantized.size()

	var color_array: Array = color_quantized.keys()
	if transparency:
		color_array.push_front([0, 0, 0])

	var data: PoolByteArray = converter.get_similar_indexed_datas(image, color_array)
	return [data, color_array, transparency]
