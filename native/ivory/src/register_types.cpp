#include "register_types.h"

#include "ivory_bone.h"
#include "ivory_comic.h"
#include "ivory_distort.h"
#include "ivory_lang.h"
#include "ivory_layout.h"
#include "ivory_store.h"
#include "ivory_canvas.h"
#include "ivory_skin.h"
#include "ivory_touch.h"
#include "ivory_warp.h"
#include "ivory_brush.h"
#include "ivory_blend.h"
#include "ivory_pose.h"
#include "ivory_arbiter.h"
#include "ivory_field.h"
#include "ivory_spline.h"
#include "ivory_rig360.h"
#include "ivory_text_tool.h"
#include "ivory_character360.h"
#include "ivory_smartbone.h"
#include "ivory_character360_rig.h"
#include "ivory_diagnostics.h"
#include "ivory_guard20.h"
#include "ivory_meshforge.h"
#include "ivory_arap.h"
#include "ivory_bonepose.h"
#include "ivory_timeline.h"
#include "ivory_rigcore.h"
#include "ivory_animation.h"
#include "ivory_animation_launcher.h"
#include "ivory_animation_workspace_picker.h"
#include "ivory_stretchy_canvas_picker.h"
#include "ivory_pose_deformer.h"
#include "ivory_selection_guard.h"
#include "ivory_mass_keeper.h"
#include "ivory_jigglephysics.h"
#include "ivory_stretchy_export.h"
#include "ivory_stretchy_document.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

// Nineteen classes, and nothing else crosses the boundary.
//
// Each is a `RefCounted` holding plain arrays, so the GDScript side owns them
// the way it owns anything else and there is no lifetime to reason about. And
// each is optional: `scripts/native.gd` asks whether the class exists and
// falls back to the GDScript that was already doing the job if it does not.
// A build of the app without this library is a working build.
void initialize_ivory_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(IvoryWarp);
	GDREGISTER_CLASS(IvorySkin);
	GDREGISTER_CLASS(IvoryTouch);
	GDREGISTER_CLASS(IvoryBone);
	GDREGISTER_CLASS(IvoryCanvas);
	GDREGISTER_CLASS(IvoryComic);
	GDREGISTER_CLASS(IvoryDistort);
	GDREGISTER_CLASS(IvoryStore);
	GDREGISTER_CLASS(IvoryLang);
	GDREGISTER_CLASS(IvoryLayout);

	// Added at stage 137. Each is optional in exactly the same way as the
	// eleven above: `scripts/native.gd` asks whether the class exists and
	// the GDScript that was already doing the job runs when it does not.
	GDREGISTER_CLASS(IvoryBrush);
	GDREGISTER_CLASS(IvoryBlend);
	GDREGISTER_CLASS(IvoryPose);
	GDREGISTER_CLASS(IvoryArbiter);
	GDREGISTER_CLASS(IvoryField);

	// B-spline curve editing and the independent Character 360 rig.
	GDREGISTER_CLASS(IvorySpline);
	GDREGISTER_CLASS(IvoryRig360);
	GDREGISTER_CLASS(IvoryTextTool);
	GDREGISTER_CLASS(IvoryCharacter360);

	// Smart bones and the native Character 360 controller.
	GDREGISTER_CLASS(IvorySmartBone);
	GDREGISTER_CLASS(IvoryCharacter360Rig);
	GDREGISTER_CLASS(IvoryDiagnostics);
	GDREGISTER_CLASS(IvoryGuard20);


	// Stage 153. The puppet warp and the quick bones, rebuilt.
	//
	// `IvoryMeshForge` lays a mesh that follows the drawing's outline instead
	// of a grid over its bounding box, and keeps a stroke one pixel wide.
	//
	// `IvoryArapSolver` deforms it by minimising an as-rigid-as-possible
	// energy with pins as hard constraints, so a pull stretches the material
	// along its length rather than dragging a neighbourhood sideways, and a
	// pin is exactly where it was put no matter how many others there are.
	//
	// `IvoryBonePose` moves the quick bones: a pinned joint holds its
	// coordinates, the ring turns a joint's descendants and nothing above it,
	// and the chain is solved by reaching rather than by relaxation, which is
	// what stopped the far joint trembling.
	GDREGISTER_CLASS(IvoryMeshForge);
	GDREGISTER_CLASS(IvoryArapSolver);
	GDREGISTER_CLASS(IvoryBonePose);

	// The band's arithmetic for every layer in one call. `CelTrack` was already
	// careful — sorted lists, binary searches, a windowed walk — and none of
	// that was the cost. The cost was asking it once per layer from GDScript on
	// every redraw: a hundred layers at sixty frames a second is six thousand
	// crossings of the script boundary before a single pixel is drawn.
	GDREGISTER_CLASS(IvoryTimelineIndex);

	GDREGISTER_CLASS(IvoryRigCore);
	GDREGISTER_CLASS(IvoryAnimation);
	GDREGISTER_CLASS(IvoryAnimationLauncher);
	GDREGISTER_CLASS(IvoryAnimationWorkspacePicker);
	GDREGISTER_CLASS(IvoryStretchyCanvasPicker);
	// Optional circular 0..360 pose correctives. It is additive and does not
	// replace BoneRig, RigSkin, or the existing Character360 path.
	GDREGISTER_CLASS(IvoryPoseDeformer);
	GDREGISTER_CLASS(IvorySelectionGuard);
	GDREGISTER_CLASS(IvoryMassKeeper);

	GDREGISTER_CLASS(IvoryJigglePhysics);
	GDREGISTER_CLASS(IvoryStretchyExport);
	GDREGISTER_CLASS(IvoryStretchyDocument);
}

void uninitialize_ivory_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT ivory_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library,
			r_initialization);
	init_obj.register_initializer(initialize_ivory_module);
	init_obj.register_terminator(uninitialize_ivory_module);
	init_obj.set_minimum_library_initialization_level(
			MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
