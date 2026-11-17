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

local _, A = ...

local MAX = 80
local PREFIX = "|cffffd100Gear Glance|r "
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
