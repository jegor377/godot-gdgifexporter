# Gif exporter for Godot made entirely in GDScript
This is gif exporter for godot made entirely using GDScript. This is based on [godot-gifexporter](https://github.com/novhack/godot-gifexporter).

<p align="center">
	<a href="https://github.com/godotengine/awesome-godot">
		<img src="https://awesome.re/mentioned-badge.svg" alt="Mentioned in Awesome Godot" />
	</a>
</p>

## Example
```gdscript
extends Node2D


# load gif exporter module
const GIFExporter = preload("res://gdgifexporter/exporter.gd")
# load quantization module that you want to use
const MedianCutQuantization = preload("res://gdgifexporter/quantization/median_cut.gd")


func _ready():
	var img := Image.new()
	# load your image from png file
	img.load('res://image.png')
	# remember to use this image format when exporting
	img.convert(Image.FORMAT_RGBA8)

	# initialize exporter object with width and height of gif canvas
	var exporter = GIFExporter.new(img1.get_width(), img1.get_height())
	# write image using median cut quantization method and with one second animation delay
	exporter.add_frame(img, 1, MedianCutQuantization)

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
Addon supports two quantization methods:
- Median Cut
- Uniform (with small color adjustment)

Both method files are stored in gdgifexporter/quantization directory.

## Error Codes
Some methods give error codes. These are used error codes and their meaning:
- OK = 0 (Everything went okay)
- EMPTY_IMAGE = 1 (Passed image object has no data in it)
- BAD_IMAGE_FORMAT = 2 (You are using different image format than FORMAT_RGBA8)

# Contributors
If you want to contribute to this code then go ahead! :) Huge thanks to Kinwailo and novhack. This project wouldn't work without their help! :D

# Used external libs
- [godot-gif-lzw](https://github.com/jegor377/godot-gif-lzw)
