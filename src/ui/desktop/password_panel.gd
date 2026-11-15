class_name PasswordPanel
extends VBoxContainer
## «Пароль»: из пула букв собрать слово в ячейках (docs/tech/puzzles-spec.md). Буквы можно
## перетаскивать мышью или кликать. Когда все ячейки заполнены, слово проверяется: верные буквы
## остаются на местах, лишние исчезают, «есть, но не там» возвращаются в пул.
## Показывает партию `PasswordPuzzle` и передаёт слова в неё: правил здесь нет.

signal finished(gained: int)

const COLOR_EXACT: String = "#5fd27a"
const COLOR_PRESENT: String = "#e8c547"
const COLOR_ABSENT: String = "#7b8190"
const ALPHABET: String = "абвгдежзийклмнопрстуфхцчшщыэюя"
## Сколько букв в пуле в начале: слово плюс ложные.
const POOL_SIZE: int = 12

var puzzle: PasswordPuzzle

var _title: Label
var _history: RichTextLabel
var _note: Label
var _slot_row: HBoxContainer
var _slot_holder: Control
var _zone: LetterZone
var _slots: Array[String] = []
var _locked: Array[bool] = []
var _pool: Array[String] = []
var _done: bool = false
## Идёт тряска неверного слова: ввод на это время закрыт.
var _busy: bool = false


func setup(game: PasswordPuzzle) -> void:
	puzzle = game
	_title = Label.new()
	add_child(_title)

	_history = RichTextLabel.new()
	_history.bbcode_enabled = true
	_history.fit_content = true
	_history.custom_minimum_size = Vector2(360, 0)
	_history.add_theme_font_override("normal_font", _mono())
	add_child(_history)

	# Обёртка нужна, чтобы трясти ряд: внутри контейнера положение детей задаёт сам контейнер.
	_slot_holder = Control.new()
	_slot_holder.custom_minimum_size = Vector2(0, 60)
	add_child(_slot_holder)
	_slot_row = HBoxContainer.new()
	_slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slot_holder.add_child(_slot_row)

	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_note)

	_zone = LetterZone.new()
	_zone.alignment = FlowContainer.ALIGNMENT_CENTER
	_zone.custom_minimum_size = Vector2(360, 110)
	_zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_zone.returned.connect(func(from: Dictionary) -> void: unplace(int(from["index"])))
	add_child(_zone)

	for index: int in puzzle.length:
		var open: bool = puzzle.known.has(index)
		_slots.append(str(puzzle.known[index]) if open else "")
		_locked.append(open)
	_pool = build_pool(puzzle)
	_refresh()


static func _mono() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	return font


## Пул букв: нужные слову (кроме уже открытых) плюс ложные, не совпадающие с буквами слова.
## Тасуется по сиду головоломки, поэтому одна и та же партия всегда выглядит одинаково.
static func build_pool(game: PasswordPuzzle) -> Array[String]:
	var pool: Array[String] = []
	for index: int in game.length:
		if not game.known.has(index):
			pool.append(game.word[index])
	var decoys: Array[String] = []
	for letter: String in ALPHABET:
		if not game.word.contains(letter):
			decoys.append(letter)
	var rng: RandomNumberGenerator = Rng.fixed(("pool:%d" % game.puzzle_seed).hash())
	for index: int in range(decoys.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var swap: String = decoys[index]
		decoys[index] = decoys[other]
		decoys[other] = swap
	while pool.size() < POOL_SIZE and not decoys.is_empty():
		pool.append(decoys.pop_back())
	for index: int in range(pool.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var swap: String = pool[index]
		pool[index] = pool[other]
		pool[other] = swap
	return pool


# --- Ходы игрока ---------------------------------------------------------------

## Буква из пула — в ячейку. Занятая ячейка меняется: старая буква уходит обратно в пул.
func place(pool_index: int, slot_index: int) -> void:
	if _done or _busy or pool_index < 0 or pool_index >= _pool.size() or _locked[slot_index]:
		return
	var letter: String = _pool[pool_index]
	_pool.remove_at(pool_index)
	if not _slots[slot_index].is_empty():
		_pool.append(_slots[slot_index])
	_slots[slot_index] = letter
	_after_change()


## Буква из ячейки — обратно в пул.
func unplace(slot_index: int) -> void:
	if _done or _busy or _locked[slot_index] or _slots[slot_index].is_empty():
		return
	_pool.append(_slots[slot_index])
	_slots[slot_index] = ""
	_after_change()


func move_slot(from_index: int, to_index: int) -> void:
	if _done or _busy or from_index == to_index or _locked[from_index] or _locked[to_index]:
		return
	var swap: String = _slots[to_index]
	_slots[to_index] = _slots[from_index]
	_slots[from_index] = swap
	_after_change()


## Клик по пулу: буква в первую свободную ячейку.
func place_first_free(pool_index: int) -> void:
	for slot_index: int in puzzle.length:
		if _slots[slot_index].is_empty() and not _locked[slot_index]:
			place(pool_index, slot_index)
			return


func _on_dropped(from: Dictionary, _to_kind: String, to_index: int) -> void:
	if str(from["kind"]) == LetterTile.KIND_POOL:
		place(int(from["index"]), to_index)
	else:
		move_slot(int(from["index"]), to_index)


func _after_change() -> void:
	_refresh()
	if not _slots.has(""):
		_evaluate()


## Все ячейки заполнены: слово идёт в партию.
func _evaluate() -> void:
	_apply(puzzle.guess("".join(_slots), false))


## Итог проверки: верные буквы закрепляются, лишние исчезают, «не там» уходят в пул.
func _apply(result: Dictionary) -> void:
	SessionLog.write("puzzle", "пароль: %s → %s" % ["".join(_slots), JSON.stringify(result.get("marks", result.get("reason", "")))])
	if not bool(result["valid"]):
		# Слово не подошло и не из словаря: буквы возвращаются в пул, попытка не тратится.
		for index: int in puzzle.length:
			if not _locked[index] and not _slots[index].is_empty():
				_pool.append(_slots[index])
				_slots[index] = ""
		_refresh()
		_note.text = _reason_text(str(result["reason"]))
		return
	var shake: bool = not bool(result.get("in_dictionary", true))
	var marks: Array = result["marks"] as Array
	for index: int in puzzle.length:
		if _locked[index]:
			continue
		var mark: int = int(marks[index])
		if mark == PasswordPuzzle.MARK_EXACT:
			_locked[index] = true
		else:
			if mark == PasswordPuzzle.MARK_PRESENT:
				_pool.append(_slots[index])
			_slots[index] = ""
	if shake and not _done:
		_shake_then_refresh()
	else:
		_refresh()
	if bool(result["solved"]):
		_finish(1, "Пароль подошёл.")
	elif bool(result["failed"]):
		_finish(0, "Попытки кончились. Было слово: %s." % puzzle.word)
	else:
		_note.text = ""


## Целое слово разом (для тестов и отладки): раскладывает его по ячейкам и проверяет.
func submit(text: String) -> Dictionary:
	if _done:
		return {}
	var entered: String = text.strip_edges().to_lower().replace("ё", "е")
	var result: Dictionary = puzzle.guess(entered, false)
	if bool(result["valid"]):
		for index: int in puzzle.length:
			if not _locked[index]:
				_pool.erase(entered[index])
				_slots[index] = entered[index]
	_apply(result)
	return result


## Слово не из словаря: ячейки на секунду краснеют и трясутся, потом буквы разбираются по меткам.
func _shake_then_refresh() -> void:
	_busy = true
	for tile: Node in _slot_row.get_children():
		if not (tile as LetterTile).locked:
			(tile as LetterTile).modulate = Color(1.0, 0.35, 0.35)
	var tween: Tween = create_tween()
	for step: int in 6:
		tween.tween_property(_slot_row, "position:x", 10.0 if step % 2 == 0 else -10.0, 0.06)
	tween.tween_property(_slot_row, "position:x", 0.0, 0.06)
	tween.tween_interval(0.35)
	tween.tween_callback(func() -> void:
		_busy = false
		_refresh())


func _finish(gained: int, message: String) -> void:
	_done = true
	_note.text = message
	if not _busy:
		_refresh()
	var button := Button.new()
	button.text = "Дальше"
	button.pressed.connect(func() -> void: finished.emit(gained))
	add_child(button)


## Игрок закрыл окно или нажал «Выйти»: партия не доиграна, слоёв нет.
func abandon_gained() -> int:
	return 0


func is_done() -> bool:
	return _done


func note_text() -> String:
	return _note.text


func slot_text() -> String:
	return "".join(_slots)


func pool_letters() -> Array[String]:
	return _pool.duplicate()


## Подсказка без траты попытки: что за ввод не принят.
static func _reason_text(reason: String) -> String:
	match reason:
		"length":
			return "Нужно слово ровно нужной длины."
		"unknown":
			return "Не подходит. Попытка не потрачена, попробуй другие буквы."
	return "Ввод не принят."


func _refresh() -> void:
	_title.text = "Собери пароль (%d букв) · попыток: %d из %d" % [puzzle.length, puzzle.attempts_left(), puzzle.max_attempts]
	for child: Node in _slot_row.get_children():
		_slot_row.remove_child(child)
		child.queue_free()
	for index: int in puzzle.length:
		var tile := LetterTile.new()
		tile.setup(LetterTile.KIND_SLOT, index, _slots[index], _locked[index])
		if _locked[index]:
			tile.add_theme_color_override("font_disabled_color", Color(COLOR_EXACT))
		tile.dropped.connect(_on_dropped)
		tile.pressed.connect(unplace.bind(index))
		_slot_row.add_child(tile)
	for child: Node in _zone.get_children():
		_zone.remove_child(child)
		child.queue_free()
	for index: int in _pool.size():
		var tile := LetterTile.new()
		tile.setup(LetterTile.KIND_POOL, index, _pool[index], false)
		tile.pressed.connect(place_first_free.bind(index))
		_zone.add_child(tile)
	var lines: PackedStringArray = []
	for entry: Dictionary in puzzle.history:
		lines.append(_row(str(entry["word"]), entry["marks"] as Array))
	_history.text = "\n".join(lines)


## Строка с метками: цвет — как в Wordle, плюс знак, чтобы не полагаться только на цвет.
static func _row(word: String, marks: Array) -> String:
	var text: String = ""
	for index: int in word.length():
		var mark: int = int(marks[index])
		var color: String = COLOR_ABSENT
		var sign: String = " "
		if mark == PasswordPuzzle.MARK_EXACT:
			color = COLOR_EXACT
			sign = "="
		elif mark == PasswordPuzzle.MARK_PRESENT:
			color = COLOR_PRESENT
			sign = "~"
		text += "[color=%s]%s%s[/color] " % [color, word[index].to_upper(), sign]
	return text
