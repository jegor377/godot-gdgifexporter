extends Control


const MedianCut := preload("res://gdgifexporter/quantization/new_median_cut.gd")

var median_cut := MedianCut.new()
var img: Image

# Called when the node enters the scene tree for the first time.
func _ready():
	img = Image.new()
	img.load('res://imgs/parrots.png')
	img.convert(Image.FORMAT_RGBA8)
	var img_texture := ImageTexture.new()
	img_texture.create_from_image(img)
	$CenterContainer/VBoxContainer/TextureRect.texture = img_texture


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func to_img(colors) -> Image:
	var res_img := Image.new()
	var pixel_data := []
	for color in colors:
		pixel_data += [color[0], color[1], color[2]]
	res_img.unlock()
	res_img.create_from_data(colors.size(), 1, false, Image.FORMAT_RGB8, PoolByteArray(pixel_data))
	res_img.resize(colors.size()*5, 5, Image.INTERPOLATE_NEAREST)
	res_img.lock()
	return res_img


func _on_Button_pressed():
	var colors := median_cut.get_colors(img)
	print(colors[1].size())
	var res_img := to_img(colors[1])
	var img_texture := ImageTexture.new()
	img_texture.create_from_image(res_img)
	$CenterContainer/VBoxContainer/TextureRect2.texture = img_texture
