extends SceneTree
## 自测脚本：验证数据加载、查询、朝代/诗人筛选、正文重建、转义与字体。
## 运行：godot --headless --path <项目> --script res://tools/selftest.gd

const DataStore := preload("res://DataStore.gd")

var _fails := 0


func _init() -> void:
	_run()


func _check(name: String, cond: bool) -> void:
	if cond:
		print("PASS  ", name)
	else:
		print("FAIL  ", name)
		_fails += 1


func _run() -> void:
	# 1) 直接验证二进制索引反序列化
	var ds := DataStore.new()
	var ok := ds.load_binary(DataStore.INDEX_PATH)
	_check("binary index loads", ok)
	_check("poem total == 311855", ds.poem_total() == 311855)
	_check("sentence total == 1365284", ds.sentence_total() == 1365284)
	_check("last-char keys == 8996", ds.last_char_index.size() == 8996)

	var all := ds.get_sentence_ids("春", DataStore.DYN_ALL, "")
	var tang := ds.get_sentence_ids("春", DataStore.DYN_TANG, "")
	var song := ds.get_sentence_ids("春", DataStore.DYN_SONG, "")
	_check("query 春 has results", all.size() > 0)
	_check("tang+song == all", tang.size() + song.size() == all.size())
	_check("tang != song", tang.size() != song.size())

	# 2) 诗人筛选：所有命中句必须属于「李白」
	var lb := ds.get_sentence_ids("春", DataStore.DYN_ALL, "李白")
	var all_lb_ok := true
	for sid in lb:
		if ds.get_poem_author(ds.get_sentence_poem_id(sid)) != "李白":
			all_lb_ok = false
			break
	_check("李白 filter only returns 李白 poems", lb.size() > 0 and all_lb_ok)

	# 3) 正文重建：正文应包含目标句
	if all.size() > 0:
		var sid: int = all[0]
		var pid := ds.get_sentence_poem_id(sid)
		var body := ds.get_poem_body(pid)
		var sent := ds.get_sentence(sid)
		_check("body reconstruction contains sentence", body.find(sent) >= 0)

	# 4) 转义
	_check("_esc escapes '['", "[lb]" in _esc("[一]"))

	# 5) 挂载主场景，验证 UI 与渲染
	var scene: Node = (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var main: Control = scene

	var timeout := 1200
	while timeout > 0 and not main.poems_ready:
		await process_frame
		timeout -= 1
	_check("main scene data ready", main.poems_ready)
	_check("main poem total matches", main.store.poem_total() == 311855)

	main.char_input.text = "春"
	main._on_query_pressed()
	_check("result contains rhyme header", "平水韻" in main.result_label.text)
	_check("result contains rhyme group", "上平聲部" in main.result_label.text)
	_check("result contains scope 全唐宋詩", "全唐宋詩" in main.result_label.text)
	_check("result cites poem source", "《" in main.result_label.text)

	# 朝代筛选 -> 全唐詩
	main.dynasty_filter = DataStore.DYN_TANG
	main.author_filter = ""
	main._on_query_pressed()
	_check("tang filter shows 全唐詩", "全唐詩中" in main.result_label.text)

	# 诗人筛选
	main.dynasty_filter = DataStore.DYN_ALL
	main.author_filter = "李白"
	main._on_query_pressed()
	_check("poet filter shows 李白", "「李白」詩中" in main.result_label.text)

	# 6) 加载更多（增量渲染）
	main.dynasty_filter = DataStore.DYN_ALL
	main.author_filter = ""
	main._on_query_pressed()
	if main.more_btn.visible:
		var before_count: int = main.current_display_count
		var before_len: int = main.result_label.get_parsed_text().length()
		main._on_more_pressed()
		_check("more increments page", main.current_display_count == before_count + 600)
		_check("more appends text", main.result_label.get_parsed_text().length() > before_len)
	else:
		print("  (春 结果不足一页，跳过加载更多)")

	# 7) 字体层级：正文用宋、标题用楷，且正文按 BODY_SIZE 渲染
	main.dynasty_filter = DataStore.DYN_ALL
	main.author_filter = ""
	main._on_query_pressed()
	_check("body font size applied", ("[font_size=%d]" % main.BODY_SIZE) in main.result_label.text)
	_check("serif body font applied", main.result_label.get_theme_font("normal_font") == main.body_font)
	_check("kai title font applied", main.result_label.get_theme_font("bold_font") == main.title_font)

	# 8) 韵部字可点击跳转查询
	main.current_query_char = "春"
	main.current_rhyme_name = "上平聲一東"
	main._render_result("春")
	_check("rhyme chars are clickable", "[url=char:" in main.result_label.text)
	main._on_meta_clicked("char:東")
	_check("char click jumps to query", main.current_query_char == "東" and main.char_input.text == "東")

	# 9) 全詩彈層開闔與高亮
	var any_ids := ds.get_sentence_ids("春", DataStore.DYN_ALL, "")
	main._show_poem(any_ids[0])
	_check("overlay opens with poem title", main.overlay.visible and main.dialog_title.text.begins_with("《"))
	_check("overlay highlights target line", main.dialog_body.text.find("[bgcolor=") >= 0)
	main._hide_overlay()
	_check("overlay closes", not main.overlay.visible)

	# 10) 扉頁備用層在查詢後隱藏
	main.char_input.text = "春"
	main._on_query_pressed()
	_check("welcome layer hidden after query", not main.welcome_box.visible and main.result_label.visible)

	print("")
	if _fails == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILURES: ", _fails)
		quit(1)


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")
