# Gear Glance (Forever)

A small Forever version of the retail Gear Glance. It marks your bag and bank items:

- **Item level** in the top-left corner, in the item's quality color (or white).
- **Green arrow** when the item level is higher than what you wear in that slot. It compares item level only.
- **BoE / BoA / WuE** in the bottom-left corner.
- **Gold glow** on items you can open (lockboxes, clams, bags of loot).

## Use

- `/gg` opens the options. `/gg on` and `/gg off` turn the markings on or off.
- The small round button in the backpack's title bar (next to the portrait) opens the options too; right-click it to turn Gear Glance on or off. It sits on the combined bag, or on the backpack when bags are separate.
- It is also listed in the minimap's addon menu.

## What was left out (compared with retail)

Expansion filters and the bag toolbar, upgrade ranks and tracks, equipment-set names,
tooltip scanning, and support for bag addons (Bagnon, Baganator and others). It works with Blizzard's
bags (combined or separate) and the bank.

## Forever notes

- Forever keeps the classic ranged slot, so bows, guns, wands and thrown weapons compare with it.
- Armor arrows follow classic rules: hunters and shamans move to mail, warriors and paladins to plate, at level 40.
  Before that, both armor types count.
- The markings are textures and text drawn on the item buttons, not frames inside the bags,
  so they stay clear of the gamepad navigation (see the stuck-gamepad notes).

## Tests

From this folder: `lua5.1 tests/Smoke.lua` and `luajit tests/Smoke.lua`. Run both: luajit rejects bad string escapes (like a single `\` in a texture path) that lua5.1 silently accepts.
