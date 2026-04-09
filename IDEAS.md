# Conky Future Ideas

## Multi-line CPU graph (one line per core)

Conky does not support overlapping graphs natively. Two implementation paths:

### Option A — Stacked mini-graphs (simple)
One small `${cpugraph cpuN}` per core, stacked tightly with no spacing.
- 16 threads × 6px = ~96px total height
- Easy to implement
- Rows are separate, not overlaid

## Improve pixel art eye animation with Cairo

The current eye sprite uses Unicode block characters (█▀▄░▒▓), limited to a coarse grid. Replacing it with Cairo-based drawing would give full per-pixel control.

With Cairo (via `lua_draw_hook_post` in bars.lua):
- Draw a proper pixel-art sprite at any resolution (e.g. 48×16 px)
- Authentic pixel look with no font metric constraints
- Full animation control: smooth pupil movement, iris texture, eyelash detail
- Requires hardcoding the Y pixel position of the sprite in the conky window

---

## Multi-line CPU graph (one line per core)

Conky does not support overlapping graphs natively. Two implementation paths:

### Option A — Stacked mini-graphs (simple)
One small `${cpugraph cpuN}` per core, stacked tightly with no spacing.
- 16 threads × 6px = ~96px total height
- Easy to implement
- Rows are separate, not overlaid

### Option B — Lua + Cairo custom drawing (complex)
Draw a proper multi-line chart using the Cairo graphics library inside `bars.lua`.
- Each core gets its own color, all drawn in the same graph area
- Requires a history ring buffer per core (~285 data points × 16 cores)
- Requires hardcoding the Y pixel position of the graph in the conky window
- ~80–100 lines of Lua/Cairo code
