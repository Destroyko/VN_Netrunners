class_name Screens
extends RefCounted
## Пути к экранам в одном месте: иначе они расползаются по сценам строками,
## и при переименовании файла ломается навигация.

const MAIN_MENU: String = "res://src/ui/main_menu.tscn"
## Выбор сложности; из меню сейчас не открывается (см. new_game.gd).
const NEW_GAME: String = "res://src/ui/new_game.tscn"
const SETTINGS: String = "res://src/ui/settings_screen.tscn"
const ABOUT: String = "res://src/ui/about.tscn"
## Комната героя: отсюда начинается игра (заглушка M1).
const ROOM: String = "res://src/ui/room.tscn"
## Рабочий стол (M1, шаг 7). Заменил заглушку M0.
const DESKTOP: String = "res://src/ui/desktop/desktop.tscn"
