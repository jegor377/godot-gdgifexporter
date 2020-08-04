extends Control


var gifexporter = preload("res://gdgifexporter/gifexporter.gd")
var uniform_quantizator = preload("res://gdgifexporter/quantization/uniform_quantization.gd").new()
var enhanced_uniform_quantizator = preload("res://gdgifexporter/quantization/enhanced_uniform_quantization.gd").new()
var my_quantizator = preload("res://gdgifexporter/quantization/quantization.gd").new()
var median_cut = preload("res://gdgifexporter/quantization/median_cut.gd").new()

var img1: Image
var img2: Image
var img3: Image
var img4: Image

var export_thread: Thread = Thread.new()
var timer: float = 0
var should_count: bool = false
var count_mutex: Mutex = Mutex.new()

func _ready():
	img1 = Image.new()
	img2 = Image.new()
	img3 = Image.new()
	img4 = Image.new()
	img1.load('res://half_transparent.png')
	img1.convert(Image.FORMAT_RGBA8)
	img2.load('res://two_colors.png')
	img2.convert(Image.FORMAT_RGBA8)
	img3.load('res://transparent.png')
	img3.convert(Image.FORMAT_RGBA8)
	img4.load('res://one_color.png')
	img4.convert(Image.FORMAT_RGBA8)
	var img_texture := ImageTexture.new()
	img_texture.create_from_image(img1)
	$CenterContainer/VBoxContainer/TextureRect.texture = img_texture

func _process(delta):
	count_mutex.lock()
	if should_count:
		timer += delta
	count_mutex.unlock()

func _exit_tree():
	export_thread.wait_to_finish()

func export_thread_method(args: Dictionary):
	count_mutex.lock()
	should_count = true
	count_mutex.unlock()
	var exporter = gifexporter.new(img1.get_width(), img1.get_height())
	exporter.write_frame(img1, 1, median_cut)
	exporter.write_frame(img2, 1, median_cut)
	exporter.write_frame(img3, 1, median_cut)
	exporter.write_frame(img4, 1, median_cut)

	print("DONE")
	count_mutex.lock()
	should_count = false
	print("Time took: " + str(timer))
	timer = 0
	count_mutex.unlock()

	var file: File = File.new()
	file.open('user://result.gif', File.WRITE)
	file.store_buffer(exporter.export_file_data())
	file.close()

func _on_Button_pressed():
	if not should_count:
		if export_thread.is_active():
			export_thread.wait_to_finish()
		export_thread = Thread.new()
		export_thread.start(self, 'export_thread_method', {})
