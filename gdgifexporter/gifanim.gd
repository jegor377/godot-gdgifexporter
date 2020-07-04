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
	for ii in range(left, right - 1):
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
				for ii in range(0, num_pixels):
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
				for ii in range(0, num_pixels):
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
		for ii in range(0, num_pixels):
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
	for ii in range(0, num_pixels):
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
	
	# offsetted_image is needed because in the original file, the image pointer was offsetted by specified amount.
	var offsetted_image: PoolByteArray = image.subarray(sub_pixels_a * 4, -1)
	gif_split_palette(offsetted_image, sub_pixels_b, split_elt, last_elt, split_elt + split_dist, split_dist / 2, tree_node * 2 + 1, build_for_dither, pal)

# Finds all pixels that have changed from the previous image and
# moves them to the fromt of the buffer.
# This allows us to build a palette optimized for the colors of the
# changed pixels only.
# -----------------------------------------------------------------
func gif_pick_changed_pixels(last_frame: PoolByteArray, frame: PoolByteArray, num_pixels: int) -> int:
	var num_changed: int = 0
	var write_iter: PoolByteArray = frame
	var curr_byte_id: int = 0
	var write_curr_byte_id: int = 0
	
	for ii in range(0, num_pixels):
		if (last_frame[curr_byte_id] != frame[curr_byte_id]) or (last_frame[curr_byte_id + 1] != frame[curr_byte_id + 1]) or (last_frame[curr_byte_id + 2] != frame[curr_byte_id + 2]):
			write_iter[write_curr_byte_id] = frame[curr_byte_id]
			write_iter[write_curr_byte_id + 1] = frame[curr_byte_id + 1]
			write_iter[write_curr_byte_id + 2] = frame[curr_byte_id + 2]
			num_changed += 1
			write_curr_byte_id += 4
		curr_byte_id += 4
	
	return num_changed

# Creates a palette by placing all the image pixels in a
# k-d tree and then averaging the blocks at the bottom.
# This is known as the "modified median split" technique
# ------------------------------------------------------
func gif_make_palette(last_frame: PoolByteArray, next_frame: PoolByteArray, width: int, height: int, bit_depth: int, build_for_dither: bool, p_pal: GifPallete) -> void:
	p_pal.bit_depth = bit_depth
	
	# SplitPalette is destructive (it sorts the pixels by color) so
	# we must create a copy of the image for it to destroy
	# --------------------------------------------------------------
	var destroyable_image: PoolByteArray = next_frame
	
	var num_pixels: int = width * height
	if not last_frame.empty():
		num_pixels = gif_pick_changed_pixels(last_frame, destroyable_image, num_pixels)
	
	var last_elt: int = 1 << bit_depth
	var split_elt: int = last_elt / 2
	var split_dist: int = split_elt / 2
	
	gif_split_palette(destroyable_image, num_pixels, 1, last_elt, split_elt, split_dist, 1, build_for_dither, p_pal)
	
	# add the bottom node for the transparency index
	# ----------------------------------------------
	p_pal.tree_split[1 << (bit_depth - 1)] = 0
	p_pal.tree_split_elt[1 << (bit_depth - 1)] = 0
	p_pal.r[0] = 0
	p_pal.g[0] = 0
	p_pal.b[0] = 0

# Implements Floyd-Steinberg dithering, writes palette value to alpha
# -------------------------------------------------------------------
func gif_dither_image(last_frame: PoolByteArray, next_frame: PoolByteArray, out_frame: PoolByteArray, width: int, height: int, p_pal: GifPallete) -> void:
	var num_pixels = width * height
	
	# quantPixels initially holds color*256 for all pixels. The extra
	# 8 bits of precision allow for sub-single-color error values to
	# be propagated
	# ---------------------------------------------------------------
	var quant_pixels: PoolIntArray = []
	quant_pixels.resize(num_pixels * 4)
	
	for ii in range(0, num_pixels * 4):
		var pix: int = next_frame[ii]
		var pix16: int = pix * 256
		quant_pixels[ii] = pix16
	
	for yy in range(0, height):
		for xx in range(0, width):
			var next_pix: int = 4 * (yy * width + xx)
			var last_pix: int = -1 # instead of NULL
			if not last_frame.empty():
				last_pix = 4 * (yy * width + xx)
			
			# Compute the colors we want (rounding to nearest)
			# ------------------------------------------------
			var rr: int = (quant_pixels[next_pix] + 127) / 256
			var gg: int = (quant_pixels[next_pix + 1] + 127) / 256
			var bb: int = (quant_pixels[next_pix + 2] + 127) / 256
			
			# if it happens that we want the color from the last
			# frame, then just write out a transparent pixel
			# --------------------------------------------------
			if (not last_frame.empty()) and quant_pixels[last_pix] == rr and quant_pixels[last_pix + 1] == gg and quant_pixels[last_pix + 2] == bb:
				quant_pixels[next_pix] = rr
				quant_pixels[next_pix + 1] == gg
				quant_pixels[next_pix + 2] == bb
				quant_pixels[next_pix + 3] = K_GIF_TRANS_INDEX
				continue
			
			var best_diff: int = 1000000
			var best_ind: int = K_GIF_TRANS_INDEX
			
			# Search the palete
			# -----------------
			gif_get_closest_palette_color(p_pal, rr, gg, bb, best_ind, best_diff, 0) # idk why there is no last parameter passed but I pass 0
			
			# Write the result to the temp buffer
			# -----------------------------------
			var r_err = quant_pixels[next_pix] - p_pal.r[best_ind] * 256
			var g_err = quant_pixels[next_pix + 1] - p_pal.g[best_ind] * 256
			var b_err = quant_pixels[next_pix + 2] - p_pal.b[best_ind] * 256
			
			quant_pixels[next_pix] = p_pal.r[best_ind]
			quant_pixels[next_pix + 1] = p_pal.g[best_ind]
			quant_pixels[next_pix + 2] = p_pal.b[best_ind]
			quant_pixels[next_pix + 3] = best_ind
			
			# Propagate the error to the four adjacent locations
			# that we haven't touched yet
			# --------------------------------------------------
			var quantloc_7: int = yy * width + xx + 1
			var quantloc_3: int = yy * width + width + xx - 1
			var quantloc_5: int = yy * width + width + xx
			var quantloc_1: int = yy * width + width + xx + 1
			
			if quantloc_7 < num_pixels:
				var pix7: int = 4 * quantloc_7
				quant_pixels[pix7] += max(-quant_pixels[pix7], r_err * 7 / 16)
				quant_pixels[pix7] += max(-quant_pixels[pix7 + 1], g_err * 7 / 16)
				quant_pixels[pix7] += max(-quant_pixels[pix7 + 2], b_err * 7 / 16)
			
			if quantloc_3 < num_pixels:
				var pix3: int = 4 * quantloc_3
				quant_pixels[pix3] += max(-quant_pixels[pix3], r_err * 3 / 16)
				quant_pixels[pix3] += max(-quant_pixels[pix3 + 1], g_err * 3 / 16)
				quant_pixels[pix3] += max(-quant_pixels[pix3 + 2], b_err * 3 / 16)
			
			if quantloc_5 < num_pixels:
				var pix5: int = 4 * quantloc_5
				quant_pixels[pix5] += max(-quant_pixels[pix5], r_err * 5 / 16)
				quant_pixels[pix5] += max(-quant_pixels[pix5 + 1], g_err * 5 / 16)
				quant_pixels[pix5] += max(-quant_pixels[pix5 + 2], b_err * 5 / 16)
			
			if quantloc_1 < num_pixels:
				var pix1: int = 4 * quantloc_1
				quant_pixels[pix1] += max(-quant_pixels[pix1], r_err * 1 / 16)
				quant_pixels[pix1] += max(-quant_pixels[pix1 + 1], g_err * 1 / 16)
				quant_pixels[pix1] += max(-quant_pixels[pix1 + 2], b_err * 1 / 16)		
	
	# Copy the palettized result to the output buffer
	# -----------------------------------------------
	for ii in range(0, num_pixels * 4):
		out_frame[ii] = quant_pixels[ii]

# Picks palette colors for the image using simple thresholding, no dithering
# --------------------------------------------------------------------------
func gif_threshold_image(last_frame: PoolByteArray, next_frame: PoolByteArray, out_frame: PoolByteArray, width: int, height: int, p_pal: GifPallete):
	var pindex: int
	var next_frame_byte_id: int = 0
	var out_frame_byte_id: int = 0
	var last_frame_byte_id: int = 0
	
	var num_pixels = width * height
	if have_palette:
		for ii in range(0, num_pixels):
			# find exact match
			pindex = 1 # in case it's not there... which would be bad
			for pi in range(0, 256):
				if next_frame[next_frame_byte_id] == have.r[pi]:
					if next_frame[next_frame_byte_id + 1] == have.g[pi]:
						if next_frame[next_frame_byte_id + 2] == have.b[pi]:
							pindex = pi
							pi = 256 # found
			out_frame[out_frame_byte_id + 3] = pindex
			out_frame_byte_id += 4
			next_frame_byte_id + 4
		return
	for ii in range(0, num_pixels):
		# if a previous color is available, and it matches
		# the current color, set the pixel to transparent
		# ------------------------------------------------
		if (not last_frame.empty()) and (last_frame[last_frame_byte_id] == next_frame[next_frame_byte_id]) and (last_frame[last_frame_byte_id + 1] == next_frame[next_frame_byte_id + 1]) and (last_frame[last_frame_byte_id + 2] == next_frame[next_frame_byte_id + 2]):
			out_frame[out_frame_byte_id] = last_frame[last_frame_byte_id]
			out_frame[out_frame_byte_id + 1] = last_frame[last_frame_byte_id + 1]
			out_frame[out_frame_byte_id + 2] = last_frame[last_frame_byte_id + 2]
			out_frame[out_frame_byte_id + 3] = K_GIF_TRANS_INDEX
		else:
			# palettize the pixel
			# -------------------
			var best_diff: int = 1000000
			var best_ind: int = 1
			gif_get_closest_palette_color(p_pal, next_frame[next_frame_byte_id], next_frame[next_frame_byte_id + 1], next_frame[next_frame_byte_id + 2], best_ind, best_diff, 0)
			
			# Write the resulting color to the output buffer
			# ----------------------------------------------
			out_frame[out_frame_byte_id] = p_pal.r[best_ind]
			out_frame[out_frame_byte_id + 1] = p_pal.g[best_ind]
			out_frame[out_frame_byte_id + 2] = p_pal.b[best_ind]
			out_frame[out_frame_byte_id + 3] = best_ind
			
			if not last_frame.empty():
				last_frame_byte_id += 4
			out_frame_byte_id += 4
			next_frame_byte_id += 4
