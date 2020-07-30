extends Control


var gifexporter = preload("res://gdgifexporter/gifexporter.gd")
var uniform_quantizator = preload("res://gdgifexporter/quantization/uniform_quantization.gd").new()
var enhanced_uniform_quantizator = preload("res://gdgifexporter/quantization/enhanced_uniform_quantization.gd").new()
var my_quantizator = preload("res://gdgifexporter/quantization/quantization.gd").new()
var median_cut = preload("res://gdgifexporter/quantization/median_cut.gd").new()

var img1: Image
var img2: Image

var export_thread: Thread = Thread.new()
var timer: float = 0
var should_count: bool = false
var count_mutex: Mutex = Mutex.new()

func _ready():
	img1 = Image.new()
	img2 = Image.new()
	img1.load('res://chocolade.png')
	img1.convert(Image.FORMAT_RGBA8)
	img2.load('res://colors.png')
	img2.convert(Image.FORMAT_RGBA8)
	var img_texture := ImageTexture.new()
	img_texture.create_from_image(img1)
	$CenterContainer/VBoxContainer/TextureRect.texture = img_texture

func _process(delta):
	count_mutex.lock()
	if should_count:
		timer += delta
	count_mutex.unlock()

func export_thread_method(args: Dictionary):
	count_mutex.lock()
	should_count = true
	count_mutex.unlock()
	var exporter = gifexporter.new(img1.get_width(), img1.get_height())
	exporter.write_frame(img1, 0.3, median_cut)
	#exporter.write_frame(img2, 0.5, my_quantizator)

	var file: File = File.new()
	file.open('user://result.gif', File.WRITE)
	file.store_buffer(exporter.export_file_data())
	file.close()
	print("DONE")
	count_mutex.lock()
	should_count = false
	print("Time took: " + str(timer))
	timer = 0
	count_mutex.unlock()

func _on_Button_pressed():
	if not export_thread.is_active():
		export_thread.start(self, 'export_thread_method', {})
