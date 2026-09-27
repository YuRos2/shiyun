extends Control
## 全唐宋詩 · 平水韻 查詢
## Godot 4.7
##
## 數據層見 DataStore.gd。本腳本負責主題、界面、查詢狀態與渲染。
##
## 界面取意古刻：宣紙為底，楷宋為字，朱印為飾。
##
## 功能：按朝代（唐/宋）與詩人縮小查詢範圍。

const DataStore := preload("res://DataStore.gd")
const PAPER_SHADER := preload("res://paper.gdshader")

# ============================================================
# 版面與字號
# ============================================================
const TITLE_SIZE := 46      # 主標題
const HEAD_SIZE := 34       # 彈層書名／字頭
const SUBTITLE_SIZE := 22   # 副標題
const BODY_SIZE := 30       # 正文、詩句
const SMALL_SIZE := 21      # 出處、注釋
const TINY_SIZE := 18       # 提示、頁腳

const PAGE_SIZE := 600      # 每頁顯示句數

# ============================================================
# 色
# ============================================================
const PAPER_COLOR      := Color("#ece0c6")
const PAPER_LIT_COLOR  := Color("#f8f1e0")
const PAPER_DIM_COLOR  := Color("#e3d6b8")
const INK_COLOR        := Color("#241d16")
const INK_SOFT_COLOR   := Color("#5b4f42")
const ACCENT_COLOR     := Color("#9c2b21")   # 朱砂
const ACCENT_DEEP      := Color("#7a1f18")
const RULE_COLOR       := Color("#cbb78f")
const MUTED_COLOR      := Color("#a08f74")
const GOLD_COLOR       := Color("#b08d4f")
const HIGHLIGHT_COLOR  := Color("#f2dbc9")   # 全詩彈層中高亮該句

# ============================================================
# 裝飾控件（內嵌類）
# ============================================================
## 分隔線：左右細線，中央菱形，兩側小點。
class Ornament extends Control:
	var line_color := Color("#cbb78f")
	var accent_color := Color("#9c2b21")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var mid := size.y * 0.5
		var w := size.x
		var cx := w * 0.5
		var gap: float = maxf(14.0, minf(26.0, w * 0.09))
		draw_line(Vector2(0.0, mid), Vector2(maxf(0.0, cx - gap), mid), line_color, 1.0)
		draw_line(Vector2(minf(w, cx + gap), mid), Vector2(w, mid), line_color, 1.0)
		var d := 4.5
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx, mid - d), Vector2(cx + d, mid),
			Vector2(cx, mid + d), Vector2(cx - d, mid),
		]), accent_color)
		draw_circle(Vector2(cx - gap - 7.0, mid), 1.5, line_color)
		draw_circle(Vector2(cx + gap + 7.0, mid), 1.5, line_color)


## 書頁外框：雙線為欄，四角朱飾。
class DecoFrame extends Control:
	var line_color := Color("#cbb78f")
	var inner_color := Color("#d8c9a8")
	var accent_color := Color("#9c2b21")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var m := 16.0
		if size.x < m * 2.0 + 20.0 or size.y < m * 2.0 + 20.0:
			return
		var outer := Rect2(Vector2(m, m), size - Vector2(m * 2.0, m * 2.0))
		draw_rect(outer, line_color, false, 2.0)
		var inner := outer.grow(-7.0)
		draw_rect(inner, inner_color, false, 1.0)

		# 四角朱色回紋
		var arm := 18.0
		var a := accent_color
		draw_line(outer.position, outer.position + Vector2(arm, 0.0), a, 2.0)
		draw_line(outer.position, outer.position + Vector2(0.0, arm), a, 2.0)
		var tr := Vector2(outer.end.x, outer.position.y)
		draw_line(tr, tr + Vector2(-arm, 0.0), a, 2.0)
		draw_line(tr, tr + Vector2(0.0, arm), a, 2.0)
		var bl := Vector2(outer.position.x, outer.end.y)
		draw_line(bl, bl + Vector2(arm, 0.0), a, 2.0)
		draw_line(bl, bl + Vector2(0.0, -arm), a, 2.0)
		draw_line(outer.end, outer.end + Vector2(-arm, 0.0), a, 2.0)
		draw_line(outer.end, outer.end + Vector2(0.0, -arm), a, 2.0)


## 朱文小印：朱底素字，字豎排。
class Seal extends Control:
	var font: Font
	var chars := PackedStringArray(["詩", "韻"])
	var bg_color := Color("#9c2b21")
	var fg_color := Color("#f8f1e0")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, bg_color, true)
		draw_rect(r.grow(-2.0), fg_color, false, 1.0)
		if font == null or chars.is_empty():
			return
		var fs: int = maxi(8, int(minf(size.x, size.y / float(chars.size())) * 0.80))
		var asc := font.get_ascent(fs)
		var desc := font.get_descent(fs)
		var step := float(asc + desc)
		var total := step * float(chars.size())
		var y := (size.y - total) * 0.5 + float(asc)
		for ch in chars:
			draw_string(font, Vector2(0.0, y), ch, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, fg_color)
			y += step


# ============================================================
# 數據與狀態
# ============================================================
var store := DataStore.new()

var rhyme_ready := false
var poems_ready := false

var current_rhyme_name := ""
var current_query_char := ""
var current_display_count := 0
var current_ids: PackedInt32Array = PackedInt32Array()   # 當前查詢命中的句 id（已篩選）

# 篩選條件
var dynasty_filter := DataStore.DYN_ALL
var author_filter := ""

# ============================================================
# 字體
# ============================================================
var title_font: SystemFont   # 楷
var body_font: SystemFont    # 宋
var title_spaced: FontVariation   # 楷·疏排（匾額之感）

# ============================================================
# UI 引用
# ============================================================
var status_label: Label
var char_input: LineEdit
var query_btn: Button
var dynasty_option: OptionButton
var poet_input: LineEdit
var result_scroll: ScrollContainer
var result_label: RichTextLabel
var welcome_box: VBoxContainer
var welcome_links: RichTextLabel
var more_btn: Button

var overlay: Control
var dialog_title: Label
var dialog_author: Label
var dialog_body: RichTextLabel


# ============================================================
# 生命週期
# ============================================================
func _ready() -> void:
	_setup_theme()
	_build_ui()
	_build_overlay()
	_wire_signals()
	await _load_all_data()


func _setup_theme() -> void:
	title_font = _system_font(PackedStringArray([
		"KaiTi", "楷体", "楷體", "STKaiti", "Kaiti SC", "Kaiti TC",
		"LXGW WenKai", "Noto Serif CJK SC", "Source Han Serif SC",
		"STSong", "SimSun", "宋体", "serif",
	]))
	body_font = _system_font(PackedStringArray([
		"STSong", "SimSun", "宋体", "Songti SC", "Songti TC",
		"Noto Serif CJK SC", "Source Han Serif SC", "Source Han Serif TC",
		"FangSong", "仿宋", "STFangsong",
		"KaiTi", "楷体", "serif",
	]))

	title_spaced = FontVariation.new()
	title_spaced.base_font = title_font
	title_spaced.spacing_glyph = 6
	title_spaced.spacing_space = 3

	var t := Theme.new()
	t.default_font = body_font
	t.default_font_size = BODY_SIZE
	self.theme = t


func _system_font(names: PackedStringArray) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = names
	f.allow_system_fallback = true
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f


# ============================================================
# 界面構建
# ============================================================
func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# ---- 宣紙底 ----
	var bg := ColorRect.new()
	bg.color = Color.WHITE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_mat := ShaderMaterial.new()
	bg_mat.shader = PAPER_SHADER
	bg_mat.set_shader_parameter("paper_top", Color("#f0e5cd"))
	bg_mat.set_shader_parameter("paper_bottom", Color("#e0d1ae"))
	bg_mat.set_shader_parameter("vignette_strength", 0.16)
	bg.material = bg_mat
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_build_header(vbox)

	# ---- 檢字行 ----
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 14)
	vbox.add_child(hbox)

	hbox.add_child(_make_label("檢字", BODY_SIZE, INK_SOFT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, title_font))

	char_input = LineEdit.new()
	char_input.custom_minimum_size = Vector2(150, 52)
	char_input.max_length = 4
	char_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_input.placeholder_text = "字"
	char_input.add_theme_font_override("font", title_font)
	char_input.add_theme_font_size_override("font_size", HEAD_SIZE)
	char_input.add_theme_color_override("font_color", INK_COLOR)
	char_input.add_theme_color_override("caret_color", ACCENT_COLOR)
	char_input.add_theme_color_override("font_placeholder_color", Color(0.63, 0.57, 0.46, 0.5))
	char_input.add_theme_stylebox_override("normal", _input_box(RULE_COLOR, 1))
	char_input.add_theme_stylebox_override("focus", _input_box(ACCENT_COLOR, 2))
	char_input.add_theme_stylebox_override("read_only", _input_box(RULE_COLOR, 1))
	hbox.add_child(char_input)

	query_btn = Button.new()
	query_btn.text = "檢　索"
	query_btn.disabled = true
	query_btn.custom_minimum_size = Vector2(0, 52)
	query_btn.add_theme_font_override("font", title_font)
	query_btn.add_theme_font_size_override("font_size", BODY_SIZE)
	query_btn.add_theme_color_override("font_color", PAPER_LIT_COLOR)
	query_btn.add_theme_color_override("font_hover_color", PAPER_LIT_COLOR)
	query_btn.add_theme_color_override("font_pressed_color", PAPER_LIT_COLOR)
	query_btn.add_theme_color_override("font_disabled_color", Color(0.93, 0.90, 0.83))
	_style_button(query_btn, ACCENT_COLOR, ACCENT_COLOR.darkened(0.18), 26, ACCENT_COLOR.lightened(0.14))
	hbox.add_child(query_btn)

	# ---- 限定行 ----
	var filter_box := HBoxContainer.new()
	filter_box.alignment = BoxContainer.ALIGNMENT_CENTER
	filter_box.add_theme_constant_override("separation", 12)
	vbox.add_child(filter_box)

	filter_box.add_child(_make_label("限定", BODY_SIZE, INK_SOFT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, title_font))

	dynasty_option = OptionButton.new()
	dynasty_option.add_item("全部")
	dynasty_option.add_item("唐")
	dynasty_option.add_item("宋")
	dynasty_option.select(0)
	dynasty_option.custom_minimum_size = Vector2(124, 44)
	dynasty_option.add_theme_font_size_override("font_size", BODY_SIZE)
	dynasty_option.add_theme_color_override("font_color", INK_COLOR)
	dynasty_option.add_theme_color_override("font_hover_color", INK_COLOR)
	dynasty_option.add_theme_color_override("font_pressed_color", INK_COLOR)
	dynasty_option.add_theme_color_override("font_focus_color", INK_COLOR)
	dynasty_option.add_theme_icon_override("arrow", _icon_chevron(GOLD_COLOR))
	var ob := _stylebox_flat(PAPER_LIT_COLOR, RULE_COLOR, 3, 1, 8)
	ob.content_margin_right = 36
	ob.content_margin_top = 6
	ob.content_margin_bottom = 6
	dynasty_option.add_theme_stylebox_override("normal", ob)
	var ob_hover := ob.duplicate() as StyleBoxFlat
	ob_hover.border_color = GOLD_COLOR
	ob_hover.bg_color = Color("#fdf8ea")
	dynasty_option.add_theme_stylebox_override("hover", ob_hover)
	dynasty_option.add_theme_stylebox_override("pressed", ob_hover)
	dynasty_option.add_theme_stylebox_override("focus", ob_hover)
	dynasty_option.add_theme_stylebox_override("disabled", ob)
	var pop := dynasty_option.get_popup()
	pop.add_theme_font_override("font", body_font)
	pop.add_theme_font_size_override("font_size", BODY_SIZE)
	pop.add_theme_color_override("font_color", INK_COLOR)
	pop.add_theme_color_override("font_hover_color", PAPER_LIT_COLOR)
	pop.add_theme_stylebox_override("panel", _stylebox_flat(PAPER_LIT_COLOR, RULE_COLOR, 4, 1, 6))
	pop.add_theme_stylebox_override("hover", _stylebox_flat(ACCENT_COLOR, ACCENT_COLOR, 3, 0, 6))
	filter_box.add_child(dynasty_option)

	filter_box.add_child(_make_label("詩人", BODY_SIZE, INK_SOFT_COLOR, HORIZONTAL_ALIGNMENT_LEFT, title_font))

	poet_input = LineEdit.new()
	poet_input.placeholder_text = "可留空"
	poet_input.custom_minimum_size = Vector2(240, 44)
	poet_input.clear_button_enabled = true
	poet_input.add_theme_font_size_override("font_size", BODY_SIZE)
	poet_input.add_theme_color_override("font_color", INK_COLOR)
	poet_input.add_theme_color_override("caret_color", ACCENT_COLOR)
	poet_input.add_theme_color_override("font_placeholder_color", Color(0.63, 0.57, 0.46, 0.5))
	poet_input.add_theme_icon_override("clear", _icon_cross(GOLD_COLOR))
	poet_input.add_theme_stylebox_override("normal", _input_box(RULE_COLOR, 1))
	poet_input.add_theme_stylebox_override("focus", _input_box(ACCENT_COLOR, 2))
	filter_box.add_child(poet_input)

	# ---- 狀態欄 ----
	status_label = _make_label("正在展卷……", SMALL_SIZE, MUTED_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(status_label)

	# ---- 書頁 ----
	result_scroll = ScrollContainer.new()
	result_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	result_scroll.clip_contents = true
	vbox.add_child(result_scroll)
	_style_scrollbar(result_scroll)

	# 右側留出卷軸欄，使書頁與捲軸互不相犯
	var page_holder := MarginContainer.new()
	page_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_holder.add_theme_constant_override("margin_right", 13)
	result_scroll.add_child(page_holder)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _page_box())
	page_holder.add_child(panel)

	var page_margin := MarginContainer.new()
	page_margin.add_theme_constant_override("margin_left", 30)
	page_margin.add_theme_constant_override("margin_right", 30)
	page_margin.add_theme_constant_override("margin_top", 22)
	page_margin.add_theme_constant_override("margin_bottom", 26)
	panel.add_child(page_margin)

	result_label = RichTextLabel.new()
	result_label.bbcode_enabled = true
	result_label.fit_content = true
	result_label.scroll_active = false
	result_label.meta_underlined = false
	result_label.selection_enabled = true
	result_label.add_theme_font_override("normal_font", body_font)
	result_label.add_theme_font_override("bold_font", title_font)
	result_label.add_theme_color_override("default_color", INK_COLOR)
	result_label.add_theme_font_size_override("normal_font_size", BODY_SIZE)
	result_label.add_theme_font_size_override("bold_font_size", BODY_SIZE)
	result_label.add_theme_constant_override("line_separation", 9)
	page_margin.add_child(result_label)

	# ---- 扉頁（未檢字時，居中）----
	welcome_box = VBoxContainer.new()
	welcome_box.alignment = BoxContainer.ALIGNMENT_CENTER
	welcome_box.add_theme_constant_override("separation", 16)
	welcome_box.mouse_filter = Control.MOUSE_FILTER_PASS
	page_margin.add_child(welcome_box)

	welcome_box.add_child(_make_label("詩　韻", 84, Color("#d8c8a6"), HORIZONTAL_ALIGNMENT_CENTER, body_font))
	welcome_box.add_child(_make_label("檢一字　考其韻部　徵唐宋之句",
		SUBTITLE_SIZE, INK_SOFT_COLOR, HORIZONTAL_ALIGNMENT_CENTER, body_font))

	var wgap := Control.new()
	wgap.custom_minimum_size = Vector2(0, 28)
	welcome_box.add_child(wgap)

	welcome_box.add_child(_make_label("試　檢", TINY_SIZE, MUTED_COLOR, HORIZONTAL_ALIGNMENT_CENTER))

	welcome_links = RichTextLabel.new()
	welcome_links.bbcode_enabled = true
	welcome_links.fit_content = true
	welcome_links.scroll_active = false
	welcome_links.selection_enabled = false
	welcome_links.add_theme_font_override("normal_font", body_font)
	welcome_links.add_theme_font_size_override("normal_font_size", BODY_SIZE)
	welcome_links.meta_clicked.connect(_on_meta_clicked)
	welcome_links.meta_hover_started.connect(_on_meta_hover_started)
	welcome_links.meta_hover_ended.connect(_on_meta_hover_ended)
	var ex_line := ""
	for c in ["春", "風", "月", "雪", "山", "水", "雲", "花", "秋", "夜"]:
		ex_line += "[url=char:%s][color=#9c2b21]%s[/color][/url]　" % [c, c]
	welcome_links.text = "[center][font_size=%d]%s[/font_size][/center]" % [BODY_SIZE, ex_line]
	welcome_box.add_child(welcome_links)

	# ---- 續覽 ----
	more_btn = Button.new()
	more_btn.text = "續　覽"
	more_btn.visible = false
	more_btn.custom_minimum_size = Vector2(0, 46)
	more_btn.add_theme_font_override("font", title_font)
	more_btn.add_theme_font_size_override("font_size", SMALL_SIZE)
	more_btn.add_theme_color_override("font_color", ACCENT_COLOR)
	_style_button(more_btn, Color(0, 0, 0, 0), GOLD_COLOR, 24, ACCENT_COLOR, PAPER_LIT_COLOR, 2)
	vbox.add_child(more_btn)

	# ---- 藏書印（右上）----
	var seal := Seal.new()
	seal.font = title_font
	seal.chars = PackedStringArray(["詩", "韻"])
	seal.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	seal.offset_left = -86.0
	seal.offset_top = 30.0
	seal.offset_right = -42.0
	seal.offset_bottom = 92.0
	add_child(seal)

	# ---- 外框 ----
	var frame := DecoFrame.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(frame)


func _build_header(vbox: VBoxContainer) -> void:
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 22)
	vbox.add_child(title_row)

	var left_rule := Ornament.new()
	left_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_rule.custom_minimum_size = Vector2(80, 26)
	title_row.add_child(left_rule)

	var title := _make_label("全唐宋詩 · 平水韻", TITLE_SIZE, INK_COLOR, HORIZONTAL_ALIGNMENT_CENTER, title_spaced)
	title_row.add_child(title)

	var right_rule := Ornament.new()
	right_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_rule.custom_minimum_size = Vector2(80, 26)
	title_row.add_child(right_rule)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(gap)

	vbox.add_child(_make_label("輸入一字　考其韻部　徵唐宋之句",
		SUBTITLE_SIZE, INK_SOFT_COLOR, HORIZONTAL_ALIGNMENT_CENTER, body_font))


func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.16, 0.11, 0.06, 0.52)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	overlay.add_child(margin)

	# 外頁
	var outer := PanelContainer.new()
	outer.add_theme_stylebox_override("panel", _page_box(RULE_COLOR, 2, 10))
	margin.add_child(outer)

	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 7)
	outer_margin.add_theme_constant_override("margin_right", 7)
	outer_margin.add_theme_constant_override("margin_top", 7)
	outer_margin.add_theme_constant_override("margin_bottom", 7)
	outer.add_child(outer_margin)

	# 內頁（雙欄）
	var inner := PanelContainer.new()
	var inner_box := _stylebox_flat(Color(0, 0, 0, 0), RULE_COLOR, 3, 1, 0)
	inner.add_theme_stylebox_override("panel", inner_box)
	outer_margin.add_child(inner)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 26)
	body_margin.add_theme_constant_override("margin_right", 26)
	body_margin.add_theme_constant_override("margin_top", 18)
	body_margin.add_theme_constant_override("margin_bottom", 16)
	inner.add_child(body_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	body_margin.add_child(vbox)

	# 書名行
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	vbox.add_child(head)

	var head_left := Control.new()
	head_left.custom_minimum_size = Vector2(86, 0)
	head.add_child(head_left)

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 2)
	head.add_child(titles)

	dialog_title = _make_label("", HEAD_SIZE, ACCENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER, title_font)
	dialog_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(dialog_title)

	dialog_author = _make_label("", SMALL_SIZE, MUTED_COLOR, HORIZONTAL_ALIGNMENT_CENTER, body_font)
	titles.add_child(dialog_author)

	var close_btn := Button.new()
	close_btn.text = "掩卷"
	close_btn.custom_minimum_size = Vector2(86, 0)
	close_btn.add_theme_font_override("font", title_font)
	close_btn.add_theme_font_size_override("font_size", SMALL_SIZE)
	close_btn.add_theme_color_override("font_color", INK_SOFT_COLOR)
	_style_button(close_btn, Color(0, 0, 0, 0), RULE_COLOR, 14, ACCENT_COLOR, PAPER_LIT_COLOR, 1)
	head.add_child(close_btn)
	close_btn.pressed.connect(_hide_overlay)

	var rule := Ornament.new()
	rule.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(rule)

	# 正文
	var body_scroll := ScrollContainer.new()
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(body_scroll)
	_style_scrollbar(body_scroll)

	dialog_body = RichTextLabel.new()
	dialog_body.bbcode_enabled = true
	dialog_body.scroll_active = false
	dialog_body.fit_content = true
	dialog_body.selection_enabled = true
	dialog_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_body.add_theme_font_override("normal_font", body_font)
	dialog_body.add_theme_font_override("bold_font", title_font)
	dialog_body.add_theme_color_override("default_color", INK_COLOR)
	dialog_body.add_theme_font_size_override("normal_font_size", BODY_SIZE)
	dialog_body.add_theme_constant_override("line_separation", 13)
	body_scroll.add_child(dialog_body)

	var foot := _make_label("按 Esc 鍵，或點「掩卷」返回", TINY_SIZE, MUTED_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(foot)


# ============================================================
# 信號
# ============================================================
func _wire_signals() -> void:
	query_btn.pressed.connect(_on_query_pressed)
	more_btn.pressed.connect(_on_more_pressed)
	char_input.text_submitted.connect(_on_text_submitted)
	char_input.text_changed.connect(_on_input_changed)
	dynasty_option.item_selected.connect(_on_dynasty_selected)
	poet_input.text_changed.connect(_on_poet_changed)
	poet_input.text_submitted.connect(_on_text_submitted)
	result_label.meta_clicked.connect(_on_meta_clicked)
	result_label.meta_hover_started.connect(_on_meta_hover_started)
	result_label.meta_hover_ended.connect(_on_meta_hover_ended)


func _on_text_submitted(_t: String) -> void:
	_on_query_pressed()


func _on_input_changed(new_text: String) -> void:
	var ch := DataStore.first_hanzi(new_text)
	if ch != "" and ch != new_text:
		char_input.text = ch
		char_input.caret_column = ch.length()


func _on_dynasty_selected(idx: int) -> void:
	dynasty_filter = idx  # 0=全部, 1=唐, 2=宋
	_requery_if_active()


func _on_poet_changed(txt: String) -> void:
	author_filter = txt.strip_edges()
	_requery_if_active()


func _requery_if_active() -> void:
	if current_query_char != "" and rhyme_ready:
		current_display_count = PAGE_SIZE
		_render_result(current_query_char)


func _unhandled_input(event: InputEvent) -> void:
	if overlay != null and overlay.visible and event.is_action_pressed("ui_cancel"):
		_hide_overlay()
		get_viewport().set_input_as_handled()


# ============================================================
# 數據加載
# ============================================================
func _load_all_data() -> void:
	_set_status("正在展卷 · 校《平水韻》……")
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	store.load_rhyme(DataStore.YUN_PATH)
	rhyme_ready = true
	query_btn.disabled = false
	_set_status("韻部已就 · 詩句索引校錄中……")

	await get_tree().process_frame
	if not is_instance_valid(self):
		return

	if not store.load_binary(DataStore.INDEX_PATH):
		await _load_poems_json_fallback()

	if not is_instance_valid(self):
		return

	poems_ready = true
	_set_status("就緒 · 詩 %s 首 · 句 %s 條 · 平水韻字 %s 個" % [
		_fmt(store.poem_total()),
		_fmt(store.sentence_total()),
		_fmt(store.rhyme_index.size()),
	])
	if current_query_char != "":
		_render_result(current_query_char)
	else:
		_render_welcome()
	char_input.grab_focus()


func _load_poems_json_fallback() -> void:
	var dir := DirAccess.open(DataStore.SHI_DIR)
	if dir == null:
		push_error("無法打開目錄：" + DataStore.SHI_DIR)
		return

	var files := dir.get_files()
	files.sort()
	var poem_files: Array[String] = []
	for fname in files:
		if DataStore.dynasty_of_filename(fname) != DataStore.DYN_ALL:
			poem_files.append(fname)

	var total := poem_files.size()
	var processed := 0
	for fname in poem_files:
		var dyn := DataStore.dynasty_of_filename(fname)
		var text := DataStore.read_text(DataStore.SHI_DIR + fname)
		if not text.is_empty():
			store.add_poem_file(text, dyn)
		processed += 1
		_set_status("正在展卷 · 校《全唐宋詩》…… %d%%" % int(processed * 100.0 / maxi(1, total)))
		await get_tree().process_frame
		if not is_instance_valid(self):
			return


# ============================================================
# 查詢與渲染
# ============================================================
func _on_query_pressed() -> void:
	if not rhyme_ready:
		_set_status("書頁未展 · 請稍候……")
		return
	var ch := DataStore.first_hanzi(char_input.text)
	if ch.is_empty():
		_set_status("請先檢一字。")
		return
	char_input.text = ch
	_set_status("所檢之字：「%s」" % ch)
	current_rhyme_name = ""
	current_query_char = ch
	current_display_count = PAGE_SIZE
	_render_result(ch)


func _scope_text() -> String:
	var a := author_filter.strip_edges()
	if not a.is_empty():
		return "「%s」詩中" % a
	match dynasty_filter:
		DataStore.DYN_TANG:
			return "全唐詩中"
		DataStore.DYN_SONG:
			return "全宋詩中"
		_:
			return "全唐宋詩中"


func _render_welcome() -> void:
	more_btn.visible = false
	current_ids = PackedInt32Array()
	result_label.text = ""
	result_label.visible = false
	welcome_box.visible = true


func _render_result(ch: String) -> void:
	welcome_box.visible = false
	result_label.visible = true
	current_ids = store.get_sentence_ids(ch, dynasty_filter, author_filter.strip_edges())

	var bb := ""

	# ---------- 字頭 ----------
	bb += "[center][font_size=%d][color=#9c2b21][b]%s[/b][/color][/font_size][/center]\n" % [
		HEAD_SIZE, _esc(ch)
	]

	# ---------- 韻部 ----------
	var rhymes: Array = store.rhyme_index.get(ch, [])
	if rhymes.is_empty():
		bb += "[center][font_size=%d][color=#5b4f42]平水韻未收此字[/color][/font_size][/center]\n" % SMALL_SIZE
	else:
		var marks := PackedStringArray()
		for r in rhymes:
			var mk := "%s · %s" % [str(r["tone"]), str(r["group"])]
			if not marks.has(mk):
				marks.append(mk)
		bb += "[center][font_size=%d][color=#5b4f42]平水韻 · %s[/color][/font_size][/center]\n" % [
			SMALL_SIZE, _esc("　".join(marks))
		]
		for r in rhymes:
			var rname := str(r["name"])
			bb += "[center][url=rhyme:%s][font_size=%d][color=#9c2b21][b]%s[/b][/color][/font_size][/url][/center]\n" % [
				rname, BODY_SIZE, _esc(rname)
			]
		bb += "[center][font_size=%d][color=#a08f74]按韻目之名，可展其全部字[/color][/font_size][/center]\n" % TINY_SIZE

	# ---------- 韻部字展開區 ----------
	if current_rhyme_name != "":
		var chars: Array = store.rhyme_chars.get(current_rhyme_name, [])
		if not chars.is_empty():
			bb += _divider_bb()
			bb += "[center][font_size=%d][color=#5b4f42]「%s」韻 · 共 %d 字[/color][/font_size][/center]\n" % [
				SMALL_SIZE, _esc(current_rhyme_name), chars.size()
			]
			var line := ""
			for c in chars:
				var cc := str(c)
				line += "[url=char:%s][color=#9c2b21]%s[/color][/url] " % [cc, _esc(cc)]
			bb += "[center][font_size=%d]%s[/font_size][/center]\n" % [BODY_SIZE, line]

	# ---------- 詩句 ----------
	if not poems_ready:
		bb += _divider_bb()
		bb += "[center][font_size=%d][color=#5b4f42]%s以「%s」收尾之句[/color][/font_size][/center]\n" % [
			SMALL_SIZE, _scope_text(), _esc(ch)
		]
		bb += "[center][font_size=%d][color=#a08f74]詩句索引校錄中，請稍候……[/color][/font_size][/center]\n" % TINY_SIZE
		more_btn.visible = false
		result_label.text = bb
		return

	bb += _divider_bb()
	bb += "[center][font_size=%d][color=#5b4f42]%s以「%s」收尾之句　共 %s 句[/color][/font_size][/center]\n" % [
		SMALL_SIZE, _scope_text(), _esc(ch), _fmt(current_ids.size())
	]
	if current_ids.is_empty():
		bb += "\n[center][font_size=%d][color=#a08f74]未得%s以「%s」收尾之句[/color][/font_size][/center]\n" % [
			SMALL_SIZE, _scope_text(), _esc(ch)
		]
		more_btn.visible = false
		result_label.text = bb
		return

	bb += "[center][font_size=%d][color=#a08f74]點按句末出處，可覽全篇[/color][/font_size][/center]\n" % TINY_SIZE

	var shown := mini(current_ids.size(), current_display_count)
	for i in shown:
		bb += _sentence_bb(current_ids[i])

	result_label.text = bb
	_update_more_button()


func _divider_bb() -> String:
	return "[center][color=#cbb78f][font_size=%d]───────────◆───────────[/font_size][/color][/center]\n" % TINY_SIZE


func _sentence_bb(sid: int) -> String:
	var txt := store.get_sentence(sid)
	var pid := store.get_sentence_poem_id(sid)
	var title := _esc(store.get_poem_title(pid))
	var author := _esc(store.get_poem_author(pid))
	var src := "《%s》" % title
	if not author.is_empty():
		src = author + " · " + src
	return "[url=poem:%d][color=#b08d4f][font_size=17]〇[/font_size][/color]  [color=#241d16][font_size=%d]%s[/font_size][/color]  [color=#a08f74][font_size=%d]%s[/font_size][/color][/url]\n" % [
		sid, BODY_SIZE, _esc(txt), SMALL_SIZE, src
	]


func _update_more_button() -> void:
	var total := current_ids.size()
	var shown := mini(total, current_display_count)
	if total > shown:
		more_btn.visible = true
		more_btn.text = "續　覽　（已見 %s ／ 共 %s 句）" % [_fmt(shown), _fmt(total)]
	else:
		more_btn.visible = false
		result_label.append_text("\n[center][font_size=%d][color=#a08f74]—— 卷終 · 通計 %s 句 ——[/color][/font_size][/center]\n" % [
			TINY_SIZE, _fmt(total)
		])


func _on_more_pressed() -> void:
	var old := current_display_count
	current_display_count += PAGE_SIZE
	var shown := mini(current_ids.size(), current_display_count)
	var more_bb := ""
	for i in range(old, shown):
		more_bb += _sentence_bb(current_ids[i])
	result_label.append_text(more_bb)
	_update_more_button()


# ============================================================
# meta 點擊：rhyme / char / poem
# ============================================================
func _on_meta_hover_started(meta) -> void:
	var s := str(meta)
	if s.begins_with("poem:"):
		var sid := int(s.substr(5))
		var pid := store.get_sentence_poem_id(sid)
		var author := store.get_poem_author(pid)
		if author.is_empty():
			author = "佚名"
		_set_status("《%s》%s · 點按可覽全篇" % [store.get_poem_title(pid), author])
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	elif s.begins_with("rhyme:"):
		_set_status("按此可展「%s」韻之全部字" % s.substr(6))
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	elif s.begins_with("char:"):
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)


func _on_meta_hover_ended(_meta) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if current_query_char != "":
		_set_status("所檢之字：「%s」" % current_query_char)


func _on_meta_clicked(meta) -> void:
	var s := str(meta)

	if s.begins_with("rhyme:"):
		var rname := s.substr(6)
		if current_rhyme_name == rname:
			current_rhyme_name = ""
		else:
			current_rhyme_name = rname
		_render_result(current_query_char)
		return

	if s.begins_with("char:"):
		var c := s.substr(5)
		char_input.text = c
		_on_query_pressed()
		return

	if s.begins_with("poem:"):
		var sid := int(s.substr(5))
		_show_poem(sid)


# ============================================================
# 全詩彈層（含目標句高亮）
# ============================================================
func _show_poem(sid: int) -> void:
	if sid < 0 or sid >= store.sentence_total():
		return
	var pid := store.get_sentence_poem_id(sid)
	if pid < 0 or pid >= store.poem_total():
		return
	var author := store.get_poem_author(pid)
	if author.is_empty():
		author = "佚名"

	dialog_title.text = "《%s》" % _esc(store.get_poem_title(pid))
	dialog_author.text = author

	var body: String = store.get_poem_body(pid).strip_edges()
	# 逐句縮進，取其書頁之貌
	var lines := body.split("\n", false)
	var indented := PackedStringArray()
	for ln in lines:
		var t := ln.strip_edges()
		if not t.is_empty():
			indented.append("　　" + t)
	var esc_body := _esc("\n".join(indented))

	# 找到觸發查詢的那一句，用朱色底包裹
	var target := store.get_sentence(sid)
	var esc_target := _esc("　　" + target)
	var pos := esc_body.find(esc_target)
	if pos < 0:
		esc_target = _esc(target)
		pos = esc_body.find(esc_target)
	if pos >= 0:
		var hl_open := "[bgcolor=#%s]" % HIGHLIGHT_COLOR.to_html(false)
		esc_body = esc_body.substr(0, pos) \
			+ hl_open + esc_target + "[/bgcolor]" \
			+ esc_body.substr(pos + esc_target.length())

	dialog_body.text = esc_body
	overlay.visible = true
	overlay.modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(overlay, "modulate", Color(1, 1, 1, 1), 0.16)
	await get_tree().process_frame
	if is_instance_valid(dialog_body):
		dialog_body.scroll_to_line(0)


func _hide_overlay() -> void:
	overlay.visible = false


# ============================================================
# 控件工廠
# ============================================================
func _make_label(text: String, size: int, color: Color, align: HorizontalAlignment, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _stylebox_flat(bg: Color, border: Color, radius: int, border_width: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


func _input_box(border: Color, width: int) -> StyleBoxFlat:
	var sb := _stylebox_flat(PAPER_LIT_COLOR, border, 3, width, 10)
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _page_box(border: Color = RULE_COLOR, width: int = 1, radius: int = 4) -> StyleBoxFlat:
	var sb := _stylebox_flat(PAPER_LIT_COLOR, border, radius, width, 0)
	sb.shadow_color = Color(0.24, 0.17, 0.09, 0.20)
	sb.shadow_size = 7
	sb.shadow_offset = Vector2(0, 3)
	return sb


func _style_button(btn: Button, bg: Color, border: Color,
		pad_x: int, hover_bg: Color = ACCENT_COLOR, hover_fg: Color = PAPER_LIT_COLOR,
		border_w: int = 0) -> void:
	var normal := _stylebox_flat(bg, border, 3, border_w, 12)
	normal.content_margin_left = pad_x
	normal.content_margin_right = pad_x
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = hover_bg
	hover.border_color = hover_bg
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = hover_bg.darkened(0.15)
	pressed.border_color = pressed.bg_color
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("#bcae94")
	disabled.border_color = Color("#bcae94")
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_color_override("font_hover_color", hover_fg)
	btn.add_theme_color_override("font_pressed_color", hover_fg)


func _style_scrollbar(scroll: ScrollContainer) -> void:
	var vsb := scroll.get_v_scroll_bar()
	# 轨道留白 + 滑块最小尺寸，使卷軸在窄條上也清晰可見
	var track := _stylebox_flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 0, 0)
	track.content_margin_left = 5
	track.content_margin_right = 5
	var grab := _stylebox_flat(Color("#c2a068"), Color(0, 0, 0, 0), 3, 0, 0)
	grab.content_margin_left = 3
	grab.content_margin_right = 3
	grab.content_margin_top = 11
	grab.content_margin_bottom = 11
	var grab_hl := grab.duplicate() as StyleBoxFlat
	grab_hl.bg_color = ACCENT_COLOR
	var grab_pr := grab.duplicate() as StyleBoxFlat
	grab_pr.bg_color = ACCENT_DEEP
	vsb.add_theme_stylebox_override("scroll", track)
	vsb.add_theme_stylebox_override("scroll_focus", track)
	vsb.add_theme_stylebox_override("grabber", grab)
	vsb.add_theme_stylebox_override("grabber_highlight", grab_hl)
	vsb.add_theme_stylebox_override("grabber_pressed", grab_pr)


func _icon_chevron(col: Color, s: int = 15) -> ImageTexture:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var h: int = maxi(2, int(s * 0.30))
	var top := int((s - h) / 2.0)
	for y in h:
		var half := int(round(float(h - 1 - y) * (s * 0.34) / maxf(1.0, float(h - 1))))
		for x in range(-half, half + 1):
			img.set_pixel(clampi(s / 2 + x, 0, s - 1), top + y, col)
	return ImageTexture.create_from_image(img)


func _icon_cross(col: Color, s: int = 13) -> ImageTexture:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in s:
		img.set_pixel(i, i, col)
		img.set_pixel(s - 1 - i, i, col)
		if i + 1 < s:
			img.set_pixel(i + 1, i, col)
			img.set_pixel(s - 2 - i, i, col)
	return ImageTexture.create_from_image(img)


# ============================================================
# 工具
# ============================================================
func _set_status(s: String) -> void:
	if status_label != null:
		status_label.text = s


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
