## Draws a teletext page (the lines of jf_pages.render) on a 40 x 24 grid of cells.
##
## Text is placed cell by cell, never as a run, so a proportional fallback font (a Quest has no
## system fonts) still lines up in columns. Characters in the private-use range U+E000..U+E03F are
## the MOSAIC blocks: the low six bits say which of the cell's 2 x 3 blocks are lit, drawn as
## rectangles (the font needs no block glyphs).
##
## `transparent` is for a page laid over the picture (the audio and subtitle choosers): plain black
## cells become a dim panel instead of opaque black, so the film shows between the words.
extends Control

const Pages = preload("res://mods/xenu.jellyfin/scripts/jf_pages.gd")

const COLS := 40
const ROWS := 24
const MOSAIC_FIRST := 0xE000

## Teletext's eight colours, a notch off pure so a CRT does not bloom them to white.
const PALETTE := [
	Color(0.0, 0.0, 0.0), Color(1.0, 0.1, 0.1), Color(0.1, 1.0, 0.2), Color(1.0, 1.0, 0.1),
	Color(0.15, 0.2, 1.0), Color(1.0, 0.1, 1.0), Color(0.1, 1.0, 1.0), Color(0.95, 0.95, 0.95),
]

var lines: Array = []
var transparent := false
var _font: Font = null


func _ready() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Courier New", "Consolas", "monospace"])
	_font = f
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_lines(l: Array) -> void:
	lines = l
	queue_redraw()


## The character that draws as the given blocks (bit 0 top-left, 1 top-right, 2 mid-left, 3 mid-right,
## 4 bottom-left, 5 bottom-right).
static func mosaic(mask: int) -> String:
	return String.chr(MOSAIC_FIRST + (mask & 0x3F))


func _draw() -> void:
	var cw := size.x / COLS
	var ch := size.y / ROWS
	if not transparent:
		draw_rect(Rect2(Vector2.ZERO, size), PALETTE[0])
	var font_size := int(ch * 0.9)
	for row in mini(lines.size(), ROWS):
		var x := 0
		for seg in lines[row]:
			var text: String = seg[0]
			var fg: Color = PALETTE[int(seg[1]) & 7]
			var bg_i := int(seg[2]) & 7
			var rect := Rect2(x * cw, row * ch, text.length() * cw, ch)
			if bg_i != 0:
				draw_rect(rect, PALETTE[bg_i])
			elif transparent and not text.strip_edges().is_empty():
				draw_rect(rect, Color(0, 0, 0, 0.72))
			for i in text.length():
				var code := text.unicode_at(i)
				var cell := Rect2((x + i) * cw, row * ch, cw, ch)
				if code >= MOSAIC_FIRST and code < MOSAIC_FIRST + 64:
					_draw_mosaic(cell, code - MOSAIC_FIRST, fg)
				elif code != 32:
					# Baseline: a font's ascent is ~0.8 of the cell.
					draw_string(_font, Vector2(cell.position.x + cw * 0.08, cell.position.y + ch * 0.80),
						text.substr(i, 1), HORIZONTAL_ALIGNMENT_LEFT, cw, font_size, fg)
			x += text.length()


func _draw_mosaic(cell: Rect2, mask: int, color: Color) -> void:
	var bw := cell.size.x / 2.0
	var bh := cell.size.y / 3.0
	for bit in 6:
		if mask & (1 << bit):
			var col := bit % 2
			var rw := bit / 2
			draw_rect(Rect2(cell.position.x + col * bw, cell.position.y + rw * bh, bw, bh), color)
