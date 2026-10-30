class_name TestLib
extends RefCounted
## Assertion helper for headless tests. Use inside a test's run(host): TestLib.check(cond, "what is expected").

static var failures := 0
static var checks := 0


static func check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("ok: ", msg)
	else:
		failures += 1
		printerr("FAIL: ", msg)


## Wait n rendered/physics frames.
static func frames(host: Node, n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame


static func finish(tree: SceneTree) -> void:
	print("RESULT: ", "PASS" if failures == 0 else "FAIL (%d of %d checks)" % [failures, checks])
	tree.quit(0 if failures == 0 else 1)
