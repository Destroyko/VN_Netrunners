extends Node
## Сторож окна: держит пропорции в рамке 4:3…21:9, когда игрок тянет окно мышкой.
##
## Почему автозагрузка, а не узел в сцене: окно одно на всю игру, а сцены меняются.
## Узел-наблюдатель пришлось бы добавлять в каждый экран и не забывать про новые —
## в M1 их появится много. Правил игры здесь нет, это инфраструктура окна.
##
## Сама логика — в WindowAspect (src/core/window_aspect.gd), чтобы её проверяли тесты.

var _applying: bool = false


func _ready() -> void:
	# В headless окна нет, сторожить нечего.
	if DisplayServer.get_name() == "headless":
		return
	var window: Window = get_window()
	if window != null:
		window.size_changed.connect(_on_size_changed)


func _on_size_changed() -> void:
	# Защита от рекурсии: мы сами меняем размер, и это снова шлёт size_changed.
	if _applying:
		return
	var window: Window = get_window()
	if window == null or window.mode != Window.MODE_WINDOWED:
		return

	var wanted: Vector2i = WindowAspect.clamp_size(window.size, AppSettings.MIN_WINDOW_SIZE)
	_applying = true
	if wanted != window.size:
		window.size = wanted
	# Окно сжали — масштаб интерфейса не должен оставить рабочую область меньше минимума.
	var settings := AppSettings.new()
	settings.load_from()
	window.content_scale_factor = AppSettings.fit_ui_scale(settings.resolved_ui_scale(DisplayServer.screen_get_size().y), window.size)
	_applying = false
