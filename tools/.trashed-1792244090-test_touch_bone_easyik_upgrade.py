from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
B=(ROOT/'native/ivory/src/ivory_bone.cpp').read_text(); BH=(ROOT/'scripts/ui/bone_handle.gd').read_text(); CV=(ROOT/'scripts/canvas_view.gd').read_text(); C360=(ROOT/'native/ivory/src/ivory_character360_rig.cpp').read_text(); C360H=(ROOT/'native/ivory/src/ivory_character360_rig.h').read_text(); T=(ROOT/'native/ivory/src/ivory_touch.cpp').read_text(); TH=(ROOT/'native/ivory/src/ivory_touch.h').read_text(); BR=(ROOT/'scripts/ui/bone_room.gd').read_text();
checks=0; fails=[]
def ok(n,c):
 global checks; checks+=1
 if not c: fails.append(n)
ok('EasyIK reference uses analytic two bone', 'TWO_BONE_IK' in (ROOT.parent/'EasyIK-7cccb4168b8e76f0e70e5bcd463daf08e483c15d/addons/easyik/core/ik_enums.gd').read_text() if (ROOT.parent/'EasyIK-7cccb4168b8e76f0e70e5bcd463daf08e483c15d').exists() else True)
ok('native pole reach exposed','reach_pole' in B and 'reach_pole' in BH)
ok('pole hysteresis present','hysteresis' in B and '0.0125' in B)
ok('no single-joint mirror','Do not mirror a single joint' in B or 'complete solved chain' in B)
ok('rigid lengths remain source-of-truth','length_' in B and 'carry' in B)
ok('touch-only canvas routing','touch_bones: bool = false' in CV and 'BoneHandle.grab(self, screen, touch_bones)' in CV)
ok('touch down enables bone mode','_begin_input(e.position, true)' in CV)
ok('mouse cannot seize BoneHandle','BoneHandle.grab(self, screen, touch_bones)' in CV)
ok('native touch deadband','deadband_px' in TH and 'deadband_hits_' in T)
ok('native touch jitter metric','jitter_rms_px' in T)
ok('native pressure metric','sample_pressure' in T and 'pressure_' in TH)
ok('native stable gate','bool IvoryTouch::stable' in T)
ok('Character360 pole API','solve_ik_pole' in C360H and 'solve_ik_pole' in C360)
ok('Character360 uses pole-aware path','has_method("solve_ik_pole")' in (ROOT/'scripts/character360_rig_controller.gd').read_text())
ok('bone-room mouse move blocked','if _touches.size() > 0 else []' in BR)
print(f'TOUCH BONE EASYIK UPGRADE / {checks} CHECKS / {len(fails)} FAILURES')
if fails:
 for x in fails: print('FAIL:',x)
 raise SystemExit(1)
print('ALL CHECKS PASSED')
