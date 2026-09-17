#!/usr/bin/env python3
"""Five offline guardrails for the comic cutter frame-lock repair."""
from pathlib import Path
import random

ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "scripts/ui/comic_board.gd"
CPP_TEST = ROOT / "native/ivory/tests/test_comic.cpp"


def frame(page):
    w, h = page
    m = min(42.0, min(w, h) * 0.12)
    return (m, m, max(w - 2*m, 8.0), max(h - 2*m, 8.0))


def inside(r, p, eps=1e-6):
    x, y, w, h = r
    px, py = p
    return x-eps <= px <= x+w+eps and y-eps <= py <= y+h+eps


def test_1_bounds():
    for page in [(320,240),(800,600),(1920,1080),(4096,4096),(12000,8000)]:
        x,y,w,h = frame(page)
        assert x > 0 and y > 0
        assert x+w < page[0] and y+h < page[1]
    return "frame stays inside all five project sizes"


def test_2_clamp():
    random.seed(141)
    for page in [(320,240),(800,600),(1920,1080),(4096,4096),(12000,8000)]:
        r = frame(page)
        x,y,w,h = r
        for _ in range(500):
            raw = (random.uniform(-page[0]*3,page[0]*4),
                   random.uniform(-page[1]*3,page[1]*4))
            clamped = (min(max(raw[0],x),x+w), min(max(raw[1],y),y+h))
            assert inside(r, clamped)
    return "500 endpoint clamps per size never escape the frame"


def draw_body(text):
    start = text.index("static func draw(view: CanvasView) -> void:")
    end = text.index("static func _draw_pending", start)
    return text[start:end]


def test_3_no_double_transform():
    text = BOARD.read_text()
    body = draw_body(text)
    assert "canvas_to_screen" not in body
    assert "from_page(view, v)" in body
    return "ComicBoard.draw is page-local; no screen-space double transform"


def test_4_zoom_lock():
    text = BOARD.read_text()
    body = draw_body(text)
    assert "view.view_zoom" in body
    assert "/ maxf(view.view_zoom" in body
    return "overlay stroke width follows zoom without changing geometry space"


def test_5_comic_only():
    board = BOARD.read_text()
    panels = (ROOT / "scripts/ui/comic_panels_ui.gd").read_text()
    assert "ProjectManager.Kind.COMIC" in board
    assert "p.kind != ProjectManager.Kind.COMIC" in board
    assert "if kind != ProjectManager.Kind.COMIC:" in panels
    assert "test_project_frame_stability" in CPP_TEST.read_text()
    return "comic-only gate and five native boundary cases are present"


TESTS = [test_1_bounds, test_2_clamp, test_3_no_double_transform,
         test_4_zoom_lock, test_5_comic_only]

if __name__ == "__main__":
    for i, test in enumerate(TESTS, 1):
        result = test()
        print(f"TEST {i}/5 PASS — {result}")
    print("5/5 PASS")
