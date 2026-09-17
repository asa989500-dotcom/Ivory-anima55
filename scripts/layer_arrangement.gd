class_name LayerArrangement
extends RefCounted
## Saving and restoring the *shape* of a layer stack.
##
## Lifted out of `layer_stack.gd` at stage 145, unchanged, because that file
## had grown past what one file is allowed here and the size checker refused
## to record it. Nothing about the behaviour moved with it: `LayerStack` still
## has `capture_arrangement` and `apply_arrangement`, and they now delegate.
##
## What belongs in here is the part that answers "what did the document look
## like" — order, folders, opacities, which layer was selected, and the
## Character 360 metadata that goes with them. Not the pixels: an arrangement
## is a few hundred bytes, which is the whole reason structural undo is cheap
## enough to keep on every action.

## The whole shape of the document as plain numbers — order, folders,
## opacities, which layer is selected. A few hundred bytes, which is why
## structural undo costs almost nothing to keep.
static func character360_meta(state: Dictionary) -> Dictionary:
	var out: Dictionary = state.duplicate(true)
	# Binary PNG buffers are project assets, not undo metadata. Keep filenames
	# only in arrangement snapshots so a single pose does not duplicate MBs.
	out.erase("front_png")
	out.erase("side_png")
	return out

static func capture_arrangement(owner_: LayerStack) -> Dictionary:
	var rows: Array = []
	for l in owner_.layers:
		rows.append({
			"id": l.id,
			"group": l.group_id,
			"opacity": l.opacity,
			"visible": l.visible,
			"locked": l.locked,
			"bone_layer": l.is_bone_layer,
			"character360": l.is_character360,
			"character360_motion": l.is_character360_motion,
			"character360_state": owner_._character360_meta(l.character360_state),
			"motion_position": l.motion_position,
			"motion_rotation": l.motion_rotation,
			"motion_scale": l.motion_scale,
			"title": l.title,
			# --- everything that was outside undo until now ---
			#
			# The skeleton and the pose it stands in was the big omission:
			# bones were laid, accepted and dragged, and none of it was ever
			# written anywhere undo could see, so taking back a pose was not
			# unreliable — it was not implemented. A rig is a few dozen
			# floats beside the tiles already kept here, so there was never a
			# cost reason for leaving it out. Where the writing sits and how
			# far it is turned were one-way doors for the same reason, and so
			# was the frame a layer was retired at.
			"rig": (l.rig as Dictionary).duplicate(true),
			"text_at": l.text_at,
			"text_turn": l.text_turn,
			"text_scale": l.text_scale,
			"text_size": l.text_size,
			"born_at": l.born_at,
			"gone_at": l.gone_at,
				})
	var folders: Array = []
	for g in owner_.groups:
		folders.append({
			"id": g.id,
			"title": g.title,
			"opacity": g.opacity,
			"visible": g.visible,
			"collapsed": g.collapsed,
			"switch": g.is_switch,
			"switch_index": g.switch_index,
			"animation": g.is_animation,
		})
	return {
		"layers": rows,
		"groups": folders,
		"active": owner_.active_index,
		"active_group": owner_.active_group,
		"solo": owner_.solo_id,
	}

static func apply_arrangement(owner_: LayerStack, state: Dictionary) -> void:
	# Folders first, so layers have somewhere to point at.
	var wanted_groups: Dictionary = {}
	for row in state["groups"]:
		var id: int = int(row["id"])
		wanted_groups[id] = true
		var g: LayerStack.Group = owner_.group_by_id(id)
		if g == null:
			g = LayerStack.Group.new()
			g.id = id
			g.node = Node2D.new()
			g.node.name = "Group_%d" % id
			owner_.add_child(g.node)
			owner_.groups.append(g)
			owner_._next_group_id = maxi(owner_._next_group_id, id + 1)
		g.title = String(row["title"])
		g.opacity = float(row["opacity"])
		g.visible = bool(row["visible"])
		g.collapsed = bool(row["collapsed"])
		# Defaulted rather than required: undo states captured by an older
		# build carry none of these, and an arrangement that refused to load
		# because it predates a feature would turn undo into a crash.
		g.is_switch = bool(row.get("switch", false))
		g.switch_index = maxi(int(row.get("switch_index", 0)), 0)
		g.is_animation = bool(row.get("animation", g.is_animation))
	for i in range(owner_.groups.size() - 1, -1, -1):
		if wanted_groups.has(owner_.groups[i].id):
			continue
		if owner_.groups[i].node != null:
			owner_.groups[i].node.queue_free()
		owner_.groups.remove_at(i)

	var rebuilt: Array[LayerStack.Layer] = []
	var kept: Dictionary = {}
	for row in state["layers"]:
		var layer_id: int = int(row["id"])
		var l: LayerStack.Layer = owner_.by_id(layer_id)
		if l == null:
			continue
		if owner_._detached.has(layer_id):
			owner_._reattach(l)
		l.group_id = int(row["group"])
		l.opacity = float(row["opacity"])
		l.visible = bool(row["visible"])
		l.locked = bool(row["locked"])
		l.is_bone_layer = bool(row.get("bone_layer", l.is_bone_layer))
		l.is_character360 = bool(row.get("character360", l.is_character360))
		l.is_character360_motion = bool(row.get("character360_motion", l.is_character360_motion))
		l.character360_state = (row.get("character360_state", l.character360_state) as Dictionary).duplicate(true)
		l.motion_position = row.get("motion_position", l.motion_position)
		l.motion_rotation = float(row.get("motion_rotation", l.motion_rotation))
		l.motion_scale = maxf(float(row.get("motion_scale", l.motion_scale)), 0.001)
		l.title = String(row["title"])
		# Defaulted to what the layer already has, never required. An undo
		# state captured by an older build carries none of these keys, and an
		# arrangement that refused to load because it predates a feature would
		# turn undo into a crash — see the same reasoning on folders above.
		l.rig = (row.get("rig", l.rig) as Dictionary).duplicate(true)
		l.text_at = row.get("text_at", l.text_at)
		l.text_turn = float(row.get("text_turn", l.text_turn))
		l.text_scale = float(row.get("text_scale", l.text_scale))
		l.text_size = row.get("text_size", l.text_size)
		l.born_at = int(row.get("born_at", l.born_at))
		l.gone_at = int(row.get("gone_at", l.gone_at))
		rebuilt.append(l)
		kept[layer_id] = true

	# Anything the saved shape does not mention steps off-stage rather than
	# being destroyed — a redo may well want it back.
	for l in owner_.layers:
		if not kept.has(l.id):
			owner_._detach(l)
	owner_.layers = rebuilt

	owner_.active_index = clampi(int(state["active"]), 0, maxi(owner_.layers.size() - 1, 0))
	owner_.active_group = int(state["active_group"])
	owner_.solo_id = int(state["solo"])
	owner_._rebuild()
	owner_.changed.emit()
	owner_.active_changed.emit(owner_.active_index)
