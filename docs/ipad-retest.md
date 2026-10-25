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
- **Taps:** Items → Inventory → in the **Rooms** chips at the top, tap each old room's **⋯** (or long-press its chip) → **Hide room**.
- **Expected:** the room disappears from Inventory, its totals, Review, the Scan hero and Move (the new home, boxes and truck). **Show hidden rooms (N)** appears at the bottom, and **Unhide** brings a room back.
- **Report if wrong:** which screen still shows the hidden room, plus a screenshot.

### 1b. Rename a room
- **Taps:** Items → Inventory → a room chip's **⋯** → **Rename room** → type "Sam's room" → **Save**.
- **Expected:** the chip, New Home's **Moving from** list, Pack's room rows and Review show "Sam's room" right away, and still do after quitting and reopening the app. (Until the module has `rename_room`, #370, the name is kept on this iPad only.)
- **Report if wrong:** which screen shows the old name.

### 2. Fresh scan
- **Taps:** Scan → **Scan a room** → sweep the room slowly → **Done** → **Looks right: check photos** → check the **Room** field at the top (change it with a chip or by typing) → **Add N items**.
- **Expected:** the Room field is prefilled from what was found (bed → "Bedroom", sofa/TV → "Living room", stove/fridge → "Kitchen", desk + monitor → "Office", nothing telling → "Room"), and says "Bedroom 2" if you already have a Bedroom (a hint offers the number when you type a taken name; keeping it is fine for a re-scan). "Scan · Done" and "N items added". The new room has that name in Inventory, New Home's **Moving from** and Pack. The "Also found: …" chip lists detector finds. If something was impossible, "N objects looked wrong and were skipped" appears.
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
- **Taps:** Items → Inventory → the new room's **3D** pill (on its chip in the Rooms strip). Switch the style picker between **Voxel** and **Plan**.
- **Expected:** Voxel is the dollhouse from check 3. Plan is the floor plan with RoomPlan's raw boxes, top down. Use the two to tell the errors apart:
  - The **Plan box is wrong** (wrong size, spot or label): that's a scan error.
  - The **Plan box is right but the voxel piece is wrong**: that's a model error.
- **Report if wrong:** the piece, its Plan box (size, spot), what Voxel drew, and which of the two errors it is. Screenshots of both.

### 5. Inventory: the binder (a page per function, items on shelves)
- **Taps:** Items → Inventory. Tap each colored index tab, then swipe the page left and right; tap an item on a shelf, then in its placard tap the story line and type "Grandma's, 1974", **Save**; long-press another item. Then rotate the iPad, try dark mode, the largest text size, and Reduce Motion.
- **Expected:**
  - A **Rooms** strip on top: one chip per room, newest scan first, with item count, scan time ("Today 15:42"), a **Demo** tag for **Load demo scan** rooms and "Shared by …" for joined ones, plus Share / **3D** / **⋯** (Add item here, Rename room, Hide room). Tapping a chip still narrows the binder to that room.
  - A binder: one page per function (Sleep, Work & study, …, biggest first, "Everything else" last). iPad: colored index tabs down the page's right edge; iPhone: folder tabs across the top that scroll sideways. Each tab says the name and count, and keeps its color (Sleep is always slate). The page heading is the name (serif) and "4 pieces · est. $610"; holes along the left edge.
  - Each page is a wall of chunky wooden shelves (5 cm blocks, grain, brackets): smallest things on the top planks, larger pieces sharing planks with them when they fit (each at its own size), beds/sofas/bookcases/floor lamps on the floor row. iPad fits about 6 per plank, iPhone 2–3; a plank rarely holds just one thing. Each item stands on the wood as its voxel model with a small hanging tag (name, price; a gold bookmark on possibly sentimental ones).
  - Swiping turns the page with a slide; with Reduce Motion it crossfades. An office chair is on Work & study, a nightstand on Sleep.
  - Tapping an item opens its placard: the model on a plinth, name, a short size line, the one-line story, price and origin chip, with **Open details**, **Fix it** and **Delete**. Your story replaces the auto one and stays after relaunch (this iPad only). Long-press still shows Open, Edit story, Rename, What is it?, Turn around, Rotate 90°, Not a real item, Delete item.
  - Largest text sizes: each page becomes a plain list. Dark mode: walnut shelves on a deep wall. VoiceOver: tabs read "Sleep, 4 pieces, page 1 of 6", each item is one button, three-finger swipe turns pages.
- **Report if wrong:** the item, its page or shelf, what it should be, plus a screenshot.

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

### 8. Move: "Paste a Zillow link" and "Change home"
- **Taps:** Move (one page, no New Home / Pack pills). On the picker at the top, tap **Paste a Zillow link**, paste a Zillow URL, optionally add a floor-plan screenshot → **Build floor plan** → **Use this home**. Then tap **Change home** (under the title) and pick **Use this home** on the demo house.
- **Expected:** the button is easy to find on the picker, and behind **Change home** once a home is chosen. The address comes from the link. With no worker, the plan is labeled estimated.
- **Report if wrong:** the step, plus a screenshot or the error text.

### 9. Fly-in: from scanned spots, and smoothness
- **Taps:** on the chosen home, watch the fly-in, then tap **Fly in** to replay it. Keep about 20 items (mark more as keep in Items → Review if needed).
- **Expected:** pieces lift from where they stood in the scanned room drawn beside the house, arc over the walls and land. No stutter or long freeze with ~20 items. The tall/low walls follow the camera here too.
- **Report if wrong:** the item count, where it stuttered (start, mid-arc, landing), and a screen recording.

### 10. Scan home hero
- **Taps:** Scan tab. Watch the turning dollhouse at the top for one full orbit.
- **Expected:** a smooth turn with no hitch when the walls switch between tall and low.
- **Report if wrong:** a screen recording, plus where in the turn it hitched.

### 11. Getting there: truck and boxes
- **Taps:** Move, scroll past the room shots to **Getting there**. Open a box, then tap **Print labels** → **4 × 6 in labels** or **Letter, 2 per page**.
- **Expected:**
  - Box cards are plain kraft with a small room dot (Bedroom and Bedroom 2 differ) and the box number; the reason is inside the box ("Fragile: wrapped…").
  - Box detail shows a voxel model on each line.
  - The labels PDF opens in the share sheet, with the room band, a big number and a QR code.
  - Bought items appear under **Delivered to your new home**.
  - Hidden rooms stay out.
  - Furniture notes, Supplies, Schedule and Pieces are folded at the bottom (closed); tapping a header opens it.
- **Report if wrong:** the box number, what's off (density, colors, a model that doesn't match), plus a screenshot or the PDF.

### 12. Agents kept you safe and the kg banner
- **Taps:** Sell & Buy → **Agents** → scroll to **Agents kept you safe** (under "Needs your OK"). Then Items → **Review** and tap the green "kept out of landfill" strip at the top.
- **Expected:** the scam deal blocked, the approvals, sentimental items left to you, and spend against the caps, with **Simulated** tags where simulated. On Review: "~49 kg kept out of landfill", "4 items sold or donated", and a sheet explaining the estimate with Sell / Donate counts. There is no Summary tab (4 tabs).
- **Report if wrong:** the line that's wrong or missing, plus a screenshot.

### 13. Sell & Buy at the largest text size
- **Taps:** iPad Settings → Accessibility → Display & Text Size → **Larger Text** → turn it on and drag to the maximum. In Moove, open Sell & Buy → **Listings**, **Shopping**, **Agents** (scroll all the way down to the receipts).
- **Expected:** no clipped prices or buttons. Stat strips stack, and SIMULATED pills stay readable. On Listings the posters go to one column and hang straight (no tilt), and the flyer's Live / Listed / Sold stack. Turn Larger Text back off afterwards.
- **Report if wrong:** the screen and element, plus a screenshot.

### 13b. Listings: the poster wall (Lisa's redesign)
- **Taps:** Sell & Buy → **Listings**. Look at the wall, tap a poster and go back, long-press one, then pull down. Then turn on Dark Mode (Control Center) and look again.
- **Expected:**
  - A flyer at the top with **Live**, **Listed** and **Sold**, then the groups (Needs approval, Live, Drafting, Sold, Not posted), each a tidy **three-column** wall of posters on iPad (two on iPhone). Each poster has a pin or tape, a banner ("FOR SALE", "MUST GO"…), the item's voxel model, a bold title, a big price, a status stamp, the SIMULATED pill and blank tear-off tabs. Posters tilt a little (at most 1.5°) but the columns stay aligned.
  - Stamps: NEEDS YOUR OK, POSTED (never LIVE on a simulated post), DRAFTING (a dashed, faded sketch), a big diagonal SOLD, FAILED (torn corner plus the reason), DENIED (crossed out).
  - Pressing a poster lifts and straightens it; on iPadOS 18 it zooms open into the listing. Long-press shows Copy listing text, Cross-post, View simulated listing page (and Approve and post / Deny on a NEEDS YOUR OK poster). Pulling down re-pins the posters one after another. With Reduce Motion on they're just there.
  - Dark Mode: the wall goes near-black and the posters keep their colors.
  - VoiceOver: each poster is one element, read as title, price, status and "simulated listing, not on eBay".
- **Report if wrong:** the poster, what's off (overlap, clipped text, a color that's hard to read), plus a screenshot.

### 14. Optional: close-up ask (#279)
- **Taps:** Items → Inventory (or Review), open a valuable item vision wasn't sure about. (Review no longer has an "A photo would help" list; Lisa asked to remove it. The ask lives on Item detail.)
- **Expected:** the item's detail says "Moove isn't sure which model this is…", and **Add another photo** re-identifies it.
- **Report if wrong:** the item, plus a screenshot.

### 15. Review: flip cards and board (Lisa's redesign)
- **Taps:** Items → Review. The flip cards are always on top: tap the top card to flip it, tap again to flip back. Drag it right and left slowly without letting go, then swipe it for real; tap **Undo**; then decide it with a button under the card. Go through to the end and tap **Start over**. Below, look at **Where it goes**, tap a tile, then drag a row onto one of the small labels at the top of its list.
- **Expected:**
  - The stack holds every item ("1 of 12"): the ones that need you first, with a **Needs you** badge (a heart when possibly sentimental), then everything the agents sorted, each saying "Moove says: Sell · worth $30, costs ~$24 to move". Items you already decided are skipped until **Start over**.
  - The front is the item's photo, big; if no photo loads, its voxel model. Tapping turns the card in 3D to the back: voxel model, size, value range, condition, the agent's reason and the sentimental note. With Reduce Motion on (Settings → Accessibility → Motion) it crossfades and nothing tilts.
  - The card tilts and glows in the direction's color with a KEEP / SELL stamp on either side; letting go early springs it back. A real swipe flies it off with a tap of haptics, and "2 of 12" counts up. At the end, **All done** shows the totals with **Start over**.
  - **Where it goes** is four tiles (Keep / Sell / Donate / Trash) in the app's style: mono caps label, serif count, a colored strip on the left edge, no tilt, the total ("$500 expected", "4 kg kept from landfill") and the items fanned; no item lists. On iPad they're four across.
  - Tapping a label opens its list: each item, the agent's reason and a ⇄ change menu. On iPad, dropping a row on one of the small labels at the top moves it there.
  - With a saved New Home layout, Keep's rows are grouped by the room they go to ("→ Bedroom").
  - When nothing needs you, the board is at the top with "Nothing needs you".
- **Report if wrong:** the card or column, plus a screen recording (the swipe feel is what we can't check in CI).

### 16. Shopping by category (Lisa's ask)
- **Taps:** Sell & Buy → **Shopping**. Tap each category chip under the banner (All, Sit & lounge, Work & study, …), then scroll the whole page. Repeat in dark mode and at the largest text size.
- **Expected:**
  - The banner stays on top. Each chip scrolls to its section (with Reduce Motion on, it jumps without animating).
  - One section per category that has items (no empty ones), with a small colored sign and a header like "Sit & lounge · 1 to buy · from $150"; the ones that need you come first and Sleep (only the bought mattress, "Bought (simulated)") is last.
  - Inside a section, the item cards, then a sideways **Deals** row for that category. On iPad the cards stay readable at 880 pt wide; at the largest text size everything is one column.
  - **Blocked for your safety** (the $95 Aeron scam) is its own section at the very end.
- **Report if wrong:** the section or chip, plus a screenshot.

### 17. Shopping cart (Lisa's ask)
- **Taps:** Sell & Buy → **Shopping**. Tap the round cart button at the bottom right, drag the sheet up and down, tap the Mattress row, go back, tap **Done**. Repeat in dark mode, at the largest text size and with Reduce Motion on.
- **Expected:**
  - The button sits above the tab bar at the bottom right with a **1** badge; scrolled to the very bottom, it doesn't cover the last card.
  - The sheet opens at half height with a drag handle and rounded corners: **Bought**, "1 thing · $179.99, simulated", the mattress row with its voxel model, Target, $179.99, **Paid (simulated)** and the SIMULATED pill. The row opens the Mattress detail inside the sheet.
  - On iPad the sheet is a centered card; the button stays at the bottom right of the Shopping screen.
- **Report if wrong:** a screenshot of the button or sheet.

## If merged (check `gh pr list` before you start; skip any that are still open)
- **#286, Pack truck in 3D:** Move → Getting there (the 3D truck is on the truck card) → **Load the truck**. **Expected:** furniture goes in first against the cab, then boxes, with nothing overlapping. Tapping a piece shows its load order. **Report:** the piece that clips or floats, plus a screenshot. (If the 3D says a 10 ft truck while the card says Cargo van, that's known.)
- **#285, mover quotes:** Move → Getting there → truck card → **Get mover quotes**. **Expected:** three cards, each tagged **Estimate**, plus "Estimates from published rates. Call to book." Offline, they're labeled "Estimated on this phone". **Report:** the card, plus a screenshot.
- **#274 (Rio), bunk beds:** a bed 1.2 m or taller is drawn as a bunk bed with a ladder. **Report:** a screenshot.
