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
    sellMarks = true,
    textSize = 13,
    bagButton = true,
    minimapButton = true,
    minimapAngle = 200, -- degrees round the minimap, 0 = east
}
A.TEXT_MIN, A.TEXT_MAX = 10, 16

local WUE_COLOR = { 0.15, 0.82, 0.74 }
local BOA_COLOR = { 0.35, 0.72, 1.00 }
local GLOW_COLOR = { 1.00, 0.78, 0.20 }
local CHEAP_COLOR = { 1.00, 0.35, 0.10 } -- orange-red, apart from the gold "can open" glow
local MAX_RETRIES = 10
local SELL_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local SELL_DELAY = 0.2 -- seconds between sales, so the server keeps up
local PREFIX = "|cffffd100Gear Glance|r "

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

-- Profession tools are never "cheapest": you need them, whatever they sell for.
local TOOLS = {
    [2901] = true,  -- Mining Pick
    [5956] = true,  -- Blacksmith Hammer
    [7005] = true,  -- Skinning Knife
    [4471] = true,  -- Flint and Tinder
    [6219] = true,  -- Arclight Spanner
    [10498] = true, -- Gyromatic Micro-Adjustor
    [9149] = true,  -- Philosopher's Stone
    [6218] = true, [6339] = true, [11130] = true, [11145] = true, [16207] = true, -- Runed enchanting rods
}
local WEAPON_CLASS, FISHING_POLE = 2, 20
local TOOL_SLOTS = { INVTYPE_PROFESSION_TOOL = true, INVTYPE_PROFESSION_GEAR = true }

local function IsTool(link, equipLoc, classID, subClassID)
    local id = tonumber(link:match("item:(%d+)"))
    return (id and TOOLS[id]) or TOOL_SLOTS[equipLoc]
        or (classID == WEAPON_CLASS and subClassID == FISHING_POLE) or false
end
A.IsTool = IsTool

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
                local name, _, _, _, _, _, _, _, equipLoc, _, price, classID, subClassID = C_Item.GetItemInfo(info.hyperlink)
                if not name then
                    cheapIncomplete = true
                elseif price and price > 0 and not IsTool(info.hyperlink, equipLoc, classID, subClassID) then
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

-- Sale marks -----------------------------------------------------------------------------
-- Alt-click a bag item to mark it for sale; again to unmark. A mark is that
-- one item (or stack), not every copy: it is keyed by the item's GUID, which
-- stays with it when it moves. Without a GUID the key is its bag slot and
-- link, so such a mark is lost if the item moves. At a vendor the marked items
-- are sold, and their marks dropped. Marks are per character.

local function SaleKey(bag, slot, link)
    if not link then return end
    if C_Item.GetItemGUID and ItemLocation then
        local ok, guid = pcall(C_Item.GetItemGUID, ItemLocation:CreateFromBagAndSlot(bag, slot))
        if ok and not (issecretvalue and issecretvalue(guid)) and type(guid) == "string" and guid ~= "" then
            return guid
        end
    end
    return bag .. ":" .. slot .. ":" .. link
end
A.SaleKey = SaleKey

local function Marks()
    if type(GearGlanceCharDB) ~= "table" then GearGlanceCharDB = {} end
    -- 2.2.x marked every copy of an item (GearGlanceCharDB.sell); those are dropped.
    GearGlanceCharDB.sell = nil
    if type(GearGlanceCharDB.sellItems) ~= "table" then GearGlanceCharDB.sellItems = {} end
    return GearGlanceCharDB.sellItems
end

local function IsMarked(bag, slot, link)
    local key = SaleKey(bag, slot, link)
    return key ~= nil and Marks()[key] == true
end

local function BagButtonSlot(button)
    if button.GetBankTabID or not (button.GetBagID and button.GetID) then return end
    local bag, slot = button:GetBagID(), button:GetID()
    if type(bag) == "number" and type(slot) == "number" and bag >= 0 and bag <= (NUM_BAG_SLOTS or 4) then
        return bag, slot
    end
end

-- Runs after Blizzard's own click handler (a post-hook, nothing replaced).
local function OnBagClick(button, mouse)
    if mouse ~= "LeftButton" or not A.db.sellMarks then return end
    if not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
    if CursorHasItem and CursorHasItem() then return end
    local bag, slot = BagButtonSlot(button)
    local info = bag and C_Container.GetContainerItemInfo(bag, slot)
    local key = info and SaleKey(bag, slot, info.hyperlink)
    if not key then return end
    local marks = Marks()
    if marks[key] then
        marks[key] = nil
    elseif info.hasNoValue then
        print(PREFIX .. "No vendor price.")
        return
    else
        marks[key] = true
    end
    A.RefreshAll()
end

local hookedButtons = setmetatable({}, { __mode = "k" })
local function HookBagButton(button)
    if hookedButtons[button] or not button.HookScript then return end
    hookedButtons[button] = true
    button:HookScript("OnClick", OnBagClick)
end

-- Selling, one item per tick, while the vendor stays open.
local selling, tried, startMoney, waits = false, {}, nil, 0
local MAX_WAITS = 10 -- ticks to wait for the last sales to clear

local function FinishSale()
    selling = false
    -- Sold = tried and no longer in its slot.
    local soldCount, soldKeys = 0, {}
    for _, try in pairs(tried) do
        local info = C_Container.GetContainerItemInfo(try.bag, try.slot)
        if not (info and info.hyperlink == try.link) then
            soldCount, soldKeys[try.key] = soldCount + 1, true
        end
    end
    tried = {}
    if soldCount > 0 then
        -- Unmark items that are all gone; any left (refused, or a sale cut short) stay marked.
        local left = {}
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local key = info and SaleKey(bag, slot, info.hyperlink)
                if key then left[key] = true end
            end
        end
        local marks = Marks()
        for key in pairs(soldKeys) do
            if not left[key] then marks[key] = nil end
        end
        local earned = (GetMoney and startMoney) and (GetMoney() - startMoney) or 0
        local money = earned > 0 and GetCoinTextureString and (": " .. GetCoinTextureString(earned)) or ""
        print(PREFIX .. ("Sold %d item%s%s"):format(soldCount, soldCount == 1 and "" or "s", money))
    end
    A.RefreshAll()
end

local function SellNext()
    if not selling then return end
    if not (MerchantFrame and MerchantFrame:IsShown()) then FinishSale(); return end
    local any = false
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local key = info and not info.isLocked and not info.hasNoValue and SaleKey(bag, slot, info.hyperlink)
            local spot = key and (bag .. ":" .. slot .. ":" .. info.hyperlink)
            -- One try per slot: an item the vendor refuses is not retried forever.
            if key and Marks()[key] and not tried[spot] then
                tried[spot] = { bag = bag, slot = slot, link = info.hyperlink, key = key }
                C_Container.UseContainerItem(bag, slot)
                any = true
            end
        end
    end
    -- Like Leatrix Plus: sell every marked item in one pass, then look again.
    if any then C_Timer.After(SELL_DELAY, SellNext); return end
    -- Nothing left to try; give items still locked by a sale time to leave.
    for _, try in pairs(tried) do
        local info = C_Container.GetContainerItemInfo(try.bag, try.slot)
        if info and info.hyperlink == try.link and info.isLocked and waits < MAX_WAITS then
            waits = waits + 1
            C_Timer.After(SELL_DELAY, SellNext)
            return
        end
    end
    FinishSale()
end

local function StartSale()
    if IsShiftKeyDown() then return end -- shift at the vendor: no sale this time
    if selling or not (A.db and A.db.sellMarks) or not next(Marks()) then return end
    selling, tried, waits = true, {}, 0
    startMoney = GetMoney and GetMoney()
    -- MERCHANT_SHOW comes before Blizzard shows the vendor window: wait a tick.
    C_Timer.After(SELL_DELAY, SellNext)
end

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
    -- A pulsing border, so the cheapest item stands out in a full bag.
    overlay.cheapGlow = button:CreateTexture(nil, "OVERLAY", nil, 6)
    overlay.cheapGlow:SetAtlas("bags-glow-white")
    overlay.cheapGlow:SetAllPoints(button)
    overlay.cheapGlow:SetBlendMode("ADD")
    overlay.cheapGlow:SetVertexColor(CHEAP_COLOR[1], CHEAP_COLOR[2], CHEAP_COLOR[3])
    -- Marked for sale: the icon darkened, a coin pile in the top-right corner.
    overlay.sellWash = button:CreateTexture(nil, "OVERLAY", nil, 5)
    overlay.sellWash:SetAllPoints(button)
    overlay.sellWash:SetColorTexture(0, 0, 0, 0.5)
    overlay.sell = button:CreateTexture(nil, "OVERLAY", nil, 7)
    overlay.sell:SetTexture(SELL_ICON)
    overlay.sell:SetSize(16, 16)
    overlay.sell:SetPoint("TOPRIGHT", -2, -2)
    overlay.sell:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    for _, region in pairs(overlay) do region:Hide() end
    -- Made after the loop above: an animation group has no Hide.
    local pulse = overlay.cheapGlow.CreateAnimationGroup and overlay.cheapGlow:CreateAnimationGroup()
    if pulse then
        pulse:SetLooping("BOUNCE")
        local fade = pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.3)
        fade:SetDuration(0.7)
        overlay.cheapPulse = pulse
    end
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
    overlay.level:Hide(); overlay.bind:Hide(); overlay.arrow:Hide(); overlay.glow:Hide(); overlay.cheap:Hide(); overlay.cheapGlow:Hide()
    if overlay.cheapPulse then overlay.cheapPulse:Stop() end
    overlay.sell:Hide(); overlay.sellWash:Hide()
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
    overlay.cheapGlow:SetShown(cheap)
    if overlay.cheapPulse then
        if cheap and not overlay.cheapPulse:IsPlaying() then overlay.cheapPulse:Play()
        elseif not cheap then overlay.cheapPulse:Stop() end
    end
    if on and db.showItemLevel and data.level and not data.junk and not cheap then
        overlay.level:SetText(data.level)
        overlay.level:SetTextColor(r, g, b)
        overlay.level:Show()
    else
        overlay.level:Hide()
    end
    -- Sale marks show even with the other markings off: a hidden mark would still sell.
    local sell = data ~= nil and db.sellMarks and data.sell == true
    overlay.sell:SetShown(sell)
    overlay.sellWash:SetShown(sell)
    overlay.arrow:SetShown(on and db.showArrow and data.upgrade == true and not sell)
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
    if BagButtonSlot(button) then HookBagButton(button) end
    local overlay = overlays[button]
    local bag, slot = BagSlot(button)
    local info = (A.db.enabled or A.db.sellMarks) and bag and C_Container.GetContainerItemInfo(bag, slot)
    local link = info and info.hyperlink
    if not link then
        if overlay then Clear(overlay) end
        pending[button] = nil
        return
    end
    local junk = button.JunkIcon and button.JunkIcon:IsShown() or false
    local cheap = bag == cheapBag and slot == cheapSlot and not button.GetBankTabID
    local sell = not button.GetBankTabID and IsMarked(bag, slot, link)
    local key = link .. (info.isBound and "|b|" or "|u|") .. (junk and "j|" or "") .. (cheap and "c|" or "")
        .. (sell and "s|" or "") .. bag .. ":" .. slot
    if overlay and overlay.key == key and overlay.rev == revision then return end
    overlay = overlay or A.MakeOverlay(button)
    local data = Analyze(bag, slot, info)
    data.junk, data.cheap, data.sell = junk, cheap, sell
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
    if A.UpdateMinimapButton then A.UpdateMinimapButton() end
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
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:RegisterEvent("UI_ERROR_MESSAGE")
events:SetScript("OnEvent", function(_, event, arg1, ...)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then InitDB() end
    elseif event == "PLAYER_LOGIN" then
        if not A.db then InitDB() end
        ResolveRangedSlot()
        HookBags()
        HookBank()
        if A.CreateBagButton then A.CreateBagButton() end
        if A.CreateMinimapButton then A.CreateMinimapButton() end
        if A.RegisterSettings then pcall(A.RegisterSettings) end
        A.RefreshAll()
    elseif event == "MERCHANT_SHOW" then
        StartSale()
    elseif event == "MERCHANT_CLOSED" then
        if selling then FinishSale() end
    elseif event == "UI_ERROR_MESSAGE" then
        -- The vendor buys nothing, or the gold cap is reached: stop.
        local message = ... -- UI_ERROR_MESSAGE: errorType, message
        if selling and message and (message == ERR_VENDOR_DOESNT_BUY or message == ERR_TOO_MUCH_GOLD) then
            FinishSale()
        end
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

-- Key bindings (Bindings.xml).
BINDING_HEADER_GEARGLANCE = "Gear Glance"
BINDING_NAME_GEARGLANCE_TOGGLE = "Open Gear Glance"

SLASH_GEARGLANCE1 = "/gg"
SLASH_GEARGLANCE2 = "/gearglance"
SLASH_GEARGLANCE3 = "/gglance"
SlashCmdList.GEARGLANCE = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "on" or msg == "off" then
        A.SetOption("enabled", msg == "on")
        print(PREFIX .. (msg == "on" and "on." or "off."))
    elseif msg == "debug" then
        for _, line in ipairs(A.DebugBagButton and A.DebugBagButton() or {}) do
            print("|cffffd100Gear Glance|r " .. line)
        end
    elseif msg == "nav" or msg == "nav clear" then
        if A.NavReport then A.NavReport(msg == "nav clear") end
    else
        GearGlance_ToggleOptions()
    end
end

-- Gamepad bag navigation recorder (read-only diagnostics).
--
-- In the gamepad UI, the d-pad moves Blizzard's SmartNavigation cursor over
-- the bag, and it does not move like a grid. This records what it does so the
-- cause can be found: each cursor move (from, to, d-pad direction), where a
-- plain grid would have gone, and whether that slot was in Blizzard's list
-- of buttons it can go to. Presses that moved nothing are recorded too.
--
-- Taint rule: nothing here writes to, hooks or calls into SmartNavigation or
-- the bag. It only reads fields, from its own OnUpdate, while the combined
-- bag is open in the gamepad UI. Any value of ours that Blizzard's navigation
-- read would taint it (gamepad item use then fails with "action blocked").
--
-- /gg nav: summary in chat. /gg nav clear: start over.
-- The log is kept in GearGlanceDB.navLog (last MAX entries) across /reload.
do
    local MAX = 80
    local DIRS = { RIGHT = { 1, 0 }, LEFT = { -1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }

    local function Log()
        if type(GearGlanceDB) ~= "table" then return end
        if type(GearGlanceDB.navLog) ~= "table" then GearGlanceDB.navLog = {} end
        return GearGlanceDB.navLog
    end

    local function Add(entry)
        local log = Log()
        if not log then return end
        entry.t = GetTime and math.floor(GetTime() * 100) / 100 or 0
        log[#log + 1] = entry
        while #log > MAX do table.remove(log, 1) end
    end

    local function GamepadUI()
        if not (InputUtil and InputUtil.IsGamepadUIEnabled) then return false end
        local ok, on = pcall(InputUtil.IsGamepadUIEnabled)
        return ok and on == true
    end

    local function Bag()
        local bag = ContainerFrameCombinedBags
        if bag and bag:IsVisible() and bag.EnumerateValidItems then return bag end
    end

    -- The visible item buttons and their centers.
    local function Slots(bag)
        local slots = {}
        for first, second in bag:EnumerateValidItems() do
            local button = type(first) == "table" and first or second
            if type(button) == "table" and button:IsVisible() then
                local x, y = button:GetCenter()
                if x then slots[#slots + 1] = { button = button, x = x, y = y, size = button:GetWidth() or 37 } end
            end
        end
        return slots
    end

    local function Describe(button, slots)
        if not button then return "none" end
        if type(button) ~= "table" then return tostring(button) end
        local ok, forbidden = pcall(button.IsForbidden, button)
        if not ok or forbidden then return "forbidden" end
        if button.GetBagID and button.GetID then
            local okBag, bag = pcall(button.GetBagID, button)
            if okBag and type(bag) == "number" then
                local text = "bag " .. bag .. " slot " .. button:GetID()
                if slots then
                    -- Row and column in the bag, counted from the top left.
                    local me
                    for _, s in ipairs(slots) do if s.button == button then me = s end end
                    if me then
                        -- Distinct rows above and columns left of it, half a slot apart or more.
                        local step = me.size / 2
                        local function Key(v) return math.floor(v / step + 0.5) end
                        local rows, cols = {}, {}
                        for _, s in ipairs(slots) do rows[Key(s.y)] = true; cols[Key(s.x)] = true end
                        local row, col = 1, 1
                        for key in pairs(rows) do if key > Key(me.y) then row = row + 1 end end
                        for key in pairs(cols) do if key < Key(me.x) then col = col + 1 end end
                        text = text .. " (r" .. row .. " c" .. col .. ")"
                    end
                end
                return text
            end
        end
        local name = button.GetName and button:GetName()
        local parent = button.GetParent and button:GetParent()
        local parentName = parent and parent.GetName and parent:GetName()
        return (name or (button.GetObjectType and button:GetObjectType() or "frame"))
            .. (parentName and (" in " .. parentName) or "")
    end

    -- Where a plain grid goes from this button: the nearest slot in the same row
    -- (or column) in that direction.
    local function GridNeighbor(from, dir, slots)
        local me
        for _, s in ipairs(slots) do if s.button == from then me = s end end
        if not me then return end
        local tolerance = me.size / 2
        local best, bestDistance
        for _, s in ipairs(slots) do
            if s ~= me then
                local dx, dy = s.x - me.x, s.y - me.y
                local along = dir[1] ~= 0 and dx * dir[1] or dy * dir[2]
                local across = dir[1] ~= 0 and math.abs(dy) or math.abs(dx)
                if along > 0 and across < tolerance and (not bestDistance or along < bestDistance) then
                    best, bestDistance = s.button, along
                end
            end
        end
        return best
    end

    -- Blizzard's current list of buttons the cursor may go to.
    local function Candidates()
        local nav = SmartNavigation
        local info = nav and nav.activeInfo
        local groups = info and info.buttonGroups
        local group = groups and (groups.focusedGroup or groups.mainGroup)
        return group and group.buttons, info
    end

    local function DirectionName(directions)
        if type(directions) ~= "table" or #directions == 0 then return nil end
        local names = {}
        for _, d in ipairs(directions) do
            for name, v in pairs(DIRS) do
                if d.x == v[1] and d.y == v[2] then names[#names + 1] = name end
            end
        end
        return table.concat(names, "+")
    end

    local watcher = CreateFrame("Frame")
    local lastButton, lastDirection, heldSince, movedWhileHeld, openLogged

    local function OnUpdate()
        local bag = Bag()
        local nav = SmartNavigation
        if not bag or not nav or not GamepadUI() then
            lastButton, lastDirection, openLogged = nil, nil, false
            return
        end
        local current = nav.currentButton
        local direction = DirectionName(nav.currentDirections)

        -- Once per bag opening: what besides item slots can the cursor go to?
        if not openLogged then
            local buttons, info = Candidates()
            if buttons and info and info.frame == bag then
                openLogged = true
                local slots, inList, others = Slots(bag), {}, {}
                for _, b in ipairs(buttons) do
                    inList[b] = true
                    if not (b.GetBagID and b.GetID) then others[#others + 1] = Describe(b) end
                end
                local missing = 0
                for _, s in ipairs(slots) do if not inList[s.button] then missing = missing + 1 end end
                Add({ kind = "open", slots = #slots, listed = #buttons, missing = missing,
                    others = table.concat(others, "; ", 1, math.min(#others, 12)) })
            end
        end

        -- A press that ended without the cursor moving.
        if direction ~= lastDirection then
            if lastDirection and not movedWhileHeld then
                Add({ kind = "lost", dir = lastDirection, at = Describe(current, Slots(bag)) })
            end
            heldSince, movedWhileHeld = direction and GetTime() or nil, false
            lastDirection = direction
        end

        if current ~= lastButton then
            local slots = Slots(bag)
            local dir = direction or lastDirection
            local entry = { kind = "move", dir = dir or "?", from = Describe(lastButton, slots), to = Describe(current, slots) }
            local vector = dir and DIRS[dir]
            if vector and lastButton then
                local expected = GridNeighbor(lastButton, vector, slots)
                entry.grid = Describe(expected, slots)
                entry.ok = expected == current or nil
                if expected and expected ~= current then
                    local buttons = Candidates()
                    local listed = false
                    for _, b in ipairs(buttons or {}) do if b == expected then listed = true; break end end
                    entry.gridListed = listed
                end
            end
            if lastButton then Add(entry) end
            movedWhileHeld = true
            lastButton = current
        end
    end

    watcher:SetScript("OnUpdate", OnUpdate)

    function A.NavReport(clear)
        local log = Log()
        if not log then return end
        if clear then
            wipe(log)
            print(PREFIX .. "Navigation log cleared.")
            return
        end
        local moves, wrong, lost, unlisted = 0, 0, 0, 0
        for _, e in ipairs(log) do
            if e.kind == "move" then
                moves = moves + 1
                if e.grid and not e.ok then wrong = wrong + 1 end
                if e.gridListed == false then unlisted = unlisted + 1 end
            elseif e.kind == "lost" then
                lost = lost + 1
            end
        end
        print(PREFIX .. ("Navigation: %d moves, %d off-grid (%d to a slot Blizzard lost), %d presses with no move."):format(
            moves, wrong, unlisted, lost))
        local shown = 0
        for i = #log, 1, -1 do
            local e = log[i]
            if shown >= 6 then break end
            if e.kind == "move" and e.grid and not e.ok then
                print(("  %s: %s -> %s (grid: %s)"):format(e.dir, e.from, e.to, e.grid))
                shown = shown + 1
            end
        end
    end
end
