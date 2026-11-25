extends GutTest
## Подсветка консоли (TerminalHighlight): только вид — текст строк не меняется.

var paint: TerminalHighlight


func before_each() -> void:
	paint = TerminalHighlight.new("hacker")


func _plain(bbcode: String) -> String:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = bbcode
	var text: String = label.get_parsed_text()
	label.free()
	return text


func test_prompt_keeps_its_text_and_colors_parts() -> void:
	var bb: String = paint.prompt("home:/home$ ")
	assert_eq(_plain(bb), "home:/home$ ", "текст приглашения тот же")
	assert_string_contains(bb, (paint.colors["host"] as Color).to_html(false), "узел своим цветом")
	assert_string_contains(bb, (paint.colors["path"] as Color).to_html(false), "путь своим цветом")


func test_admin_sigil_is_marked() -> void:
	assert_string_contains(paint.prompt("10.0.0.5:/# "), (paint.colors["root"] as Color).to_html(false))


func test_command_paints_program_flags_and_paths() -> void:
	var bb: String = paint.command("cp -r /home/a.txt b")
	assert_eq(_plain(bb), "cp -r /home/a.txt b")
	assert_string_contains(bb, (paint.colors["command"] as Color).to_html(false))
	assert_string_contains(bb, (paint.colors["flag"] as Color).to_html(false))
	assert_string_contains(bb, (paint.colors["path"] as Color).to_html(false))


func test_output_lines_get_a_meaning() -> void:
	assert_eq(TerminalHighlight.role_of("команда не найдена: test"), "error")
	assert_eq(TerminalHighlight.role_of("подключено: 10.0.0.5 (сервер)"), "ok")
	assert_eq(TerminalHighlight.role_of("трейс запущен: 12 мин"), "warn")
	assert_eq(TerminalHighlight.role_of("команда указана неверно: cp <файл> <путь>. Подробнее: help cp"), "error")
	assert_eq(TerminalHighlight.role_of("/home"), "text")
	assert_eq(TerminalHighlight.role_of("photos/"), "path", "каталог в списке ls")


func test_brackets_are_not_tags() -> void:
	assert_eq(_plain(paint.output("[файл зашифрован, 40 КБ]")), "[файл зашифрован, 40 КБ]")
