# STAGE 134 — High Fidelity Puppet Warp

- Native ARAP now solves on the actual triangle-edge topology, including the alternating cell diagonals, instead of only the four-neighbour raster graph.
- Triangle edges use cotangent weights, reducing horizontal/vertical bias and improving bends around elbows, faces, curved silhouettes and diagonal pulls.
- Native local/global iterations: 3 during drag, 8 on settle.
- Maximum warp mesh density raised from 88 to 112 cells across the long side; the denser mesh is only used when requested and is solved natively.
- GDScript fallback remains active and uses 2/3 and 6 iterations according to available headroom.
- Dijkstra pin-distance connectivity remains four-neighbour intentionally, so influence still follows the drawn mesh rather than cutting across raster gaps.
- The GDScript-to-native mesh transfer now includes the real triangle list.
