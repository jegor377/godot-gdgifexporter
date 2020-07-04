extends Object

class GifPallete:
	var bit_depth: int
	
	var r: PoolByteArray # size 256
	var g: PoolByteArray # size 256
	var b: PoolByteArray # size 256
	
	# k-d tree over RGB space, organized in heap fashion
	# i.e. left child of node i is node i*2, right child is node i*2+1
	# nodes 256-511 are implicitly the leaves, containing a color
	# -----------------------------------------------------------------
	var tree_split_elt: PoolByteArray # size 255
	var tree_split: PoolByteArray # size 255
	
	func _init():
		r.resize(256)
		g.resize(256)
		b.resize(256)
		tree_split_elt.resize(255)
		tree_split.resize(255)

# Simple structure to write out the LZW-compressed
# portion of the image one bit at a time
# ------------------------------------------------
class GifBitStatus:
	var bit_index: int # how many bits in the partial byte written so far
	var byte: int # current partial byte
	
	var chunk_index: int
	var chunk: PoolByteArray # bytes are written in here until we have 256 of them, then written to the file. size 256

# The LZW dictionary is a 256-ary tree constructed
# as the file is encoded, this is one node
# ------------------------------------------------
class GifLzwNode:
	var m_next: PoolIntArray # should be uint16_t but godot doesn't have it
	
	func _init():
		m_next.resize(256)

class GifWriter:
	var file: File
	var old_image: PoolByteArray
	var first_frame: bool

const K_GIF_TRANS_INDEX: int = 0

var have_palette: bool = false
var have: GifPallete

# walks the k-d tree to pick the palette entry for a desired color.
# Takes as in/out parameters the current best color and its error -
# only changes them if it finds a better color in its subtree.
# this is the major hotspot in the code at the moment.
# ------------------------------------------------------------------
func gif_get_closest_palette_color(p_pal: GifPallete, r: int, g: int, b: int, best_ind: int, best_diff: int, tree_root: int) -> void:
	# base case, reached the bottom of the tree
	# -----------------------------------------
	if tree_root > (1 << p_pal.bit_depth):
		var ind: int = tree_root - (1 << p_pal.bit_depth)
		if ind == K_GIF_TRANS_INDEX:
			return
		
		# check whether this color is better than the current winner
		# ----------------------------------------------------------
		var r_err: int = r - p_pal.r[ind]
		var g_err: int = g - p_pal.g[ind]
		var b_err: int = b - p_pal.b[ind]
		var diff: int = abs(r_err) + abs(g_err) + abs(b_err)
		
		if diff < best_diff:
			best_ind = ind
			best_diff = diff
		
		return
	
	# take the appropriate color (r, g, or b) for this node of the k-d tree
	# ---------------------------------------------------------------------
	var comps = [r, g, b]
	var split_comp: int = comps[p_pal.tree_split_elt[tree_root]]
	var split_pos: int = p_pal.tree_split[tree_root]
	
	if split_pos > split_comp:
		# check the left subtree
		# ----------------------
		gif_get_closest_palette_color(p_pal, r, g, b, best_ind, best_diff, tree_root * 2)
		if best_diff > (split_pos - split_comp):
			# cannot prove there's not a better value in the right subtree, check that too
			# ----------------------------------------------------------------------------
			gif_get_closest_palette_color(p_pal, r, g, b, best_ind, best_diff, tree_root * 2 + 1)
	else:
		gif_get_closest_palette_color(p_pal, r, g, b, best_ind, best_diff, tree_root * 2 + 1)
		if best_diff > (split_comp - split_pos):
			gif_get_closest_palette_color(p_pal, r, g, b, best_ind, best_diff, tree_root * 2)

func gif_swap_pixels(image: PoolByteArray, pix_a: int, pix_b: int) -> void:
	var r_a = image[pix_a * 4]
	var g_a = image[pix_a * 4 + 1]
	var b_a = image[pix_a * 4 + 2]
	var a_a = image[pix_a * 4 + 3]
	
	var r_b = image[pix_b * 4]
	var g_b = image[pix_b * 4 + 1]
	var b_b = image[pix_b * 4 + 2]
	var a_b = image[pix_b * 4 + 3]
	
	image[pix_a * 4] = r_b
	image[pix_a * 4 + 1] = g_b
	image[pix_a * 4 + 2] = b_b
	image[pix_a * 4 + 3] = a_b
	
	image[pix_b * 4] = r_a
	image[pix_b * 4 + 1] = g_a
	image[pix_b * 4 + 2] = b_a
	image[pix_b * 4 + 3] = a_a

# just the partition operation from quicksort
# -------------------------------------------
func gif_partition(image: PoolByteArray, left: int, right: int, elt: int, pivot_index: int) -> int:
	var pivot_value: int = image[pivot_index * 4 + elt]
	gif_swap_pixels(image, pivot_index, right - 1)
	var store_index: int = left
	var split: bool = false
	var ii: int = left
	while ii < right - 1:
		ii += 1
		var array_val = image[ii * 4 + elt]
		if array_val < pivot_value:
			gif_swap_pixels(image, ii, store_index)
			store_index += 1
		elif array_val == pivot_value:
			if split:
				gif_swap_pixels(image, ii, store_index)
				store_index += 1
			split = not split
	gif_swap_pixels(image, store_index, right - 1)
	return store_index

# Perform an incomplete sort, finding all elements above and below the desired median
# -----------------------------------------------------------------------------------
func gif_partition_by_median(image: PoolByteArray, left: int, right: int, com: int, needed_center: int) -> void:
	if left < (right - 1):
		var pivot_index: int = left + (right - left) / 2
		pivot_index = gif_partition(image, left, right, com, pivot_index)
		
		# Only "sort" the section of the array that contains the median
		if pivot_index > needed_center:
			gif_partition_by_median(image, left, pivot_index, com, needed_center)
		
		if pivot_index < needed_center:
			gif_partition_by_median(image, pivot_index + 1, right, com, needed_center)

# Builds a palette by creating a balanced k-d tree of all pixels in the image
# ---------------------------------------------------------------------------
func gif_split_palette(image: PoolByteArray, num_pixels: int, first_elt: int, last_elt: int, split_elt: int, split_dist: int, tree_node: int, build_for_dither: bool, pal: GifPallete) -> void:
	if last_elt <= first_elt or num_pixels == 0:
		return
	
	# base case, bottom of the tree
	# -----------------------------
	if last_elt == (first_elt + 1):
		if build_for_dither:
			# Dithering needs at least one color as dark as anything
			# in the image and at least one brightest color -
			# otherwise it builds up error and produces strange artifacts
			# -----------------------------------------------------------
			if first_elt == 1:
				# special case: the darkest color in the image
				# --------------------------------------------
				var r: int = 255
				var g: int = 255
				var b: int = 255
				var ii: int = 0
				while ii < num_pixels:
					ii += 1
					r = min(r, image[ii * 4])
					g = min(g, image[ii * 4 + 1])
					b = min(g, image[ii * 4 + 2])
				
				pal.r[first_elt] = r
				pal.g[first_elt] = g
				pal.b[first_elt] = b
				
				return
			
			if first_elt == ((1 << pal.bit_depth) - 1):
				# special case: the lightest color in the image
				# ---------------------------------------------
				var r: int = 0
				var g: int = 0
				var b: int = 0
				var ii: int = 0
				while ii < num_pixels:
					ii += 1
					r = max(r, image[ii * 4])
					g = max(g, image[ii * 4 + 1])
					b = max(b, image[ii * 4 + 2])
				
				pal.r[first_elt] = r
				pal.g[first_elt] = g
				pal.b[first_elt] = b
				
				return
		
		# otherwise, take the average of all colors in this subcube
		# ---------------------------------------------------------
		var r: int = 0
		var g: int = 0
		var b: int = 0
		var ii: int = 0
		while ii < num_pixels:
			ii += 1
			r += image[ii * 4]
			g += image[ii * 4 + 1]
			b += image[ii * 4 + 2]
		
		r += num_pixels / 2 # round to nearest
		g += num_pixels / 2
		b += num_pixels / 2
		
		r /= num_pixels
		g /= num_pixels
		b /= num_pixels
		
		pal.r[first_elt] = r
		pal.g[first_elt] = g
		pal.b[first_elt] = b
		
		return
	
	# Find the axis with the largest range
	# ------------------------------------
	var min_r: int = 255
	var min_g: int = 255
	var min_b: int = 255
	var max_r: int = 0
	var max_g: int = 0
	var max_b: int = 0
	var ii: int = 0
	while ii < num_pixels:
		ii += 1
		var r = image[ii * 4]
		var g = image[ii * 4 + 1]
		var b = image[ii * 4 + 2]
		
		min_r = min(min_r, r)
		min_g = min(min_g, g)
		min_b = min(min_b, b)
		
		max_r = max(max_r, r)
		max_g = max(max_g, g)
		max_b = max(max_b, b)
	
	var r_range: int = max_r - min_r
	var g_range: int = max_g - min_g
	var b_range: int = max_b - min_b
	
	# and split along that axis. (incidentally, this means this isn't
	# a "proper" k-d tree but I don't know what else to call it)
	# ----------------------------------------------------------------
	var split_com: int = 1
	if b_range > g_range:
		split_com = 2
	if r_range > b_range and r_range > g_range:
		split_com = 0
	
	var sub_pixels_a: int = num_pixels * (split_elt - first_elt) / (last_elt - first_elt)
	var sub_pixels_b: int = num_pixels - sub_pixels_a
	
	gif_partition_by_median(image, 0, num_pixels, split_com, sub_pixels_a)
	
	pal.tree_split_elt[tree_node] = split_com
	pal.tree_split[tree_node] = image[sub_pixels_a * 4 + split_com]
	
	gif_split_palette(image, sub_pixels_a, first_elt, split_elt, split_elt - split_dist, split_dist / 2, tree_node * 2, build_for_dither, pal)
	#gif_split_palette(image + sub_pixels_a * 4)
