#!/usr/bin/env python3
"""Static guard for the native Animation workspace chooser."""
from pathlib import Path
import re, sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
h = root / 'native/ivory/src/ivory_animation_workspace_picker.h'
cpp = root / 'native/ivory/src/ivory_animation_workspace_picker.cpp'
settings = root / 'scripts/ui/settings_panels.gd'
reg = root / 'native/ivory/src/register_types.cpp'
native = root / 'scripts/native.gd'

errors = []
for p in (h, cpp, settings, reg, native):
    if not p.exists(): errors.append(f'missing: {p.relative_to(root)}')

if not errors:
    hs, cs, ss, rs, ns = [p.read_text(encoding='utf-8') for p in (h, cpp, settings, reg, native)]
    if 'GDCLASS(IvoryAnimationWorkspacePicker, PanelContainer)' not in hs:
        errors.append('picker is not a native PanelContainer')
    if len(re.findall(r'memnew\(Button\)', cs)) != 2:
        errors.append('native picker must create exactly two Button nodes')
    for token in ('choose_ivory', 'choose_stretchy', 'workspace_selected'):
        if token not in cs:
            errors.append(f'missing native action/signal: {token}')
    if 'ScrollContainer' in cs:
        errors.append('native picker contains ScrollContainer')
    if 'GDREGISTER_CLASS(IvoryAnimationWorkspacePicker);' not in rs:
        errors.append('native picker is not registered')
    if 'animation_workspace_picker()' not in ns:
        errors.append('Native bridge for picker is missing')
    start = ss.find('static func animation_project_start')
    end = ss.find("## Ivory's old animation form", start)
    block = ss[start:end] if start >= 0 and end >= 0 else ''
    block_code = '\n'.join(line.split('#', 1)[0] for line in block.splitlines())
    if 'Native.animation_workspace_picker()' not in block_code:
        errors.append('Animation start does not instantiate the native picker')
    if 'ScrollContainer' in block_code:
        errors.append('Animation start still contains a scrollable chooser')
    if 'make_text_button' in block_code:
        errors.append('Animation start still creates workspace buttons in GDScript')
    if 'workspace_selected' not in block_code:
        errors.append('Animation start does not consume native workspace_selected')

if errors:
    print('FAIL:')
    print('\n'.join(' - '+e for e in errors))
    raise SystemExit(1)
print('PASS: native C++ Animation workspace picker has exactly two real buttons, no scrolling, is registered, and is mounted by the Animation entry point.')
