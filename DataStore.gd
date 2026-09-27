extends RefCounted
## DataStore — 纯数据层：负责《平水韵》与《全唐宋诗》索引的
## 加载（二进制索引优先，JSON 兜底）、序列化与查询。
##
## 数据结构采用平行 PackedArray（而非 Array[Dictionary]），
## 且「诗正文」不再重复存储，改为按句重建，以降低内存占用。

const SCHEMA := 2

# 朝代
const DYN_ALL := 0
const DYN_TANG := 1
const DYN_SONG := 2

const SHI_DIR := "res://data/shi/"
const YUN_PATH := "res://data/yun/pingshuiyun.json"
const INDEX_PATH := "res://data/index.bin"

# ---- 诗级数据（平行数组，索引即 pid）----
var poem_title: PackedStringArray = PackedStringArray()
var poem_author: PackedStringArray = PackedStringArray()
var poem_dynasty: PackedInt32Array = PackedInt32Array()   # DYN_TANG / DYN_SONG
var poem_start: PackedInt32Array = PackedInt32Array()     # 该诗首句在句数组中的下标
var poem_count: PackedInt32Array = PackedInt32Array()     # 该诗包含的句数

# ---- 句级数据 ----
var sentence_text: PackedStringArray = PackedStringArray()   # 每句（含句末标点）
var sentence_poem: PackedInt32Array = PackedInt32Array()     # 句 -> 诗 id

# 末字 -> 句 id 列表
var last_char_index: Dictionary = {}

# ---- 平水韵 ----
var rhyme_index: Dictionary = {}     # 字 -> Array[{tone, group, name}]
var rhyme_chars: Dictionary = {}     # 韵部名 -> Array[字]


# ============================================================
# 查询
# ============================================================
func poem_total() -> int:
	return poem_title.size()


func sentence_total() -> int:
	return sentence_text.size()


func get_poem_title(pid: int) -> String:
	return poem_title[pid]


func get_poem_author(pid: int) -> String:
	return poem_author[pid]


func get_poem_body(pid: int) -> String:
	var start := poem_start[pid]
	var cnt := poem_count[pid]
	var parts := PackedStringArray()
	for i in cnt:
		parts.append(sentence_text[start + i])
	return "\n".join(parts)


func get_sentence(sid: int) -> String:
	return sentence_text[sid]


func get_sentence_poem_id(sid: int) -> int:
	return sentence_poem[sid]


func get_sentence_ids(ch: String, dynasty: int, author: String) -> PackedInt32Array:
	var all: PackedInt32Array = last_char_index.get(ch, PackedInt32Array())
	if dynasty == DYN_ALL and author.is_empty():
		return all
	var out := PackedInt32Array()
	for sid in all:
		var pid := sentence_poem[sid]
		if dynasty != DYN_ALL and poem_dynasty[pid] != dynasty:
			continue
		if not author.is_empty() and poem_author[pid].find(author) == -1:
			continue
		out.append(sid)
	return out


# ============================================================
# 加载：平水韵
# ============================================================
func load_rhyme(path: String) -> bool:
	var text := read_text(path)
	if text.is_empty():
		return false
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("pingshuiyun.json 解析失败：第 %d 行 %s" % [
			json.get_error_line(), json.get_error_message()
		])
		return false
	var root = json.data
	if typeof(root) != TYPE_DICTIONARY:
		push_error("pingshuiyun.json 根节点不是字典")
		return false
	_walk_rhyme(root.get("ping", {}), "平聲")
	_walk_rhyme(root.get("ze", {}), "仄聲")
	return true


func _walk_rhyme(section, tone: String) -> void:
	if typeof(section) != TYPE_DICTIONARY:
		return
	for group_name in section.keys():
		var groups = section[group_name]
		if typeof(groups) != TYPE_DICTIONARY:
			continue
		for rhyme_name in groups.keys():
			var arr = groups[rhyme_name]
			if typeof(arr) != TYPE_ARRAY:
				continue
			var rname := str(rhyme_name)
			for chunk in arr:
				if typeof(chunk) != TYPE_STRING:
					continue
				var chunk_str: String = chunk
				for i in chunk_str.length():
					var ch: String = chunk_str[i]
					if is_cjk_char(ch):
						_add_rhyme(ch, tone, str(group_name), rname)


func _add_rhyme(ch: String, tone: String, group_name: String, rhyme_name: String) -> void:
	var list: Array = rhyme_index.get(ch, [])
	var exists := false
	for item in list:
		if item["tone"] == tone and item["group"] == group_name and item["name"] == rhyme_name:
			exists = true
			break
	if not exists:
		list.append({"tone": tone, "group": group_name, "name": rhyme_name})
		rhyme_index[ch] = list

	var chars: Array = rhyme_chars.get(rhyme_name, [])
	if not chars.has(ch):
		chars.append(ch)
		rhyme_chars[rhyme_name] = chars


# ============================================================
# 加载：诗（二进制索引）
# ============================================================
func load_binary(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data = f.get_var(false)
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return false
	return deserialize(data)


func deserialize(d: Dictionary) -> bool:
	if int(d.get("schema", -1)) != SCHEMA:
		return false
	var t = d.get("title", null)
	var a = d.get("author", null)
	var dy = d.get("dynasty", null)
	var st = d.get("start", null)
	var ct = d.get("count", null)
	var sx = d.get("sent_text", null)
	var sp = d.get("sent_poem", null)
	var lc = d.get("last_char", null)
	if typeof(t) != TYPE_PACKED_STRING_ARRAY \
		or typeof(a) != TYPE_PACKED_STRING_ARRAY \
		or typeof(dy) != TYPE_PACKED_INT32_ARRAY \
		or typeof(st) != TYPE_PACKED_INT32_ARRAY \
		or typeof(ct) != TYPE_PACKED_INT32_ARRAY \
		or typeof(sx) != TYPE_PACKED_STRING_ARRAY \
		or typeof(sp) != TYPE_PACKED_INT32_ARRAY \
		or typeof(lc) != TYPE_DICTIONARY:
		return false
	poem_title = t
	poem_author = a
	poem_dynasty = dy
	poem_start = st
	poem_count = ct
	sentence_text = sx
	sentence_poem = sp
	last_char_index = lc
	return true


func serialize() -> Dictionary:
	return {
		"schema": SCHEMA,
		"title": poem_title,
		"author": poem_author,
		"dynasty": poem_dynasty,
		"start": poem_start,
		"count": poem_count,
		"sent_text": sentence_text,
		"sent_poem": sentence_poem,
		"last_char": last_char_index,
	}


# ============================================================
# 加载：诗（JSON 兜底，由调用方按文件驱动以允许 yield）
# ============================================================
func add_poem_file(text: String, dynasty: int) -> int:
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("JSON 解析失败")
		return 0
	var arr = json.data
	if typeof(arr) != TYPE_ARRAY:
		return 0
	var added := 0
	for item in arr:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var title := str(d.get("title", "无题"))
		var author := str(d.get("author", ""))
		var paras = d.get("paragraphs", [])
		if typeof(paras) != TYPE_ARRAY:
			continue

		var pid := poem_title.size()
		var start := sentence_text.size()
		var cnt := 0
		poem_title.append(title)
		poem_author.append(author)
		poem_dynasty.append(dynasty)
		poem_start.append(start)
		poem_count.append(0)  # 占位，处理完段落后回填

		for para in paras:
			if typeof(para) != TYPE_STRING:
				continue
			var p: String = para.strip_edges()
			if p.is_empty():
				continue
			for seg in split_sentences(p):
				var s: String = seg.strip_edges()
				if s.is_empty():
					continue
				var last := last_hanzi(s)
				if last.is_empty():
					continue
				var sid := sentence_text.size()
				sentence_text.append(s)
				sentence_poem.append(pid)
				var bucket: PackedInt32Array = last_char_index.get(last, PackedInt32Array())
				bucket.append(sid)
				last_char_index[last] = bucket
				cnt += 1
		poem_count[pid] = cnt
		added += 1
	return added


# ============================================================
# 静态工具
# ============================================================
static func dynasty_of_filename(fname: String) -> int:
	if fname.begins_with("poet.tang."):
		return DYN_TANG
	if fname.begins_with("poet.song."):
		return DYN_SONG
	return DYN_ALL


static func split_sentences(para: String) -> PackedStringArray:
	# 按句末标点切分，保留句末标点本身；无标点结尾的残余也保留
	var out := PackedStringArray()
	var start := 0
	var n := para.length()
	for i in n:
		var c := para[i]
		if c == "。" or c == "？" or c == "！":
			out.append(para.substr(start, i - start + 1))
			start = i + 1
	if start < n:
		out.append(para.substr(start))
	return out


static func read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		push_error("文件不存在：" + path)
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("无法打开文件：" + path)
		return ""
	var t := f.get_as_text()
	f.close()
	return t


static func is_cjk_char(ch: String) -> bool:
	if ch.length() == 0:
		return false
	var code: int = ch.unicode_at(0)
	return (code >= 0x4E00 and code <= 0x9FFF) \
		or (code >= 0x3400 and code <= 0x4DBF) \
		or (code >= 0xF900 and code <= 0xFAFF)


static func first_hanzi(s: String) -> String:
	for i in s.length():
		var ch: String = s[i]
		if is_cjk_char(ch):
			return ch
	return ""


static func last_hanzi(s: String) -> String:
	for i in range(s.length() - 1, -1, -1):
		var ch: String = s[i]
		if is_cjk_char(ch):
			return ch
	return ""
