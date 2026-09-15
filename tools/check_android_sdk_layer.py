#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JAVA = ROOT / "android/plugin_src/ivory_media/src/main/java/com/aaje/ivory/media"
FILES = {
    JAVA / "IvoryFilePicker.java": [
        'getPluginName()', '"IvoryFilePicker"', 'ACTION_OPEN_DOCUMENT',
        'CATEGORY_OPENABLE', 'file_picked', 'copyToPrivateStorage',
        'takePersistableUriPermission'
    ],
    JAVA / "IvoryAndroid.java": [
        'getPluginName()', '"IvoryAndroid"', 'sdkInfo()', 'openUrl',
        'shareText', 'vibrate', 'displayInfo', 'keepScreenOn'
    ],
    ROOT / "scripts/android_platform.gd": [
        'Engine.has_singleton("IvoryAndroid")',
        'Engine.has_singleton("IvoryFilePicker")',
    ],
}

errors = []
for path, needles in FILES.items():
    if not path.exists():
        errors.append(f"missing: {path}")
        continue
    text = path.read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            errors.append(f"{path}: missing {needle}")

# Detect accidental external-package residue after integration.
old_pkg = 'com.pattlebass.godotfilepicker'
for p in ROOT.rglob('*'):
    if p.is_file() and p.suffix in {'.java', '.gd', '.gradle', '.gdap', '.md'}:
        try:
            if old_pkg in p.read_text(encoding='utf-8', errors='ignore'):
                errors.append(f"external picker residue: {p}")
        except Exception:
            pass

if errors:
    print("ANDROID_SDK_LAYER_FAIL")
    print("\n".join(errors))
    raise SystemExit(1)
print("ANDROID_SDK_LAYER_OK")
print("IvoryFilePicker + IvoryAndroid are integrated into ivory_media.")
