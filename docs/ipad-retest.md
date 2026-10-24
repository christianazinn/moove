# iPad retest: Saturday afternoon

_For Lisa, on Rio's Mac + iPad Pro, after pulling today's `main`. By lisa's agent. About 30 minutes. It covers what changed after your morning scan (#267): walls (#269, #280), scanned spots (#268), shape sanity (#273), detector boxes (#272), Inventory (#271), sweep renames (#270), more voxel kinds (#284), the Zillow button (#266), Pack (#283), large text (#265) and close-up asks (#279)._

Each check gives the taps, the **Expected** result, and **Report if wrong**. Post reports on #267 (or a new issue) with a screenshot or screen recording. Name the piece, what it was drawn as, and where it should be.

## Setup (5 min)
1. On Rio's Mac: `cd <moove repo> && git checkout main && git pull`, then `cd ios && xcodegen`.
2. Open `Moove.xcodeproj` and pick the iPad Pro. Run **Product → Clean Build Folder**, then **Run**.
3. If the app still looks old (no **Hide room** in the room ⋯ menu, no origin chips), delete Moove from the iPad and Run again. **Do this before the fresh scan.** Deleting the app also deletes the scans saved on the iPad, and the dollhouse then falls back to the uploaded copy.
4. Settings (gear, top right) → Backend → Data source **SpacetimeDB (live)** → Database **Live (moove)** for the scan checks.
5. **Worker restart (Christian's).** The #270 sweep and vision size checks (a tall lamp can't be renamed "pillow") only run once Christian's worker is pulled and restarted (`git pull && npm ci`, then `run-worker.sh`). Ask him on #2 before check 6. Until then, check 6's names may still be wrong. The voxel drawing (#273) is on the iPad and works either way.

## Checks, in app order

### 1. Hide old test rooms
- **Taps:** Items → Inventory → on each old room's header tap **⋯** (or long-press the header) → **Hide room**.
- **Expected:** the room disappears from Inventory, its totals, Review, the Scan hero, New Home and Pack. **Show hidden rooms (N)** appears at the bottom, and **Unhide** brings a room back.
- **Report if wrong:** which screen still shows the hidden room, plus a screenshot.

### 2. Fresh scan
- **Taps:** Scan → **Scan a room** → sweep the room slowly → **Done** → **Looks right: check photos** → **Add N items**.
- **Expected:** "Scan · Done" and "N items added". The "Also found: …" chip lists detector finds. If something was impossible, "N objects looked wrong and were skipped" appears.
- **Report if wrong:** the step where it stuck, plus the on-screen message.

### 3. Scan finished dollhouse
- **Taps:** stay on the finished page and drag the dollhouse around a full turn.
- **Expected:**
  - The two walls farthest from the camera are full height. The near walls are cut low (1.1 m). Which walls are tall changes as you turn.
  - Tall walls are one continuous wall: **no strip or rail at 1.1 m** and nothing drawn twice at the corners.
  - Curtains hang at the **top of the window** on tall walls, and at the cut on low walls.
  - Pieces sit **where they stood** in the room, and small things stay on the furniture they were on.
  - The caption reads "**N placed by estimate**", and N counts only pieces without a scanned spot.
- **Report if wrong:** the wall or piece, which camera angle, plus a screenshot. For a misplaced piece, say where it really stood.

### 4. Items → room 3D: Voxel vs Plan
- **Taps:** Items → Inventory → the new room's **3D** pill. Switch the style picker between **Voxel** and **Plan**.
- **Expected:** Voxel is the dollhouse from check 3. Plan is the floor plan with RoomPlan's raw boxes, top down. Use the two to tell the errors apart:
  - The **Plan box is wrong** (wrong size, spot or label): that's a scan error.
  - The **Plan box is right but the voxel piece is wrong**: that's a model error.
- **Report if wrong:** the piece, its Plan box (size, spot), what Voxel drew, and which of the two errors it is. Screenshots of both.

### 5. Inventory: origin chips, "was: …", dates, Demo tag
- **Taps:** Items → Inventory.
- **Expected:**
  - The newest room is on top, with the scan time under its header ("Today 15:42").
  - Rooms from **Load demo scan** show a **Demo** tag, and joined rooms say "Shared by …".
  - Every row has one chip: **Scanned**, **From photos**, **Added by photo** or **Shared**.
  - A renamed scanned item reads, for example, "Lamp · was: storage".
- **Report if wrong:** the item, its chip, what it should be, plus a screenshot.

### 6. Misread pieces
- **Taps:** the 3D pill → **Voxel**. Find the pieces that were wrong this morning.
- **Expected:**
  - A table that RoomPlan boxed as storage is drawn as a **table**, not a cabinet.
  - The tall thin "pillow" is drawn as a **floor lamp**. With the restarted worker (setup step 5), it also keeps its lamp name.
  - Every piece fills its scanned box, so nothing is too big or too small.
  - Bins, baskets, trash cans, clocks, a stroller, crib, ladder or trunk are drawn as themselves, not a kraft box (#284). Small things like balls, helmets and yoga mats are still boxes, and that's known.
- **Report if wrong:** the piece, what it was drawn as, its name in Inventory, plus a screenshot (Voxel and 3D).

### 7. Detector pieces: spot, facing, duplicates
- **Taps:** same view. Look at the pieces from the "Also found" chip (bike, plant, guitar, ottoman…).
- **Expected:** each piece sits on the real furniture, not forward of it toward where you stood. Pieces against a wall face into the room. The ottoman appears **once**.
- **Report if wrong:** the piece, which way it faced or how far off it was, and whether it shows twice. Screenshot.

### 8. Move → New Home: "Paste a Zillow link" and "Change home"
- **Taps:** Move → **New Home**. On the picker, tap **Paste a Zillow link** (at the top), paste a Zillow URL, optionally add a floor-plan screenshot → **Build floor plan** → **Use this home**. Then tap **Change home** (top left) and pick **Use this home** on the demo house.
- **Expected:** the button is easy to find on the picker, and again under the title once a home is chosen. The address comes from the link. With no worker, the plan is labeled estimated.
- **Report if wrong:** the step, plus a screenshot or the error text.

### 9. Fly-in: from scanned spots, and smoothness
- **Taps:** on the chosen home, watch the fly-in, then tap **Fly in** to replay it. Keep about 20 items (mark more as keep in Items → Review if needed).
- **Expected:** pieces lift from where they stood in the scanned room drawn beside the house, arc over the walls and land. No stutter or long freeze with ~20 items. The tall/low walls follow the camera here too.
- **Report if wrong:** the item count, where it stuttered (start, mid-arc, landing), and a screen recording.

### 10. Scan home hero
- **Taps:** Scan tab. Watch the turning dollhouse at the top for one full orbit.
- **Expected:** a smooth turn with no hitch when the walls switch between tall and low.
- **Report if wrong:** a screen recording, plus where in the turn it hitched.

### 11. Pack
- **Taps:** Move → **Pack**. Open a box, then tap **Print labels** → **4 × 6 in labels** or **Letter, 2 per page**.
- **Expected:**
  - Box cards are colored by room (Bedroom and Bedroom 2 differ), each with a reason ("Fragile: wrapped…").
  - Box detail shows a voxel model on each line.
  - The labels PDF opens in the share sheet, with the room band, a big number and a QR code.
  - Bought items appear under **Delivered to your new home**.
  - Hidden rooms stay out.
- **Report if wrong:** the box number, what's off (density, colors, a model that doesn't match), plus a screenshot or the PDF.

### 12. Summary
- **Taps:** Summary tab → scroll to **Agents kept you safe**.
- **Expected:** the scam deal blocked, the approvals, sentimental items left to you, and spend against the caps, with **Simulated** tags where simulated.
- **Report if wrong:** the line that's wrong or missing, plus a screenshot.

### 13. Sell & Buy at the largest text size
- **Taps:** iPad Settings → Accessibility → Display & Text Size → **Larger Text** → turn it on and drag to the maximum. In Moove, open Sell & Buy → **Listings**, **Shopping**, **Approvals**, **Spending**.
- **Expected:** no clipped prices or buttons. Stat strips stack, and SIMULATED pills stay readable. Turn Larger Text back off afterwards.
- **Report if wrong:** the screen and element, plus a screenshot.

### 14. Optional: close-up ask (#279)
- **Taps:** Items → Review, then the **A photo would help** section (it shows only for valuable items vision wasn't sure about).
- **Expected:** the item's detail says "Moove isn't sure which model this is…", and **Add another photo** re-identifies it.
- **Report if wrong:** the item, plus a screenshot.

### 15. Review: deck and board (Lisa's redesign)
- **Taps:** Items → Review. If any item needs you (undecided or sentimental), drag its card right, left, up and down slowly without letting go, then swipe it for real; tap **Undo**; then decide it with a button under the card. Below, look at **Where it goes**, then drag a row from one column onto another column's tile.
- **Expected:**
  - The card tilts and glows in the direction's color with a KEEP / SELL / DONATE / TRASH stamp; letting go early springs it back. A real swipe flies it off with a tap of haptics, and "2 of 3" counts up. With Reduce Motion on (Settings → Accessibility → Motion) there's no tilt.
  - On iPad, the four columns (Keep, Sell, Donate, Trash) sit side by side, each with its items, the agent's reason and a ⇄ change menu. Dropping a row on another tile moves it there.
  - With a saved New Home layout, Keep's rows are grouped by the room they go to ("→ Bedroom").
  - When nothing needs you, the board is at the top with "Nothing needs you".
- **Report if wrong:** the card or column, plus a screen recording (the swipe feel is what we can't check in CI).

## If merged (check `gh pr list` before you start; skip any that are still open)
- **#286, Pack truck in 3D:** Move → Pack → Truck and crew → **See it in 3D** → **Load the truck**. **Expected:** furniture goes in first against the cab, then boxes, with nothing overlapping. Tapping a piece shows its load order. **Report:** the piece that clips or floats, plus a screenshot. (If the 3D says a 10 ft truck while the card says Cargo van, that's known.)
- **#285, mover quotes:** Pack → Truck and crew → **Get mover quotes**. **Expected:** three cards, each tagged **Estimate**, plus "Estimates from published rates. Call to book." Offline, they're labeled "Estimated on this phone". **Report:** the card, plus a screenshot.
- **#274 (Rio), bunk beds:** a bed 1.2 m or taller is drawn as a bunk bed with a ladder. **Report:** a screenshot.
