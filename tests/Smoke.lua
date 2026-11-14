-- Run from the addon folder: lua5.1 tests/Smoke.lua
-- Loads the addon against a mocked Forever client and checks the overlay rules.
local assertions = 0
local function check(value, message) assertions = assertions + 1; assert(value, message) end

-- Timers ------------------------------------------------------------------------------
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function flush()
    while #timers > 0 do
        local run = timers
        timers = {}
        for _, fn in ipairs(run) do fn() end
    end
end

-- Frames: regions record what they show -----------------------------------------------
local hooks = {}
local function Region(kind)
    local obj = { kind = kind, shown = true, scripts = {}, points = {} }
    local methods = {
        Show = function(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end,
        Hide = function(self) self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end,
        SetShown = function(self, v) if v then self:Show() else self:Hide() end end,
        IsShown = function(self) return self.shown end,
        IsVisible = function(self) return self.shown end,
        SetText = function(self, text) self.text = text end,
        GetText = function(self) return self.text end,
        SetTextColor = function(self, r, g, b) self.color = { r, g, b } end,
        SetFont = function(self, file, size, flags) self.font = { file, size, flags } end,
        SetAtlas = function(self, atlas) self.atlas = atlas end,
        SetDesaturated = function(self, v) self.desaturated = v end,
        SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
        ClearAllPoints = function(self) self.points = {} end,
        CreateTexture = function() return Region("Texture") end,
        CreateFontString = function() return Region("FontString") end,
        CreateMaskTexture = function() return Region("MaskTexture") end,
        SetScript = function(self, name, fn) self.scripts[name] = fn end,
        GetScript = function(self, name) return self.scripts[name] end,
        HookScript = function(self, name, fn)
            local old = self.scripts[name]
            self.scripts[name] = function(...) if old then old(...) end; fn(...) end
        end,
        GetChecked = function(self) return self.checked end,
        SetChecked = function(self, v) self.checked = v end,
        GetFontString = function(self) rawset(self, "fs", rawget(self, "fs") or Region("FontString")); return rawget(self, "fs") end,
        GetFrameLevel = function() return 5 end,
        GetFrameStrata = function(self) return rawget(self, "strata") or "MEDIUM" end,
        SetFrameStrata = function(self, v) self.strata = v end,
        GetCenter = function() return 100, 200 end,
        GetEffectiveScale = function() return 0.7 end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
        GetSize = function() return 100, 100 end,
        IsEnabled = function() return true end,
    }
    return setmetatable(obj, { __index = function(_, key)
        if key == "Text" or key == "text" or key == "Left" or key == "Middle" or key == "Right"
            or key == "LeftSeparator" or key == "RightSeparator" or key == "SetItemButtonTexture"
            or key == "SetItemButtonQuality" or key == "GetBankTabID" or key == "GetContainerSlotID"
            or key == "GetBagID" or key == "EnumerateValidItems" or key == "UpdateItems" or key == "JunkIcon" then
            return nil
        end
        return methods[key] or function() end
    end })
end
local created = {}
function CreateFrame(kind, name, parent, template)
    local frame = Region(kind)
    if kind == "CheckButton" then frame.Text = Region("FontString") end
    if name then _G[name] = frame end
    created[#created + 1] = { frame = frame, kind = kind, parent = parent, name = name }
    return frame
end
function hooksecurefunc(target, name, fn)
    if type(target) == "string" then target, name, fn = _G, target, name end
    local original = target[name]
    target[name] = function(...) local r = { original(...) }; fn(...); return unpack(r) end
    hooks[#hooks + 1] = name
end
UIParent, GameTooltip = Region("Frame"), Region("Frame")
NumberFontNormal = { GetFont = function() return "Fonts\\ARIALN.TTF", 14, "OUTLINE" end }
UISpecialFrames, SlashCmdList = {}, {}
SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
function PlaySound() end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function SetItemButtonTexture(button, texture) button.iconTexture = texture end
function SetItemButtonQuality(button, quality) button.quality = quality end
C_Texture = { GetAtlasInfo = function() return { width = 43, height = 60, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1, file = 1 } end }
NineSliceUtil = { ApplyLayoutByName = function() end }
C_AddOns = { GetAddOnMetadata = function() return "2.0.0" end }
Enum = { ItemBind = { OnEquip = 2, ToWoWAccount = 7, ToBnetAccount = 8, ToBnetAccountUntilEquipped = 9 } }
local printed = {}
function print(text) printed[#printed + 1] = text end

-- Player and items ---------------------------------------------------------------------
local player = { class = 8, level = 30 }
function UnitClass() return "Mage", "MAGE", player.class end
function UnitLevel() return player.level end
function GetInventorySlotInfo(name) if name == "RANGEDSLOT" then return 18 end error("bad slot") end

-- name -> { link, quality, level, equipLoc, classID, subClassID, bindType }
local ITEMS = {}
local function Item(name, fields)
    fields.link = "|Hitem:" .. name .. "|h[" .. name .. "]|h"
    fields.name = name
    ITEMS[fields.link] = fields
    return fields.link
end
local notCached = {}
C_Item = {
    GetItemInfo = function(link)
        local it = ITEMS[link]
        if not it or notCached[link] then return nil end
        return it.name, link, it.quality, it.level, 1, "", "", 1, it.equipLoc or "", 0, it.price or 0,
            it.classID or 0, it.subClassID or 0, it.bindType or 0
    end,
    GetItemInfoInstant = function(link)
        local it = ITEMS[link]
        return 1, "", "", it and it.equipLoc or "", 0, it and it.classID or 0, it and it.subClassID or 0
    end,
    GetDetailedItemLevelInfo = function(link) local it = ITEMS[link]; return it and not notCached[link] and it.level or nil end,
    GetCurrentItemLevel = function(location)
        local link
        if location.equip then link = player.worn and player.worn[location.equip]
        else link = location.bag and bags[location.bag] and bags[location.bag][location.slot] and bags[location.bag][location.slot].link end
        local it = link and ITEMS[link]
        return it and not notCached[link] and it.level or nil
    end,
    GetItemQualityColor = function(q) return q / 10, q / 10, q / 10 end,
    IsBoundToAccountUntilEquip = function(location)
        local slot = bags[location.bag] and bags[location.bag][location.slot]
        return slot and slot.wue == true
    end,
}
ItemLocation = {
    CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end,
    CreateFromEquipmentSlot = function(_, slot) return { equip = slot } end,
}
bags = {} -- bag -> slot -> { link, bound, loot }
player.worn = {}
function GetInventoryItemLink(_, slot) return player.worn[slot] end
C_Container = {
    GetContainerItemInfo = function(bag, slot)
        local s = bags[bag] and bags[bag][slot]
        if not s then return nil end
        local it = ITEMS[s.link]
        return { hyperlink = s.link, quality = it.quality, isBound = s.bound == true, hasLoot = s.loot == true,
            stackCount = s.count or 1, hasNoValue = it.noValue == true, isLocked = false }
    end,
    GetContainerNumSlots = function(bag) return bag == 0 and 8 or 0 end,
    GetContainerNumFreeSlots = function(bag)
        if bag ~= 0 then return 0, 0 end
        local free = 8
        for slot = 1, 8 do if bags[0] and bags[0][slot] then free = free - 1 end end
        return free, 0
    end,
}

-- Keys, money and the vendor ---------------------------------------------------------------
local keys = { alt = false, shift = false, ctrl = false }
function IsAltKeyDown() return keys.alt end
function IsShiftKeyDown() return keys.shift end
function IsControlKeyDown() return keys.ctrl end
function CursorHasItem() return false end
local money = 0
function GetMoney() return money end
function GetCoinTextureString(copper) return copper .. "c" end
MerchantFrame = Region("Frame")
MerchantFrame.shown = false
local refused = {} -- links the vendor will not buy
local sold = {}
C_Container.UseContainerItem = function(bag, slot)
    local s = bags[bag] and bags[bag][slot]
    if not s or refused[s.link] then return end
    sold[#sold + 1] = s.link
    money = money + (ITEMS[s.link].price or 0) * (s.count or 1)
    bags[bag][slot] = nil
end

-- Blizzard bag and bank frames -----------------------------------------------------------
local function ItemButton(bag, slot)
    local button = Region("ItemButton")
    button.GetBagID = function() return bag end
    button.GetID = function() return slot end
    return button
end
local combined = Region("Frame")
combined.shown = false
combined.buttons = {}
for slot = 1, 8 do combined.buttons[slot] = ItemButton(0, slot) end
combined.EnumerateValidItems = function(self)
    local i = 0
    return function() i = i + 1; if self.buttons[i] then return i, self.buttons[i] end end
end
combined.UpdateItems = function() end
combined.TitleContainer = Region("Frame")
ContainerFrameCombinedBags = combined
ContainerFrame1 = Region("Frame")
ContainerFrame1.shown = false
NUM_CONTAINER_FRAMES = 1

BankPanelItemButtonMixin = { Refresh = function() end }

-- Load ------------------------------------------------------------------------------------------
local ns = {}
for _, file in ipairs({ "Core.lua", "Skin.lua", "Options.lua" }) do
    assert(loadfile(file))("GearGlance", ns)
end
local events
for _, c in ipairs(created) do if c.kind == "Frame" and not c.parent then events = c.frame; break end end
local function fire(event, ...) events.scripts.OnEvent(events, event, ...) end

fire("ADDON_LOADED", "GearGlance")
check(GearGlanceDB and GearGlanceDB.enabled == true and GearGlanceDB.textSize == 13, "defaults applied")
fire("PLAYER_LOGIN")
local hookedUpdate = false
for _, name in ipairs(hooks) do if name == "UpdateItems" then hookedUpdate = true end end
check(hookedUpdate, "bag UpdateItems hooked")
check(GearGlanceBagButton and not GearGlanceBagButton:IsShown(), "bag button hidden while bags are closed")

-- Worn gear: level 30 chest, level 20 ring in slot 11, slot 12 empty, 2H level 40.
player.worn[5] = Item("WornChest", { quality = 2, level = 30, equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 1 })
player.worn[11] = Item("WornRing", { quality = 2, level = 20, equipLoc = "INVTYPE_FINGER" })
player.worn[16] = Item("WornStaff", { quality = 3, level = 40, equipLoc = "INVTYPE_2HWEAPON", classID = 2 })

bags[0] = {
    [1] = { link = Item("BetterRobe", { quality = 3, level = 35, equipLoc = "INVTYPE_ROBE", classID = 4, subClassID = 1, bindType = 2 }) },
    [2] = { link = Item("WorseChest", { quality = 2, level = 25, equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 1 }) },
    [3] = { link = Item("PlateChest", { quality = 2, level = 50, equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 4 }) },
    [4] = { link = Item("Lockbox", { quality = 1, level = 20, equipLoc = "" }), loot = true },
    [5] = { link = Item("LowOffhand", { quality = 2, level = 35, equipLoc = "INVTYPE_HOLDABLE", classID = 4, subClassID = 0 }) },
    [6] = { link = Item("AnyRing", { quality = 4, level = 5, equipLoc = "INVTYPE_FINGER", bindType = 7 }), bound = true },
    [7] = { link = Item("BoundBoE", { quality = 3, level = 10, equipLoc = "INVTYPE_WRIST", bindType = 2 }), bound = true },
    [8] = { link = Item("Shirt", { quality = 1, level = 1, equipLoc = "INVTYPE_BODY" }) },
}

combined:Show()
combined:UpdateItems()
flush()

-- Find the overlay regions: MakeOverlay is exposed, so read them back through it.
local function overlay(slot) return ns.MakeOverlay(combined.buttons[slot]) end
check(GearGlanceBagButton:IsShown(), "bag button shows with the bags")
check(GearGlanceBagButton.strata == "HIGH", "bag button one strata above the MEDIUM bag")
SlashCmdList.GEARGLANCE("debug")
check(#printed >= 3 and printed[#printed]:find("button: shown=true"), "/gg debug reports the button")
check(GearGlanceBagButton.points[1][1] == "LEFT" and GearGlanceBagButton.points[1][2] == combined.TitleContainer,
    "bag button sits at the left end of the title bar")

local o1 = overlay(1)
check(o1.level.shown and o1.level.text == 35, "item level on the robe")
check(o1.arrow.shown, "robe beats the worn chest")
check(o1.bind.shown and o1.bind.text == "BoE", "unbound BoE labelled")
check(o1.level.font[1] == "Fonts\\ARIALN.TTF" and o1.level.font[2] == 13, "native number font at the set size")
check(not overlay(2).arrow.shown and overlay(2).level.text == 25, "lower chest: level, no arrow")
check(overlay(3).level.shown and not overlay(3).arrow.shown, "plate on a mage: no arrow")
local o4 = overlay(4)
check(o4.glow.shown and not o4.level.shown, "lockbox glows and has no item level")
check(not overlay(5).arrow.shown, "off-hand below the worn two-hander: no arrow")
check(overlay(6).arrow.shown, "empty ring slot: any ring is an upgrade")
check(overlay(6).bind.text == "BoA", "account-bound ring labelled BoA even when bound")
check(not overlay(7).bind.shown, "soulbound BoE has no label")
check(not overlay(8).level.shown, "shirts show no item level")

-- Level 40 hunter: mail only; below 40 leather counts too.
player.class = 3
bags[0][2] = { link = Item("LeatherChest", { quality = 2, level = 45, equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 2 }) }
bags[0][3] = { link = Item("MailChest", { quality = 2, level = 45, equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 3 }) }
fire("PLAYER_LEVEL_UP")
flush()
check(overlay(2).arrow.shown and overlay(3).arrow.shown, "level 30 hunter: leather and mail both count")
player.level = 40
fire("PLAYER_LEVEL_UP")
flush()
check(not overlay(2).arrow.shown and overlay(3).arrow.shown, "level 40 hunter: mail only")
player.class, player.level = 8, 30 -- back to the mage
fire("PLAYER_LEVEL_UP")
flush()

-- Swap the staff for a one-hander: the off-hand is now empty, so it counts.
player.worn[16] = Item("Dagger", { quality = 2, level = 40, equipLoc = "INVTYPE_WEAPON" })
fire("PLAYER_EQUIPMENT_CHANGED")
flush()
check(overlay(5).arrow.shown, "empty off-hand beside a one-hander: arrow")

-- Options repaint what is on screen.
ns.SetOption("showItemLevel", false)
flush()
check(not overlay(1).level.shown and overlay(1).arrow.shown, "item level hidden, arrow kept")
ns.SetOption("showItemLevel", true)
ns.SetOption("qualityColors", false)
flush()
check(overlay(1).level.color[1] == 1 and overlay(1).level.color[3] == 1, "white text option")
ns.SetOption("qualityColors", true)
ns.SetOption("textSize", 99)
flush()
check(GearGlanceDB.textSize == 16 and overlay(1).level.font[2] == 16, "text size clamped and applied")
SlashCmdList.GEARGLANCE("off")
flush()
check(not GearGlanceDB.enabled and not overlay(1).level.shown and not overlay(4).glow.shown, "/gg off clears overlays")
check(GearGlanceBagButton.icon.desaturated == true, "bag button greyed while off")
SlashCmdList.GEARGLANCE("on")
flush()
check(overlay(1).level.shown, "/gg on paints again")

-- At a vendor the junk coin takes the top-left corner: no item level there.
local junkButton = combined.buttons[2]
junkButton.JunkIcon = Region("Texture")
combined:UpdateItems()
flush()
check(not overlay(2).level.shown, "no item level under the junk coin")
junkButton.JunkIcon:Hide()
combined:UpdateItems()
flush()
check(overlay(2).level.shown, "item level back when the vendor closes")

-- Item data still loading: painted once it arrives.
local slow = Item("SlowHelm", { quality = 3, level = 33, equipLoc = "INVTYPE_HEAD", classID = 4, subClassID = 1 })
notCached[slow] = true
bags[0][2] = { link = slow }
combined:UpdateItems()
flush()
check(not overlay(2).level.shown, "no level before the item loads")
notCached[slow] = nil
fire("GET_ITEM_INFO_RECEIVED", 1)
flush()
check(overlay(2).level.shown and overlay(2).level.text == 33 and overlay(2).arrow.shown, "painted after the item loads")

-- Emptied slot clears; a recycled button without a bag does not error.
bags[0][1] = nil
combined:UpdateItems()
flush()
check(not overlay(1).level.shown and not overlay(1).arrow.shown and not overlay(1).bind.shown, "empty slot cleared")
combined.buttons[1].GetBagID = function() return nil end
combined:UpdateItems()
flush()
check(true, "button without a bag is skipped")

-- Bags full: a coin on the item worth least at a vendor (price x stack).
local function cheap(slot) return overlay(slot).cheap.shown end
local function anyCheap() for s = 1, 8 do if cheap(s) then return s end end end
combined.buttons[1].GetBagID = function() return 0 end
check(not anyCheap(), "a free slot: no coin")
for slot = 1, 8 do
    bags[0][slot] = { link = Item("Sell" .. slot, { quality = 1, level = 10, price = 100 * slot }) }
end
bags[0][2] = { link = Item("Hearth", { quality = 1, level = 1, price = 0 }) }
bags[0][3] = { link = Item("Cloth", { quality = 1, level = 5, price = 20 }), count = 20 } -- 400
bags[0][5] = { link = Item("Gloves", { quality = 2, level = 15, price = 150, equipLoc = "INVTYPE_HAND", classID = 4, subClassID = 1 }) }
combined:UpdateItems()
flush()
check(anyCheap() == 1, "cheapest by stack value, unpriced items skipped")
check(overlay(1).cheapGlow.shown and not overlay(2).cheapGlow.shown, "glowing border on the cheapest item")
local keep6, keep7, keep8 = bags[0][6], bags[0][7], bags[0][8]
bags[0][6] = { link = Item("2901", { quality = 1, level = 1, price = 1 }) } -- Mining Pick
bags[0][7] = { link = Item("6256", { quality = 1, level = 5, price = 1, equipLoc = "INVTYPE_2HWEAPON", classID = 2, subClassID = 20 }) } -- Fishing Pole
bags[0][8] = { link = Item("9999", { quality = 1, level = 1, price = 1, equipLoc = "INVTYPE_PROFESSION_TOOL" }) }
combined:UpdateItems()
flush()
check(anyCheap() == 1, "profession tools are never the cheapest")
bags[0][6], bags[0][7], bags[0][8] = keep6, keep7, keep8
combined:UpdateItems()
flush()
bags[0][1] = nil
combined:UpdateItems()
flush()
check(not anyCheap(), "coin gone once a slot frees up")
bags[0][1] = { link = Item("Sell1b", { quality = 1, level = 10, price = 900 }) }
combined:UpdateItems()
flush()
check(anyCheap() == 5 and not overlay(5).level.shown, "coin moves; it takes the item level's corner")
ns.SetOption("showCheapest", false)
flush()
check(not anyCheap(), "option turns the coin off")
ns.SetOption("showCheapest", true)
flush()
check(anyCheap() == 5, "and on again")
local slowCoin = Item("SlowCoin", { quality = 0, level = 1, price = 1 })
notCached[slowCoin] = true
bags[0][4] = { link = slowCoin }
combined:UpdateItems()
flush()
check(anyCheap() == 5, "unloaded item not picked yet")
notCached[slowCoin] = nil
fire("GET_ITEM_INFO_RECEIVED", 1)
flush()
check(anyCheap() == 4, "picked once its price loads")
combined.buttons[4].JunkIcon = Region("Texture")
combined:UpdateItems()
flush()
check(not cheap(4), "Blizzard's own vendor coin is not doubled")
combined.buttons[4].JunkIcon = nil
for slot = 1, 8 do bags[0][slot] = nil end
combined:UpdateItems()
flush()

-- Alt-click marks an item for sale; at a vendor it sells.
local function altClick(slot, mouse)
    keys.alt = true
    combined.buttons[slot].scripts.OnClick(combined.buttons[slot], mouse or "LeftButton")
    keys.alt = false
    flush()
end
local function marked(slot) return overlay(slot).sell.shown end
local linen = Item("2589", { quality = 1, level = 5, price = 13 })
local bear = Item("4000:0:0:0:0:0:-12", { quality = 2, level = 20, price = 500, equipLoc = "INVTYPE_WAIST", classID = 4, subClassID = 1 })
local eagle = Item("4000:0:0:0:0:0:-17", { quality = 2, level = 20, price = 500, equipLoc = "INVTYPE_WAIST", classID = 4, subClassID = 1 })
local hearth = Item("6948", { quality = 1, level = 1, noValue = true })
local robe = Item("5000", { quality = 2, level = 22, price = 300, equipLoc = "INVTYPE_ROBE", classID = 4, subClassID = 1 })
bags[0][1] = { link = linen, count = 5 }
bags[0][2] = { link = linen, count = 3 }
bags[0][3] = { link = bear }
bags[0][4] = { link = eagle }
bags[0][5] = { link = hearth }
bags[0][6] = { link = robe }
combined:UpdateItems()
flush()
check(type(combined.buttons[1].scripts.OnClick) == "function", "bag buttons get a click hook")
combined.buttons[1].scripts.OnClick(combined.buttons[1], "LeftButton")
flush()
check(not marked(1), "plain click marks nothing")
altClick(1, "RightButton")
check(not marked(1), "alt-right-click marks nothing")
altClick(1)
check(marked(1) and marked(2) and overlay(1).sellWash.shown, "alt-click marks every stack of that item")
altClick(3)
check(marked(3) and not marked(4), "random suffixes marked apart")
check(not overlay(3).arrow.shown, "no upgrade arrow on an item marked for sale")
altClick(5)
check(not marked(5) and printed[#printed]:find("No vendor price"), "unsellable items refuse a mark")
altClick(6)
altClick(6)
check(not marked(6), "alt-click again unmarks")
check(GearGlanceCharDB.sell["2589"] and GearGlanceCharDB.sell["4000:-12"], "marks saved per character")
SlashCmdList.GEARGLANCE("off")
flush()
check(marked(1) and not overlay(6).level.shown, "marks stay visible with the markings off")
SlashCmdList.GEARGLANCE("on")
flush()

refused[bear] = true
keys.shift = true
fire("MERCHANT_SHOW")
flush()
keys.shift = false
check(#sold == 0 and bags[0][1], "shift at the vendor skips the sale")
fire("MERCHANT_SHOW") -- the event comes before Blizzard shows the window
check(#sold == 0, "nothing sold before the vendor window shows")
MerchantFrame.shown = true
flush()
check(#sold == 2 and not bags[0][1] and not bags[0][2], "both linen stacks sold")
check(bags[0][3] and bags[0][4] and bags[0][6], "refused, unmarked and other items kept")
check(printed[#printed]:find("Sold 2 items: 104c", 1, true), "summary counts only what sold")
check(GearGlanceCharDB.sell["2589"] == nil, "mark dropped once the items are gone")
check(GearGlanceCharDB.sell["4000:-12"] == true and marked(3), "refused item stays marked")
fire("MERCHANT_CLOSED")
MerchantFrame.shown = false
refused[bear] = nil
GearGlanceCharDB.sell = {}
for slot = 1, 8 do bags[0][slot] = nil end
combined:UpdateItems()
flush()

-- Bank buttons refresh through the mixin hook.
local bankButton = Region("ItemButton")
bankButton.GetBankTabID = function() return 6 end
bankButton.GetContainerSlotID = function() return 1 end
bags[6] = { [1] = { link = Item("BankBoots", { quality = 4, level = 60, equipLoc = "INVTYPE_FEET", classID = 4, subClassID = 1, bindType = 2 }) } }
BankPanelItemButtonMixin.Refresh(bankButton)
flush()
local bo = ns.MakeOverlay(bankButton)
check(bo.level.text == 60 and bo.arrow.shown and bo.bind.text == "BoE", "bank item painted")
bags[6][1].wue = true
bags[6][1].link = Item("BankWuE", { quality = 4, level = 61, equipLoc = "INVTYPE_FEET", classID = 4, subClassID = 1, bindType = 9 })
BankPanelItemButtonMixin.Refresh(bankButton)
flush()
check(bo.bind.text == "WuE", "warbound until equipped labelled WuE")

-- The window builds, and the preview follows the options.
SlashCmdList.GEARGLANCE("")
check(GearGlanceOptions and GearGlanceOptions:IsShown(), "/gg opens the window")
local itemButtons = {}
for _, c in ipairs(created) do if c.kind == "ItemButton" then itemButtons[#itemButtons + 1] = c.frame end end
check(#itemButtons == 4, "four preview items")
local preview = ns.MakeOverlay(itemButtons[1])
check(preview.level.shown and preview.arrow.shown, "preview shows level and arrow")
ns.SetOption("showArrow", false)
check(not preview.arrow.shown, "preview follows the arrow option")
ns.SetOption("showArrow", true)
check(ns.MakeOverlay(itemButtons[4]).glow.shown, "preview lockbox glows")
GearGlanceBagButton.scripts.OnClick(GearGlanceBagButton, "RightButton")
check(GearGlanceDB.enabled == false, "right-click on the button turns it off")
GearGlanceBagButton.scripts.OnClick(GearGlanceBagButton, "RightButton")
check(GearGlanceDB.enabled == true, "and on again")
GearGlanceBagButton.scripts.OnClick(GearGlanceBagButton, "LeftButton")
check(not GearGlanceOptions:IsShown(), "left-click toggles the window")
ns.SetOption("bagButton", false)
check(not GearGlanceBagButton:IsShown(), "button option hides the button")
combined:Hide()
ns.SetOption("bagButton", true)
check(not GearGlanceBagButton:IsShown(), "button stays hidden with the bags closed")

-- Nothing is ever created as a child of a Blizzard item button (gamepad taint rule).
for _, c in ipairs(created) do
    local p = c.parent
    local isBlizzardButton = p and (p.GetBagID or p.GetBankTabID)
    check(not isBlizzardButton, "no frames created inside Blizzard item buttons")
end

io.write(("Smoke: %d checks passed\n"):format(assertions))
