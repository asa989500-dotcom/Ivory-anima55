class_name LayerCharacter360
extends RefCounted
## Which layers belong to a Character 360 file, and what moves them.
##
## Lifted out of `layer_stack.gd` at stage 145. `LayerStack` still answers
## `character360_group`, `in_character360_file` and `character360_motion_layer`
## and delegates here, so nothing that called them changed.
##
## The rule these three encode is the one the single `+` in the layers panel
## depends on: a folder is a Character 360 file as soon as anything inside it
## is marked so, and a layer added while the selection is inside one joins it
## and is carried by its bones. Generous on purpose — a scene saved before
## folders carried the flag still reads correctly.

## The folder a Character 360 file lives in, or 0 when `index` is not in one.
##
## A file counts as a Character 360 file as soon as anything inside it is
## marked so — the drawing the builder committed, or its motion layer. That
## is deliberately generous: a folder holding a rigged character is a
## Character 360 file whether or not the flag was written on the folder
## itself, including in scenes saved before folders carried the flag at all.
static func character360_group(owner_: LayerStack, index: int) -> int:
	if index < 0 or index >= owner_.layers.size():
		return 0
	var gid: int = owner_.layers[index].group_id
	if gid == 0:
		return 0
	for l in owner_.layers:
		if l.group_id == gid and (l.is_character360 or l.is_character360_motion):
			return gid
	return 0

## True when the selection is standing inside a Character 360 file.
static func in_character360_file(owner_: LayerStack, index: int) -> bool:
	return owner_.character360_group(index) != 0

## The one motion layer of a Character 360 file, or null.
##
## There is exactly one per file by construction, and nothing in the UI can
## make a second: the builder creates it, and the layers panel has no button
## that makes bone layers at all any more.
static func character360_motion_layer(owner_: LayerStack, gid: int) -> LayerStack.Layer:
	if gid == 0:
		return null
	for l in owner_.layers:
		if l.group_id == gid and l.is_character360_motion:
			return l
	return null
