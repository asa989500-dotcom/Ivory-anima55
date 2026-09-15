#pragma once
#include "godot_cpp/variant/all.hpp"

// godot-cpp supplies DEFVAL for default arguments on bound methods.
// The stub only needs it to parse; nothing here inspects the value.
#ifndef DEFVAL
#define DEFVAL(x) (x)
#endif
