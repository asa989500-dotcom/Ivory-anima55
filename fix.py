import re

def replace_once(fname, old, new, label):
    with open(fname) as f:
        content = f.read()
    if old not in content:
        print(f"SKIP (already applied or not found): {label}")
        return
    content = content.replace(old, new, 1)
    with open(fname, 'w') as f:
        f.write(content)
    print(f"OK: {label}")

f1 = 'native/ivory/src/ivory_animation_workspace_picker.cpp'
replace_once(f1, 'MAXF(get_size().x, PANEL_W)', 'MAX(get_size().x, PANEL_W)', 'f1-1')
replace_once(f1, 'MAXF(get_size().y, PANEL_H)', 'MAX(get_size().y, PANEL_H)', 'f1-2')
replace_once(f1, 'MAXF(1.0f, w - PAD_X * 2.0f)', 'MAX(1.0f, w - PAD_X * 2.0f)', 'f1-3')
replace_once(f1, 'MAXF(PAD_TOP + 30.0f,', 'MAX(PAD_TOP + 30.0f,', 'f1-4')
replace_once(f1, 'MAXF(PAD_TOP,', 'MAX(PAD_TOP,', 'f1-5')
replace_once(f1,
    '    pass += get_clip_contents() == false;                                // 08',
    '    pass += const_cast<IvoryAnimationWorkspacePicker *>(this)->is_clipping_contents() == false; // 08',
    'f1-6')
replace_once(f1,
    'ivory_button_->is_connected("pressed", Callable(this, StringName("_choose_ivory"))) &&',
    'ivory_button_->is_connected("pressed", Callable(const_cast<IvoryAnimationWorkspacePicker *>(this), StringName("_choose_ivory"))) &&',
    'f1-7')
replace_once(f1,
    'stretchy_button_->is_connected("pressed", Callable(this, StringName("_choose_stretchy"))); // 29',
    'stretchy_button_->is_connected("pressed", Callable(const_cast<IvoryAnimationWorkspacePicker *>(this), StringName("_choose_stretchy"))); // 29',
    'f1-8')

f2 = 'native/ivory/src/ivory_character360_rig.h'
replace_once(f2,
    '};\n\nVARIANT_ENUM_CAST(IvoryCharacter360Rig::PinType);\n\n} // namespace godot\n#endif',
    '};\n\n} // namespace godot\n\nVARIANT_ENUM_CAST(godot::IvoryCharacter360Rig::PinType);\n#endif',
    'f2-1')

f3 = 'native/ivory/src/ivory_pose.cpp'
replace_once(f3,
    'worst = std::max(worst, head_[i].distance_to(keyed_head_[i]));',
    'worst = std::max(worst, (double)head_[i].distance_to(keyed_head_[i]));',
    'f3-1')
replace_once(f3,
    'worst = std::max(worst, tail_[i].distance_to(keyed_tail_[i]));',
    'worst = std::max(worst, (double)tail_[i].distance_to(keyed_tail_[i]));',
    'f3-2')

f4 = 'native/ivory/src/ivory_stretchy_canvas_picker.cpp'
replace_once(f4, 'set_size_flags_horizontal(', 'set_h_size_flags(', 'f4-1')

f5 = 'native/ivory/src/ivory_stretchy_document.cpp'
replace_once(f5,
    'std::max(8.0, start.distance_to(end))',
    'std::max(8.0, (double)start.distance_to(end))',
    'f5-1')
replace_once(f5,
    'std::max(4.0, delta.length())',
    'std::max(4.0, (double)delta.length())',
    'f5-2')

f6 = 'native/ivory/src/ivory_stretchy_export.cpp'
replace_once(f6,
    '#include <godot_cpp/classes/os.hpp>',
    '#include <godot_cpp/classes/os.hpp>\n#include <godot_cpp/classes/json.hpp>',
    'f6-1 include json')
replace_once(f6,
    'maxi(int(project.get("performance_sample_every_frames", 1)), 1)',
    'std::max(int(project.get("performance_sample_every_frames", 1)), 1)',
    'f6-2')
replace_once(f6,
    'maxi(int(project.get("fps", 24)), 1)',
    'std::max(int(project.get("fps", 24)), 1)',
    'f6-3')
replace_once(f6, 'String("audio_%02d") % i', 'String("audio_%02d") % (int64_t)i', 'f6-4')
replace_once(f6, 'String("texture_%02d.png") % i', 'String("texture_%02d.png") % (int64_t)i', 'f6-5')
replace_once(f6, 'String("motion_%02d") % i', 'String("motion_%02d") % (int64_t)i', 'f6-6')

replace_once(f6,
    '\t\tfor (int i = 0; i < motions.size(); ++i) {\n\t\t\tfiles.push_back(Dictionary{{"File", motions[i]}});\n\t\t}',
    '\t\tfor (int i = 0; i < motions.size(); ++i) {\n\t\t\tDictionary file_entry;\n\t\t\tfile_entry["File"] = motions[i];\n\t\t\tfiles.push_back(file_entry);\n\t\t}',
    'f6-7 dict1')

replace_once(f6,
    '\t\tif (!ids.is_empty()) {\n\t\t\tgroups_array.push_back(Dictionary{{"Target", "Parameter"}, {"Name", k}, {"Ids", ids}});\n\t\t}',
    '\t\tif (!ids.is_empty()) {\n\t\t\tDictionary group_entry;\n\t\t\tgroup_entry["Target"] = "Parameter";\n\t\t\tgroup_entry["Name"] = k;\n\t\t\tgroup_entry["Ids"] = ids;\n\t\t\tgroups_array.push_back(group_entry);\n\t\t}',
    'f6-8 dict2')

replace_once(f6,
    'out.push_back(Dictionary{{"Id", id}, {"Name", String(p.get("name", id))}});',
    'Dictionary part_entry;\n\t\t\tpart_entry["Id"] = id;\n\t\t\tpart_entry["Name"] = String(p.get("name", id));\n\t\t\tout.push_back(part_entry);',
    'f6-9 dict3')

replace_once(f6,
    'idx_kfs.push_back(Dictionary{{"time", q.get("time", 0.0)}, {"value", k}, {"easing", q.get("easing", "linear")}});',
    'Dictionary idx_entry;\n\t\t\t\tidx_entry["time"] = q.get("time", 0.0);\n\t\t\t\tidx_entry["value"] = k;\n\t\t\t\tidx_entry["easing"] = q.get("easing", "linear");\n\t\t\t\tidx_kfs.push_back(idx_entry);',
    'f6-10 dict4')

replace_once(f6,
    'curves.push_back(Dictionary{{"Target", target}, {"Id", id}, {"Segments", seg}});',
    'Dictionary curve_entry;\n\t\tcurve_entry["Target"] = target;\n\t\tcurve_entry["Id"] = id;\n\t\tcurve_entry["Segments"] = seg;\n\t\tcurves.push_back(curve_entry);',
    'f6-11 dict5')

replace_once(f6,
    'return Dictionary{{"Version", 3}, {"Meta", meta}, {"Curves", curves}};',
    'Dictionary final_out;\n\tfinal_out["Version"] = 3;\n\tfinal_out["Meta"] = meta;\n\tfinal_out["Curves"] = curves;\n\treturn final_out;',
    'f6-12 dict6')

replace_once(f6,
    'cdi_params.push_back(Dictionary{{"id", p.get("id", "")}, {"name", p.get("name", p.get("id", ""))}, {"group_id", p.get("groupId", "")}});',
    'Dictionary cdi_entry;\n\t\tcdi_entry["id"] = p.get("id", "");\n\t\tcdi_entry["name"] = p.get("name", p.get("id", ""));\n\t\tcdi_entry["group_id"] = p.get("groupId", "");\n\t\tcdi_params.push_back(cdi_entry);',
    'f6-13 dict7')

replace_once(f6,
    'Dictionary model_opts{{"model_name", model_name}, {"texture_files", textures}};',
    'Dictionary model_opts;\n\tmodel_opts["model_name"] = model_name;\n\tmodel_opts["texture_files"] = textures;',
    'f6-14 dict8')

replace_once(f6,
    'Dictionary cdi_opts{{"parameters", cdi_params}};',
    'Dictionary cdi_opts;\n\tcdi_opts["parameters"] = cdi_params;',
    'f6-15 dict9')

print("ALL DONE")
