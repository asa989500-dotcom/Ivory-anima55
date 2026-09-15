class_name Lang
extends RefCounted
## Every visible string in one place.
##
## The English text is the key. That keeps call sites readable — a reader
## sees the sentence, not an identifier — and it means an untranslated
## string degrades into correct English rather than into a blank or a
## cryptic code.
##
## Arabic, Hebrew and Persian read right to left. Godot handles the shaping
## itself once a font with those glyphs is loaded; what it cannot guess is
## which way the interface should flow, so `is_rtl` drives that.

enum L { EN, AR, ES, DE, JA, ZH, KO }

const NAMES: Array = [
	"English", "العربية", "Español", "Deutsch", "日本語", "中文", "한국어",
]

static var current: int = L.EN

## Every key must appear once. GDScript rejects a duplicate at parse time
## with a message that points at the second one, not at the pair, so this
## keeps the list honest while it is being edited.
static func count() -> int:
	return TABLE.size()

static func is_rtl() -> bool:
	return current == L.AR

# ------------------------------------------------------------------ numbers

## The digits each language actually writes numbers with.
##
## Arabic is normally set with Eastern Arabic numerals, and a panel that says
## ٣٦٠ in Arabic but "24 fps" in Western digits looks half-finished — because
## it is. Everything else on this list uses the same digits as English, so the
## table has one entry and a default rather than seven near-identical rows.
const EASTERN_DIGITS: Array = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]

## A whole number, written the way the current language writes numbers.
static func number(value: int) -> String:
	return digits(str(value))

## Every digit in a piece of text converted, and everything else left alone —
## so "24 fps" and "1920 × 1080" come out right without the words being
## touched.
static func digits(text: String) -> String:
	if current != L.AR:
		return text
	var fast: Object = Native.lang()
	if fast != null:
		fast.set_tongue(current)
		return String(fast.digits(text))
	var out: String = ""
	for i in text.length():
		var c: String = text[i]
		if c >= "0" and c <= "9":
			out += String(EASTERN_DIGITS[c.to_int()])
		else:
			out += c
	return out

## A number with a fixed number of decimal places, in the right digits.
static func decimal(value: float, places: int = 1) -> String:
	return digits(String.num(value, clampi(places, 0, 6)))

# ------------------------------------------------------------------ filling

## A sentence with something dropped into it.
##
##     Lang.fill("Frame {0} of {1}", [3, 48])
##
## Placeholders rather than joined-up pieces, because word order is not the
## same in every language. Building "Frame " + n + " of " + total by
## concatenation bakes English order into the code, and there is no way for a
## translator to move the number to where their language needs it. With a
## placeholder they can: the German, Japanese and Arabic rows put {0} and {1}
## wherever those languages put them.
##
## Numbers passed in are converted to the language's own digits on the way.
static func fill(en: String, args: Array, fallback: String = "") -> String:
	var text: String = t(en, fallback)
	# --- one pass, and each value isolated ---
	#
	# Two reasons this goes through the native side when it is there.
	#
	# **Correctness.** Replacing "{0}" and then "{1}" means that if the value
	# put in for {0} happens to contain the text "{1}" — a filename, something
	# a person typed — the second replace reaches into it and substitutes
	# again. A single pass never looks at what it has already written.
	#
	# **Direction.** Dropping a Western number into an Arabic sentence lets
	# the Unicode bidirectional algorithm decide where it goes, and it does
	# not always put it where the sentence meant: two numbers in one sentence
	# can swap, and a trailing bracket can jump to the wrong end. Wrapping
	# each value in a directional isolate fixes it for two invisible
	# characters. See `ivory_lang.h`.
	var pieces: PackedStringArray = PackedStringArray()
	for i in args.size():
		var value: Variant = args[i]
		if value is int:
			pieces.append(str(int(value)))
		elif value is float:
			pieces.append(String.num(float(value), 2))
		else:
			pieces.append(String(value))
	var fast: Object = Native.lang()
	if fast != null:
		fast.set_tongue(current)
		return String(fast.fill(text, pieces))
	for i in pieces.size():
		text = text.replace("{%d}" % i, digits(pieces[i]))
	return text

## One or many, chosen by the count.
##
## ## Two forms, and why that used to be a shrug
##
## The old comment here admitted Arabic needs more than two and left it. That
## was wrong, and not slightly: Arabic has six plural categories and the
## difference between them is grammar, not style. Choosing the plural for two
## is wrong the way "two frame" is wrong in English, and a person reading it
## sees a program that does not speak their language.
##
## The six are now decided properly — see `plural_of` — and this function
## keeps its two-argument shape because most call sites genuinely only have
## two wordings to offer. What changed is which one gets chosen: a language
## with a dual now takes the singular wording for two, which reads far closer
## to right than the plural did.
##
## `count_many` is the door to all six for a call site that has them.
static func count_of(value: int, one_en: String, many_en: String,
		one_ar: String = "", many_ar: String = "") -> String:
	if plural_of(value) <= 2:
		# zero, one or two: the singular wording. Zero takes it as well,
		# because a language with a zero category words it around the
		# singular, and English never reaches here with zero anyway.
		return fill(one_en, [value], one_ar)
	return fill(many_en, [value], many_ar)

## Which of the six plural categories a count takes in the language in force.
##
## 0 zero, 1 one, 2 two, 3 few, 4 many, 5 other — CLDR's order. The rules
## themselves are CLDR's too, which matters: a plural rule is either the one
## the language publishes or it is wrong, and the transcription is checked
## against every boundary the published rule names in
## `native/ivory/tests/test_lang.cpp`.
static func plural_of(value: int) -> int:
	var fast: Object = Native.lang()
	if fast != null:
		fast.set_tongue(current)
		return int(fast.plural_of(value))
	return _plural_here(value)

## The same rules, for a build without the extension.
static func _plural_here(value: int) -> int:
	var n: int = absi(value)
	match current:
		L.AR:
			if n == 0:
				return 0
			if n == 1:
				return 1
			if n == 2:
				return 2
			var hundred: int = n % 100
			if hundred >= 3 and hundred <= 10:
				return 3
			if hundred >= 11 and hundred <= 99:
				return 4
			return 5
		L.JA, L.ZH, L.KO:
			# No grammatical number at all. Not a simplification — these
			# languages do not inflect the noun, and offering a translator two
			# boxes to fill with the same text invites them to differ by
			# accident.
			return 5
		_:
			return 1 if n == 1 else 5

## A sentence with a count in it, choosing between all six wordings.
##
## `forms` is up to six strings in CLDR order; a shorter array falls back to
## the last one it has, which is how a language needing two is served by an
## array of two.
static func count_many(value: int, forms: Array) -> String:
	if forms.is_empty():
		return str(value)
	var which: int = clampi(plural_of(value), 0, forms.size() - 1)
	return fill(String(forms[which]), [value])

static func name_of(code: int) -> String:
	return String(NAMES[clampi(code, 0, NAMES.size() - 1)])

## `fallback` is the Arabic wording written at the call site. It is used
## only when Arabic is selected and the table has nothing better, which
## keeps the older screens working while the table fills out.
##
## A row that is short, blank or missing falls through to English rather than
## to nothing. That is deliberate: a screen in mixed English and Arabic is
## usable, a screen with holes in it is not.
static func t(en: String, fallback: String = "") -> String:
	if current == L.EN:
		return en
	if TABLE.has(en):
		var row: Array = TABLE[en]
		var idx: int = current - 1
		if idx >= 0 and idx < row.size():
			var word: String = String(row[idx])
			if word != "":
				return word
	if current == L.AR and fallback != "":
		return fallback
	return en

## Whether a language's row for a key differs from the English key.
##
## Useful while translating: a row that has been filled in with the English
## text is not a translation, and counting it as one hides the gap. This is
## how a language can read 100% covered and still be half in English.
## Words that are the same in another language on purpose.
##
## The check below flags any row whose translation is identical to the English
## key, on the reasoning that an untouched row is usually an unfinished one.
## Run over this table it found fourteen, and every one turned out to be
## correct: "Zoom" and "Airbrush" and "Linear" really are those words in
## German, "Color" and "Poses" really are those words in Spanish, and
## "B-Spline" is the name of a thing rather than a word to translate.
##
## So they are listed. A warning that cries wolf gets switched off, and then
## it is not there on the day it is right — a list of known exceptions is what
## keeps the check worth reading.
const SAME_ON_PURPOSE: Array = [
	"Color", "Zoom", "Pin", "Poses", "B-Spline", "Airbrush", "Name",
	"Animation", "Comic", "Ring", "Linear", "Smart",
]

## Rows where a language still carries the English wording — the gaps a
## coverage count cannot see, because a row filled in with English is a filled
## row.
static func literal_copies(code: int) -> Array:
	var idx: int = code - 1
	var out: Array = []
	if code == L.EN:
		return out
	for key in TABLE.keys():
		if SAME_ON_PURPOSE.has(key):
			continue
		var row: Array = TABLE[key]
		if idx >= 0 and idx < row.size() and String(row[idx]) == String(key):
			out.append(key)
	return out

## How complete each language is, counted from the table itself.
##
## Coverage that is only known by reading the file is coverage nobody checks.
## A row that is short by one is invisible at the call site — it simply comes
## out in English and looks like a string somebody forgot to wrap. Counting it
## here makes the gap something the app can say out loud.
static func coverage(code: int) -> Dictionary:
	var idx: int = code - 1
	var total: int = TABLE.size()
	if code == L.EN:
		return {"done": total, "total": total, "share": 1.0}
	var done: int = 0
	for key in TABLE.keys():
		var row: Array = TABLE[key]
		if idx >= 0 and idx < row.size() and String(row[idx]) != "":
			done += 1
	return {"done": done, "total": total,
		"share": float(done) / maxf(float(total), 1.0)}

## The keys a language is still missing, for anyone filling the table in.
static func gaps(code: int) -> Array:
	var idx: int = code - 1
	var out: Array = []
	if code == L.EN:
		return out
	for key in TABLE.keys():
		var row: Array = TABLE[key]
		if idx < 0 or idx >= row.size() or String(row[idx]) == "":
			out.append(key)
	return out

# Order of each row: AR, ES, DE, JA, ZH, KO
const TABLE: Dictionary = {
	# --- tools ---
	"Brush": ["الفرشاة", "Pincel", "Pinsel", "ブラシ", "画笔", "브러시"],
	"Fill": ["الملء", "Relleno", "Füllen", "塗りつぶし", "填充", "채우기"],
	"Shapes": ["الأشكال", "Formas", "Formen", "図形", "形状", "도형"],
	"Color": ["الألوان", "Color", "Farbe", "カラー", "颜色", "색상"],
	"Eraser": ["الممحاة", "Borrador", "Radierer", "消しゴム", "橡皮擦", "지우개"],
	"Select": ["التحديد", "Selección", "Auswahl", "選択", "选择", "선택"],
	"Copy": ["نسخ", "Copiar", "Kopieren", "コピー", "复制", "복사"],
	"Paste": ["لصق", "Pegar", "Einfügen", "貼り付け", "粘贴", "붙여넣기"],
	"Layers": ["الطبقات", "Capas", "Ebenen", "レイヤー", "图层", "레이어"],
	"Settings": ["الإعدادات", "Ajustes", "Einstellungen", "設定", "设置", "설정"],

	# --- brushes ---
	"Pen": ["قلم", "Pluma", "Feder", "ペン", "钢笔", "펜"],
	"Ink": ["حبر", "Tinta", "Tinte", "インク", "墨", "잉크"],
	"Watercolor": ["ألوان مائية", "Acuarela", "Aquarell", "水彩", "水彩", "수채"],
	"Paint": ["دهان", "Pintura", "Farbe", "ペイント", "油彩", "물감"],
	"Spruce": ["شجر صنوبر", "Abeto", "Fichte", "モミ", "云杉", "침엽수"],
	"Leaves": ["أوراق شجر", "Hojas", "Blätter", "葉", "树叶", "나뭇잎"],
	"Fur": ["فرو", "Pelaje", "Fell", "毛", "毛发", "털"],
	"Airbrush": ["رذاذ", "Aerógrafo", "Airbrush", "エアブラシ", "喷枪", "에어브러시"],

	# --- common controls ---
	"Size": ["الحجم", "Tamaño", "Größe", "サイズ", "大小", "크기"],
	"Opacity": ["الشفافية", "Opacidad", "Deckkraft", "不透明度", "不透明度", "불투명도"],
	"Strength": ["القوة", "Fuerza", "Stärke", "強さ", "强度", "강도"],
	"Soft": ["ناعمة", "Suave", "Weich", "ソフト", "柔和", "부드럽게"],
	"Hard": ["حادة", "Duro", "Hart", "ハード", "硬", "딱딱하게"],
	"Square": ["مربعة", "Cuadrado", "Quadrat", "四角", "方形", "사각"],
	"Free": ["حر", "Libre", "Frei", "フリー", "自由", "자유"],
	"Line": ["خط", "Línea", "Linie", "直線", "直线", "직선"],
	"Rect": ["مربع", "Rect.", "Rechteck", "矩形", "矩形", "사각형"],
	"Circle": ["دائرة", "Círculo", "Kreis", "円", "圆形", "원"],
	"Curve": ["منحنى", "Curva", "Kurve", "曲線", "曲线", "곡선"],
	"Box": ["مربع", "Caja", "Kasten", "四角", "方框", "상자"],
	"Points": ["نقاط", "Puntos", "Punkte", "点", "点", "점"],
	"Back": ["رجوع", "Atrás", "Zurück", "戻る", "返回", "뒤로"],
	"Undo": ["تراجع", "Deshacer", "Rückgängig", "元に戻す", "撤销", "실행 취소"],
	"Redo": ["إعادة", "Rehacer", "Wiederholen", "やり直す", "重做", "다시 실행"],
	"Cancel": ["إلغاء", "Cancelar", "Abbrechen", "キャンセル", "取消", "취소"],
	"Place": ["ثبّت", "Colocar", "Platzieren", "配置", "放置", "배치"],
	"Create": ["أنشئ", "Crear", "Erstellen", "作成", "创建", "만들기"],
	"Delete": ["حذف", "Eliminar", "Löschen", "削除", "删除", "삭제"],
	"Duplicate": ["نسخة مطابقة", "Duplicar", "Duplizieren", "複製", "复制", "복제"],
	"Move": ["تحريك", "Mover", "Verschieben", "移動", "移动", "이동"],
	"Name": ["الاسم", "Nombre", "Name", "名前", "名称", "이름"],
	"Width": ["العرض", "Ancho", "Breite", "幅", "宽度", "너비"],
	"Height": ["الارتفاع", "Alto", "Höhe", "高さ", "高度", "높이"],
	"Pages": ["الصفحات", "Páginas", "Seiten", "ページ", "页数", "페이지"],
	"Pick": ["قطرة", "Cuentagotas", "Pipette", "スポイト", "取色", "스포이트"],

	# --- projects ---
	"New project": ["مشروع جديد", "Nuevo proyecto", "Neues Projekt",
		"新規プロジェクト", "新建项目", "새 프로젝트"],
	"Drawing": ["رسم", "Dibujo", "Zeichnung", "イラスト", "绘画", "그림"],
	"Animation": ["رسوم متحركة", "Animación", "Animation", "アニメ", "动画", "애니메이션"],
	# The project kind. Named in full in Arabic — "قصص مصورة" rather than the
	# transliteration "الكوميكس" that the rail used to show. A borrowed word
	# in an Arabic interface is a word the reader has to translate back, and
	# this one has a perfectly good name of its own.
	"Comic": ["قصص مصورة", "Cómic", "Comic", "コミック", "漫画", "만화"],
	"Comics": ["قصص مصورة", "Cómics", "Comics", "コミック", "漫画", "만화"],
	"Paper colour": ["لون الورقة", "Color del papel", "Papierfarbe",
		"用紙の色", "纸张颜色", "용지 색"],
	"Frame colour": ["لون الإطار", "Color del marco", "Rahmenfarbe",
		"枠の色", "边框颜色", "테두리 색"],
	"Favourite": ["مميّز", "Favorito", "Favorit", "お気に入り", "收藏", "즐겨찾기"],
	"Export": ["تصدير", "Exportar", "Exportieren", "書き出し", "导出", "내보내기"],
	"Share": ["مشاركة", "Compartir", "Teilen", "共有", "分享", "공유"],
	"Save and close": ["حفظ وإغلاق", "Guardar y cerrar", "Speichern und schließen",
		"保存して閉じる", "保存并关闭", "저장하고 닫기"],
	"Language": ["اللغة", "Idioma", "Sprache", "言語", "语言", "언어"],
	"Open": ["فتح", "Abrir", "Öffnen", "開く", "打开", "열기"],
	"Closed": ["مغلق", "Cerrado", "Geschlossen", "閉じています", "已关闭", "닫힘"],
	"Add page": ["أضف صفحة", "Añadir página", "Seite hinzufügen",
		"ページを追加", "添加页面", "페이지 추가"],
	"Tap to open": ["اضغط للفتح", "Toca para abrir", "Zum Öffnen tippen",
		"タップして開く", "点击打开", "탭하여 열기"],
	"Double tap to open": ["اضغط مرتين للفتح", "Toca dos veces para abrir",
		"Zum Öffnen doppelt tippen", "ダブルタップで開く", "双击打开",
		"두 번 탭하여 열기"],
	"Hold and drag to move it": ["اضغط مطولاً واسحب لتحريكه",
		"Mantén pulsado y arrastra para moverlo",
		"Gedrückt halten und ziehen zum Verschieben",
		"長押ししてドラッグで移動", "长按并拖动以移动", "길게 눌러 끌어 옮기기"],
	"Drag to move it": ["اسحب لتحريكه", "Arrastra para moverlo",
		"Zum Verschieben ziehen", "ドラッグして移動", "拖动以移动", "끌어서 이동"],
	"Drag to place it, then double tap to fix it":
		["اسحبه لتضعه، ثم اضغط مرتين لتثبيته",
		 "Arrástralo y toca dos veces para fijarlo",
		 "Ziehen und zum Fixieren doppelt tippen",
		 "ドラッグして配置し、ダブルタップで固定",
		 "拖动放置，双击固定",
		 "끌어서 놓은 뒤 두 번 탭하여 고정"],
	"Every project starts empty — its own layers, its own history":
		["كل مشروع يبدأ من الصفر — طبقاته وسجلّه خاصان به",
		 "Cada proyecto empieza vacío: sus capas, su historial",
		 "Jedes Projekt beginnt leer — eigene Ebenen, eigene Historie",
		 "各プロジェクトは空から始まります",
		 "每个项目都从零开始，拥有独立的图层与历史",
		 "모든 프로젝트는 비어 있게 시작합니다 — 고유한 레이어와 기록"],
	"Saved to": ["حُفظ في", "Guardado en", "Gespeichert unter", "保存先", "已保存至", "저장 위치"],
	"Nothing to export yet": ["لا يوجد ما يُصدَّر بعد", "Nada que exportar todavía",
		"Noch nichts zum Exportieren", "書き出すものがありません", "暂无可导出内容", "내보낼 항목이 없습니다"],
	"Video needs the timeline, which comes next":
		["الفيديو يحتاج التايم لاين، وهو التالي",
		 "El vídeo necesita la línea de tiempo, que viene después",
		 "Video braucht die Zeitleiste, die als Nächstes kommt",
		 "動画にはタイムラインが必要です",
		 "视频导出需要时间轴，将在下一步加入",
		 "동영상에는 타임라인이 필요하며, 다음 단계입니다"],
	"Each page separately": ["كل صفحة على حدة", "Cada página por separado",
		"Jede Seite einzeln", "各ページを個別に", "每页单独导出", "페이지별로 저장"],
	"One sheet": ["ورقة واحدة", "Una hoja", "Ein Blatt", "1枚にまとめる", "合并为一张", "한 장으로"],
	"Open this layer alone": ["افتح هذه الطبقة وحدها", "Abrir solo esta capa",
		"Nur diese Ebene öffnen", "このレイヤーだけ表示", "仅显示此图层", "이 레이어만 보기"],
	"Erase its contents": ["امسح محتواها", "Borrar su contenido",
		"Inhalt löschen", "内容を消去", "清除内容", "내용 지우기"],
	"Merge into the one below": ["دمج مع التي تحتها", "Combinar con la de abajo",
		"Mit der darunter verbinden", "下のレイヤーと結合", "向下合并", "아래 레이어와 병합"],
	"Background": ["الخلفية", "Fondo", "Hintergrund", "背景", "背景", "배경"],
	"Locked": ["مقفلة", "Bloqueada", "Gesperrt", "ロック中", "已锁定", "잠김"],
	"Unlocked": ["غير مقفلة", "Desbloqueada", "Entsperrt", "ロック解除", "未锁定", "잠금 해제"],

	# --- panels, menus and every line of guidance ---
	"Exit": ["خروج", "Salir", "Verlassen", "終了", "退出", "나가기"],
	"Plain": ["عادية", "Simple", "Schlicht", "標準", "标准", "기본"],
	"Fine": ["رفيعة", "Fina", "Fein", "細い", "细", "가는"],
	"Broad": ["عريضة", "Ancha", "Breit", "太い", "宽", "넓은"],
	"Rough": ["خشنة", "Áspera", "Rau", "かすれ", "粗糙", "거친"],
	"Deleted": ["حُذف", "Eliminado", "Gelöscht", "削除しました", "已删除", "삭제됨"],
	"The timeline reads these. Length can also be changed from its own settings.": ["التايم لاين يقرأ هذه. والمدّة تُغيَّر أيضاً من إعداداته.", "La línea de tiempo los lee. La duración también se cambia en sus ajustes.", "Die Zeitleiste liest diese. Die Länge lässt sich auch dort ändern.", "タイムラインがこれを読みます。長さはその設定からも変更できます。", "时间轴会读取这些设置，时长也可在其设置中修改。", "타임라인이 이 값을 읽습니다. 길이는 타임라인 설정에서도 바꿀 수 있습니다."],
	"Save project": ["احفظ المشروع", "Guardar proyecto", "Projekt speichern", "プロジェクトを保存", "保存项目", "프로젝트 저장"],
	"Saved": ["حُفظ", "Guardado", "Gespeichert", "保存しました", "已保存", "저장됨"],
	"Nothing is open. Make something.": ["لا شيء مفتوح. اصنع شيئاً.", "No hay nada abierto. Crea algo.", "Nichts geöffnet. Erstelle etwas.", "何も開いていません。作りましょう。", "当前没有打开的项目，先创建一个。", "열린 항목이 없습니다. 새로 만들어 보세요."],
	"New frame": ["إطار جديد", "Fotograma nuevo", "Neues Bild", "新規フレーム", "新建帧", "새 프레임"],
	"Duplicate after": ["نسخ بعده", "Duplicar después", "Danach duplizieren", "次に複製", "向后复制", "뒤에 복제"],
	"Starts blank, for a fresh pose.": ["يبدأ فارغاً، لوضعية جديدة.", "Empieza en blanco, para una pose nueva.", "Beginnt leer, für eine neue Pose.", "空から始まり、新しいポーズに。", "从空白开始，用于新姿势。", "비어 있게 시작하여 새 포즈에 사용합니다."],
	"Starts from the drawing before it, so the last pose can be traced.": ["يبدأ من الرسمة قبله، فتُتتبَّع الوضعية السابقة.", "Empieza desde el dibujo anterior, para calcar la última pose.", "Beginnt bei der vorigen Zeichnung, damit die letzte Pose nachgezogen werden kann.", "前の絵から始まるので、直前のポーズをなぞれます。", "从上一张开始，便于描摹上一个姿势。", "이전 그림에서 시작해 마지막 포즈를 따라 그릴 수 있습니다."],
	"Even speed": ["سرعة ثابتة", "Velocidad constante", "Gleichmäßig", "等速", "匀速", "등속"],
	"Hard cut": ["قطع حاد", "Corte seco", "Harter Schnitt", "カット", "硬切", "컷"],
	"Each shot holds until the next.": ["كل لقطة تمسك حتى التالية.", "Cada plano se mantiene hasta el siguiente.", "Jede Einstellung hält bis zur nächsten.", "各ショットは次まで保持されます。", "每个镜头保持到下一个。", "각 샷은 다음 샷까지 유지됩니다."],
	"Key the first shot, go to the last frame, frame it again. The move between is built for you.": ["ثبّت اللقطة الأولى، ثم اذهب لآخر إطار وأعد التأطير. والحركة بينهما تُبنى لك.", "Marca el primer plano, ve al último fotograma y reencuadra. El movimiento intermedio se crea solo.", "Ersten Ausschnitt keyen, zum letzten Bild gehen, neu rahmen. Die Bewegung entsteht von selbst.", "最初の構図にキーを打ち、最後のフレームで再構図すれば、間の動きが作られます。", "为首个镜头打关键帧，转到最后一帧重新构图，中间运动会自动生成。", "첫 샷에 키를 찍고 마지막 프레임에서 다시 잡으면 사이 움직임이 만들어집니다."],
	"Free memory now": ["حرّر الذاكرة الآن", "Liberar memoria ahora", "Speicher jetzt freigeben", "今すぐメモリを解放", "立即释放内存", "지금 메모리 해제"],
	"Freed": ["حُرِّر", "Liberado", "Freigegeben", "解放しました", "已释放", "해제됨"],
	"Empties the undo history and hands every sleeping tile back. The drawing itself is untouched.": ["يفرغ سجلّ التراجع ويعيد كل بلاطة نائمة. والرسم نفسه لا يُمسّ.", "Vacía el historial y devuelve cada tesela dormida. El dibujo no se toca.", "Leert die Historie und gibt jede schlafende Kachel zurück. Die Zeichnung bleibt unberührt.", "履歴を空にし、休止中のタイルを解放します。絵自体は変わりません。", "清空撤销历史并归还所有休眠图块，画作本身不受影响。", "실행 취소 기록을 비우고 잠든 타일을 반환합니다. 그림 자체는 그대로입니다."],
	"No frames yet": ["لا إطارات بعد", "Aún sin fotogramas", "Noch keine Bilder", "フレームはまだありません", "尚无帧", "아직 프레임이 없습니다"],
	"Point animation": ["التحريك بالنقاط", "Animación por puntos", "Punkt-Animation", "ポイントアニメーション", "点动画", "포인트 애니메이션"],
	"A grid on the drawing's outline. Place points and pull; nothing ever leaves the grid.": ["شبكة على حدود الرسمة. ضع نقاطاً واسحب؛ ولا شيء يخرج من الشبكة أبداً.", "Una malla sobre el contorno del dibujo. Coloca puntos y tira; nada sale de la malla.", "Ein Netz auf der Kontur der Zeichnung. Punkte setzen und ziehen; nichts verlässt das Netz.", "絵の輪郭に沿ったグリッド。点を置いて引っぱっても、グリッドの外には出ません。", "沿画面轮廓的网格。放点并拖动，任何东西都不会越出网格。", "그림 윤곽을 따르는 격자. 점을 놓고 당겨도 격자를 벗어나지 않습니다."],
	"Build": ["بناء", "Construir", "Aufbauen", "作成", "搭建", "만들기"],
	"Pose": ["تحريك", "Posar", "Posieren", "ポーズ", "摆姿", "포즈"],
	"Pose bone": ["تحريك عظمة", "Posar hueso", "Knochen posieren", "ボーンをポーズ", "摆动骨骼", "본 포즈"],
	"Build lays bones down. Pose swings them — take hold anywhere on a bone and turn it.": ["البناء يضع العظام. والتحريك يؤرجحها — امسك العظمة من أي مكان وأدرها.", "Construir coloca huesos. Posar los balancea: agarra el hueso en cualquier punto y gíralo.", "Aufbauen legt Knochen an. Posieren schwingt sie — irgendwo am Knochen greifen und drehen.", "作成はボーンを置き、ポーズは振ります。ボーンのどこを掴んでも回せます。", "搭建用于放置骨骼，摆姿用于摆动：抓住骨骼任意位置即可旋转。", "만들기는 본을 놓고, 포즈는 본을 휘두릅니다. 본의 어느 곳이든 잡아 돌리세요."],
	"Smooth curve": ["تنعيم منحنى", "Suavizar curva", "Kurve glätten", "カーブを整える", "平滑曲线", "커브 다듬기"],
	"Sculpt curve": ["نحت منحنى", "Esculpir curva", "Kurve formen", "カーブを彫る", "雕刻曲线", "커브 조각"],
	"Thicken": ["تثخين", "Engrosar", "Verdicken", "太くする", "加粗", "굵게"],
	"Thin": ["ترقيق", "Adelgazar", "Verdünnen", "細くする", "变细", "가늘게"],
	"Tap the button again to leave curve mode.": ["اضغط الزر ثانيةً للخروج من وضع المنحنيات.", "Toca el botón otra vez para salir del modo curvas.", "Erneut tippen, um den Kurvenmodus zu verlassen.", "もう一度タップするとカーブモードを終了します。", "再次点击该按钮可退出曲线模式。", "버튼을 다시 누르면 커브 모드를 종료합니다."],
	"Curve layer": ["طبقة المنحنيات", "Capa de curvas", "Kurvenebene", "カーブレイヤー", "曲线图层", "커브 레이어"],
	"Reshape": ["إعادة تشكيل", "Remodelar", "Umformen", "形を変える", "调整形状", "형태 변경"],
	"Vector eraser": ["ممحاة متجهية", "Borrador vectorial", "Vektor-Radierer", "ベクター消しゴム", "矢量橡皮", "벡터 지우개"],
	"Draw curve": ["رسم منحنى", "Dibujar curva", "Kurve zeichnen", "カーブを描く", "绘制曲线", "커브 그리기"],
	"Shape curve": ["تشكيل منحنى", "Modelar curva", "Kurve formen", "カーブを整える", "调整曲线", "커브 다듬기"],
	"Erase curve": ["حذف منحنى", "Borrar curva", "Kurve löschen", "カーブを消す", "删除曲线", "커브 삭제"],
	"Merge the bones in": ["ادمج العظام", "Fusionar los huesos", "Knochen einbinden", "ボーンを統合", "合并骨骼", "본 병합"],
	"Hands this folder's drawings to their nearest bones and freezes the skeleton where it lies. Only this folder — so other characters in the file are untouched.": ["يسلّم رسمات هذا المجلّد لأقرب عظامها ويجمّد الهيكل حيث هو. هذا المجلّد وحده — فبقية الشخصيات في الملف لا تُمسّ.", "Asigna los dibujos de esta carpeta a sus huesos más cercanos y fija el esqueleto donde está. Solo esta carpeta; los demás personajes no se tocan.", "Übergibt die Zeichnungen dieses Ordners den nächsten Knochen und friert das Skelett dort ein. Nur dieser Ordner — andere Figuren bleiben unberührt.", "このフォルダーの絵を最も近いボーンに割り当て、骨格を現在位置で固定します。他のキャラクターには影響しません。", "将此文件夹的图交给最近的骨骼并就地固定骨架。仅限本文件夹，其他角色不受影响。", "이 폴더의 그림을 가장 가까운 본에 넘기고 골격을 현재 위치에 고정합니다. 이 폴더만 해당되며 다른 캐릭터는 그대로입니다."],
	"Merged. The rig now moves this character.": ["مدموج. الرِج يحرّك هذه الشخصية الآن.", "Fusionado. El rig ya mueve a este personaje.", "Eingebunden. Das Rig bewegt diese Figur jetzt.", "統合済み。リグがこのキャラクターを動かします。", "已合并，绑定现在驱动该角色。", "병합됨. 이제 리그가 이 캐릭터를 움직입니다."],
	"Lines made of points, not pixels. Reshape them at any time, at any zoom, and let the app work out the in-betweens.": ["خطوط من نقاط لا من بكسلات. أعد تشكيلها متى شئت وبأي تقريب، ودع التطبيق يبني البينيّات.", "Líneas hechas de puntos, no de píxeles. Remodélalas cuando quieras, a cualquier zoom, y deja que la app cree las intermedias.", "Linien aus Punkten statt Pixeln. Jederzeit und bei jedem Zoom umformbar; die Zwischenbilder rechnet die App.", "ピクセルではなく点でできた線。いつでもどの拡大率でも形を変えられ、中割りはアプリが作ります。", "由点而非像素构成的线条。可随时在任意缩放下调整形状，中间帧由应用生成。", "픽셀이 아닌 점으로 이루어진 선. 언제든 어떤 배율에서든 형태를 바꿀 수 있고 중간 프레임은 앱이 만듭니다."],
	"Hide the timeline": ["أخفِ التايم لاين", "Ocultar la línea de tiempo", "Zeitleiste ausblenden", "タイムラインを隠す", "隐藏时间轴", "타임라인 숨기기"],
	"How you animate": ["كيف تحرّك", "Cómo animas", "Wie du animierst", "アニメの方法", "动画方式", "애니메이션 방식"],
	"Key frames": ["مفاتيح", "Fotogramas clave", "Keyframes", "キーフレーム", "关键帧", "키프레임"],
	"Frame by frame": ["إطاراً بإطار", "Fotograma a fotograma", "Bild für Bild", "コマ撮り", "逐帧", "프레임 단위"],
	"Pose at the start, pose at the end, and the app fills the middle.": ["ثبّت وضعية في البداية وأخرى في النهاية، والتطبيق يملأ ما بينهما.", "Pose al principio y al final; la app rellena el medio.", "Pose am Anfang, Pose am Ende — die App füllt die Mitte.", "最初と最後にポーズを付ければ、間は自動で埋まります。", "在开头与结尾摆姿势，中间由应用补足。", "처음과 끝에 포즈를 잡으면 중간은 앱이 채웁니다."],
	"One line, one drawing per frame. Drag a frame's right edge to hold it longer.": ["سطر واحد، ورسمة لكل إطار. اسحب حافة الإطار اليمنى ليدوم أطول.", "Una línea, un dibujo por fotograma. Arrastra el borde derecho para alargarlo.", "Eine Zeile, eine Zeichnung pro Bild. Rechte Kante ziehen, um sie länger zu halten.", "1行、1フレーム1枚。右端をドラッグすると長く保持します。", "一行，每帧一张。拖动右边缘可延长停留。", "한 줄, 프레임당 한 장. 오른쪽 가장자리를 끌면 더 길게 유지됩니다."],
	"Add frame": ["أضف إطاراً", "Añadir fotograma", "Bild hinzufügen", "フレームを追加", "添加帧", "프레임 추가"],
	"Timeline settings": ["إعدادات التايم لاين", "Ajustes de la línea de tiempo", "Zeitleisten-Einstellungen", "タイムライン設定", "时间轴设置", "타임라인 설정"],
	"Repeat": ["تكرار", "Repetir", "Wiederholen", "繰り返し", "循环", "반복"],
	"Frame width": ["عرض الإطار", "Ancho del fotograma", "Bildbreite", "フレーム幅", "帧宽", "프레임 너비"],
	"Zoom": ["التقريب", "Zoom", "Zoom", "ズーム", "缩放", "줌"],
	"Glide between keys": ["انسياب بين المفاتيح", "Deslizar entre claves", "Zwischen Keys gleiten", "キー間をなめらかに", "在关键帧间平滑过渡", "키 사이를 부드럽게"],
	"Move key by key": ["حركة مفتاحاً بمفتاح", "Mover clave a clave", "Key für Key bewegen", "キーごとに動かす", "逐关键帧移动", "키 단위로 이동"],
	"Key the first shot, go to the last frame, compose again, key it. The move between is built for you.": ["ثبّت اللقطة الأولى، ثم اذهب لآخر إطار وأعد التأطير وثبّته. والحركة بينهما تُبنى لك.", "Marca el primer encuadre, ve al último fotograma, recompón y márcalo. El movimiento intermedio se crea solo.", "Ersten Bildausschnitt keyen, zum letzten Bild gehen, neu setzen, keyen. Die Bewegung dazwischen entsteht von selbst.", "最初の構図にキーを打ち、最後のフレームで構図を決めてキーを打つと、間の動きが作られます。", "为首个镜头打关键帧，转到最后一帧重新构图再打一次，中间的运动会自动生成。", "첫 화면에 키를 찍고 마지막 프레임에서 다시 구도를 잡아 키를 찍으면 사이 움직임이 만들어집니다."],
	"Each key holds until the next. For a move that must hit its marks exactly.": ["كل مفتاح يمسك حتى التالي. لحركة يجب أن تصيب علاماتها بالضبط.", "Cada clave se mantiene hasta la siguiente. Para un movimiento que debe dar en el punto exacto.", "Jeder Key hält bis zum nächsten. Für eine Bewegung, die genau treffen muss.", "各キーは次まで保持されます。狙い通りに決める動きに。", "每个关键帧保持到下一个，适合必须精确到位的运动。", "각 키는 다음 키까지 유지됩니다. 정확히 맞춰야 하는 움직임에 적합합니다."],
	"Bone motion": ["حركة العظام", "Movimiento de huesos", "Knochenbewegung", "ボーンの動き", "骨骼运动", "본 움직임"],
	"Pose the first frame and the last; the app builds the swing between them.": ["ثبّت وضعية أول إطار وآخره؛ والتطبيق يبني الأرجحة بينهما.", "Pose el primer y el último fotograma; la app crea el balanceo entre ellos.", "Erstes und letztes Bild posieren; die App baut den Schwung dazwischen.", "最初と最後のフレームでポーズを取れば、間の振りが作られます。", "为首尾两帧摆好姿势，中间的摆动由应用生成。", "첫 프레임과 마지막 프레임에 포즈를 잡으면 사이 동작이 만들어집니다."],
	"Pose step by step": ["وضعية بعد وضعية", "Pose paso a paso", "Schritt für Schritt posieren", "一歩ずつポーズ", "逐步摆姿", "한 단계씩 포즈"],
	"Every key holds. Add many of them for a move you control entirely.": ["كل مفتاح يمسك. أضف الكثير منها لحركة تتحكّم بها كاملة.", "Cada clave se mantiene. Añade muchas para controlar el movimiento por completo.", "Jeder Key hält. Viele davon geben volle Kontrolle über die Bewegung.", "各キーは保持されます。多く打てば動きを完全に制御できます。", "每个关键帧都保持，多打几个即可完全掌控运动。", "각 키가 유지됩니다. 여러 개를 찍으면 움직임을 완전히 제어할 수 있습니다."],
	"Bone": ["عظمة", "Hueso", "Knochen", "ボーン", "骨骼", "본"],
	"Add bone": ["أضف عظاماً", "Añadir hueso", "Knochen hinzufügen", "ボーンを追加", "添加骨骼", "본 추가"],
	# --- the bone room, reached from the layer itself ---
	"Correct the bones": ["صحّح العظام", "Corregir los huesos",
		"Knochen korrigieren", "ボーンを修正", "修正骨骼", "본 수정"],
	"Move a joint": ["حرّك مفصلاً", "Mover una articulación",
		"Gelenk verschieben", "関節を移動", "移动关节", "관절 이동"],
	"Remove a bone": ["احذف عظماً", "Quitar un hueso", "Knochen entfernen",
		"ボーンを削除", "删除骨骼", "본 삭제"],
	"Accept": ["تطبيق", "Aceptar", "Übernehmen", "適用", "应用", "적용"],
	"Clear": ["امسح الكل", "Borrar todo", "Alles löschen", "すべて消去",
		"全部清除", "모두 지우기"],
	"Bone laid": ["وُضع العظم", "Hueso colocado", "Knochen gesetzt",
		"ボーンを配置しました", "已放置骨骼", "본을 놓았습니다"],
	"Bone removed": ["أُزيل العظم", "Hueso eliminado", "Knochen entfernt",
		"ボーンを削除しました", "已删除骨骼", "본을 삭제했습니다"],
	"Bones merged. Drag a joint to move the drawing.":
		["دُمجت العظام. اسحب مفصلاً لتحريك الرسم.",
		"Huesos fusionados. Arrastra una articulación para mover el dibujo.",
		"Knochen zusammengeführt. Ziehe ein Gelenk, um die Zeichnung zu bewegen.",
		"ボーンを統合しました。関節をドラッグして絵を動かします。",
		"骨骼已合并。拖动关节即可移动画面。",
		"본이 병합되었습니다. 관절을 끌어 그림을 움직이세요."],
	"Joints turn freely. Move them in Test.":
		["المفاصل تدور بحرية. حرّكها في وضع التجربة.",
		"Las articulaciones giran libremente. Muévelas en Prueba.",
		"Gelenke drehen sich frei. Bewege sie im Test.",
		"関節は自由に回ります。テストで動かしてください。",
		"关节可自由旋转。请在测试模式中移动。",
		"관절은 자유롭게 회전합니다. 테스트에서 움직이세요."],
	"Move bone": ["تحريك عظمة", "Mover hueso", "Knochen bewegen", "ボーンを移動", "移动骨骼", "본 이동"],
	"Remove bone": ["حذف عظمة", "Quitar hueso", "Knochen entfernen", "ボーンを削除", "删除骨骼", "본 삭제"],
	"Add pin": ["أضف نقطة", "Añadir alfiler", "Nadel hinzufügen", "ピンを追加", "添加图钉", "핀 추가"],
	"Move pin": ["تحريك نقطة", "Mover alfiler", "Nadel bewegen", "ピンを移動", "移动图钉", "핀 이동"],
	"Remove pin": ["حذف نقطة", "Quitar alfiler", "Nadel entfernen", "ピンを削除", "删除图钉", "핀 삭제"],
	"Animation layer": ["طبقة تحريك", "Capa de animación", "Animationsebene", "アニメーションレイヤー", "动画图层", "애니메이션 레이어"],
	"Drawing layer": ["طبقة رسم", "Capa de dibujo", "Zeichenebene", "描画レイヤー", "绘画图层", "그림 레이어"],
	"Holds what you paint.": ["تحمل ما ترسمه.", "Contiene lo que pintas.", "Enthält, was du malst.", "描いたものを保持します。", "保存你所绘制的内容。", "그린 내용을 담습니다."],
	"Bones and pins that move the drawings under it.": ["عظام ونقاط تحرّك الرسمات تحتها.", "Huesos y alfileres que mueven los dibujos debajo.", "Knochen und Nadeln, die die Zeichnungen darunter bewegen.", "下の絵を動かすボーンとピン。", "用于移动其下方图画的骨骼与图钉。", "아래 그림을 움직이는 본과 핀."],
	"Moves everything in its folder as one piece.": ["تحرّك كل ما في مجلّدها ككتلة واحدة.", "Mueve todo su carpeta como una sola pieza.", "Bewegt alles in seinem Ordner als ein Stück.", "フォルダー内をひとまとまりで動かします。", "将其文件夹内的所有内容作为整体移动。", "폴더 안의 모든 것을 하나로 움직입니다."],
	"Puppet pin": ["التحريك بالنقاط", "Alfileres", "Puppen-Nadeln", "パペットピン", "图钉变形", "퍼펫 핀"],
	"Fix the bones": ["تثبيت العظام", "Fijar los huesos", "Knochen festlegen", "ボーンを確定", "固定骨骼", "본 고정"],
	"Back to rest": ["العودة لوضع الراحة", "Volver al reposo", "Zurück zur Ruhelage", "静止状態に戻す", "回到静止姿势", "기본 자세로"],
	"Key the bones": ["ثبّت العظام في الزمن", "Marcar los huesos", "Knochen keyen", "ボーンにキーを打つ", "为骨骼打关键帧", "본에 키 찍기"],
	"Drag inside the drawing to lay a bone. Drag from an end to hang the next one from it.": ["اسحب داخل الرسمة لتضع عظمة. واسحب من طرفها لتعلّق التالية عليها.", "Arrastra dentro del dibujo para crear un hueso. Arrastra desde un extremo para encadenar el siguiente.", "Im Bild ziehen legt einen Knochen an. Von einem Ende ziehen hängt den nächsten daran.", "絵の中をドラッグしてボーンを置き、端からドラッグして次をつなげます。", "在画面内拖动以放置骨骼；从端点拖动可连接下一根。", "그림 안을 드래그해 본을 놓고, 끝에서 드래그해 다음 본을 잇습니다."],
	"A grid on the outline. Place pins and pull; three fingers puts it away.": ["شبكة على حدود الشخصية. ضع نقاطاً واسحب؛ وثلاثة أصابع تخفيها.", "Una malla sobre el contorno. Coloca alfileres y tira; tres dedos la ocultan.", "Ein Netz auf der Kontur. Nadeln setzen und ziehen; drei Finger blenden es aus.", "輪郭に沿ったグリッド。ピンを置いて引っぱり、三本指で閉じます。", "沿轮廓的网格。放置图钉并拖动；三指可收起。", "윤곽을 따르는 격자. 핀을 놓고 당기며, 세 손가락으로 닫습니다."],
	"Gives each drawing to its nearest bone. Do this once the skeleton is built.": ["يسلّم كل رسمة لأقرب عظمة إليها. افعله بعد أن يكتمل الهيكل.", "Asigna cada dibujo al hueso más cercano. Hazlo cuando el esqueleto esté listo.", "Ordnet jede Zeichnung dem nächsten Knochen zu. Danach, wenn das Skelett steht.", "各絵を最も近いボーンに割り当てます。骨組みができてから実行します。", "将每张图交给最近的骨骼。骨架搭好后再执行。", "각 그림을 가장 가까운 본에 배정합니다. 골격을 다 만든 뒤 실행하세요."],
	"New drawing": ["رسمة جديدة", "Nuevo dibujo", "Neue Zeichnung", "新しい絵", "新建画面", "새 그림"],
	"Play": ["تشغيل", "Reproducir", "Abspielen", "再生", "播放", "재생"],
	"Stop": ["إيقاف", "Detener", "Stopp", "停止", "停止", "정지"],
	"Previous frame": ["الإطار السابق", "Fotograma anterior", "Vorheriges Bild", "前のフレーム", "上一帧", "이전 프레임"],
	"Next frame": ["الإطار التالي", "Fotograma siguiente", "Nächstes Bild", "次のフレーム", "下一帧", "다음 프레임"],
	"Add a camera key": ["أضف مفتاح كاميرا", "Añadir clave de cámara", "Kamera-Key setzen", "カメラキーを追加", "添加相机关键帧", "카메라 키 추가"],
	"Camera": ["الكاميرا", "Cámara", "Kamera", "カメラ", "相机", "카메라"],
	"Onion skin": ["قشرة البصل", "Papel cebolla", "Zwiebelhaut", "オニオンスキン", "洋葱皮", "어니언 스킨"],
	"Frames behind": ["إطارات للخلف", "Fotogramas atrás", "Bilder zurück", "前方向のフレーム", "向前帧数", "이전 프레임 수"],
	"Frames ahead": ["إطارات للأمام", "Fotogramas adelante", "Bilder vorwärts", "後方向のフレーム", "向后帧数", "이후 프레임 수"],
	"Behind": ["الخلف", "Atrás", "Zurück", "前", "之前", "이전"],
	"Ahead": ["الأمام", "Adelante", "Vorwärts", "後", "之后", "이후"],
	"Frames per tap": ["إطارات لكل ضغطة", "Fotogramas por toque", "Bilder pro Tipp", "1タップあたりのフレーム", "每次点击帧数", "한 번 탭당 프레임"],
	"One tap keys this frame and the ones after it.": ["ضغطة واحدة تضع مفتاحاً هنا وفيما بعده.", "Un toque marca este fotograma y los siguientes.", "Ein Tippen setzt diesen und die folgenden Bilder.", "1タップでこのフレームと続くフレームにキーを打ちます。", "一次点击会为当前帧及其后续帧打关键帧。", "한 번 탭으로 현재 프레임과 이후 프레임에 키를 찍습니다."],
	"Timeline": ["التايم لاين", "Línea de tiempo", "Zeitleiste", "タイムライン", "时间轴", "타임라인"],
	"Frame": ["فريم", "Fotograma", "Bild", "フレーム", "帧", "프레임"],
	"Add camera": ["أضف كاميرا", "Añadir cámara", "Kamera hinzufügen",
		"カメラを追加", "添加相机", "카메라 추가"],
	"Add camera key": ["إضافة مفتاح كاميرا", "Añadir clave de cámara",
		"Kameraschlüssel setzen", "カメラキーを追加", "添加相机关键帧",
		"카메라 키 추가"],
	"Ease in and out": ["تسارع وتباطؤ", "Entrada y salida suaves",
		"Weich rein und raus", "イーズイン・アウト", "缓入缓出",
		"천천히 시작하고 천천히 끝내기"],
	"Ease in — start slowly": ["تسارع — يبدأ ببطء", "Entrada suave",
		"Weich beginnen", "ゆっくり始める", "缓慢开始", "천천히 시작"],
	"Ease out — arrive slowly": ["تباطؤ — يصل ببطء", "Salida suave",
		"Weich ankommen", "ゆっくり止まる", "缓慢结束", "천천히 도착"],
	"Travel to the next key": ["الانتقال إلى المفتاح التالي",
		"Recorrido a la siguiente clave", "Weg zum nächsten Schlüssel",
		"次のキーまでの移動", "到下一个关键帧的过渡", "다음 키까지의 이동"],
	"New keys use": ["المفاتيح الجديدة تستخدم", "Las claves nuevas usan",
		"Neue Schlüssel nutzen", "新しいキーの既定", "新关键帧使用",
		"새 키가 사용할 값"],
	"Set every key at once": ["طبّق على كل المفاتيح",
		"Aplicar a todas las claves", "Auf alle Schlüssel anwenden",
		"すべてのキーに適用", "应用于所有关键帧", "모든 키에 적용"],
	"How many behind": ["كم إطاراً للخلف", "Cuántos atrás", "Wie viele zurück",
		"前に何枚", "向前几帧", "이전 몇 장"],
	"How many ahead": ["كم إطاراً للأمام", "Cuántos adelante",
		"Wie viele vorwärts", "後に何枚", "向后几帧", "이후 몇 장"],
	"Puppet warp": ["التحريك بالدبابيس", "Deformación con pines",
		"Formgitter", "パペットワープ", "操控变形", "퍼펫 뒤틀기"],
	"Pins": ["الدبابيس", "Pines", "Nadeln", "ピン", "图钉", "핀"],
	"Undo the last pull": ["تراجع عن آخر سحبة", "Deshacer el último tirón",
		"Letzten Zug zurücknehmen", "直前の引きを取り消す", "撤销上一次拖拉",
		"마지막 당김 취소"],
	"Rights": ["الحقوق", "Derechos", "Rechte", "権利", "权利", "권리"],
	"Icons": ["الأيقونات", "Iconos", "Symbole", "アイコン", "图标", "아이콘"],
	"Edit the text": ["عدّل النص", "Editar el texto", "Text bearbeiten",
		"テキストを編集", "编辑文字", "텍스트 편집"],
	"Text updated": ["حُدّث النص", "Texto actualizado", "Text aktualisiert",
		"テキストを更新しました", "文字已更新", "텍스트가 갱신되었습니다"],
	"Pin": ["دبوس", "Pin", "Nadel", "ピン", "图钉", "핀"],
	"Compass": ["البوصلة", "Brújula", "Kompass", "コンパス", "罗盘", "나침반"],
	"Frame {0} of {1}": ["الإطار {0} من {1}", "Fotograma {0} de {1}",
		"Bild {0} von {1}", "{1} 中 {0} フレーム", "第 {0} 帧，共 {1} 帧",
		"{1} 중 {0} 프레임"],
	"{0} frames": ["{0} إطاراً", "{0} fotogramas", "{0} Bilder",
		"{0} フレーム", "{0} 帧", "{0} 프레임"],
	"1 frame": ["إطار واحد", "1 fotograma", "1 Bild", "1 フレーム", "1 帧",
		"1 프레임"],
	"Orbit": ["مدار", "Órbita", "Umlauf", "オービット", "环绕", "궤도"],
	"untranslated": ["غير مترجم", "sin traducir", "unübersetzt", "未翻訳",
		"未翻译", "미번역"],
	"Right-angle bend — an elbow that reaches its stop":
		["انحناء بزاوية قائمة — كوع يبلغ حدّه",
		 "Codo en ángulo recto, con tope",
		 "Rechtwinklige Beuge — ein Ellbogen mit Anschlag",
		 "直角の曲げ — 止まる肘", "直角弯曲 — 到位的肘部",
		 "직각 굽힘 — 멈추는 팔꿈치"],
	"Free bend — turns wherever it is taken":
		["انحناء حر — يدور حيث يُؤخذ", "Codo libre, gira a donde lo lleves",
		 "Freie Beuge — dreht sich, wohin man sie führt",
		 "自由な曲げ — 好きな向きに回る", "自由弯曲 — 随意转动",
		 "자유 굽힘 — 원하는 대로 회전"],
	"repeat": ["مكرّر", "repetido", "Wiederholung", "重複", "重复", "중복"],
	"stray": ["دخيل", "ajeno", "Fremdbild", "異物", "无关图", "이질적"],
	"Dropped {0} repeated or stray drawings":
		["حُذف {0} من الرسوم المكرّرة أو الدخيلة",
		 "Se descartaron {0} dibujos repetidos o ajenos",
		 "{0} doppelte oder fremde Zeichnungen verworfen",
		 "重複または異物の絵を {0} 枚除外しました",
		 "已剔除 {0} 张重复或无关的图", "중복되거나 이질적인 그림 {0}장 제외"],
	"Turn": ["تدوير", "Girar", "Drehen", "回す", "转动", "돌리기"],
	"Test": ["تجربة", "Probar", "Testen", "試す", "试验", "시험"],
	"Child": ["ابن", "Hijo", "Kind", "子", "子", "자식"],
	"Parent": ["أب", "Padre", "Eltern", "親", "父", "부모"],
	"Grandparent": ["جد", "Abuelo", "Großeltern", "祖父", "祖父", "조부모"],
	"Ring": ["حلقة", "Anillo", "Ring", "リング", "圆环", "링"],
	"Limb ring": ["حلقة طرف", "Anillo de miembro", "Gliedring",
		"手足リング", "肢体圆环", "팔다리 링"],
	"Body ring": ["حلقة الجسم", "Anillo del cuerpo", "Körperring",
		"全身リング", "身体圆环", "몸통 링"],
	"Show dead rings": ["أظهر الحلقات الميتة", "Mostrar anillos inertes",
		"Tote Ringe zeigen", "停止したリングを表示", "显示停用圆环",
		"정지된 링 표시"],
	"Hide dead rings": ["أخفِ الحلقات الميتة", "Ocultar anillos inertes",
		"Tote Ringe verbergen", "停止したリングを隠す", "隐藏停用圆环",
		"정지된 링 숨기기"],
	"Import PNG sequence": ["استيراد تسلسل PNG", "Importar secuencia PNG",
		"PNG-Sequenz importieren", "PNG連番を読み込む", "导入 PNG 序列",
		"PNG 시퀀스 가져오기"],
	"Export to timeline": ["تصدير إلى التايم لاين", "Exportar a la línea de tiempo",
		"In die Zeitleiste exportieren", "タイムラインへ書き出す",
		"导出到时间轴", "타임라인으로 내보내기"],
	"Poses": ["الوضعيات", "Poses", "Posen", "ポーズ", "姿势", "포즈"],
	"skipped": ["تُخطّي", "omitidos", "übersprungen", "スキップ", "已跳过",
		"건너뜀"],
	"Facing": ["الاتجاه", "Orientación", "Blickrichtung", "向き", "朝向",
		"방향"],
	"Bones": ["العظام", "Huesos", "Knochen", "ボーン", "骨骼", "본"],
	"Rings": ["الدوائر", "Anillos", "Ringe", "リング", "圆环", "링"],
	"Front": ["أمام", "Frente", "Vorne", "正面", "正面", "정면"],
	"Front right": ["أمام يمين", "Frente derecha", "Vorne rechts",
		"右前", "右前", "우전면"],
	"Right": ["يمين", "Derecha", "Rechts", "右", "右", "우측"],
	"Back right": ["خلف يمين", "Atrás derecha", "Hinten rechts", "右後",
		"右后", "우후면"],
	"Back left": ["خلف يسار", "Atrás izquierda", "Hinten links", "左後",
		"左后", "좌후면"],
	"Left": ["يسار", "Izquierda", "Links", "左", "左", "좌측"],
	"Front left": ["أمام يسار", "Frente izquierda", "Vorne links", "左前",
		"左前", "좌전면"],
	"Nothing imported yet": ["لم يُستورد شيء بعد", "Aún no se ha importado nada",
		"Noch nichts importiert", "まだ何も読み込まれていません",
		"尚未导入任何内容", "아직 가져온 것이 없습니다"],

	# --- stage 137 ---
	"Finish": ["إتمام", "Terminar", "Fertig", "完了", "完成", "완료"],
	"Finish splitting": ["إتمام التقسيم", "Terminar división",
		"Teilung abschließen", "分割を完了", "完成分割", "분할 완료"],
	"Discard splitting": ["إلغاء التقسيم", "Descartar división",
		"Teilung verwerfen", "分割を破棄", "放弃分割", "분할 취소"],
	"Panels": ["اللوحات", "Viñetas", "Panels", "コマ", "分格", "칸"],
	"Cuts": ["القطوع", "Cortes", "Schnitte", "カット", "切割", "컷"],
	"Blend colours": ["دمج الألوان", "Fusionar colores", "Farben mischen",
		"色を混ぜる", "混合颜色", "색 혼합"],
	"Blend strength": ["شدة الدمج", "Intensidad", "Stärke", "強さ", "强度",
		"강도"],
	"Blend size": ["حجم الدمج", "Tamaño", "Größe", "サイズ", "大小", "크기"],
	"Pick up": ["الالتقاط", "Recoger", "Aufnehmen", "拾い上げ", "拾取", "집기"],
	"Mix": ["مزج", "Mezclar", "Mischen", "混合", "混合", "혼합"],
	"Gradient": ["تدرّج", "Degradado", "Verlauf", "グラデーション", "渐变",
		"그라데이션"],
	"Smudge": ["تلطيخ", "Difuminar", "Verwischen", "ぼかし", "涂抹", "번지기"],
	"Average": ["متوسط", "Promedio", "Mittelwert", "平均", "平均", "평균"],
	"Snap to two": ["اقتناص اللونين", "Ajustar a dos", "Auf zwei fangen",
		"2色に寄せる", "吸附两色", "두 색으로"],
	"Hold above": ["تثبيت ما فوق", "Fijar arriba", "Oben halten",
		"上を固定", "固定上方", "위 고정"],
	"Sequential hold": ["تثبيت تسلسلي", "Fijación secuencial",
		"Sequenzielles Halten", "連鎖固定", "顺序固定", "연쇄 고정"],
	"Release hold": ["إلغاء التثبيت", "Soltar", "Freigeben", "固定解除",
		"解除固定", "고정 해제"],
	"Four fingers to cancel": ["أربعة أصابع للإلغاء",
		"Cuatro dedos para cancelar", "Vier Finger zum Abbrechen",
		"4本指でキャンセル", "四指取消", "네 손가락으로 취소"],
	"Tool cancelled": ["أُلغيت الأداة", "Herramienta cancelada",
		"Werkzeug abgebrochen", "ツールを解除", "已取消工具", "도구 취소됨"],
	"Web": ["شبكة", "Red", "Netz", "ウェブ", "网", "웹"],
	"Hair halo": ["هالات شعرية", "Halos", "Haarkränze", "ヘアハロー", "发光环",
		"헤어 헤일로"],
	"Chalk": ["طباشير", "Tiza", "Kreide", "チョーク", "粉笔", "분필"],
	"Wrap twice to fasten": ["لُفّ مرتين للتثبيت",
		"Enrolla dos veces para fijar", "Zweimal wickeln zum Befestigen",
		"2回巻いて固定", "缠绕两圈固定", "두 번 감아 고정"],
	"Fastened": ["مثبّت", "Fijado", "Befestigt", "固定済み", "已固定", "고정됨"],
	"Written instructions": ["تعليمات مكتوبة", "Instrucciones escritas",
		"Schriftliche Anleitung", "文章の手順", "文字说明", "서면 지침"],
	"Working order": ["ترتيب العمل", "Orden de trabajo", "Arbeitsreihenfolge",
		"作業順序", "工作顺序", "작업 순서"],
	"Pin map": ["خريطة الدبابيس", "Mapa de alfileres", "Nadelkarte",
		"ピン配置図", "针位图", "핀 지도"],
	"Chart": ["مخطط", "Diagrama", "Diagramm", "チャート", "图表", "차트"],
	"Print sheets": ["أوراق الطباعة", "Hojas de impresión", "Druckbögen",
		"印刷シート", "打印页", "인쇄 시트"],
	"Export everything": ["تصدير كل الصيغ", "Exportar todo", "Alles exportieren",
		"すべて書き出し", "全部导出", "모두 내보내기"],

	# --- stage 138: the B-spline room ---
	"Warp points": ["نقاط التشويه", "Puntos de deformación", "Verzerrpunkte",
		"変形ポイント", "变形点", "왜곡 점"],
	"Add warp point": ["إضافة نقطة تشويه", "Añadir punto", "Punkt hinzufügen",
		"ポイントを追加", "添加变形点", "점 추가"],
	"Delete warp point": ["حذف نقطة التشويه", "Borrar punto", "Punkt löschen",
		"ポイントを削除", "删除变形点", "점 삭제"],
	"Studying the drawing": ["جارٍ دراسة الرسمة", "Estudiando el dibujo",
		"Zeichnung wird untersucht", "描画を解析中", "正在分析图画",
		"그림 분석 중"],
	"measuring the outline": ["قياس الحدود", "Midiendo el contorno",
		"Kontur wird vermessen", "輪郭を計測中", "测量轮廓", "윤곽 측정 중"],
	"rounding the form": ["تدوير الشكل", "Redondeando la forma",
		"Form wird gerundet", "形を丸めています", "圆化形体", "형태 둥글리기"],
	"finding the centre line": ["إيجاد خط المنتصف", "Buscando el eje",
		"Mittellinie wird gesucht", "中心線を探索中", "寻找中线",
		"중심선 찾는 중"],
	"learning what each point reaches": ["دراسة مدى كل نقطة",
		"Aprendiendo el alcance", "Reichweite wird gelernt", "影響範囲を学習中",
		"学习各点范围", "각 점의 범위 학습 중"],
	"placing the bones": ["وضع العظام", "Colocando los huesos",
		"Knochen werden gesetzt", "ボーンを配置中", "放置骨骼", "본 배치 중"],
	"Cancel study": ["إلغاء الدراسة", "Cancelar", "Abbrechen", "解析を中止",
		"取消分析", "분석 취소"],
	"Share of turn": ["نسبة الدوران", "Parte del giro", "Anteil der Drehung",
		"回転の割合", "旋转比例", "회전 비율"],
	"All sizes": ["كل المقاسات", "Todos los tamaños", "Alle Größen",
		"すべてのサイズ", "全部尺寸", "모든 크기"],
	"Or type": ["أو اكتب", "O escribe", "Oder eingeben", "または入力",
		"或输入", "또는 입력"],
	"Let it change transparency": ["اسمح بتغيير الشفافية",
		"Permitir cambiar la transparencia", "Transparenz ändern erlauben",
		"透明度の変更を許可", "允许改变透明度", "투명도 변경 허용"],
	"Reach": ["المدى", "Alcance", "Reichweite", "範囲", "范围", "범위"],
	"Turn left and right": ["الدوران يمينًا ويسارًا", "Girar a los lados",
		"Nach links und rechts", "左右に回す", "左右转动", "좌우 회전"],
	"Turn up and down": ["الدوران فوق وتحت", "Girar arriba y abajo",
		"Nach oben und unten", "上下に回す", "上下转动", "상하 회전"],
	"Tilt": ["الميل", "Inclinar", "Neigen", "傾ける", "倾斜", "기울기"],
	"Secondary bones": ["العظام الثانوية", "Huesos secundarios",
		"Sekundäre Knochen", "補助ボーン", "次级骨骼", "보조 본"],
	"Smart bone rig": ["هيكل عظام ذكي", "Esqueleto inteligente",
		"Intelligentes Rig", "スマートボーン", "智能骨骼", "스마트 본"],
	"Record action": ["تسجيل حركة", "Grabar acción", "Aktion aufnehmen",
		"アクションを記録", "记录动作", "동작 기록"],
	"Clear actions": ["مسح الحركات", "Borrar acciones", "Aktionen löschen",
		"アクションを消去", "清除动作", "동작 지우기"],
	"Character 360": ["شخصية 360", "Personaje 360", "Figur 360",
		"キャラクター360", "角色360", "캐릭터 360"],
	"Export to project": ["تصدير إلى المشروع", "Exportar al proyecto",
		"In das Projekt exportieren", "プロジェクトへ書き出し", "导出到项目",
		"프로젝트로 내보내기"],
	"Undo last": ["تراجع", "Deshacer", "Rückgängig", "元に戻す", "撤销",
		"실행 취소"],
	"Move the curve": ["تحريك المنحنى", "Mover la curva", "Kurve bewegen",
		"曲線を動かす", "移动曲线", "곡선 이동"],
	"One point": ["نقطة واحدة", "Un punto", "Ein Punkt", "1点", "单点",
		"한 점"],
	"Spread": ["موزّع", "Repartido", "Verteilt", "分散", "分散", "분산"],
	"Stiff": ["متيبّس", "Rígido", "Steif", "硬め", "刚性", "뻣뻣함"],
	"Light layer": ["طبقة ضوء", "Capa de luz", "Lichtebene",
		"ライトレイヤー", "光照图层", "빛 레이어"],
	"Light": ["ضوء", "Luz", "Licht", "ライト", "光", "빛"],
	"Opposite": ["المقابل", "Opuesto", "Gegenüber", "補色", "对比色", "보색"],
	"Triad": ["ثلاثي", "Tríada", "Triade", "トライアド", "三色", "삼색"],
	"Near": ["قريب", "Cercano", "Benachbart", "近似色", "邻近色", "유사색"],
	"Tolerance": ["التسامح", "Tolerancia", "Toleranz", "許容差", "容差",
		"허용치"],
	"Tuck under the line": ["الاندساس تحت الخط", "Meterse bajo la línea",
		"Unter die Linie schieben", "線の下に潜り込む", "钻入线条下方",
		"선 아래로 파고들기"],
	"Bulb": ["مصباح", "Bombilla", "Glühbirne", "電球", "灯泡", "전구"],
	"Filament": ["خيط متوهج", "Filamento", "Glühfaden", "フィラメント",
		"灯丝", "필라멘트"],
	"Lamp": ["ضوء واسع", "Lámpara", "Lampe", "ランプ", "灯", "램프"],
	"Flare": ["توهج نجمي", "Destello", "Blendenstern", "フレア", "星芒",
		"플레어"],
	"Haze": ["ضباب ضوئي", "Neblina", "Dunst", "ヘイズ", "光雾", "헤이즈"],
	"Shallow depth of field": ["عمق ميدان ضحل", "Profundidad de campo corta",
		"Geringe Schärfentiefe", "浅い被写界深度", "浅景深", "얕은 피사계 심도"],
	"Depth of field": ["عمق الميدان", "Profundidad de campo", "Schärfentiefe",
		"被写界深度", "景深", "피사계 심도"],
	"Full blur, no build-up": ["ضبابية كاملة بلا تدرج",
		"Desenfoque total, sin transición", "Voll unscharf, ohne Übergang",
		"段階なしの完全なぼかし", "完全模糊，无渐变", "단계 없는 완전 흐림"],
	"Cinematic fade": ["تلاشٍ سينمائي", "Fundido cinematográfico",
		"Filmische Überblendung", "シネマティックなフェード", "电影级渐隐",
		"영화적 페이드"],
	"How soft": ["مقدار الضبابية", "Cuánto desenfoque", "Wie weich",
		"ぼかしの強さ", "模糊程度", "흐림 정도"],
	"Remove this focus line": ["احذف خط التركيز", "Quitar esta línea de foco",
		"Diese Fokuslinie entfernen", "このフォーカス線を削除",
		"移除该对焦线", "이 초점 선 제거"],
	"This layer is already the subject here": ["هذه الطبقة هي الموضوع هنا بالفعل",
		"Esta capa ya es el sujeto aquí", "Diese Ebene ist hier bereits das Motiv",
		"このレイヤーは既にここの被写体です", "该图层在此处已是主体",
		"이 레이어는 여기서 이미 주체입니다"],
	"Play from frame": ["التشغيل من الإطار", "Reproducir desde el fotograma",
		"Abspielen ab Bild", "再生開始フレーム", "从第几帧播放",
		"재생 시작 프레임"],
	"First frame": ["أول إطار", "Primer fotograma", "Erstes Bild",
		"最初のフレーム", "起始帧", "첫 프레임"],
	"Last frame": ["آخر إطار", "Último fotograma", "Letztes Bild",
		"最後のフレーム", "结束帧", "마지막 프레임"],
	"Whole scene": ["المشهد كامله", "Escena completa", "Ganze Szene",
		"シーン全体", "整个场景", "장면 전체"],
	"Play the whole scene": ["شغّل المشهد كامله", "Reproducir toda la escena",
		"Ganze Szene abspielen", "シーン全体を再生", "播放整个场景",
		"장면 전체 재생"],
	"frames": ["إطاراً", "fotogramas", "Bilder", "フレーム", "帧", "프레임"],
	"B-Spline": ["بي-سبلاين", "B-Spline", "B-Spline", "Bスプライン",
		"B样条", "B-스플라인"],
	"Add point": ["أضف نقطة", "Añadir punto", "Punkt hinzufügen",
		"点を追加", "添加点", "점 추가"],
	"Connect": ["وصل", "Conectar", "Verbinden", "接続", "连接", "연결"],
	"Application": ["تطبيق", "Aplicar", "Anwenden", "適用", "应用", "적용"],
	"Rest pose": ["الوضع الأصلي", "Pose inicial", "Ruhehaltung",
		"元のポーズ", "初始姿势", "기본 자세"],
	"Clear rig": ["امسح الهيكل", "Borrar el esqueleto", "Rig löschen",
		"リグを消去", "清除骨架", "리그 지우기"],
	"Text layer": ["طبقة نص", "Capa de texto", "Textebene",
		"テキストレイヤー", "文字图层", "텍스트 레이어"],
	"Put pins on the drawing": ["ضع الدبابيس على الرسم",
		"Pon los pines sobre el dibujo", "Nadeln auf die Zeichnung setzen",
		"ピンは絵の上に置いてください", "请把图钉放在画上",
		"핀은 그림 위에 놓으세요"],
	"Depth": ["العمق", "Profundidad", "Tiefe", "深度", "深度", "깊이"],
	"No pin chosen": ["لا دبوس محدد", "Ningún pin elegido",
		"Keine Nadel gewählt", "ピン未選択", "未选择图钉", "선택된 핀 없음"],
	"Bring forward": ["إلى الأمام", "Traer al frente", "Nach vorn",
		"前面へ", "上移一层", "앞으로"],
	"Send back": ["إلى الخلف", "Enviar atrás", "Nach hinten",
		"背面へ", "下移一层", "뒤로"],
	"Hold this pin still": ["ثبّت هذا الدبوس", "Fijar este pin",
		"Diese Nadel feststellen", "このピンを固定", "固定此图钉",
		"이 핀 고정"],
	"Let this pin go": ["أطلق هذا الدبوس", "Soltar este pin",
		"Nadel freigeben", "このピンを解放", "解除固定", "이 핀 해제"],
	"Pin held still": ["ثُبّت الدبوس", "Pin fijado", "Nadel festgestellt",
		"ピンを固定しました", "图钉已固定", "핀을 고정했습니다"],
	"Pin released": ["أُطلق الدبوس", "Pin liberado", "Nadel freigegeben",
		"ピンを解放しました", "图钉已解除", "핀을 해제했습니다"],
	"Pin softness": ["نعومة الدبوس", "Suavidad del pin", "Weichheit der Nadel",
		"ピンの柔らかさ", "图钉柔和度", "핀의 부드러움"],
	"Smoothing": ["التنعيم", "Suavizado", "Glättung", "スムージング",
		"平滑", "부드럽게"],
	"Keep area": ["حفظ المساحة", "Conservar área", "Fläche erhalten",
		"面積を保つ", "保持面积", "면적 유지"],
	"Pin grip": ["قبضة الدبوس", "Agarre del pin", "Griff der Nadel",
		"ピンの効き", "图钉握力", "핀의 장악력"],
	"Grid": ["دقة الشبكة", "Rejilla", "Gitter", "グリッド", "网格", "격자"],
	"Back to the pose it started in": ["أعده إلى وضعه الأصلي",
		"Volver a la pose inicial", "Zurück zur Ausgangshaltung",
		"元のポーズに戻す", "回到初始姿势", "처음 자세로"],
	"Take every pin away": ["أزل كل الدبابيس", "Quitar todos los pines",
		"Alle Nadeln entfernen", "すべてのピンを外す", "移除所有图钉",
		"모든 핀 제거"],
	"Draw something first": ["ارسم شيئاً أولاً", "Dibuja algo primero",
		"Zeichne zuerst etwas", "先に何か描いてください", "请先画点什么",
		"먼저 무언가를 그리세요"],
	"Apply": ["تطبيق", "Aplicar", "Übernehmen", "適用", "应用", "적용"],
	"Go to this frame": ["اذهب إلى هذا الإطار", "Ir a este fotograma",
		"Zu diesem Bild springen", "このフレームへ移動", "跳到该帧",
		"이 프레임으로 이동"],
	"Delete frame": ["احذف الإطار", "Eliminar fotograma", "Bild löschen",
		"フレームを削除", "删除帧", "프레임 삭제"],
	"Clear this drawing": ["امسح هذا الرسم", "Borrar este dibujo",
		"Diese Zeichnung leeren", "この絵を消去", "清除该画面",
		"이 그림 지우기"],
	"Delete camera key": ["احذف مفتاح الكاميرا", "Eliminar clave de cámara",
		"Kameraschlüssel löschen", "カメラキーを削除", "删除相机关键帧",
		"카메라 키 삭제"],
	"Reframe from the canvas": ["أعد التأطير من اللوحة",
		"Reencuadrar desde el lienzo", "Auf der Leinwand neu rahmen",
		"キャンバスで再フレーミング", "在画布上重新构图",
		"캔버스에서 다시 잡기"],
	"Insert blank after current": ["وضع إطار فارغ بعد الحالي",
		"Insertar vacío después", "Leeres Bild danach einfügen",
		"現在の後に空フレームを挿入", "在当前帧后插入空白帧",
		"현재 뒤에 빈 프레임 삽입"],
	"Input event": ["حدث الإدخال", "Evento de entrada", "Eingabeereignis", "入力イベント", "输入事件", "입력 이벤트"],
	"Selection tools": ["أدوات التحديد", "Herramientas de selección", "Auswahlwerkzeuge", "選択ツール", "选择工具", "선택 도구"],
	"Lateral symmetry": ["التناظر الجانبي", "Simetría lateral", "Seitensymmetrie", "左右対称", "横向对称", "좌우 대칭"],
	"Enable symmetry": ["تفعيل التناظر", "Activar simetría", "Symmetrie aktivieren", "対称を有効化", "启用对称", "대칭 활성화"],
	"Symmetry type": ["نوع التناظر", "Tipo de simetría", "Symmetrietyp", "対称タイプ", "对称类型", "대칭 유형"],
	"Axis angle": ["زاوية المحور", "Ángulo del eje", "Achsenwinkel", "軸角度", "轴角", "축 각도"],
	"App information": ["معلومات التطبيق", "Información de la aplicación", "App-Informationen", "アプリ情報", "应用信息", "앱 정보"],
	"Icon & tools source": ["مصدر الأيقونات والأدوات", "Fuente de iconos y herramientas", "Quelle für Symbole und Werkzeuge", "アイコンとツールのソース", "图标与工具来源", "아이콘 및 도구 출처"],
	"Exit project": ["الخروج من المشروع", "Salir del proyecto", "Projekt verlassen", "プロジェクトを終了", "退出项目", "프로젝트 나가기"],
	"Done": ["تم", "Listo", "Fertig", "完了", "完成", "완료"],
	"Stop frame": ["إطار التوقف", "Fotograma final", "Stoppbild", "停止フレーム", "停止帧", "종료 프레임"],
	"Camera key": ["مفتاح الكاميرا", "Clave de cámara", "Kamera-Key", "カメラキー", "相机关键帧", "카메라 키"],
	"Animation projects only": ["لمشاريع الرسوم المتحركة فقط", "Solo proyectos de animación", "Nur für Animationsprojekte", "アニメーションプロジェクトのみ", "仅限动画项目", "애니메이션 프로젝트 전용"],
	"Add a key": ["أضف مفتاحاً", "Añadir clave", "Key setzen", "キーを追加", "添加关键帧", "키 추가"],
	"Remove the key": ["احذف المفتاح", "Quitar la clave", "Key entfernen", "キーを削除", "删除关键帧", "키 삭제"],
	"Close the timeline": ["أغلق التايم لاين", "Cerrar la línea de tiempo", "Zeitleiste schließen", "タイムラインを閉じる", "关闭时间轴", "타임라인 닫기"],
	"All bones": ["كل العظام", "Todos los huesos", "Alle Knochen", "すべてのボーン", "全部骨骼", "모든 본"],
	"Selected only": ["المحدّدة فقط", "Solo lo seleccionado", "Nur Ausgewähltes", "選択中のみ", "仅选中项", "선택한 항목만"],
	"Curves": ["المنحنيات", "Curvas", "Kurven", "カーブ", "曲线", "커브"],
	"Smooth": ["ناعم", "Suave", "Weich", "スムーズ", "平滑", "부드럽게"],
	"Linear": ["خطّي", "Lineal", "Linear", "リニア", "线性", "선형"],
	"Hold": ["ثابت", "Mantener", "Halten", "ホールド", "保持", "고정"],
	"Smart": ["ذكي", "Inteligente", "Smart", "スマート", "智能", "스마트"],
	"Rotation": ["الدوران", "Rotación", "Drehung", "回転", "旋转", "회전"],
	"Across": ["أفقياً", "Horizontal", "Waagerecht", "横", "水平", "가로"],
	"Down": ["رأسياً", "Vertical", "Senkrecht", "縦", "垂直", "세로"],
	"Scale": ["الحجم", "Escala", "Größe", "スケール", "缩放", "크기"],
	"Moving WebP": ["WebP متحرك", "WebP animado", "Bewegtes WebP", "動くWebP", "动态 WebP", "움직이는 WebP"],
	"Moving WebP, smaller": ["WebP متحرك مصغّر", "WebP animado, más pequeño", "Bewegtes WebP, kleiner", "動くWebP（小）", "较小的动态 WebP", "작은 움직이는 WebP"],
	"Full colour, far smaller than GIF": ["بألوان كاملة، وأصغر من GIF بكثير", "Color completo, mucho más pequeño que GIF", "Volle Farbe, viel kleiner als GIF", "フルカラー、GIFよりずっと小さい", "全彩，远小于 GIF", "풀컬러, GIF보다 훨씬 작음"],
	"960 wide": ["بعرض 960", "960 de ancho", "960 breit", "幅960", "宽 960", "가로 960"],
	"These scripts need a font that carries them. Put one at assets/fonts/ui.ttf.": ["هذه الحروف تحتاج خطاً يحملها. ضع واحداً في assets/fonts/ui.ttf.", "Estas escrituras necesitan una fuente que las incluya. Pon una en assets/fonts/ui.ttf.", "Diese Schriften brauchen eine Schriftart, die sie enthält. Lege eine unter assets/fonts/ui.ttf ab.", "これらの文字を含むフォントが必要です。assets/fonts/ui.ttf に置いてください。", "这些文字需要包含它们的字体，请放置于 assets/fonts/ui.ttf。", "이 문자를 담은 글꼴이 필요합니다. assets/fonts/ui.ttf 에 넣어 주세요."],
	"Import image": ["استيراد صورة", "Importar imagen", "Bild importieren", "画像を読み込む", "导入图片", "이미지 가져오기"],
	"Side by side": ["جنباً إلى جنب", "Una al lado de otra", "Nebeneinander", "横に並べる", "并排排列", "나란히 배치"],
	"Stacked": ["فوق بعضها", "Apiladas", "Untereinander", "縦に並べる", "上下排列", "위아래 배치"],
	"Between lines": ["بين الخطوط", "Entre líneas", "Zwischen Linien", "線の内側", "线条之间", "선 사이"],
	"Triangle": ["مثلث", "Triángulo", "Dreieck", "三角形", "三角形", "삼각형"],
	"Diamond": ["معيّن", "Rombo", "Raute", "ひし形", "菱形", "마름모"],
	"Star": ["نجمة", "Estrella", "Stern", "星", "星形", "별"],
	"Fill colour": ["لون الملء", "Color de relleno", "Füllfarbe", "塗りの色", "填充颜色", "채우기 색"],
	"A shape is dragged out and filled solid. Between lines needs only a tap.": ["الشكل يُسحب فيُملأ صلباً. والملء بين الخطوط يحتاج ضغطة واحدة.", "La forma se arrastra y se rellena por completo. Entre líneas basta un toque.", "Eine Form wird aufgezogen und voll gefüllt. Zwischen Linien genügt ein Tippen.", "形はドラッグして塗りつぶします。線の内側はタップだけです。", "形状拖出后整体填充；线条之间只需轻点。", "도형은 드래그해 꽉 채웁니다. 선 사이는 한 번만 탭하면 됩니다."],
	"Previous": ["السابقة", "Anterior", "Zurück", "前へ", "上一页", "이전"],
	"Next": ["التالية", "Siguiente", "Weiter", "次へ", "下一页", "다음"],
	"Drag it, then Place": ["حرّكها ثم ثبّت", "Arrástrala y luego Colocar", "Ziehen, dann Platzieren", "動かしてから配置", "拖动后再放置", "옮긴 뒤 배치"],
	"Storage": ["التخزين", "Almacenamiento", "Speicher", "ストレージ", "存储", "저장소"],
	"Projects": ["المشاريع", "Proyectos", "Projekte", "プロジェクト", "项目", "프로젝트"],
	"Saved but not open": ["محفوظ وغير مفتوح", "Guardado pero no abierto", "Gespeichert, nicht offen", "保存済み（未オープン）", "已保存但未打开", "저장됨, 열지 않음"],
	"Forget everything saved": ["انسَ كل ما هو محفوظ", "Olvidar todo lo guardado", "Alles Gespeicherte vergessen", "保存済みをすべて削除", "忘记所有已保存内容", "저장된 항목 모두 삭제"],
	"Removes every saved project from this device. Nothing else is touched.": ["يحذف كل مشروع محفوظ من هذا الجهاز. لا يمسّ شيئاً آخر.", "Elimina todos los proyectos guardados de este dispositivo. Nada más se toca.", "Entfernt jedes gespeicherte Projekt von diesem Gerät. Sonst bleibt alles unberührt.", "この端末の保存済みプロジェクトをすべて削除します。他には影響しません。", "从本设备删除所有已保存项目，不影响其他内容。", "이 기기의 저장된 프로젝트를 모두 삭제합니다. 다른 항목은 그대로입니다."],
	"Place a picture from your device": ["استورد صورة من جهازك", "Colocar una imagen de tu dispositivo", "Bild vom Gerät einfügen", "端末から画像を配置", "从设备置入图片", "기기에서 사진 넣기"],
	"Place a picture": ["وضع صورة", "Colocar imagen", "Bild einfügen", "画像を配置", "置入图片", "사진 넣기"],
	"That file could not be read": ["تعذّرت قراءة هذا الملف", "No se pudo leer ese archivo", "Diese Datei konnte nicht gelesen werden", "このファイルは読み込めませんでした", "无法读取该文件", "해당 파일을 읽을 수 없습니다"],
	"Frames per second": ["إطارات في الثانية", "Fotogramas por segundo", "Bilder pro Sekunde", "フレームレート", "每秒帧数", "초당 프레임"],
	"Length": ["المدة", "Duración", "Länge", "長さ", "时长", "길이"],
	"seconds": ["ثانية", "segundos", "Sekunden", "秒", "秒", "초"],
	"Frames are frame rate times length. Both can change later.": ["عدد الإطارات = المعدّل × المدة. وكلاهما قابل للتغيير لاحقاً.", "Los fotogramas son la tasa por la duración. Ambos se pueden cambiar después.", "Bilder ergeben sich aus Rate mal Länge. Beides lässt sich später ändern.", "フレーム数はレート×長さです。あとから変更できます。", "帧数 = 帧率 × 时长，两者稍后都可更改。", "프레임 수는 프레임레이트 × 길이이며, 나중에 바꿀 수 있습니다."],
	"Pages sit side by side, so a drawing can cross them.": ["الصفحات متجاورة، فيمكن للرسم أن يعبر بينها.", "Las páginas van una junto a otra, así un dibujo puede cruzarlas.", "Die Seiten liegen nebeneinander, sodass eine Zeichnung über sie hinweggehen kann.", "ページは横に並ぶので、絵が両ページにまたがれます。", "页面并排排列，画面可以跨页。", "페이지가 나란히 놓여 그림이 페이지를 가로지를 수 있습니다."],
	"Straighten": ["اعدل الميل", "Enderezar", "Gerade richten", "傾きを戻す", "摆正", "기울기 되돌리기"],
	"Turn with two fingers": ["أدر بإصبعين", "Gira con dos dedos", "Mit zwei Fingern drehen", "二本指で回転", "双指旋转", "두 손가락으로 회전"],
	"Settings, then New project": ["الإعدادات، ثم مشروع جديد", "Ajustes y luego Nuevo proyecto", "Einstellungen, dann Neues Projekt", "設定 → 新規プロジェクト", "设置 → 新建项目", "설정 → 새 프로젝트"],
	"800 wide — far lighter": ["بعرض 800 — أخف بكثير", "800 de ancho, mucho más ligero", "800 breit — viel leichter", "幅800、ずっと軽量", "宽800，轻得多", "가로 800 — 훨씬 가벼움"],
	"A native share sheet on Android needs a platform plugin, which cannot live inside the project itself.": ["لوحة المشاركة في أندرويد تحتاج إضافة على مستوى النظام لا يمكن أن تعيش داخل المشروع.", "La hoja de compartir de Android necesita un complemento de plataforma que no puede vivir dentro del proyecto.", "Das native Teilen-Menü unter Android braucht ein Plattform-Plugin, das nicht im Projekt selbst liegen kann.", "Androidの共有シートにはプロジェクト内には置けないプラットフォームプラグインが必要です。", "安卓原生分享面板需要平台插件，无法置于项目内部。", "안드로이드 공유 시트는 프로젝트 안에 넣을 수 없는 플랫폼 플러그인이 필요합니다."],
	"Applies to the project you have open.": ["يُطبَّق على المشروع المفتوح.", "Se aplica al proyecto abierto.", "Gilt für das geöffnete Projekt.", "開いているプロジェクトに適用されます。", "应用于当前打开的项目。", "열려 있는 프로젝트에 적용됩니다."],
	"Clear points": ["امسح النقاط", "Borrar puntos", "Punkte löschen", "点を消去", "清除点", "점 지우기"],
	"Close shape": ["أغلق الشكل", "Cerrar forma", "Form schließen", "形を閉じる", "闭合形状", "도형 닫기"],
	"Delete layer": ["حذف الطبقة", "Eliminar capa", "Ebene löschen", "レイヤーを削除", "删除图层", "레이어 삭제"],
	"Dims every layer inside it.": ["تخفّف كل الطبقات التي بداخله.", "Atenúa todas las capas que contiene.", "Dimmt alle Ebenen darin.", "中のすべてのレイヤーを薄くします。", "会使其中所有图层变淡。", "안의 모든 레이어를 흐리게 합니다."],
	"Draw around a part, then drag, turn or resize it.": ["ارسم حول جزء، ثم حرّكه أو أدره أو غيّر حجمه.", "Dibuja alrededor de una parte y luego muévela, gírala o redimensiónala.", "Umkreise einen Teil und verschiebe, drehe oder skaliere ihn.", "一部を囲んでから移動・回転・拡大縮小できます。", "圈出一部分，然后移动、旋转或缩放。", "일부를 둘러싼 뒤 이동·회전·크기 조절할 수 있습니다."],
	"Draw the curve": ["ارسم المنحنى", "Dibujar la curva", "Kurve zeichnen", "曲線を描く", "绘制曲线", "곡선 그리기"],
	"Duplicate layer": ["نسخة من الطبقة", "Duplicar capa", "Ebene duplizieren", "レイヤーを複製", "复制图层", "레이어 복제"],
	"Erase layer": ["مسح الطبقة", "Borrar capa", "Ebene leeren", "レイヤーを消去", "清除图层", "레이어 지우기"],
	"Every page, anywhere": ["كل الصفحات، في أي جهاز", "Todas las páginas, en cualquier parte", "Jede Seite, überall", "すべてのページをどこでも", "所有页面，随处可看", "모든 페이지를 어디서나"],
	"Focus on it": ["التركيز عليه", "Enfocarlo", "Darauf fokussieren", "これに集中", "专注于它", "이 항목에 집중"],
	"Fold or unfold": ["طيّ أو فتح", "Plegar o desplegar", "Ein- oder ausklappen", "折りたたむ / 展開", "折叠或展开", "접기 또는 펼치기"],
	"Folder opacity": ["شفافية المجلد", "Opacidad de la carpeta", "Ordner-Deckkraft", "フォルダーの不透明度", "文件夹不透明度", "폴더 불투명도"],
	"For games and the web": ["للألعاب والويب", "Para juegos y la web", "Für Spiele und das Web", "ゲームとウェブ向け", "用于游戏和网页", "게임과 웹용"],
	"Frames": ["عدد الإطارات", "Fotogramas", "Bilder", "フレーム数", "帧数", "프레임 수"],
	"GIF, smaller": ["GIF مصغّر", "GIF más pequeño", "GIF, kleiner", "GIF（小）", "较小的 GIF", "작은 GIF"],
	"Hide the grid": ["أخفِ الشبكة", "Ocultar la cuadrícula", "Raster ausblenden", "グリッドを隠す", "隐藏网格", "격자 숨기기"],
	"Hide the others": ["أخفِ البقية", "Ocultar los demás", "Andere ausblenden", "ほかを隠す", "隐藏其他", "나머지 숨기기"],
	"Layer opacity": ["شفافية الطبقة", "Opacidad de la capa", "Ebenen-Deckkraft", "レイヤーの不透明度", "图层不透明度", "레이어 불투명도"],
	"Layers kept": ["بطبقاته محفوظة", "Con las capas intactas", "Ebenen bleiben erhalten", "レイヤーを保持", "保留图层", "레이어 유지"],
	"Leave focus": ["إنهاء التركيز", "Salir del enfoque", "Fokus verlassen", "集中を終了", "退出专注", "집중 해제"],
	"Lock layer": ["قفل الطبقة", "Bloquear capa", "Ebene sperren", "レイヤーをロック", "锁定图层", "레이어 잠금"],
	"Lossless, transparent": ["بلا فقد، وبشفافية", "Sin pérdida, con transparencia", "Verlustfrei, transparent", "可逆圧縮・透過あり", "无损、支持透明", "무손실, 투명 지원"],
	"Merge layers": ["دمج الطبقتين", "Combinar capas", "Ebenen verbinden", "レイヤーを結合", "合并图层", "레이어 병합"],
	"Move layer": ["نقل الطبقة", "Mover capa", "Ebene verschieben", "レイヤーを移動", "移动图层", "레이어 이동"],
	"New folder": ["مجلد جديد", "Nueva carpeta", "Neuer Ordner", "新規フォルダー", "新建文件夹", "새 폴더"],
	"New layer": ["طبقة جديدة", "Nueva capa", "Neue Ebene", "新規レイヤー", "新建图层", "새 레이어"],
	"Next page": ["الصفحة التالية", "Página siguiente", "Nächste Seite", "次のページ", "下一页", "다음 페이지"],
	"Open a project first": ["افتح مشروعاً أولاً", "Abre un proyecto primero", "Öffne zuerst ein Projekt", "先にプロジェクトを開いてください", "请先打开一个项目", "먼저 프로젝트를 여세요"],
	"Open an animation project first": ["افتح مشروع رسوم متحركة أولاً", "Abre primero un proyecto de animación", "Öffne zuerst ein Animationsprojekt", "先にアニメーションプロジェクトを開いてください", "请先打开动画项目", "먼저 애니메이션 프로젝트를 여세요"],
	"Open the folder": ["افتح المجلد", "Abrir la carpeta", "Ordner öffnen", "フォルダーを開く", "打开文件夹", "폴더 열기"],
	"Out of folder": ["إخراج من المجلد", "Sacar de la carpeta", "Aus dem Ordner nehmen", "フォルダーから出す", "移出文件夹", "폴더에서 빼기"],
	"Place selection": ["تثبيت التحديد", "Colocar selección", "Auswahl absetzen", "選択を配置", "放置选区", "선택 영역 배치"],
	"Plays anywhere, 256 colours": ["يعمل في كل مكان، 256 لوناً", "Se reproduce en todas partes, 256 colores", "Läuft überall, 256 Farben", "どこでも再生、256色", "随处可播放，256 色", "어디서나 재생, 256색"],
	"Previous page": ["الصفحة السابقة", "Página anterior", "Vorherige Seite", "前のページ", "上一页", "이전 페이지"],
	"Put in a new folder": ["ضعها في مجلد جديد", "Poner en una carpeta nueva", "In einen neuen Ordner legen", "新しいフォルダーへ入れる", "放入新文件夹", "새 폴더에 넣기"],
	"Put this layer in a folder": ["ضع هذه الطبقة في مجلد", "Poner esta capa en una carpeta", "Diese Ebene in einen Ordner legen", "このレイヤーをフォルダーへ", "将此图层放入文件夹", "이 레이어를 폴더에 넣기"],
	"Remove folder": ["إزالة المجلد", "Quitar la carpeta", "Ordner entfernen", "フォルダーを削除", "移除文件夹", "폴더 제거"],
	"Remove the folder": ["أزل المجلد", "Quitar la carpeta", "Ordner entfernen", "フォルダーを削除", "移除文件夹", "폴더 제거"],
	"Show or hide": ["إظهار أو إخفاء", "Mostrar u ocultar", "Ein- oder ausblenden", "表示 / 非表示", "显示或隐藏", "표시 또는 숨김"],
	"Show or hide folder": ["إظهار أو إخفاء المجلد", "Mostrar u ocultar la carpeta", "Ordner ein- oder ausblenden", "フォルダーの表示 / 非表示", "显示或隐藏文件夹", "폴더 표시 또는 숨김"],
	"Show or hide the folder": ["إظهار أو إخفاء المجلد", "Mostrar u ocultar la carpeta", "Ordner ein- oder ausblenden", "フォルダーの表示 / 非表示", "显示或隐藏文件夹", "폴더 표시 또는 숨김"],
	"Show the grid": ["أظهر الشبكة", "Mostrar la cuadrícula", "Raster einblenden", "グリッドを表示", "显示网格", "격자 표시"],
	"Show the others": ["أظهر البقية", "Mostrar los demás", "Andere einblenden", "ほかを表示", "显示其他", "나머지 표시"],
	"Small and lossless": ["صغير وبلا فقد", "Pequeño y sin pérdida", "Klein und verlustfrei", "小さく可逆圧縮", "体积小且无损", "작고 무손실"],
	"Small, for sending": ["صغير، للإرسال", "Pequeño, para enviar", "Klein, zum Versenden", "送信向けに小さく", "体积小，便于发送", "전송용으로 작게"],
	"Sprite sheet": ["ورقة إطارات", "Hoja de sprites", "Sprite-Blatt", "スプライトシート", "精灵图", "스프라이트 시트"],
	"Stroke": ["خط", "Trazo", "Strich", "ストローク", "笔画", "획"],
	"Take a colour from the canvas": ["التقط لوناً من اللوحة", "Tomar un color del lienzo", "Farbe von der Leinwand aufnehmen", "キャンバスから色を取る", "从画布上取色", "캔버스에서 색 추출"],
	"Take out of the folder": ["أخرجها من المجلد", "Sacar de la carpeta", "Aus dem Ordner nehmen", "フォルダーから出す", "移出文件夹", "폴더에서 빼기"],
	"Tap again to delete": ["اضغط ثانية للحذف", "Toca otra vez para eliminar", "Zum Löschen erneut tippen", "もう一度タップで削除", "再次点击以删除", "삭제하려면 다시 탭"],
	"The background stays. Only what is on it can go.": ["الخلفية لا تُحذف. يُمسح محتواها فقط.", "El fondo permanece. Solo se borra lo que hay encima.", "Der Hintergrund bleibt. Nur sein Inhalt kann gehen.", "背景は残ります。消せるのは中身だけです。", "背景会保留，只能清除其内容。", "배경은 남고 그 내용만 지울 수 있습니다."],
	"The brush follows the shape you pick.": ["الفرشاة تتبع الشكل الذي تختاره.", "El pincel sigue la forma que elijas.", "Der Pinsel folgt der gewählten Form.", "ブラシは選んだ形をなぞります。", "画笔会沿着你选的形状走。", "브러시가 선택한 도형을 따라갑니다."],
	"The layers inside are kept.": ["الطبقات التي بداخله تبقى كما هي.", "Las capas de dentro se conservan.", "Die Ebenen darin bleiben erhalten.", "中のレイヤーはそのまま残ります。", "其中的图层会保留。", "안의 레이어는 그대로 유지됩니다."],
	"The timeline itself is next. These settings are what it will read.": ["التايم لاين نفسه هو التالي. وهذه الإعدادات هي ما سيقرؤه.", "La línea de tiempo viene después. Leerá estos ajustes.", "Die Zeitleiste kommt als Nächstes. Sie liest diese Einstellungen.", "次はタイムラインです。ここの設定を読み取ります。", "接下来是时间轴，它会读取这些设置。", "다음은 타임라인이며 이 설정을 읽습니다."],
	"This layer only": ["هذه الطبقة وحدها", "Solo esta capa", "Nur diese Ebene", "このレイヤーだけ", "仅此图层", "이 레이어만"],
	"Too many projects": ["عدد المشاريع بلغ الحد", "Demasiados proyectos", "Zu viele Projekte", "プロジェクトが多すぎます", "项目数量已达上限", "프로젝트가 너무 많습니다"],
	"Type a colour code": ["اكتب رمز اللون", "Escribe un código de color", "Farbcode eingeben", "カラーコードを入力", "输入颜色代码", "색상 코드 입력"],
	"What comic readers open": ["ما تفتحه قارئات القصص", "Lo que abren los lectores de cómics", "Was Comic-Reader öffnen", "コミックリーダーが開く形式", "漫画阅读器可打开", "만화 뷰어가 여는 형식"],
	"What editing software expects": ["ما تتوقّعه برامج المونتاج", "Lo que espera el software de edición", "Was Schnittprogramme erwarten", "編集ソフトが想定する形式", "剪辑软件期望的格式", "편집 소프트웨어가 기대하는 형식"],
	"With nothing marked, Copy takes the whole layer.": ["بلا تحديد، النسخ يأخذ الطبقة كاملة.", "Sin selección, Copiar toma toda la capa.", "Ohne Auswahl kopiert Kopieren die ganze Ebene.", "選択がなければレイヤー全体をコピーします。", "未选择时，复制会取整个图层。", "선택이 없으면 레이어 전체를 복사합니다."],
	"Writes a PNG and opens the folder holding it, ready to attach.": ["يكتب صورة PNG ويفتح مجلدها، جاهزة للإرسال.", "Guarda un PNG y abre su carpeta, listo para adjuntar.", "Schreibt ein PNG und öffnet dessen Ordner, bereit zum Anhängen.", "PNGを書き出し、そのフォルダーを開きます。", "导出 PNG 并打开所在文件夹，便于发送。", "PNG를 저장하고 해당 폴더를 엽니다."],
	"locked": ["مقفلة", "bloqueada", "gesperrt", "ロック", "已锁定", "잠김"],
	# --- frame-rate units and the view window ---
	"Dividing frame rate into units": ["تقسيم معدل الإطارات إلى وحدات", "División de la velocidad en unidades", "Bildrate in Einheiten teilen", "フレームレートを単位に分割", "将帧率分割为单元", "프레임 레이트를 단위로 나누기"],
	"Frame rate unit": ["وحدة معدل الإطارات", "Unidad de velocidad", "Bildraten-Einheit", "フレームレート単位", "帧率单元", "프레임 레이트 단위"],
	"Frame rate units": ["وحدات معدل الإطارات", "Unidades de velocidad", "Bildraten-Einheiten", "フレームレート単位", "帧率单元", "프레임 레이트 단위"],
	"Frames a second": ["إطارات في الثانية", "Fotogramas por segundo", "Bilder pro Sekunde", "秒あたりのフレーム数", "每秒帧数", "초당 프레임"],
	"Straight to": ["مباشرةً إلى", "Directo a", "Direkt auf", "そのまま", "直接设为", "바로 지정"],
	"Back to the scene's rate": ["عد إلى معدل المشهد", "Volver a la velocidad de la escena", "Zurück zur Szenenrate", "シーンの速度に戻す", "恢复为场景帧率", "장면 속도로 되돌리기"],
	"Remove this unit": ["احذف هذه الوحدة", "Eliminar esta unidad", "Diese Einheit entfernen", "この単位を削除", "删除此单元", "이 단위 삭제"],
	"No room for a unit here": ["لا يوجد متسع لوحدة هنا", "No hay sitio para una unidad aquí", "Hier ist kein Platz für eine Einheit", "ここには単位を置く余地がありません", "此处没有放置单元的空间", "여기에는 단위를 놓을 자리가 없습니다"],
	"Slide the unit along the band": ["اسحب الوحدة على الشريط", "Desliza la unidad por la banda", "Einheit auf dem Band verschieben", "バーに沿って単位を動かします", "沿轴滑动该单元", "띠를 따라 단위를 미세요"],
	"Going to one brings it back on screen.": ["الذهاب إلى واحدة يعيدها إلى الشاشة.", "Ir a una la trae de vuelta a la pantalla.", "Zu einer zu gehen holt sie zurück auf den Schirm.", "選ぶと画面に戻ってきます。", "前往某个单元会把它带回屏幕。", "하나를 고르면 화면으로 돌아옵니다."],
	"None yet. Tap the button to lay one down at the playhead, drag its arrows to cover the frames you mean, then tap it twice to set its rate.": ["لا توجد بعد. اضغط الزر لوضع واحدة عند رأس التشغيل، واسحب سهميها لتغطي الإطارات التي تريدها، ثم اضغط عليها مرتين لضبط معدلها.", "Ninguna todavía. Toca el botón para poner una en el cabezal, arrastra sus flechas hasta cubrir los fotogramas que quieras y tócala dos veces para fijar su velocidad.", "Noch keine. Tippe auf die Schaltfläche, um eine am Abspielkopf zu setzen, zieh ihre Pfeile über die gewünschten Bilder und tippe sie zweimal an, um die Rate zu setzen.", "まだありません。ボタンを押して再生ヘッドの位置に置き、矢印をドラッグして対象のフレームを覆い、二回タップして速度を決めます。", "尚无。点击按钮在播放头处放置一个，拖动它的箭头覆盖所需帧，然后双击设定其帧率。", "아직 없습니다. 버튼을 눌러 재생 헤드에 하나를 놓고, 화살표를 끌어 원하는 프레임을 덮은 다음 두 번 탭해 속도를 정하세요."],
	"The frames inside this unit are held at their own rate. Nothing is added and nothing is moved along — only how long each frame lasts. Slowing a unit down stretches time where it stands instead of stretching the band, so everything after it simply happens later.": ["تُعرض الإطارات داخل هذه الوحدة بمعدلها الخاص. لا يُضاف شيء ولا يتزحزح شيء — يتغيّر فقط طول بقاء كل إطار. فتبطيء الوحدة يمدّ الزمن في مكانه لا يمدّ الشريط، وكل ما بعدها يحدث متأخراً وحسب.", "Los fotogramas dentro de esta unidad se sostienen a su propia velocidad. No se añade ni se desplaza nada: solo cambia cuánto dura cada fotograma. Ralentizar una unidad estira el tiempo en su sitio en vez de estirar la banda, así que todo lo posterior simplemente ocurre más tarde.", "Die Bilder in dieser Einheit werden mit ihrer eigenen Rate gehalten. Nichts wird hinzugefügt und nichts verschoben — nur wie lange jedes Bild steht. Eine langsamere Einheit dehnt die Zeit an Ort und Stelle statt das Band, alles danach geschieht also einfach später.", "この単位の中のフレームは独自の速度で保たれます。何も追加されず、何も動きません。変わるのは各フレームの長さだけです。単位を遅くすると、バーが伸びるのではなくその場で時間が伸び、以降のすべてはただ遅れて起こります。", "该单元内的帧按它自己的帧率停留。不会增加任何东西，也不会移动任何东西——只改变每一帧停留的时长。放慢一个单元是在原地拉长时间，而不是拉长时间轴，因此其后的一切只是发生得更晚。", "이 단위 안의 프레임은 자체 속도로 유지됩니다. 아무것도 추가되지 않고 아무것도 밀리지 않으며, 각 프레임이 머무는 길이만 바뀝니다. 단위를 늦추면 띠가 늘어나는 대신 그 자리에서 시간이 늘어나므로, 그 뒤의 모든 것은 그저 더 늦게 일어납니다."],
	"Frames {0} to {1} — {2} frames at {3} a second, lasting {4} seconds": ["الإطارات {0} إلى {1} — {2} إطاراً بمعدل {3} في الثانية، فتستغرق {4} ثانية", "Fotogramas {0} a {1} — {2} fotogramas a {3} por segundo, durando {4} segundos", "Bilder {0} bis {1} — {2} Bilder mit {3} pro Sekunde, Dauer {4} Sekunden", "フレーム {0} から {1} — {2} フレームを毎秒 {3} で、{4} 秒", "第 {0} 至 {1} 帧 — {2} 帧，每秒 {3} 帧，历时 {4} 秒", "프레임 {0}부터 {1}까지 — {2} 프레임을 초당 {3}으로, {4}초"],
	"The scene itself runs at {0} a second.": ["المشهد نفسه يعمل بمعدل {0} في الثانية.", "La escena en sí va a {0} por segundo.", "Die Szene selbst läuft mit {0} pro Sekunde.", "シーン自体は毎秒 {0} で動きます。", "场景本身以每秒 {0} 帧运行。", "장면 자체는 초당 {0}으로 재생됩니다."],
	"Drag the arrows on its edges to change which frames it covers. Hold the unit and drag to slide it along the band.": ["اسحب السهمين على حافتيها لتغيير الإطارات التي تغطيها. واضغط عليها مطولاً ثم اسحب لتحريكها على الشريط.", "Arrastra las flechas de sus bordes para cambiar qué fotogramas cubre. Mantén pulsada la unidad y arrastra para deslizarla por la banda.", "Zieh die Pfeile an den Rändern, um zu ändern, welche Bilder sie umfasst. Halte die Einheit gedrückt und zieh sie, um sie zu verschieben.", "端の矢印をドラッグすると覆うフレームが変わります。単位を長押ししてドラッグすると位置を動かせます。", "拖动两端的箭头可改变它覆盖的帧。长按该单元并拖动可沿轴移动它。", "가장자리의 화살표를 끌면 덮는 프레임이 바뀝니다. 단위를 길게 누른 뒤 끌면 위치를 옮길 수 있습니다."],
	"Show the band from this frame": ["ابدأ عرض الشريط من هذا الإطار", "Mostrar la banda desde este fotograma", "Band ab diesem Bild zeigen", "このフレームからバーを表示", "从此帧开始显示时间轴", "이 프레임부터 띠 보이기"],
	"Show the band up to this frame — 0 for no end": ["اعرض الشريط حتى هذا الإطار — صفر لبلا نهاية", "Mostrar la banda hasta este fotograma — 0 para sin fin", "Band bis zu diesem Bild zeigen — 0 für kein Ende", "このフレームまでバーを表示 — 0 で終わりなし", "显示时间轴到此帧 — 填 0 表示没有尽头", "이 프레임까지 띠 보이기 — 0이면 끝 없음"],
	"Show the band from frame": ["ابدأ عرض الشريط من الإطار", "Mostrar la banda desde el fotograma", "Band ab Bild zeigen", "バーを表示し始めるフレーム", "时间轴从第几帧开始显示", "띠를 보이기 시작할 프레임"],
	"Show the band up to frame": ["اعرض الشريط حتى الإطار", "Mostrar la banda hasta el fotograma", "Band bis Bild zeigen", "バーを表示し終えるフレーム", "时间轴显示到第几帧", "띠를 보일 마지막 프레임"],
	"Where the band begins. This changes what you are looking at, not what plays — the frames before it are still there and still in the film.": ["من أين يبدأ الشريط. هذا يغيّر ما تنظر إليه لا ما يُعرض — فالإطارات التي قبله باقية وما زالت في الفيلم.", "Donde empieza la banda. Cambia lo que miras, no lo que se reproduce: los fotogramas anteriores siguen ahí y siguen en la película.", "Wo das Band beginnt. Das ändert, was du siehst, nicht was abgespielt wird — die Bilder davor sind weiter da und weiter im Film.", "バーの始まり。これは見ている範囲を変えるだけで、再生される内容は変わりません。手前のフレームはそのまま作品の中にあります。", "时间轴从哪里开始。这改变的是你看到的范围，而不是播放的内容——之前的帧仍在，也仍在影片里。", "띠가 시작되는 곳입니다. 보고 있는 범위만 바뀔 뿐 재생되는 내용은 그대로이며, 앞선 프레임은 여전히 작품 안에 있습니다."],
	"Where the band stops. Nought means it never stops: the band runs on forward for as long as you keep dragging it, past the last drawing and out into empty frames waiting to be used.": ["أين يتوقف الشريط. والصفر يعني أنه لا يتوقف: يمضي الشريط إلى الأمام ما دمت تسحبه، متجاوزاً آخر رسم إلى إطارات فارغة تنتظر الاستعمال.", "Donde se detiene la banda. Cero significa que no se detiene: la banda sigue hacia delante mientras la arrastres, más allá del último dibujo, hacia fotogramas vacíos a la espera.", "Wo das Band endet. Null heißt: es endet nie — das Band läuft weiter, solange du ziehst, über die letzte Zeichnung hinaus in leere Bilder, die auf Arbeit warten.", "バーが止まる場所。0 なら止まりません。引きつづける限り前へ進み、最後の絵を越えて、これから使う空のフレームへ入っていきます。", "时间轴在哪里停止。填 0 表示不停止：只要你继续拖动，它就一直向前，越过最后一张画，进入等待使用的空帧。", "띠가 멈추는 곳입니다. 0은 멈추지 않는다는 뜻으로, 끄는 동안 계속 앞으로 나아가 마지막 그림을 지나 빈 프레임까지 이어집니다."],
	"The playhead": ["رأس التشغيل", "El cabezal", "Der Abspielkopf", "再生ヘッド", "播放头", "재생 헤드"],
	"No end": ["بلا نهاية", "Sin fin", "Kein Ende", "終わりなし", "没有尽头", "끝 없음"],
	"The last drawing": ["آخر رسم", "El último dibujo", "Die letzte Zeichnung", "最後の絵", "最后一张画", "마지막 그림"],
	"OK": ["تم", "OK", "OK", "OK", "确定", "확인"],
	"Which frames": ["أي الإطارات", "Qué fotogramas", "Welche Bilder", "対象のフレーム", "哪些帧", "어떤 프레임"],
	"Begin at the playhead": ["ابدأ عند رأس التشغيل", "Empezar en el cabezal", "Am Abspielkopf beginnen", "再生ヘッドから始める", "从播放头开始", "재생 헤드에서 시작"],
	"End at the playhead": ["انتهِ عند رأس التشغيل", "Terminar en el cabezal", "Am Abspielkopf enden", "再生ヘッドで終える", "到播放头结束", "재생 헤드에서 끝내기"],
	"A unit can never be pushed onto its neighbour: both ends stop where the next unit begins.": ["لا يمكن دفع وحدة فوق جارتها: يقف طرفاها حيث تبدأ الوحدة التالية.", "Una unidad nunca puede empujarse sobre su vecina: ambos extremos se detienen donde empieza la siguiente.", "Eine Einheit lässt sich nie über ihre Nachbarin schieben: beide Enden halten dort, wo die nächste beginnt.", "単位を隣の単位に重ねることはできません。両端は次の単位が始まるところで止まります。", "一个单元永远无法推到相邻单元之上：两端都会在下一个单元开始处停住。", "단위는 이웃 위로 밀 수 없습니다. 양 끝은 다음 단위가 시작되는 곳에서 멈춥니다."],
	"The frame this end of the unit sits on. Out of reach numbers are pulled back to whatever the neighbouring unit leaves free.": ["الإطار الذي يقف عليه هذا الطرف من الوحدة. والأرقام البعيدة تُردّ إلى ما تتركه الوحدة المجاورة حراً.", "El fotograma en el que se apoya este extremo de la unidad. Los números fuera de alcance se recogen hasta donde la unidad vecina deja libre.", "Das Bild, auf dem dieses Ende der Einheit sitzt. Unerreichbare Zahlen werden auf das zurückgeholt, was die Nachbareinheit frei lässt.", "この単位の端が置かれるフレームです。届かない数値は隣の単位が空けている範囲まで戻されます。", "该单元这一端所在的帧。超出范围的数字会被收回到相邻单元留出的空位。", "이 단위의 끝이 놓이는 프레임입니다. 닿지 않는 숫자는 이웃 단위가 비워 둔 자리까지 되돌아옵니다."],
	"Shape of the iris": ["شكل الحدقة", "Forma del diafragma", "Form der Blende", "絞りの形", "光圈形状", "조리개 모양"],
	"Round": ["دائرية", "Redondo", "Rund", "円形", "圆形", "원형"],
	"Six blades": ["ست شفرات", "Seis palas", "Sechs Lamellen", "六枚羽根", "六片光圈叶", "여섯 날"],
	"Seven blades": ["سبع شفرات", "Siete palas", "Sieben Lamellen", "七枚羽根", "七片光圈叶", "일곱 날"],
	"Nine blades": ["تسع شفرات", "Nueve palas", "Neun Lamellen", "九枚羽根", "九片光圈叶", "아홉 날"],
	"Fewer blades give a more angular highlight. Six is what most lenses do; round is a lens wide open.": ["كلما قلّت الشفرات صار وميض الخلفية أكثر زواية. والست هي ما تفعله أغلب العدسات، والدائرية عدسة مفتوحة على آخرها.", "Menos palas dan un destello más angular. Seis es lo que hacen casi todos los objetivos; redondo es un objetivo abierto del todo.", "Weniger Lamellen ergeben ein kantigeres Glanzlicht. Sechs ist, was die meisten Objektive tun; rund ist ein ganz geöffnetes Objektiv.", "羽根が少ないほど玉ボケは角ばります。六枚が多くのレンズの形で、円形は開放のレンズです。", "叶片越少，光斑越有棱角。六片是大多数镜头的形状；圆形则是全开的镜头。", "날이 적을수록 빛망울이 더 각지게 나옵니다. 여섯이 대부분 렌즈의 모양이고, 원형은 활짝 열린 렌즈입니다."],
	"Listening to the sound…": ["يُنصت إلى الصوت…", "Escuchando el sonido…", "Der Ton wird abgehört…", "音を聞いています…", "正在聆听声音…", "소리를 듣는 중…"],
	"Listening": ["يُنصت", "Escuchando", "Wird abgehört", "聞いています", "正在聆听", "듣는 중"],
	"Every file": ["كل الملفات", "Todos los archivos", "Alle Dateien", "すべてのファイル", "所有文件", "모든 파일"],
	"That is not a WAV file. Convert the sound to WAV and try again.": ["هذا ليس ملف WAV. حوّل الصوت إلى WAV وأعد المحاولة.", "Eso no es un archivo WAV. Convierte el sonido a WAV e inténtalo de nuevo.", "Das ist keine WAV-Datei. Wandle den Ton in WAV um und versuch es erneut.", "これは WAV ファイルではありません。音を WAV に変換してからもう一度お試しください。", "这不是 WAV 文件。请把声音转换为 WAV 后重试。", "WAV 파일이 아닙니다. 소리를 WAV로 변환한 뒤 다시 시도하세요."],
	"This WAV is compressed. Save it again as plain PCM WAV.": ["ملف WAV هذا مضغوط. احفظه مرة أخرى كـ WAV عادي غير مضغوط.", "Este WAV está comprimido. Vuelve a guardarlo como WAV PCM sin comprimir.", "Diese WAV-Datei ist komprimiert. Speichere sie erneut als reines PCM-WAV.", "この WAV は圧縮されています。無圧縮の PCM WAV として保存し直してください。", "此 WAV 已压缩。请重新保存为未压缩的 PCM WAV。", "이 WAV는 압축되어 있습니다. 무압축 PCM WAV로 다시 저장하세요."],
	"This WAV is stored in a way the app cannot read. Save it as 16-bit WAV.": ["ملف WAV هذا مخزَّن بطريقة لا يقرؤها التطبيق. احفظه بصيغة WAV ١٦ بت.", "Este WAV está guardado de una forma que la app no puede leer. Guárdalo como WAV de 16 bits.", "Diese WAV-Datei liegt in einer Form vor, die die App nicht lesen kann. Speichere sie als 16-Bit-WAV.", "この WAV はアプリが読めない形式で保存されています。16 ビット WAV として保存してください。", "此 WAV 的存储方式应用无法读取。请保存为 16 位 WAV。", "이 WAV는 앱이 읽을 수 없는 방식으로 저장되어 있습니다. 16비트 WAV로 저장하세요."],
	"That sound file is too long.": ["ملف الصوت هذا أطول من اللازم.", "Ese archivo de sonido es demasiado largo.", "Diese Tondatei ist zu lang.", "この音声ファイルは長すぎます。", "这个声音文件太长了。", "이 소리 파일은 너무 깁니다."],
	"That file could not be opened. It may be somewhere the app is not allowed to read.": ["تعذّر فتح هذا الملف. قد يكون في مكان لا يُسمح للتطبيق بالقراءة منه.", "No se pudo abrir ese archivo. Puede estar en un lugar del que la app no tiene permiso para leer.", "Diese Datei ließ sich nicht öffnen. Sie liegt vielleicht dort, wo die App nicht lesen darf.", "このファイルを開けませんでした。アプリに読み取りが許可されていない場所にあるかもしれません。", "无法打开该文件。它可能位于应用无权读取的位置。", "이 파일을 열 수 없습니다. 앱이 읽을 권한이 없는 위치에 있을 수 있습니다."],
	"Remove the bones": ["أزل العظام", "Quitar los huesos", "Knochen entfernen", "ボーンを外す", "移除骨骼", "뼈 제거"],
	"Tap again to remove": ["اضغط ثانية للإزالة", "Toca otra vez para quitar", "Zum Entfernen nochmal tippen", "もう一度タップで削除", "再次点击以移除", "한 번 더 누르면 제거"],
	"Bones removed — the drawing is yours again": ["أُزيلت العظام — عادت الرسمة إليك", "Huesos quitados — el dibujo vuelve a ser tuyo", "Knochen entfernt — die Zeichnung gehört wieder dir", "ボーンを外しました。絵はまたあなたのものです", "已移除骨骼 — 这张画又归你了", "뼈를 제거했습니다 — 그림은 다시 당신 것입니다"],
	"Retire layer": ["إنهاء طبقة", "Retirar capa", "Ebene ausmustern", "レイヤーを終了", "结束图层", "레이어 종료"],
	"Rendering {0} frames…": ["يُعالج {0} إطاراً…", "Procesando {0} fotogramas…", "{0} Bilder werden erzeugt…", "{0} フレームを処理しています…", "正在处理 {0} 帧…", "{0} 프레임을 처리하는 중…"],
	"{0} frames  ·  {1} seconds": ["{0} إطاراً  ·  {1} ثانية", "{0} fotogramas  ·  {1} segundos", "{0} Bilder  ·  {1} Sekunden", "{0} フレーム  ·  {1} 秒", "{0} 帧  ·  {1} 秒", "{0} 프레임  ·  {1}초"],
	"Straight to your files, the same way as last time. Choose another below to change it.": ["مباشرةً إلى ملفاتك، بالطريقة نفسها كالمرة السابقة. اختر غيرها أدناه لتغييرها.", "Directo a tus archivos, igual que la última vez. Elige otro abajo para cambiarlo.", "Direkt in deine Dateien, so wie beim letzten Mal. Unten ein anderes wählen, um das zu ändern.", "前回と同じ形式で、そのままファイルへ。変更するには下から選んでください。", "直接保存到你的文件，与上次相同。要更改请在下方选择。", "지난번과 같은 방식으로 파일에 바로 저장합니다. 바꾸려면 아래에서 고르세요."],
	"For video, export the PNG sequence and bring it into any editor — that is what they expect to be given.": ["للفيديو، صدّر تسلسل PNG وأدخله في أي برنامج مونتاج — فهو ما تتوقّع أن يُسلَّم إليها.", "Para vídeo, exporta la secuencia PNG y llévala a cualquier editor: es lo que esperan recibir.", "Für Video exportiere die PNG-Sequenz und zieh sie in einen Schnittplatz — das ist, was die erwarten.", "動画にするには PNG 連番を書き出して編集ソフトに読み込ませてください。編集ソフトが求めているのはこれです。", "如需视频，请导出 PNG 序列并导入任意剪辑软件——那正是它们期望接收的格式。", "영상으로 만들려면 PNG 시퀀스를 내보내 편집 프로그램에 넣으세요. 편집 프로그램이 기대하는 형식입니다."],
	"Every frame as a comic": ["كل إطار كصفحة قصة", "Cada fotograma como cómic", "Jedes Bild als Comicseite", "各フレームを漫画のページとして", "每一帧作为漫画页", "각 프레임을 만화 페이지로"],
	"Every frame, anywhere": ["كل إطار، في أي جهاز", "Cada fotograma, en cualquier sitio", "Jedes Bild, überall", "各フレームを、どの端末でも", "每一帧，任何设备", "각 프레임을, 어디서나"],
	"This frame only, transparent": ["هذا الإطار فقط، بشفافية", "Solo este fotograma, transparente", "Nur dieses Bild, transparent", "このフレームのみ、透明背景で", "仅此帧，带透明", "이 프레임만, 투명 배경"],
	"PNG frames": ["إطارات PNG", "Fotogramas PNG", "PNG-Bilder", "PNG 連番", "PNG 帧序列", "PNG 프레임"],
	"Each page": ["كل صفحة", "Cada página", "Jede Seite", "各ページ", "每一页", "각 페이지"],

	# --- transfer of the decree, and the clipboard it leans on ---
	"Transfer of the decree": ["نقل المرسوم", "Transferir el dibujo", "Zeichnung übertragen", "描き上げたものを移す", "转移画稿", "그림 옮기기"],
	"Cut": ["قص", "Cortar", "Ausschneiden", "切り取り", "剪切", "잘라내기"],
	"Paste as new layer": ["لصق كطبقة جديدة", "Pegar como capa nueva", "Als neue Ebene einfügen", "新しいレイヤーとして貼り付け", "粘贴为新图层", "새 레이어로 붙여넣기"],
	"Select all": ["تحديد الكل", "Seleccionar todo", "Alles auswählen", "すべて選択", "全选", "모두 선택"],
	"Choose a project": ["اختر مشروعاً", "Elegir un proyecto", "Projekt wählen", "プロジェクトを選ぶ", "选择项目", "프로젝트 선택"],
	"Which project?": ["إلى أي مشروع؟", "¿A qué proyecto?", "In welches Projekt?", "どのプロジェクトへ？", "转移到哪个项目？", "어느 프로젝트로?"],
	"How should it land?": ["كيف تصل؟", "¿Cómo debe llegar?", "Wie soll es ankommen?", "どのように置きますか？", "要如何落下？", "어떻게 놓을까요?"],
	"One layer": ["طبقة واحدة", "Una capa", "Eine Ebene", "一枚のレイヤー", "单个图层", "한 레이어"],
	"Several layers": ["عدة طبقات", "Varias capas", "Mehrere Ebenen", "複数のレイヤー", "多个图层", "여러 레이어"],
	"empty": ["فارغة", "vacía", "leer", "空", "空", "비어 있음"],
	"hidden": ["مخفية", "oculta", "ausgeblendet", "非表示", "已隐藏", "숨김"],
	"Nothing to transfer": ["لا شيء لنقله", "No hay nada que transferir", "Nichts zu übertragen", "移すものがありません", "没有可转移的内容", "옮길 것이 없습니다"],
	"Those layers are empty": ["تلك الطبقات فارغة", "Esas capas están vacías", "Diese Ebenen sind leer", "それらのレイヤーは空です", "那些图层是空的", "그 레이어들은 비어 있습니다"],
	"That project is full of layers": ["ذلك المشروع بلغ حدّ الطبقات", "Ese proyecto ya no admite más capas", "Dieses Projekt hat keine Ebenen mehr frei", "そのプロジェクトはレイヤーがいっぱいです", "该项目的图层已满", "그 프로젝트는 레이어가 가득 찼습니다"],
	"Transferred": ["منقول", "Transferido", "Übertragen", "移したもの", "已转移", "옮긴 것"],
	"No room for another layer": ["لا مكان لطبقة أخرى", "No hay sitio para otra capa", "Kein Platz für eine weitere Ebene", "もうレイヤーを増やせません", "没有空间再加图层", "레이어를 더 넣을 자리가 없습니다"],
	"Moved into {0}": ["نُقلت إلى {0}", "Movido a {0}", "Nach {0} übertragen", "{0} へ移しました", "已移入 {0}", "{0} 으로 옮겼습니다"],
	"{0} layers moved into {1}": ["نُقلت {0} طبقات إلى {1}", "{0} capas movidas a {1}", "{0} Ebenen nach {1} übertragen", "{0} 枚のレイヤーを {1} へ移しました", "已将 {0} 个图层移入 {1}", "{0}개의 레이어를 {1} 으로 옮겼습니다"],
	"{0} would not fit": ["{0} لم تتّسع", "{0} no cupieron", "{0} passten nicht", "{0} 枚は入りませんでした", "{0} 个未能放下", "{0}개는 들어가지 않았습니다"],
	"{0} layer chosen": ["طبقة واحدة مختارة", "{0} capa elegida", "{0} Ebene gewählt", "{0} 枚を選択", "已选 {0} 个图层", "{0}개 레이어 선택됨"],
	"{0} layers chosen": ["{0} طبقات مختارة", "{0} capas elegidas", "{0} Ebenen gewählt", "{0} 枚を選択", "已选 {0} 个图层", "{0}개 레이어 선택됨"],
	"{0} layer is ready to go": ["طبقة واحدة جاهزة للانتقال", "{0} capa lista para ir", "{0} Ebene ist bereit", "{0} 枚の準備ができました", "{0} 个图层已就绪", "{0}개 레이어가 준비되었습니다"],
	"{0} layers are ready to go": ["{0} طبقات جاهزة للانتقال", "{0} capas listas para ir", "{0} Ebenen sind bereit", "{0} 枚の準備ができました", "{0} 个图层已就绪", "{0}개 레이어가 준비되었습니다"],
	"Going into {0}": ["ستذهب إلى {0}", "Irá a {0}", "Geht nach {0}", "{0} へ向かいます", "将进入 {0}", "{0} 으로 갑니다"],
	"Choose what is going. The drawing stays here — a transfer takes a copy.": ["اختر ما سينتقل. الرسمة تبقى هنا — النقل يأخذ نسخة.", "Elige qué se va. El dibujo se queda aquí: transferir toma una copia.", "Wähle, was mitgeht. Die Zeichnung bleibt hier — übertragen nimmt eine Kopie.", "移すものを選んでください。絵はここに残ります。移すのは複製です。", "选择要转移的内容。画稿留在这里——转移取的是副本。", "무엇을 옮길지 고르세요. 그림은 여기 남습니다 — 옮기기는 복사본을 가져갑니다."],
	"There is nothing on this page yet.": ["لا شيء في هذه الصفحة بعد.", "Todavía no hay nada en esta página.", "Auf dieser Seite ist noch nichts.", "このページにはまだ何もありません。", "这一页上还什么都没有。", "이 페이지에는 아직 아무것도 없습니다."],
	"There is nowhere to send it yet. Make an animation or a comic first.": ["لا مكان لإرساله بعد. أنشئ مشروع رسوم متحركة أو قصة مصورة أولاً.", "Aún no hay adónde enviarlo. Crea primero una animación o un cómic.", "Es gibt noch kein Ziel. Leg zuerst eine Animation oder einen Comic an.", "送り先がまだありません。先にアニメーションかコミックを作ってください。", "还没有可以送去的地方。请先新建一个动画或漫画项目。", "아직 보낼 곳이 없습니다. 먼저 애니메이션이나 만화를 만드세요."],
	"Flattened into a single layer, exactly as it looks now.": ["تُدمج في طبقة واحدة، تماماً كما تبدو الآن.", "Aplanado en una sola capa, exactamente como se ve ahora.", "Auf eine einzige Ebene reduziert, genau wie es jetzt aussieht.", "いま見えているとおりに、一枚のレイヤーへまとめます。", "合并为单个图层，与现在看到的完全一样。", "지금 보이는 그대로, 하나의 레이어로 합칩니다."],
	"Each layer arrives as its own layer, in the order it was drawn in.": ["كل طبقة تصل كطبقة مستقلة، بالترتيب الذي رُسمت به.", "Cada capa llega como su propia capa, en el orden en que se dibujó.", "Jede Ebene kommt als eigene Ebene an, in der Reihenfolge, in der sie gezeichnet wurde.", "各レイヤーがそれぞれのレイヤーとして、描いた順のまま届きます。", "每个图层各自成为一个图层，保持绘制时的顺序。", "각 레이어가 그린 순서 그대로 자기 레이어로 도착합니다."],
	"With nothing marked, Copy and Cut take the whole layer.": ["بلا تحديد، النسخ والقص يأخذان الطبقة كاملة.", "Sin nada marcado, Copiar y Cortar toman la capa entera.", "Ohne Markierung nehmen Kopieren und Ausschneiden die ganze Ebene.", "何も選んでいなければ、コピーと切り取りはレイヤー全体を取ります。", "没有选区时，复制和剪切会取走整个图层。", "선택이 없으면 복사와 잘라내기는 레이어 전체를 가져갑니다."],
	"Cut, paste and everything below are one step of undo each.": ["القص واللصق وكل ما تحته: كل منها خطوة تراجع واحدة.", "Cortar, pegar y todo lo de abajo son un paso de deshacer cada uno.", "Ausschneiden, Einfügen und alles darunter sind je ein Schritt zum Rückgängigmachen.", "切り取りも貼り付けも、この下のものもすべて、元に戻すの一手で戻ります。", "剪切、粘贴以及下方的一切，各自都只是一步撤销。", "잘라내기와 붙여넣기, 그리고 아래의 모든 것은 각각 한 번의 실행 취소입니다."],

	# --- placing a transferred drawing, and running out of room ---
	"Place it, then tap outside to fix it": ["ضعها، ثم اضغط خارجها لتثبيتها", "Colócalo y toca fuera para fijarlo", "Platziere es und tippe daneben, um es festzusetzen", "置きたい場所へ動かし、外側をタップして決めます", "摆好位置，然后点击外部固定", "원하는 자리에 놓고 바깥을 눌러 고정하세요"],
	"Transfer cancelled": ["أُلغي النقل", "Transferencia cancelada", "Übertragung abgebrochen", "移動を取り消しました", "已取消转移", "옮기기를 취소했습니다"],
	"That drawing is too large for this device to carry": ["تلك الرسمة أكبر من أن يحملها هذا الجهاز", "Ese dibujo es demasiado grande para este dispositivo", "Diese Zeichnung ist zu groß für dieses Gerät", "この端末で扱うには絵が大きすぎます", "这张画对本设备来说太大了", "이 기기가 감당하기에는 그림이 너무 큽니다"],
	"{0} frames left out — not enough memory": ["حُذف {0} إطاراً — الذاكرة لا تكفي", "{0} fotogramas omitidos: memoria insuficiente", "{0} Bilder ausgelassen — zu wenig Speicher", "メモリが足りず {0} フレームを省きました", "内存不足，已略去 {0} 帧", "메모리가 부족하여 {0}개 프레임을 제외했습니다"],
	"tap again": ["اضغط ثانية", "toca otra vez", "erneut tippen", "もう一度タップ", "再次点击", "다시 탭"],
}
