class_name LayerRigRow
extends RefCounted
## The skeleton row on a layer's settings sheet.
##
## Lifted out of `layers_panel.gd`, which had grown past its limit, and lifted
## along a real seam: this is one subject — a layer's bones — and it is the
## only place in the settings sheet that has to reason about what having a
## skeleton *means* for the rest of the tools.

## Adds "Add bone" or "Correct the bones", and "Remove the bones" beside it.
##
## Bones belong to a layer, so they are offered where a layer is being talked
## about rather than in a room reached through a curve tool. Tap the layer you
## want to move, tap this, lay the skeleton, tap Accept.
static func build(panel: LayersPanel, l: LayerStack.Layer, index: int,
		into: VBoxContainer) -> void:
	if l == null or into == null or panel == null:
		return
	if l.is_background:
		return

	# --- bones belong to animation, and nowhere else ---
	#
	# A skeleton exists to be posed over time. Where there is no timeline
	# nothing to pose, and on a plain
	# drawing there is no timeline for a pose to be a key on, so the whole
	# feature collapses to "the drawing can be bent once and left bent". That
	# is not a rig, it is a distortion tool, and IVORY already has one of
	# those in the puppet warp.
	#
	# Offered on the wrong kind of project it was worse than useless: it locks
	# the layer against every drawing tool the moment bones are accepted, so
	# somebody who tried it on a sketch got a layer they could no longer draw
	# on in exchange for a pose that nothing would ever play back.
	#
	# A layer that already carries a skeleton still shows the row wherever it
	# is, so that a rig which arrived on the wrong project — transferred in,
	# or laid before this rule existed — can still be taken off. Hiding the
	# only way to remove something is how a layer becomes permanently stuck.
	if not boned_here(panel) and l.rig.is_empty():
		return

	var boned: bool = not l.rig.is_empty()
	var rig_it: Button = UiKit.make_text_button(
		UiKit.label_for("Correct the bones", "صحّح العظام") if boned
		else UiKit.label_for("Add bone", "أضف عظاماً"), true)
	rig_it.pressed.connect(func() -> void:
		panel.stack.set_active(index)
		panel.ask_for_bones(index))
	into.add_child(rig_it)

	if not boned:
		note(into, UiKit.label_for(
			"Opens this layer on its own to take a skeleton. Once the bones are accepted the drawing is moved by dragging its joints, here on the canvas — and the layer is for posing only until they come off.",
			"يفتح هذه الطبقة وحدها لتأخذ هيكلاً. وبعد قبول العظام يُحرَّك الرسم بسحب مفاصله هنا على اللوحة — وتصير الطبقة للتحريك فقط حتى تُزال."))
		return

	# Taking them off, beside putting them on — the same decision
	# reconsidered. It was reachable only by opening the bone room, clearing
	# every bone by hand and accepting an empty skeleton: which works, and
	# which nobody would ever guess.
	var strip: Button = UiKit.make_text_button(
		UiKit.label_for("Remove the bones", "أزل العظام"), true)
	strip.pressed.connect(func() -> void:
		panel.stack.set_active(index)
		panel.ask_to_remove_bones(index))
	into.add_child(strip)
	note(into, UiKit.label_for(
		"While this layer has a skeleton it is for posing only. Drawing, B-Spline, Puppet warp and the rest are held back — one heavy tool at a time, or two of them fight over the same pixels and you get the drawing twice. Remove the bones to draw on it again.",
		"ما دام لهذه الطبقة هيكل فهي للتحريك فقط. الرسم وبي-سبلاين وتشويه الدمية وغيرها محجوبة — أداة ثقيلة واحدة في كلّ مرّة، وإلّا تنازعت اثنتان على البكسلات نفسها فظهر الرسم مرّتين. أزل العظام لتعود الرسم عليها."))

## A line of quiet explanation under a control.
static func note(into: VBoxContainer, text: String) -> void:
	var say: Label = UiKit.make_label(text, 11.0, UiKit.TEXT_DIM)
	say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	into.add_child(say)

## Whether the project being looked at is one bones mean anything on.
##
## Read through the panel rather than from a global, so that a panel built for
## a project that is not the active one — which the transfer sheet does — asks
## about the right project.
static func boned_here(panel: LayersPanel) -> bool:
	if panel == null or panel.stack == null:
		return false
	var view: CanvasView = panel.view
	if view == null or view.projects == null:
		return false
	var p: ProjectManager.Project = view.projects.focus_on
	if p == null:
		p = view.projects.active
	if p == null:
		return false
	return p.kind == ProjectManager.Kind.ANIMATION
