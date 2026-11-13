class_name AppSettings
extends RefCounted
## Настройки приложения: громкость, режим окна, масштаб интерфейса.
##
## Лежат отдельно от сейва (`user://settings.cfg`), потому что это не часть игрового
## состояния: их не надо версионировать и мигрировать вместе с `GameState`.
## Поэтому же они не ждут SaveManager из M4.
##
## Загрузка, сохранение и расчёт масштаба отделены от apply(): так настройки можно проверить
## тестами, не трогая звук, окно и экран.

const PATH: String = "user://settings.cfg"
const SECTION: String = "app"

const DEFAULT_MASTER_VOLUME: float = 0.8
const DEFAULT_FULLSCREEN: bool = false

## Масштаб интерфейса. AUTO — подобрать от высоты экрана (docs/tech/resolution.md).
const UI_SCALE_AUTO: float = 0.0
const UI_SCALES: Array[float] = [1.0, 1.25, 1.5, 2.0]

## Минимальный размер окна. Не 1024x768, а 1024x720: это ограничение по каждой стороне
## отдельно, и так проходят оба поддерживаемых минимума — 1024x768 и 1280x720.
const MIN_WINDOW_SIZE: Vector2i = Vector2i(1024, 720)

## Разрешение «как сейчас у окна»: игрок растянул окно мышкой и ничего не выбирал из списка.
const RESOLUTION_WINDOW: Vector2i = Vector2i.ZERO

## Стандартные разрешения для выпадающего списка, по возрастанию.
## Подпись пропорции хранится рядом, а не считается: 1366x768 это «почти 16:9»,
## и честнее написать так, как это называют люди, чем выводить дробь.
const RESOLUTIONS: Array[Dictionary] = [
	{"size": Vector2i(1024, 768), "aspect": "4:3"},
	{"size": Vector2i(1280, 720), "aspect": "16:9"},
	{"size": Vector2i(1280, 800), "aspect": "16:10"},
	{"size": Vector2i(1280, 960), "aspect": "4:3"},
	{"size": Vector2i(1600, 900), "aspect": "16:9"},
	{"size": Vector2i(1680, 1050), "aspect": "16:10"},
	{"size": Vector2i(1920, 1080), "aspect": "16:9"},
	{"size": Vector2i(1920, 1200), "aspect": "16:10"},
	{"size": Vector2i(2560, 1080), "aspect": "21:9"},
	{"size": Vector2i(2560, 1440), "aspect": "16:9"},
	{"size": Vector2i(3440, 1440), "aspect": "21:9"},
	{"size": Vector2i(3840, 2160), "aspect": "16:9"},
]

## Громкость 0..1. В децибелы переводим только в apply().
var master_volume: float = DEFAULT_MASTER_VOLUME
var fullscreen: bool = DEFAULT_FULLSCREEN
var ui_scale: float = UI_SCALE_AUTO
var resolution: Vector2i = RESOLUTION_WINDOW


## Прочитать настройки. Файла нет (первый запуск) — остаются значения по умолчанию.
func load_from(path: String = PATH) -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	master_volume = clamp_volume(float(config.get_value(SECTION, "master_volume", DEFAULT_MASTER_VOLUME)))
	fullscreen = bool(config.get_value(SECTION, "fullscreen", DEFAULT_FULLSCREEN))
	ui_scale = normalize_ui_scale(float(config.get_value(SECTION, "ui_scale", UI_SCALE_AUTO)))
	resolution = config.get_value(SECTION, "resolution", RESOLUTION_WINDOW) as Vector2i


func save_to(path: String = PATH) -> Error:
	var config := ConfigFile.new()
	config.set_value(SECTION, "master_volume", master_volume)
	config.set_value(SECTION, "fullscreen", fullscreen)
	config.set_value(SECTION, "ui_scale", ui_scale)
	config.set_value(SECTION, "resolution", resolution)
	return config.save(path)


## Применить к игре. Окно передаёт вызывающий (из сцены это get_window()) —
## так класс не лазит в главный цикл и остаётся проверяемым.
func apply(window: Window = null) -> void:
	var bus: int = AudioServer.get_bus_index(&"Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(master_volume))
		AudioServer.set_bus_mute(bus, is_zero_approx(master_volume))

	# В headless-режиме окна и экрана нет, трогать их нельзя.
	if window == null or DisplayServer.get_name() == "headless":
		return

	window.min_size = MIN_WINDOW_SIZE
	window.content_scale_factor = resolved_ui_scale(DisplayServer.screen_get_size().y)
	window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED

	# Разрешение задаём только в оконном режиме: в полном экране его диктует монитор.
	if not fullscreen and resolution != RESOLUTION_WINDOW:
		window.size = resolution
		window.move_to_center()


func set_master_volume(value: float) -> void:
	master_volume = clamp_volume(value)


func set_ui_scale(value: float) -> void:
	ui_scale = normalize_ui_scale(value)


## Во сколько раз масштабировать интерфейс на самом деле.
func resolved_ui_scale(screen_height: int) -> float:
	if is_equal_approx(ui_scale, UI_SCALE_AUTO):
		return suggest_ui_scale(screen_height)
	return ui_scale


## Догадка по высоте экрана. Системный масштаб на Windows узнать нельзя
## (DisplayServer.screen_get_scale работает не везде), поэтому это предположение,
## а игрок правит его руками.
static func suggest_ui_scale(screen_height: int) -> float:
	if screen_height >= 2160:
		return 2.0
	if screen_height >= 1440:
		return 1.25
	return 1.0


## Привести к допустимому значению: ноль — это «авто», остальное — ближайший из UI_SCALES.
static func normalize_ui_scale(value: float) -> float:
	if value <= 0.0:
		return UI_SCALE_AUTO
	var nearest: float = UI_SCALES[0]
	for scale: float in UI_SCALES:
		if absf(scale - value) < absf(nearest - value):
			nearest = scale
	return nearest


func set_resolution(value: Vector2i) -> void:
	resolution = value if value == RESOLUTION_WINDOW else value.max(MIN_WINDOW_SIZE)


## Разрешения, которые влезают в экран. Предлагать 4K на ноутбучном экране бессмысленно,
## и игрок получил бы окно больше монитора.
static func resolutions_for_screen(screen: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in RESOLUTIONS:
		if fits_screen(item["size"] as Vector2i, screen):
			result.append(item)
	return result


static func fits_screen(size: Vector2i, screen: Vector2i) -> bool:
	return size.x <= screen.x and size.y <= screen.y


static func clamp_volume(value: float) -> float:
	return clampf(value, 0.0, 1.0)
