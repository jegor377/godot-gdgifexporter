# Gif exporter for Godot made entirely in GDScript
This is gif exporter for godot made entirely using GDScript. This is based on [godot-gifexporter](https://github.com/novhack/godot-gifexporter).

# Usage
First, if you use code directly cloned from this repo, grab gdgifexporter directory into your project and preload gifexporter.gd file. Although, I suggest you using code from release package.

## Use examples
### Simple way
```gdscript
extends Node2D


# load gif exporter module
var gifexporter = preload("res://gdgifexporter/gifexporter.gd")
# load and initialize quantization method that you want to use
var median_cut = preload("res://gdgifexporter/quantization/median_cut.gd").new()


func _ready():
	var img := Image.new()
	# load your image from png file
	img.load('res://image.png')
	# remember to use this image format when exporting
	img.convert(Image.FORMAT_RGBA8)

	# initialize exporter object with width and height of gif canvas
	var exporter = gifexporter.new(img1.get_width(), img1.get_height())
	# write image using median_cut quantizator and with one second animation delay
	exporter.write_frame(img, 1, median_cut)

	# when you have exported all frames of animation you, then you can save data into file
	var file: File = File.new()
	# open new file with write privlige
	file.open('user://result.gif', File.WRITE)
	# save data stream into file
	file.store_buffer(exporter.export_file_data())
	# close the file
	file.close()
```

### Convert image, scale and then save
```gdscript
extends Node2D


# load gif exporter module
var gifexporter = preload("res://gdgifexporter/gifexporter.gd")
# load and initialize quantization method that you want to use
var median_cut = preload("res://gdgifexporter/quantization/median_cut.gd").new()


func _ready():
	var img := Image.new()
	# load your image from png file
	img.load('res://image.png')
	# remember to use this image format when exporting
	img.convert(Image.FORMAT_RGBA8)

	# initialize exporter object with width and height of gif canvas.
	# Remember to have bigger canvas when you want to scale the image
	var exporter = gifexporter.new(img1.get_width() * 2, img1.get_height() * 2)
	# convert image using median_cut quantizator
	var conv_img_res = exporter.convert_image(img, median_cut)
	# check if converted image result error value says that everything is OK
	if conv_img_res.error == exporter.Error.OK:
		# if yes then scale the image 2x times
		var conv_img = exporter.scale_conv_image(conv_img_res.converted_image, 2)
		# write converted image with frame delay of 1s
		exporter.write_frame_from_conv_image(conv_img, 1)
	else:
		# else print error to the screen with error code
		push_error("Error: %d" % [conv_img_res.error])

	# when you have exported all frames of animation you, then you can save data into file
	var file: File = File.new()
	# open new file with write privlige
	file.open('user://result.gif', File.WRITE)
	# save data stream into file
	file.store_buffer(exporter.export_file_data())
	# close the file
	file.close()
```

## Quantization methods
We support two quantization methods:
- Median Cut
- Enhanced Uniform (this is just Uniform method with small color adjustment)

Both method files are stored in gdgifexporter/quantization directory.

## Error Codes
Some methods give error codes. These are used error codes and their meaning:
- OK = 0 (Everything went okay)
- EMPTY_IMAGE = 1 (Passed image object has no data in it)
- BAD_IMAGE_FORMAT = 2 (You are using different image format than FORMAT_RGBA8)

# Contriburors
If you want to contribute to this code then go ahead! :) Huge thanks to Kinwailo and novhack. This project wouldn't work without their help! :D

# Used external libs
- [godot-gif-lzw](https://github.com/jegor377/godot-gif-lzw)
