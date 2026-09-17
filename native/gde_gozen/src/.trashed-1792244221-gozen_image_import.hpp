#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
}

class GoZenImageImport : public godot::RefCounted {
    GDCLASS(GoZenImageImport, godot::RefCounted)
protected:
    static void _bind_methods();
public:
    static godot::Dictionary decode(const godot::String &path, int max_side=8192);
    static godot::Dictionary inspect(const godot::String &path);
};
