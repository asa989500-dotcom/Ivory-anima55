# حالة دمج Stretchy Studio داخل IVORY

## المكتمل في هذه النسخة

تم نقل واجهة Stretchy إلى إعدادات مشاريع الرسوم المتحركة فقط، مع خيارين: واجهة Ivory العادية وواجهة Stretchy Studio الاحترافية. يحفظ المشروع اختيار الواجهة، وتبقى بطاقة المشروع في لوحة المشاريع بالشكل المعتاد، بينما يصبح الإطار الخارجي أسود عند اختيار Stretchy.

ترتبط غرفة Stretchy بمشروع الرسوم الحالي، وتحفظ وثيقة Stretchy تلقائيًا بعد التعديلات، وعند الخروج، وعند مغادرة التطبيق. كما تُنسخ صور الطبقات المستوردة إلى مجلد المشروع حتى لا يعتمد الاسترجاع على مسار خارجي قد يتغير. زر الخروج وزر الرجوع في النظام يحفظان الوثيقة ثم يحرران غرفة Stretchy وملفاتها ويعيدان المستخدم إلى لوحة المشاريع.

تمت إضافة تاريخ تعديلات مستقل داخل Stretchy. النقر السريع بإصبعين دون حركة ينفذ Undo، والنقر السريع بثلاثة أصابع دون حركة ينفذ Redo. لا تُنشأ نقطة أو عظمة قبل التأكد من أن اللمسة ليست gesture متعددة الأصابع.

## غير المكتمل فعليًا

ملفات كتّاب Cubism الثنائية التالية غير موجودة في المصدر المرفق، ولذلك لا يمكن اعتبار تصدير Live2D الكامل مكتملًا أو اختلاق تنفيذه دون المصدر المرجعي والاختبارات الثنائية:

- `moc3writer`
- `cmo3writer`
- `can3writer`
- `bodyAnalyzer`
- `caffPacker`
- `textureAtlas`
- `pngHelpers`
- `xmlbuilder`
- `bodyRig`
- `deformerEmit`

الموجود حاليًا في C++ هو بناء ملفات JSON التالية: `model3.json` و`cdi3.json` و`motion3.json`. أما إنشاء ملفات `MOC3` و`CMO3` و`CAN3` الحقيقية فيتطلب ملفات المصدر الأصلية أو مواصفات binary fixtures الخاصة بها.

## التحقق

اجتازت الملفات المعدلة فحوصات المسافات، المعرفات غير المعلنة، واستدعاءات الدوال غير الموجودة. لا يحتوي بيئة الأرشيف على Godot أو `godot-cpp` أو `scons`، لذلك لم يتم تشغيل build فعلي للمحرك أو امتداد C++ داخل هذه البيئة.

> النتيجة: وظائف الواجهة والحفظ واللمس والخروج مدمجة، لكن ادعاء اكتمال تصدير Cubism الثنائي بنسبة 100% سيكون غير صحيح ما لم تصل ملفات الكتّاب الأصلية.

---

# Stretchy Studio integration status

## Completed in this build

Stretchy is now selected only from animation-project settings, with Ivory and Stretchy Studio workspace choices. The choice is stored per project, the project card remains a normal animation card, and Stretchy uses a black outer stage. The room owns the active animation document, autosaves changes, saves on exit and application back navigation, and copies imported layer images into the project directory for reliable restoration.

Two-finger tap performs Undo and three-finger tap performs Redo. A mesh point or bone is not created until the gesture is known to be a one-finger action.

## Not present in the supplied source

The binary Cubism writer sources listed above are absent from the supplied archive. The C++ layer currently emits `model3.json`, `cdi3.json`, and `motion3.json`; it does not fabricate `MOC3`, `CMO3`, or `CAN3` binaries.
