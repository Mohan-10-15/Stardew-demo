extends RefCounted
## Remembers the last [signal EventBus] event a test cares about.
##
## ## Why this exists
##
## The quest suite asserts that a refusal says *which* refusal it was, not merely that
## something was refused. Capturing an event means connecting to it, and a plain array of
## captured events has to be disconnected by hand — get that wrong and the connection
## outlives the case, so a later case's refusal is written into a dead suite's array and
## the failure lands in the wrong place.
##
## ## Why every argument is kept
##
## Quest signals carry two or three arguments and they are not interchangeable:
## [signal EventBus.quest_turned_in_failed] ends in a reason,
## [signal EventBus.quest_progress_changed] ends in two amounts. A recorder with fixed
## "last_reason" and "last_id" slots silently drops the second amount, and the case that
## wanted it fails on a missing method rather than on a wrong number. Storing the argument
## list means a signal that later gains an argument does not need this file changed.
##
## ## What this is not
##
## Not an assertion. It records; the case asserts. A helper that decided what the right
## answer was would move the interesting question out of the test and into the harness.

## How many times the watched signal has fired since [method watch] was called.
var count: int = 0
## The arguments of the most recent event, in order. One event is enough: every case wants
## the last thing that happened, not a history.
var args: Array = []


## Starts recording [param signal_name] on [param bus].
##
## Watching the same signal twice is a re-record, not a second connection: a case that
## watches a signal, fires an event to learn what it looks like, and then watches it again
## would otherwise log a failed connect and leave the old connection live.
func watch(bus: Object, signal_name: StringName) -> void:
	if bus == null or not bus.has_signal(signal_name):
		return
	if bus.is_connected(signal_name, _on_event):
		bus.disconnect(signal_name, _on_event)
	count = 0
	args = []
	bus.connect(signal_name, _on_event)


## Stops recording [param signal_name] on [param bus].
##
## Explicit rather than relying on the recorder being freed. A case that watches three
## signals leaves three live connections behind, and the next case's first event lands in
## the previous case's arrays — a failure that reports the wrong case entirely.
func stop(bus: Object, signal_name: StringName) -> void:
	if bus == null or not bus.has_signal(signal_name):
		return
	if bus.is_connected(signal_name, _on_event):
		bus.disconnect(signal_name, _on_event)
	count = 0
	args = []


## Argument [param index] of the last event, or an empty [StringName] when the event did
## not carry one. Named rather than indexing `args` at the call site so a signal that gains
## or loses a leading argument is a change here and nowhere else.
func arg(index: int) -> Variant:
	if index < 0 or index >= args.size():
		return &""
	return args[index]


func _on_event(a: Variant = null, b: Variant = null, c: Variant = null) -> void:
	count += 1
	args = [a, b, c]