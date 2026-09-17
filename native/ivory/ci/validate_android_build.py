from pathlib import Path
import sys

root = Path(__file__).resolve().parents[3]
bin_dir = root / 'bin'
ext = root / 'ivory.gdextension'
required = [
    bin_dir / 'libivory.android.template_release.arm64.so',
    bin_dir / 'libivory.android.template_debug.arm64.so',
]
missing = [str(p) for p in required if not p.is_file() or p.stat().st_size == 0]
text = ext.read_text(encoding='utf-8') if ext.is_file() else ''
checks = {
    'gdextension exists': ext.is_file(),
    'release mapping': 'android.release.arm64 = "res://bin/libivory.android.template_release.arm64.so"' in text,
    'debug mapping': 'android.debug.arm64 = "res://bin/libivory.android.template_debug.arm64.so"' in text,
    'release library': required[0].is_file() and required[0].stat().st_size > 0,
    'debug library': required[1].is_file() and required[1].stat().st_size > 0,
}
for name, ok in checks.items():
    print(f'[PASS] {name}' if ok else f'[FAIL] {name}')
if missing or not all(checks.values()):
    if missing:
        print('Missing/empty:', *missing, sep='\n  ')
    sys.exit(1)
print('ANDROID_NATIVE_BUILD_VALIDATION=PASS')
