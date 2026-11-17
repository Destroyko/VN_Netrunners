extends Control
## Настройки: громкость и режим окна.
##
## Вся логика — в AppSettings (src/core/app_settings.gd), здесь только показ и ввод.
## Сохраняем сразу при изменении: отдельная кнопка «Применить» на двух настройках —
## лишний шаг, на котором игрок теряет изменения, если уйдёт назад.

var _settings := AppSettings.new()

@onready var _volume: HSlider = $Rows/VolumeRow/Volume
@onready var _volume_value: Label = $Rows/VolumeRow/Value
@onready var _fullscreen: CheckButton = $Rows/Fullscreen
@onready var _ui_scale: OptionButton = $Rows/ScaleRow/Scale
@onready var _resolution: OptionButton = $Rows/ResolutionRow/Resolution


func _ready() -> void:
	_settings.load_from()

	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.05
	_volume.value = _settings.master_volume
	_fullscreen.button_pressed = _settings.fullscreen
	_update_volume_label()
	_fill_ui_scales()
	_fill_resolutions()

	_volume.value_changed.connect(_on_volume_changed)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_ui_scale.item_selected.connect(_on_ui_scale_selected)
	_resolution.item_selected.connect(_on_resolution_selected)
	_add_text_speed()
	$Rows/Back.pressed.connect(_on_back)


## Скорость текста в диалогах (docs/tech/dialogue-format.md): строка собирается кодом, чтобы не
## править сцену ради одного выпадающего списка.
func _add_text_speed() -> void:
	var row := HBoxContainer.new()
	row.name = "TextSpeedRow"
	var label := Label.new()
	label.text = "Скорость текста"
	label.custom_minimum_size = Vector2(160, 0)
	row.add_child(label)
	var speed := OptionButton.new()
	speed.name = "TextSpeed"
	for item: Dictionary in AppSettings.TEXT_SPEEDS:
		speed.add_item(str(item["title"]))
		speed.set_item_metadata(speed.item_count - 1, float(item["cps"]))
		if is_equal_approx(float(item["cps"]), _settings.text_speed):
			speed.select(speed.item_count - 1)
	speed.item_selected.connect(func(index: int) -> void:
		_settings.text_speed = float(speed.get_item_metadata(index))
		_apply_and_save())
	row.add_child(speed)
	$Rows.add_child(row)
	$Rows.move_child(row, $Rows/Fullscreen.get_index())


## Список разрешений: только те, что влезают в экран, плюс «по размеру окна» —
## его выбирает тот, кто тянул окно мышкой.
func _fill_resolutions() -> void:
	_resolution.clear()
	_resolution.add_item("По размеру окна")
	_resolution.set_item_metadata(0, AppSettings.RESOLUTION_WINDOW)

	var screen: Vector2i = (
		DisplayServer.screen_get_size()
		if DisplayServer.get_name() != "headless"
		else Vector2i(1920, 1080)
	)
	for item: Dictionary in AppSettings.resolutions_for_screen(screen):
		var size: Vector2i = item["size"] as Vector2i
		_resolution.add_item("%d×%d (%s)" % [size.x, size.y, item["aspect"]])
		_resolution.set_item_metadata(_resolution.item_count - 1, size)

	for index: int in _resolution.item_count:
		if (_resolution.get_item_metadata(index) as Vector2i) == _settings.resolution:
			_resolution.select(index)
			return
	_resolution.select(0)


func _on_resolution_selected(index: int) -> void:
	_settings.set_resolution(_resolution.get_item_metadata(index) as Vector2i)
	_apply_and_save()


## Масштаб интерфейса: «Авто» плюс фиксированные значения (docs/tech/resolution.md).
func _fill_ui_scales() -> void:
	_ui_scale.clear()
	_ui_scale.add_item("Авто")
	_ui_scale.set_item_metadata(0, AppSettings.UI_SCALE_AUTO)
	for scale: float in AppSettings.UI_SCALES:
		_ui_scale.add_item("%d%%" % roundi(scale * 100.0))
		_ui_scale.set_item_metadata(_ui_scale.item_count - 1, scale)
	for index: int in _ui_scale.item_count:
		if is_equal_approx(float(_ui_scale.get_item_metadata(index)), _settings.ui_scale):
			_ui_scale.select(index)
			return
	_ui_scale.select(0)


func _on_ui_scale_selected(index: int) -> void:
	_settings.set_ui_scale(float(_ui_scale.get_item_metadata(index)))
	_apply_and_save()


func _on_volume_changed(value: float) -> void:
	_settings.set_master_volume(value)
	_update_volume_label()
	_apply_and_save()


func _on_fullscreen_toggled(pressed: bool) -> void:
	_settings.fullscreen = pressed
	_apply_and_save()


func _update_volume_label() -> void:
	_volume_value.text = "%d%%" % roundi(_settings.master_volume * 100.0)


func _apply_and_save() -> void:
	_settings.apply(get_window())
	var err: Error = _settings.save_to()
	if err != OK:
		push_error("Настройки не сохранились: ошибка %d" % err)


func _on_back() -> void:
	get_tree().change_scene_to_file(Screens.MAIN_MENU)
