# Stage 147 — إصلاح أخطاء المحرّك (Character 360 High Rig)

## سبب الأخطاء الأربعة كلها: خطأ واحد

الأخطاء التي ظهرت لك:

```
main.gd:826   Could not resolve external class member "player".
main.gd:1627  Could not resolve external class member "setup".
canvas_view.gd:58     Could not parse global class "AnimPlayer"
ui/timeline_panel.gd:163  Could not parse global class "AnimPlayer"
```

كلّها نتيجة واحدة، لا أربع مشاكل. الملف `scripts/anim_player.gd`
فشل في التحليل (parse)، فسقط معه كل ملف يستعمل الصنف `AnimPlayer`:
`view.player` و`timeline.setup(...)` لم يعد لهما نوع معروف.

سطراه 541–542 كانا مكتوبين بمُعامل ثلاثي على طريقة C:

```gdscript
var back_pose: Dictionary = clip.length > 0 and prev >= 0 ? ... : {}
```

**GDScript لا يملك `? :` إطلاقًا.** صيغته `a if cond else b`.
هذا خطأ نحوي قاتل، لا خطأ منطق.

## ما جرى إصلاحه

1. **`scripts/anim_player.gd`** — كُتب السطران شرطًا صريحًا، وأُضيف
   معهما ما كان السطر المختصر يفتقده: فحص `l.poses != null`، واحترام
   `onion_back` / `onion_forward` فلا يُرسم شبح في اتجاه أطفأه المستخدم.
   وأُزيلت كل `:=` من الملف إلى أنواع صريحة.

2. **`scripts/character360_rig_fallback.gd` (جديد)** — بديل GDScript
   خالص لمازج الأقراص. المشروع لا يحوي أي `bin/` مبنيّ، أي أن
   `Native.character360_rig()` كان يُرجع `null` على جهازك، فيعود
   المتحكّم `null`، فلا يعمل دوران Character 360 أصلًا حتى بعد إصلاح
   الخطأ النحوي. الآن يعمل بالبناء الأصلي أو بدونه بنفس النتيجة.

3. **`native/ivory/src/ivory_character360_rig.cpp`** — تصحيح رياضي في
   `disc_weights`: الوزن على الجهة الخلفية كان يُقاس من `right` بدل نقطة
   الالتفاف، فيضيع المدى كلّه بين آخر قرص وأوّله. برِج من أربعة أقراص،
   زاوية 315° كانت تمزج «الخلف + اليسار» بدل «اليسار + الأمام». صار
   المزج متناظرًا، ومطابقًا تمامًا لبديل GDScript أعلاه.

4. **ذاكرة المتحكّمات** — كانت مخزّنة بمعرّف الطبقة وحده، فتعديل الأقراص
   يترك الهيكل القديم قائمًا حتى إعادة ربط المشروع. صارت مخزّنة ببصمة
   الأقراص أيضًا، فالتعديل يبني من جديد وحده.

## تحقّق

فحص نحوي شامل على كل ملفات `scripts/` بعد الإصلاح: صفر مشاكل
(لا `? :`، لا مسافات بدل Tab، الأقواس متوازنة في كل ملف).
