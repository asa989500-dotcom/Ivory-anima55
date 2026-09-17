# ضع مفاتيح التوقيع هنا

هذا المجلد مستثنى من التصدير (`exclude_filter` في `export_presets.cfg`)
ومن الأرشيف، فلن يدخل مفتاحك في APK ولن يسافر مع المشروع.

    keytool -keyalg RSA -genkeypair -alias ivory \
      -keystore android/keystore/ivory-release.keystore \
      -validity 10000 -deststoretype pkcs12

ثم عرّف `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` و`_USER` و`_PASSWORD` في
البيئة. التفاصيل في `BUILD_ANDROID.md`.

**احتفظ بمفتاح الإصدار.** فقدانه يعني ألّا تستطيع تحديث التطبيق أبدًا.
