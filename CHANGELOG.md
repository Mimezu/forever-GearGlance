# Changelog

## 2.3.5

- Gamepad bag navigation recorder (diagnostics, read-only): `/gg nav` shows how the d-pad cursor moved in the
  combined bag, the moves that left the grid, and presses that moved nothing. `/gg nav clear` starts over.
  It only reads Blizzard's navigation state, so it cannot taint gamepad item use.

## 2.3.4

- Fix: the backpack button was invisible in 2.3.1-2.3.3. This client raises windows by draw order, not frame level, so the button is now part of the bag (created at login, then attached to the open bag): above the bag's art, under windows covering the bag.

## 2.3.3

- Alt-click marks only the item (or stack) you click, not every copy. The mark follows the item when it moves.
  Marks from 2.2.x, which covered every copy, are cleared once.

## 2.3.2

- Fix for 2.3.1: the backpack button was hidden under the bag's border. It now sits one level above the bag's highest child frame (one strata above if levels can't be read). `/gg debug` shows the offset.

## 2.3.1

- Fix: the backpack button showed through windows covering the bag (it sat one strata above the bag). It now shares the bag's strata and follows its level.

## 2.3.0

- Key to open the window, set from the window itself (Buttons card) or from Key Bindings > AddOns.
- Minimap button: click opens the window, right-click turns Gear Glance on or off, drag to move. Shown by default.
- Page in Esc > Options > AddOns: Open, minimap icon, key.

## 2.2.3

- Fix for 2.2.2: an error while setting up each bag slot left stray coins on random items,
  hid all item levels and broke alt-click marking. (The new border pulse was hidden along with the textures.)

## 2.2.2

- Cheapest item: a pulsing orange border around it, under the coin, so it stands out in a full bag.
- Profession tools are never picked as cheapest: mining pick, blacksmith hammer, skinning knife,
  fishing poles, flint and tinder, enchanting rods, engineering tools, Philosopher's Stone.

## 2.2.1

- Fix: marked items did not sell. The sale started before Blizzard showed the vendor window and stopped at once; it now waits a tick.
- Sells all marked items per pass (like Leatrix Plus), stops if the vendor buys nothing or you hit the gold cap.
- Hold Shift when talking to a vendor to skip the sale.

## 2.2.0

- Alt-click a bag item to mark it for sale (darkened, coin pile top right); alt-click again to unmark.
  Marks are per character and cover every copy of the item.
- At a vendor, marked items sell one by one, with a summary in chat. A mark is dropped once its items are gone.
- Option "Alt-click: sell at vendor", on by default. Marks stay visible with the other markings off.

## 2.1.0

- Bags full: a junk coin on the bag item worth least at a vendor (price x stack). Option "Coin on cheapest, bags full", on by default.

## 2.0.1

- Build 70338: a frame's strata can now be a secret value; the backpack title-bar button falls back to HIGH instead of erroring.

## 2.0.0 (Forever)

- New Forever version, based on the retail Gear Glance 1.2.1 and kept small: item level, upgrade arrow,
  BoE/BoA/WuE labels, and a glow on items you can open, on Blizzard bags and the bank.
- Options in a Legacy-style window (`/gg`), with a live preview, and a small minimap-style round button in the backpack's title bar.
- Classic ranged slot and classic armor-by-level rules for the arrow.
- Grey items at a vendor skip the item level, since Blizzard's junk coin uses that corner.
- Removed from retail: expansion filters and toolbar, upgrade ranks, equipment sets, tooltip scanning,
  and bag-addon adapters.
