class_name TermTable
extends RefCounted
## Таблица в выводе консоли (вычитка 25.11.2026): заголовки заглавными и столбцы фиксированной
## ширины, как у настоящих утилит (`ls -l`, `netstat`). Длинное значение обрезается «…», чтобы
## столбцы не разъезжались. Последний столбец — без ширины; если ячеек столько же, сколько
## ширин, строка добита до последнего столбца — его допишет вывод (статус «[Х]» / «[✓]»).


static func row(cells: Array, widths: Array[int]) -> String:
	var parts: PackedStringArray = []
	for i: int in cells.size():
		var text: String = str(cells[i])
		if i < widths.size():
			var width: int = widths[i]
			if text.length() > width - 1:
				text = text.substr(0, width - 2) + "…"
			text = text.rpad(width)
		parts.append(text)
	# Все ячейки с шириной — строка добита до следующего столбца (туда встанет статус).
	if cells.size() == widths.size():
		return "".join(parts)
	return "".join(parts).strip_edges(false, true)
