class_name Native
extends RefCounted
## Whether the C++ half of the app is here, and how to reach it.
##
## ## The rule this whole file exists to enforce
##
## **Nothing in IVORY may require the extension.** The GDScript that was doing
## each of these jobs is still there, still correct, and still what runs when
## the library has not been built for the platform in hand — which is every
## checkout before somebody runs `scons`, and every platform somebody has not
## got round to yet.
##
## So there is exactly one place that asks whether the native classes exist,
## and every caller asks it rather than asking Godot. A caller that reached for
## `IvoryWarp` directly would be a caller that stops working on a machine where
## the library is absent, and it would fail at the worst possible moment: when
## somebody is trying to build the app for the first time.
##
## ## Why it is asked once
##
## `ClassDB.class_exists` is not free and the answer cannot change while the
## app is running — an extension is loaded before the first scene and never
## unloaded. So it is asked on the first call and remembered.

## Nought means not yet asked, one means present, minus one means absent.
static var _warp: int = 0
static var _skin: int = 0
static var _touch: int = 0
static var _bone: int = 0
static var _canvas: int = 0
static var _comic: int = 0
static var _distort: int = 0
static var _store: int = 0
static var _lang: int = 0
static var _layout: int = 0
static var _smartbone: int = 0
static var _diagnostics: int = 0
static var _diagnostics_one: Object = null
static var _character360_rig: int = 0
static var _rigcore: int = 0
static var _animation: int = 0
static var _animation_launcher: int = 0
static var _animation_workspace_picker: int = 0
static var _stretchy_canvas_picker: int = 0
static var _selection_guard: int = 0
static var _mass_keeper: int = 0
static var _jiggle_physics: int = 0
static var _stretchy_export: int = 0
static var _stretchy_document: int = 0

static func _known(had: int, name: String) -> int:
	if had != 0:
		return had
	return 1 if ClassDB.class_exists(name) else -1

## True when the native solver for the puppet warp is available.
static func has_warp() -> bool:
	_warp = _known(_warp, "IvoryWarp")
	return _warp == 1

static func has_skin() -> bool:
	_skin = _known(_skin, "IvorySkin")
	return _skin == 1

static func has_touch() -> bool:
	_touch = _known(_touch, "IvoryTouch")
	return _touch == 1

static func has_bone() -> bool:
	_bone = _known(_bone, "IvoryBone")
	return _bone == 1

static func has_canvas() -> bool:
	_canvas = _known(_canvas, "IvoryCanvas")
	return _canvas == 1

static func has_comic() -> bool:
	_comic = _known(_comic, "IvoryComic")
	return _comic == 1

static func has_distort() -> bool:
	_distort = _known(_distort, "IvoryDistort")
	return _distort == 1

static func has_store() -> bool:
	_store = _known(_store, "IvoryStore")
	return _store == 1

static func has_lang() -> bool:
	_lang = _known(_lang, "IvoryLang")
	return _lang == 1

static func has_layout() -> bool:
	_layout = _known(_layout, "IvoryLayout")
	return _layout == 1

## True when the smart-bone dials are available.
static func has_smartbone() -> bool:
	_smartbone = _known(_smartbone, "IvorySmartBone")
	return _smartbone == 1

## A fresh smart-bone controller, or nothing.
static func smartbone() -> Object:
	if not has_smartbone():
		return null
	return ClassDB.instantiate("IvorySmartBone")

## Circular 0..360 pose correctives. Optional: the existing reference and
## GDScript paths remain the fallback when this class is absent.
static var _pose_deformer: int = 0
static func has_pose_deformer() -> bool:
	_pose_deformer = _known(_pose_deformer, "IvoryPoseDeformer")
	return _pose_deformer == 1

static func pose_deformer() -> Object:
	if not has_pose_deformer():
		return null
	return ClassDB.instantiate("IvoryPoseDeformer")

## Native Character 360 controller: multi-disc blending, pins, IK/FK,
## constraints, weight painting, independent FFD and rig-history.
static func has_character360_rig() -> bool:
	_character360_rig = _known(_character360_rig, "IvoryCharacter360Rig")
	return _character360_rig == 1

static func character360_rig() -> Object:
	if not has_character360_rig():
		return null
	return ClassDB.instantiate("IvoryCharacter360Rig")


## A fresh pack, or nothing. One per project — a pack is a file, and two
## projects sharing one object would be two documents writing to one file.
static func store() -> Object:
	if not has_store():
		return null
	return ClassDB.instantiate("IvoryStore")

## The language engine. One is enough: it holds which tongue is selected and
## nothing else, and the whole app is in one language at a time.
static var _lang_one: Object = null

static func lang() -> Object:
	if not has_lang():
		return null
	if _lang_one == null:
		_lang_one = ClassDB.instantiate("IvoryLang")
	return _lang_one

## A fresh layout resolver. One per group of controls being kept apart, since
## it holds the rectangles it is working on.
static func layout() -> Object:
	if not has_layout():
		return null
	return ClassDB.instantiate("IvoryLayout")

## A fresh native warp solver, or nothing.
static func warp() -> Object:
	if not has_warp():
		return null
	return ClassDB.instantiate("IvoryWarp")

## The skinning helper. One is enough for the whole app: it holds no state
## between calls, which is deliberate — a helper that remembered which layer it
## last worked on would be a second place the truth about a layer lived.
static var _skin_one: Object = null

static func skin() -> Object:
	if not has_skin():
		return null
	if _skin_one == null:
		_skin_one = ClassDB.instantiate("IvorySkin")
	return _skin_one

## A fresh native touch filter, or nothing. One per gesture, because it holds
## the velocity of the drag it is smoothing.
static func brush_touch() -> Object:
	if not has_touch():
		return null
	return ClassDB.instantiate("IvoryTouch")

static func warp_touch() -> Object:
	if not has_touch():
		return null
	return ClassDB.instantiate("IvoryTouch")

## A fresh native skeleton, or nothing.
##
## One per gesture rather than one shared, because it holds the bones it is
## solving: a second grab starting while the first is mid-solve would be two
## drags writing into one array, and the figure would come apart.
static func bones() -> Object:
	if not has_bone():
		return null
	return ClassDB.instantiate("IvoryBone")

## A fresh panel page, or nothing.
##
## One per comic page rather than one shared, because it holds that page's
## panels: two pages open at once through one object would be two layouts
## overwriting each other.
static func comic() -> Object:
	if not has_comic():
		return null
	return ClassDB.instantiate("IvoryComic")

static func distort() -> Object:
	if not has_distort():
		return null
	return ClassDB.instantiate("IvoryDistort")

## The canvas-size table. Stateless, so one is enough for the whole app.
static var _canvas_one: Object = null

static func canvas() -> Object:
	if not has_canvas():
		return null
	if _canvas_one == null:
		_canvas_one = ClassDB.instantiate("IvoryCanvas")
	return _canvas_one

# ---------------------------------------------------------------- stage 137
#
# Seven more, all optional in exactly the same way. Each `has_` asks once and
# remembers; each maker returns `null` when the library is absent, and every
# caller is written so that `null` means "do it the way it was done before".

static var _brush: int = 0
static var _blend: int = 0
static var _pose: int = 0
static var _arbiter: int = 0
static var _field: int = 0

## The stamp generator for the web, halo and chalk families, and the knife.
static func has_brush() -> bool:
	_brush = _known(_brush, "IvoryBrush")
	return _brush == 1

## Stateless, so one serves the whole app. Making a fresh one per stamp would
## mean the sRGB table and the hash state are rebuilt for every brush picked
## up, which is paid on the first stroke of every session.
static var _brush_one: Object = null

static func brush() -> Object:
	if not has_brush():
		return null
	if _brush_one == null:
		_brush_one = ClassDB.instantiate("IvoryBrush")
	return _brush_one

## The colour merge tool. Holds a surface, so callers get their own.
static func has_blend() -> bool:
	_blend = _known(_blend, "IvoryBlend")
	return _blend == 1

static func blend() -> Object:
	if not has_blend():
		return null
	return ClassDB.instantiate("IvoryBlend")

## The bone lock, the steady drag and the timeline bookkeeping.

static func has_rigcore() -> bool:
	_rigcore = _known(_rigcore, "IvoryRigCore")
	return _rigcore == 1

static func rigcore() -> Object:
	if not has_rigcore():
		return null
	return ClassDB.instantiate("IvoryRigCore")

## Native pose blending + deterministic animation-event crossing.
## The timeline remains authoritative; this object only accelerates numeric work.

## Native numerical guard for selection geometry. Optional: GDScript keeps a
## complete fallback so the editor remains usable before the extension is built.
static func has_selection_guard() -> bool:
	_selection_guard = _known(_selection_guard, "IvorySelectionGuard")
	return _selection_guard == 1

static func selection_guard() -> Object:
	if not has_selection_guard():
		return null
	return ClassDB.instantiate("IvorySelectionGuard")

## Native drawing-mass and skin-weight keeper. Keeps one object per pose path; it is stateless.
static func has_mass_keeper() -> bool:
	_mass_keeper = _known(_mass_keeper, "IvoryMassKeeper")
	return _mass_keeper == 1

static var _mass_keeper_one: Object = null
static func mass_keeper() -> Object:
	if not has_mass_keeper():
		return null
	if _mass_keeper_one == null:
		_mass_keeper_one = ClassDB.instantiate("IvoryMassKeeper")
	return _mass_keeper_one

## True when the native secondary-motion solver (hair, hems, jiggle) is
## available. Ported from Stretchy Studio's `physics.js` pendulum-chain
## vocabulary; see `ivory_jigglephysics.h` for what changed on the way.
static func has_jiggle_physics() -> bool:
	_jiggle_physics = _known(_jiggle_physics, "IvoryJigglePhysics")
	return _jiggle_physics == 1

## A fresh secondary-motion solver, or nothing.
##
## One per rigged layer, the same reason `smartbone()` is one per layer: it
## holds that layer's own chains and their live angles.
static func jiggle_physics() -> Object:
	if not has_jiggle_physics():
		return null
	return ClassDB.instantiate("IvoryJigglePhysics")

static func has_stretchy_export() -> bool:
	_stretchy_export = _known(_stretchy_export, "IvoryStretchyExport")
	return _stretchy_export == 1

static func stretchy_export() -> Object:
	if not has_stretchy_export():
		return null
	return ClassDB.instantiate("IvoryStretchyExport")

## Native Stretchy document/mesh/armature core.
static func has_stretchy_document() -> bool:
	_stretchy_document = _known(_stretchy_document, "IvoryStretchyDocument")
	return _stretchy_document == 1

static func stretchy_document() -> Object:
	if not has_stretchy_document():
		return null
	return ClassDB.instantiate("IvoryStretchyDocument")

static func has_animation_launcher() -> bool:
	_animation_launcher = _known(_animation_launcher, "IvoryAnimationLauncher")
	return _animation_launcher == 1

static func animation_launcher() -> Object:
	if not has_animation_launcher():
		return null
	return ClassDB.instantiate("IvoryAnimationLauncher")

## Native C++ UI panel containing the two real animation workspace buttons.
static func has_animation_workspace_picker() -> bool:
	_animation_workspace_picker = _known(_animation_workspace_picker, "IvoryAnimationWorkspacePicker")
	return _animation_workspace_picker == 1

static func animation_workspace_picker() -> Object:
	if not has_animation_workspace_picker():
		return null
	return ClassDB.instantiate("IvoryAnimationWorkspacePicker")

## Native C++ canvas-size chooser for the Stretchy creation hand-off.
static func has_stretchy_canvas_picker() -> bool:
	_stretchy_canvas_picker = _known(_stretchy_canvas_picker, "IvoryStretchyCanvasPicker")
	return _stretchy_canvas_picker == 1

static func stretchy_canvas_picker() -> Object:
	if not has_stretchy_canvas_picker():
		return null
	return ClassDB.instantiate("IvoryStretchyCanvasPicker")

static func has_animation() -> bool:
	_animation = _known(_animation, "IvoryAnimation")
	return _animation == 1

static func animation() -> Object:
	if not has_animation():
		return null
	return ClassDB.instantiate("IvoryAnimation")

static func has_pose() -> bool:
	_pose = _known(_pose, "IvoryPose")
	return _pose == 1

static func pose() -> Object:
	if not has_pose():
		return null
	return ClassDB.instantiate("IvoryPose")

## One tool at a time, and the four-finger cancel.
static func has_arbiter() -> bool:
	_arbiter = _known(_arbiter, "IvoryArbiter")
	return _arbiter == 1

## Deliberately one for the whole app rather than one per screen. The rule it
## enforces is "no two buttons anywhere are live at once", and an arbiter per
## screen would enforce "no two on this screen", which is the bug it exists to
## fix wearing a different hat.
static var _arbiter_one: Object = null

static func arbiter() -> Object:
	if not has_arbiter():
		return null
	if _arbiter_one == null:
		_arbiter_one = ClassDB.instantiate("IvoryArbiter")
	return _arbiter_one

## The endless canvas: tile addressing and pan/zoom-stable anchoring.
static func has_field() -> bool:
	_field = _known(_field, "IvoryField")
	return _field == 1

static func field() -> Object:
	if not has_field():
		return null
	return ClassDB.instantiate("IvoryField")

# ---------------------------------------------------------------- stage 138

static var _spline: int = 0
static var _rig360: int = 0
static var _text_tool: int = 0

## The B-spline room's curve: exact local editing, arc length, curve space.
static func has_spline() -> bool:
	_spline = _known(_spline, "IvorySpline")
	return _spline == 1

static func spline() -> Object:
	if not has_spline():
		return null
	return ClassDB.instantiate("IvorySpline")

## The Character 360 rig: smart bones, rest binding, layers, export.
static func has_rig360() -> bool:
	_rig360 = _known(_rig360, "IvoryRig360")
	return _rig360 == 1



## Two-view Character 360 reconstruction: front + side -> depth model.
static var _character360: int = 0

static func has_character360() -> bool:
	_character360 = _known(_character360, "IvoryCharacter360")
	return _character360 == 1

static func character360() -> Object:
	if not has_character360():
		return null
	return ClassDB.instantiate("IvoryCharacter360")

static func rig360() -> Object:
	if not has_rig360():
		return null
	return ClassDB.instantiate("IvoryRig360")

## Whether the app is running with its native half at all.
##
## For the one place that says so out loud — the settings panel — and for
## nothing else. No behaviour anywhere may branch on this beyond choosing
## which implementation to call.


## Native text-object interaction kernel. It owns only hot geometry and
## preview transforms; shaping and rasterization remain with TextServer.
static func has_text_tool() -> bool:
	_text_tool = _known(_text_tool, "IvoryTextTool")
	return _text_tool == 1

static func text_tool() -> Object:
	if not has_text_tool():
		return null
	return ClassDB.instantiate("IvoryTextTool")


## Native integrity instruments. They are optional like every other native
## service, but when present they validate the geometry boundary before it can
## reach the renderer.
static func has_diagnostics() -> bool:
	_diagnostics = _known(_diagnostics, "IvoryDiagnostics")
	return _diagnostics == 1

static func diagnostics() -> Object:
	if not has_diagnostics():
		return null
	if _diagnostics_one == null:
		_diagnostics_one = ClassDB.instantiate("IvoryDiagnostics")
	return _diagnostics_one

static func present() -> bool:
	return has_warp() and has_skin() and has_touch()

static var _guard20: int = 0
static var _guard20_one: Object = null

## Twenty native integrity instruments. The object is optional like every
## other C++ service, so source checkouts still run on the GDScript path.
static func has_guard20() -> bool:
	_guard20 = _known(_guard20, "IvoryGuard20")
	return _guard20 == 1

static func guard20() -> Object:
	if not has_guard20():
		return null
	if _guard20_one == null:
		_guard20_one = ClassDB.instantiate("IvoryGuard20")
	return _guard20_one


## The native warp, bone and band engines.
##
## Same rule as everything above: asked for by name, and absent without
## complaint. Each has a GDScript path that already exists and goes on
## working, so a checkout with no compiled library behaves the same and is
## only slower.
static var _meshforge: int = 0
static var _arap: int = 0
static var _bonepose: int = 0
static var _timeline: int = 0
static var _stability: int = 0

## Shared native stability kernel for high-rigging gestures and control points.
static func has_stability() -> bool:
	_stability = _known(_stability, "IvoryStability")
	return _stability == 1

static func stability() -> Object:
	if not has_stability():
		return null
	return ClassDB.instantiate("IvoryStability")

## Lays a warp mesh that follows the drawing's outline rather than a grid over
## its bounding box, and keeps a stroke one pixel wide.
static func has_meshforge() -> bool:
	_meshforge = _known(_meshforge, "IvoryMeshForge")
	return _meshforge == 1

static func meshforge() -> Object:
	if not has_meshforge():
		return null
	return ClassDB.instantiate("IvoryMeshForge")

## As-rigid-as-possible deformation with pins as hard constraints — the
## difference between stretching a drawing and dragging it.
static func has_arap() -> bool:
	_arap = _known(_arap, "IvoryArapSolver")
	return _arap == 1

static func arap() -> Object:
	if not has_arap():
		return null
	return ClassDB.instantiate("IvoryArapSolver")

## The quick bones: pinning, the ring, and a chain solved by reaching.
static func has_bonepose() -> bool:
	_bonepose = _known(_bonepose, "IvoryBonePose")
	return _bonepose == 1

static func bonepose() -> Object:
	if not has_bonepose():
		return null
	return ClassDB.instantiate("IvoryBonePose")

## Every question the timeline band asks, for all layers in one call.
static func has_timeline_index() -> bool:
	_timeline = _known(_timeline, "IvoryTimelineIndex")
	return _timeline == 1

static func timeline_index() -> Object:
	if not has_timeline_index():
		return null
	return ClassDB.instantiate("IvoryTimelineIndex")
