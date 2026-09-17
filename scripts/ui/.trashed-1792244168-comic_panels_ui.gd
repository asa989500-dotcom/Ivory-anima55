class_name ComicPanelsUi
extends RefCounted
## Comic-only compass entries. Speech bubbles and page-size controls are
## intentionally absent; cutting a page into frames is the comic-only tool.

static func rows(kind: int) -> Array:
	if kind != ProjectManager.Kind.COMIC:
		return []
	return [
		{
			"icon": "panel_cut",
			"title": UiKit.label_for("Frames", "التقسيم"),
			"note": UiKit.label_for(
				"Cut the page into frames and choose which one you are drawing in. A cut need not cross the whole page — draw one down the middle, then a shorter one inside either half, and the other half is untouched.",
				"قسّم الصفحة إلى إطارات واختر الإطار الذي ترسم فيه. ولا يلزم أن يعبر القصّ الصفحة كلّها — اقسمها من الوسط، ثمّ اقسم أحد النصفين بخطٍّ أقصر، والنصف الآخر لا يُمسّ."),
			"key": "panels",
		},
	]

## The label for the perspective ruler, which lives with the shape tools
## rather than here.
##
## A ruler is a constraint on a *line*, and lines are made with the shape
## tools — so that is where it belongs, in a comic or out of one. Backgrounds
## are not a comic-only problem: anybody drawing a room wants the room's edges
## to meet properly.
static func ruler_label(kind: int) -> String:
	match kind:
		PerspectiveRuler.Kind.ONE_POINT:
			return UiKit.label_for("One point", "نقطة واحدة")
		PerspectiveRuler.Kind.TWO_POINT:
			return UiKit.label_for("Two points", "نقطتان")
		PerspectiveRuler.Kind.THREE_POINT:
			return UiKit.label_for("Three points", "ثلاث نقاط")
		_:
			return UiKit.label_for("No ruler", "بلا مسطرة")
