extends Control


var gifexporter = preload("res://gdgifexporter/gifexporter.gd")
var uniform_quantizator = preload("res://gdgifexporter/quantization/uniform_quantization.gd").new()
var enhanced_uniform_quantizator = preload("res://gdgifexporter/quantization/enhanced_uniform_quantization.gd").new()
var my_quantizator = preload("res://gdgifexporter/quantization/quantization.gd").new()

var img1: Image
var img2: Image

func _ready():
	img1 = Image.new()
	img2 = Image.new()
	img1.load('res://img1.png')
	img1.convert(Image.FORMAT_RGBA8)
	img2.load('res://img2.png')
	img2.convert(Image.FORMAT_RGBA8)
	var img_texture := ImageTexture.new()
	img_texture.create_from_image(img1)
	$CenterContainer/VBoxContainer/TextureRect.texture = img_texture

func _on_Button_pressed():
	var exporter = gifexporter.new(img1.get_width(), img1.get_height())
	exporter.write_frame(img1, 0.3, my_quantizator)
	exporter.write_frame(img2, 0.5, uniform_quantizator)

	var file: File = File.new()
	file.open('user://result.gif', File.WRITE)
	file.store_buffer(exporter.export_file_data())
	file.close()
	print("DONE")
