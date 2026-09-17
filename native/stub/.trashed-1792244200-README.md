# The bench stub

A minimal stand-in for godot-cpp, so the test benches under
`native/ivory/tests` compile and run without the engine.

It is deliberately not a full implementation and it is not used in any build of
the app. It provides only what the files under test actually touch — `Vector2`,
`Rect2`, the packed arrays, `String` — which is why it is a few hundred lines
rather than a dependency.

The reasoning: a bench that needs godot-cpp checked out and built is a bench
that gets run once and then never again, and geometry, checksums and plural
rules are exactly the code that needs checking on every change.

    cd ../ivory/tests && ./run_tests.sh ../stub
