-- Gear Glance for Forever: item level, an upgrade arrow, a binding label and
-- a glow on items you can open, drawn on Blizzard's bag and bank buttons.
-- A small port of the retail addon: no expansion filters, upgrade tracks,
-- equipment sets or bag-addon adapters.
--
-- Gamepad safety: Forever's gamepad navigation hooks CreateFrame and
-- rebuilds the open panel under the caller's taint (the MapMementos bug).
-- So the overlays are plain textures and font strings on the item button,
-- never child frames, and nothing here calls Blizzard panel or menu code.

local ADDON_NAME, A = ...

local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
A.version = GetMetadata and GetMetadata(ADDON_NAME, "Version") or "?"

A.defaults = {
    enabled = true,
    showItemLevel = true,
    qualityColors = true,
    showArrow = true,
    showBinding = true,
    showOpenable = true,
    showCheapest = true,
    textSize = 13,
    bagButton = true,
}
A.TEXT_MIN, A.TEXT_MAX = 10, 16

local WUE_COLOR = { 0.15, 0.82, 0.74 }
local BOA_COLOR = { 0.35, 0.72, 1.00 }
local GLOW_COLOR = { 1.00, 0.78, 0.20 }
local MAX_RETRIES = 10

-- Item data ----------------------------------------------------------------------------

local MAIN_HAND, OFF_HAND = 16, 17
-- The equipped slots an item competes with. Forever keeps the classic ranged
-- slot; ResolveRangedSlot checks that at login.
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { MAIN_HAND, OFF_HAND },
    INVTYPE_2HWEAPON = { MAIN_HAND }, INVTYPE_WEAPONMAINHAND = { MAIN_HAND },
    INVTYPE_SHIELD = { OFF_HAND }, INVTYPE_WEAPONOFFHAND = { OFF_HAND },
    INVTYPE_HOLDABLE = { OFF_HAND },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}
local TWO_HAND = { INVTYPE_2HWEAPON = true }
-- Items that show an item level. Relics only fit some classes, so no arrow.
local GEAR = { INVTYPE_RELIC = true }
for equipLoc in pairs(SLOTS) do GEAR[equipLoc] = true end

local function ResolveRangedSlot()
    local ok, slot = pcall(GetInventorySlotInfo, "RANGEDSLOT")
    if ok and type(slot) == "number" then return end
    for _, equipLoc in ipairs({ "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN" }) do
        SLOTS[equipLoc] = { MAIN_HAND }
    end
    TWO_HAND.INVTYPE_RANGED = true
end

-- Armor each class wears, best first. Classic rules: hunters and shamans
-- learn mail, warriors and paladins plate, at level 40. Before that both count.
local CLOTH, LEATHER, MAIL, PLATE = 1, 2, 3, 4
local ARMOR_CLASS = 4
local ARMOR = {
    [1] = { PLATE, MAIL }, [2] = { PLATE, MAIL }, [3] = { MAIL, LEATHER },
    [4] = { LEATHER }, [5] = { CLOTH }, [6] = { PLATE }, [7] = { MAIL, LEATHER },
    [8] = { CLOTH }, [9] = { CLOTH }, [10] = { LEATHER }, [11] = { LEATHER },
    [12] = { LEATHER }, [13] = { MAIL },
}

local function WearsArmor(classID, subClassID, equipLoc)
    if classID ~= ARMOR_CLASS or equipLoc == "INVTYPE_CLOAK"
        or type(subClassID) ~= "number" or subClassID < CLOTH or subClassID > PLATE then
        return true
    end
    local _, _, class = UnitClass("player")
    local types = ARMOR[class]
    if not types or subClassID == types[1] then return true end
    return subClassID == types[2] and (UnitLevel("player") or 0) < 40
end

local equipped = {} -- inventory slot -> item level (0 = empty); cleared when gear changes

-- nil while the equipped item is still loading.
local function EquippedLevel(slot)
    local level = equipped[slot]
    if level then return level end
    local link = GetInventoryItemLink("player", slot)
    if link then
        if ItemLocation and C_Item.GetCurrentItemLevel then
            level = C_Item.GetCurrentItemLevel(ItemLocation:CreateFromEquipmentSlot(slot))
        end
        if not level or level <= 0 then level = C_Item.GetDetailedItemLevelInfo(link) end
        if not level or level <= 0 then return nil end
    elseif slot == OFF_HAND then
        -- A two-hander fills both hands, so off-hand items compete with it.
        local mainHand = GetInventoryItemLink("player", MAIN_HAND)
        local mainLoc = mainHand and select(4, C_Item.GetItemInfoInstant(mainHand))
        if mainLoc and TWO_HAND[mainLoc] then
            level = EquippedLevel(MAIN_HAND)
            if not level then return nil end
        else
            level = 0
        end
    else
        level = 0
    end
    equipped[slot] = level
    return level
end

-- true or false; nil while the equipped item is still loading.
local function IsUpgrade(level, equipLoc)
    local slots = SLOTS[equipLoc]
    if not slots then return false end
    local lowest
    for _, slot in ipairs(slots) do
        local worn = EquippedLevel(slot)
        if not worn then return nil end
        lowest = lowest and math.min(lowest, worn) or worn
    end
    return level > lowest
end

local BIND = Enum and Enum.ItemBind or {}
local BIND_ON_EQUIP = BIND.OnEquip or 2
local BIND_WUE = BIND.ToBnetAccountUntilEquipped or 9
local BIND_ACCOUNT = { [BIND.ToWoWAccount or 7] = true, [BIND.ToBnetAccount or 8] = true }

local function BindLabel(bindType, location, isBound)
    if location and C_Item.IsBoundToAccountUntilEquip then
        if C_Item.IsBoundToAccountUntilEquip(location) then return "WuE" end
    elseif bindType == BIND_WUE and not isBound then
        return "WuE"
    end
    if BIND_ACCOUNT[bindType] then return "BoA" end
    if bindType == BIND_ON_EQUIP and not isBound then return "BoE" end
end

-- Reads one bag slot into paint data. data.pending: something was still
-- loading, so read the slot again later.
local function Analyze(bag, slot, info)
    local link = info.hyperlink
    local data = { quality = info.quality, openable = info.hasLoot == true }
    local name, _, quality, _, _, _, _, _, equipLoc, _, _, classID, subClassID, bindType = C_Item.GetItemInfo(link)
    if not name then
        data.pending = true
        local _, _, _, instantLoc, _, instantClass, instantSub = C_Item.GetItemInfoInstant(link)
        equipLoc, classID, subClassID = instantLoc, instantClass, instantSub
    end
    data.quality = quality or data.quality
    local location = ItemLocation and ItemLocation:CreateFromBagAndSlot(bag, slot)
    if GEAR[equipLoc] then
        local level
        if location and C_Item.GetCurrentItemLevel then level = C_Item.GetCurrentItemLevel(location) end
        if not level or level <= 0 then level = C_Item.GetDetailedItemLevelInfo(link) end
        if level and level > 0 then
            data.level = level
            if WearsArmor(classID, subClassID, equipLoc) then
                data.upgrade = IsUpgrade(level, equipLoc)
                if data.upgrade == nil then data.pending = true end
            end
        else
            data.pending = true
        end
    end
    if bindType then data.bind = BindLabel(bindType, location, info.isBound) end
    return data
end

-- Cheapest item when the bags are full ------------------------------------------------
-- When no general bag has a free slot, the bag item with the lowest vendor
-- value (price x stack) gets a junk coin: the one to sell or drop for room.
-- Items with no vendor price (quest items, the hearthstone) are skipped.

local cheapBag, cheapSlot
local cheapIncomplete = false -- an item's price was still loading

local function ScanCheapest()
    cheapBag, cheapSlot, cheapIncomplete = nil, nil, false
    local db = A.db
    if not (db and db.enabled and db.showCheapest) then return end
    local general = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        if (family or 0) == 0 and (C_Container.GetContainerNumSlots(bag) or 0) > 0 then
            if (free or 0) > 0 then return end
            general[#general + 1] = bag
        end
    end
    local lowest
    for _, bag in ipairs(general) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and not info.hasNoValue then
                local name, _, _, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(info.hyperlink)
                if not name then
                    cheapIncomplete = true
                elseif price and price > 0 then
                    local value = price * (info.stackCount or 1)
                    if not lowest or value < lowest then
                        lowest, cheapBag, cheapSlot = value, bag, slot
                    end
                end
            end
        end
    end
end
A.ScanCheapest = ScanCheapest

-- Overlay ---------------------------------------------------------------------------------

local qualityColors = {}
local function QualityColor(quality)
    local color = quality and qualityColors[quality]
    if not color then
        local r, g, b
        if quality and C_Item.GetItemQualityColor then r, g, b = C_Item.GetItemQualityColor(quality) end
        color = { r or 1, g or 1, b or 1 }
        if quality then qualityColors[quality] = color end
    end
    return color[1], color[2], color[3]
end

local overlays = setmetatable({}, { __mode = "k" })

function A.MakeOverlay(button)
    local overlay = overlays[button]
    if overlay then return overlay end
    overlay = {}
    overlay.level = button:CreateFontString(nil, "OVERLAY")
    overlay.level:SetDrawLayer("OVERLAY", 7)
    overlay.level:SetPoint("TOPLEFT", 2, -2)
    overlay.level:SetJustifyH("LEFT")
    overlay.bind = button:CreateFontString(nil, "OVERLAY")
    overlay.bind:SetDrawLayer("OVERLAY", 7)
    overlay.bind:SetPoint("BOTTOMLEFT", 2, 2)
    overlay.bind:SetJustifyH("LEFT")
    overlay.arrow = button:CreateTexture(nil, "OVERLAY", nil, 7)
    -- Native arrow art at its own size (Blizzard's unused UpgradeIcon uses it on
    -- the same 37px slots); top right, since the item level has the top left.
    overlay.arrow:SetAtlas("bags-greenarrow", true)
    overlay.arrow:SetPoint("TOPRIGHT", 0, 0)
    overlay.glow = button:CreateTexture(nil, "OVERLAY", nil, 6)
    overlay.glow:SetAtlas("bags-glow-white")
    overlay.glow:SetAllPoints(button)
    overlay.glow:SetBlendMode("ADD")
    overlay.glow:SetVertexColor(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3])
    -- Blizzard's vendor junk coin, same art and corner.
    overlay.cheap = button:CreateTexture(nil, "OVERLAY", nil, 7)
    overlay.cheap:SetAtlas("bags-junkcoin", true)
    overlay.cheap:SetPoint("TOPLEFT", 1, 0)
    for _, region in pairs(overlay) do region:Hide() end
    overlays[button] = overlay
    return overlay
end

local function StyleFonts(overlay)
    local size = (A.db or A.defaults).textSize
    if overlay.size == size then return end
    overlay.size = size
    local font = NumberFontNormal and NumberFontNormal:GetFont() or "Fonts\\ARIALN.TTF"
    overlay.level:SetFont(font, size, "OUTLINE")
    overlay.bind:SetFont(font, math.max(8, size - 3), "OUTLINE")
end

local function Clear(overlay)
    overlay.level:Hide(); overlay.bind:Hide(); overlay.arrow:Hide(); overlay.glow:Hide(); overlay.cheap:Hide()
    overlay.key = nil
end

-- Shows data on an overlay, following the options. Also paints the preview.
function A.Paint(overlay, data)
    local db = A.db or A.defaults
    StyleFonts(overlay)
    local on = db.enabled and data ~= nil
    local r, g, b = 1, 1, 1
    if on and db.qualityColors then r, g, b = QualityColor(data.quality) end
    -- At a vendor Blizzard puts a junk coin in the top-left corner of grey items;
    -- the cheapest item gets the same coin when the bags are full.
    local cheap = on and db.showCheapest and data.cheap == true and not data.junk
    overlay.cheap:SetShown(cheap)
    if on and db.showItemLevel and data.level and not data.junk and not cheap then
        overlay.level:SetText(data.level)
        overlay.level:SetTextColor(r, g, b)
        overlay.level:Show()
    else
        overlay.level:Hide()
    end
    overlay.arrow:SetShown(on and db.showArrow and data.upgrade == true)
    local bind = on and db.showBinding and data.bind
    if bind then
        overlay.bind:SetText(bind)
        local color = bind == "WuE" and WUE_COLOR or bind == "BoA" and BOA_COLOR
        if color then overlay.bind:SetTextColor(color[1], color[2], color[3])
        else overlay.bind:SetTextColor(r, g, b) end
        overlay.bind:Show()
    else
        overlay.bind:Hide()
    end
    overlay.glow:SetShown(on and db.showOpenable and data.openable == true)
end

-- Buttons ---------------------------------------------------------------------------------

local revision = 0 -- bumped when options or worn gear change
local pending = setmetatable({}, { __mode = "k" }) -- button -> retries left

local function BagSlot(button)
    local bag, slot
    if button.GetBankTabID and button.GetContainerSlotID then
        bag, slot = button:GetBankTabID(), button:GetContainerSlotID()
    elseif button.GetBagID and button.GetID then
        bag, slot = button:GetBagID(), button:GetID()
    end
    if type(bag) == "number" and type(slot) == "number" and slot >= 1 then return bag, slot end
end

local function Update(button)
    local overlay = overlays[button]
    local bag, slot = BagSlot(button)
    local info = A.db.enabled and bag and C_Container.GetContainerItemInfo(bag, slot)
    local link = info and info.hyperlink
    if not link then
        if overlay then Clear(overlay) end
        pending[button] = nil
        return
    end
    local junk = button.JunkIcon and button.JunkIcon:IsShown() or false
    local cheap = bag == cheapBag and slot == cheapSlot and not button.GetBankTabID
    local key = link .. (info.isBound and "|b|" or "|u|") .. (junk and "j|" or "") .. (cheap and "c|" or "")
        .. bag .. ":" .. slot
    if overlay and overlay.key == key and overlay.rev == revision then return end
    overlay = overlay or A.MakeOverlay(button)
    local data = Analyze(bag, slot, info)
    data.junk, data.cheap = junk, cheap
    A.Paint(overlay, data)
    if data.pending then
        -- Blizzard redraws its bags when their items load; the retries cover
        -- the rest (bank slots, a worn item that was still loading).
        overlay.key = nil
        local left = (pending[button] or MAX_RETRIES + 1) - 1
        pending[button] = left > 0 and left or nil
    else
        overlay.key, overlay.rev = key, revision
        pending[button] = nil
    end
end
A.Update = Update

-- Refreshes wait for the next frame, so a burst of Blizzard updates costs one pass.
local queuedFrames, queuedButtons = {}, {}
local flushQueued = false

local function EachButton(frame, fn)
    for first, second in frame:EnumerateValidItems() do
        local button = type(first) == "table" and first or second
        if type(button) == "table" then fn(button) end
    end
end

local function Flush()
    flushQueued = false
    ScanCheapest()
    for frame in pairs(queuedFrames) do
        queuedFrames[frame] = nil
        if frame:IsShown() then EachButton(frame, Update) end
    end
    for button in pairs(queuedButtons) do
        queuedButtons[button] = nil
        if button:IsVisible() then Update(button) end
    end
end

local function Schedule()
    if flushQueued then return end
    flushQueued = true
    C_Timer.After(0, Flush)
end

function A.QueueFrame(frame)
    if frame then queuedFrames[frame] = true; Schedule() end
end

function A.QueueButton(button)
    if button then queuedButtons[button] = true; Schedule() end
end

local bagFrames = {}

local function HookBagFrame(frame)
    if not frame or bagFrames[frame] or type(frame.UpdateItems) ~= "function"
        or type(frame.EnumerateValidItems) ~= "function" then
        return
    end
    bagFrames[frame] = true
    hooksecurefunc(frame, "UpdateItems", A.QueueFrame)
end

local function HookBags()
    HookBagFrame(ContainerFrameCombinedBags)
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do HookBagFrame(_G["ContainerFrame" .. i]) end
end

-- Bank buttons refresh one by one. Camelot's bank buttons call this
-- mixin's Refresh too, and buttons made after the hook carry it.
local bankHooked = false
local function HookBank()
    if bankHooked or not (BankPanelItemButtonMixin and BankPanelItemButtonMixin.Refresh) then return end
    bankHooked = true
    hooksecurefunc(BankPanelItemButtonMixin, "Refresh", A.QueueButton)
end

-- Repaints everything on screen, e.g. after an option change.
function A.RefreshAll()
    revision = revision + 1
    for frame in pairs(bagFrames) do
        if frame:IsShown() then A.QueueFrame(frame) end
    end
    local bank = BankPanel or (BankFrame and BankFrame.BankPanel)
    if bank and bank:IsVisible() and bank.EnumerateValidItems then EachButton(bank, A.QueueButton) end
end

local function RetryPending()
    for button in pairs(pending) do A.QueueButton(button) end
end

-- Options -----------------------------------------------------------------------------------

function A.SetOption(key, value)
    if not A.db or A.defaults[key] == nil then return end
    if key == "textSize" then value = math.max(A.TEXT_MIN, math.min(A.TEXT_MAX, value)) end
    A.db[key] = value
    A.RefreshAll()
    if A.RefreshOptions then A.RefreshOptions() end
    if A.UpdateBagButton then A.UpdateBagButton() end
end

local function InitDB()
    if type(GearGlanceDB) ~= "table" then GearGlanceDB = {} end
    for key, value in pairs(A.defaults) do
        if GearGlanceDB[key] == nil then GearGlanceDB[key] = value end
    end
    A.db = GearGlanceDB
end

-- Events ------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then InitDB() end
    elseif event == "PLAYER_LOGIN" then
        if not A.db then InitDB() end
        ResolveRangedSlot()
        HookBags()
        HookBank()
        if A.CreateBagButton then A.CreateBagButton() end
        A.RefreshAll()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_LEVEL_UP" then
        wipe(equipped)
        A.RefreshAll()
    else -- item data arrived
        if cheapIncomplete then A.RefreshAll() end
        RetryPending()
    end
end)

HookBank() -- the bank template is part of the base UI; hook before any bank opens

function GearGlance_ToggleOptions()
    if A.ToggleOptions then A.ToggleOptions() end
end

SLASH_GEARGLANCE1 = "/gg"
SLASH_GEARGLANCE2 = "/gearglance"
SLASH_GEARGLANCE3 = "/gglance"
SlashCmdList.GEARGLANCE = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "on" or msg == "off" then
        A.SetOption("enabled", msg == "on")
        print("|cffffd100Gear Glance|r " .. (msg == "on" and "on." or "off."))
    elseif msg == "debug" then
        for _, line in ipairs(A.DebugBagButton and A.DebugBagButton() or {}) do
            print("|cffffd100Gear Glance|r " .. line)
        end
    else
        GearGlance_ToggleOptions()
    end
end
