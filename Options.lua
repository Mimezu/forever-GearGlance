-- The Gear Glance window (a Legacy frame, like Petal and Forever Names) and
-- the small round button on the backpack that opens it.

local _, A = ...

local W, H = 560, 422
local PW = W - 48            -- content width
local GAP = 10
local CW = (PW - GAP) / 2    -- card width
local RIGHT = CW + GAP
local H1, H2 = 208, 108      -- card rows
local TOP = 36               -- first control below a card title
local LABEL_X = 34           -- where a checkbox label starts (box at 10, text at +24)
local NOTE, DIM = { 0.80, 0.77, 0.70 }, { 0.5, 0.5, 0.5 }
local GOLD = { 1, 0.82, 0 }
local BUTTON_ICON = "Interface\\Icons\\INV_Misc_Spyglass_02"

-- Made-up items for the preview; painted with the same code as real ones.
local SAMPLES = {
    { name = "Upgrade", icon = "Interface\\Icons\\INV_Sword_39", quality = 3, level = 42, upgrade = true,
        tip = "Item level 42, higher than what you wear in that slot." },
    { name = "BoE", icon = "Interface\\Icons\\INV_Chest_Chain_05", quality = 2, level = 35, bind = "BoE",
        tip = "Binds when equipped. You can still trade or sell it." },
    { name = "BoA", icon = "Interface\\Icons\\INV_Jewelry_Ring_03", quality = 4, level = 60, bind = "BoA",
        tip = "Bound to your account. Your other characters can use it." },
    { name = "Openable", icon = "Interface\\Icons\\INV_Box_02", quality = 1, openable = true,
        tip = "Has loot inside. Right-click it in your bags to open it." },
}

local frame, skin
local checks, updaters = {}, {}

-- Building blocks (same as Petal) ------------------------------------------------------

local function Text(parent, text, x, y, template, width, color)
    local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    label:SetText(text or "")
    if width then label:SetWidth(width); label:SetWordWrap(true) end
    if color then label:SetTextColor(unpack(color)) end
    return label
end
local function Note(parent, text, x, y, width)
    return Text(parent, text, x, y, "GameFontHighlightSmall", width, NOTE)
end
local function Line(parent, x, y, width, height, alpha)
    local line = parent:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT", x, y)
    line:SetSize(width, height)
    line:SetColorTexture(0.68, 0.50, 0.26, alpha or 0.45)
    return line
end
local function Card(parent, title, x, y, width, height)
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", x, y)
    card:SetSize(width, height)
    local wash = card:CreateTexture(nil, "BACKGROUND", nil, -2)
    wash:SetAllPoints()
    wash:SetColorTexture(0.25, 0.17, 0.085, 0.16)
    Line(card, 0, 0, width, 1, 0.55); Line(card, 0, -height + 1, width, 1, 0.3)
    Line(card, 0, 0, 1, height, 0.3); Line(card, width - 1, 0, 1, height, 0.3)
    card.title = Text(card, title, 12, -10, "GameFontNormal")
    Line(card, 8, -28, width - 16, 1, 0.25)
    return card
end
local function Tooltip(owner, title, body, anchor)
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        GameTooltip:SetText(title, GOLD[1], GOLD[2], GOLD[3])
        if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
local function Button(parent, text, x, y, width, onClick, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(width, height or 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    skin.Button(button)
    return button
end
local function Check(parent, key, text, x, y, width)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", x, y)
    check:SetSize(26, 26)
    local label = check.Text or check.text
    label:SetFontObject("GameFontHighlight")
    label:SetText(text)
    label:SetWidth(width or 200)
    label:SetJustifyH("LEFT")
    check.label = label
    check:SetScript("OnClick", function(self)
        PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        A.SetOption(key, self:GetChecked() == true)
    end)
    checks[#checks + 1] = { key = key, check = check }
    return check
end
local function SetCheckEnabled(check, enabled)
    check:SetEnabled(enabled)
    check.label:SetTextColor(unpack(enabled and { 1, 1, 1 } or DIM))
end
-- [-] value [+]
local function Stepper(parent, x, y, valueWidth, onStep)
    local stepper = {}
    stepper.minus = Button(parent, "-", x, y, 24, function() onStep(-1) end)
    stepper.value = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    stepper.value:SetPoint("TOPLEFT", x + 24, y - 4)
    stepper.value:SetWidth(valueWidth)
    stepper.value:SetJustifyH("CENTER")
    stepper.plus = Button(parent, "+", x + 24 + valueWidth, y, 24, function() onStep(1) end)
    function stepper:SetEnabled(enabled)
        self.minus:SetEnabled(enabled); self.plus:SetEnabled(enabled)
        self.value:SetTextColor(unpack(enabled and { 1, 1, 1 } or DIM))
    end
    return stepper
end
-- One-of-several buttons: the selected one is washed gold.
local function Segmented(parent, x, y, width, choices, get, set)
    local buttons, left = {}, x
    for i, choice in ipairs(choices) do
        local button = Button(parent, choice[1], left, y, width, function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON); set(choice[2])
        end)
        left = left + width + 4
        button.wash = button:CreateTexture(nil, "ARTWORK")
        button.wash:SetPoint("TOPLEFT", 4, -4); button.wash:SetPoint("BOTTOMRIGHT", -4, 4)
        button.wash:SetColorTexture(1, 0.72, 0.2, 0.2)
        buttons[i] = button
    end
    function buttons:Update(enabled)
        local current = get()
        for i, choice in ipairs(choices) do
            local selected = choice[2] == current
            self[i]:SetEnabled(enabled)
            self[i].wash:SetShown(selected and enabled)
            self[i]:GetFontString():SetTextColor(unpack(not enabled and DIM or selected and GOLD or { 0.9, 0.9, 0.9 }))
        end
    end
    return buttons
end

-- Cards ---------------------------------------------------------------------------------

local function BuildContent(page)
    local db = A.db

    local items = Card(page, "On bag items", 0, 0, CW, H1)
    local itemChecks = {
        Check(items, "showItemLevel", "Item level", 10, -TOP),
        Check(items, "showArrow", "Upgrade arrow", 10, -TOP - 26),
        Check(items, "showBinding", "Binding (BoE, BoA)", 10, -TOP - 82),
        Check(items, "showOpenable", "Glow on items you can open", 10, -TOP - 108),
        Check(items, "showCheapest", "Coin on cheapest, bags full", 10, -TOP - 134),
    }
    Note(items, "Item level higher than what you wear.\nStats are not compared.", LABEL_X, -TOP - 50, CW - LABEL_X - 10)

    -- Four bag slots on a dark tray, centered in the card body, names below.
    local preview = Card(page, "Preview", RIGHT, 0, CW, H1)
    local size, step, pad = 37, 18, 12
    local trayW, trayH = #SAMPLES * size + (#SAMPLES - 1) * step + 2 * pad, size + 2 * pad
    local blockH = trayH + 8 + 10 -- tray, gap, one line of names
    local trayX = math.floor((CW - trayW) / 2)
    local trayY = -29 - math.floor((H1 - 29 - blockH) / 2)
    local tray = preview:CreateTexture(nil, "BACKGROUND", nil, -1)
    tray:SetPoint("TOPLEFT", trayX, trayY)
    tray:SetSize(trayW, trayH)
    tray:SetColorTexture(0, 0, 0, 0.35)
    Line(preview, trayX, trayY, trayW, 1, 0.3); Line(preview, trayX, trayY - trayH + 1, trayW, 1, 0.3)
    Line(preview, trayX, trayY, 1, trayH, 0.3); Line(preview, trayX + trayW - 1, trayY, 1, trayH, 0.3)
    local samples = {}
    for i, sample in ipairs(SAMPLES) do
        local x = trayX + pad + (i - 1) * (size + step)
        local button = CreateFrame("ItemButton", nil, preview)
        button:SetSize(size, size)
        button:SetPoint("TOPLEFT", x, trayY - pad)
        button:SetButtonState("NORMAL", true) -- hover only; no pressed look
        SetItemButtonTexture(button, sample.icon)
        SetItemButtonQuality(button, sample.quality)
        Tooltip(button, sample.name, sample.tip)
        local label = Note(preview, sample.name, x - step / 2, trayY - trayH - 8, size + step)
        label:SetJustifyH("CENTER")
        samples[i] = { button = button, overlay = A.MakeOverlay(button), data = sample }
    end
    updaters[#updaters + 1] = function()
        for _, sample in ipairs(samples) do
            A.Paint(sample.overlay, sample.data)
            if SetItemButtonDesaturated then SetItemButtonDesaturated(sample.button, not db.enabled) end
        end
    end

    local text = Card(page, "Text", 0, -H1 - GAP, CW, H2)
    Text(text, "Size", 12, -TOP - 6)
    local sizeStep = Stepper(text, 70, -TOP - 2, 40, function(delta)
        A.SetOption("textSize", db.textSize + delta)
    end)
    Text(text, "Color", 12, -TOP - 38)
    local colors = Segmented(text, 70, -TOP - 34, 76, { { "Quality", true }, { "White", false } },
        function() return db.qualityColors end,
        function(value) A.SetOption("qualityColors", value) end)
    Tooltip(colors[1], "Quality", "Item level in the item's quality color.")
    Tooltip(colors[2], "White", "Item level in white.")

    local bags = Card(page, "Bags", RIGHT, -H1 - GAP, CW, H2)
    Check(bags, "bagButton", "Button on the backpack", 10, -TOP)
    Note(bags, "Click: open this window\nRight-click: turn on or off\nOr type /gg", LABEL_X, -TOP - 26, CW - LABEL_X - 10)

    updaters[#updaters + 1] = function()
        local on = db.enabled
        for _, check in ipairs(itemChecks) do SetCheckEnabled(check, on) end
        sizeStep.value:SetText(db.textSize)
        sizeStep:SetEnabled(on)
        colors:Update(on)
    end
end

-- Window --------------------------------------------------------------------------------

function A.RefreshOptions()
    if not (frame and frame:IsShown()) then return end
    for _, entry in ipairs(checks) do entry.check:SetChecked(A.db[entry.key] == true) end
    for _, update in ipairs(updaters) do update() end
end

local function Build()
    skin = A.Skin
    frame = CreateFrame("Frame", "GearGlanceOptions", UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetSize(W, H)
    local point = A.db.point
    if type(point) == "table" and point[1] then
        frame:SetPoint(point[1], UIParent, point[3] or point[1], point[4] or 0, point[5] or 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetToplevel(true)
    table.insert(UISpecialFrames, "GearGlanceOptions")
    -- Stay visible in Frame Gambit's cinematic modes, like the suite's other windows.
    if FrameGambitAPI and FrameGambitAPI.RegisterCinematicWindow then
        pcall(FrameGambitAPI.RegisterCinematicWindow, frame)
    end
    local heading = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetText("Gear Glance")
    skin.Frame(frame, heading)
    hooksecurefunc(frame, "StopMovingOrSizing", function(self)
        local p, _, rel, x, y = self:GetPoint()
        A.db.point = { p, nil, rel, x, y }
    end)

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 26, -48)
    content:SetPoint("BOTTOMRIGHT", -22, 44)
    BuildContent(content)

    local enable = Check(frame, "enabled", "Show Gear Glance on items", 0, 0, 240)
    enable:ClearAllPoints(); enable:SetPoint("BOTTOMLEFT", 22, 11)
    local close = Button(frame, "Close", 0, 0, 96, function() frame:Hide() end, 22)
    close:ClearAllPoints(); close:SetPoint("BOTTOMRIGHT", -22, 13) -- right edge in line with the cards
    local version = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("RIGHT", close, "LEFT", -10, 0)
    version:SetText("v" .. A.version)

    frame:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
        A.RefreshOptions()
    end)
    frame:SetScript("OnHide", function() PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end)
end

function A.ToggleOptions()
    if not A.db then return end
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
end

-- Bag button ----------------------------------------------------------------------------
-- A small round button in the bag's title bar, next to the portrait, drawn
-- like a minimap addon button. It sits on the combined bag, or on the
-- backpack when bags are separate. It is parented to UIParent and only
-- anchored to the bag, so nothing is created inside Blizzard's
-- (gamepad-navigated) bag frames.

local BUTTON_SCALE = 0.7          -- 31px minimap button -> about 22px, the title bar's height
-- The bags are toplevel frames: opening or clicking one raises it above
-- everything else in its strata, which would bury a button in the same
-- strata. So the button lives one strata above the bag.
local STRATA_ABOVE = { BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG",
    DIALOG = "FULLSCREEN", FULLSCREEN = "FULLSCREEN_DIALOG", FULLSCREEN_DIALOG = "TOOLTIP" }
local BAGS = { "ContainerFrameCombinedBags", "ContainerFrame1" } -- combined, or the backpack

local bagButton

local function BagOwner()
    for _, name in ipairs(BAGS) do
        local bag = _G[name]
        if bag and bag:IsShown() then return bag end
    end
end

function A.UpdateBagButton()
    if not bagButton then return end
    local owner = A.db.bagButton and BagOwner()
    if not owner then bagButton:Hide(); return end
    bagButton:ClearAllPoints()
    local title = owner.TitleContainer
    if title then
        -- Title bar starts right of the portrait; sit at its left end, centred.
        bagButton:SetPoint("LEFT", title, "LEFT", 1 / BUTTON_SCALE, 0)
    else
        bagButton:SetPoint("TOPLEFT", owner, "TOPLEFT", 58 / BUTTON_SCALE, 0)
    end
    -- Since build 70338 a frame's strata can be a secret value.
    local strata = owner:GetFrameStrata()
    if issecretvalue and issecretvalue(strata) then strata = nil end
    bagButton:SetFrameStrata(strata and STRATA_ABOVE[strata] or "HIGH")
    bagButton.icon:SetDesaturated(not A.db.enabled)
    bagButton.icon:SetAlpha(A.db.enabled and 1 or 0.6)
    bagButton:Show()
end

-- Same pieces and offsets as the usual minimap addon button (LibDBIcon).
-- /gg debug: where the button is, for when it can't be seen.
function A.DebugBagButton()
    local lines = {}
    local function Add(text) lines[#lines + 1] = text end
    Add("option bagButton=" .. tostring(A.db.bagButton) .. ", button made=" .. tostring(bagButton ~= nil))
    for _, name in ipairs(BAGS) do
        local bag = _G[name]
        Add(name .. ": " .. (bag and ("shown=" .. tostring(bag:IsShown()) .. " strata=" .. bag:GetFrameStrata()
            .. " level=" .. bag:GetFrameLevel() .. " title=" .. tostring(bag.TitleContainer ~= nil)) or "missing"))
    end
    if bagButton then
        local x, y = bagButton:GetCenter()
        Add(("button: shown=%s visible=%s strata=%s level=%d scale=%.2f center=%s,%s"):format(
            tostring(bagButton:IsShown()), tostring(bagButton:IsVisible()), bagButton:GetFrameStrata(),
            bagButton:GetFrameLevel(), bagButton:GetEffectiveScale(), tostring(x and math.floor(x)), tostring(y and math.floor(y))))
    end
    return lines
end

function A.CreateBagButton()
    if bagButton then return end
    bagButton = CreateFrame("Button", "GearGlanceBagButton", UIParent)
    local button = bagButton
    button:Hide()
    button:SetSize(31, 31)
    button:SetScale(BUTTON_SCALE)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(24, 24)
    background:SetPoint("CENTER", 0, 1)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(BUTTON_ICON)
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    if button.CreateMaskTexture and icon.AddMaskTexture then
        local mask = button:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end
    button.icon = icon
    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(50, 50)
    ring:SetPoint("TOPLEFT")
    button:SetScript("OnMouseDown", function() icon:SetPoint("CENTER", 1, 0) end)
    button:SetScript("OnMouseUp", function() icon:SetPoint("CENTER", 0, 1) end)
    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            A.SetOption("enabled", not A.db.enabled)
        else
            A.ToggleOptions()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("Gear Glance", GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:AddLine("Click: options", 1, 1, 1)
        GameTooltip:AddLine("Right-click: turn " .. (A.db.enabled and "off" or "on"), 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    for _, name in ipairs(BAGS) do
        local bag = _G[name]
        if bag then
            bag:HookScript("OnShow", A.UpdateBagButton)
            bag:HookScript("OnHide", A.UpdateBagButton)
        end
    end
    A.UpdateBagButton()
end
