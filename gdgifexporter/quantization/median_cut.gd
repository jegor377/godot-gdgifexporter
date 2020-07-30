extends Node


var color_table: Dictionary = {}
var transparency: bool = false
var tree: TreeNode
var leaf: Array = []


class TreeNode:
	var colors: Array
	var average_color: Array
	var axis: int
	var median: int
	var parent: TreeNode
	var left: TreeNode
	var right: TreeNode


	func _init(_parent: TreeNode, _colors: Array):
		self.parent = _parent
		self.colors = _colors


	func sort_color(a, b):
		return a[axis] < b[axis]


	func median_cut() -> void:
		var start: Array = [255, 255, 255]
		var end: Array = [0, 0, 0]
		var delta: Array = [0, 0, 0]

		for color in colors:
			for i in 3:
				if color[i] < start[i]:
					start[i] = color[i]
				if color[i] > end[i]:
					end[i] = color[i]
		for i in 3:
			delta[i] = end[i] - start[i]
		axis = 0
		if delta[1] > delta[0]:
			axis = 1
		if delta[2] > delta[axis]:
			axis = 2

		if parent == null or axis != parent.axis:
			colors.sort_custom(self, "sort_color")
		var cut = colors.size() >> 1
		median = colors[cut][axis]
		left = TreeNode.new(self, colors.slice(0, cut - 1))
		right = TreeNode.new(self, colors.slice(cut, colors.size() - 1))
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
			average_color[i] /= total


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


func convert_image(image: Image, colors: Array) -> PoolByteArray:
	image.lock()
	var data: PoolByteArray = image.get_data()
	var nearest_lookup: Dictionary = {}
	var result: PoolByteArray = PoolByteArray()

	for i in range(0, data.size(), 4):
		if data[i + 3] == 0:
			result.append(0)
			continue
		var current: Vector3 = Vector3(data[i], data[i + 1], data[i + 2])
		var nearest_index: int = 0 + int(transparency)
		if current in nearest_lookup:
			nearest_index = nearest_lookup[current]
		else:
			var nearest_color: Vector3 = Vector3(colors[nearest_index][0], colors[nearest_index][1], colors[nearest_index][2])
			for j in range(1 + int(transparency), colors.size()):
				var color: Vector3 = Vector3(colors[j][0], colors[j][1], colors[j][2])
				if current.distance_squared_to(color) < current.distance_squared_to(nearest_color):
					nearest_index = j
					nearest_color = color
			nearest_lookup[current] = nearest_index
		result.append(nearest_index)

	image.unlock()
	return result


func quantize_and_convert_to_codes(image: Image) -> Array:
	color_table.clear()
	transparency = false
	fill_color_table(image)

	tree = TreeNode.new(null, color_table.keys())
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
	return [convert_image(image, color_array), color_array, transparency]
