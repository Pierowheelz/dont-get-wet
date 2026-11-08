extends Node
## Entry point of tests/run_tests.tscn. Loads the tests in run_tests.gd and fails the run, instead of
## passing or hanging, when they don't compile, an error is logged while they run (a runtime error
## aborts its test function without failing a check), or they don't finish.
## Kept free of game code so a broken game script can't stop it from reporting.

const TESTS := "res://tests/run_tests.gd"
const SCRIPT_DIRS: Array[String] = ["res://src", "res://tests"]
const TIMEOUT_S := 120.0
const AFTER_ERROR_S := 2.0   # an error already fails the run; give the tests a moment to print more


class ErrorCounter extends Logger:
	var count := 0
	var first := ""
	var on_first: Callable
	var _lock := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()   # engine errors can be logged from other threads
		count += 1
		var is_first := count == 1
		if is_first:
			first = "%s (%s:%d)" % [rationale if rationale != "" else code, file, line]
		_lock.unlock()
		if is_first:
			on_first.call_deferred()


var _errors := ErrorCounter.new()
var _done := false


func _ready() -> void:
	_errors.on_first = func() -> void:
		get_tree().create_timer(AFTER_ERROR_S).timeout.connect(finish.bind(-1))
	OS.add_logger(_errors)
	# Autoloads compile before this runs, so a broken script can fail silently there; check them all.
	var broken: Array[String] = []
	for dir in SCRIPT_DIRS:
		for path in _scripts(dir):
			var s := load(path) as GDScript
			if s == null or not s.can_instantiate():
				broken.append(path.trim_prefix("res://"))
	if not broken.is_empty():
		finish(-1, "does not compile: " + ", ".join(broken))
		return
	get_tree().create_timer(TIMEOUT_S).timeout.connect(finish.bind(-1, "the tests did not finish within %d s" % TIMEOUT_S))
	add_child((load(TESTS) as GDScript).new())


static func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out


## Called by run_tests.gd when every test has run, with its count of failed checks (-1: cut short).
func finish(failures: int, problem := "") -> void:
	if _done:
		return
	_done = true
	OS.remove_logger(_errors)
	var problems: Array[String] = []
	if failures > 0:
		problems.append("%d failed check%s" % [failures, "" if failures == 1 else "s"])
	if _errors.count > 0:
		problems.append("%d error%s logged, first: %s" % [_errors.count, "" if _errors.count == 1 else "s", _errors.first])
	if problem != "":
		problems.append(problem)
	print("\n%s" % ("PASSED" if problems.is_empty() else "FAILED: " + "; ".join(problems)))
	get_tree().quit(0 if problems.is_empty() else 1)
