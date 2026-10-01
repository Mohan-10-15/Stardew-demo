class_name Inventory
extends Resource
## A grid of item stacks, and the rules about moving them around.
##
## Deliberately a [Resource] of plain values so it can be saved, compared
## field-by-field in tests, and constructed without a scene. The rules below came
## straight out of the retired Unity `InventorySim` via
## `docs/SALVAGED_DESIGN.md`, which recorded 29 tests' worth of edge cases; each
## comment below names the trap it closes.
##
## ## Quality matters, because "one parsnip" is not one number
##
## Stacks merge on `(id, quality)`, never on id alone. Silver is not Normal, and
## merging them would destroy value every time the player sorted their bag.

enum Quality { NORMAL, SILVER, GOLD }

## Emitted after any change to the bag's contents.
##
## A local signal rather than a publish straight onto [EventBus], for two reasons.
## This is a plain [Resource] with no scene and no owner, so it cannot know who
## should hear about a change; and reaching for an autoload from here makes the
## file impossible to load from a `--script` run, because autoloads are not
## global identifiers until they are in the tree (see `AGENTS.md`, "Two
## Godot-specific traps"). Whoever owns the bag — [FarmService] — relays this to
## `EventBus.inventory_changed` once it has somewhere to publish from.
##
## Named `contents_changed` rather than the obvious `changed` because [Resource]
## already declares `changed`, and shadowing a native signal makes this file
## unparseable.
signal contents_changed

## A single occupied slot. An empty slot is a null entry, not a zero-count stack:
## a slot holding zero items must be cleaned up, or the bag fills with ghosts that
## the player cannot see and cannot clear.
class ItemStack extends Resource:
	var id: StringName = &""
	var amount: int = 0
	var quality: int = Quality.NORMAL

	func _init(p_id: StringName = &"", p_amount: int = 0, p_quality: int = Quality.NORMAL) -> void:
		id = p_id
		amount = p_amount
		quality = p_quality

	func is_empty() -> bool:
		return id.is_empty() or amount <= 0

	func copy() -> ItemStack:
		return ItemStack.new(id, amount, quality)

	## "Parsnip x3" / "Parsnip x3 (Silver)"
	func describe() -> String:
		if is_empty():
			return ""
		var label := String(id)
		if amount > 1:
			label += " x%d" % amount
		if quality != Quality.NORMAL:
			label += " (%s)" % Quality.keys()[quality]
		return label


## Total slots in the bag.
@export var capacity: int = 24
var _slots: Array = []  # Array[ItemStack | null]


func _init(p_capacity: int = 24) -> void:
	capacity = maxi(p_capacity, 1)
	_resize(capacity)


## Contents of one slot, or null when the slot is empty or out of range.
func get_slot(index: int) -> ItemStack:
	if index < 0 or index >= _slots.size():
		return null
	return _slots[index] as ItemStack


## Whether the slot is empty. Distinct from "holds null": an empty slot and a
## broken slot are different bugs and worth telling apart in a test.
func is_slot_empty(index: int) -> bool:
	return get_slot(index) == null


func slot_count() -> int:
	return _slots.size()


func is_full() -> bool:
	return free_slot_count() == 0


func free_slot_count() -> int:
	var n := 0
	for slot: ItemStack in _slots:
		if slot == null:
			n += 1
	return n


func is_empty() -> bool:
	for slot: ItemStack in _slots:
		if slot != null and not slot.is_empty():
			return false
	return true


## Whether this bag could accept [param amount] of [param id] at [param quality].
##
## The check every refusal goes through, so a shop cannot sell into a full bag
## and the player cannot end up with an item they cannot see.
func can_fit(id: StringName, amount: int = 1, quality: int = Quality.NORMAL) -> bool:
	return _remaining_space(id, amount, quality) >= amount


## Adds items, merging into matching stacks first and splitting the overflow
## across free slots.
##
## All-or-nothing. A partial add would leave the player short of what they were
## told they bought, with no indication of which items are missing — the salvage
## notes call this out explicitly.
##
## Returns how many were actually added, which is either `amount` or `0`.
func add(id: StringName, amount: int = 1, quality: int = Quality.NORMAL) -> int:
	if id.is_empty() or amount <= 0:
		return 0
	if not can_fit(id, amount, quality):
		# No logging here. See the `changed` signal's docs: this file must load in a
		# `--script` run, where `Log` does not resolve. The refusal is not silent —
		# `add` returns 0, and every caller treats 0 as "did not happen".
		return 0
	var remaining := amount
	for slot: ItemStack in _slots:
		if remaining <= 0:
			break
		if slot == null:
			continue
		if slot.id == id and slot.quality == quality:
			var room := _max_stack() - slot.amount
			if room > 0:
				var moved := mini(room, remaining)
				slot.amount += moved
				remaining -= moved
	# Second pass for genuinely free slots, so a merge never consumes a slot that
	# a split needed.
	for i: int in range(_slots.size()):
		if remaining <= 0:
			break
		if _slots[i] != null:
			continue
		var stack := ItemStack.new(id, mini(remaining, _max_stack()), quality)
		_slots[i] = stack
		remaining -= stack.amount
	_notify_changed()
	return amount - remaining


## Removes up to [param amount] of [param id], taking the **lowest quality first**.
##
## Lowest quality first is the salvage note's rule, and it is the difference
## between a bag that conserves value and one that eats it: consuming a silver
## parsnip when a normal one is available destroys the bonus.
##
## Unknown ids remove nothing and return 0 rather than erroring — callers are
## allowed to ask for something that is not there.
func remove(id: StringName, amount: int = 1) -> int:
	if id.is_empty() or amount <= 0:
		return 0
	var remaining := amount
	for quality: int in _quality_order():
		for i: int in range(_slots.size()):
			if remaining <= 0:
				break
			var slot := get_slot(i)
			if slot == null or slot.id != id or slot.quality != quality:
				continue
			var taken := mini(slot.amount, remaining)
			slot.amount -= taken
			remaining -= taken
			# Emptied slots are nulled out, never left as zero-count stacks. The
			# salvage notes call this out: a zero stack is invisible to the player
			# and still occupies the slot forever.
			if slot.amount <= 0:
				_slots[i] = null
	_prune_empty_stacks()
	if remaining < amount:
		_notify_changed()
	return amount - remaining


## Whether [param amount] of [param id] is present in total.
func count(id: StringName) -> int:
	var total := 0
	for slot: ItemStack in _slots:
		if slot != null and slot.id == id:
			total += slot.amount
	return total


## Total units of [param id] at exactly [param quality].
func count_quality(id: StringName, quality: int) -> int:
	var total := 0
	for slot: ItemStack in _slots:
		if slot != null and slot.id == id and slot.quality == quality:
			total += slot.amount
	return total


## Swaps, merges or moves between two slots.
##
## Handles all five cases the salvage notes list: two different items swap, matching
## stacks merge, a move into an empty slot, a no-op from an empty slot, and a no-op
## onto itself. Returns true when the board actually changed.
func move_slots(from_index: int, to_index: int) -> bool:
	if from_index == to_index:
		return false
	var source := get_slot(from_index)
	if source == null or source.is_empty():
		return false
	if to_index < 0 or to_index >= _slots.size():
		return false
	var destination := get_slot(to_index)

	if destination == null or destination.is_empty():
		_slots[to_index] = source
		_slots[from_index] = null
		_notify_changed()
		return true

	if destination.id == source.id and destination.quality == source.quality:
		var room := _max_stack() - destination.amount
		if room <= 0:
			# Both stacks are full, so there is nowhere for the merge to go.
			# Swapping two identical full stacks is a no-op either way.
			return false
		var moved := mini(room, source.amount)
		destination.amount += moved
		source.amount -= moved
		if source.amount <= 0:
			_slots[from_index] = null
		_notify_changed()
		return true

	# Different items, or the same item at a different quality: a straight swap.
	# Quality blocks the merge on purpose — see the class docs.
	_slots[to_index] = source
	_slots[from_index] = destination
	_notify_changed()
	return true


## Lowest index holding [param id] at [param quality], or -1.
func find_slot(id: StringName, quality: int = -1) -> int:
	for i: int in range(_slots.size()):
		var slot := get_slot(i)
		if slot == null or slot.id != id:
			continue
		if quality < 0 or slot.quality == quality:
			return i
	return -1


## Grows or shrinks the bag.
##
## Growing keeps everything. Shrinking **refuses** when items would be lost, and
## succeeds when the tail being removed is empty. Silently dropping the overflow
## would delete a player's crops with no warning, so the caller gets `false` and
## can say "empty some slots first".
func resize(new_capacity: int) -> bool:
	var target := maxi(new_capacity, 1)
	if target == _slots.size():
		return true
	if target < _slots.size():
		var dropped := 0
		for i: int in range(target, _slots.size()):
			var slot := get_slot(i)
			if slot != null and not slot.is_empty():
				dropped += slot.amount
		if dropped > 0:
			return false
		while _slots.size() > target:
			_slots.resize(target)
		capacity = target
		_notify_changed()
		return true
	while _slots.size() < target:
		_slots.append(null)
	capacity = target
	_notify_changed()
	return true


## `[(id, quality) -> total]`, ignoring empty slots.
##
## The bag's answer to "what am I carrying", for a shipping bin or a quest check.
## Keyed by a string rather than nested arrays because the consumer only ever
## wants "how much of this thing".
func summary() -> Dictionary:
	var out := {}
	for slot: ItemStack in _slots:
		if slot == null or slot.is_empty():
			continue
		var key := "%s:%d" % [slot.id, slot.quality]
		out[key] = int(out.get(key, 0)) + slot.amount
	return out


func to_dict() -> Dictionary:
	var stacks: Array = []
	for slot: ItemStack in _slots:
		if slot == null or slot.is_empty():
			stacks.append(null)
			continue
		stacks.append({
			"id": String(slot.id),
			"amount": slot.amount,
			"quality": slot.quality,
		})
	return {"capacity": capacity, "slots": stacks}


## Restores from [method to_dict].
##
## A saved bag may be *longer* or *shorter* than the current one, so the
## capacity comes from the payload and slots past the end are dropped rather than
## overflowing an array. Empty slots stay null, which is what makes a save file
## readable in a diff: an empty slot is `null`, not a zero-count object.
func from_dict(data: Dictionary) -> void:
	var saved_capacity := maxi(int(data.get("capacity", capacity)), 1)
	var stacks: Variant = data.get("slots", [])
	_slots.clear()
	if stacks is Array:
		for entry: Variant in stacks:
			if entry == null or not entry is Dictionary:
				_slots.append(null)
				continue
			var row: Dictionary = entry
			var id := StringName(str(row.get("id", "")))
			var amount := int(row.get("amount", 0))
			if id.is_empty() or amount <= 0:
				_slots.append(null)
				continue
			_slots.append(ItemStack.new(id, amount, _clamp_quality(row.get("quality", 0))))
	_resize(maxi(saved_capacity, _slots.size()))
	_prune_empty_stacks()
	_notify_changed()


## Gives the bag its starting contents.
##
## Used by a new game. Leaves no null slot only if the loadout actually fits,
## which the caller should have checked — so the leftover assertion is a real
## signal, not decoration.
func set_contents(entries: Array) -> int:
	for i: int in range(_slots.size()):
		_slots[i] = null
	var added := 0
	for entry: Variant in entries:
		if not entry is Dictionary:
			continue
		var row: Dictionary = entry
		added += add(
			StringName(str(row.get("id", ""))),
			int(row.get("amount", 1)),
			_clamp_quality(row.get("quality", 0))
		)
	return added


func copy() -> Inventory:
	var clone := Inventory.new(capacity)
	clone.from_dict(to_dict())
	return clone


func describe_slot(index: int) -> String:
	var slot := get_slot(index)
	return slot.describe() if slot != null else ""


## How many items of `id`/`quality` the bag could still take.
##
## Room in partial stacks plus room in free slots, with the overflow past one
## full stack needing a fresh slot. Getting this wrong is how a bag reports "full"
## while visibly having an empty row.
func _remaining_space(id: StringName, amount: int, quality: int) -> int:
	var space := 0
	var free := 0
	for slot: ItemStack in _slots:
		if slot == null:
			free += 1
		elif slot.id == id and slot.quality == quality:
			space += maxi(_max_stack() - slot.amount, 0)
	if free <= 0:
		return space
	# Every free slot can take a full stack, plus whatever is left in partial ones.
	return space + free * _max_stack()


func _max_stack() -> int:
	return 99


func _quality_order() -> Array[int]:
	# Lowest quality first, so `remove` spends the common stuff before the
	# valuable stuff. Enumerated rather than sorted so a new quality has to be
	# placed deliberately.
	var order: Array[int] = [Quality.NORMAL, Quality.SILVER, Quality.GOLD]
	order.sort()
	return order


static func _clamp_quality(value: Variant) -> int:
	return clampi(int(value), Quality.NORMAL, Quality.GOLD)


## Drops any stack that has been reduced to zero, wherever it is.
##
## Called after removal rather than inline, because `remove` decrements across
## several slots and a slot can empty at any point in the loop. Zero-count stacks
## are the ghost-slot bug from the salvage notes.
func _prune_empty_stacks() -> void:
	for i: int in range(_slots.size()):
		var slot := get_slot(i)
		if slot != null and slot.amount <= 0:
			_slots[i] = null


func _resize(target: int) -> void:
	while _slots.size() < target:
		_slots.append(null)
	while _slots.size() > target:
		_slots.resize(target)


func _notify_changed() -> void:
	contents_changed.emit()