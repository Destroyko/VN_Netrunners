extends CanvasLayer
## Окно диалогов поверх любой сцены и журнал реплик (`H`) (docs/tech/dialogue-format.md).
## Правил здесь нет: показывает `DialogueManager.current` и зовёт `advance()` / `choose()`.
##
## Текст набирается постепенно со скоростью из настроек; клик, пробел или Enter во время набора —
## вся строка сразу, после — следующая реплика. Термины `[[id]]` — ссылки, при наведении
## подсказка из глоссария.

const PORTRAIT_SIZE: Vector2 = Vector2(192, 384)
const PORTRAIT_DIR: String = "res://assets/portraits"

var box: PanelContainer
## Прозрачная подложка на весь экран: клик где угодно — дальше; сцена под диалогом не кликается.
var _blocker: Control
var _portrait: TextureRect
var _plaque: ColorRect
var _plaque_label: Label
var _name: Label
var _text: RichTextLabel
var _choices: VBoxContainer
var _tooltip: PanelContainer
var _tooltip_label: Label
var _journal: PanelContainer
var _journal_list: RichTextLabel
var _chars_per_second: float = AppSettings.DEFAULT_TEXT_SPEED
var _typing: float = 0.0


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_set_shown(false)
	_journal.visible = false
	EventBus.dialogue_started.connect(func(_id: String) -> void: _on_started())
	EventBus.dialogue_node_changed.connect(func(_id: String, _node: String) -> void: show_node())
	EventBus.dialogue_ended.connect(func(_id: String) -> void:
		_set_shown(false)
		_tooltip.visible = false)


func _on_started() -> void:
	var settings := AppSettings.new()
	settings.load_from()
	_chars_per_second = settings.text_speed
	_set_shown(true)
	show_node()


## Показать текущий узел: говорящий, портрет, текст (набирается заново), выборы.
func show_node() -> void:
	var run: DialogueRun = DialogueManager.current
	if run == null:
		_set_shown(false)
		return
	var node: Dictionary = run.node()
	var speaker: String = str(node.get("speaker", ""))
	var character: Dictionary = DataLoader.characters().get(speaker, {}) as Dictionary
	var thought: bool = bool(node.get("thought", false))
	_name.visible = not speaker.is_empty() and not thought
	_name.text = DialogueText.with_names(str(character.get("name", speaker)))
	_name.add_theme_color_override("font_color", Color(str(character.get("color", "#d0d4dc"))))
	_show_portrait(character, str(node.get("emotion", "neutral")), not speaker.is_empty() and not thought)
	var bb: String = DialogueText.to_bbcode(str(node.get("text", "")))
	_text.text = "[i][color=#9aa0aa]%s[/color][/i]" % bb if thought else bb
	_text.visible_characters = 0 if _chars_per_second > 0.0 else -1
	_typing = 0.0
	_fill_choices(run)


func is_typing() -> bool:
	return _text.visible_characters >= 0 and _text.visible_characters < _text.get_total_character_count()


## Клик / пробел / Enter: набор идёт — показать всю строку; нет — дальше (если нет выборов).
func proceed() -> void:
	if DialogueManager.current == null:
		return
	if is_typing():
		_text.visible_characters = -1
		_choices.visible = true
		return
	if not DialogueManager.current.has_choices():
		DialogueManager.advance()


func _process(delta: float) -> void:
	if not box.visible or not is_typing():
		return
	_typing += delta * _chars_per_second
	_text.visible_characters = int(_typing)
	if not is_typing():
		_choices.visible = true


func _set_shown(on: bool) -> void:
	box.visible = on
	_blocker.visible = on


## Клик по подложке или по панели — то же, что пробел.
func _on_click(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		proceed()


func _unhandled_input(event: InputEvent) -> void:
	if box.visible and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		proceed()
		return
	# H — журнал реплик, но не пока игрок печатает (буквы в поле ввода — это текст).
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_H and not _typing_in_field():
		get_viewport().set_input_as_handled()
		toggle_journal()


func toggle_journal() -> void:
	_journal.visible = not _journal.visible
	if not _journal.visible:
		return
	var lines: PackedStringArray = []
	for entry: Dictionary in DialogueRun.journal():
		var speaker: String = str(entry.get("speaker", ""))
		var name: String = ""
		if not speaker.is_empty():
			name = DialogueText.with_names(str((DataLoader.characters().get(speaker, {}) as Dictionary).get("name", speaker)))
		var prefix: String = "→ " if bool(entry.get("choice", false)) else ("%s: " % name if not name.is_empty() else "")
		lines.append("%s%s" % [prefix, str(entry.get("text", ""))])
	_journal_list.text = "\n".join(lines) if not lines.is_empty() else "Пока пусто."


func _fill_choices(run: DialogueRun) -> void:
	for child: Node in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	var visible_choices: Array = run.choices() if run.has_choices() else []
	for i: int in visible_choices.size():
		var button := Button.new()
		button.name = "Choice_%d" % i
		button.text = DialogueText.plain(str((visible_choices[i] as Dictionary).get("text", "")))
		button.pressed.connect(func() -> void: DialogueManager.choose(i))
		_choices.add_child(button)
	_choices.visible = not is_typing()


func _show_portrait(character: Dictionary, emotion: String, shown: bool) -> void:
	var base: String = str(character.get("portrait", ""))
	var path: String = "%s/chr_%s_%s.png" % [PORTRAIT_DIR, base, emotion]
	var has_art: bool = shown and not base.is_empty() and ResourceLoader.exists(path)
	_portrait.visible = has_art
	_plaque.visible = shown and not has_art
	if has_art:
		_portrait.texture = load(path) as Texture2D
	elif shown:
		# Арта ещё нет — плашка цветом персонажа с именем и эмоцией.
		_plaque.color = Color(str(character.get("color", "#555b66"))).darkened(0.4)
		_plaque_label.text = "%s\n(%s)" % [DialogueText.with_names(str(character.get("name", ""))), emotion]


func _on_meta_hover(meta: Variant) -> void:
	var id: String = str(meta).trim_prefix(DialogueText.TERM_PREFIX)
	var hint: String = DialogueText.hint(id)
	if hint.is_empty():
		return
	_tooltip_label.text = hint
	_tooltip.visible = true
	_tooltip.position = _text.get_global_mouse_position() + Vector2(12, -48)


func _typing_in_field() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _build() -> void:
	_blocker = Control.new()
	_blocker.name = "ClickCatcher"
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.gui_input.connect(_on_click)
	add_child(_blocker)
	box = PanelContainer.new()
	box.name = "DialogueBox"
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_top = -220
	box.gui_input.connect(_on_click)
	add_child(box)
	# Клик по любому месту панели — дальше: всё внутри пропускает мышь к панели. Иначе текст и
	# плашка «съедали» клик (плейтест M3).
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var portrait_slot := Control.new()
	portrait_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_slot.custom_minimum_size = Vector2(PORTRAIT_SIZE.x, 200)
	row.add_child(portrait_slot)
	_portrait = TextureRect.new()
	_portrait.size = PORTRAIT_SIZE
	_portrait.position = Vector2(0, 200 - PORTRAIT_SIZE.y)
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_slot.add_child(_portrait)
	_plaque = ColorRect.new()
	_plaque.size = Vector2(PORTRAIT_SIZE.x, 200)
	_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_slot.add_child(_plaque)
	_plaque_label = Label.new()
	_plaque_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_plaque_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plaque_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_plaque.add_child(_plaque_label)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	_name = Label.new()
	_name.name = "Speaker"
	column.add_child(_name)
	_text = RichTextLabel.new()
	_text.name = "Text"
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# PASS, а не IGNORE: наведение на термин должно работать, а клик — уйти дальше к панели.
	_text.mouse_filter = Control.MOUSE_FILTER_PASS
	_text.meta_hover_started.connect(_on_meta_hover)
	_text.meta_hover_ended.connect(func(_meta: Variant) -> void: _tooltip.visible = false)
	column.add_child(_text)
	_choices = VBoxContainer.new()
	_choices.name = "Choices"
	_choices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_choices)

	_tooltip = PanelContainer.new()
	_tooltip.name = "TermHint"
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label = Label.new()
	_tooltip_label.custom_minimum_size = Vector2(260, 0)
	_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip.add_child(_tooltip_label)
	add_child(_tooltip)

	_journal = PanelContainer.new()
	_journal.name = "Journal"
	_journal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_journal.custom_minimum_size = Vector2(640, 420)
	_journal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_journal.grow_vertical = Control.GROW_DIRECTION_BOTH
	var journal_box := VBoxContainer.new()
	_journal.add_child(journal_box)
	var title := Label.new()
	title.text = "Журнал реплик (H — закрыть)"
	journal_box.add_child(title)
	_journal_list = RichTextLabel.new()
	_journal_list.name = "Lines"
	_journal_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal_list.scroll_following = true
	journal_box.add_child(_journal_list)
	add_child(_journal)


## Для тестов: текст реплики и подписи как их видит игрок.
func shown_text() -> String:
	return _text.get_parsed_text()


func speaker_text() -> String:
	return _name.text if _name.visible else ""


func journal_text() -> String:
	return _journal_list.get_parsed_text()


func journal_visible() -> bool:
	return _journal.visible


func set_speed(chars_per_second: float) -> void:
	_chars_per_second = chars_per_second
