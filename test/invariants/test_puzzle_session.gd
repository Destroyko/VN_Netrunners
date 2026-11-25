extends "res://test/unit/terminal_fixture.gd"
## Головоломка на стыке с сеансом: брошенная попытка и её цена (docs/tech/interactions.md;
## docs/issues.md: ISS-009). Окно закрыли — попытка засчитана (`finish_puzzle`); сеанс
## оборвался, пока окно открыто (`dc`, перезагрузка, трейс, конец прайм-тайма), — терминал
## забывает головоломку без итога.

const OpenIssue = preload("res://test/invariants/open_issue.gd")
const NODE: String = "node_training_pc"
const SERVICE: String = "svc_login"


func _now() -> int:
	return Network.for_game().abs_minute(GameState.day, GameState.minute)


func _attempts() -> int:
	return PuzzleProgress.for_game().attempts(NODE, SERVICE, _now())


## У двери учебного ПК и запустить взломщика: открывается головоломка.
func _open_puzzle() -> int:
	learn_programs()
	reveal(NODE)
	run("connect " + address_of(NODE))
	run("passhound")
	assert_eq(str(last.request.get("type", "")), "puzzle")
	return int(last.request["seed"])


## Как задумано: вышел из окна, ничего не собрав, — провал, следующая попытка — новая партия.
func test_closing_the_puzzle_counts_the_attempt() -> void:
	var first_seed: int = _open_puzzle()
	t.finish_puzzle(0)
	assert_eq(_attempts(), 1)
	run("passhound")
	assert_ne(int(last.request["seed"]), first_seed, "вторая попытка — другая головоломка")


func test_dc_mid_puzzle_counts_the_attempt() -> void:
	var first_seed: int = _open_puzzle()
	run("dc")
	assert_null(t.current_puzzle(), "сеанс закрыт — головоломки нет")
	assert_eq(_attempts(), 1, "брошенная обрывом попытка засчитана, как выход из окна")
	run("connect " + address_of(NODE))
	run("passhound")
	assert_ne(int(last.request["seed"]), first_seed, "посмотреть партию и уйти бесплатно нельзя")
