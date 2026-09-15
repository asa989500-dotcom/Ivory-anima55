# بناء IVORY كملف APK — الدليل الكامل

> قبل هذه المرحلة لم يكن في المشروع ملف `export_presets.cfg`، ومعناه بالضبط
> أنّ المحرّر لا يعرف أنّ هناك هدفًا اسمه أندرويد، وسطر الأوامر لا يجد اسم
> إعدادٍ يُعطى له. صار الملف موجودًا الآن، ومعه الأيقونة التكيّفية والأذونات
> ومكان التوقيع.

## ما تحتاجه مرة واحدة فقط

1. **Godot 4.7** (نسخة standard، لا mono).
2. **قوالب التصدير** — من داخل المحرّر:
   `Editor ▸ Manage Export Templates ▸ Download and Install`.
3. **Java (JDK 17)** — لأداة `keytool` وحدها، لأنّ البناء هنا لا يستعمل Gradle.

لا حاجة إلى Android SDK ولا إلى Gradle: `gradle_build/use_gradle_build=false`،
والبناء يتمّ من القالب الجاهز.

## أولًا: مفتاح التوقيع

كلّ APK يجب أن يكون موقَّعًا وإلّا رفض الجهاز تركيبه.

### مفتاح التجربة (debug)

```bash
keytool -keyalg RSA -genkeypair -alias androiddebugkey \
  -keypass android -keystore android/keystore/debug.keystore \
  -storepass android -dname "CN=Android Debug,O=Android,C=US" \
  -validity 9999 -deststoretype pkcs12
```

### مفتاح الإصدار (release) — احتفظ به، فقدانه يعني ألّا تستطيع تحديث التطبيق أبدًا

```bash
keytool -keyalg RSA -genkeypair -alias ivory \
  -keystore android/keystore/ivory-release.keystore \
  -validity 10000 -deststoretype pkcs12
```

ثمّ عرّف المسارات وكلمات السرّ في البيئة — لا تكتبها داخل الملفات:

```bash
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$PWD/android/keystore/debug.keystore"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="android"

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$PWD/android/keystore/ivory-release.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="ivory"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="…"
```

`android/keystore/` مستثنًى من التصدير ومن الأرشيف، فلن يدخل مفتاحك في APK.

## ثانيًا: البناء

```bash
mkdir -p build

# نسخة تجربة، فيها رسائل الخطأ كاملة
godot --headless --path . --export-debug "Android" build/IVORY-debug.apk

# نسخة الإصدار
godot --headless --path . --export-release "Android" build/IVORY.apk
```

ثم التركيب على الجهاز:

```bash
adb install -r build/IVORY-debug.apk
```

## ثالثًا: قبل كلّ بناء

```bash
python3 tools/check_all.py .      # الفواحص الساكنة الاثنتا عشرة
godot --headless --path . --script tests/run_tests.gd    # الاختبارات التي تشغّل الكود فعلًا
```

الأمران معًا في سطر واحد:

```bash
bash tools/build.sh
```

## الأيقونات

مولَّدة من `icon.png` بأمرٍ واحد، فإن غيّرت الرسم أعد توليدها:

```bash
python3 tools/make_android_icons.py .
```

يُنتج أربعة ملفات في `android/icons/`: الأيقونة العادية 192، ومقدّمة تكيّفية
432 داخل الدائرة الآمنة، وخلفية بلون الأيقونة نفسه، وصورة أحادية لأيقونات
أندرويد 13 المصبوغة بلون الخلفية.

## الأذونات

| الإذن | لماذا |
|---|---|
| `READ_EXTERNAL_STORAGE` | استيراد صورة إلى طبقة |
| `READ_MEDIA_IMAGES` | نفس الشيء على أندرويد 13 فما فوق، حيث لم يعد الإذن الأول يغطّي الصور |
| `WRITE_EXTERNAL_STORAGE` | خروج التصدير إلى مكانٍ يراه معرض الصور |

`MANAGE_EXTERNAL_STORAGE` غير مطلوب عمدًا: هو الإذن الذي يراجعه متجر Play
يدويًّا ويرفضه لتطبيقٍ لا يحتاجه، والتصدير هنا يمرّ عبر مجلّدات الوسائط.

---

# Building IVORY (English)

`export_presets.cfg` defines two presets: **Android** (arm64 only, min SDK 24,
target 34) and **Linux/X11** (only so the tests and the benchmark can run on a
desktop).

```bash
godot --headless --path . --export-release "Android" build/IVORY.apk
```

Signing credentials come from the `GODOT_ANDROID_KEYSTORE_*` environment
variables so no secret is ever stored in the repository. Icons are generated
by `tools/make_android_icons.py`. Run `bash tools/build.sh` to check, test and
export in one step.

## MP4 / GDE GoZen

يحتوي المشروع الآن على مصدر GDE GoZen المعدّل في `native/gde_gozen`، ومعه
الصنف `GoZenMP4Encoder`. قبل بناء APK يجب أن تكون مكتبة GoZen الأصلية المترجمة
لـ Android موجودة في `addons/gde_gozen/bin/`.

لـ arm64:

```text
addons/gde_gozen/bin/libgozen.android.template_release.arm64.so
```

تجميعة GoZen الأصلية تحتاج FFmpeg و`godot-cpp` و`libvpx` و`libaom` كـ
submodules، ولذلك لا يمكن أن تكون ملفات `.so` جزءاً من هذا المصدر وحده.
راجع `native/gde_gozen/IVORY_MP4.md`.

بعد وضع المكتبة، سيضم `export_filter="all_resources"` مكتبة GDExtension داخل
APK تلقائياً، وسيظهر خيار MP4 في صفحة تصدير الرسوم المتحركة.
