class_name SettingsPanels
extends RefCounted
## Everything behind the gear: new projects, language, export, sharing, and
## the options a single project carries.

const ICON: String = "res://assets/icons/%s.png"

## Capped against the screen so a panel can never be wider than the device
## it is on, and never so narrow that its right-hand column is cut away.
static func _shell(width: float = 330.0) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.panel_style())
	var room: float = 640.0
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		room = tree.root.get_visible_rect().size.x * 0.94
	p.set_meta("desired_width", minf(UiKit.s(maxf(width, 410.0)), room))
	p.custom_minimum_size = Vector2(0.0, 0.0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p

## Every settings page is built inside a scroller, so a page longer than the
## screen can be reached rather than losing its last button off the bottom.
static func _column(parent: PanelContainer, max_height: float = 470.0) -> VBoxContainer:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", int(UiKit.s(9.0)))
	# Never taller than the screen it has to stand on.
	#
	# The cap was a flat number, so on the opening screen — where the menu is
	# at its longest — the panel grew past the bottom of the display and its
	# last rows could not be reached at all. It looked like a panel too tall
	# for its own button because that is exactly what it was. The tool panels
	# were given this same ceiling; the settings pages had been left behind.
	var room: float = UiKit.s(max_height)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		room = minf(room, tree.root.get_visible_rect().size.y * 0.84)
	parent.add_child(UiKit.scroller(v, room))
	return v

static func _title(v: VBoxContainer, text: String) -> void:
	v.add_child(UiKit.make_label(text, 15.0, UiKit.TEXT))

## Every page below the menu carries the same way home, in the same place.
## Back, to wherever you actually came from.
##
## `to` used to be assumed: every page returned to the gear's menu, because
## for a long time there was only one menu to return to. Now that making a
## project has its own, a page reached from the plus and returning to the gear
## would leave you in a list you never opened, looking for a way back to one
## you did — which is worse than no Back at all.
static func _back(v: VBoxContainer, host: Node, to: String = "menu") -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiKit.s(6.0)))
	var b: Button = UiKit.make_text_button(UiKit.label_for("Back", "رجوع"))
	b.pressed.connect(func() -> void: host.open_settings_page(to))
	row.add_child(b)
	v.add_child(row)
	v.add_child(HSeparator.new())

static func _note(v: VBoxContainer, text: String) -> void:
	var l: Label = UiKit.make_label(text, 11.0, UiKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)

static func _row_button(icon_name: String, text: String, action: Callable) -> Button:
	var b: Button = UiKit.make_text_button(text, true)
	b.custom_minimum_size = Vector2(UiKit.s(240.0), UiKit.s(48.0))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var path: String = ICON % icon_name
	if ResourceLoader.exists(path):
		b.icon = load(path)
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", int(UiKit.s(22.0)))
	b.add_theme_constant_override("h_separation", int(UiKit.s(10.0)))
	b.add_theme_color_override("icon_normal_color", UiKit.TEXT)
	b.add_theme_color_override("icon_pressed_color", Color("#1b1c22"))
	b.pressed.connect(action)
	return b

# ------------------------------------------------------------------- menu

## The settings button shows one of two things, never both.
##
## Outside a project it is the workspace: make something, choose a language,
## look at what is on disk. Inside one it is that project: export it, save
## it, mark it, close it. Mixing the two meant every screen carried a dozen
## rows that did not apply, and the one that did was somewhere among them.
static func menu(host: Node) -> PanelContainer:
	if host.current_project() != null:
		return project_menu(host)
	# Outside a project there is one panel, not two. Every workspace settings
	# page has a Back control that opens page "menu", and this is where that
	# lands — so it must be the same list the user came from, which is why
	# the old separate workspace menu is gone rather than merely unused.
	return make_menu(host)

## Making something new, and nothing else.
##
## Its own button and its own panel, because it is its own kind of act.
## Everything a settings menu holds is about a thing that already exists —
## its language, its storage, its export, its name. Making a project is the
## one act that has no subject yet, and it was sitting in the same list as
## *Storage* and *App information*, which is why it needed a paragraph of
## explanation and a separator to be found at all.
##
## Split out, neither list needs explaining. This one is three lines long and
## every line makes a project. The gear is settings, all the way down.
##
## Deliberately short and deliberately narrow — a panel with three choices
## should not be the size of a panel with twelve. The width is set here rather
## than left to the default for exactly that reason.
##
## The workspace's own settings live at the bottom of it now. Splitting them
## into a second button made sense as an argument and not on a screen: the
## workspace had a bar with two marks on it, and the only way to know which
## held *Language* was to have opened both. One button, one panel, and the
## three things that make something are still first — because that is what an
## empty workspace is for.
static func make_menu(host: Node) -> PanelContainer:
	var shell: PanelContainer = _shell(268.0)
	var v: VBoxContainer = _column(shell, 250.0)
	_title(v, UiKit.label_for("New project", "مشروع جديد"))

	v.add_child(_row_button("new_project", UiKit.label_for("Drawing", "رسم"),
		func() -> void: host.open_settings_page("new")))
	v.add_child(_row_button("anim_play",
		UiKit.label_for("Animation", "رسوم متحركة"),
		func() -> void: host.open_settings_page("animation_new")))
	v.add_child(_row_button("comics", UiKit.label_for("Comic", "قصة مصورة"),
		func() -> void: host.open_settings_page("comic")))

	# Below the line, because they are a different kind of thing and should
	# still read as one. Making a project acts on nothing yet; these three act
	# on the app itself.
	v.add_child(HSeparator.new())
	_note(v, UiKit.label_for("Settings", "الإعدادات"))
	v.add_child(_row_button("language", UiKit.label_for("Language", "اللغة"),
		func() -> void: host.open_settings_page("language")))
	v.add_child(_row_button("settings_gear",
		UiKit.label_for("Storage", "التخزين"),
		func() -> void: host.open_settings_page("storage")))
	v.add_child(_row_button("information",
		UiKit.label_for("App information", "معلومات التطبيق"),
		func() -> void: host.open_settings_page("information")))
	return shell

## The open project's own settings, in the same place the workspace ones
## were — so the button always means "settings for what I am looking at".
static func project_menu(host: Node) -> PanelContainer:
	var p: ProjectManager.Project = host.current_project()
	var shell: PanelContainer = _shell()
	var v: VBoxContainer = _column(shell, 560.0)
	_title(v, p.title)
	_note(v, "%s  ·  %d × %d" % [_kind_word(p.kind), int(p.page.x), int(p.page.y)])

	v.add_child(_row_button("save_close", UiKit.label_for("Save project", "احفظ المشروع"),
		func() -> void: host.save_project()))
	v.add_child(_row_button("export", UiKit.label_for("Export", "تصدير"),
		func() -> void: host.open_settings_page("export")))
	v.add_child(_row_button("share", UiKit.label_for("Share", "مشاركة"),
		func() -> void: host.open_settings_page("share")))
	v.add_child(HSeparator.new())

	if p.kind == ProjectManager.Kind.ANIMATION:
		v.add_child(_row_button("anim_play", UiKit.label_for("Animation", "رسوم متحركة"),
			func() -> void: host.open_settings_page("animation")))
	if p.kind == ProjectManager.Kind.COMIC:
		v.add_child(_row_button("comics", UiKit.label_for("Add page", "أضف صفحة"),
			func() -> void: host.add_page(p)))

	# The one door between two projects, and it is only ever on this side of
	# it. An animation is a scene and a comic is a book — neither is a thing
	# you reach into for a picture. A drawing is, which is why the row exists
	# here and is absent from the other two menus rather than greyed out in
	# them: a button that can never be pressed is a question the user has to
	# answer every time they read the list.
	if DrawTransfer.offered_by(p):
		v.add_child(_row_button("transfer",
			UiKit.label_for("Transfer of the decree", "نقل المرسوم"),
			func() -> void: host.begin_transfer()))

	v.add_child(_row_button("favorite", UiKit.label_for("Favourite", "مميّز"),
		func() -> void: host.toggle_favourite()))
	v.add_child(_row_button("new_project", UiKit.label_for("Duplicate", "نسخة مطابقة"),
		func() -> void: host.duplicate_project(p)))
	v.add_child(HSeparator.new())
	# The door icon belongs to leaving, and to nothing else — it is not on
	# the compass and it is not a tool. This is the one place it appears.
	v.add_child(_row_button("exit",
		UiKit.label_for("Exit project", "الخروج من المشروع"),
		func() -> void: host.close_project(p)))

	# Deleting a whole project is the one thing here with no undo, so it
	# asks once rather than acting on the first tap.
	var armed: Array = [false]
	var kill: Button = UiKit.make_text_button(UiKit.label_for("Delete", "حذف"), true)
	kill.custom_minimum_size = Vector2(0.0, UiKit.s(46.0))
	kill.pressed.connect(func() -> void:
		if not armed[0]:
			armed[0] = true
			kill.text = UiKit.label_for("Tap again to delete", "اضغط ثانية للحذف")
			return
		host.delete_project(p))
	v.add_child(kill)
	return shell

# -------------------------------------------------------------- information

## The app's own network assistant, if this build has one.
##
## Asked for by name rather than by type so this page does not have to know
## how `main.gd` is put together — and answered honestly with null when there
## is nothing there, so the button says so instead of doing nothing.
static func _assistant_of(host: Node) -> AIAssistant:
	if host == null or not is_instance_valid(host):
		return null
	if not (host.get("ai") is AIAssistant):
		return null
	return host.get("ai") as AIAssistant

static func information(host: Node) -> PanelContainer:
	var shell: PanelContainer = _shell(520.0)
	var v: VBoxContainer = _column(shell, 620.0)
	_back(v, host)
	_title(v, UiKit.label_for("IVORY information", "معلومات IVORY"))
	_note(v, UiKit.label_for(
		"IVORY is a touch-first creative workspace for illustration, frame-by-frame animation and multi-page comics. Each project owns its layers, history, timeline and camera data, while the drawing canvas stays flat and predictable when you are editing.",
		"IVORY مساحة إبداعية مصممة للمس للرسم والتحريك إطاراً بإطار والقصص المصورة متعددة الصفحات. كل مشروع يملك طبقاته وسجل التراجع والتايملاين وبيانات الكاميرا الخاصة به، بينما تبقى لوحة الرسم مسطحة وواضحة أثناء العمل."))
	v.add_child(HSeparator.new())
	_title(v, UiKit.label_for("Core workflow", "طريقة العمل الأساسية"))
	_note(v, UiKit.label_for(
		"Create a project, draw on layers, animate on the timeline, use Onion Skin to compare nearby poses, and key the camera when a shot needs movement. Project-browser effects never alter the artwork inside an opened project.",
		"أنشئ مشروعاً، ارسم على الطبقات، حرّك على التايملاين، استخدم Onion Skin لمقارنة الوضعيات القريبة، وثبّت الكاميرا عندما تحتاج اللقطة إلى حركة. تأثيرات متصفح المشاريع لا تغيّر العمل الفني داخل المشروع المفتوح."))
	_title(v, UiKit.label_for("Input tools", "أدوات الإدخال"))
	_note(v, UiKit.label_for(
		"Input Event is the home for Selection Tools and Lateral Symmetry. Selection keeps the original selection/copy workflow, while Lateral Symmetry provides a movable axis, rotation handle and repeated mathematical symmetry modes.",
		"Input Event هو مكان أدوات التحديد والتناظر الجانبي. أدوات التحديد تحافظ على نظام التحديد والنسخ الأصلي، بينما يوفر التناظر الجانبي محوراً قابلاً للتحريك ومقبض دوران وأنماط تناظر رياضية متكررة."))
	v.add_child(HSeparator.new())
	_title(v, UiKit.label_for("Timeline", "التايملاين"))
	_note(v, UiKit.label_for(
		"The timeline uses the supplied frame, camera, onion-skin, layer and navigation artwork. Play and Stop share one transport button. Frame stepping is discrete, and a new frame can start blank or duplicate the previous pose for tracing.",
		"التايملاين يستخدم أصول الفريم والكاميرا وOnion Skin والطبقة والتنقل التي زودت بها. التشغيل والإيقاف في زر واحد. الانتقال بين الفريمات متدرج بفريمات منفصلة، ويمكن إنشاء فريم فارغ أو نسخه من الوضعية السابقة للتتبع."))
	var source_button: Button = _row_button("information", UiKit.label_for("Icon & tools source", "مصدر الأيقونات والأدوات"),
		func() -> void: OS.shell_open("https://share.google/MvGCvk0HJ5SzZ6hwU"))
	v.add_child(source_button)
	var source_note: Label = UiKit.make_label("https://share.google/MvGCvk0HJ5SzZ6hwU", 10.0, UiKit.TEXT_DIM)
	source_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(source_note)
	v.add_child(HSeparator.new())
	_title(v, UiKit.label_for("The workspace", "مساحة العمل"))
	_note(v, UiKit.label_for(
		"Projects sit on the endless grid as sheets. One tap picks a sheet out, two taps open it and fill the screen with it, and a press held on a sheet picks it up so it can be dragged anywhere. Inside an open project every touch belongs to the drawing tools.",
		"تجلس المشاريع على الشبكة اللانهائية كصفحات. ضغطة واحدة تختار الصفحة، وضغطتان تفتحانها وتملآن بها الشاشة، والضغط المستمر على الصفحة يرفعها لتسحبها إلى أي مكان. وداخل المشروع المفتوح تعود كل لمسة لأدوات الرسم."))
	_title(v, UiKit.label_for("Performance", "الأداء"))
	_note(v, UiKit.label_for(
		"IVORY keeps the active project live and compresses inactive project pixels. The project browser is viewport-culled, so a workspace holding many sheets only ever draws the ones you can see.",
		"يحافظ IVORY على المشروع النشط بحالة حيّة ويضغط بكسلات المشاريع غير النشطة. ومتصفح المشاريع يستخدم إخفاءً حسب إطار العرض، فمساحة العمل التي تحمل صفحات كثيرة لا ترسم إلا ما تراه."))

	v.add_child(HSeparator.new())
	_title(v, UiKit.label_for("What this device measured",
		"ما قِيس على هذا الجهاز"))
	_note(v, UiKit.label_for(
		"Every performance budget in IVORY is now arithmetic on numbers timed on this device rather than numbers chosen in advance. What follows is all of them, with how many samples each is built on. If something is slow, a photograph of this page says more than any description of it can.",
		"كل ميزانيات الأداء في IVORY صارت حسابًا على أرقام قيست على هذا الجهاز، لا أرقامًا اختيرت مسبقًا. وما يلي هو كلها، ومعها عدد العينات التي بُني عليها كل رقم. فإن كان شيء بطيئًا، فصورة لهذه الصفحة تقول أكثر من أي وصف."))
	var readout: Label = UiKit.make_label(Perf.report(), 10.0, UiKit.TEXT_DIM)
	readout.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.add_child(readout)
	var fill_note: Label = UiKit.make_label(FloodFill.describe_last(), 10.0,
		UiKit.TEXT_DIM)
	fill_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(fill_note)

	var again: Button = _row_button("information", UiKit.label_for(
		"Measure this device again", "أعد قياس هذا الجهاز"),
		func() -> void:
			# A device that was hot and throttling when it was first measured
			# deserves a second opinion, and so does one that has just had
			# every other application closed.
			Perf.calibrate(true)
			readout.text = Perf.report())
	v.add_child(again)

	v.add_child(HSeparator.new())
	_title(v, UiKit.label_for("The AI connection", "اتصال الذكاء الاصطناعي"))
	_note(v, UiKit.label_for(
		"The app was reaching the service and being turned away: the address it was built with was retired, and every refusal was reported as the model being busy. From outside, an app being refused and an app never calling look identical — so here is the difference, in numbers. Press below and the app makes one real request over the real network with the real key, then prints the address it used, what the server answered and how long it took.",
		"كان التطبيق يصل إلى الخدمة فيُردّ: العنوان الذي بُني به قد أُلغي، وكان كل ردّ رفض يُبلَّغ عنه كأنّ النموذج مشغول. ومن الخارج لا فرق بين تطبيقٍ يُرَدّ وتطبيقٍ لا يتصل أصلاً — فهذا هو الفرق، بالأرقام. اضغط أدناه فيُرسل التطبيق طلباً حقيقياً عبر الشبكة الحقيقية بالمفتاح الحقيقي، ثم يطبع العنوان الذي استُعمل وما أجاب به الخادم وكم استغرق."))
	var doors: Label = UiKit.make_label(AIAssistant.describe_doors(), 10.0,
		UiKit.TEXT_DIM)
	doors.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(doors)
	var knock: Button = _row_button("information", UiKit.label_for(
		"Test the connection now", "اختبر الاتصال الآن"),
		func() -> void:
			var who: AIAssistant = _assistant_of(host)
			if who == null:
				doors.text = "no assistant in this build"
				return
			doors.text = UiKit.label_for("knocking…", "يطرق…")
			# Refreshed when the exchange ends, whichever way it ends. A
			# report that only appeared on success would vanish at exactly
			# the moment it is wanted.
			var restate: Callable = func(_a: Variant = null,
					_b: Variant = null, _c: Variant = null,
					_d: Variant = null) -> void:
				if is_instance_valid(doors):
					doors.text = AIAssistant.describe_doors()
			who.finished.connect(restate, Object.CONNECT_ONE_SHOT)
			who.failed.connect(restate, Object.CONNECT_ONE_SHOT)
			who.test_connection())
	v.add_child(knock)

	v.add_child(HSeparator.new())
	_title(v, UiKit.label_for("Rights", "الحقوق"))
	_note(v, UiKit.label_for(
		"All rights reserved to AAJE.",
		"جميع الحقوق محفوظة لدى AAJE."))

	_title(v, UiKit.label_for("Icons", "الأيقونات"))
	_note(v, UiKit.label_for(
		"All icons used in this app were taken from Icons8.",
		"جميع الأيقونات المستخدمة في هذا التطبيق تم أخذها من موقع Icons8."))
	var link: Button = UiKit.make_text_button("https://icons8.com", true)
	link.pressed.connect(func() -> void: OS.shell_open("https://icons8.com"))
	v.add_child(link)
	return shell


# ---------------------------------------------------------------- storage

## What is actually on the disk, and a way to be rid of it. Every other
## screen shows the workspace; this one shows the truth underneath it.
static func storage_page(host: Node) -> PanelContainer:
	var shell: PanelContainer = _shell(310.0)
	var v: VBoxContainer = _column(shell)
	_back(v, host)
	_title(v, UiKit.label_for("Storage", "التخزين"))

	var manager: ProjectManager = host.view.projects
	_note(v, "%s: %d" % [UiKit.label_for("Projects", "المشاريع"),
		manager.projects.size()])
	var strays: int = Vault.orphan_count(manager)
	if strays > 0:
		_note(v, "%s: %d" % [UiKit.label_for("Saved but not open", "محفوظ وغير مفتوح"),
			strays])

	for p in manager.projects:
		var row: Button = UiKit.make_text_button("%s  ·  %s" % [p.title, p.created], true)
		row.custom_minimum_size = Vector2(0.0, UiKit.s(44.0))
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var target: ProjectManager.Project = p
		row.pressed.connect(func() -> void: host.show_project_menu(target))
		v.add_child(row)

	v.add_child(HSeparator.new())
	_note(v, UiKit.label_for(
		"Removes every saved project from this device. Nothing else is touched.",
		"يحذف كل مشروع محفوظ من هذا الجهاز. لا يمسّ شيئاً آخر."))
	var free: Button = UiKit.make_text_button(
		UiKit.label_for("Free memory now", "حرّر الذاكرة الآن"), true)
	free.custom_minimum_size = Vector2(0.0, UiKit.s(46.0))
	free.pressed.connect(func() -> void: host.free_memory())
	v.add_child(free)
	_note(v, UiKit.label_for(
		"Empties the undo history and hands every sleeping tile back. The drawing itself is untouched.",
		"يفرغ سجلّ التراجع ويعيد كل بلاطة نائمة. والرسم نفسه لا يُمسّ."))
	v.add_child(HSeparator.new())

	var armed: Array = [false]
	var wipe: Button = UiKit.make_text_button(
		UiKit.label_for("Forget everything saved", "انسَ كل ما هو محفوظ"), true)
	wipe.custom_minimum_size = Vector2(0.0, UiKit.s(46.0))
	wipe.pressed.connect(func() -> void:
		if not armed[0]:
			armed[0] = true
			wipe.text = UiKit.label_for("Tap again to delete", "اضغط ثانية للحذف")
			return
		host.forget_everything())
	v.add_child(wipe)
	return shell

# ------------------------------------------------------------ new project

## `mode` is "drawing", "comic" or "animation". They are separate dialogs
## because they ask genuinely different questions: a comic wants pages, an
## animation wants a frame rate and a length, and a drawing wants neither.
## Bundling them behind one form makes every user read past two thirds of it.
# -------------------------------------------------------- animation launcher

## First screen shown when the user asks for a new Animation project.
##
## The decision is made before any project settings are shown. Stretchy is a
## separate authoring surface, so its creation path intentionally does not
## expose Ivory's FPS/colour/pages controls. The native C++ launcher is the
## source of truth for the two workspaces and the small set of starting canvas
## presets; GDScript only renders the touch UI and forwards the selected choice.
static func animation_project_start(host: Node) -> PanelContainer:
	# The workspace chooser is a real native C++ PanelContainer. It owns the
	# two actual Button nodes and emits workspace_selected. There is deliberately
	# no GDScript list, no ScrollContainer, and no fallback panel that can hide
	# the choices when the native module is missing.
	var picker_obj: Object = Native.animation_workspace_picker()
	if picker_obj == null:
		# A native-only chooser is required for this build. Keep the failure small
		# and explicit instead of rendering a misleading empty animation panel.
		var failed: PanelContainer = _shell(360.0)
		var fv: VBoxContainer = _column(failed)
		_title(fv, UiKit.label_for("Animation Project", "مشروع رسوم متحركة"))
		_note(fv, UiKit.label_for(
			"Native C++ workspace UI is not available in this build.",
			"واجهة اختيار المشاريع الأصلية C++ غير متاحة في هذا الإصدار."))
		return failed

	var picker: PanelContainer = picker_obj as PanelContainer
	if picker == null:
		return null
	picker.workspace_selected.connect(func(workspace: String) -> void:
		if workspace == "ivory":
			host.open_settings_page("new_animation_ivory")
		elif workspace == "stretchy":
			host.open_stretchy_project_canvas_choice()
	)
	return picker

## Ivory's old animation form remains intact, but it is reached only after
## explicitly choosing Ivory on the first screen.
static func new_animation_ivory_project(host: Node) -> PanelContainer:
	return new_project(host, "animation")

## Stretchy starts with canvas selection only. Selecting a preset creates the
## animation project immediately and opens the dedicated Stretchy room; the
## rest of the project settings belong to Stretchy itself.
static func stretchy_canvas_choice(host: Node) -> PanelContainer:
	var picker_obj: Object = Native.stretchy_canvas_picker()
	if picker_obj == null:
		var failed: PanelContainer = _shell(360.0)
		var fv: VBoxContainer = _column(failed)
		_title(fv, UiKit.label_for("Stretchy Studio", "Stretchy Studio"))
		_note(fv, UiKit.label_for(
			"Native C++ canvas picker is not available in this build.",
			"واجهة اختيار الكانفاس الأصلية C++ غير متاحة في هذا الإصدار."))
		return failed

	var picker: PanelContainer = picker_obj as PanelContainer
	if picker == null:
		return null
	picker.canvas_selected.connect(func(width: int, height: int, _key: String) -> void:
		host.spawn_stretchy_project(Vector2(float(width), float(height))))
	picker.back_requested.connect(func() -> void:
		host.open_settings_page("animation_new"))
	return picker

static func new_project(host: Node, mode: String) -> PanelContainer:
	var comic: bool = mode == "comic"
	var animation: bool = mode == "animation"
	var shell: PanelContainer = _shell(320.0)
	var v: VBoxContainer = _column(shell)
	_back(v, host, "make")
	if comic:
		_title(v, UiKit.label_for("Comic", "قصة مصورة"))
	elif animation:
		_title(v, UiKit.label_for("Animation", "رسوم متحركة"))
	else:
		_title(v, UiKit.label_for("Drawing", "رسم"))
	_note(v, UiKit.label_for(
		"Every project starts empty — its own layers, its own history",
		"كل مشروع يبدأ من الصفر — طبقاته وسجلّه خاصان به"))

	var name_field: LineEdit = LineEdit.new()
	name_field.placeholder_text = UiKit.label_for("Name", "الاسم")
	# A field is tapped to put a caret in it, so it is a touch target like
	# any other and takes the same floor.
	name_field.custom_minimum_size = Vector2(0.0, UiKit.s(UiKit.TOUCH_FLOOR))
	name_field.add_theme_font_size_override("font_size", int(UiKit.s(14.0)))
	v.add_child(name_field)

	var kind: Array = [ProjectManager.Kind.DRAWING]
	if comic:
		kind[0] = ProjectManager.Kind.COMIC
	elif animation:
		kind[0] = ProjectManager.Kind.ANIMATION

	# --- how big the canvas is ---
	#
	# It used to be fixed at 1600 by 1200 for every project of every kind,
	# with a comment here saying that was on purpose. It was not defensible:
	# an app that makes animation and comic pages could not make a Full HD
	# frame or an A4 page, so everything it produced had to be resampled by
	# something else before it could be used.
	#
	# One row, opening a panel with the presets, a preview and two fields for
	# anything the presets do not cover. See `canvas_size.gd`, which explains
	# why it is a panel rather than twenty-six buttons on this sheet.
	#
	# The default differs by kind, because the right first guess differs:
	# animation wants a video frame, everything else wants a page.
	var kind_word: String = "animation" if animation else (
		"comic" if comic else "drawing")
	var page: Array = [Vector2(1920.0, 1080.0) if animation
		else Vector2(1600.0, 1200.0)]
	CanvasSize.row(v, host, kind_word, page)

	# --- what only this kind of project needs ---
	var pages: Array = [1]
	var fps: Array = [24]

	if comic:
		var page_row: HBoxContainer = HBoxContainer.new()
		page_row.add_theme_constant_override("separation", int(UiKit.s(6.0)))
		v.add_child(page_row)
		page_row.add_child(UiKit.make_label(
			UiKit.label_for("Pages", "الصفحات"), 12.0, UiKit.TEXT_DIM))
		var page_field: LineEdit = _number_field("2")
		pages[0] = 2
		page_field.text_changed.connect(func(txt: String) -> void:
			pages[0] = clampi(int(txt), 1, ProjectManager.MAX_PAGES))
		page_row.add_child(page_field)
		_note(v, UiKit.label_for("Pages sit side by side, so a drawing can cross them.",
			"الصفحات متجاورة، فيمكن للرسم أن يعبر بينها."))

	if animation:
		v.add_child(UiKit.make_label(UiKit.label_for("Frames per second", "إطارات في الثانية"),
			12.0, UiKit.TEXT_DIM))
		var rate_row: HBoxContainer = HBoxContainer.new()
		rate_row.add_theme_constant_override("separation", int(UiKit.s(5.0)))
		v.add_child(rate_row)
		var rates: Array = [12, 24, 25, 30, 60]
		var rbtns: Array[Button] = []
		for r in rates:
			var b: Button = UiKit.make_text_button(str(int(r)))
			b.toggle_mode = true
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.set_pressed_no_signal(int(r) == 24)
			rbtns.append(b)
			rate_row.add_child(b)

		for i in rbtns.size():
			var idx: int = i
			var value: int = int(rates[i])
			rbtns[i].pressed.connect(func() -> void:
				fps[0] = value
				for k in rbtns.size():
					rbtns[k].set_pressed_no_signal(k == idx))

		# A length is not asked for any more.
		#
		# A scene ends where the drawing ends, and nobody knows that when the
		# project is being named. Choosing a number here only ever produced
		# one of two wrong answers: a wall to hit at four seconds, or a field
		# of empty frames stretching past everything that was drawn. The
		# timeline is open-ended now and grows as the work does, so this
		# question has no reason to exist.
		_note(v, UiKit.label_for(
			"The scene has no set length. It grows as you draw, and the frame rate can change later from the timeline.",
			"لا طول محدَّد للمشهد. ينمو كلما رسمت، ومعدّل الإطارات قابل للتغيير لاحقاً من التايم لاين."))

	# --- paper colour ---
	# The presets remain for one-tap choices, but the project can now use the
	# same precise square/ring picker used by the drawing tools. The picker is
	# deliberately part of project creation: the paper colour is a property of
	# this project, not an application-wide preference.
	v.add_child(UiKit.make_label(
		UiKit.label_for("Canvas colour", "لون الكانفاس"), 12.0, UiKit.TEXT_DIM))
	var paper: Array = [Color("#ffffff")]
	var picker: ColorWheelControl = ColorWheelControl.new()
	picker.custom_minimum_size = Vector2(UiKit.s(250.0), UiKit.s(250.0))
	v.add_child(picker)

	var colour_readout: Label = UiKit.make_label("", 11.0, UiKit.TEXT_DIM)
	colour_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(colour_readout)

	var hex_row: HBoxContainer = HBoxContainer.new()
	hex_row.add_theme_constant_override("separation", int(UiKit.s(6.0)))
	v.add_child(hex_row)
	hex_row.add_child(UiKit.make_label("HEX", 12.0, UiKit.TEXT_DIM))
	var hex_field: LineEdit = LineEdit.new()
	hex_field.placeholder_text = "#RRGGBB"
	hex_field.text = "#FFFFFF"
	hex_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hex_field.custom_minimum_size = Vector2(0.0, UiKit.s(40.0))
	hex_field.add_theme_font_size_override("font_size", int(UiKit.s(13.0)))
	hex_row.add_child(hex_field)

	var apply_colour: Callable = func(c: Color) -> void:
		paper[0] = c
		picker.set_color(c)
		hex_field.text = c.to_html(false).to_upper()
		colour_readout.text = "HSV  %d°   %d%%   %d%%" % [
			int(round(c.h * 360.0)), int(round(c.s * 100.0)),
			int(round(c.v * 100.0))]
	picker.picked.connect(apply_colour)
	picker.released.connect(apply_colour)

	hex_field.text_submitted.connect(func(value: String) -> void:
		var raw: String = value.strip_edges()
		if not raw.begins_with("#"):
			raw = "#" + raw
		if raw.length() == 7:
			var chosen: Color = Color(raw)
			apply_colour.call(chosen))

	apply_colour.call(paper[0])

	v.add_child(UiKit.make_label(
		UiKit.label_for("Quick colours", "ألوان سريعة"), 11.0, UiKit.TEXT_DIM))
	v.add_child(_swatch_row(
		["#ffffff", "#fbf6ea", "#f2efe6", "#1b1c22", "#2b3a4a"],
		func(c: Color) -> void: apply_colour.call(c)))

	v.add_child(HSeparator.new())
	if host.view.projects.projects.size() >= ProjectManager.MAX_PROJECTS - 4:
		_note(v, "%s %d / %d" % [UiKit.label_for("Projects", "المشاريع"),
			host.view.projects.projects.size(), ProjectManager.MAX_PROJECTS])

	var go: Button = UiKit.make_text_button(UiKit.label_for("Create", "أنشئ"), true)
	go.custom_minimum_size = Vector2(0.0, UiKit.s(46.0))
	go.pressed.connect(func() -> void:
		host.spawn_project(name_field.text, int(kind[0]), page[0] as Vector2,
			paper[0], int(pages[0]), int(fps[0]), Anim.OPENING_FRAMES))
	v.add_child(go)
	return shell

static func _number_field(value: String) -> LineEdit:
	var f: LineEdit = LineEdit.new()
	f.text = value
	f.alignment = HORIZONTAL_ALIGNMENT_CENTER
	f.custom_minimum_size = Vector2(UiKit.s(72.0), UiKit.s(40.0))
	f.add_theme_font_size_override("font_size", int(UiKit.s(14.0)))
	return f

static func _swatch_row(hexes: Array, on_pick: Callable) -> HFlowContainer:
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", int(UiKit.s(6.0)))
	row.add_theme_constant_override("v_separation", int(UiKit.s(6.0)))
	for hex in hexes:
		var c: Color = Color(String(hex))
		var b: Button = Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(UiKit.s(40.0), UiKit.s(36.0))
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = c
		sb.border_color = Color(0.0, 0.0, 0.0, 0.25)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(int(UiKit.s(8.0)))
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.pressed.connect(func() -> void: on_pick.call(c))
		row.add_child(b)
	return row

# --------------------------------------------------------------- language

static func language(host: Node) -> PanelContainer:
	var shell: PanelContainer = _shell()
	var v: VBoxContainer = _column(shell)
	_back(v, host)
	_title(v, UiKit.label_for("Language", "اللغة"))

	# Each language says how much of the app it actually covers.
	#
	# A row missing one translation is invisible from the outside — that
	# string simply comes out in English and looks like something nobody
	# wrapped. Printing the count here means a gap has to be looked at
	# instead of being quietly lived with.
	for code in Lang.NAMES.size():
		var reach: Dictionary = Lang.coverage(code)
		var share: int = int(round(float(reach["share"]) * 100.0))
		var label: String = Lang.name_of(code)
		if share < 100:
			label += "   %s%%" % Lang.number(share)
		else:
			# A row filled in with the English text is not a translation, and
			# counting it as one is how a language reads fully covered while
			# still being half in English. Those are counted separately.
			var copies: int = Lang.literal_copies(code).size()
			if copies > 0:
				label += "   %s %s" % [Lang.number(copies),
					UiKit.label_for("untranslated", "غير مترجم")]
		var b: Button = UiKit.make_text_button(label, true)
		b.custom_minimum_size = Vector2(0.0, UiKit.s(46.0))
		b.toggle_mode = true
		b.set_pressed_no_signal(code == Lang.current)
		var value: int = code
		b.pressed.connect(func() -> void: host.set_language(value))
		v.add_child(b)

	_note(v, UiKit.label_for(
		"Anything a language has not covered is shown in English rather than left blank, so no screen can come out with holes in it.",
		"ما لم تغطّه لغة يظهر بالإنجليزية بدل أن يُترك فارغاً، فلا تخرج شاشة وفيها فجوات."))

	if UiKit.missing_glyphs():
		_note(v, UiKit.label_for(
			"These scripts need a font that carries them. Put one at assets/fonts/ui.ttf.",
			"هذه الحروف تحتاج خطاً يحملها. ضع واحداً في assets/fonts/ui.ttf."))
	return shell

# ----------------------------------------------------------- frame colour

## Just the colours, for the strip above a project. No title, no back
## button, nothing else — it is answering one question.
static func frame_colour_for(host: Node, p: ProjectManager.Project) -> PanelContainer:
	var shell: PanelContainer = _shell(260.0)
	var v: VBoxContainer = _column(shell)
	_title(v, p.title)
	_note(v, UiKit.label_for("Frame colour", "لون الإطار"))
	v.add_child(_swatch_row(
		["#1b1c22", "#d8a24a", "#5f6675", "#b4573f", "#4e8f52", "#3f6fb5",
		 "#8a5fb5", "#f6f2ea"],
		func(c: Color) -> void:
			p.frame = c
			host.frame_colour_chosen()))
	return shell

static func frame_colour(host: Node) -> PanelContainer:
	var shell: PanelContainer = _shell()
	var v: VBoxContainer = _column(shell)
	_back(v, host)
	_title(v, UiKit.label_for("Frame colour", "لون الإطار"))
	_note(v, UiKit.label_for("Applies to the project you have open.",
		"يُطبَّق على المشروع المفتوح."))
	v.add_child(_swatch_row(
		["#1b1c22", "#d8a24a", "#5f6675", "#b4573f", "#4e8f52", "#3f6fb5", "#f6f2ea"],
		func(c: Color) -> void: host.set_frame_colour(c)))
	return shell

# ------------------------------------------------------------------ export

## Each kind of project gets the formats that make sense for it and none
## that do not. Offering PNG for an animation, or a sprite sheet for a
## comic, is not generosity — it is a menu the user has to filter by hand.
static func export_page(host: Node) -> PanelContainer:
	var shell: PanelContainer = _shell(310.0)
	var v: VBoxContainer = _column(shell)
	_back(v, host)
	_title(v, UiKit.label_for("Export", "تصدير"))

	var target: ProjectManager.Project = host.current_project()
	if target == null:
		_note(v, UiKit.label_for("Nothing to export yet", "لا يوجد ما يُصدَّر بعد"))
		return shell

	_note(v, "%s  ·  %s" % [_kind_word(target.kind), target.title])
	_note(v, "%s  %s" % [UiKit.label_for("Saved to", "حُفظ في"),
		Exporters.out_dir().get_file()])

	# How long the scene actually is, said before anything is chosen.
	#
	# Every moving format below writes this many frames, and how many there
	# are decides whether an export takes two seconds or two minutes. Saying
	# it here is the difference between waiting patiently and tapping again.
	var moving_frames: int = Exporters.frame_count(target)
	if moving_frames > 1:
		_note(v, Lang.fill("{0} frames  ·  {1} seconds", [moving_frames,
			float(moving_frames) / float(maxi(target.fps, 1))],
			"{0} إطاراً  ·  {1} ثانية"))

	# --- the one press ---
	#
	# Exporting while a piece is being finished is the same export, over and
	# over: fix a frame, export, look at it, fix another frame, export. Every
	# one of those used to mean opening this sheet and walking the list again
	# to press the same button. This is that button, on the outside.
	var again: Button = UiKit.make_text_button("%s  ·  %s" % [
		UiKit.label_for("Export", "تصدير"),
		_export_words(host, target)], true)
	again.custom_minimum_size = Vector2(0.0, UiKit.s(52.0))
	again.pressed.connect(func() -> void: host.export_again())
	v.add_child(again)
	_note(v, UiKit.label_for(
		"Straight to your files, the same way as last time. Choose another below to change it.",
		"مباشرةً إلى ملفاتك، بالطريقة نفسها كالمرة السابقة. اختر غيرها أدناه لتغييرها."))
	v.add_child(HSeparator.new())

	var rows: Array = []
	if target.kind == ProjectManager.Kind.COMIC:
		rows = [
			["cbz", "CBZ", UiKit.label_for("What comic readers open",
				"ما تفتحه قارئات القصص")],
			["pdf", "PDF", UiKit.label_for("Every page, anywhere",
				"كل الصفحات، في أي جهاز")],
			["pages", "PNG", UiKit.label_for("Each page separately",
				"كل صفحة على حدة")],
			["psd", "PSD", UiKit.label_for("Layers kept", "بطبقاته محفوظة")],
			["jpg", "JPEG", UiKit.label_for("Small, for sending",
				"صغير، للإرسال")],
		]
	elif target.kind == ProjectManager.Kind.ANIMATION:
		rows = [
			["mp4", "MP4", UiKit.label_for("Video export", "تصدير فيديو")],
			["mp4_small", UiKit.label_for("MP4, smaller", "MP4 مصغّر"),
				UiKit.label_for("1280 wide — lighter file", "بعرض 1280 — ملف أخف")],
			["webp_anim", UiKit.label_for("Moving WebP", "WebP متحرك"),
				UiKit.label_for("Full colour, far smaller than GIF",
					"بألوان كاملة، وأصغر من GIF بكثير")],
			["webp_anim_small", UiKit.label_for("Moving WebP, smaller",
				"WebP متحرك مصغّر"),
				UiKit.label_for("960 wide", "بعرض 960")],
			["gif", "GIF", UiKit.label_for("Plays anywhere, 256 colours",
				"يعمل في كل مكان، 256 لوناً")],
			["gif_small", UiKit.label_for("GIF, smaller", "GIF مصغّر"),
				UiKit.label_for("800 wide — far lighter", "بعرض 800 — أخف بكثير")],
			["sequence", "PNG", UiKit.label_for("What editing software expects",
				"ما تتوقّعه برامج المونتاج")],
			["sheet", UiKit.label_for("Sprite sheet", "ورقة إطارات"),
				UiKit.label_for("For games and the web", "للألعاب والويب")],
			["psd", "PSD", UiKit.label_for("Layers kept", "بطبقاته محفوظة")],
			["cbz", "CBZ", UiKit.label_for("Every frame as a comic",
				"كل إطار كصفحة قصة")],
			["pdf", "PDF", UiKit.label_for("Every frame, anywhere",
				"كل إطار، في أي جهاز")],
			["png", "PNG", UiKit.label_for("This frame only, transparent",
				"هذا الإطار فقط، بشفافية")],
		]
	else:
		rows = [
			["psd", "PSD", UiKit.label_for("Layers kept", "بطبقاته محفوظة")],
			["png", "PNG", UiKit.label_for("Lossless, transparent",
				"بلا فقد، وبشفافية")],
			["gif", "GIF", UiKit.label_for("Plays anywhere, 256 colours",
				"يعمل في كل مكان، 256 لوناً")],
			["jpg", "JPEG", UiKit.label_for("Small, for sending", "صغير، للإرسال")],
			["webp", "WebP", UiKit.label_for("Small and lossless", "صغير وبلا فقد")],
		]

	for row in rows:
		var box: VBoxContainer = VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		var b: Button = UiKit.make_text_button(String(row[1]), true)
		b.custom_minimum_size = Vector2(0.0, UiKit.s(44.0))
		var kind: String = String(row[0])
		b.pressed.connect(func() -> void: host.run_export(kind))
		box.add_child(b)
		box.add_child(UiKit.make_label(String(row[2]), 10.0, UiKit.TEXT_DIM))
		v.add_child(box)

	if target.kind == ProjectManager.Kind.ANIMATION:
		v.add_child(HSeparator.new())
		_note(v, UiKit.label_for(
			"MP4 uses H.264/AVC with optional AAC, streaming frames in a worker thread. Resolution, CRF, bitrate, profile and audio are configurable above.",
			"MP4 يستخدم H.264/AVC مع AAC اختياري، ويبث الإطارات عبر خيط عمل. يمكنك ضبط الدقة وCRF ومعدل البت والملف التعريفي والصوت أعلاه."))
		var cancel_export: Button = UiKit.make_text_button(UiKit.label_for("Cancel current export", "إلغاء التصدير الحالي"), true)
		cancel_export.pressed.connect(func() -> void: host.cancel_export())
		v.add_child(cancel_export)
	return shell

## What the one-press button will do, in words.
##
## Named rather than left as "Export again", because a button that does not
## say what it does is a button nobody presses twice.
static func _export_words(_host: Node, target: ProjectManager.Project) -> String:
	var kind: String = target.export_kind
	if kind == "":
		if target.kind == ProjectManager.Kind.ANIMATION:
			kind = "mp4"
		elif target.kind == ProjectManager.Kind.COMIC:
			kind = "cbz"
		else:
			kind = "png"
	match kind:
		"mp4", "mp4_small":
			return "MP4"
		"webp_anim", "webp_anim_small":
			return UiKit.label_for("Moving WebP", "WebP متحرك")
		"gif", "gif_small":
			return "GIF"
		"sequence":
			return UiKit.label_for("PNG frames", "إطارات PNG")
		"sheet":
			return UiKit.label_for("Sprite sheet", "ورقة إطارات")
		"cbz":
			return "CBZ"
		"pdf":
			return "PDF"
		"psd":
			return "PSD"
		"pages":
			return UiKit.label_for("Each page", "كل صفحة")
		"jpg":
			return "JPEG"
		"webp":
			return "WebP"
	return "PNG"

static func share_page(host: Node) -> PanelContainer:
	var shell: PanelContainer = _shell(300.0)
	var v: VBoxContainer = _column(shell)
	_back(v, host)
	_title(v, UiKit.label_for("Share", "مشاركة"))
	_note(v, UiKit.label_for(
		"Writes a PNG and opens the folder holding it, ready to attach.",
		"يكتب صورة PNG ويفتح مجلدها، جاهزة للإرسال."))
	var b: Button = UiKit.make_text_button(UiKit.label_for("Share", "مشاركة"), true)
	b.custom_minimum_size = Vector2(0.0, UiKit.s(46.0))
	b.pressed.connect(func() -> void: host.share_project())
	v.add_child(b)
	_note(v, UiKit.label_for(
		"A native share sheet on Android needs a platform plugin, which cannot live inside the project itself.",
		"لوحة المشاركة في أندرويد تحتاج إضافة على مستوى النظام لا يمكن أن تعيش داخل المشروع."))
	return shell

# ------------------------------------------------------ animation settings

## Only meaningful for an animation project, so it is only offered there.
static func animation_page(host: Node) -> PanelContainer:
	var shell: PanelContainer = _shell(300.0)
	var v: VBoxContainer = _column(shell)
	_back(v, host)
	_title(v, UiKit.label_for("Animation", "رسوم متحركة"))

	var p: ProjectManager.Project = host.current_project()
	if p == null or p.kind != ProjectManager.Kind.ANIMATION:
		_note(v, UiKit.label_for("Open an animation project first",
			"افتح مشروع رسوم متحركة أولاً"))
		return shell

	# Workspace selection happens only during creation. Once the project exists,
	# this page is for Ivory animation settings; Stretchy owns its own settings.

	var rates: Array = [12, 24, 25, 30, 60]
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", int(UiKit.s(6.0)))
	grid.add_theme_constant_override("v_separation", int(UiKit.s(6.0)))
	v.add_child(grid)

	var btns: Array[Button] = []
	for r in rates:
		var b: Button = UiKit.make_text_button("%d fps" % int(r), true)
		b.toggle_mode = true
		b.set_pressed_no_signal(int(r) == p.fps)
		btns.append(b)
		grid.add_child(b)
	for i in btns.size():
		var idx: int = i
		var value: int = int(rates[i])
		btns[i].pressed.connect(func() -> void:
			host.set_fps(value)
			for k in btns.size():
				btns[k].set_pressed_no_signal(k == idx))

	UiKit.slider_row(v, UiKit.label_for("Frames", "عدد الإطارات"),
		1.0, 600.0, float(p.frames), 1.0, "",
		func(x: float) -> void: host.set_frames(int(x)))
	_note(v, UiKit.label_for(
		"The timeline reads these. Length can also be changed from its own settings.",
		"التايم لاين يقرأ هذه. والمدّة تُغيَّر أيضاً من إعداداته."))

	v.add_child(HSeparator.new())
	var to_export: Button = UiKit.make_text_button(
		UiKit.label_for("Video export settings", "إعدادات تصدير الفيديو"), true)
	to_export.pressed.connect(func() -> void:
		host.open_settings_page("mp4"))
	v.add_child(to_export)
	_note(v, UiKit.label_for(
		"Size, quality, sound and range live there — they are asked at a different moment than these.",
		"الحجم والجودة والصوت والنطاق هناك — لأنها تُسأل في لحظة غير هذه."))
	return shell

# --------------------------------------------------------- project options

## A list of commands, not a toolbar — so it is set in words. Icons here
## would make a menu look like a row of tools and read slower, not faster.
static func project_options(host: Node, p: ProjectManager.Project) -> PanelContainer:
	var shell: PanelContainer = _shell()
	var v: VBoxContainer = _column(shell)
	_title(v, p.title)
	_note(v, "%s  ·  %s  ·  %d × %d" % [_kind_word(p.kind), p.created,
		int(p.page.x), int(p.page.y)])
	v.add_child(HSeparator.new())

	var add: Callable = func(text: String, action: Callable) -> void:
		var b: Button = UiKit.make_text_button(text, true)
		b.custom_minimum_size = Vector2(UiKit.s(240.0), UiKit.s(46.0))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(action)
		v.add_child(b)

	add.call(UiKit.label_for("Open", "فتح"), func() -> void: host.open_project(p))

	var focused: bool = host.view.projects.focus_on == p
	if focused:
		add.call(UiKit.label_for("Leave focus", "إنهاء التركيز"),
			func() -> void: host.leave_focus())
		var others: String = UiKit.label_for("Hide the others", "أخفِ البقية")
		if not host.view.projects.focus_shows_others:
			others = UiKit.label_for("Show the others", "أظهر البقية")
		add.call(others, func() -> void: host.toggle_neighbours())
	else:
		add.call(UiKit.label_for("Focus on it", "التركيز عليه"),
			func() -> void: host.focus_project(p))

	if focused:
		add.call(UiKit.label_for("Straighten", "اعدل الميل"),
			func() -> void: host.view.straighten())

	var guide: String = UiKit.label_for("Hide the grid", "أخفِ الشبكة")
	if not p.grid_guide:
		guide = UiKit.label_for("Show the grid", "أظهر الشبكة")
	add.call(guide, func() -> void: host.toggle_guide())

	# Moving a sheet is a press held on the sheet itself, not a command in
	# a list — so there is nothing here to turn it on with.
	add.call(UiKit.label_for("Duplicate", "نسخة مطابقة"),
		func() -> void: host.duplicate_project(p))
	add.call(UiKit.label_for("Favourite", "مميّز"),
		func() -> void: host.toggle_favourite_of(p))
	# Pages are turned and added on screen while focused, not from here.
	if p.kind == ProjectManager.Kind.ANIMATION:
		add.call(UiKit.label_for("Animation", "رسوم متحركة"),
			func() -> void: host.open_settings_page("animation"))
	add.call(UiKit.label_for("Export", "تصدير"),
		func() -> void: host.open_settings_page("export"))
	add.call(UiKit.label_for("Save and close", "حفظ وإغلاق"),
		func() -> void: host.close_project(p))

	v.add_child(HSeparator.new())

	# Deleting a whole project is the one thing here with no undo, so it
	# asks once rather than acting on the first tap.
	var armed: Array = [false]
	var kill: Button = UiKit.make_text_button(UiKit.label_for("Delete", "حذف"), true)
	kill.custom_minimum_size = Vector2(0.0, UiKit.s(46.0))
	kill.pressed.connect(func() -> void:
		if not armed[0]:
			armed[0] = true
			kill.text = UiKit.label_for("Tap again to delete", "اضغط ثانية للحذف")
			return
		host.delete_project(p))
	v.add_child(kill)
	return shell

static func _kind_word(kind: int) -> String:
	if kind == ProjectManager.Kind.ANIMATION:
		return UiKit.label_for("Animation", "رسوم متحركة")
	if kind == ProjectManager.Kind.COMIC:
		return UiKit.label_for("Comic", "قصة مصورة")
	return UiKit.label_for("Drawing", "رسم")

# ----------------------------------------------------- transfer of the decree

## Three screens, one question each.
##
## *Which layers*, then *which project*, then *how they should land*. They are
## three panels and not one long form for a reason that shows itself on a
## phone: each answer changes what the next question should say, and a form
## that asks all three at once has to show every project and every layer at the
## same time on a screen that fits about eight rows.
##
## Backing out of any of them keeps the answers already given. The plan lives
## on the shell, not on the panel, so a panel rebuilt in another language or
## after a rotation finds the same choices ticked.

## How large a layer's picture is drawn beside its name.
const TRANSFER_THUMB: float = 46.0

## A layer's own drawing, shown the way the canvas shows it.
##
## The premultiplied material is not decoration. These pixels come straight off
## a canvas tile, where colour is already multiplied by its own alpha, and a
## TextureRect drawing them the ordinary way puts a dark halo round every
## stroke. It is the same material the layers panel uses on the same pictures.
static func _transfer_thumb(tex: Texture2D) -> Control:
	var frame: PanelContainer = PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.custom_minimum_size = Vector2(UiKit.s(TRANSFER_THUMB),
		UiKit.s(TRANSFER_THUMB))
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color("#f4f1ea")
	sb.border_color = Color("#4a505c")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(UiKit.s(6.0)))
	frame.add_theme_stylebox_override("panel", sb)

	var pic: TextureRect = TextureRect.new()
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.material = PaintSurface.premultiplied_material()
	pic.texture = tex
	frame.add_child(pic)
	return frame

## Screen one: which layers are going.
static func transfer_layers(host: Node) -> PanelContainer:
	var plan: DrawTransfer.Plan = host.transfer_plan()
	var shell: PanelContainer = _shell(360.0)
	var v: VBoxContainer = _column(shell, 560.0)
	_title(v, UiKit.label_for("Transfer of the decree", "نقل المرسوم"))
	_back(v, host, "menu")
	_note(v, UiKit.label_for(
		"Choose what is going. The drawing stays here — a transfer takes a copy.",
		"اختر ما سينتقل. الرسمة تبقى هنا — النقل يأخذ نسخة."))

	var rows: Array = DrawTransfer.rows(plan.source, plan.page)
	if rows.is_empty():
		_note(v, UiKit.label_for("There is nothing on this page yet.",
			"لا شيء في هذه الصفحة بعد."))
		return shell

	var count_label: Label = UiKit.make_label("", 12.0, UiKit.ACCENT)
	var next_b: Button = UiKit.make_text_button(
		UiKit.label_for("Choose a project", "اختر مشروعاً"), true)
	next_b.custom_minimum_size = Vector2(0.0, UiKit.s(48.0))

	# Named so the buttons can be redrawn without rebuilding the panel: a
	# panel rebuilt under the finger loses the press that caused it.
	var toggles: Array = []

	var restate: Callable = func() -> void:
		var n: int = plan.count()
		count_label.text = Lang.count_of(n, "{0} layer chosen",
			"{0} layers chosen", "طبقة واحدة مختارة", "{0} طبقات مختارة")
		next_b.disabled = n == 0
		for entry in toggles:
			var pair: Array = entry
			var b: Button = pair[0]
			if is_instance_valid(b):
				b.set_pressed_no_signal(plan.holds(int(pair[1])))

	# Everything at once, which is what anyone transferring a finished
	# drawing wants and would otherwise tap twenty times to say.
	var all_b: Button = UiKit.make_text_button(
		UiKit.label_for("Select all", "تحديد الكل"), true)
	all_b.toggle_mode = true
	all_b.custom_minimum_size = Vector2(0.0, UiKit.s(44.0))
	all_b.set_pressed_no_signal(plan.count() == rows.size())
	all_b.toggled.connect(func(on: bool) -> void:
		plan.clear()
		if on:
			for r in rows:
				plan.chosen[int((r as Dictionary)["id"])] = true
		restate.call())
	v.add_child(all_b)
	v.add_child(count_label)
	v.add_child(HSeparator.new())

	for r in rows:
		var row: Dictionary = r
		var id: int = int(row["id"])
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override("separation", int(UiKit.s(7.0)))

		# The picture is a second way to press the same switch. A list of
		# drawings where the drawings are not what you touch reads as a list
		# of names with decoration beside them.
		var pic_b: Button = Button.new()
		pic_b.toggle_mode = true
		pic_b.flat = true
		pic_b.focus_mode = Control.FOCUS_NONE
		pic_b.custom_minimum_size = Vector2(UiKit.s(TRANSFER_THUMB),
			UiKit.s(TRANSFER_THUMB))
		var art: Control = _transfer_thumb(row["thumb"])
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pic_b.add_child(art)
		line.add_child(pic_b)

		var name_text: String = String(row["title"])
		if bool(row["background"]):
			name_text = UiKit.label_for("Background", "الخلفية")
		var tail: Array = []
		if bool(row["empty"]):
			tail.append(UiKit.label_for("empty", "فارغة"))
		if bool(row["hidden"]):
			tail.append(UiKit.label_for("hidden", "مخفية"))
		if not tail.is_empty():
			name_text += "   ·   " + "  ".join(tail)

		var b: Button = UiKit.make_text_button(name_text, true)
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0.0, UiKit.s(TRANSFER_THUMB))
		b.set_pressed_no_signal(plan.holds(id))
		b.toggled.connect(func(_on: bool) -> void:
			plan.toggle(id)
			all_b.set_pressed_no_signal(plan.count() == rows.size())
			restate.call())
		pic_b.toggled.connect(func(_on: bool) -> void:
			plan.toggle(id)
			all_b.set_pressed_no_signal(plan.count() == rows.size())
			restate.call())
		toggles.append([b, id])
		toggles.append([pic_b, id])

		line.add_child(b)
		v.add_child(line)

	v.add_child(HSeparator.new())
	next_b.pressed.connect(func() -> void:
		host.open_settings_page("transfer_to"))
	v.add_child(next_b)
	restate.call()
	return shell

## Screen two: the project boards.
static func transfer_target(host: Node) -> PanelContainer:
	var plan: DrawTransfer.Plan = host.transfer_plan()
	var shell: PanelContainer = _shell(360.0)
	var v: VBoxContainer = _column(shell, 560.0)
	_title(v, UiKit.label_for("Which project?", "إلى أي مشروع؟"))
	_back(v, host, "transfer")

	var boards: Array = DrawTransfer.targets(host.view.projects, plan.source)
	if boards.is_empty():
		_note(v, UiKit.label_for(
			"There is nowhere to send it yet. Make an animation or a comic first.",
			"لا مكان لإرساله بعد. أنشئ مشروع رسوم متحركة أو قصة مصورة أولاً."))
		return shell

	_note(v, Lang.count_of(plan.count(), "{0} layer is ready to go",
		"{0} layers are ready to go", "طبقة واحدة جاهزة للانتقال",
		"{0} طبقات جاهزة للانتقال"))
	v.add_child(HSeparator.new())

	for one in boards:
		var p: ProjectManager.Project = one
		var b: Button = UiKit.make_text_button(p.title, true)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0.0, UiKit.s(52.0))
		# The kind and the paper size under the name, because two projects
		# called "Drawing 2" and "Drawing 3" tell you nothing and their sizes
		# tell you which is the one you meant.
		b.text = "%s\n%s  ·  %s × %s" % [p.title, _kind_word(p.kind),
			Lang.number(int(p.page.x)), Lang.number(int(p.page.y))]
		b.pressed.connect(func() -> void:
			plan.target = p
			plan.target_page = p.active_page
			host.choose_transfer_target())
		v.add_child(b)
	return shell

## Screen three: one layer, or as many as were chosen.
static func transfer_mode(host: Node) -> PanelContainer:
	var plan: DrawTransfer.Plan = host.transfer_plan()
	var shell: PanelContainer = _shell(340.0)
	var v: VBoxContainer = _column(shell, 420.0)
	_title(v, UiKit.label_for("How should it land?", "كيف تصل؟"))
	_back(v, host, "transfer_to")

	var where: String = ""
	if plan.target != null:
		where = plan.target.title
	_note(v, Lang.fill("Going into {0}", [where], "ستذهب إلى {0}"))
	v.add_child(HSeparator.new())

	var one_b: Button = UiKit.make_text_button(
		UiKit.label_for("One layer", "طبقة واحدة"), true)
	one_b.custom_minimum_size = Vector2(0.0, UiKit.s(52.0))
	one_b.pressed.connect(func() -> void: host.finish_transfer(true))
	v.add_child(one_b)
	_note(v, UiKit.label_for(
		"Flattened into a single layer, exactly as it looks now.",
		"تُدمج في طبقة واحدة، تماماً كما تبدو الآن."))

	var many_b: Button = UiKit.make_text_button(
		UiKit.label_for("Several layers", "عدة طبقات"), true)
	many_b.custom_minimum_size = Vector2(0.0, UiKit.s(52.0))
	many_b.pressed.connect(func() -> void: host.finish_transfer(false))
	v.add_child(many_b)
	_note(v, UiKit.label_for(
		"Each layer arrives as its own layer, in the order it was drawn in.",
		"كل طبقة تصل كطبقة مستقلة، بالترتيب الذي رُسمت به."))
	return shell
