extends RefCounted
## Prints every balance table including the skill tree. Run: tools/balance_sim.sh


func run(_host: Node) -> void:
	for l in BalanceReport.lines(true):
		print(l)
