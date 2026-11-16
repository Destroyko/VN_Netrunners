extends Node
## Слушатель потребностей: ход часов → правила `Needs`, их события → шина. Логики здесь нет,
## кроме одного: вырубание (docs/gameplay/needs.md, «Вырубание»).
##
## Вырубание откладывается на следующий кадр (`call_deferred`): энергия кончается посреди хода
## часов, а сон сам двигает часы — двигать их изнутри их же сигнала нельзя. Если в этот момент шло
## ожидание у кровати, оно прерывается, и вместо него начинается сон.

## Потребности считаются, только пока идёт игра (`Clock.running`): тесты и отладочные запуски
## сцен двигают часы сами, и там герой не должен вырубаться посреди проверки трейса. Тесты
## потребностей включают их этим флагом.
var always_on: bool = false

var _pass_out_pending: bool = false
## Экран взял подачу вырубания на себя и сам позовёт сон, когда погаснет.
var _claimed: bool = false


func _ready() -> void:
	EventBus.time_advanced.connect(_on_time_advanced)


func _on_time_advanced(_minute: int, minutes_passed: int) -> void:
	if not Clock.running and not always_on:
		return
	for event: String in Needs.pass_minutes(minutes_passed, Rest.is_asleep()):
		if event == Needs.EVENT_PASSED_OUT:
			_schedule_pass_out()
		else:
			EventBus.need_warned.emit(event)


func _schedule_pass_out() -> void:
	if _pass_out_pending:
		return
	_pass_out_pending = true
	EventBus.wake_requested.emit("вырубился")
	call_deferred("_begin_pass_out")


## Сначала — сигнал: экран (стол или комната) может взять подачу на себя (`claim_pass_out`) и
## позвать `sleep_after_pass_out`, когда экран погаснет, — чтобы часы не прыгнули на глазах у
## игрока. Никто не взял (тесты, сцена без подачи) — сон сразу.
func _begin_pass_out() -> void:
	_claimed = false
	EventBus.passed_out.emit()
	if not _claimed:
		sleep_after_pass_out()


func claim_pass_out() -> void:
	_claimed = true


## Сон до полного восстановления, без будильника. Подключение к узлу никто не закрывает — трейс
## идёт. Отметка — для комнаты: она открывается уже после сна и проявляет картинку из черноты.
func sleep_after_pass_out() -> void:
	_pass_out_pending = false
	var report: Dictionary = Rest.sleep_until_rested()
	GameState.set_var(Needs.VAR_WOKE_AFTER_PASS_OUT, true)
	EventBus.woke_after_pass_out.emit(int(report["minutes"]))
