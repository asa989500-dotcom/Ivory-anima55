# Stage 148 — الجولة الثانية من إصلاح أخطاء المحرّك

## ١. `layer_arrangement.gd` — الأسطر 88 و114 و118

```gdscript
var g: owner_.Group = owner_.group_by_id(id)
var rebuilt: Array[owner_.Layer] = []
```

`owner_` معامل (parameter)، والمعامل لا يصلح نوعًا في GDScript.
الأنواع تُحلّ وقت التحليل، والمعامل لا وجود له إلا وقت التشغيل.
صارت `LayerStack.Group` و`LayerStack.Layer` و`Array[LayerStack.Layer]`
— نفس الأصناف الداخلية بعينها، مكتوبة من صنفها لا من متغيّر.

## ٢. `puppet_warp_pins.gd` و`puppet_warp_draw.gd` و`puppet_warp_build.gd`

نفس الخطأ بوجه آخر: `host.Pin` نوعًا، وفي `as host.Pin` كذلك.
استُبدلت كلها بـ `PuppetWarp.Pin` (تسعة مواضع، منها ثلاثة لم يكن
المحرّك قد وصل إلى الإبلاغ عنها بعد لأنه توقّف عند الأولى).

لاحظ أن `host.GOLD` و`host.MIN_CELLS` و`host.Fit.RIGID` وأمثالها
سليمة ولم تُمس: تلك قيم لا أنواع، والوصول إلى ثابت عبر نسخة مسموح.

## ٣. `ui/bspline_room.gd` — ثمانية أسطر

`BsplineRoomDraw` والاسم الحقيقي `BSplineRoomDraw` بسين كبيرة.
خطأ حروف لا أكثر، لكنه يُسقط `_draw` الغرفة كلها.

## ٤. `ui/timeline_pose_frames.gd` — السطر 20

```gdscript
static func duplicate_pose_forward(host: TimelinePoseFrames) -> bool:
```

الدالة تقرأ `host.stack` و`host.player` و`host._carry_pose` و`host.rebuild`
— وكلها أعضاء `TimelinePanel` لا `TimelinePoseFrames`. النوع كُتب
باسم الصنف نفسه سهوًا، فصار المُنادي `TimelinePanel.self` مرفوضًا.
صار `host: TimelinePanel`.

## ٥. `tests/test_character360_rig.gd` — السطر 19

`Native.character360_rig()` نوعه `Object`، فالاستدعاء عليه ديناميكي
ولا نوع له يُستنتج، و`var pin := ...` لا تجد ما تستنتجه. كُتبت
`var pin: int` و`var r: Object` صراحةً.

## ٦. عن رسائل المكتبات في أعلى السجلّ

```
Can't open dynamic library: .../bin/libivory.android...so
Can't open dynamic library: .../addons/gde_gozen/bin/libgozen...so
```

هذه ليست أخطاءً في الكود: المشروع لا يحوي مجلّد `bin/` مبنيًّا، و
`ivory.gdextension` مصمَّم ليعمل بدونه — يسجّل المحرّك السطر ويمضي،
و`scripts/native.gd` يجد الأصناف غائبة فيستعمل بديل GDScript.
البديل الذي أضفته في الجولة السابقة لـ Character 360 من هذا الباب.

## الفحص بعد الإصلاح

مسحٌ آليّ على كل ملفات `scripts/` و`tests/` و`tools/` (١٠٠ صنف):

- لا معامل مستعملًا نوعًا: **صفر**
- لا مُعرّف مجهول (كل `CamelCase.` إمّا صنف في المشروع أو صنف محرّك): **صفر**
- لا `? :`، لا مسافات بدل Tab، الأقواس متوازنة، لا اسم صنف مكرّر،
  لا دالة مكرّرة في ملف: **صفر**
- فحص تقاطعي: كل `Helper.func(self, ...)` نوع أول معاملها يطابق
  صنف المُنادي أو أبًا له: **صفر تعارض**
