class_name Screens
extends RefCounted
## Пути к экранам в одном месте: иначе они расползаются по сценам строками,
## и при переименовании файла ломается навигация.

const MAIN_MENU: String = "res://src/ui/main_menu.tscn"
## Выбор сложности; из меню сейчас не открывается (см. new_game.gd).
const NEW_GAME: String = "res://src/ui/new_game.tscn"
const SETTINGS: String = "res://src/ui/settings_screen.tscn"
const ABOUT: String = "res://src/ui/about.tscn"
## Рабочий стол. На M0.5 это заглушка из M0, в M1 на её месте появится настоящий.
const DESKTOP: String = "res://src/ui/main.tscn"
