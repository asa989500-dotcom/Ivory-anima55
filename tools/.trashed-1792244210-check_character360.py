#!/usr/bin/env python3
from pathlib import Path
root=Path(__file__).resolve().parents[1]
checks=[]
def req(path, text): checks.append((text in (root/path).read_text(), f'{path} contains {text}'))
req(Path('native/ivory/src/ivory_character360.h'),'class IvoryCharacter360')
req(Path('native/ivory/src/ivory_character360.cpp'),'void IvoryCharacter360::_bind_methods')
req(Path('native/ivory/src/ivory_character360.cpp'),'render_view')
req(Path('native/ivory/src/register_types.cpp'),'GDREGISTER_CLASS(IvoryCharacter360)')
req(Path('scripts/native.gd'),'ClassDB.instantiate("IvoryCharacter360")')
req(Path('scripts/ui/character360_builder.gd'),'Import PNG')
req(Path('scripts/ui/character360_builder.gd'),'Build Character 360')
req(Path('scripts/ui/character360_builder.gd'),'Character 360 Motion')
req(Path('scripts/ui/bspline_room.gd'),'_open_character360_builder')
req(Path('scripts/layer_stack.gd'),'is_character360_motion')
req(Path('scripts/vault.gd'),'character360_state')
req(Path('scripts/vault.gd'),'side_png')
req(Path('scripts/ui/bspline_room.gd'),'func _draw_curve_legacy')
req(Path('tools/test_character360_ultra.py'),'TOTAL:')
failed=[m for ok,m in checks if not ok]
print(f'Character360 static checks: {len(checks)} checks / {len(failed)} failures')
for m in failed: print('FAIL:',m)
raise SystemExit(1 if failed else 0)
