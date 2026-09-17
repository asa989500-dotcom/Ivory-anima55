#pragma once

#include "ffmpeg.hpp"
#include "ffmpeg_helpers.hpp"

#include <cmath>
#include <godot_cpp/classes/audio_stream_wav.hpp>
#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>


using namespace godot;

class GoZenAudio : public Resource {
	GDCLASS(GoZenAudio, Resource);

  private:
	static PackedByteArray _get_audio(AVFormatContext*& format_ctx, AVStream*& stream, bool stereo);

	static inline void _log(String message) { UtilityFunctions::print("GoZenAudio: ", message, "."); }
	static inline bool _log_err(String message) {
		UtilityFunctions::printerr("GoZenAudio: ", message, "!");
		return false;
	}

  public:
	static PackedByteArray get_audio_data(String file_path, int stream_index = -1, bool stereo = true);

	// Decodes any audio FFmpeg can read straight into a plain PCM16 WAV file,
	// a packet at a time, without ever holding the whole track in memory.
	//
	// This is what makes a feature-length import possible on a phone.
	// get_audio_data() above returns the entire decoded track as one array:
	// an hour of stereo audio is roughly six hundred megabytes, which an
	// Android process will not be given. Writing as we decode costs a
	// constant few kilobytes no matter how long the file is.
	//
	// Returns a Dictionary: ok, rate, channels, frames, seconds, error.
	static Dictionary decode_to_wav(String source_path, String out_path, int rate = 48000,
									int channels = 2);

  protected:
	static void _bind_methods();
};
