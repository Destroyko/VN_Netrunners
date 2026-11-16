class_name PassOutCurtain
extends Control
## Вырубание на экране (docs/gameplay/needs.md, «Вырубание»): реплика героя «я слишком устал…»,
## экран гаснет, по центру — «ты еле добрался до кровати и уснул», потом стол сменяется комнатой,
## и картинка проявляется уже там. Правил здесь нет: сон уже прошёл в `Rest`, это только подача.
##
## Реплика пока подписью внизу; в M3 она станет репликой диалога новеллы. Тексты —
## `data/needs.json`. Пока занавес идёт, часы стоят (`Clock.pause`), как в диалоге.

const PAUSE_REASON: String = "pass_out"
const LINE_SECONDS: float = 2.5
const FADE_SECONDS: float = 1.0
const CAPTION_SECONDS: float = 2.5

## Анимации выключаются в тестах: занавес проходит сразу.
static var animate: bool = true

signal finished

var _black: ColorRect
var _caption: Label
var _line: Label


func _init() -> void:
	name = "PassOutCurtain"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # пока идёт занавес, кликать по столу нельзя
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.modulate.a = 0.0
	add_child(_black)
	_caption = _label(Control.PRESET_CENTER)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line = _label(Control.PRESET_CENTER_BOTTOM)
	_line.position.y -= 48


static func text(key: String) -> String:
	return str((DataLoader.needs().get("thoughts", {}) as Dictionary).get(key, ""))


## Реплика → экран гаснет → подпись. В конце — `finished` (стол меняет сцену).
func play_falling_asleep() -> void:
	Clock.pause(PAUSE_REASON)
	_line.text = text("passing_out")
	_caption.text = text("passed_out_caption")
	_caption.modulate.a = 0.0
	if not animate:
		_black.modulate.a = 1.0
		_caption.modulate.a = 1.0
		_done()
		return
	var tween := create_tween()
	tween.tween_interval(LINE_SECONDS)
	tween.tween_callback(func() -> void: _line.text = "")
	tween.tween_property(_black, "modulate:a", 1.0, FADE_SECONDS)
	tween.tween_property(_caption, "modulate:a", 1.0, FADE_SECONDS * 0.5)
	tween.tween_interval(CAPTION_SECONDS)
	tween.tween_callback(_done)


## Уже в комнате: из черноты проявляется картинка, часы снова идут.
func play_waking_up() -> void:
	_black.modulate.a = 1.0
	if not animate:
		_wake_done()
		return
	var tween := create_tween()
	tween.tween_property(_black, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(_wake_done)


func caption_text() -> String:
	return _caption.text


func line_text() -> String:
	return _line.text


func _done() -> void:
	finished.emit()


func _wake_done() -> void:
	Clock.resume(PAUSE_REASON)
	queue_free()


func _label(preset: Control.LayoutPreset) -> Label:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
