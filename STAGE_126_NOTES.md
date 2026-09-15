# STAGE 126 — WORLD-SPACE RIG OVERLAY FIX

## Fixed
- Bone overlay coordinates were being converted to screen space even though the overlay is already a child of the transformed `world` node.
- This caused the skeleton to receive the camera transform twice, producing the floating/offset behaviour during zoom, pan, and rotation.
- Bone and held-joint overlay drawing now stays in world/canvas coordinates, so it remains locked to the artwork.

## Visual polish
- Reduced the filled bone body and line weight so the rig reads more like a light pencil construction drawing on the canvas instead of a heavy floating UI object.
- Joint rings were slightly reduced to keep the drawing visible.

## Performance
- The fix removes extra coordinate conversion work from every bone endpoint and avoids any new per-frame allocations.
