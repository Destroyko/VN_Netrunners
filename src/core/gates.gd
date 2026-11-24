class_name Gates
extends RefCounted
## Ворота механик среза (docs/tech/gates.md): механика, которая ещё не доведена до конца или не нужна
## первому показу, спрятана за флагом `gate.*`. Закрыта по умолчанию, сюжет или консоль F1
## (`set_flag gate.hunger`) открывает. Код механик не удаляется: открыл ворота — механика работает.

## Голод: сытость тает, влияет на темп энергии, показывается шкалой; еду можно есть.
const HUNGER: String = "gate.hunger"
## Магазин еды на рабочем столе ПК (доставка, энергетик).
const SHOP: String = "gate.shop"
## Приложение «Новости».
const NEWS: String = "gate.news"
## Команда `decrypt` и фоновый подбор пароля к архиву.
const AUTOCRACK: String = "gate.autocrack"


static func is_open(gate: String) -> bool:
	return GameState.has_flag(gate)
