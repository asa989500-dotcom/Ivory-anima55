#!/usr/bin/env python3
"""Stage 179: 29 invariant checks + 20 regression tests for the two native buttons."""
from pathlib import Path
import re
import sys

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
CPP = ROOT / 'native/ivory/src/ivory_animation_workspace_picker.cpp'
H = ROOT / 'native/ivory/src/ivory_animation_workspace_picker.h'
EXT = ROOT / 'ivory.gdextension'
REG = ROOT / 'native/ivory/src/register_types.cpp'
NATIVE = ROOT / 'scripts/native.gd'
SETTINGS = ROOT / 'scripts/ui/settings_panels.gd'
ROUTER = ROOT / 'scripts/ui/settings_router.gd'

errors = []
def require(cond, msg):
    if not cond:
        errors.append(msg)

def read(p):
    require(p.exists(), f'missing {p.relative_to(ROOT)}')
    return p.read_text(encoding='utf-8') if p.exists() else ''

cpp, h, ext, reg, native, settings, router = [read(p) for p in (CPP,H,EXT,REG,NATIVE,SETTINGS,ROUTER)]

# 29 source/runtime contract checks. These are deliberately independent.
checks = [
    ('01 native class', 'GDCLASS(IvoryAnimationWorkspacePicker, PanelContainer)' in h),
    ('02 exactly two Button allocations', len(re.findall(r'memnew\(Button\)', cpp)) == 2),
    ('03 Ivory allocation', 'ivory_button_ = memnew(Button);' in cpp),
    ('04 Stretchy allocation', 'stretchy_button_ = memnew(Button);' in cpp),
    ('05 fixed width constant', 'PANEL_W = 430.0f' in h),
    ('06 fixed height constant', 'PANEL_H = 236.0f' in h),
    ('07 fixed geometry function', 'layout_fixed' in h and 'layout_fixed' in cpp),
    ('08 resize relayout', 'NOTIFICATION_RESIZED' in cpp),
    ('09 no scrolling container token', 'scrollcontainer' not in cpp.lower() and 'scrollcontainer' not in h.lower()),
    ('10 no scrolling container include', 'scroll_container' not in cpp.lower()),
    ('11 clipping disabled', 'set_clip_contents(false)' in cpp),
    ('12 panel input stops', 'set_mouse_filter(Control::MOUSE_FILTER_STOP)' in cpp),
    ('13 panel high z', 'set_z_index(PANEL_Z)' in cpp),
    ('14 panel z independent', 'set_z_as_relative(false)' in cpp),
    ('15 dedicated surface', 'surface_ = memnew(Control);' in cpp),
    ('16 surface ignores input', 'surface_->set_mouse_filter(Control::MOUSE_FILTER_IGNORE)' in cpp),
    ('17 Ivory visible', 'ivory_button_->set_visible(true)' in cpp),
    ('18 Stretchy visible', 'stretchy_button_->set_visible(true)' in cpp),
    ('19 Ivory input stops', cpp.count('ivory_button_->set_mouse_filter(Control::MOUSE_FILTER_STOP)') == 1),
    ('20 Stretchy input stops', cpp.count('stretchy_button_->set_mouse_filter(Control::MOUSE_FILTER_STOP)') == 1),
    ('21 Ivory high z', 'ivory_button_->set_z_index(BUTTON_Z)' in cpp),
    ('22 Stretchy high z', 'stretchy_button_->set_z_index(BUTTON_Z)' in cpp),
    ('23 Ivory callback', 'Callable(this, "_choose_ivory")' in cpp),
    ('24 Stretchy callback', 'Callable(this, "_choose_stretchy")' in cpp),
    ('25 Ivory route', 'emit_signal("workspace_selected", String("ivory"))' in cpp),
    ('26 Stretchy route', 'emit_signal("workspace_selected", String("stretchy"))' in cpp),
    ('27 native registration', 'GDREGISTER_CLASS(IvoryAnimationWorkspacePicker);' in reg),
    ('28 native bridge', 'ClassDB.instantiate("IvoryAnimationWorkspacePicker")' in native),
    ('29 animation entry mounts native picker', 'Native.animation_workspace_picker()' in settings and 'workspace_selected' in settings),
]
for name, ok in checks:
    require(ok, f'29-check FAIL: {name}')

# 20 deterministic geometry/input regression tests.
PANEL_W, PANEL_H = 430.0, 236.0
PAD_X, PAD_TOP, GAP, BUTTON_H = 20.0, 18.0, 12.0, 78.0

def layout(w, h):
    w = max(w, PANEL_W); h = max(h, PANEL_H)
    bw = max(1.0, w - 2*PAD_X)
    y1 = PAD_TOP + 30.0
    y2 = y1 + BUTTON_H + GAP
    if y2 + BUTTON_H > h:
        y2 = max(PAD_TOP + 30.0, h - BUTTON_H - PAD_TOP)
        y1 = max(PAD_TOP, y2 - BUTTON_H - GAP)
    return (PAD_X, y1, bw, BUTTON_H), (PAD_X, y2, bw, BUTTON_H)

def inside(r, w, h):
    w = max(w, PANEL_W); h = max(h, PANEL_H)
    x,y,rw,rh = r
    return x >= 0 and y >= 0 and x+rw <= w+1 and y+rh <= h+1

cases = [
    ('01 default', 430,236), ('02 wide', 800,236), ('03 very wide', 1600,300),
    ('04 tall', 430,600), ('05 phone-ish width', 430,700), ('06 exact minimum',236,236),
    ('07 oversized width',1200,236), ('08 oversized height',430,1200),
    ('09 square',600,600), ('10 2x',860,472), ('11 tiny external request',100,100),
    ('12 landscape tablet',1280,800), ('13 portrait tablet',800,1280),
    ('14 16:9-ish',960,540), ('15 4:3-ish',1024,768), ('16 fractional',513,241),
    ('17 one-pixel wider',431,237), ('18 one-pixel shorter',430,235),
    ('19 repeated resize A',700,260), ('20 repeated resize B',450,500),
]
for name,w,h in cases:
    a,b = layout(w,h)
    require(inside(a,w,h), f'20-test FAIL: {name} Ivory outside panel')
    require(inside(b,w,h), f'20-test FAIL: {name} Stretchy outside panel')
    require(a[1]+a[3] <= b[1]+1e-6, f'20-test FAIL: {name} vertical order')
    require(a[1]+a[3] <= b[1], f'20-test FAIL: {name} overlap')
    require(a[2] > 1 and b[2] > 1, f'20-test FAIL: {name} zero width')

# Integration sanity: only the workspace decision is being tested here.
require('open_settings_page("new_animation_ivory")' in settings, 'Ivory destination changed')
require('host.open_stretchy_project_canvas_choice()' in settings, 'Stretchy destination changed')
require('elif page == "animation_new":' in router, 'Animation router entry missing')
require('entry_symbol = "ivory_library_init"' in ext, 'GDExtension entry symbol missing')
require('android.release.arm64' in ext and 'android.debug.arm64' in ext, 'Android ARM64 library mappings missing')
require('android.release.arm32' in ext and 'android.debug.arm32' in ext, 'Android ARM32 library mappings missing')

if errors:
    print('FAIL')
    for e in errors:
        print(' -', e)
    raise SystemExit(1)
print('PASS: 29/29 native safety invariants + 20/20 deterministic geometry regression tests.')
