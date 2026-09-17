# المرحلة ١١٨ — تصدير MP4

أضيف تصدير **MP4** حقيقي إلى مشروع IVORY باستخدام مصدر **GDE GoZen** الذي أُدخل
إلى `native/gde_gozen`.

## ما أُضيف

- `Exporters.save_mp4()` يمر على إطارات الـ timeline ويُرسل كل إطار مباشرةً إلى
  المرمّز، فلا يحتفظ بالفيديو كاملاً في الذاكرة.
- زر **MP4** وزر **MP4 مصغّر 1280** في صفحة التصدير.
- تصدير الرسوم المتحركة بالضغطة الواحدة أصبح MP4 افتراضياً.
- أُضيف `GoZenMP4Encoder` إلى GDE GoZen.
- أُعيد تفعيل `mpeg4` encoder و`mp4` muxer في FFmpeg، مع إبقاء بقية بناء
  FFmpeg مصغّراً كما هو.
- أبعاد MP4 تُجعل زوجية تلقائياً عند الحاجة، لأن مسار YUV420 المستخدم يحتاج
  ذلك.

## ملاحظة مهمة عن الكودك

هذا البناء يستخدم **MPEG-4 Part 2** الأصلي في FFmpeg، وليس H.264/x264. السبب
أن تجميعة GoZen الأصلية تعطل الـ encoders والـ muxers، ولا تحمل x264. النتيجة
ملف MP4 حقيقي، لكن إذا أردنا لاحقاً H.264/AVC لأقصى توافق مع المنصات الحديثة،
فنحتاج إضافة encoder H.264 مناسب إلى بناء FFmpeg أو استخدام MediaCodec على
Android.

## الصوت

هذا الإصدار يصدر **الصورة فقط**. لا يضيف مسار الصوت الموجود في المشروع إلى
MP4 بعد.

## التجميع

ملف المصدر الأصلي لا يحتوي الثنائيات الجاهزة ولا محتويات الـ submodules كاملة.
بعد تهيئة FFmpeg وgodot-cpp وlibvpx وlibaom، يجب بناء GDE GoZen لـ Android
`arm64` ثم نسخ الناتج إلى:

`addons/gde_gozen/bin/libgozen.android.template_release.arm64.so`

ولنسخة debug:

`addons/gde_gozen/bin/libgozen.android.template_debug.arm64.so`

بعد وجود المكتبة سيجد IVORY الصنف `GoZenMP4Encoder` تلقائياً، ويصبح زر MP4
فعالاً. قبل ذلك يبقى المشروع قابلاً للفتح، لكن تصدير MP4 يرجع بفشل بدلاً من
إغلاق التطبيق.

## Stage 119 — professional H.264 MP4 export

MP4 now targets H.264/AVC rather than MPEG-4 Part 2. The exporter exposes Source/720p/1080p/1440p/4K sizing, CRF, optional bitrate, H.264 profile and audio. Frames are streamed one at a time through `MP4ExportWorker`; encoding runs on a dedicated thread while the timeline remains on the main thread. Progress reports percentage/frame count and an ETA, and cancellation removes partial files.

The layer now remembers its linked WAV source so the same timeline sound can be fed into the MP4 AAC stream. Audio is streamed in frame-sized PCM16 slices rather than loaded as one giant buffer. The current source model links one WAV sound per layer; the exporter uses the first valid linked sound. The native encoder accepts AAC and resamples to the source rate/channel count. HEVC/H.265 remains a later codec option.

The Android GoZen builder enables JNI, MediaCodec, H.264 MediaCodec encoding, AAC encoding, MP4 muxing and the file protocol. The Android NDK C++ compiler path was also corrected to `clang++`.
