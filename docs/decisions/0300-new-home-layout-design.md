# 0300: New Home lays rooms out by interior-design rules, from the rooms you pick

**Context.** Lisa on the iPad (Oct 24): "do better research on how to do interior design when you are importing items into the new house. now when i do it there are multiple beds and the items are just randomly scattered." Two causes. New Home took the kept items of every scanned room, so three test scans of one bedroom brought three beds. And `LayoutSolver` put each piece on the first free wall spot of a room that suited its category, with no idea of groups, facing or clearances. Lisa also asked: "right now for the move new home tab it's importing all the items from all the rooms that have been scanned. add an option to import items from only the rooms you select."

**Decision.**

*Which items move* (MooveKit `MovingRooms`, New Home's "Moving from" row and picker):
- By default only the newest scan of each room name moves. Older rooms with the same name are treated as re-scans. A room with nothing kept counts as picked.
- **Moving from N rooms · M items ›** opens a checklist of every visible scanned room (name, scan time, kept-item count, Demo tag) with Select all and None. The picks are saved on this device (UserDefaults `moove.newHome.rooms`, like the hidden rooms in #271), and ids of deleted rooms are dropped. With no rooms picked, New Home shows a "Choose rooms" empty state.
- If two same-named rooms are both picked, near-identical items in them (same role, sizes within 15% or 12 cm) are deduped one for one. Rooms with different names are never deduped, since two kids' rooms can have the same bed.
- Beds go one per bedroom, biggest bed in the biggest bedroom. A second twin or bunk (≤ 1.15 m wide) may join the smallest bedroom that already holds one. Any other beds go to `LayoutOption.stored` ("Storage" in the pieces list) and are never put in a living room. A plan with only one room (a scan's own dollhouse) takes every bed.

*Designer layout* (`Designer`, `DesignRole`, `WalkGrid`): each piece gets a role (`VoxelModels.kind` + `PropPlacer.role` + name words; RoomPlan's plain "storage" box is classified by its shape; toilet / sink / bathtub come from category words, so this works before those voxel kinds exist). Pieces are then placed in function groups, anchor first, picking the lowest-cost of the candidate anchor spots (enumerated in a fixed order, so the result is deterministic):

| Group | Rule adopted | Source |
|---|---|---|
| Sleep | Headboard on a solid wall: penalized under a window, on the door wall, or with the foot pointing at the door. Prefer long walls, centered. | Feng shui "command position" (Homes & Gardens, Livingetc); designer guides |
| | Nightstands flank the bed at the head, 0–12" away. | Merrell et al. 2011, Table 1 (from Panero & Repetto) |
| | Bed sides reachable with ≥ 24" (0.6 m); 30–36" preferred; both sides for a double bed. | Bedroom clearance guides; Merrell Table 1 ("bed side 36"") |
| | Dresser on the wall facing the bed, ≥ 36" from its foot (drawers plus standing room), else a side wall. Wardrobes on a side wall. | Bedroom guides (36" in front of a dresser) |
| Living | Sofa faces the TV / media wall at 1.5–2.5× the screen diagonal (2× By function, 1.75× Compact, 2.25× Open). It is pushed back onto the far wall when the gap behind it would be too narrow to walk. No TV: sofa back on a long wall without a door. | TV distance guides (1.5–2.5× diagonal); Yu et al. 2011 ("couches face the TV") |
| | Coffee table 14–18" (0.35–0.45 m) in front of the sofa. | Havenly / Rayon living-room rules; Merrell Table 1 (16–18") |
| | Armchairs at the coffee table's ends facing in, or angled in at the sofa's end: a conversation group 4–8 ft (1.2–2.4 m) across. | Merrell 2011 conversation term (Panero & Repetto) |
| | Side table and floor lamp at the sofa's ends (lamps beside seating). Rug centered under the coffee table, under the front legs. The floor between the sofa and the TV is kept clear (no walkway or other furniture there). | Designer rules; Merrell emphasis / focal point |
| | TV on its stand, toward the back. A TV over a window is penalized (glare). | |
| Dining | Table in the middle of its zone, long axis along the room. Chairs on the long sides, then the ends, facing the table, tucked about 12 cm from it. 36" (0.9 m) from the table edge to walls and furniture (0.75 Compact, 1.0 Open). | NKBA kitchen planning guidelines (36" behind a seated diner); Merrell Table 1 ("dining table 36" all around") |
| Office | Desk on a wall with or beside a window (daylight), chair in front facing it, with room behind the chair. Not with your back to the door. In a shared room, away from what's already there. Bookshelf and lamp on the nearest free wall. | Designer rules; Merrell Table 1 ("seat 30" in front") |
| Kitchen / bath | Appliances cluster along the kitchen walls. Bathtub long side to the wall, in a corner. Toilet not in line with the door. Sink near the door. | |
| Everything | Circulation: a flood fill from each door on a 10 cm grid. Every room's doors stay connected, and each piece's use side stays reachable with a 0.6 m path (0.7 Open); 0.9 m (0.75 Compact, 1.0 Open) is preferred. Door keep-outs stay. No overlaps. Leftovers go on free walls near their group (spare chairs by the table, spare nightstands in bedrooms), and plants go by windows. | Merrell 2011 circulation term (free configuration space, connected components); NKBA 36" walkways |
| Small things | Placed next to the piece they belong on, so `PropPlacer` lifts them onto it: a lamp per nightstand, the monitor on the desk (before a TV can take it), books on the shelf, the TV on the stand or dresser. Art goes by the sofa or bed, a mirror by the dresser. | |

Styles: **By function** uses the full rules. **Compact** uses fewer rooms (the desk goes in the main bedroom, dining in the kitchen, a TV with no sofa faces the bed) and tighter clearances. **Open** uses more clearance, a longer viewing distance and centered wall spots, and spreads leftovers to the least crowded rooms. The API (`solve`, `solveAll`, `solve(_:style:around:)`) and its guarantees (no overlaps, inside rooms, doors clear, deterministic) are unchanged.

**Consequences.**
- About 1 s per `solveAll` on Linux debug for the demo house (6 rooms). It is much faster in an iOS release build. The walk check only runs on the 14 cheapest candidates per group.
- Not adopted from the literature: Merrell's visual balance, symmetry and Monte Carlo sampling, and Yu et al.'s simulated annealing. Fixed group templates plus a small deterministic search are easier to test and repeat in a live demo.
- A 3.6 m deep living room can't fit an armchair at each end of the coffee table, so the second one goes on a nearby wall.
- Pack still plans from every visible room (the Pack files were being edited in parallel). Making it follow the New Home picks is a follow-up.
- `LayoutPreview.svg` plus `MOOVE_LAYOUT_SVG_DIR=<dir> swift test --filter LayoutPreviewTests` write top-down SVGs of the test layouts for checking them by eye.

**Sources.**
- Merrell, Schkufza, Li, Agrawala, Koltun. "Interactive Furniture Layout Using Interior Design Guidelines." SIGGRAPH 2011. https://graphics.stanford.edu/projects/furniture/ (PDF: https://paulmerrell.org/furnitureLayout2.pdf): clearance, circulation, conversation (4–8 ft), pairwise (coffee table 16–18", nightstand 0–12"), balance, alignment, emphasis.
- Yu, Yeung, Tang, Terzopoulos, Chan, Osher. "Make It Home: Automatic Optimization of Furniture Arrangement." SIGGRAPH 2011. https://history.siggraph.org/?p=114673 : accessibility, visibility, pairwise relationships, "couches face the TV".
- NKBA Kitchen Planning Guidelines. https://kb.nkba.org/uploads/2022/05/Kitchen-Planning-Guidelines.pdf : 36" walkways, 42" where walkways meet, 36" behind a seated diner.
- Havenly, living room layout. https://havenly.com/blog/living-room-layout ; Rayon, living room rules. https://rayon.design/knowledge-base/living-room/rules : coffee table 14–18", seats 7–10 ft apart.
- Homes & Gardens, bed placement. https://homesandgardens.com/interior-design/bedrooms/where-should-a-bed-be-placed-in-a-room ; Livingetc, headboard wall. https://www.livingetc.com/news/bed-headboard-layout-tip : solid wall, not under a window, see the door but not in line with it.
- Bedroom clearance guide. https://checkout.mattressstoreslosangeles.com/blogs/mattress-buying-guide/how-to-arrange-bedroom-furniture : 24–36" beside the bed, 36" in front of a dresser, 30–36" main walkways.
