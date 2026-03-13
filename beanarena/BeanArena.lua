-- BeanArena.lua
-- TBC Anniversary Arena Point Calculator & Honor Tracker
-- ============================================================
-- VERSION HISTORY
-- ============================================================
-- v0.1.0 | Initial release - arena point calculator
-- v0.1.1 | Honor tracking, BG marks, minimap button
-- v0.1.2 | Arena history tracking, class icons, win/loss
-- v0.1.3 | Resizable history window, per-bracket filters, PVP UI hook
-- v0.1.4 | Per-character history, result filters, bracket detection fix
-- v0.1.5 | 2025-03-01 | Per-char storage via chars table, PLAYER_LOGIN migration
-- v0.1.5.1 | 2025-03-01 | Container API compat fix
-- v0.1.5.2 | 2025-03-01 | Minimap border removed, PVP button removed
-- v0.1.5.3 | 2025-03-01 | Win/loss: guard winner==nil mid-match
-- v0.1.5.4 | 2025-03-01 | Win/loss: switched to UnitIsDeadOrGhost
-- v0.1.5.5 | 2025-03-01 | Kills-based win detection attempt
-- v0.1.5.6 | 2025-03-01 | Fresh win detection rewrite
-- v0.1.5.7 | 2025-03-01 | Win detection partially working
-- v0.1.6 | 2025-03-01 | Removed all arena history tracking and history UI
-- v0.1.7 | 2025-03-01 | Honor cap bar, milestones, gear planner, minimap tooltip
-- v0.1.8 | 2025-03-01 | Two-column layout, EotS fix, individual mark rows
-- v0.1.8.1 | 2025-03-01 | Frame height 420->540
-- v0.1.9 | 2025-03-01 | UI polish, column reorder, inline AP calc, honor gear progress
-- v0.2.0 | 2025-03-01 | Arena Gear Costs popup + Honor Gear Costs popup
-- v0.2.1 | 2025-03-01 | CC/DR Table — all classes, all categories, TBC rules
--         |             Spell Lookup — 80+ spells, filter by class/type/search
-- v0.2.2 | 2026-03-11 | Full embedded spell tooltip DB (97 spells, Blizzard-style)
-- v0.2.3 | 2026-03-11 | Condensed single-col layout, removed Spell Lookup
--         |             Opens attached to PvPUI (H key), flair title + version
--         |             Honor moved to popup button; CC/DR condensed
--         |             Gear cost buttons inline; minimap + /ap unchanged
-- v0.2.4 | 2026-03-11 | Notes popup — 2v2/3v3 comp reference with per-comp notes
--         |             Title right-aligned; 3-button bottom row (+ Notes button)
-- v0.2.7 | 2026-03-11 | Split notes into 2v2 and 3v3 windows; spec-named comps
--         |             tier-ranked S->C; removed default strats; plain-text buttons
-- v0.2.8 | 2026-03-12 | /ba commands; Info button; per-character DB; char viewer
-- v0.2.9 | 2026-03-13 | WoW dialog BG; spacing pass; centered Viewing dropdown; button rows
-- ============================================================
-- CURRENT: v0.2.9
-- ============================================================

-- ============================================================
-- SAVED VARIABLES  (per-character storage in v0.2.8)
-- BeanArenaDB               = global/shared (minimap angle, frame pos)
-- BeanArenaCharDB           = per-character (ratings, honor, comp notes)
-- BeanArenaDB.chars[realm][name] = snapshot of another char's data
-- ============================================================
BeanArenaDB     = BeanArenaDB     or {}
BeanArenaCharDB = BeanArenaCharDB or {}   -- per-char SavedVariable

local ADDON_NAME    = "BeanArena"
local RESET_WEEKDAY = 3 -- Tuesday (wday=3)

-- Character identity (populated on PLAYER_LOGIN)
local CHAR_NAME, CHAR_REALM

local defaults = {
    manual2v2    = 0,
    manual3v3    = 0,
    manual5v5    = 0,
    minimapAngle = 45,
    frameX       = nil,
    frameY       = nil,
    openOnLogin  = false,
}

-- Shared DB (global prefs)
local function DB(key)
    if BeanArenaDB[key] == nil then return defaults[key] end
    return BeanArenaDB[key]
end
local function SetDB(key, val) BeanArenaDB[key] = val end

-- Per-character DB (comp notes, snapshots)
local function CharDB(key)
    if BeanArenaCharDB[key] == nil then return nil end
    return BeanArenaCharDB[key]
end
local function SetCharDB(key, val) BeanArenaCharDB[key] = val end

-- NotesDB now reads/writes per-character storage
-- (defined here; referenced by BuildNotesWindow via upvalue)
local function GetCharNotes(bracket)
    if not BeanArenaCharDB["compEntries"] then
        BeanArenaCharDB["compEntries"] = {}
    end
    if not BeanArenaCharDB["compEntries"][bracket] then
        BeanArenaCharDB["compEntries"][bracket] = {}
    end
    return BeanArenaCharDB["compEntries"][bracket]
end

-- Snapshot current char data into the cross-char roster
local function SnapshotCharData()
    if not CHAR_NAME or not CHAR_REALM then return end
    BeanArenaDB.chars = BeanArenaDB.chars or {}
    local key = CHAR_NAME .. "-" .. CHAR_REALM
    local r2,r3,r5,g2,g3,g5 = 0,0,0,0,0,0
    if GetLiveRatings then r2,r3,r5,g2,g3,g5 = GetLiveRatings() end
    local snap = {
        name         = CHAR_NAME,
        realm        = CHAR_REALM,
        notes2v2     = BeanArenaCharDB.compEntries and BeanArenaCharDB.compEntries["2v2"] or {},
        notes3v3     = BeanArenaCharDB.compEntries and BeanArenaCharDB.compEntries["3v3"] or {},
        arenaPoints  = GetCurrentArenaPoints and GetCurrentArenaPoints() or 0,
        honor        = GetCurrentHonor and GetCurrentHonor() or 0,
        r2=r2, r3=r3, r5=r5, g2=g2, g3=g3, g5=g5,
        timestamp    = time(),
    }
    BeanArenaDB.chars[key] = snap
end

-- ============================================================
-- POINT FORMULA
-- ============================================================
local function CalcBasePoints(rating)
    rating = tonumber(rating) or 0
    if rating <= 0 then return 0 end
    return ((1651.94 - 475) / (1 + 2500000 * math.exp(-0.009 * rating)) + 475) * 1.5
end

local function CalcBracketPoints(rating, bracket)
    local base = CalcBasePoints(rating)
    if bracket == "2v2" then return base * 0.76
    elseif bracket == "3v3" then return base * 0.88
    else return base end
end

local function CalcBestPoints(r2, r3, r5)
    local candidates = {
        ["2v2"] = r2 > 0 and CalcBracketPoints(r2, "2v2") or 0,
        ["3v3"] = r3 > 0 and CalcBracketPoints(r3, "3v3") or 0,
        ["5v5"] = r5 > 0 and CalcBracketPoints(r5, "5v5") or 0,
    }
    local best, bestBracket = 0, "None"
    for b, pts in pairs(candidates) do
        if pts > best then best = pts; bestBracket = b end
    end
    return best, bestBracket
end

-- ============================================================
-- GEAR DATA TABLES
-- ============================================================
local ARENA_GEAR_FULL = {
    { slot="Gloves",           ap=930,  rating=0    },
    { slot="Wand",             ap=830,  rating=0    },
    { slot="Caster Off-hand",  ap=930,  rating=0    },
    { slot="Helmet",           ap=1550, rating=0    },
    { slot="Legs",             ap=1550, rating=0    },
    { slot="Chest",            ap=1550, rating=0    },
    { slot="Shoulders",        ap=1245, rating=2000 },
    { slot="Shield",           ap=1550, rating=1700 },
    { slot="Off-hand Melee",   ap=930,  rating=1700 },
    { slot="Throwing Weapon",  ap=830,  rating=1700 },
    { slot="Main-hand Melee",  ap=2175, rating=1700 },
    { slot="Caster Main-hand", ap=2610, rating=1700 },
    { slot="2H / Main Ranged", ap=3110, rating=1700 },
    { slot="Caster Staff",     ap=3110, rating=1700 },
}

local HONOR_GEAR_FULL = {
    { slot="Neck",      honor=12695, marks={ EotS=5  } },
    { slot="Ring",      honor=12695, marks={ AV=5    } },
    { slot="Cloak",     honor=9785,  marks={ AB=10   } },
    { slot="Bracers",   honor=9785,  marks={ WSG=10  } },
    { slot="Belt",      honor=14815, marks={ AB=10   } },
    { slot="Boots",     honor=14815, marks={ EotS=20 } },
    { slot="Gloves",    honor=10475, marks={ AV=10   } },
    { slot="Shoulders", honor=10475, marks={ AB=10   } },
    { slot="Helmet",    honor=16665, marks={ AV=15   } },
    { slot="Legs",      honor=16665, marks={ WSG=15  } },
    { slot="Chest",     honor=17140, marks={ AB=15   } },
}

-- ============================================================
-- RESET TIMER
-- ============================================================
local function GetDaysToReset()
    local d = date("*t", time())
    local daysUntilTue = (RESET_WEEKDAY - d.wday + 7) % 7
    if daysUntilTue == 0 then daysUntilTue = d.hour < 8 and 0 or 7 end
    local hoursLeft = (daysUntilTue * 24) + (8 - d.hour - 1)
    local minsLeft  = 60 - d.min
    if minsLeft == 60 then minsLeft = 0; hoursLeft = hoursLeft + 1 end
    return string.format("%dd %dh %dm", math.floor(hoursLeft / 24), hoursLeft % 24, minsLeft)
end

-- ============================================================
-- CURRENCIES
-- ============================================================
local HONOR_CAP = 75000

local function GetCurrentHonor()
    if GetHonorCurrency then
        local h = GetHonorCurrency(); if h then return h end
    end
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = C_CurrencyInfo.GetCurrencyInfo(1901)
        if info then return info.quantity or 0 end
    end
    if GetCurrencyInfo then
        local _, count = GetCurrencyInfo(1901); if count then return count end
    end
    return 0
end

local function GetCurrentArenaPoints()
    if GetArenaPoints then
        local pts = GetArenaPoints(); if pts then return pts end
    end
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = C_CurrencyInfo.GetCurrencyInfo(1900)
        if info then return info.quantity or 0 end
    end
    if GetCurrencyInfo then
        local _, count = GetCurrencyInfo(1900); if count then return count end
    end
    return 0
end

-- ============================================================
-- PVP MARKS
-- ============================================================
local PVP_MARKS = { [20560]="AV", [20558]="WSG", [20559]="AB", [29024]="EotS" }

local function SafeGetContainerNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    elseif GetContainerNumSlots then return GetContainerNumSlots(bag) or 0 end
    return 0
end
local function SafeGetContainerItemLink(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bag, slot)
    elseif GetContainerItemLink then return GetContainerItemLink(bag, slot) end
    return nil
end
local function SafeGetContainerItemCount(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        return info and info.stackCount or 1
    elseif GetContainerItemInfo then
        local _, count = GetContainerItemInfo(bag, slot); return count or 1
    end
    return 1
end

local function GetPvPMarkCounts()
    local counts = { AV=0, WSG=0, AB=0, EotS=0 }
    for bag = 0, 4 do
        local numSlots = SafeGetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local link = SafeGetContainerItemLink(bag, slot)
            if link then
                for itemID, markName in pairs(PVP_MARKS) do
                    if link:find("item:" .. itemID .. ":") then
                        counts[markName] = counts[markName] + SafeGetContainerItemCount(bag, slot)
                    end
                end
            end
        end
    end
    return counts
end

-- ============================================================
-- LIVE RATINGS
-- ============================================================
local function GetLiveRatings()
    local r2,r3,r5,g2,g3,g5 = 0,0,0,0,0,0
    if GetPersonalRatedInfo then
        -- GetPersonalRatedInfo: rating, seasonBest, weeklyBest, seasonPlayed, seasonWon, weeklyPlayed, weeklyWon, cap
        local a,_,_,_,_,b = GetPersonalRatedInfo(1); r2=tonumber(a) or 0; g2=tonumber(b) or 0
        local c,_,_,_,_,d = GetPersonalRatedInfo(2); r3=tonumber(c) or 0; g3=tonumber(d) or 0
        local e,_,_,_,_,f = GetPersonalRatedInfo(3); r5=tonumber(e) or 0; g5=tonumber(f) or 0
    end
    return r2,r3,r5,g2,g3,g5
end

-- ============================================================
-- UI HELPERS
-- ============================================================
local function MakeBGFrame(name, parent, w, h)
    local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left=11, right=12, top=12, bottom=11 },
    })
    f:SetBackdropColor(0, 0, 0, 0.9)
    f:SetBackdropBorderColor(1, 1, 1, 1)
    -- Title bar highlight strip
    local tb = f:CreateTexture(nil, "ARTWORK")
    tb:SetTexture("Interface\DialogFrame\UI-DialogBox-Header")
    tb:SetSize(w * 0.7, 32)
    tb:SetPoint("TOP", f, "TOP", 0, 10)
    return f
end

local function RegisterEsc(f)
    tinsert(UISpecialFrames, f:GetName())
end

-- Inset "stone panel" section background (like PvP UI bracket panels)
local function MakeSectionBG(parent, x, y, w, h)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t:SetTexture("Interface\Common\bluemenu-main")
    t:SetTexCoord(0.02, 0.98, 0.02, 0.98)
    t:SetSize(w, h)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    t:SetAlpha(0.18)
    return t
end

local function MakeHeader(parent, y, text, x)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 18, y)
    h:SetText("|cff00CCFF" .. text .. "|r")
end

local function MakeLine(parent, y, w, x)
    local l = parent:CreateTexture(nil, "ARTWORK")
    l:SetSize(w or 294, 1)
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 18, y)
    l:SetColorTexture(0.4, 0.4, 0.4, 0.6)
end

local function FS(parent, x, y)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    f:SetText("--")
    return f
end

-- ============================================================
-- MINIMAP BUTTON
-- ============================================================
local minimapButton = CreateFrame("Button", "BeanArenaMinimapButton", Minimap)
minimapButton:SetSize(31, 31)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
minimapButton:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

local mmIcon = minimapButton:CreateTexture(nil, "ARTWORK")
mmIcon:SetSize(20, 20)
mmIcon:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)
mmIcon:SetTexture("Interface\\Icons\\Achievement_Arena_2v2_7")
mmIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local function UpdateMinimapPos()
    local a = math.rad(DB("minimapAngle"))
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
end

minimapButton:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", function(self)
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        SetDB("minimapAngle", math.deg(math.atan2(cy/s - my, cx/s - mx)))
        UpdateMinimapPos()
    end)
end)
minimapButton:SetScript("OnDragStop", function(self)
    self:UnlockHighlight(); self:SetScript("OnUpdate", nil)
end)
minimapButton:RegisterForDrag("LeftButton")
minimapButton:RegisterForClicks("LeftButtonUp", "MiddleButtonUp", "RightButtonUp")
minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("|cffFFD700BeanArena|r", 1, 1, 1)
    local honor = GetCurrentHonor()
    local ap    = GetCurrentArenaPoints()
    local r2,r3,r5,g2,g3,g5 = GetLiveRatings()
    local er2=g2>=10 and r2 or 0; local er3=g3>=10 and r3 or 0; local er5=g5>=10 and r5 or 0
    local best,bb = CalcBestPoints(er2,er3,er5)
    local honorPct = math.min(100, math.floor(honor / HONOR_CAP * 100))
    GameTooltip:AddLine(string.format("Honor: |cffFFD700%s|r / 75,000  (%d%%)",
        BreakUpLargeNumbers and BreakUpLargeNumbers(honor) or tostring(honor), honorPct), 0.8,0.8,0.8)
    if honor >= 70000 then GameTooltip:AddLine("|cffFF4444Warning: Near honor cap! Spend soon.|r") end
    GameTooltip:AddLine(string.format("Arena Points: |cff88FF88%d|r", ap), 0.8,0.8,0.8)
    if best > 0 then
        GameTooltip:AddLine(string.format("Best reward: |cffFFD700%.0f AP|r  (%s)", best, bb), 0.8,0.8,0.8)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: toggle window",  0.6,0.6,0.6)
    GameTooltip:AddLine("Middle-click: commands",     0.6,0.6,0.6)
    GameTooltip:AddLine("Right-click: options",       0.6,0.6,0.6)
    GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ============================================================
-- FORWARD DECLARATIONS
-- ============================================================
local OpenBeanArena, OpenCommands, frame, cFrame, SetupPVPHook
local arenaGearFrame, honorGearFrame, honorFrame, drFrame, notesFrame2, notesFrame3
local infoFrame, charViewFrame
local BeanArena_RefreshArenaGearPopup, BeanArena_RefreshHonorGearPopup
local BeanArena_RefreshHonorFrame
local BeanArena_RefreshFrame, BeanArena_RefreshManual

-- ============================================================
-- OPTIONS DROPDOWN
-- ============================================================
local optDD = CreateFrame("Frame", "BeanArenaOptDD", UIParent, "UIDropDownMenuTemplate")

local function ShowOptions()
    UIDropDownMenu_Initialize(optDD, function()
        local function Btn(text, func, checked, notCheckable)
            local i = {}
            i.text = text; i.func = func; i.checked = checked
            i.notCheckable = notCheckable or false; i.isNotRadio = notCheckable or false
            i.disabled = false; i.isTitle = false; i.keepShownOnClick = false
            UIDropDownMenu_AddButton(i)
        end
        local function Title(text)
            local i = {}
            i.text = text; i.isTitle = true; i.notCheckable = true; i.disabled = true
            UIDropDownMenu_AddButton(i)
        end
        Title("|cffFFD700BeanArena Options|r")
        Btn("Toggle BeanArena Window", function()
            if frame:IsShown() then frame:Hide() else OpenBeanArena() end
            CloseDropDownMenus()
        end, nil, true)
        Btn("Toggle Commands Window", function()
            if cFrame:IsShown() then cFrame:Hide() else OpenCommands() end
            CloseDropDownMenus()
        end, nil, true)
        Title("Startup")
        Btn("Open on Login", function()
            SetDB("openOnLogin", not DB("openOnLogin"))
            CloseDropDownMenus()
        end, DB("openOnLogin"), false)
    end, "MENU")
    ToggleDropDownMenu(1, nil, optDD, "cursor", 0, 0)
end

minimapButton:SetScript("OnClick", function(self, btn)
    if btn == "LeftButton" then
        if frame:IsShown() then frame:Hide() else OpenBeanArena() end
    elseif btn == "MiddleButton" then
        if cFrame:IsShown() then cFrame:Hide() else OpenCommands() end
    elseif btn == "RightButton" then
        ShowOptions()
    end
end)

-- ============================================================
-- LAYOUT CONSTANTS  (condensed single-column main frame)
-- ============================================================
local FW, FH = 430, 430   -- expanded spacing + 3 button rows
local LC = 18
local CW = FW - 36

-- Y positions — all in one table to stay under 200-local limit
local Y = {
    -- Arena Ratings  (extra padding around dividers)
    LHEAD   = -42,  LLINE1  = -58,  LCOLHDR = -70,
    LLINE2  = -83,  L2V2    = -97,  L3V3    = -117,
    L5V5    = -137, LLINE3  = -155,
    LBANKED = -168, LLINE4  = -185,
    -- Arena Point Calculator
    MHEAD   = -200, MLINE1  = -215, MCALCHDR= -227,
    MLINE1B = -240, M2V2    = -254, M3V3    = -274,
    M5V5    = -294, MLINE2  = -312,
    -- Bottom button rows
    BTNS    = -330, BTNROW2 = -355, CHARDD  = -380,
}

-- ============================================================
-- MAIN FRAME
-- ============================================================
frame = MakeBGFrame("BeanArenaFrame", UIParent, FW, FH)
frame:SetFrameStrata("MEDIUM")
frame:SetMovable(true); frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetCenter(); SetDB("frameX", x); SetDB("frameY", y)
end)
frame:Hide()
RegisterEsc(frame)

-- ── Title — right-aligned to avoid overlap with top-left buttons ─
local titleFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -10)
titleFS:SetText("|cffFF6600«|r |cffFFD700BeanArena|r |cffFF6600»|r")
titleFS:SetJustifyH("RIGHT")

local versionFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
versionFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -27)
versionFS:SetText("|cff666666v0.2.9  •  TBC Anniversary|r")
versionFS:SetJustifyH("RIGHT")

local mainClose = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
mainClose:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
mainClose:SetScript("OnClick", function() frame:Hide() end)



-- ── Helpers scoped to main frame ─────────────────────────────
local function SmallHdr(x, y, txt)
    local f = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    f:SetText("|cffAAAAAA" .. txt .. "|r")
end

-- ══════════════════════════════════════════════════════════════
-- SECTION: CURRENT ARENA RATINGS
-- ══════════════════════════════════════════════════════════════
MakeHeader(frame, Y.LHEAD, "Current Arena Ratings", LC)
MakeLine(frame, Y.LLINE1, CW, LC)

-- Bracket | Games | Rating | Reward AP | Total AP
local LCOL = { br=LC, gms=LC+60, rat=LC+112, pts=LC+182, tot=LC+268 }
SmallHdr(LCOL.br,  Y.LCOLHDR, "Bracket")
SmallHdr(LCOL.gms, Y.LCOLHDR, "Games")
SmallHdr(LCOL.rat, Y.LCOLHDR, "Rating")
SmallHdr(LCOL.pts, Y.LCOLHDR, "Reward AP")
SmallHdr(LCOL.tot, Y.LCOLHDR, "Total AP")
MakeLine(frame, Y.LLINE2, CW, LC)

local function LiveRow(y, label)
    local l = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l:SetPoint("TOPLEFT", frame, "TOPLEFT", LCOL.br, y)
    l:SetText(label); l:SetTextColor(0.8, 0.8, 0.8)
    local function F(x) return FS(frame, x, y) end
    -- liveR=rating, liveG=games, liveP=reward AP, liveT=total AP
    return F(LCOL.rat), F(LCOL.gms), F(LCOL.pts), F(LCOL.tot)
end

local liveR2, liveG2, liveP2, liveT2 = LiveRow(Y.L2V2, "2v2")
local liveR3, liveG3, liveP3, liveT3 = LiveRow(Y.L3V3, "3v3")
local liveR5, liveG5, liveP5, liveT5 = LiveRow(Y.L5V5, "5v5")
MakeLine(frame, Y.LLINE3, CW, LC)

local apLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
apLbl:SetPoint("TOPLEFT", frame, "TOPLEFT", LC, Y.LBANKED)
apLbl:SetText("Banked AP:"); apLbl:SetTextColor(0.8, 0.8, 0.8)
local apInlineVal = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
apInlineVal:SetPoint("LEFT", apLbl, "RIGHT", 8, 0); apInlineVal:SetText("--")

-- ══════════════════════════════════════════════════════════════
-- SECTION: ARENA POINT CALCULATOR
-- ══════════════════════════════════════════════════════════════
MakeLine(frame, Y.LLINE4, CW, LC)
MakeHeader(frame, Y.MHEAD, "Arena Point Calculator", LC)
MakeLine(frame, Y.MLINE1, CW, LC)

local CALC = { lbl=LC, eb=LC+110, res=LC+240 }
SmallHdr(CALC.lbl, Y.MCALCHDR, "Bracket")
SmallHdr(CALC.eb,  Y.MCALCHDR, "Rating")
SmallHdr(CALC.res, Y.MCALCHDR, "Arena Points")
MakeLine(frame, Y.MLINE1B, CW, LC)

local editFocused = {}
local manResultFS = {}

local function MakeCalcRow(y, labelText, dbKey, bracket)
    local l = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l:SetPoint("TOPLEFT", frame, "TOPLEFT", CALC.lbl, y)
    l:SetText(labelText); l:SetTextColor(0.8, 0.8, 0.8)
    local eb = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    eb:SetSize(88, 20)
    eb:SetPoint("TOPLEFT", frame, "TOPLEFT", CALC.eb, y + 4)
    eb:SetAutoFocus(false); eb:SetNumeric(true); eb:SetMaxLetters(4)
    eb:SetText(tostring(DB(dbKey)))
    eb:SetScript("OnEditFocusGained", function() editFocused[dbKey] = true end)
    eb:SetScript("OnEditFocusLost", function(self)
        editFocused[dbKey] = nil
        SetDB(dbKey, tonumber(self:GetText()) or 0)
        BeanArena_RefreshManual()
    end)
    eb:SetScript("OnEnterPressed", function(self)
        SetDB(dbKey, tonumber(self:GetText()) or 0)
        self:ClearFocus(); BeanArena_RefreshManual()
    end)
    eb:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(DB(dbKey))); self:ClearFocus()
    end)
    local res = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    res:SetPoint("TOPLEFT", frame, "TOPLEFT", CALC.res, y); res:SetText("--")
    manResultFS[bracket] = res
    return eb
end

local man2v2Edit = MakeCalcRow(Y.M2V2, "2v2:", "manual2v2", "2v2")
local man3v3Edit = MakeCalcRow(Y.M3V3, "3v3:", "manual3v3", "3v3")
local man5v5Edit = MakeCalcRow(Y.M5V5, "5v5:", "manual5v5", "5v5")

MakeLine(frame, Y.MLINE2, CW, LC)

-- ── Row 1: Arena Gear | Honor Gear | 2v2 Notes | 3v3 Notes ──
local BTNW = math.floor((CW - 12) / 4)

local arenaGearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
arenaGearBtn:SetSize(BTNW, 20)
arenaGearBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", LC, Y.BTNS)
arenaGearBtn:SetText("Arena Gear")
arenaGearBtn:GetFontString():SetFontObject("GameFontNormalSmall")
arenaGearBtn:SetScript("OnClick", function()
    if arenaGearFrame:IsShown() then arenaGearFrame:Hide()
    else arenaGearFrame:ClearAllPoints()
        arenaGearFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0); arenaGearFrame:Show() end
end)

local honorGearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
honorGearBtn:SetSize(BTNW, 20)
honorGearBtn:SetPoint("LEFT", arenaGearBtn, "RIGHT", 4, 0)
honorGearBtn:SetText("Honor Gear")
honorGearBtn:GetFontString():SetFontObject("GameFontNormalSmall")
honorGearBtn:SetScript("OnClick", function()
    if honorGearFrame:IsShown() then honorGearFrame:Hide()
    else honorGearFrame:ClearAllPoints()
        honorGearFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0); honorGearFrame:Show() end
end)

local notes2vBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
notes2vBtn:SetSize(BTNW, 20)
notes2vBtn:SetPoint("LEFT", honorGearBtn, "RIGHT", 4, 0)
notes2vBtn:SetText("2v2 Notes")
notes2vBtn:GetFontString():SetFontObject("GameFontNormalSmall")
notes2vBtn:SetScript("OnClick", function()
    if notesFrame2:IsShown() then notesFrame2:Hide()
    else notesFrame2:ClearAllPoints()
        notesFrame2:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0); notesFrame2:Show() end
end)

local notes3vBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
notes3vBtn:SetSize(BTNW, 20)
notes3vBtn:SetPoint("LEFT", notes2vBtn, "RIGHT", 4, 0)
notes3vBtn:SetText("3v3 Notes")
notes3vBtn:GetFontString():SetFontObject("GameFontNormalSmall")
notes3vBtn:SetScript("OnClick", function()
    if notesFrame3:IsShown() then notesFrame3:Hide()
    else notesFrame3:ClearAllPoints()
        notesFrame3:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0); notesFrame3:Show() end
end)

-- ── Row 2: CC/DR Table | Honor | Info ─────────────────────────
local BTNW3 = math.floor((CW - 8) / 3)

local drMainBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
drMainBtn:SetSize(BTNW3, 20)
drMainBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", LC, Y.BTNROW2)
drMainBtn:SetText("CC/DR Table")
drMainBtn:GetFontString():SetFontObject("GameFontNormalSmall")
drMainBtn:SetScript("OnClick", function()
    if drFrame:IsShown() then drFrame:Hide()
    else drFrame:ClearAllPoints()
        drFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0); drFrame:Show() end
end)

local honorMainBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
honorMainBtn:SetSize(BTNW3, 20)
honorMainBtn:SetPoint("LEFT", drMainBtn, "RIGHT", 4, 0)
honorMainBtn:SetText("Honor")
honorMainBtn:GetFontString():SetFontObject("GameFontNormalSmall")
honorMainBtn:SetScript("OnClick", function()
    if honorFrame:IsShown() then honorFrame:Hide()
    else honorFrame:ClearAllPoints()
        honorFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0); honorFrame:Show() end
end)

local infoMainBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
infoMainBtn:SetSize(BTNW3, 20)
infoMainBtn:SetPoint("LEFT", honorMainBtn, "RIGHT", 4, 0)
infoMainBtn:SetText("Info")
infoMainBtn:GetFontString():SetFontObject("GameFontNormalSmall")
infoMainBtn:SetScript("OnClick", function()
    if infoFrame:IsShown() then infoFrame:Hide()
    else infoFrame:ClearAllPoints()
        infoFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0); infoFrame:Show() end
end)

-- ── Character dropdown row (centered) ───────────────────────
local charDDLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
charDDLbl:SetPoint("TOP", frame, "TOP", 0, Y.CHARDD + 16)
charDDLbl:SetText("|cff888888Viewing:|r")
charDDLbl:SetJustifyH("CENTER")

local charDD = CreateFrame("Frame", "BeanArenaCharDD", frame, "UIDropDownMenuTemplate")
UIDropDownMenu_SetWidth(charDD, 260)
charDD:SetPoint("TOP", frame, "TOP", 0, Y.CHARDD - 4)

-- Track which character's data is being shown (nil = current char)
local viewingSnap = nil  -- nil means live/current char

local function GetAllCharSnaps()
    local snaps = {}
    local chars = BeanArenaDB.chars or {}
    for key, snap in pairs(chars) do
        if type(snap) == "table" and snap.name then
            snaps[#snaps+1] = snap
        end
    end
    table.sort(snaps, function(a,b) return (a.name or "") < (b.name or "") end)
    return snaps
end

local function ApplyCharView(snap)
    viewingSnap = snap
    if snap == nil then
        -- Restore live data
        UIDropDownMenu_SetText(charDD, "|cffFFD700" .. (CHAR_NAME or "Current") .. " (you)|r")
        UIDropDownMenu_JustifyText(charDD, "CENTER")
        BeanArena_RefreshFrame()
        -- Reset notes windows to current char
        if notesFrame2.initialized then notesFrame2.initialized = false; if notesFrame2:IsShown() then notesFrame2:Hide(); notesFrame2:Show() end end
        if notesFrame3.initialized then notesFrame3.initialized = false; if notesFrame3:IsShown() then notesFrame3:Hide(); notesFrame3:Show() end end
    else
        UIDropDownMenu_SetText(charDD, snap.name)
        UIDropDownMenu_JustifyText(charDD, "CENTER")
        -- Push snap data into live display fields
        liveR2:SetText(snap.r2 and tostring(snap.r2) or "|cff666666--|r")
        liveG2:SetText(snap.g2 and tostring(snap.g2) or "|cff666666--|r")
        liveP2:SetText(snap.r2 and string.format("|cffFFD700%.0f|r", CalcBracketPoints(snap.r2 or 0,"2v2")) or "|cff666666--|r")
        liveR3:SetText(snap.r3 and tostring(snap.r3) or "|cff666666--|r")
        liveG3:SetText(snap.g3 and tostring(snap.g3) or "|cff666666--|r")
        liveP3:SetText(snap.r3 and string.format("|cffFFD700%.0f|r", CalcBracketPoints(snap.r3 or 0,"3v3")) or "|cff666666--|r")
        liveR5:SetText(snap.r5 and tostring(snap.r5) or "|cff666666--|r")
        liveG5:SetText(snap.g5 and tostring(snap.g5) or "|cff666666--|r")
        liveP5:SetText(snap.r5 and string.format("|cffFFD700%.0f|r", CalcBracketPoints(snap.r5 or 0,"5v5")) or "|cff666666--|r")
        local sap = snap.arenaPoints or 0
        local sp2 = snap.r2 and CalcBracketPoints(snap.r2,"2v2") or 0
        local sp3 = snap.r3 and CalcBracketPoints(snap.r3,"3v3") or 0
        local sp5 = snap.r5 and CalcBracketPoints(snap.r5,"5v5") or 0
        liveT2:SetText(sp2>0 and string.format("|cff88FF88%.0f|r", sap+sp2) or "|cff666666--|r")
        liveT3:SetText(sp3>0 and string.format("|cff88FF88%.0f|r", sap+sp3) or "|cff666666--|r")
        liveT5:SetText(sp5>0 and string.format("|cff88FF88%.0f|r", sap+sp5) or "|cff666666--|r")
        apInlineVal:SetText(sap > 0 and string.format("|cff88FF88%d|r", sap) or "|cff666666--|r")
    end
end

UIDropDownMenu_Initialize(charDD, function()
    UIDropDownMenu_JustifyText(charDD, "CENTER")
    local info = UIDropDownMenu_CreateInfo()
    -- "Current character" entry
    info.text = "|cffFFD700" .. (CHAR_NAME or "Current") .. " (you)|r"
    info.value = "SELF"
    info.notCheckable = false
    info.checked = (viewingSnap == nil)
    info.func = function() ApplyCharView(nil); CloseDropDownMenus() end
    UIDropDownMenu_AddButton(info)

    local snaps = GetAllCharSnaps()
    for _, snap in ipairs(snaps) do
        if not (snap.name == CHAR_NAME and snap.realm == CHAR_REALM) then
            local i = UIDropDownMenu_CreateInfo()
            i.text = snap.name .. " |cff888888(" .. (snap.realm or "?") .. ")|r"
            i.value = snap.name
            i.notCheckable = false
            i.checked = (viewingSnap and viewingSnap.name == snap.name)
            i.func = function()
                SnapshotCharData()
                ApplyCharView(snap)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(i)
        end
    end
end)

-- ============================================================
-- POPUP: HONOR WINDOW
-- Full honor data, marks, weekly plan, gear progress.
-- ============================================================
do
    local PW  = 430
    local PRC = 18
    local PCW = PW - 36
    local PBAR= PCW - 4
    local PH  = 374 + #HONOR_GEAR_FULL * 18 + 20

    honorFrame = MakeBGFrame("BeanArenaHonorFrame", UIParent, PW, PH)
    honorFrame:SetFrameStrata("HIGH")
    honorFrame:SetMovable(true); honorFrame:EnableMouse(true)
    honorFrame:RegisterForDrag("LeftButton")
    honorFrame:SetScript("OnDragStart", honorFrame.StartMoving)
    honorFrame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    honorFrame:Hide()
    RegisterEsc(honorFrame)

    local ht = honorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ht:SetPoint("TOP", honorFrame, "TOP", 0, -10)
    ht:SetText("|cffFFD700Honor|r")

    local hcBtn = CreateFrame("Button", nil, honorFrame, "UIPanelCloseButton")
    hcBtn:SetPoint("TOPRIGHT", honorFrame, "TOPRIGHT", -4, -4)
    hcBtn:SetScript("OnClick", function() honorFrame:Hide() end)

    local function HRow(y, lbl)
        local l = honorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetPoint("TOPLEFT", honorFrame, "TOPLEFT", PRC, y)
        l:SetText(lbl); l:SetTextColor(0.8, 0.8, 0.8)
        local v = honorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        v:SetPoint("TOPLEFT", honorFrame, "TOPLEFT", PRC + 148, y)
        v:SetText("--"); return v
    end
    local function HLine(y) MakeLine(honorFrame, y, PCW, PRC) end
    local function HHead(y, t) MakeHeader(honorFrame, y, t, PRC) end

    HHead(-28, "Current Status"); HLine(-42)
    local hHonorVal   = HRow(-53,  "Current Honor:")
    local hResetVal   = HRow(-71,  "Reset In:")
    local hArenaAPVal = HRow(-89,  "Arena Points:")

    HLine(-105)
    local hBarBG = honorFrame:CreateTexture(nil, "BACKGROUND")
    hBarBG:SetSize(PBAR, 16)
    hBarBG:SetPoint("TOPLEFT", honorFrame, "TOPLEFT", PRC, -116)
    hBarBG:SetColorTexture(0.12, 0.12, 0.12, 0.9)

    local hBarFill = honorFrame:CreateTexture(nil, "ARTWORK")
    hBarFill:SetSize(1, 16)
    hBarFill:SetPoint("TOPLEFT", hBarBG, "TOPLEFT", 0, 0)
    hBarFill:SetColorTexture(0.85, 0.75, 0.1, 1)

    local hBarText = honorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hBarText:SetPoint("CENTER", hBarBG, "CENTER", 0, 0)
    hBarText:SetText("0 / 75,000")

    local hCapWarn = honorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hCapWarn:SetPoint("TOPLEFT", honorFrame, "TOPLEFT", PRC, -138)
    hCapWarn:SetText("")

    HLine(-153); HHead(-163, "PvP Marks in Bags"); HLine(-177)
    local hMkAV   = HRow(-188, "AV:")
    local hMkWSG  = HRow(-206, "WSG:")
    local hMkAB   = HRow(-224, "AB:")
    local hMkEotS = HRow(-242, "EotS:")

    HLine(-258); HHead(-268, "Weekly Honor Plan"); HLine(-282)
    local hPlanText = honorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hPlanText:SetPoint("TOPLEFT", honorFrame, "TOPLEFT", PRC, -293)
    hPlanText:SetWidth(PCW - 8); hPlanText:SetJustifyH("LEFT")
    hPlanText:SetText("--")

    HLine(-318); HHead(-328, "Honor Gear Progress"); HLine(-342)

    local HGC = { slot=PRC, marks=PRC+55, honor=PRC+190, status=PRC+305 }
    local function HSHdr(x, y, t)
        local f = honorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f:SetPoint("TOPLEFT", honorFrame, "TOPLEFT", x, y)
        f:SetText("|cffAAAAAA" .. t .. "|r")
    end
    HSHdr(HGC.slot, -352, "Slot"); HSHdr(HGC.marks, -352, "Marks Needed")
    HSHdr(HGC.honor, -352, "Honor"); HSHdr(HGC.status, -352, "Ready?")
    MakeLine(honorFrame, -363, PCW, PRC)

    local honorGearRowsH = {}
    for i, gear in ipairs(HONOR_GEAR_FULL) do
        local y = -374 - (i - 1) * 18
        local slotFS = honorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        slotFS:SetPoint("TOPLEFT", honorFrame, "TOPLEFT", HGC.slot, y)
        slotFS:SetText(gear.slot); slotFS:SetTextColor(0.85, 0.85, 0.85)
        local marksFS = honorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        marksFS:SetPoint("TOPLEFT", honorFrame, "TOPLEFT", HGC.marks, y)
        marksFS:SetText("--")
        local honorFS = honorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        honorFS:SetPoint("TOPLEFT", honorFrame, "TOPLEFT", HGC.honor, y)
        honorFS:SetText("--")
        local statusFS = honorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        statusFS:SetPoint("TOPLEFT", honorFrame, "TOPLEFT", HGC.status, y)
        statusFS:SetText("--")
        honorGearRowsH[i] = { gear=gear, marksFS=marksFS, honorFS=honorFS, statusFS=statusFS }
    end

    local function RefreshHonorFrame()
        local honor = GetCurrentHonor()
        local ap    = GetCurrentArenaPoints()
        local marks = GetPvPMarkCounts()
        local fmt   = BreakUpLargeNumbers or tostring

        hHonorVal:SetText(string.format("|cffFFD700%s|r", fmt(honor)))
        hArenaAPVal:SetText(string.format("|cff88FF88%s|r", fmt(ap)))
        hResetVal:SetText("|cff00CCFF" .. GetDaysToReset() .. "|r")

        hMkAV:SetText(string.format("|cffFFD700%d|r", marks.AV or 0))
        hMkWSG:SetText(string.format("|cffFFD700%d|r", marks.WSG or 0))
        hMkAB:SetText(string.format("|cffFFD700%d|r", marks.AB or 0))
        hMkEotS:SetText(string.format("|cffFFD700%d|r", marks.EotS or 0))

        local pct = math.min(1, honor / HONOR_CAP)
        hBarFill:SetWidth(math.max(1, math.floor(PBAR * pct)))
        hBarText:SetText(string.format("%s / 75,000  (%d%%)", fmt(honor), math.floor(pct * 100)))
        if honor >= 70000 then
            hCapWarn:SetText("|cffFF4444Warning: Near cap — spend before 75k or gains are lost!|r")
            hBarFill:SetColorTexture(1, 0.2, 0.2, 1)
        elseif honor >= 55000 then
            hCapWarn:SetText("|cffFFAA00Getting full — consider spending soon.|r")
            hBarFill:SetColorTexture(1, 0.7, 0.1, 1)
        else
            hCapWarn:SetText("")
            hBarFill:SetColorTexture(0.85, 0.75, 0.1, 1)
        end

        local toFill = math.max(0, HONOR_CAP - honor)
        if toFill == 0 then
            hPlanText:SetText("|cff00FF00Honor capped! Time to spend.|r")
        else
            hPlanText:SetText(string.format(
                "|cffAAAAAA~%d AV wins to cap|r  |cff666666(or ~%d WSG/AB/EotS)|r",
                math.ceil(toFill / 419), math.ceil(toFill / 209)))
        end

        for _, row in ipairs(honorGearRowsH) do
            local gear     = row.gear
            local honorMet = honor >= gear.honor
            local allMet   = true
            local mparts   = {}
            for bg, req in pairs(gear.marks) do
                local have = marks[bg] or 0
                local met  = have >= req
                if not met then allMet = false end
                table.insert(mparts, string.format("%s|cffAAAAAA/%d %s|r",
                    met and string.format("|cff00FF00%d", have)
                        or  string.format("|cffFF4444%d", have), req, bg))
            end
            table.sort(mparts)
            row.marksFS:SetText(table.concat(mparts, "  "))
            local hc = honorMet and "00FF00" or "FF4444"
            row.honorFS:SetText(string.format("|cff%s%s|r|cffAAAAAA/%s|r", hc, fmt(honor), fmt(gear.honor)))
            row.statusFS:SetText(honorMet and allMet and "|cff00FF00Ready!|r" or "|cffAAAAAA...|r")
        end
    end

    honorFrame:SetScript("OnShow", RefreshHonorFrame)
    BeanArena_RefreshHonorFrame = RefreshHonorFrame
end

-- ============================================================
-- POPUP: ARENA GEAR COSTS
-- ============================================================
do
    local PW      = 360
    local NUM     = #ARENA_GEAR_FULL
    local ROW_H   = 18
    local PH      = 80 + NUM * ROW_H + 20
    local INNER_W = PW - 32
    local AGC     = { slot=18, ap=200, rating=280 }

    arenaGearFrame = MakeBGFrame("BeanArenaArenaGearFrame", UIParent, PW, PH)
    arenaGearFrame:SetFrameStrata("HIGH")
    arenaGearFrame:SetMovable(true); arenaGearFrame:EnableMouse(true)
    arenaGearFrame:RegisterForDrag("LeftButton")
    arenaGearFrame:SetScript("OnDragStart", arenaGearFrame.StartMoving)
    arenaGearFrame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    arenaGearFrame:Hide()
    RegisterEsc(arenaGearFrame)

    local t = arenaGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOP", arenaGearFrame, "TOP", 0, -14)
    t:SetText("|cffFFD700Arena Gear Costs|r")

    local c = CreateFrame("Button", nil, arenaGearFrame, "UIPanelCloseButton")
    c:SetPoint("TOPRIGHT", arenaGearFrame, "TOPRIGHT", -4, -4)
    c:SetScript("OnClick", function() arenaGearFrame:Hide() end)

    local sub = arenaGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("TOP", arenaGearFrame, "TOP", 0, -30)
    sub:SetText("|cffAAAAAASeason 1  —  Arena Points required|r")
    MakeLine(arenaGearFrame, -42, INNER_W, 16)

    local function AGHdr(x, y, txt)
        local f = arenaGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f:SetPoint("TOPLEFT", arenaGearFrame, "TOPLEFT", x, y)
        f:SetText("|cffAAAAAA" .. txt .. "|r")
    end
    AGHdr(AGC.slot, -50, "Item Slot"); AGHdr(AGC.ap, -50, "AP Cost"); AGHdr(AGC.rating, -50, "Min Rating")
    MakeLine(arenaGearFrame, -61, INNER_W, 16)

    local agRows = {}
    for i, item in ipairs(ARENA_GEAR_FULL) do
        local y = -70 - (i - 1) * ROW_H
        local slotFS = arenaGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        slotFS:SetPoint("TOPLEFT", arenaGearFrame, "TOPLEFT", AGC.slot, y)
        slotFS:SetText(item.slot); slotFS:SetTextColor(0.85, 0.85, 0.85)
        local apFS = arenaGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        apFS:SetPoint("TOPLEFT", arenaGearFrame, "TOPLEFT", AGC.ap, y)
        apFS:SetText(string.format("|cffFFD700%d|r", item.ap))
        local ratingFS = arenaGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ratingFS:SetPoint("TOPLEFT", arenaGearFrame, "TOPLEFT", AGC.rating, y)
        ratingFS:SetText(item.rating > 0 and tostring(item.rating) or "|cff666666None|r")
        agRows[i] = { ratingFS=ratingFS, item=item }
    end

    MakeLine(arenaGearFrame, -70 - NUM * ROW_H, INNER_W, 16)
    local foot = arenaGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    foot:SetPoint("BOTTOMLEFT", arenaGearFrame, "BOTTOMLEFT", 18, 10)
    foot:SetText("|cff888888Rating shown in |cffFF4444red|r|cff888888 if below your best.|r")

    BeanArena_RefreshArenaGearPopup = function()
        local r2, r3, r5 = GetLiveRatings()
        local best = math.max(r2, r3, r5)
        for _, row in ipairs(agRows) do
            if row.item.rating > 0 then
                if best >= row.item.rating then
                    row.ratingFS:SetText(string.format("|cff00FF00%d|r", row.item.rating))
                else
                    row.ratingFS:SetText(string.format("|cffFF4444%d|r", row.item.rating))
                end
            end
        end
    end
    arenaGearFrame:SetScript("OnShow", BeanArena_RefreshArenaGearPopup)
end

-- ============================================================
-- POPUP: HONOR GEAR COSTS
-- ============================================================
do
    local PW      = 500
    local NUM     = #HONOR_GEAR_FULL
    local ROW_H   = 18
    local PH      = 80 + NUM * ROW_H + 20
    local INNER_W = PW - 32
    local HGP     = { slot=18, honor=110, marks=230, have=340 }

    honorGearFrame = MakeBGFrame("BeanArenaHonorGearFrame", UIParent, PW, PH)
    honorGearFrame:SetFrameStrata("HIGH")
    honorGearFrame:SetMovable(true); honorGearFrame:EnableMouse(true)
    honorGearFrame:RegisterForDrag("LeftButton")
    honorGearFrame:SetScript("OnDragStart", honorGearFrame.StartMoving)
    honorGearFrame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    honorGearFrame:Hide()
    RegisterEsc(honorGearFrame)

    local t = honorGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOP", honorGearFrame, "TOP", 0, -14)
    t:SetText("|cffFFD700Honor Gear Costs|r")

    local c = CreateFrame("Button", nil, honorGearFrame, "UIPanelCloseButton")
    c:SetPoint("TOPRIGHT", honorGearFrame, "TOPRIGHT", -4, -4)
    c:SetScript("OnClick", function() honorGearFrame:Hide() end)

    local sub = honorGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("TOP", honorGearFrame, "TOP", 0, -30)
    sub:SetText("|cffAAAAAASeason 1  —  Honor + BG Marks required|r")
    MakeLine(honorGearFrame, -42, INNER_W, 16)

    local function HGHdr(x, y, txt)
        local f = honorGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f:SetPoint("TOPLEFT", honorGearFrame, "TOPLEFT", x, y)
        f:SetText("|cffAAAAAA" .. txt .. "|r")
    end
    HGHdr(HGP.slot,-50,"Item Slot"); HGHdr(HGP.honor,-50,"Honor Cost")
    HGHdr(HGP.marks,-50,"Marks Req."); HGHdr(HGP.have,-50,"You Have")
    MakeLine(honorGearFrame, -61, INNER_W, 16)

    local hgRows = {}
    for i, gear in ipairs(HONOR_GEAR_FULL) do
        local y = -70 - (i - 1) * ROW_H
        local slotFS = honorGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        slotFS:SetPoint("TOPLEFT", honorGearFrame, "TOPLEFT", HGP.slot, y)
        slotFS:SetText(gear.slot); slotFS:SetTextColor(0.85, 0.85, 0.85)
        local honorFS = honorGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        honorFS:SetPoint("TOPLEFT", honorGearFrame, "TOPLEFT", HGP.honor, y)
        honorFS:SetText(string.format("|cffFFD700%d|r", gear.honor))
        local reqParts = {}
        for bg, req in pairs(gear.marks) do table.insert(reqParts, req .. " " .. bg) end
        table.sort(reqParts)
        local marksReqFS = honorGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        marksReqFS:SetPoint("TOPLEFT", honorGearFrame, "TOPLEFT", HGP.marks, y)
        marksReqFS:SetText("|cffAAAAAA" .. table.concat(reqParts, ", ") .. "|r")
        local haveFS = honorGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        haveFS:SetPoint("TOPLEFT", honorGearFrame, "TOPLEFT", HGP.have, y)
        haveFS:SetText("--")
        hgRows[i] = { gear=gear, haveFS=haveFS }
    end

    MakeLine(honorGearFrame, -70 - NUM * ROW_H, INNER_W, 16)
    local foot = honorGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    foot:SetPoint("BOTTOMLEFT", honorGearFrame, "BOTTOMLEFT", 18, 10)
    foot:SetText("|cff888888|cff00FF00Green|r|cff888888 = met.  |cffFF4444Red|r|cff888888 = still needed.|r")

    BeanArena_RefreshHonorGearPopup = function()
        local honor = GetCurrentHonor()
        local marks = GetPvPMarkCounts()
        local fmt   = BreakUpLargeNumbers or tostring
        for _, row in ipairs(hgRows) do
            local gear     = row.gear
            local honorMet = honor >= gear.honor
            local parts    = {}
            for bg, req in pairs(gear.marks) do
                local have = marks[bg] or 0
                local met  = have >= req
                table.insert(parts, string.format("%s|cffAAAAAA/%d %s|r",
                    met  and string.format("|cff00FF00%d", have)
                         or  string.format("|cffFF4444%d", have), req, bg))
            end
            table.sort(parts)
            local hColor   = honorMet and "00FF00" or "FF4444"
            local honorStr = string.format("|cff%s%s/%s hon|r  ", hColor, fmt(honor), fmt(gear.honor))
            row.haveFS:SetText(honorStr .. table.concat(parts, "  "))
        end
    end
    honorGearFrame:SetScript("OnShow", BeanArena_RefreshHonorGearPopup)
end

-- ============================================================
-- POPUP: COMP NOTES  v0.2.8
-- Table layout per your mockup:
--   [icon+DD1] [icon+DD2] [icon+DD3?] | [diff] | [confidence] | [notes]
-- Single-row per entry. Built once, never destroyed on re-show.
-- Data in BeanArenaDB.compEntries[bracket].
-- ============================================================

-- ── Spec list ────────────────────────────────────────────────
local SPECS = {
    { label="Sub Rogue",      icon="Interface\\Icons\\ClassIcon_Rogue"   },
    { label="Combat Rogue",   icon="Interface\\Icons\\ClassIcon_Rogue"   },
    { label="Frost Mage",     icon="Interface\\Icons\\ClassIcon_Mage"    },
    { label="PomPyro Mage",   icon="Interface\\Icons\\ClassIcon_Mage"    },
    { label="Arcane Mage",    icon="Interface\\Icons\\ClassIcon_Mage"    },
    { label="Resto Druid",    icon="Interface\\Icons\\ClassIcon_Druid"   },
    { label="Feral Druid",    icon="Interface\\Icons\\ClassIcon_Druid"   },
    { label="Balance Druid",  icon="Interface\\Icons\\ClassIcon_Druid"   },
    { label="Arms Warrior",   icon="Interface\\Icons\\ClassIcon_Warrior" },
    { label="Fury Warrior",   icon="Interface\\Icons\\ClassIcon_Warrior" },
    { label="Ele Shaman",     icon="Interface\\Icons\\ClassIcon_Shaman"  },
    { label="Enh Shaman",     icon="Interface\\Icons\\ClassIcon_Shaman"  },
    { label="Resto Shaman",   icon="Interface\\Icons\\ClassIcon_Shaman"  },
    { label="SL Warlock",     icon="Interface\\Icons\\ClassIcon_Warlock" },
    { label="Destro Warlock", icon="Interface\\Icons\\ClassIcon_Warlock" },
    { label="UA Warlock",     icon="Interface\\Icons\\ClassIcon_Warlock" },
    { label="BM Hunter",      icon="Interface\\Icons\\ClassIcon_Hunter"  },
    { label="MM Hunter",      icon="Interface\\Icons\\ClassIcon_Hunter"  },
    { label="Ret Paladin",    icon="Interface\\Icons\\ClassIcon_Paladin" },
    { label="Holy Paladin",   icon="Interface\\Icons\\ClassIcon_Paladin" },
    { label="Shadow Priest",  icon="Interface\\Icons\\ClassIcon_Priest"  },
    { label="Disc Priest",    icon="Interface\\Icons\\ClassIcon_Priest"  },
    { label="Holy Priest",    icon="Interface\\Icons\\ClassIcon_Priest"  },
}

-- ── Difficulty levels — click to cycle ───────────────────────
local DIFF_OPTS = {
    { label="Easy",        color="00EE77" },
    { label="Medium",      color="FFD700" },
    { label="Hard",        color="FF4444" },
    { label="Counters Us", color="CC44FF" },
}

-- ── Confidence levels — click to cycle ───────────────────────
local CONF_OPTS = {
    { label="Solid",          color="00EE77" },
    { label="Could Use Work", color="FFD700" },
    { label="Weak",           color="FF4444" },
    { label="idk",            color="888888" },
}

-- ── DB accessor (per-character) ───────────────────────────────
local function NotesDB(bracket)
    return GetCharNotes(bracket)
end

-- ── Window builder ─────────────────────────────────────────────
local function BuildNotesWindow(frameName, bracketLabel, numOpps)
    -- Table column widths
    local PH_DEF   = 460
    local PAD      = 8
    local ROW_H    = 52               -- height of each table row
    local COL_DD   = numOpps==3 and 140 or 160   -- each spec dropdown column
    local COL_DIFF = 110              -- difficulty column (icon + label)
    local COL_CONF = 105              -- confidence column (text cycle)
    local COL_NOTE = 120              -- notes: ~17 chars @ GameFontNormalSmall
    -- Total width: spec cols + diff + conf + note + dividers + scrollbar
    local PW = numOpps * COL_DD + COL_DIFF + COL_CONF + COL_NOTE
              + PAD * (numOpps + 4) + 28 + 4

    local nf = MakeBGFrame(frameName, UIParent, PW, PH_DEF)
    nf:SetFrameStrata("HIGH")
    nf:SetMovable(true); nf:EnableMouse(true)
    nf:RegisterForDrag("LeftButton")
    nf:SetScript("OnDragStart", nf.StartMoving)
    nf:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)
    nf:SetResizable(true)
    if nf.SetResizeBounds then nf:SetResizeBounds(500, 300, 1200, 900)
    elseif nf.SetMinResize then nf:SetMinResize(500, 300) end
    nf:Hide(); RegisterEsc(nf)

    -- Title
    local nTitle = nf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nTitle:SetPoint("TOP", nf, "TOP", 0, -12)
    nTitle:SetText("|cffFFD700" .. bracketLabel .. " Comp Notes|r")

    local nClose = CreateFrame("Button", nil, nf, "UIPanelCloseButton")
    nClose:SetPoint("TOPRIGHT", nf, "TOPRIGHT", -4, -4)
    nClose:SetScript("OnClick", function() nf:Hide() end)

    -- Column headers
    local HDR_Y = -44
    local hx = PAD
    for n = 1, numOpps do
        local hdr = nf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hdr:SetPoint("TOPLEFT", nf, "TOPLEFT", hx + 4, HDR_Y)
        hdr:SetText("|cff888888Class " .. n .. "|r")
        hx = hx + COL_DD + PAD
    end
    local hdrDiff = nf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrDiff:SetPoint("TOPLEFT", nf, "TOPLEFT", hx + 4, HDR_Y)
    hdrDiff:SetText("|cff888888Difficulty|r")
    hx = hx + COL_DIFF + PAD
    local hdrConf = nf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrConf:SetPoint("TOPLEFT", nf, "TOPLEFT", hx + 4, HDR_Y)
    hdrConf:SetText("|cff888888Confidence|r")
    hx = hx + COL_CONF + PAD
    local hdrNote = nf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrNote:SetPoint("TOPLEFT", nf, "TOPLEFT", hx + 4, HDR_Y)
    hdrNote:SetText("|cff888888Notes|r")
    MakeLine(nf, HDR_Y - 12, PW - 32, PAD - 2)

    -- Resize grip
    local grip = CreateFrame("Button", nil, nf)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", nf, "BOTTOMRIGHT", -2, 2)
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrab-Down")
    grip:SetScript("OnMouseDown", function() nf:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp",   function() nf:StopMovingOrSizing() end)

    -- Add Comp button
    local addBtn = CreateFrame("Button", nil, nf, "UIPanelButtonTemplate")
    addBtn:SetSize(110, 22)
    addBtn:SetPoint("BOTTOMLEFT", nf, "BOTTOMLEFT", PAD, 22)
    addBtn:SetText("+ Add Comp")
    addBtn:GetFontString():SetFontObject("GameFontNormalSmall")

    -- Scroll area (sits between headers and add button)
    local SCROLL_TOP = HDR_Y - 16
    local nScr = CreateFrame("ScrollFrame", frameName.."Scr", nf, "UIPanelScrollFrameTemplate")
    nScr:SetPoint("TOPLEFT",     nf, "TOPLEFT",     PAD - 4, SCROLL_TOP)
    nScr:SetPoint("BOTTOMRIGHT", nf, "BOTTOMRIGHT", -26, 46)

    -- Content frame — rows are anchored sequentially to this
    local nCnt = CreateFrame("Frame", nil, nScr)
    nCnt:SetWidth(PW - 28 - PAD * 2)
    nCnt:SetHeight(10)
    nScr:SetScrollChild(nCnt)

    -- entries: array of row data tables, built once, never rebuilt
    local entries = {}
    local initialized = false

    -- ── serial for unique DD frame names ─────────────────────
    local ddSerial = 0

    -- ── Build one spec dropdown ───────────────────────────────
    -- Returns: setFn(idx), getFn()
    local function MakeSpecDD(parent, initIdx, onChange)
        ddSerial = ddSerial + 1
        local ddName = frameName .. "DD" .. ddSerial
        local dd = CreateFrame("Frame", ddName, parent, "UIDropDownMenuTemplate")
        local ddW = COL_DD - 22   -- SetWidth value (frame is ~22px wider)
        UIDropDownMenu_SetWidth(dd, ddW)
        dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -2)

        -- Class icon overlaid on left side of button
        local ic = parent:CreateTexture(nil, "OVERLAY")
        ic:SetSize(16, 16)
        ic:SetPoint("TOPLEFT", dd, "TOPLEFT", 4, -7)

        local curIdx = initIdx or 0

        local function Refresh()
            if curIdx > 0 and SPECS[curIdx] then
                UIDropDownMenu_SetText(dd, "  " .. SPECS[curIdx].label)
                ic:SetTexture(SPECS[curIdx].icon)
                ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                ic:Show()
            else
                UIDropDownMenu_SetText(dd, "Select")
                ic:SetTexture(nil)
            end
        end

        UIDropDownMenu_Initialize(dd, function()
            for i, sp in ipairs(SPECS) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = sp.label; info.value = i
                info.checked = (i == curIdx); info.hasArrow = false
                info.func = function(self)
                    curIdx = self.value; Refresh()
                    if onChange then onChange() end
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        Refresh()
        return dd,
               function(idx) curIdx = idx; Refresh() end,
               function() return curIdx end
    end

    -- ── Difficulty cycle button (text only, centered, same as MakeConfWidget) ─
    local function MakeDiffWidget(parent, initDiff, onChange)
        local dIdx = initDiff or 1
        local btn = CreateFrame("Button", nil, parent)
        btn:SetAllPoints(parent)
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        local dLbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dLbl:SetPoint("CENTER", btn, "CENTER", 0, 0)
        dLbl:SetWidth(COL_DIFF - 6)
        dLbl:SetJustifyH("CENTER")
        local function Refresh()
            local d = DIFF_OPTS[dIdx]
            dLbl:SetText("|cff" .. d.color .. d.label .. "|r")
        end
        Refresh()
        btn:SetScript("OnClick", function()
            dIdx = (dIdx % #DIFF_OPTS) + 1; Refresh()
            if onChange then onChange() end
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Click to change difficulty", 1,1,1); GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return function(d) dIdx=d; Refresh() end, function() return dIdx end
    end

    -- ── Confidence cycle button (text only, click to cycle) ──────
    local function MakeConfWidget(parent, initConf, onChange)
        local cIdx = initConf or 1
        local btn = CreateFrame("Button", nil, parent)
        btn:SetAllPoints(parent)
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        local cLbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cLbl:SetPoint("CENTER", btn, "CENTER", 0, 0)
        cLbl:SetWidth(COL_CONF - 6)
        cLbl:SetJustifyH("CENTER")
        local function Refresh()
            local c = CONF_OPTS[cIdx]
            cLbl:SetText("|cff" .. c.color .. c.label .. "|r")
        end
        Refresh()
        btn:SetScript("OnClick", function()
            cIdx = (cIdx % #CONF_OPTS) + 1; Refresh()
            if onChange then onChange() end
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Click to change confidence", 1,1,1); GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return function(c) cIdx=c; Refresh() end, function() return cIdx end
    end

    -- ── Save one row to DB ────────────────────────────────────
    local function SaveRow(r, idx)
        local db = NotesDB(bracketLabel)
        db[idx] = {
            specs = {},
            diff  = r.getDiff(),
            conf  = r.getConf(),
            note  = r.getNoteText(),
        }
        for n = 1, numOpps do db[idx].specs[n] = r.getSpec[n]() end
    end

    -- ── SaveAll ───────────────────────────────────────────────
    local function SaveAll()
        local db = NotesDB(bracketLabel)
        while #db > 0 do table.remove(db) end
        for i, r in ipairs(entries) do
            if r.visible then SaveRow(r, i) end
        end
    end

    -- ── Reposition all visible rows sequentially ──────────────
    local function Reflow()
        local y = 0
        local count = 0
        for _, r in ipairs(entries) do
            if r.visible then
                r.row:ClearAllPoints()
                r.row:SetPoint("TOPLEFT", nCnt, "TOPLEFT", 0, y)
                r.row:Show()
                y = y - (ROW_H + 1)
                count = count + 1
            end
        end
        nCnt:SetHeight(math.max(10, count * (ROW_H + 1)))
    end

    -- ── Build one table row (called once per entry ever) ──────
    local function BuildRow(rowIdx, initData)
        -- The row is a plain Frame parented directly to nCnt
        local row = CreateFrame("Frame", nil, nCnt)
        row:SetSize(nCnt:GetWidth(), ROW_H)
        -- Don't SetPoint here — Reflow() handles all positioning

        -- Alternating row background
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(rowIdx%2==0 and 0.06 or 0.12, 0.04, 0.10, 0.6)

        -- Thin top border line
        local border = row:CreateTexture(nil, "BORDER")
        border:SetSize(2000, 1)
        border:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        border:SetColorTexture(0.3, 0.3, 0.3, 0.5)

        -- Delete (X) button — top-right of row
        local delBtn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        delBtn:SetSize(16, 16)
        delBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)

        -- ── Lay out columns using cell sub-frames ─────────────
        -- Each cell is a frame with fixed width, positioned LEFT→RIGHT
        local cx = 0

        local specGetters = {}
        local specSetters = {}
        for n = 1, numOpps do
            local cell = CreateFrame("Frame", nil, row)
            cell:SetSize(COL_DD, ROW_H)
            cell:SetPoint("TOPLEFT", row, "TOPLEFT", cx, 0)
            cx = cx + COL_DD + PAD

            local initIdx = initData and initData.specs and initData.specs[n] or 0
            local dd, setFn, getFn = MakeSpecDD(cell, initIdx, function()
                -- find this row in entries and save
                for i, r2 in ipairs(entries) do
                    if r2.row == row then SaveRow(r2, i) end
                end
            end)
            specSetters[n] = setFn
            specGetters[n] = getFn

            -- Column divider
            if n < numOpps then
                local vline = row:CreateTexture(nil, "ARTWORK")
                vline:SetSize(1, ROW_H)
                vline:SetPoint("TOPLEFT", row, "TOPLEFT", cx - PAD/2, 0)
                vline:SetColorTexture(0.25, 0.25, 0.25, 0.6)
            end
        end

        -- Difficulty cell
        local diffCell = CreateFrame("Frame", nil, row)
        diffCell:SetSize(COL_DIFF, ROW_H)
        diffCell:SetPoint("TOPLEFT", row, "TOPLEFT", cx, 0)
        cx = cx + COL_DIFF + PAD
        local vlineD = row:CreateTexture(nil, "ARTWORK")
        vlineD:SetSize(1, ROW_H)
        vlineD:SetPoint("TOPLEFT", row, "TOPLEFT", cx - PAD/2, 0)
        vlineD:SetColorTexture(0.25, 0.25, 0.25, 0.6)

        local setDiff, getDiff = MakeDiffWidget(diffCell,
            initData and initData.diff or 1, function()
                for i, r2 in ipairs(entries) do
                    if r2.row == row then SaveRow(r2, i) end
                end
            end)

        -- Confidence cell
        local confCell = CreateFrame("Frame", nil, row)
        confCell:SetSize(COL_CONF, ROW_H)
        confCell:SetPoint("TOPLEFT", row, "TOPLEFT", cx, 0)
        cx = cx + COL_CONF + PAD
        local vlineC = row:CreateTexture(nil, "ARTWORK")
        vlineC:SetSize(1, ROW_H)
        vlineC:SetPoint("TOPLEFT", row, "TOPLEFT", cx - PAD/2, 0)
        vlineC:SetColorTexture(0.25, 0.25, 0.25, 0.6)

        local setConf, getConf = MakeConfWidget(confCell,
            initData and initData.conf or 1, function()
                for i, r2 in ipairs(entries) do
                    if r2.row == row then SaveRow(r2, i) end
                end
            end)

        -- Notes cell — plain EditBox (no InputBoxTemplate, avoids the rounded frame)
        local noteCell = CreateFrame("Frame", nil, row)
        noteCell:SetSize(COL_NOTE, ROW_H)
        noteCell:SetPoint("TOPLEFT", row, "TOPLEFT", cx, 0)

        local eb = CreateFrame("EditBox", nil, noteCell)
        eb:SetPoint("TOPLEFT",     noteCell, "TOPLEFT",     2, -4)
        eb:SetPoint("BOTTOMRIGHT", noteCell, "BOTTOMRIGHT", -2, 4)
        eb:SetAutoFocus(false)
        eb:SetMultiLine(true)
        eb:SetMaxLetters(400)
        eb:SetFontObject("GameFontNormalSmall")

        local savedNote = initData and initData.note or ""
        eb:SetText(savedNote)
        if savedNote ~= "" then eb:SetTextColor(0.9, 0.85, 0.65)
        else                     eb:SetTextColor(0.4, 0.4, 0.4) end
        eb:SetScript("OnEditFocusGained", function(self) self:SetTextColor(0.9, 0.85, 0.65) end)
        eb:SetScript("OnEditFocusLost", function(self)
            if self:GetText() == "" then self:SetTextColor(0.4, 0.4, 0.4) end
            for i, r2 in ipairs(entries) do
                if r2.row == row then SaveRow(r2, i) end
            end
        end)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        local entryRef = {
            row         = row,
            eb          = eb,
            getDiff     = getDiff,
            getConf     = getConf,
            setDiff     = setDiff,
            setConf     = setConf,
            getSpec     = specGetters,
            setSpec     = specSetters,
            getNoteText = function() return eb:GetText() end,
            visible     = true,
        }

        delBtn:SetScript("OnClick", function()
            entryRef.visible = false
            row:Hide()
            for i, r2 in ipairs(entries) do
                if r2 == entryRef then table.remove(entries, i); break end
            end
            Reflow()
            SaveAll()
        end)

        return entryRef
    end

    -- ── Load DB into rows (called once on first show) ─────────
    local function LoadFromDB()
        local db = NotesDB(bracketLabel)
        for i, saved in ipairs(db) do
            local r = BuildRow(i, saved)
            table.insert(entries, r)
        end
        Reflow()
    end

    -- ── Add button ────────────────────────────────────────────
    addBtn:SetScript("OnClick", function()
        local idx = #entries + 1
        local r = BuildRow(idx, nil)
        table.insert(entries, r)
        Reflow()
        -- Save blank row to DB so it persists
        local db = NotesDB(bracketLabel)
        local row = { specs={}, diff=1, conf=1, note="" }
        for n = 1, numOpps do row.specs[n] = 0 end
        table.insert(db, row)
    end)

    -- ── First show: load DB; subsequent shows: just display ───
    nf:SetScript("OnShow", function()
        if not initialized then
            initialized = true
            LoadFromDB()
        end
    end)

    return nf
end

notesFrame2 = BuildNotesWindow("BeanArenaNotes2v2", "2v2", 2)
notesFrame3 = BuildNotesWindow("BeanArenaNotes3v3", "3v3", 3)

-- ============================================================
-- FORWARD DECLARATION ASSIGNMENT
-- ============================================================
OpenBeanArena = function()
    frame:Show(); BeanArena_RefreshFrame()
end

-- ============================================================
-- COMMANDS FRAME  (updated to /ba)
-- ============================================================
local COMMANDS_LIST = {
    { cmd="/ba",           desc="Toggle main window"        },
    { cmd="/ba honor",     desc="Toggle honor window"       },
    { cmd="/ba cc",        desc="Toggle CC/DR table"        },
    { cmd="/ba gear",      desc="Toggle arena gear window"  },
    { cmd="/ba hgear",     desc="Toggle honor gear window"  },
    { cmd="/ba 2s",        desc="Toggle 2v2 comp notes"     },
    { cmd="/ba 3s",        desc="Toggle 3v3 comp notes"     },
    { cmd="/ba info",      desc="Toggle info/help window"   },
    { cmd="/ba chars",     desc="View other characters"     },
    { cmd="/ba commands",  desc="Toggle this window"        },
    { cmd="/ba points",    desc="Print point breakdown"     },
    { cmd="/ba reset",     desc="Print time until reset"    },
    { cmd="/ba help",      desc="Print help in chat"        },
}

cFrame = MakeBGFrame("BeanArenaCommandsFrame", UIParent, 340, 42 + #COMMANDS_LIST * 24)
cFrame:SetFrameStrata("HIGH")
cFrame:SetMovable(true); cFrame:EnableMouse(true)
cFrame:RegisterForDrag("LeftButton")
cFrame:SetScript("OnDragStart", cFrame.StartMoving)
cFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
cFrame:Hide(); RegisterEsc(cFrame)

local cTitle = cFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
cTitle:SetPoint("TOP", cFrame, "TOP", 0, -14)
cTitle:SetText("|cffFFD700BeanArena Commands|r")

local cClose = CreateFrame("Button", nil, cFrame, "UIPanelCloseButton")
cClose:SetPoint("TOPRIGHT", cFrame, "TOPRIGHT", -4, -4)
cClose:SetScript("OnClick", function() cFrame:Hide() end)

for i, entry in ipairs(COMMANDS_LIST) do
    local y = -38 - (i - 1) * 24
    if i > 1 then
        local div = cFrame:CreateTexture(nil, "ARTWORK")
        div:SetSize(304, 1); div:SetPoint("TOPLEFT", cFrame, "TOPLEFT", 18, y + 5)
        div:SetColorTexture(0.3, 0.3, 0.3, 0.3)
    end
    local cmdFS = cFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cmdFS:SetPoint("TOPLEFT", cFrame, "TOPLEFT", 18, y)
    cmdFS:SetText("|cff00CCFF" .. entry.cmd .. "|r")
    local descFS = cFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descFS:SetPoint("TOPLEFT", cFrame, "TOPLEFT", 160, y)
    descFS:SetText("|cffAAAAAA" .. entry.desc .. "|r")
end

local aliasFS = cFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
aliasFS:SetPoint("BOTTOMLEFT", cFrame, "BOTTOMLEFT", 18, 10)
aliasFS:SetText("|cff888888/beanarena also works in place of /ba|r")

OpenCommands = function()
    if cFrame:IsShown() then cFrame:Hide(); return end
    cFrame:ClearAllPoints()
    cFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    cFrame:Show()
end

-- ============================================================
-- INFO FRAME  (addon usage guide)
-- ============================================================
do
    local IW, IH = 420, 560
    infoFrame = MakeBGFrame("BeanArenaInfoFrame", UIParent, IW, IH)
    infoFrame:SetFrameStrata("HIGH")
    infoFrame:SetMovable(true); infoFrame:EnableMouse(true)
    infoFrame:RegisterForDrag("LeftButton")
    infoFrame:SetScript("OnDragStart", infoFrame.StartMoving)
    infoFrame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    infoFrame:Hide(); RegisterEsc(infoFrame)

    local iClose = CreateFrame("Button", nil, infoFrame, "UIPanelCloseButton")
    iClose:SetPoint("TOPRIGHT", infoFrame, "TOPRIGHT", -4, -4)
    iClose:SetScript("OnClick", function() infoFrame:Hide() end)

    local iTitle = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    iTitle:SetPoint("TOP", infoFrame, "TOP", 0, -12)
    iTitle:SetText("|cffFFD700BeanArena|r  |cff888888v0.2.8|r")

    MakeLine(infoFrame, -30, IW - 32, 14)

    -- Scroll area for info text
    local iScr = CreateFrame("ScrollFrame", "BeanArenaInfoScr", infoFrame, "UIPanelScrollFrameTemplate")
    iScr:SetPoint("TOPLEFT",     infoFrame, "TOPLEFT",     10, -38)
    iScr:SetPoint("BOTTOMRIGHT", infoFrame, "BOTTOMRIGHT", -28, 10)
    local iCnt = CreateFrame("Frame", nil, iScr)
    iCnt:SetWidth(IW - 52)
    iScr:SetScrollChild(iCnt)

    local INFO_SECTIONS = {
        { hdr="Overview", body=
            "BeanArena is a PvP utility addon for WoW TBC Anniversary. It tracks your arena ratings, arena point projections, honor, and battleground marks — and helps you plan gear purchases, build comp strategies, and understand CC/DR rules, all without leaving the game." },
        { hdr="Main Window  ( /ba )", body=
            "Shows your live 2v2 / 3v3 / 5v5 ratings, games played, and projected AP reward for the week. The Arena Point Calculator lets you type in any rating to simulate AP earnings. Banked AP is shown so you can track progress toward your next item." },
        { hdr="Honor Window  ( /ba honor )", body=
            "Displays your current honor, progress toward the 75,000 cap, weekly honor plan, BG mark inventory, and a full S1 honor gear checklist with checkboxes to track what you still need." },
        { hdr="CC/DR Table  ( /ba cc )", body=
            "Reference table for all Diminishing Return categories in TBC. Shows every spell per category, which share DR with which, and TBC-specific rules (e.g. Cyclone only DRs with itself; Silence does NOT DR in TBC; DR resets 15-20s after the effect ends)." },
        { hdr="Gear Windows  ( /ba gear  |  /ba hgear )", body=
            "Arena Gear: Full S1 arena gear list with AP and rating requirements.\nHonor Gear: Full S1 honor gear list with honor costs per slot." },
        { hdr="Comp Notes  ( /ba 2s  |  /ba 3s )", body=
            "Build and save a personal database of enemy comps you face in 2v2 and 3v3. For each comp: select opponent specs from a dropdown (with class icons), rate the difficulty (Easy/Medium/Hard/Counters Us), rate your confidence (Solid/Could Use Work/Weak/idk), and type freeform notes. Data is saved per character." },
        { hdr="Character Viewer  ( /ba chars )", body=
            "View comp notes and arena/honor data for your other characters on the same account. Any character that has logged in with BeanArena installed will appear here. Useful for checking your alt's notes or comparing progress." },
        { hdr="Slash Commands", body=
            "/ba               Toggle main window\n/ba honor         Honor window\n/ba cc            CC/DR table\n/ba gear          Arena gear costs\n/ba hgear         Honor gear costs\n/ba 2s            2v2 comp notes\n/ba 3s            3v3 comp notes\n/ba info          This window\n/ba chars         Character viewer\n/ba commands      Commands list\n/ba points        Print AP breakdown\n/ba reset         Time until reset\n/ba help          Print commands" },
        { hdr="Tips", body=
            "• BeanArena opens automatically alongside the PvP panel (H key).\n• Minimap button: left-click = main window, middle-click = commands, right-click = options.\n• Comp notes are saved per character — each alt has its own database.\n• The frame position is saved between sessions." },
    }

    local cy = -8
    local PAD_L = 4
    for _, sec in ipairs(INFO_SECTIONS) do
        local hdrFS = iCnt:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hdrFS:SetPoint("TOPLEFT", iCnt, "TOPLEFT", PAD_L, cy)
        hdrFS:SetText("|cffFFD700" .. sec.hdr .. "|r")
        cy = cy - 18

        -- Body — wrap manually by splitting on \n and letting FontString wrap per line
        for line in (sec.body .. "\n"):gmatch("([^\n]*)\n") do
            local bodyFS = iCnt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            bodyFS:SetPoint("TOPLEFT", iCnt, "TOPLEFT", PAD_L + 6, cy)
            bodyFS:SetWidth(iCnt:GetWidth() - PAD_L - 10)
            bodyFS:SetJustifyH("LEFT")
            bodyFS:SetText("|cffCCCCCC" .. line .. "|r")
            -- Estimate height: ~14px per wrapped line; ~16 chars per 100px width at small font
            local wrapEst = math.max(1, math.ceil(#line / 55))
            cy = cy - (14 * wrapEst)
        end
        cy = cy - 10  -- section gap
    end
    iCnt:SetHeight(math.abs(cy) + 20)
end

-- ============================================================
-- CHARACTER VIEWER FRAME  ( /ba chars )
-- ============================================================
do
    local CVW, CVH = 500, 460
    charViewFrame = MakeBGFrame("BeanArenaCharViewFrame", UIParent, CVW, CVH)
    charViewFrame:SetFrameStrata("HIGH")
    charViewFrame:SetMovable(true); charViewFrame:EnableMouse(true)
    charViewFrame:RegisterForDrag("LeftButton")
    charViewFrame:SetScript("OnDragStart", charViewFrame.StartMoving)
    charViewFrame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    charViewFrame:Hide(); RegisterEsc(charViewFrame)

    local cvClose = CreateFrame("Button", nil, charViewFrame, "UIPanelCloseButton")
    cvClose:SetPoint("TOPRIGHT", charViewFrame, "TOPRIGHT", -4, -4)
    cvClose:SetScript("OnClick", function() charViewFrame:Hide() end)

    local cvTitle = charViewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cvTitle:SetPoint("TOP", charViewFrame, "TOP", 0, -12)
    cvTitle:SetText("|cffFFD700Character Viewer|r")

    local cvSub = charViewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cvSub:SetPoint("TOP", charViewFrame, "TOP", 0, -28)
    cvSub:SetText("|cff888888Characters seen with BeanArena installed|r")

    MakeLine(charViewFrame, -40, CVW - 32, 14)

    -- Left panel: character list
    local LIST_W = 150
    local listScr = CreateFrame("ScrollFrame", "BeanArenaCharListScr", charViewFrame, "UIPanelScrollFrameTemplate")
    listScr:SetPoint("TOPLEFT",     charViewFrame, "TOPLEFT",  10, -48)
    listScr:SetPoint("BOTTOMRIGHT", charViewFrame, "TOPLEFT", LIST_W + 10, 10)
    local listCnt = CreateFrame("Frame", nil, listScr)
    listCnt:SetWidth(LIST_W - 22)
    listCnt:SetHeight(10)
    listScr:SetScrollChild(listCnt)

    -- Vertical divider
    local vdiv = charViewFrame:CreateTexture(nil, "ARTWORK")
    vdiv:SetSize(1, CVH - 60)
    vdiv:SetPoint("TOPLEFT", charViewFrame, "TOPLEFT", LIST_W + 14, -48)
    vdiv:SetColorTexture(0.3, 0.3, 0.3, 0.6)

    -- Right panel: selected character data
    local detailScr = CreateFrame("ScrollFrame", "BeanArenaCharDetailScr", charViewFrame, "UIPanelScrollFrameTemplate")
    detailScr:SetPoint("TOPLEFT",     charViewFrame, "TOPLEFT",  LIST_W + 18, -48)
    detailScr:SetPoint("BOTTOMRIGHT", charViewFrame, "BOTTOMRIGHT", -28, 10)
    local detailCnt = CreateFrame("Frame", nil, detailScr)
    detailCnt:SetWidth(CVW - LIST_W - 60)
    detailCnt:SetHeight(10)
    detailScr:SetScrollChild(detailCnt)

    local function ClearDetail()
        for _, child in ipairs({detailCnt:GetChildren()}) do child:Hide() end
        for _, r in ipairs({detailCnt:GetRegions()}) do r:Hide() end
    end

    local function BuildDetail(snap)
        ClearDetail()
        local dy = -4
        local DW = detailCnt:GetWidth()

        local function DLine(text, color, indent)
            local fs = detailCnt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("TOPLEFT", detailCnt, "TOPLEFT", (indent or 0), dy)
            fs:SetWidth(DW)
            fs:SetJustifyH("LEFT")
            fs:SetText("|cff" .. (color or "CCCCCC") .. text .. "|r")
            dy = dy - 14
        end
        local function DGap() dy = dy - 6 end

        DLine((snap.name or "Unknown") .. "  —  " .. (snap.realm or "?"), "FFD700")
        local ts = snap.timestamp and date("%Y-%m-%d", snap.timestamp) or "unknown"
        DLine("Last seen: " .. ts, "888888")
        DGap()
        DLine("Arena Points:  " .. (snap.arenaPoints or "?"), "88FF88")
        DLine("Honor:         " .. (snap.honor or "?"),        "88CCFF")
        DGap()

        -- 2v2 Notes
        local n2 = snap.notes2v2 or {}
        DLine("2v2 Comp Notes  (" .. #n2 .. " entries)", "FFD700")
        if #n2 == 0 then
            DLine("  (none)", "666666")
        else
            for _, row in ipairs(n2) do
                local specs = row.specs or {}
                local specNames = {}
                for _, idx in ipairs(specs) do
                    if SPECS and SPECS[idx] then specNames[#specNames+1] = SPECS[idx].label end
                end
                local compStr = table.concat(specNames, " + ")
                local diff = DIFF_OPTS and row.diff and DIFF_OPTS[row.diff] and DIFF_OPTS[row.diff].label or "?"
                local conf = CONF_OPTS and row.conf and CONF_OPTS[row.conf] and CONF_OPTS[row.conf].label or "?"
                DLine("  " .. (compStr ~= "" and compStr or "(no specs)"), "AAAAAA")
                DLine("    Diff: " .. diff .. "  |  Conf: " .. conf, "888888")
                if row.note and row.note ~= "" then
                    DLine("    " .. row.note, "CCCCCC")
                end
            end
        end
        DGap()

        -- 3v3 Notes
        local n3 = snap.notes3v3 or {}
        DLine("3v3 Comp Notes  (" .. #n3 .. " entries)", "FFD700")
        if #n3 == 0 then
            DLine("  (none)", "666666")
        else
            for _, row in ipairs(n3) do
                local specs = row.specs or {}
                local specNames = {}
                for _, idx in ipairs(specs) do
                    if SPECS and SPECS[idx] then specNames[#specNames+1] = SPECS[idx].label end
                end
                local compStr = table.concat(specNames, " + ")
                local diff = DIFF_OPTS and row.diff and DIFF_OPTS[row.diff] and DIFF_OPTS[row.diff].label or "?"
                local conf = CONF_OPTS and row.conf and CONF_OPTS[row.conf] and CONF_OPTS[row.conf].label or "?"
                DLine("  " .. (compStr ~= "" and compStr or "(no specs)"), "AAAAAA")
                DLine("    Diff: " .. diff .. "  |  Conf: " .. conf, "888888")
                if row.note and row.note ~= "" then
                    DLine("    " .. row.note, "CCCCCC")
                end
            end
        end

        detailCnt:SetHeight(math.abs(dy) + 20)
    end

    local function RefreshCharList()
        -- Hide old buttons
        for _, child in ipairs({listCnt:GetChildren()}) do child:Hide() end

        local chars = BeanArenaDB.chars or {}
        local rows = {}
        for key, snap in pairs(chars) do
            if type(snap) == "table" and snap.name then
                rows[#rows+1] = snap
            end
        end
        table.sort(rows, function(a,b) return (a.name or "") < (b.name or "") end)

        local ly = 0
        if #rows == 0 then
            local noFS = listCnt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noFS:SetPoint("TOPLEFT", listCnt, "TOPLEFT", 4, ly)
            noFS:SetText("|cff666666No characters\nfound yet.|r")
            listCnt:SetHeight(40)
            return
        end

        for i, snap in ipairs(rows) do
            local btn = CreateFrame("Button", nil, listCnt)
            btn:SetSize(listCnt:GetWidth(), 20)
            btn:SetPoint("TOPLEFT", listCnt, "TOPLEFT", 0, ly)
            btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

            local isMe = (snap.name == CHAR_NAME and snap.realm == CHAR_REALM)
            local nameFS = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nameFS:SetPoint("LEFT", btn, "LEFT", 4, 0)
            nameFS:SetWidth(listCnt:GetWidth() - 8)
            nameFS:SetText(isMe and ("|cffFFD700" .. snap.name .. "|r") or snap.name)

            btn:SetScript("OnClick", function()
                if isMe then SnapshotCharData() end
                BuildDetail(snap)
            end)

            ly = ly - 22
        end
        listCnt:SetHeight(math.abs(ly) + 10)

        -- Auto-select first
        if #rows > 0 then BuildDetail(rows[1]) end
    end

    charViewFrame:SetScript("OnShow", RefreshCharList)
end

-- ============================================================
-- REFRESH FUNCTIONS
-- ============================================================
BeanArena_RefreshManual = function()
    local m2, m3, m5 = DB("manual2v2"), DB("manual3v3"), DB("manual5v5")
    local function FmtPts(r, bracket)
        return r > 0
            and string.format("|cffFFD700%.0f|r", CalcBracketPoints(r, bracket))
            or  "|cff666666--|r"
    end
    manResultFS["2v2"]:SetText(FmtPts(m2, "2v2"))
    manResultFS["3v3"]:SetText(FmtPts(m3, "3v3"))
    manResultFS["5v5"]:SetText(FmtPts(m5, "5v5"))

end

local function RefreshLive()
    local r2,r3,r5,g2,g3,g5 = GetLiveRatings()
    local curAP = GetCurrentArenaPoints()
    local function GT(g)
        return g >= 10 and string.format("|cff00FF00%d|r", g)
                       or  string.format("|cffFF4444%d/10|r", g)
    end
    local function ProjAP(r, b)
        return r > 0 and CalcBracketPoints(r, b) or 0
    end
    local function APTxt(ap)
        return ap > 0 and string.format("|cffFFD700%.0f|r", ap) or "|cff666666--|r"
    end
    local ap2 = ProjAP(r2, "2v2")
    local ap3 = ProjAP(r3, "3v3")
    local ap5 = ProjAP(r5, "5v5")
    liveR2:SetText(r2>0 and tostring(r2) or "|cff666666--|r")
    liveG2:SetText(GT(g2)); liveP2:SetText(APTxt(ap2))
    liveT2:SetText(ap2>0 and string.format("|cff88FF88%.0f|r", curAP+ap2) or "|cff666666--|r")
    liveR3:SetText(r3>0 and tostring(r3) or "|cff666666--|r")
    liveG3:SetText(GT(g3)); liveP3:SetText(APTxt(ap3))
    liveT3:SetText(ap3>0 and string.format("|cff88FF88%.0f|r", curAP+ap3) or "|cff666666--|r")
    liveR5:SetText(r5>0 and tostring(r5) or "|cff666666--|r")
    liveG5:SetText(GT(g5)); liveP5:SetText(APTxt(ap5))
    liveT5:SetText(ap5>0 and string.format("|cff88FF88%.0f|r", curAP+ap5) or "|cff666666--|r")
    apInlineVal:SetText(curAP > 0
        and string.format("|cff88FF88%d|r", curAP)
        or  "|cff666666--|r")
end

local function RefreshMisc()
    if arenaGearFrame:IsShown()  then BeanArena_RefreshArenaGearPopup() end
    if honorGearFrame:IsShown()  then BeanArena_RefreshHonorGearPopup() end
    if honorFrame:IsShown() and BeanArena_RefreshHonorFrame then
        BeanArena_RefreshHonorFrame()
    end
end

BeanArena_RefreshFrame = function()
    RefreshLive(); RefreshMisc()
    if not editFocused["manual2v2"] then man2v2Edit:SetText(tostring(DB("manual2v2"))) end
    if not editFocused["manual3v3"] then man3v3Edit:SetText(tostring(DB("manual3v3"))) end
    if not editFocused["manual5v5"] then man5v5Edit:SetText(tostring(DB("manual5v5"))) end
    BeanArena_RefreshManual()
end

-- ============================================================
-- DR DATA  (TBC 2.4.3 / Anniversary)
-- ============================================================
local DR_CATEGORIES = {
    { id="STUN_CTRL", name="Controlled Stun",  color="FF4444", desc="Activated stun abilities. Full→50%→25%→immune." },
    { id="STUN_KS",   name="Kidney Shot",       color="FF6622", desc="Kidney Shot only. Its own independent DR." },
    { id="STUN_PROC", name="Proc Stun",         color="FF8844", desc="Stun procs from talents/items." },
    { id="INCAP",     name="Incapacitate",      color="FFD700", desc="Breaks on damage. Polymorph, Sap, Gouge, etc." },
    { id="FEAR",      name="Fear / Disorient",  color="CC88FF", desc="Running fears + Blind (TBC: Blind shares Fear DR)." },
    { id="HORROR",    name="Horror",            color="AA44FF", desc="Death Coil. Own category, not Fear." },
    { id="CYCLONE",   name="Cyclone",           color="00CCFF", desc="DRs with itself only in TBC." },
    { id="ROOT_CTRL", name="Controlled Root",   color="00FF88", desc="Frost Nova, Entangling Roots, Freeze, Frostbite." },
    { id="SLEEP",     name="Sleep / Hibernate", color="88FFCC", desc="Wyvern Sting, Hibernate (breaks on dmg)." },
    { id="SILENCE",   name="Silence",           color="AAAAAA", desc="NO DR in TBC. Chain freely." },
    { id="DISARM",    name="Disarm",            color="FFAA44", desc="Subject to DR in PvP." },
}

local CLASS_CC = {
    ["Druid"]   = {
        { spell="Cyclone",            dr="CYCLONE",   dur="6s",   notes="Immunity, no dmg/heal" },
        { spell="Bash",               dr="STUN_CTRL", dur="3s",   notes="Bear form" },
        { spell="Pounce",             dr="STUN_CTRL", dur="3s",   notes="Cat stealth opener" },
        { spell="Maim",               dr="STUN_CTRL", dur="1-5s", notes="Cat finisher" },
        { spell="Hibernate",          dr="SLEEP",     dur="8s",   notes="Beasts/Dragonkin" },
        { spell="Entangling Roots",   dr="ROOT_CTRL", dur="8s",   notes="Breaks on dmg" },
        { spell="Nature's Grasp",     dr="ROOT_CTRL", dur="8s",   notes="Proc root on hit" },
        { spell="Feral Charge",       dr="ROOT_CTRL", dur="4s",   notes="Bear interrupt+root" },
    },
    ["Hunter"]  = {
        { spell="Freezing Trap",  dr="INCAP",     dur="8s",  notes="Target walks in" },
        { spell="Wyvern Sting",   dr="SLEEP",     dur="8s",  notes="Survival, 1 min CD" },
        { spell="Scatter Shot",   dr="FEAR",      dur="4s",  notes="Breaks on dmg" },
        { spell="Intimidation",   dr="STUN_CTRL", dur="3s",  notes="Pet, BM talent" },
        { spell="Silencing Shot", dr="SILENCE",   dur="3s",  notes="NO DR in TBC" },
        { spell="Entrapment",     dr="ROOT_CTRL", dur="4s",  notes="Frost Trap proc" },
        { spell="Scare Beast",    dr="FEAR",      dur="8s",  notes="Beasts only" },
    },
    ["Mage"]    = {
        { spell="Polymorph",         dr="INCAP",     dur="8s", notes="Humanoids, heals target" },
        { spell="Frost Nova",        dr="ROOT_CTRL", dur="8s", notes="Melee AoE" },
        { spell="Freeze",            dr="ROOT_CTRL", dur="8s", notes="Water Elemental" },
        { spell="Frostbite",         dr="ROOT_CTRL", dur="5s", notes="Chill proc, 2.1+" },
        { spell="Dragon's Breath",   dr="INCAP",     dur="5s", notes="Fire 41pt, breaks on dmg" },
        { spell="Counterspell",      dr="SILENCE",   dur="8s", notes="Interrupt+lock; NO DR" },
        { spell="Imp. Counterspell", dr="SILENCE",   dur="4s", notes="Silence; NO DR" },
    },
    ["Paladin"] = {
        { spell="Hammer of Justice", dr="STUN_CTRL", dur="6s",  notes="Any target" },
        { spell="Repentance",        dr="INCAP",     dur="6s",  notes="Humanoids/Undead/Demons" },
        { spell="Turn Evil",         dr="FEAR",      dur="10s", notes="Undead/Demons" },
    },
    ["Priest"]  = {
        { spell="Psychic Scream",   dr="FEAR",    dur="8s",  notes="AoE fear" },
        { spell="Mind Control",     dr="NONE",    dur="—",   notes="No DR; breaks on dmg" },
        { spell="Shackle Undead",   dr="NONE",    dur="50s", notes="Undead only; no DR" },
        { spell="Silence (Shadow)", dr="SILENCE", dur="5s",  notes="Shadow spec; NO DR" },
    },
    ["Rogue"]   = {
        { spell="Sap",         dr="INCAP",     dur="10s", notes="Out of combat; breaks on dmg" },
        { spell="Gouge",       dr="INCAP",     dur="4s",  notes="Breaks on dmg" },
        { spell="Cheap Shot",  dr="STUN_CTRL", dur="4s",  notes="Stealth opener" },
        { spell="Kidney Shot", dr="STUN_KS",   dur="6s",  notes="5cp; own DR category" },
        { spell="Blind",       dr="FEAR",      dur="10s", notes="Shares Fear DR in TBC" },
        { spell="Garrote",     dr="SILENCE",   dur="3s",  notes="Stealth silence; NO DR" },
    },
    ["Shaman"]  = {
        { spell="Earthbind Totem",   dr="NONE",    dur="—",  notes="Slow pulse; no DR" },
        { spell="Frost Shock",       dr="NONE",    dur="8s", notes="Snare only; no DR" },
        { spell="Earth Shock",       dr="SILENCE", dur="2s", notes="Interrupt; NO DR" },
        { spell="Frostbrand Weapon", dr="NONE",    dur="5s", notes="Snare proc; no DR" },
    },
    ["Warlock"] = {
        { spell="Fear",           dr="FEAR",      dur="8s",  notes="Breaks on dmg" },
        { spell="Howl of Terror", dr="FEAR",      dur="8s",  notes="AoE; breaks on dmg" },
        { spell="Death Coil",     dr="HORROR",    dur="3s",  notes="Horror category" },
        { spell="Seduction",      dr="FEAR",      dur="15s", notes="Succubus; humanoids" },
        { spell="Shadowfury",     dr="STUN_CTRL", dur="3s",  notes="Destro 41pt AoE" },
        { spell="Spell Lock",     dr="SILENCE",   dur="3s",  notes="Felhunter; NO DR" },
        { spell="Banish",         dr="NONE",      dur="30s", notes="Demons/Elementals; no DR" },
    },
    ["Warrior"] = {
        { spell="Intimidating Shout", dr="FEAR",      dur="8s",  notes="AoE; primary immob." },
        { spell="Intercept",          dr="STUN_CTRL", dur="3s",  notes="Charge stun" },
        { spell="Concussion Blow",    dr="STUN_CTRL", dur="5s",  notes="Prot talent" },
        { spell="Hamstring",          dr="NONE",      dur="15s", notes="Snare; no DR" },
        { spell="Disarm",             dr="DISARM",    dur="10s", notes="Weapon disarm" },
        { spell="Mace Stun Proc",     dr="STUN_PROC", dur="3s",  notes="Mace Spec proc" },
    },
}

local function BuildDRCrossRef()
    local tbl = {}
    for cls, spells in pairs(CLASS_CC) do
        for _, entry in ipairs(spells) do
            local dr = entry.dr
            if dr ~= "NONE" then
                if not tbl[dr] then tbl[dr] = {} end
                table.insert(tbl[dr], { class=cls, spell=entry.spell, dur=entry.dur })
            end
        end
    end
    for dr, entries in pairs(tbl) do
        table.sort(entries, function(a,b) return a.class < b.class end)
    end
    return tbl
end

-- ============================================================
-- POPUP: CC / DR TABLE  (condensed, scrollable)
-- ============================================================
do
    local PW = 560
    local PH = 540

    drFrame = MakeBGFrame("BeanArenaDRFrame", UIParent, PW, PH)
    drFrame:SetFrameStrata("HIGH")
    drFrame:SetMovable(true); drFrame:EnableMouse(true)
    drFrame:RegisterForDrag("LeftButton")
    drFrame:SetScript("OnDragStart", drFrame.StartMoving)
    drFrame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    drFrame:Hide(); RegisterEsc(drFrame)

    local dt = drFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dt:SetPoint("TOP", drFrame, "TOP", 0, -12)
    dt:SetText("|cffFFD700Arena CC & Diminishing Returns|r")

    local dc = CreateFrame("Button", nil, drFrame, "UIPanelCloseButton")
    dc:SetPoint("TOPRIGHT", drFrame, "TOPRIGHT", -4, -4)
    dc:SetScript("OnClick", function() drFrame:Hide() end)

    local dsub = drFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dsub:SetPoint("TOP", drFrame, "TOP", 0, -28)
    dsub:SetText("|cffAAAAAATBC  •  Silences: NO DR  •  Reset: 15-20s after effect ends|r")
    MakeLine(drFrame, -40, PW - 32, 16)

    local scrollFrame = CreateFrame("ScrollFrame", "BeanArenaDRScroll", drFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     drFrame, "TOPLEFT",     16, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", drFrame, "BOTTOMRIGHT", -28, 12)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(PW - 48, 2000)
    scrollFrame:SetScrollChild(content)

    local crossRef = BuildDRCrossRef()
    local catColor = {}
    for _, cat in ipairs(DR_CATEGORIES) do catColor[cat.id] = cat.color end

    local cy = -4
    for _, cat in ipairs(DR_CATEGORIES) do
        local entries = crossRef[cat.id]
        -- Category header row
        local hdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 2, cy)
        hdr:SetText(string.format("|cff%s%s|r  |cffAAAAAA— %s|r", cat.color, cat.name, cat.desc))
        cy = cy - 15
        local div = content:CreateTexture(nil, "ARTWORK")
        div:SetSize(PW - 56, 1); div:SetPoint("TOPLEFT", content, "TOPLEFT", 2, cy)
        div:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        cy = cy - 5
        if not entries or #entries == 0 then
            local ne = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            ne:SetPoint("TOPLEFT", content, "TOPLEFT", 10, cy)
            ne:SetText("|cff555555(none)|r"); cy = cy - 14
        else
            for _, e in ipairs(entries) do
                local ln = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                ln:SetPoint("TOPLEFT", content, "TOPLEFT", 10, cy)
                ln:SetText(string.format("|cffFFD700%-10s|r  |cffFFFFFF%-22s|r  |cffAAAAAA%s|r",
                    e.class, e.spell, e.dur))
                cy = cy - 14
            end
        end
        cy = cy - 6
    end

    -- TBC notes footer
    local noteDiv = content:CreateTexture(nil, "ARTWORK")
    noteDiv:SetSize(PW - 56, 1); noteDiv:SetPoint("TOPLEFT", content, "TOPLEFT", 2, cy - 4)
    noteDiv:SetColorTexture(0.4, 0.35, 0.25, 0.6); cy = cy - 14

    local noteHdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noteHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 2, cy)
    noteHdr:SetText("|cff00CCFFTBC-Specific Rules|r"); cy = cy - 15

    local tbcNotes = {
        "|cffFFFFFFBlind|r  |cffAAAAAAshares Fear DR (not Cyclone) — changed post-TBC|r",
        "|cffFFFFFFCyclone|r  |cffAAAAAADRs with itself only in TBC|r",
        "|cffFFFFFFKidney Shot|r  |cffAAAAAAown stun DR, separate from Cheap Shot|r",
        "|cffFFFFFFSilences|r  |cffFF4444ZERO DR in TBC|r|cffAAAAAA — chain Garrote+Silence+Spell Lock freely|r",
        "|cffFFFFFFDeath Coil|r  |cffAAAAAAHorror category, NOT Fear|r",
        "|cffFFFFFFProc Stuns|r  |cffAAAAAA(Mace Spec) separate DR from activated stuns|r",
    }
    for _, note in ipairs(tbcNotes) do
        local nFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nFS:SetPoint("TOPLEFT", content, "TOPLEFT", 10, cy)
        nFS:SetText(note); cy = cy - 14
    end
    content:SetHeight(math.abs(cy) + 20)
end

-- ============================================================
-- SLASH COMMANDS  ( /ba  and  /beanarena )
-- ============================================================
SLASH_BEANARENA1 = "/ba"; SLASH_BEANARENA2 = "/beanarena"
SlashCmdList["BEANARENA"] = function(msg)
    msg = msg:lower():trim()
    local function Toggle(f, anchorTo)
        if f:IsShown() then f:Hide()
        else
            f:ClearAllPoints()
            if anchorTo then f:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT", 6, 0)
            else              f:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
            f:Show()
        end
    end
    if msg == "" or msg == "show" then
        if frame:IsShown() then frame:Hide() else OpenBeanArena() end
    elseif msg == "honor" then
        Toggle(honorFrame, frame)
    elseif msg == "cc" or msg == "dr" then
        Toggle(drFrame, frame)
    elseif msg == "gear" or msg == "arenagear" then
        Toggle(arenaGearFrame, frame)
    elseif msg == "hgear" or msg == "honorgear" then
        Toggle(honorGearFrame, frame)
    elseif msg == "2s" or msg == "2v2" then
        Toggle(notesFrame2, frame)
    elseif msg == "3s" or msg == "3v3" then
        Toggle(notesFrame3, frame)
    elseif msg == "info" then
        Toggle(infoFrame, frame)
    elseif msg == "chars" or msg == "characters" then
        Toggle(charViewFrame, frame)
    elseif msg == "commands" then
        if cFrame:IsShown() then cFrame:Hide() else OpenCommands() end
    elseif msg == "points" or msg == "rating" then
        local r2,r3,r5,g2,g3,g5 = GetLiveRatings()
        local curAP = GetCurrentArenaPoints()
        local er2=g2>=10 and r2 or 0; local er3=g3>=10 and r3 or 0; local er5=g5>=10 and r5 or 0
        local best, bb = CalcBestPoints(er2, er3, er5)
        print(string.format("|cffFFD700[BeanArena]|r Ratings  (Banked AP: |cff88FF88%d|r)", curAP))
        print(string.format("  2v2: %d  %dg  proj:|cffFFD700%.0f|r  %s", r2,g2,CalcBracketPoints(r2,"2v2"),g2>=10 and "|cff00FF00(ok)|r" or "|cffFF4444need 10|r"))
        print(string.format("  3v3: %d  %dg  proj:|cffFFD700%.0f|r  %s", r3,g3,CalcBracketPoints(r3,"3v3"),g3>=10 and "|cff00FF00(ok)|r" or "|cffFF4444need 10|r"))
        print(string.format("  5v5: %d  %dg  proj:|cffFFD700%.0f|r  %s", r5,g5,CalcBracketPoints(r5,"5v5"),g5>=10 and "|cff00FF00(ok)|r" or "|cffFF4444need 10|r"))
        print(best > 0 and string.format("  Best: |cffFFD700%.0f|r from |cffFFD700%s|r", best, bb) or "  |cffFF4444No eligible bracket|r")
    elseif msg == "honor" then
        print(string.format("|cffFFD700[BeanArena]|r Honor: |cffFFD700%d|r", GetCurrentHonor()))
    elseif msg == "reset" then
        print("|cffFFD700[BeanArena]|r Reset in: |cff00CCFF" .. GetDaysToReset() .. "|r")
    elseif msg == "marks" then
        local m = GetPvPMarkCounts()
        print("|cffFFD700[BeanArena]|r Marks:")
        for n, c in pairs(m) do print("  " .. n .. ": |cffFFD700" .. c .. "|r") end
    elseif msg == "options" then ShowOptions()
    elseif msg == "help" then
        print("|cffFFD700[BeanArena]|r Commands  (use /ba {command})")
        print("  /ba              Toggle main window")
        print("  /ba honor        Honor window")
        print("  /ba cc           CC/DR table")
        print("  /ba gear         Arena gear costs")
        print("  /ba hgear        Honor gear costs")
        print("  /ba 2s           2v2 comp notes")
        print("  /ba 3s           3v3 comp notes")
        print("  /ba info         Info / help window")
        print("  /ba chars        Character viewer")
        print("  /ba commands     Commands list window")
        print("  /ba points       Print AP breakdown")
        print("  /ba reset        Time until weekly reset")
        print("  /ba help         This message")
    else
        print("|cffFF4444[BeanArena]|r Unknown command. Try /ba help")
    end
end

-- ============================================================
-- EVENTS
-- ============================================================
local eFrame = CreateFrame("Frame")
eFrame:RegisterEvent("ADDON_LOADED")
eFrame:RegisterEvent("PLAYER_LOGIN")
eFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eFrame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")

eFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        -- Restore position
        if DB("frameX") and DB("frameY") then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", DB("frameX"), DB("frameY"))
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        UpdateMinimapPos()
        SetupPVPHook()
        print("|cffFFD700[BeanArena]|r v0.2.8 loaded! /ba help")
        if DB("openOnLogin") then OpenBeanArena() end
    elseif event == "PLAYER_LOGIN" then
        CHAR_NAME  = UnitName("player") or "Unknown"
        CHAR_REALM = GetRealmName and GetRealmName() or "Unknown"
        SnapshotCharData()
        -- Set dropdown to current char
        UIDropDownMenu_SetText(charDD, "|cffFFD700" .. CHAR_NAME .. " (you)|r")
    elseif event == "PLAYER_ENTERING_WORLD" then
        if RequestPVPRewardsUpdate then RequestPVPRewardsUpdate() end
        if frame:IsShown() then BeanArena_RefreshFrame() end
        -- Update snapshot with fresh live data
        if C_Timer and C_Timer.After then C_Timer.After(3, SnapshotCharData) end
    elseif event == "UPDATE_BATTLEFIELD_STATUS" then
        if frame:IsShown() then BeanArena_RefreshFrame() end
    end
end)

-- ============================================================
-- PVP UI HOOK  — open BeanArena alongside the PvP frame (H key)
-- ============================================================
local pvpHookDone = false
SetupPVPHook = function()
    if pvpHookDone then return end
    pvpHookDone = true
    -- Hook the PvP frame show (opened by H key in TBC)
    if PVPFrame then
        PVPFrame:HookScript("OnShow", function()
            if not frame:IsShown() then
                frame:ClearAllPoints()
                -- Position BeanArena to the right of PVPFrame
                frame:SetPoint("TOPLEFT", PVPFrame, "TOPRIGHT", 6, 0)
                OpenBeanArena()
            end
        end)
        PVPFrame:HookScript("OnHide", function()
            frame:Hide()
        end)
    end
end

-- ============================================================
-- TICKER  (refresh every 5s while frame is visible)
-- ============================================================
local ticker = 0
frame:SetScript("OnUpdate", function(self, elapsed)
    ticker = ticker + elapsed
    if ticker >= 5 then
        ticker = 0
        RefreshLive(); RefreshMisc()
        if not editFocused["manual2v2"] then man2v2Edit:SetText(tostring(DB("manual2v2"))) end
        if not editFocused["manual3v3"] then man3v3Edit:SetText(tostring(DB("manual3v3"))) end
        if not editFocused["manual5v5"] then man5v5Edit:SetText(tostring(DB("manual5v5"))) end
    end
end)

-- ============================================================
-- END OF FILE | BeanArena v0.2.8 | 2026-03-12
-- ============================================================
