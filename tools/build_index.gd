extends SceneTree
## 构建脚本：把 data/shi/poet.*.json 预编译为 data/index.bin 二进制索引。
## 运行方式：
##   godot --headless --path <项目路径> --script res://tools/build_index.gd

const DataStore := preload("res://DataStore.gd")


func _init() -> void:
	print("开始构建索引……")
	var ds := DataStore.new()

	var dir := DirAccess.open(DataStore.SHI_DIR)
	if dir == null:
		print("无法打开目录：" + DataStore.SHI_DIR)
		quit(1)
		return

	var files := dir.get_files()
	files.sort()

	var total := 0
	for fname in files:
		var dyn := DataStore.dynasty_of_filename(fname)
		if dyn == DataStore.DYN_ALL:
			continue
		var text := DataStore.read_text(DataStore.SHI_DIR + fname)
		if text.is_empty():
			continue
		var added := ds.add_poem_file(text, dyn)
		total += added
		if total % 20000 < added:  # 跨过 2 万的整数倍时打印一次
			print("  已处理 %d 首诗……" % total)

	if total == 0:
		print("未找到任何诗集 JSON。")
		quit(1)
		return

	var f := FileAccess.open(DataStore.INDEX_PATH, FileAccess.WRITE)
	if f == null:
		print("无法写入索引文件：" + DataStore.INDEX_PATH)
		quit(1)
		return
	f.store_var(ds.serialize())
	f.close()

	print("完成：诗 %d 首 · 句 %d 条 · 尾字键 %d 个" % [
		ds.poem_total(), ds.sentence_total(), ds.last_char_index.size()
	])
	print("已写入：" + DataStore.INDEX_PATH)
	quit(0)
