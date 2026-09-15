class_name ComicToolPanels
extends RefCounted
## The two panels a comic needs and nothing else does.
##
## Kept out of `tool_panels.gd`, which is at its line limit, and kept out on a
## real seam rather than for room: every panel in there is offered to every
## project, and these two are offered to one kind.

## The move tool, and the way out of it.
##
## Lives here rather than in `tool_panels.gd`, which is at its line limit —
## the same seam the comic panels were kept out on.
static func mover(on_done: Callable,
		on_revert: Callable) -> PanelContainer:
	var shell: PanelContainer = ToolPanels._shell(300.0)
	var v: VBoxContainer = ToolPanels._column(shell)
	ToolPanels._title(v, "Move and resize", "التحريك وتغيير الحجم")
	ToolPanels._note_line(v, UiKit.label_for(
		"The drawing on this layer is in a box. Drag inside it to move it, drag a corner to make it larger or smaller. Nothing has to be selected first.",
		"رسم هذه الطبقة داخل صندوق. اسحب من داخله لتحريكه، واسحب زاويةً لتكبيره أو تصغيره. ولا شيء يحتاج تحديداً مسبقاً."))
	var done: Button = UiKit.make_text_button(
		UiKit.label_for("Done", "تمكين"), true)
	done.pressed.connect(on_done)
	v.add_child(done)
	var back: Button = UiKit.make_text_button(
		UiKit.label_for("Put it back", "أعِده كما كان"), true)
	back.pressed.connect(on_revert)
	v.add_child(back)
	ToolPanels._note_line(v, UiKit.label_for(
		"Resizing is always worked out from the drawing as it was when you picked it up, never from the last size you tried — so you can hunt for the right size for a minute and lose nothing. Only the size you settle on is ever written down.",
		"تغيير الحجم يُحسب دائماً من الرسم كما كان حين أمسكتَه، لا من المقاس الأخير الذي جرّبته — فلك أن تبحث عن المقاس الصحيح دقيقةً كاملة ولا تخسر شيئاً. ولا يُكتب إلّا المقاس الذي تستقرّ عليه."))
	ToolPanels._note_line(v, UiKit.label_for(
		"Choosing any other tool writes it down too — what you can see is never thrown away.",
		"واختيار أيّ أداةٍ أخرى يكتبه أيضاً — فما تراه لا يُرمى أبداً."))
	return shell

# ------------------------------------------------------------- the frames
#
# ## What this panel is for
#
# Two questions and nothing else: **what shape does a cut make**, and **which
# frame is the next stroke going into**. Everything else on it — the gutter,
# the two confinement buttons, the reset — is there because it changes the
# answer to one of those two.

## Supported cut shapes. Free cut is intentionally excluded: every exposed mode is deterministic.
const SHAPES: Array = [
	[ComicPage.Cut.LINE, "Line", "خط"],
	[ComicPage.Cut.RECT, "Rectangle", "مستطيل"],
	[ComicPage.Cut.SQUARE, "Square", "مربّع"],
	[ComicPage.Cut.CIRCLE, "Circle", "دائرة"],
]

static func panels(host: Node, view: CanvasView) -> PanelContainer:
	var shell: PanelContainer = ToolPanels._shell(340.0)
	var v: VBoxContainer = ToolPanels._column(shell)
	ToolPanels._title(v, "Frames", "التقسيم")

	var sheet: ComicPage = ComicBoard.layout(view)
	if sheet == null:
		ToolPanels._note_line(v, UiKit.label_for(
			"Frames belong to a comic page.",
			"التقسيم لصفحات القصص المصوّرة."))
		return shell

	# --- cut, or choose ---
	#
	# One control rather than two modes hidden behind gestures. A finger on a
	# page can mean "cut here" or "I am drawing in this one", and no gesture
	# distinguishes those — they are both a finger on a frame. So it is said
	# rather than guessed, which is the same conclusion the comic board's
	# pins arrived at for the same reason.
	ToolPanels._choice(v, [
		[ComicBoard.Mode.CUT, "Cut", "قصّ"],
		[ComicBoard.Mode.PICK, "Choose a frame", "اختر إطاراً"],
	], ComicBoard.mode, 2, false, func(value: int) -> void:
		ComicBoard.mode = value
		host.call("_refresh_panels"))

	if ComicBoard.mode == ComicBoard.Mode.CUT:
		ToolPanels._title(v, "Cut with", "اقطع بـ")
		var rows: Array = []
		for one in SHAPES:
			rows.append([one[0], one[1], one[2]])
		ToolPanels._choice(v, rows, ComicBoard.shape, 3, false,
			func(value: int) -> void:
				ComicBoard.shape = value
				host.call("_refresh_panels"))
		ToolPanels._note_line(v, UiKit.label_for(
			"A line is the one that does the work — a page is divided, and a division is a line. Drag across a frame and it splits along that line. You need not cross the whole page: a drag that stops inside a frame has said which frame it meant, and every other frame is left exactly as it was.",
			"الخطّ هو الذي يؤدّي العمل — فالصفحة تُقسَم، والقسمة خطّ. اسحب عبر إطارٍ فينشقّ على ذلك الخطّ. ولا يلزمك عبور الصفحة كلّها: السحبة التي تقف داخل إطارٍ قد قالت أيّ إطارٍ تعني، وكلّ إطارٍ سواه يبقى كما كان تماماً."))
		ToolPanels._note_line(v, UiKit.label_for(
			"The other four take a bite out of a frame and become a frame themselves. A shape landing in the middle of a frame leaves the rest as two or three frames rather than one ring — a ring has a hole in it, and a frame with a hole is not something you can draw in.",
			"والأربعة الأخرى تقتطع من الإطار وتصير إطاراً بنفسها. والشكل الذي يقع في وسط إطارٍ يترك الباقي إطارين أو ثلاثة لا حلقةً واحدة — فالحلقة فيها ثقب، وإطارٌ فيه ثقب ليس شيئاً تستطيع الرسم فيه."))
	else:
		ToolPanels._note_line(v, UiKit.label_for(
			"Press a frame to draw in it. Press it again to let it go. While a frame is held, nothing you draw leaves it — not the brush, not the shapes, and not the eraser.",
			"اضغط إطاراً لترسم فيه. واضغطه ثانيةً لتتركه. وما دام الإطار ممسوكاً فلا شيء ترسمه يخرج منه — لا الفرشاة ولا الأشكال ولا الممحاة."))

	v.add_child(HSeparator.new())

	# --- the channel ---
	UiKit.slider_row(v, UiKit.label_for("Gutter", "الفراغ بين الإطارات"),
		0.0, 60.0, sheet.gutter, 2.0, "",
		func(x: float) -> void: sheet.gutter = x)
	ToolPanels._note_line(v, UiKit.label_for(
		"The white channel a cut leaves. It is centred on the cut, so both frames give up the same amount — putting it all on one side would make the page visibly drift as it was subdivided. Set it to nothing for frames that touch.",
		"القناة البيضاء التي يتركها القصّ. وهي مركزّة على القصّ فيتنازل الإطاران بالقدر نفسه — ووضعها كلّها في جهةٍ يجعل الصفحة تنزاح انزياحاً مرئيّاً كلّما قُسّمت. اجعلها صفراً لإطاراتٍ متلاصقة."))

	v.add_child(HSeparator.new())

	# --- drawing over the border ---
	#
	# ## Why both buttons exist rather than one that toggles
	#
	# Because this is the setting somebody reaches for in the middle of
	# something, usually because a stroke has just been cut off at a border
	# they did not want. At that moment they do not want to work out which
	# state a toggle is in — they want the one that lets them draw. So the two
	# states are two buttons, the one in force is marked, and pressing it
	# again does nothing rather than undoing the thing they just asked for.
	ToolPanels._title(v, "Over the border", "الكتابة فوق الحدود")
	ToolPanels._choice(v, [
		[0, "Kept inside", "محبوس داخل الإطار"],
		[1, "Draw over", "الكتابة فوق"],
	], 0 if sheet.confine else 1, 2, false, func(value: int) -> void:
		sheet.confine = value == 0
		if view.overlay != null:
			view.overlay.queue_redraw()
		host.call("_refresh_panels"))
	ToolPanels._note_line(v, UiKit.label_for(
		"Kept inside is the ordinary way and it is firm: every dab is checked, so a stroke that starts in a frame and is dragged out of it stops at the border rather than escaping halfway. Draw over lifts that entirely — for a figure that breaks out of its frame, which is half of what makes a comic page a comic page.",
		"«محبوس داخل الإطار» هو الوضع العاديّ وهو حازم: كلّ لمسةٍ تُفحَص، فالخطّ الذي يبدأ داخل إطارٍ ويُسحَب خارجه يقف عند الحدّ ولا يفلت في منتصفه. و«الكتابة فوق» ترفع ذلك تماماً — لشخصيّةٍ تخرج من إطارها، وهذا نصف ما يجعل صفحة القصص المصوّرة كذلك."))
	ToolPanels._note_line(v, UiKit.label_for(
		"Turning it off and on again changes nothing that is already drawn. The border decides where new paint may go, not where old paint is — so a figure drawn over its frame stays over it when the border is put back.",
		"إطفاؤه وإشعاله لا يغيّر شيئاً ممّا رُسم. فالحدّ يقرّر أين يذهب الطلاء الجديد لا أين الطلاء القديم — فالشخصيّة المرسومة فوق إطارها تبقى فوقه حين يُعاد الحدّ."))

	v.add_child(HSeparator.new())
	var count: int = sheet.panels.size()
	ToolPanels._note_line(v, UiKit.label_for(
		"This page has %d frame(s)." % count,
		"في هذه الصفحة %d إطاراً." % count))

	var start_over: Button = UiKit.make_text_button(
		UiKit.label_for("One frame again", "أعِدها إطاراً واحداً"))
	start_over.pressed.connect(func() -> void:
		var page: ProjectManager.Page = ComicBoard.page_of(view)
		if page == null or page.frames == null:
			return
		# On the undo stack like any other cut, because undoing a page you
		# flattened by mistake is exactly when an undo stack earns its keep.
		var before: Dictionary = page.frames.to_dict()
		if page.history != null:
			page.history.push(
				UiKit.label_for("One frame again", "إعادة إطار واحد"),
				[{"t": "frames", "owner": page, "state": before}])
		page.frames.reset(view.projects.active.page)
		if view.overlay != null:
			view.overlay.queue_redraw()
		if view.projects != null:
			view.projects.mark_dirty(view.projects.active)
		host.call("_refresh_panels"))
	v.add_child(start_over)
	ToolPanels._note_line(v, UiKit.label_for(
		"The border box goes back to one frame, a little inside the edge of the page. Nothing drawn is touched — the frames are a boundary, not a layer.",
		"يعود مربّع الحدود إطاراً واحداً، داخل حافّة الصفحة بقليل. ولا يُمسّ شيءٌ ممّا رُسم — فالإطارات حدٌّ لا طبقة."))
	return shell
