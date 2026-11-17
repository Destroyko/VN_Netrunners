class_name Screens
extends RefCounted
## Пути к экранам в одном месте: иначе они расползаются по сценам строками,
## и при переименовании файла ломается навигация.

const MAIN_MENU: String = "res://src/ui/main_menu.tscn"
## Выбор сложности; из меню сейчас не открывается (см. new_game.gd).
const NEW_GAME: String = "res://src/ui/new_game.tscn"
const SETTINGS: String = "res://src/ui/settings_screen.tscn"
const ABOUT: String = "res://src/ui/about.tscn"
## Квартира: сцена текущей локации (docs/gameplay/locations.md). Отсюда начинается игра, сюда
## уходят от ПК. Имя константы осталось с M1, когда была одна комната.
const ROOM: String = "res://src/ui/location/location_view.tscn"
## Рабочий стол (M1, шаг 7). Заменил заглушку M0.
const DESKTOP: String = "res://src/ui/desktop/desktop.tscn"
