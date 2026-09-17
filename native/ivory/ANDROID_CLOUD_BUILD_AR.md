# بناء IVORY C++ لـ Android بدون كمبيوتر

هذا المشروع أصبح مجهزًا للبناء السحابي عبر GitHub Actions.

## ماذا يبني؟

- `libivory.android.template_release.arm64.so`
- `libivory.android.template_debug.arm64.so`
- باستخدام `godot-cpp` المضمّن داخل `native/ivory/godot-cpp/`
- مستهدف Godot API 4.7

## طريقة التشغيل من الهاتف

1. ارفع مجلد المشروع إلى مستودع GitHub خاص بك.
2. افتح تبويب **Actions**.
3. اختر **Build IVORY C++ Android GDExtension**.
4. اضغط **Run workflow**.
5. انتظر انتهاء البناء.
6. نزّل artifact باسم `ivory-android-arm64-native`.
7. ضع ملفات `.so` الناتجة في مجلد `bin/` في مشروع Godot.
8. بعدها صدّر APK من Godot/بيئة التصدير التي تستخدمها.

> لا يوجد هنا ملف `.so` وهمي. الـ workflow هو الذي يبني المكتبة فعليًا باستخدام Android NDK.

## اختبار الحماية

لا يعتبر البناء ناجحًا إذا لم توجد المكتبتان أو إذا لم تتطابق أسماءهما مع `ivory.gdextension`.
