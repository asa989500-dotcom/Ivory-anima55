#!/usr/bin/env python3
"""Find class names that collide with a Godot native class.

`comic_panels.gd` declared `class Panel extends RefCounted`. `Panel` is a
Godot native class — a Control that draws a background — and this cost four
errors in one file that was otherwise correct:

    Line 39:  Class "Panel" hides a native class.
    Line 56:  Cannot assign a value of type Panel to variable "out"
              with specified type Panel.
    Line 72:  ... to variable "one" with specified type Panel.
    Line 239: ... to variable "p" with specified type Panel.

The three that follow are the expensive part, and they are the reason this
checker exists rather than a note in a review. `Panel.new()` inside that file
resolved to the *engine's* Panel, so every constructor built a Control while
every annotation still meant the inner class — and the parser reported the
mismatch with **the two names spelled identically in the same sentence**.
Nothing in that message points at the declaration forty lines up. A person
reads "cannot assign a value of type Panel to a variable of type Panel",
concludes the compiler is broken, and starts changing correct code.

One shadowed name, four errors, none of which said what was wrong. That is
exactly the shape of fault a checker is for: cheap to detect, and expensive
to find by hand precisely because the message misdirects.

## What is checked

Both kinds of name a file can declare:

* `class_name X` at the top of a file — a global name, so a collision here
  breaks every file in the project rather than one.
* `class X extends ...` inside a file — the case above.

## On the list below

It is not all ~900 of Godot's classes and does not try to be. It is every
native name that a person might *plausibly* reach for when naming something
of their own: ordinary English nouns like Panel, Timer, Label, Curve, Image,
Skeleton, Bone, Camera, Material, Line. Nobody is going to call an inner
class `VisualShaderNodeVec4Parameter` by accident, and a list padded with
those would take longer to maintain and catch nothing more.

So a clean run means "no collision with a name you might plausibly have
picked", not "no collision with anything in the engine". That is honest, and
it is still the whole of the risk in practice — the collisions that actually
happen are the short ordinary words, because those are the words a person
reaches for when naming a rectangle on a comic page.
"""
import re
import sys
import pathlib

CLASS_NAME = re.compile(r'^class_name\s+([A-Za-z_]\w*)')
INNER = re.compile(r'^(\s*)class\s+([A-Za-z_]\w*)')

# Godot 4 native classes whose names are ordinary enough to be picked by
# accident. Grouped so a name can be added where it belongs.
NATIVE = set("""
Panel PanelContainer Label Button Container Control Window Popup Tree
Range Slider Separator Timer Line LineEdit TextEdit RichTextLabel
Node Node2D Node3D Object Resource RefCounted Script Shortcut

Image ImageTexture Texture Texture2D Texture3D Material Shader Mesh
ArrayMesh MeshInstance2D MeshInstance3D Font FontFile Theme StyleBox
Gradient Curve Curve2D Curve3D Path Path2D Path3D Polygon2D Line2D
Sprite2D Sprite3D Camera2D Camera3D Viewport Environment World2D World3D

Animation AnimationPlayer AnimationTree Skeleton2D Skeleton3D Bone2D
BoneAttachment3D Skin SkinReference Tween Marker2D Marker3D

Time OS Engine Performance Input InputEvent Translation TranslationServer
JSON XMLParser FileAccess DirAccess Thread Mutex Semaphore Expression
RandomNumberGenerator Crypto HashingContext StreamPeer PacketPeer

Shape2D Shape3D RectangleShape2D CircleShape2D Area2D Area3D Joint2D
Joint3D Generic6DOFJoint3D PinJoint2D PinJoint3D SpringArm3D

AudioStream AudioStreamPlayer AudioServer AudioEffect
Light2D Light3D LightmapGI Decal Sky Fog FogVolume GPUParticles2D

Callable Signal Variant Dictionary Array Color Vector2 Vector3 Vector4
Rect2 Rect2i Transform2D Transform3D Basis Quaternion Plane AABB
Projection StringName NodePath PackedScene SceneTree

TileMap TileSet GridMap Label3D Sprite SubViewport CanvasItem CanvasLayer
CanvasGroup BackBufferCopy ColorRect TextureRect NinePatchRect
ScrollContainer SplitContainer BoxContainer GridContainer FlowContainer
TabContainer MarginContainer CenterContainer AspectRatioContainer
""".split())


def scan(path, root):
    """Every declared name in this file that collides, as (line, kind, name)."""
    out = []
    rel = path.relative_to(root).as_posix()
    lines = path.read_text(encoding='utf-8').split('\n')
    for i, line in enumerate(lines, 1):
        # A commented-out declaration is not a declaration.
        if line.lstrip().startswith('#'):
            continue
        m = CLASS_NAME.match(line)
        if m and m.group(1) in NATIVE:
            out.append((rel, i, 'class_name', m.group(1)))
            continue
        m = INNER.match(line)
        if m and m.group(2) in NATIVE:
            out.append((rel, i, 'class', m.group(2)))
    return out


def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.')
    found = []
    for folder in ('scripts', 'tests'):
        base = root / folder
        if not base.exists():
            continue
        for path in sorted(base.rglob('*.gd')):
            found.extend(scan(path, root))

    for rel, line, kind, name in found:
        where = 'global name' if kind == 'class_name' else 'inner class'
        print('%s:%d  %s "%s" hides the Godot native class of that name. '
              'Rename it — Godot resolves "%s.new()" to the engine\'s class, '
              'so every use of yours fails with both spelled the same.'
              % (rel, line, where, name, name))
    print('--- %d class names hiding a native class ---' % len(found))
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main())
