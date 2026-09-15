# إضافة DragonBones إلى IVORY بأمان

## النتيجة المختصرة

يحتوي IVORY أصلًا على نظام عظام متكامل (`BoneRig` و`BoneSolver` و`RigSkin` و`IvoryRigCore`) مع دعم FK/IK، السلاسل، القيود، إصلاح الحجم، التشويه الشبكي، الحفظ، التراجع، والتحريك على الخط الزمني. لذلك لا ينبغي استبدال هذا المسار بإضافة DragonBones.

الطريقة الآمنة هي تشغيل DragonBones كمسار اختياري ومعزول:

```text
DragonBones assets (.ske.json/.tex.json/.png)
                │
                ▼
      Optional DragonBones bridge
                │
      ┌─────────┴─────────┐
      ▼                   ▼
Preview/playback       Explicit import
(DragonBones node)     (converted IVORY rig)
      │                   │
      └────── disabled by default ──────┘

IVORY default path: LayerStack → BoneRig → RigSkin → Canvas
```

## لماذا لا نربطه مباشرة؟

إضافة Godot-DragonBones الشائعة هي GDExtension مستقلة لـ Godot 4.2+، وتوفر `DragonBonesFactory` و`DragonBonesArmatureView`. كما أن كائن `DragonBonesArmature` يُنشأ ويدار من خلال `DragonBonesArmatureView` ولا ينبغي تحريره يدويًا. هذا يختلف عن نموذج IVORY الذي يعتبر العظم جزءًا من الطبقة، ويحفظه داخل `project.json`، ويبدّل بين الرسم الأصلي والجلد الشبكي عبر `shed_skin()`.

الربط المباشر قد يؤدي إلى:

1. طبقة تختفي لأن سطحها أخفي ولم تُستعد حالته.
2. فقدان التراجع أو جعل وضعية العرض تعدّل الرسم الأصلي.
3. اختلاف نظام الإحداثيات والوحدات وزوايا Godot.
4. تضاعف الرسم إذا رُسم DragonBones و`RigSkin` معًا.
5. تعارض في دورة الحياة، خصوصًا عند تحرير `DragonBonesArmature` يدويًا.

## خطة التنفيذ الموصى بها

### المرحلة 0 — لا تغيير في المسار الافتراضي

- ضع الإضافة داخل `addons/godot_dragon_bones...` فقط.
- لا تعدّل `LayerStack` أو `BoneRig` أو `RigSkin` في هذه المرحلة.
- اجعل الإضافة معطلة افتراضيًا.
- أضف إعدادًا مثل:

```ini
[dragonbones]
enabled=false
preview_only=true
```

- لا يُحمّل أي مشهد DragonBones إذا كان الإعداد `enabled=false`.

### المرحلة 1 — معاينة منفصلة

أضف غرفة أو لوحة معاينة مستقلة لا تغيّر الطبقة الحالية:

```gdscript
# DragonBonesPreviewHost.gd — تصور واجهة العزل
extends Node2D

var armature_view: Node = null
var source_path: String = ""

func open_asset(factory_resource: Resource, armature_name: String) -> bool:
    if not ProjectSettings.get_setting("dragonbones/enabled", false):
        return false
    # إنشاء DragonBonesArmatureView من المصنع فقط.
    # لا تربطه بطبقة IVORY ولا تخفِ surface الخاصة بالطبقة.
    return true

func close_preview() -> void:
    # أوقف التشغيل ثم أزل عقدة المعاينة فقط.
    # لا تستدعِ LayerStack.shed_skin() هنا لأن المعاينة ليست جلد IVORY.
    if is_instance_valid(armature_view):
        armature_view.queue_free()
    armature_view = null
```

الفكرة الأساسية: المعاينة تستخدم `DragonBonesArmatureView`، بينما لوحة IVORY الأصلية تبقى كما هي. عند الإغلاق يجب ألا تكون هناك أي كتابة إلى `l.rig` أو `l.poses` أو سطح الطبقة.

### المرحلة 2 — استيراد صريح، وليس ربطًا حيًا

إذا أردت تحرير شخصية DragonBones داخل IVORY، استخدم أمرًا صريحًا مثل **Import as IVORY Rig**. هذا الأمر ينشئ نسخة جديدة قابلة للتراجع ولا يستبدل الأصل:

- يقرأ عظام DragonBones ويحوّلها إلى `BoneRig.Bone`.
- يحوّل `parent` ومواضع العظام إلى إحداثيات IVORY.
- يحفظ بيانات المصدر في حقل منفصل، مثل `rig.source = "dragonbones"` و`rig.source_version`.
- ينشئ نسخة عمل داخل طبقة جديدة أو نسخة من الطبقة، لا فوق الأصل مباشرة.
- يسجل العملية عبر `record_state()` كي تعمل Undo/Redo.
- إذا فشل الاستيراد، يحذف النسخة المؤقتة ويترك المشروع كما كان.

### المرحلة 3 — دعم الميزات المتقدمة تدريجيًا

| ميزة DragonBones | المسار الأول الآمن |
|---|---|
| العظام وFK | تحويل إلى `BoneRig.Bone` |
| IK | تحويل إلى إعدادات IVORY أو خبز الوضعيات إلى مفاتيح |
| Skinning/mesh/FFD | تحويل إلى `RigSkin` عند توافق البيانات، وإلا معاينة فقط |
| Slots وz-order | طبقات/مجموعات IVORY منفصلة |
| Constraints | خبزها إلى وضعيات أو إضافة محول منفصل، لا خلط solverين في الإطار نفسه |
| Nested armature | معاينة DragonBones أولًا؛ لا استيراد تلقائي في الإصدار الأول |
| Texture atlas | نسخ الموارد إلى مجلد المشروع مع مسارات نسبية |
| Animation curves | تحويل منحنيات مدعومة فقط، مع fallback إلى keyframes |

لا ينبغي تشغيل solver DragonBones و`BoneRig.solve()` على نفس الشخصية في الوقت نفسه. يجب اختيار مالك واحد للهيكل في كل وضع تشغيل.

## عقد العزل المطلوبة

ينبغي أن يكون هناك وضعان واضحان:

```text
IVORY_NATIVE
  source of truth = LayerStack.rig / RigTrack
  renderer        = RigSkin

DRAGONBONES_PREVIEW
  source of truth = DragonBonesArmature
  renderer        = DragonBonesArmatureView
  writes IVORY    = no

DRAGONBONES_IMPORTED
  source of truth = converted LayerStack.rig / RigTrack
  renderer        = RigSkin
  source asset    = metadata only
```

يجب رفض أي انتقال يخلط مصدرَي الحقيقة في الإطار الواحد.

## اختبارات عدم التأثير

قبل تفعيل الإضافة في نسخة الإنتاج، يجب اجتياز الاختبارات التالية:

1. تشغيل المشروع بدون مجلد الإضافة أو بدون مكتبة GDExtension؛ يجب أن يعمل IVORY كما كان.
2. فتح مشروع قديم؛ يجب أن تبقى الطبقات والعظام والوضعيات كما هي.
3. رسم، تراجع، إعادة، حفظ، وإعادة فتح أثناء عدم تفعيل DragonBones.
4. فتح المعاينة ثم إغلاقها؛ يجب ألا يتغير `project.json` أو عدد الطبقات.
5. إلغاء الاستيراد أو فشل ملف JSON؛ يجب ألا تترك طبقة نصف منشأة.
6. حذف المعاينة أثناء تشغيل animation؛ يجب ألا يحدث crash أو بقاء عقدة يتيمة.
7. التأكد من عدم رسم نفس الشخصية مرتين.
8. اختبار التصدير مع الإضافة موجودة ومعها غير موجودة.
9. اختبار Android/Compatibility renderer، لأن IVORY مضبوط على `gl_compatibility`.
10. التحقق من أن كل الموارد المنسوخة تستخدم مسارات نسبية داخل المشروع.

## قرار عملي لهذا المشروع

الملفات الحالية تبين أن IVORY لا يحتاج DragonBones كي يحصل على نظام عظام متقدم؛ هذا موجود بالفعل في النواة الأصلية. القيمة الحقيقية من DragonBones ستكون في **استيراد أصول خارجية أو معاينتها**. لذلك يكون التنفيذ الصحيح:

1. إضافة الإضافة الخارجية كاعتماد اختياري غير مطلوب للتشغيل.
2. بناء `DragonBonesPreviewHost` منفصل.
3. إضافة مستورد منفصل لا يعدّل المشاريع القديمة تلقائيًا.
4. تحويل العظام الأساسية أولًا.
5. إبقاء mesh/FFD/constraints المتقدمة في المعاينة إلى أن يثبت تحويلها.
6. تفعيل الخيار للمستخدم فقط بعد اجتياز اختبارات الرجوع والتصدير.

## تنبيه عن الإضافة الخارجية

الإضافة المرجعية `Daylily-Zeleen/Godot-DragonBones` تدعم Godot 4.2+ وDragonBones Pro 5.6، وتُبنى كـ GDExtension. يجب اختيار نسخة release المطابقة للمنصة أو بناء المكتبة محليًا؛ لا يكفي نسخ ملفات المصدر إلى المشروع. كما يجب فحص ترخيصها وحجم ثنائياتها قبل شحنها مع IVORY.

> لا تُفعّل DragonBones كاعتماد إلزامي ولا تستبدل `BoneRig` الحالي. ابدأ بالمعاينة المعزولة، ثم الاستيراد بنسخة جديدة وتراجع كامل.
