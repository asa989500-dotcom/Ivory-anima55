#include "ivory_stretchy_document.h"

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <algorithm>

using namespace godot;

void IvoryStretchyDocument::_bind_methods() {
    ClassDB::bind_method(D_METHOD("create_document"),
            &IvoryStretchyDocument::create_document);
    ClassDB::bind_method(D_METHOD("set_document", "document"),
            &IvoryStretchyDocument::set_document);
    ClassDB::bind_method(D_METHOD("document"),
            &IvoryStretchyDocument::document);
    ClassDB::bind_method(D_METHOD("clear_mesh", "layer_index"),
            &IvoryStretchyDocument::clear_mesh);
    ClassDB::bind_method(D_METHOD("add_point", "layer_index", "point"),
            &IvoryStretchyDocument::add_point);
    ClassDB::bind_method(D_METHOD("move_point", "layer_index", "point_index", "point"),
            &IvoryStretchyDocument::move_point);
    ClassDB::bind_method(D_METHOD("finish_triangle", "layer_index", "point_indices"),
            &IvoryStretchyDocument::finish_triangle);
    ClassDB::bind_method(D_METHOD("add_layer", "id", "name", "texture_path"),
            &IvoryStretchyDocument::add_layer);
    ClassDB::bind_method(D_METHOD("add_bone", "start", "end"),
            &IvoryStretchyDocument::add_bone);
    ClassDB::bind_method(D_METHOD("rotate_bone", "bone_index", "tip"),
            &IvoryStretchyDocument::rotate_bone);
    ClassDB::bind_method(D_METHOD("set_parameter_value", "parameter_index", "value"),
            &IvoryStretchyDocument::set_parameter_value);
}

Dictionary IvoryStretchyDocument::create_document() const {
    Dictionary out;
    out["format"] = "stretchy.standalone.v1";
    out["model_name"] = "character";
    out["layers"] = Array();
    out["armature"] = Array();
    Dictionary param_angle_x;
    param_angle_x["id"] = "ParamAngleX";
    param_angle_x["name"] = "Angle X";
    param_angle_x["min"] = -30.0;
    param_angle_x["max"] = 30.0;
    param_angle_x["value"] = 0.0;

    Dictionary param_angle_y;
    param_angle_y["id"] = "ParamAngleY";
    param_angle_y["name"] = "Angle Y";
    param_angle_y["min"] = -30.0;
    param_angle_y["max"] = 30.0;
    param_angle_y["value"] = 0.0;

    Dictionary param_mouth_open_y;
    param_mouth_open_y["id"] = "ParamMouthOpenY";
    param_mouth_open_y["name"] = "Mouth open";
    param_mouth_open_y["min"] = 0.0;
    param_mouth_open_y["max"] = 1.0;
    param_mouth_open_y["value"] = 0.0;

    Array parameters;
    parameters.append(param_angle_x);
    parameters.append(param_angle_y);
    parameters.append(param_mouth_open_y);
    out["parameters"] = parameters;

    Array canvas_size;
    canvas_size.append(1920.0);
    canvas_size.append(1080.0);
    out["canvas_size"] = canvas_size;
    return out;
}

void IvoryStretchyDocument::set_document(const Dictionary &document) {
    document_ = document.duplicate(true);
}

Dictionary IvoryStretchyDocument::document() const {
    return document_.duplicate(true);
}

Dictionary IvoryStretchyDocument::layer_at(int layer_index) const {
    const Array layers = document_.get("layers", Array());
    if (layer_index < 0 || layer_index >= layers.size()) return Dictionary();
    return layers[layer_index].get_type() == Variant::DICTIONARY
            ? Dictionary(layers[layer_index]) : Dictionary();
}

Array IvoryStretchyDocument::points_of(const Dictionary &layer) {
    return layer.get("points", Array());
}

Array IvoryStretchyDocument::triangles_of(const Dictionary &layer) {
    return layer.get("triangles", Array());
}

Dictionary IvoryStretchyDocument::clear_mesh(int layer_index) {
    Dictionary layer = layer_at(layer_index);
    if (layer.is_empty()) return Dictionary();
    layer["points"] = Array();
    layer["triangles"] = Array();
    Array layers = document_.get("layers", Array());
    layers[layer_index] = layer;
    document_["layers"] = layers;
    return layer;
}

Dictionary IvoryStretchyDocument::add_point(int layer_index, const Vector2 &point) {
    Dictionary layer = layer_at(layer_index);
    if (layer.is_empty()) return Dictionary();
    Array points = points_of(layer);
    Array new_point;
    new_point.append(point.x);
    new_point.append(point.y);
    points.append(new_point);
    layer["points"] = points;
    Array layers = document_.get("layers", Array());
    layers[layer_index] = layer;
    document_["layers"] = layers;
    Dictionary result;
    result["layer"] = layer;
    result["index"] = points.size() - 1;
    return result;
}

Dictionary IvoryStretchyDocument::move_point(int layer_index, int point_index, const Vector2 &point) {
    Dictionary layer = layer_at(layer_index);
    Array points = points_of(layer);
    if (layer.is_empty() || point_index < 0 || point_index >= points.size()) return Dictionary();
    Array moved_point;
    moved_point.append(point.x);
    moved_point.append(point.y);
    points[point_index] = moved_point;
    layer["points"] = points;
    Array layers = document_.get("layers", Array());
    layers[layer_index] = layer;
    document_["layers"] = layers;
    return layer;
}

Dictionary IvoryStretchyDocument::finish_triangle(int layer_index, const Array &point_indices) {
    Dictionary layer = layer_at(layer_index);
    Array points = points_of(layer);
    if (layer.is_empty() || point_indices.size() != 3) return Dictionary();
    for (int i = 0; i < point_indices.size(); ++i) {
        const int index = int(point_indices[i]);
        if (index < 0 || index >= points.size()) return Dictionary();
    }
    Array triangles = triangles_of(layer);
    triangles.append(point_indices.duplicate(true));
    layer["triangles"] = triangles;
    Array layers = document_.get("layers", Array());
    layers[layer_index] = layer;
    document_["layers"] = layers;
    return layer;
}

Dictionary IvoryStretchyDocument::add_layer(const String &id, const String &name, const String &texture_path) {
    Array layers = document_.get("layers", Array());
    Dictionary layer;
    layer["id"] = id;
    layer["name"] = name;
    layer["visible"] = true;
    layer["texture_path"] = texture_path;
    layer["points"] = Array();
    layer["triangles"] = Array();
    layers.append(layer);
    document_["layers"] = layers;
    return layer;
}

Dictionary IvoryStretchyDocument::add_bone(const Vector2 &start, const Vector2 &end) {
    Array armature = document_.get("armature", Array());
    const int id = armature.size();
    Dictionary bone;
    bone["id"] = id;
    bone["name"] = String("Bone ") + String::num_int64(id + 1);
    bone["x"] = start.x;
    bone["y"] = start.y;
	bone["length"] = std::max(8.0, (double)start.distance_to(end));
    bone["angle"] = (end - start).angle();
    armature.append(bone);
    document_["armature"] = armature;
    return bone;
}

Dictionary IvoryStretchyDocument::rotate_bone(int bone_index, const Vector2 &tip) {
    Array armature = document_.get("armature", Array());
    if (bone_index < 0 || bone_index >= armature.size()) return Dictionary();
    Dictionary bone = armature[bone_index];
    const Vector2 root(float(bone.get("x", 0.0)), float(bone.get("y", 0.0)));
    const Vector2 delta = tip - root;
    bone["angle"] = delta.angle();
	bone["length"] = std::max(4.0, (double)delta.length());
    armature[bone_index] = bone;
    document_["armature"] = armature;
    return bone;
}

Dictionary IvoryStretchyDocument::set_parameter_value(int parameter_index, double value) {
    Array parameters = document_.get("parameters", Array());
    if (parameter_index < 0 || parameter_index >= parameters.size()) return Dictionary();
    Dictionary parameter = parameters[parameter_index];
    const double minimum = double(parameter.get("min", 0.0));
    const double maximum = double(parameter.get("max", 1.0));
	parameter["value"] = std::clamp(value, minimum, maximum);
    parameters[parameter_index] = parameter;
    document_["parameters"] = parameters;
    return parameter;
}
