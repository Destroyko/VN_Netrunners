extends GutTest
## BalanceSim: бот проживает дни на настоящих правилах (docs/tech/testing.md, «Экономика и баланс»).
## Числа баланса не проверяем — они меняются на плейтесте; проверяем, что симуляция живая.


func test_bot_lives_through_the_first_job_week() -> void:
	var report: Dictionary = BalanceSim.run(6)
	var rows: Array = report["rows"]
	assert_eq(rows.size(), 6)
	for r: Dictionary in rows:
		assert_gt(int(r["income"]), 0, "день %d: заказ сдан и оплачен" % int(r["day"]))
	assert_eq(str(rows[5]["job"]), "side_job_6", "цепочка заказов дошла до шестого")
	assert_eq(int(rows[4]["rent"]), 200, "в понедельник (день 5) аренда оплачена")
	assert_false(NeedsManager.always_on, "после симуляции потребности снова только в игре")
	assert_gt((report["summary"] as PackedStringArray).size(), 6)
