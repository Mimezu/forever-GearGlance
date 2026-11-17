-- Run from the addon folder: lua5.1 tests/NavLog.lua
-- The gamepad navigation recorder: logs moves, flags off-grid ones and lost
-- presses, and never writes to Blizzard's navigation.
local checks = 0
local function check(v, msg) checks = checks + 1; assert(v, msg) end

local now = 0
function GetTime() return now end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local printed = {}
function print(s) printed[#printed + 1] = s end
InputUtil = { IsGamepadUIEnabled = function() return true end }

local update
function CreateFrame()
    return { SetScript = function(_, name, fn) if name == "OnUpdate" then update = fn end end }
end

-- A 3 x 2 bag: row 1 at y=100, row 2 at y=60; columns at x=10, 50, 90.
local function Slot(bag, slot, x, y)
    return {
        GetBagID = function() return bag end, GetID = function() return slot end,
        GetCenter = function() return x, y end, GetWidth = function() return 37 end,
        IsVisible = function() return true end, IsForbidden = function() return false end,
    }
end
local s = {
    Slot(0, 1, 10, 100), Slot(0, 2, 50, 100), Slot(0, 3, 90, 100),
    Slot(1, 1, 10, 60), Slot(1, 2, 50, 60), Slot(1, 3, 90, 60),
}
local search = {
    GetName = function() return "BagSearchBox" end, IsForbidden = function() return false end,
    GetParent = function() return nil end,
}
ContainerFrameCombinedBags = {
    IsVisible = function() return true end,
    EnumerateValidItems = function()
        local i = 0
        return function() i = i + 1; if s[i] then return i, s[i] end end
    end,
}
-- Blizzard's list is missing slot r1 c3.
local listed = { s[1], s[2], s[4], s[5], s[6], search }
local navState = {
    currentButton = s[1], currentDirections = {},
    activeInfo = { frame = ContainerFrameCombinedBags, buttonGroups = { mainGroup = { buttons = listed } } },
}
SmartNavigation = setmetatable({}, {
    __index = navState,
    __newindex = function() error("the recorder must never write to SmartNavigation") end,
})
local RIGHT, DOWN = { x = 1, y = 0 }, { x = 0, y = -1 }

GearGlanceDB = {}
local ns = {}
assert(loadfile("NavLog.lua"))("GearGlance", ns)
local function frame() now = now + 0.016; update() end

frame()
local log = GearGlanceDB.navLog
check(log[1].kind == "open" and log[1].slots == 6 and log[1].listed == 6 and log[1].missing == 1, "open: one slot missing from Blizzard's list")
check(log[1].others:find("BagSearchBox", 1, true), "open: lists non-slot targets")

-- RIGHT to the grid neighbor: fine.
navState.currentDirections = { RIGHT }; frame()
navState.currentButton = s[2]; frame()
navState.currentDirections = {}; frame()
check(log[2].kind == "move" and log[2].ok and log[2].dir == "RIGHT", "a grid move is ok")
check(log[2].from:find("r1 c1", 1, true) and log[2].to:find("r1 c2", 1, true), "rows and columns counted from the top left")

-- RIGHT again, but it jumps to r2 c3 because r1 c3 is not listed.
navState.currentDirections = { RIGHT }; frame()
navState.currentButton = s[6]; frame()
navState.currentDirections = {}; frame()
local jump = log[3]
check(jump.kind == "move" and not jump.ok and jump.gridListed == false, "off-grid move to a slot Blizzard lost")
check(jump.grid:find("r1 c3", 1, true) and jump.to:find("r2 c3", 1, true), "expected and actual slots named")

-- DOWN pressed and released with no move: a lost press.
navState.currentDirections = { DOWN }; frame()
navState.currentDirections = {}; frame()
check(log[4].kind == "lost" and log[4].dir == "DOWN", "a press with no move is recorded")

ns.NavReport()
check(printed[1]:find("3 moves") == nil and printed[1]:find("2 moves", 1, true) and printed[1]:find("1 off-grid", 1, true)
    and printed[1]:find("1 to a slot Blizzard lost", 1, true) and printed[1]:find("1 presses with no move", 1, true), "summary")
ns.NavReport(true)
check(#GearGlanceDB.navLog == 0, "clear")

-- Not in the gamepad UI: nothing recorded.
InputUtil.IsGamepadUIEnabled = function() return false end
navState.currentButton = s[1]; frame()
check(#GearGlanceDB.navLog == 0, "keyboard UI records nothing")

io.write(("NavLog: %d checks passed\n"):format(checks))
