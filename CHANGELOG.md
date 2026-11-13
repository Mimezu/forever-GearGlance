# Changelog

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
