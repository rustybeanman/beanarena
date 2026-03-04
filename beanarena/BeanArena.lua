-- BeanArena.lua
-- TBC Anniversary Arena Point Calculator & Honor Tracker
-- ============================================================
-- VERSION HISTORY
-- ============================================================
-- v1.0.0 | Initial release - arena point calculator
-- v1.1.0 | Honor tracking, BG marks, minimap button
-- v1.2.0 | Arena history tracking, class icons, win/loss
-- v1.3.0 | Resizable history window, per-bracket filters, PVP UI hook
-- v1.4.0 | Per-character history, result filters, bracket detection fix
-- v1.5.0 | 2025-03-01 | Per-char storage via chars table, PLAYER_LOGIN migration
-- v1.5.1 | 2025-03-01 | Container API compat fix
-- v1.5.2 | 2025-03-01 | Minimap border removed, PVP button removed
-- v1.5.3 | 2025-03-01 | Win/loss: guard winner==nil mid-match
-- v1.5.4 | 2025-03-01 | Win/loss: switched to UnitIsDeadOrGhost
-- v1.5.5 | 2025-03-01 | Kills-based win detection attempt
-- v1.5.6 | 2025-03-01 | Fresh win detection rewrite
-- v1.5.7 | 2025-03-01 | Win detection partially working
-- v1.6.0 | 2025-03-01 | Removed all arena history tracking and history UI
-- v1.7.0 | 2025-03-01 | Honor cap bar, milestones, gear planner, minimap tooltip
-- v1.8.0 | 2025-03-01 | Two-column layout, EotS fix, individual mark rows
-- v1.8.1 | 2025-03-01 | Frame height 420->540
-- v1.9.0 | 2025-03-01 | UI polish, column reorder, inline AP calc, honor gear progress
-- v2.0.0 | 2025-03-01 | Arena Gear Costs popup + Honor Gear Costs popup
--         |             Full S1 item lists with marks/honor/AP/rating requirements
--         |             Buttons in respective sections; live progress in popups
-- ============================================================
-- CURRENT: v2.0.0
-- ============================================================

-- ============================================================
-- SAVED VARIABLES
-- ============================================================
BeanArenaDB = BeanArenaDB or {}

local ADDON_NAME    = "BeanArena"
local RESET_WEEKDAY = 3 -- Tuesday

local defaults = {
    manual2v2     = 0,
    manual3v3     = 0,
    manual5v5     = 0,
    minimapAngle  = 45,
    frameX        = nil,
    frameY        = nil,
    openWithHonor = false,
}

local function DB(key)
    if BeanArenaDB[key] == nil then return defaults[key] end
    return BeanArenaDB[key]
end
local function SetDB(key, val) BeanArenaDB[key] = val end

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

-- Used by the weeks-to-gear planner in the main frame
local GEAR_ITEMS = {
    { name="Head",      cost=1875, rating=0    },
    { name="Shoulders", cost=1500, rating=2000 },
    { name="Chest",     cost=1875, rating=0    },
    { name="Hands",     cost=1125, rating=0    },
    { name="Legs",      cost=1875, rating=0    },
    { name="Weapon",    cost=3000, rating=1700 },
    { name="Offhand",   cost=1500, rating=1700 },
}

-- Full S1 Arena gear list for the popup
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

-- Full S1 Honor gear list for the popup
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
        local h = GetHonorCurrency()
        if h then return h end
    end
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = C_CurrencyInfo.GetCurrencyInfo(1901)
        if info then return info.quantity or 0 end
    end
    if GetCurrencyInfo then
        local _, count = GetCurrencyInfo(1901)
        if count then return count end
    end
    return 0
end

local function GetCurrentArenaPoints()
    if GetArenaPoints then
        local pts = GetArenaPoints()
        if pts then return pts end
    end
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = C_CurrencyInfo.GetCurrencyInfo(1900)
        if info then return info.quantity or 0 end
    end
    if GetCurrencyInfo then
        local _, count = GetCurrencyInfo(1900)
        if count then return count end
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
    elseif GetContainerNumSlots then
        return GetContainerNumSlots(bag) or 0
    end
    return 0
end

local function SafeGetContainerItemLink(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bag, slot)
    elseif GetContainerItemLink then
        return GetContainerItemLink(bag, slot)
    end
    return nil
end

local function SafeGetContainerItemCount(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        return info and info.stackCount or 1
    elseif GetContainerItemInfo then
        local _, count = GetContainerItemInfo(bag, slot)
        return count or 1
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
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false, tileSize = 32, edgeSize = 26,
        insets = { left=8, right=8, top=8, bottom=8 },
    })
    f:SetBackdropColor(0, 0, 0, 0.88)
    f:SetBackdropBorderColor(0.4, 0.35, 0.25, 1)
    return f
end

local function RegisterEsc(f)
    tinsert(UISpecialFrames, f:GetName())
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
        BreakUpLargeNumbers and BreakUpLargeNumbers(honor) or tostring(honor), honorPct), 0.8, 0.8, 0.8)
    if honor >= 70000 then
        GameTooltip:AddLine("|cffFF4444Warning: Near honor cap! Spend soon.|r")
    end
    GameTooltip:AddLine(string.format("Arena Points: |cff88FF88%d|r", ap), 0.8, 0.8, 0.8)
    if best > 0 then
        GameTooltip:AddLine(string.format("Best reward: |cffFFD700%.0f AP|r  (%s)", best, bb), 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: toggle window", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Middle-click: commands",    0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click: options",      0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ============================================================
-- FORWARD DECLARATIONS
-- ============================================================
local OpenBeanArena, OpenCommands, frame, cFrame, SetupHonorHook
local arenaGearFrame, honorGearFrame
local BeanArena_RefreshArenaGearPopup, BeanArena_RefreshHonorGearPopup

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
        Title("Open With Honor Window")
        Btn("Open on Login", function()
            SetDB("openOnLogin", not DB("openOnLogin"))
            CloseDropDownMenus()
        end, DB("openOnLogin"), false)
        local honorOnly = DB("openWithHonor")
        Btn("BeanArena only", function()
            SetDB("openWithHonor", not honorOnly)
            CloseDropDownMenus()
        end, honorOnly, false)
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
-- LAYOUT CONSTANTS
-- ============================================================
local FW, FH = 820, 610

local LC    = 18
local RC    = FW/2 + 14
local CW    = FW/2 - 28
local BAR_W = CW - 4

-- LEFT COLUMN Y
local Y_LHEAD      = -38
local Y_LLINE1     = -54
local Y_LCOLHDR    = -64
local Y_LLINE2     = -75
local Y_L2V2       = -86
local Y_L3V3       = -104
local Y_L5V5       = -122
local Y_LLINE3     = -137
local Y_LBEST      = -148
local Y_LBANKED    = -166
local Y_LLINE4     = -183
local Y_MHEAD      = -193
local Y_MLINE1     = -207
local Y_MCALCHDR   = -217
local Y_MLINE1B    = -228
local Y_M2V2       = -239
local Y_M3V3       = -257
local Y_M5V5       = -275
local Y_MLINE2     = -291
local Y_MBEST      = -302
local Y_MBTN       = -321   -- "View Arena Gear Costs" button
local Y_MILE_LINE0 = -351
local Y_MILEHEAD   = -361
local Y_MILELINE1  = -375
local Y_MWEAPON    = -386
local Y_MSHOULDER  = -404
local Y_GEAR_LINE  = -421
local Y_GEAR_HEAD  = -431
local Y_GEAR_LINE2 = -445
local Y_GEAR_COLHDR= -455
local Y_GEAR_LINE3 = -466
local Y_GEAR_START = -477

-- RIGHT COLUMN Y
local Y_RHEAD      = -38
local Y_RLINE1     = -54
local Y_RHONOR     = -65
local Y_RRESET     = -83
local Y_RAP        = -101
local Y_RLINE2     = -117
local Y_RBAR       = -128
local Y_RWARN      = -150
local Y_RLINE3     = -165
local Y_RMARKHEAD  = -175
local Y_RMARKLINE  = -189
local Y_RAVMARKS   = -200
local Y_RWSGMARKS  = -218
local Y_RABMARKS   = -236
local Y_REOTS      = -254
local Y_RLINE4     = -270
local Y_RPLANHEAD  = -280
local Y_RPLANLINE  = -294
local Y_RPLAN      = -305
local Y_RBTN       = -323   -- "View Honor Gear Costs" button
local Y_RLINE5     = -353
local Y_RGEARHD    = -363
local Y_RGEARLINE  = -377
local Y_HGCOLHDR   = -388
local Y_HGLINE     = -399
local Y_HGSTART    = -410

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

local titleFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleFS:SetPoint("TOP", frame, "TOP", 0, -14)
titleFS:SetText("|cffFFD700BeanArena|r")

local mainClose = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
mainClose:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
mainClose:SetScript("OnClick", function() frame:Hide() end)

local divLine = frame:CreateTexture(nil, "ARTWORK")
divLine:SetSize(1, FH - 36)
divLine:SetPoint("TOPLEFT", frame, "TOPLEFT", FW/2, -30)
divLine:SetColorTexture(0.4, 0.35, 0.25, 0.8)

local function Row2(x, y, lbl)
    local l = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    l:SetText(lbl); l:SetTextColor(0.8, 0.8, 0.8)
    local v = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    v:SetPoint("TOPLEFT", frame, "TOPLEFT", x + 148, y)
    v:SetText("--")
    return v
end

local function SmallHdr(x, y, txt)
    local f = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    f:SetText("|cffAAAAAA" .. txt .. "|r")
end

-- ══════════════════════════════════════════════════════════════
-- LEFT COLUMN — ARENA
-- ══════════════════════════════════════════════════════════════

MakeHeader(frame, Y_LHEAD,  "Current Arena Ratings", LC)
MakeLine(frame,   Y_LLINE1, CW, LC)

local LCOL = { br=LC, gms=LC+62, rat=LC+114, proj=LC+175, total=LC+255 }
SmallHdr(LCOL.br,    Y_LCOLHDR, "Bracket")
SmallHdr(LCOL.gms,   Y_LCOLHDR, "Games")
SmallHdr(LCOL.rat,   Y_LCOLHDR, "Rating")
SmallHdr(LCOL.proj,  Y_LCOLHDR, "Arena Points")
SmallHdr(LCOL.total, Y_LCOLHDR, "AP + Next Week")
MakeLine(frame, Y_LLINE2, CW, LC)

local function LiveRow(y, label)
    local l = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l:SetPoint("TOPLEFT", frame, "TOPLEFT", LCOL.br, y)
    l:SetText(label); l:SetTextColor(0.8, 0.8, 0.8)
    local function F(x) return FS(frame, x, y) end
    return F(LCOL.rat), F(LCOL.gms), F(LCOL.proj), F(LCOL.total)
end

local liveR2, liveG2, liveP2, livePT2 = LiveRow(Y_L2V2, "2v2")
local liveR3, liveG3, liveP3, livePT3 = LiveRow(Y_L3V3, "3v3")
local liveR5, liveG5, liveP5, livePT5 = LiveRow(Y_L5V5, "5v5")
MakeLine(frame, Y_LLINE3, CW, LC)

local bestLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bestLbl:SetPoint("TOPLEFT", frame, "TOPLEFT", LC, Y_LBEST)
bestLbl:SetText("Best Reward:"); bestLbl:SetTextColor(0.8, 0.8, 0.8)
local liveBestVal = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
liveBestVal:SetPoint("LEFT", bestLbl, "RIGHT", 8, 0); liveBestVal:SetText("--")

local apInlineLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
apInlineLbl:SetPoint("TOPLEFT", frame, "TOPLEFT", LC, Y_LBANKED)
apInlineLbl:SetText("Banked AP:"); apInlineLbl:SetTextColor(0.8, 0.8, 0.8)
local apInlineVal = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
apInlineVal:SetPoint("LEFT", apInlineLbl, "RIGHT", 8, 0); apInlineVal:SetText("--")

-- Arena Point Calculator
MakeLine(frame,   Y_LLINE4, CW, LC)
MakeHeader(frame, Y_MHEAD,  "Arena Point Calculator", LC)
MakeLine(frame,   Y_MLINE1, CW, LC)

local CALC_LBL_X = LC
local CALC_EB_X  = LC + 130
local CALC_RES_X = LC + 240

SmallHdr(CALC_LBL_X, Y_MCALCHDR, "Bracket")
SmallHdr(CALC_EB_X,  Y_MCALCHDR, "Rating")
SmallHdr(CALC_RES_X, Y_MCALCHDR, "Arena Points")
MakeLine(frame, Y_MLINE1B, CW, LC)

local editFocused = {}
local manResultFS = {}

local function MakeCalcRow(y, labelText, dbKey, bracket)
    local l = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l:SetPoint("TOPLEFT", frame, "TOPLEFT", CALC_LBL_X, y)
    l:SetText(labelText); l:SetTextColor(0.8, 0.8, 0.8)
    local eb = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    eb:SetSize(88, 20)
    eb:SetPoint("TOPLEFT", frame, "TOPLEFT", CALC_EB_X, y + 4)
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
    res:SetPoint("TOPLEFT", frame, "TOPLEFT", CALC_RES_X, y)
    res:SetText("--")
    manResultFS[bracket] = res
    return eb
end

local man2v2Edit = MakeCalcRow(Y_M2V2, "2v2:", "manual2v2", "2v2")
local man3v3Edit = MakeCalcRow(Y_M3V3, "3v3:", "manual3v3", "3v3")
local man5v5Edit = MakeCalcRow(Y_M5V5, "5v5:", "manual5v5", "5v5")

MakeLine(frame, Y_MLINE2, CW, LC)

local manBestLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
manBestLbl:SetPoint("TOPLEFT", frame, "TOPLEFT", LC, Y_MBEST)
manBestLbl:SetText("Best:"); manBestLbl:SetTextColor(0.8, 0.8, 0.8)
local manualBestVal = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
manualBestVal:SetPoint("LEFT", manBestLbl, "RIGHT", 8, 0); manualBestVal:SetText("--")

-- ── View Arena Gear Costs button ──────────────────────────
local arenaGearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
arenaGearBtn:SetSize(CW - 4, 24)
arenaGearBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", LC, Y_MBTN)
arenaGearBtn:SetText("View Arena Gear Costs")
arenaGearBtn:GetFontString():SetFontObject("GameFontNormalSmall")
arenaGearBtn:SetScript("OnClick", function()
    if arenaGearFrame:IsShown() then
        arenaGearFrame:Hide()
    else
        arenaGearFrame:ClearAllPoints()
        arenaGearFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
        arenaGearFrame:Show()
    end
end)

-- Rating Milestones
MakeLine(frame,   Y_MILE_LINE0, CW, LC)
MakeHeader(frame, Y_MILEHEAD,   "Rating Milestones", LC)
MakeLine(frame,   Y_MILELINE1,  CW, LC)

local function MilestoneRow(y, label, target)
    local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", frame, "TOPLEFT", LC, y)
    lbl:SetText(label); lbl:SetTextColor(0.8, 0.8, 0.8)
    local tgt = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tgt:SetPoint("TOPLEFT", frame, "TOPLEFT", LC + 148, y)
    tgt:SetText(string.format("|cffAAAAAA(need %d)|r", target))
    local val = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    val:SetPoint("TOPLEFT", frame, "TOPLEFT", LC + 240, y)
    val:SetText("--")
    return val
end

local mileWeapon   = MilestoneRow(Y_MWEAPON,   "Weapon (1700):",   1700)
local mileShoulder = MilestoneRow(Y_MSHOULDER,  "Shoulder (2000):", 2000)

-- Weeks to Gear
MakeLine(frame,   Y_GEAR_LINE,  CW, LC)
MakeHeader(frame, Y_GEAR_HEAD,  "Weeks to Gear (S1 AP Cost)", LC)
MakeLine(frame,   Y_GEAR_LINE2, CW, LC)

local GC = { name=LC, cost=LC+80, weeks=LC+158, note=LC+230 }
SmallHdr(GC.name,  Y_GEAR_COLHDR, "Item")
SmallHdr(GC.cost,  Y_GEAR_COLHDR, "Cost")
SmallHdr(GC.weeks, Y_GEAR_COLHDR, "ETA")
SmallHdr(GC.note,  Y_GEAR_COLHDR, "Status")
MakeLine(frame, Y_GEAR_LINE3, CW, LC)

local gearRows = {}
for i, item in ipairs(GEAR_ITEMS) do
    local y = Y_GEAR_START - (i - 1) * 16
    local namFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    namFS:SetPoint("TOPLEFT", frame, "TOPLEFT", GC.name, y)
    namFS:SetText(item.name); namFS:SetTextColor(0.8, 0.8, 0.8)
    local costFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    costFS:SetPoint("TOPLEFT", frame, "TOPLEFT", GC.cost, y)
    costFS:SetText("|cffAAAAAA" .. item.cost .. "|r")
    local weeksFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    weeksFS:SetPoint("TOPLEFT", frame, "TOPLEFT", GC.weeks, y)
    weeksFS:SetText("--")
    local notesFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    notesFS:SetPoint("TOPLEFT", frame, "TOPLEFT", GC.note, y)
    notesFS:SetText("")
    gearRows[i] = { weeksFS=weeksFS, notesFS=notesFS, item=item }
end

-- ══════════════════════════════════════════════════════════════
-- RIGHT COLUMN — HONOR
-- ══════════════════════════════════════════════════════════════
local function RCLine(y)   MakeLine(frame, y, CW, RC) end
local function RCHead(y,t) MakeHeader(frame, y, t, RC) end

RCHead(Y_RHEAD,  "Honor")
RCLine(Y_RLINE1)

local honorVal   = Row2(RC, Y_RHONOR,  "Current Honor:")
local resetVal   = Row2(RC, Y_RRESET,  "Reset In:")
local arenaAPVal = Row2(RC, Y_RAP,     "Arena Points:")

RCLine(Y_RLINE2)
local honorBarBG = frame:CreateTexture(nil, "BACKGROUND")
honorBarBG:SetSize(BAR_W, 16)
honorBarBG:SetPoint("TOPLEFT", frame, "TOPLEFT", RC, Y_RBAR)
honorBarBG:SetColorTexture(0.12, 0.12, 0.12, 0.9)

local honorBarFill = frame:CreateTexture(nil, "ARTWORK")
honorBarFill:SetSize(1, 16)
honorBarFill:SetPoint("TOPLEFT", honorBarBG, "TOPLEFT", 0, 0)
honorBarFill:SetColorTexture(0.85, 0.75, 0.1, 1)

local honorBarText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
honorBarText:SetPoint("CENTER", honorBarBG, "CENTER", 0, 0)
honorBarText:SetText("0 / 75,000")

local honorCapWarn = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
honorCapWarn:SetPoint("TOPLEFT", frame, "TOPLEFT", RC, Y_RWARN)
honorCapWarn:SetText("")

-- PvP Marks
RCLine(Y_RLINE3)
RCHead(Y_RMARKHEAD, "PvP Marks in Bags")
RCLine(Y_RMARKLINE)

local marksVal = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
marksVal:SetPoint("TOPLEFT", frame, "TOPLEFT", RC, -2000)
marksVal:SetText("--"); marksVal:SetJustifyH("LEFT")

local mkAV   = Row2(RC, Y_RAVMARKS,  "AV:")
local mkWSG  = Row2(RC, Y_RWSGMARKS, "WSG:")
local mkAB   = Row2(RC, Y_RABMARKS,  "AB:")
local mkEotS = Row2(RC, Y_REOTS,     "EotS:")

-- Weekly Honor Plan
RCLine(Y_RLINE4)
RCHead(Y_RPLANHEAD, "Weekly Honor Plan")
RCLine(Y_RPLANLINE)

local honorPlanText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
honorPlanText:SetPoint("TOPLEFT", frame, "TOPLEFT", RC, Y_RPLAN)
honorPlanText:SetWidth(CW - 8); honorPlanText:SetJustifyH("LEFT")
honorPlanText:SetText("--")

-- ── View Honor Gear Costs button ──────────────────────────
local honorGearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
honorGearBtn:SetSize(CW - 4, 24)
honorGearBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", RC, Y_RBTN)
honorGearBtn:SetText("View Honor Gear Costs")
honorGearBtn:GetFontString():SetFontObject("GameFontNormalSmall")
honorGearBtn:SetScript("OnClick", function()
    if honorGearFrame:IsShown() then
        honorGearFrame:Hide()
    else
        honorGearFrame:ClearAllPoints()
        honorGearFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
        honorGearFrame:Show()
    end
end)

-- Honor Gear Progress (live tracker)
RCLine(Y_RLINE5)
RCHead(Y_RGEARHD, "Honor Gear Progress")
RCLine(Y_RGEARLINE)

local HGC = { slot=RC, marks=RC+50, honor=RC+188, status=RC+295 }
SmallHdr(HGC.slot,   Y_HGCOLHDR, "Slot")
SmallHdr(HGC.marks,  Y_HGCOLHDR, "Marks Needed")
SmallHdr(HGC.honor,  Y_HGCOLHDR, "Honor")
SmallHdr(HGC.status, Y_HGCOLHDR, "Ready?")
MakeLine(frame, Y_HGLINE, CW, RC)

local honorGearRows = {}
for i, gear in ipairs(HONOR_GEAR_FULL) do
    local y = Y_HGSTART - (i - 1) * 18
    local slotFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slotFS:SetPoint("TOPLEFT", frame, "TOPLEFT", HGC.slot, y)
    slotFS:SetText(gear.slot); slotFS:SetTextColor(0.85, 0.85, 0.85)
    local marksFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    marksFS:SetPoint("TOPLEFT", frame, "TOPLEFT", HGC.marks, y)
    marksFS:SetText("--")
    local honorFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    honorFS:SetPoint("TOPLEFT", frame, "TOPLEFT", HGC.honor, y)
    honorFS:SetText("--")
    local statusFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusFS:SetPoint("TOPLEFT", frame, "TOPLEFT", HGC.status, y)
    statusFS:SetText("--")
    honorGearRows[i] = { gear=gear, marksFS=marksFS, honorFS=honorFS, statusFS=statusFS }
end

-- ============================================================
-- POPUP: ARENA GEAR COSTS
-- ============================================================
do
    local PW       = 360
    local NUM      = #ARENA_GEAR_FULL
    local ROW_H    = 18
    local PH       = 80 + NUM * ROW_H + 20
    local INNER_W  = PW - 32
    local AGC      = { slot=18, ap=200, rating=280 }

    arenaGearFrame = MakeBGFrame("BeanArenaArenaGearFrame", UIParent, PW, PH)
    arenaGearFrame:SetFrameStrata("HIGH")
    arenaGearFrame:SetMovable(true); arenaGearFrame:EnableMouse(true)
    arenaGearFrame:RegisterForDrag("LeftButton")
    arenaGearFrame:SetScript("OnDragStart", arenaGearFrame.StartMoving)
    arenaGearFrame:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)
    arenaGearFrame:Hide()
    RegisterEsc(arenaGearFrame)

    -- Title
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

    -- Column headers
    local function AGHdr(x, y, txt)
        local f = arenaGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f:SetPoint("TOPLEFT", arenaGearFrame, "TOPLEFT", x, y)
        f:SetText("|cffAAAAAA" .. txt .. "|r")
    end
    AGHdr(AGC.slot,   -50, "Item Slot")
    AGHdr(AGC.ap,     -50, "AP Cost")
    AGHdr(AGC.rating, -50, "Min Rating")
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
    foot:SetText("|cff888888Rating shown in |cffFF4444red|r|cff888888 if you don't currently meet it.|r")

    -- Refresh: color rating by player's best
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
    honorGearFrame:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)
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
    HGHdr(HGP.slot,  -50, "Item Slot")
    HGHdr(HGP.honor, -50, "Honor Cost")
    HGHdr(HGP.marks, -50, "Marks Req.")
    HGHdr(HGP.have,  -50, "You Have")
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

        -- Static marks requirement
        local reqParts = {}
        for bg, req in pairs(gear.marks) do
            table.insert(reqParts, req .. " " .. bg)
        end
        table.sort(reqParts)
        local marksReqFS = honorGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        marksReqFS:SetPoint("TOPLEFT", honorGearFrame, "TOPLEFT", HGP.marks, y)
        marksReqFS:SetText("|cffAAAAAA" .. table.concat(reqParts, ", ") .. "|r")

        -- Dynamic "You Have" column
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
                         or  string.format("|cffFF4444%d", have),
                    req, bg))
            end
            table.sort(parts)

            local hColor   = honorMet and "00FF00" or "FF4444"
            local honorStr = string.format("|cff%s%s/%s hon|r  ",
                hColor, fmt(honor), fmt(gear.honor))

            row.haveFS:SetText(honorStr .. table.concat(parts, "  "))
        end
    end

    honorGearFrame:SetScript("OnShow", BeanArena_RefreshHonorGearPopup)
end

-- ============================================================
-- FORWARD DECLARATION ASSIGNMENT
-- ============================================================
OpenBeanArena = function()
    frame:Show(); BeanArena_RefreshFrame()
end

-- ============================================================
-- COMMANDS FRAME
-- ============================================================
local COMMANDS_LIST = {
    { cmd="/ap",          desc="Toggle main window"     },
    { cmd="/ap commands", desc="Toggle this window"     },
    { cmd="/ap points",   desc="Print point breakdown"  },
    { cmd="/ap honor",    desc="Print current honor"    },
    { cmd="/ap reset",    desc="Print time until reset" },
    { cmd="/ap marks",    desc="Print BG mark counts"   },
    { cmd="/ap options",  desc="Open options menu"      },
    { cmd="/ap help",     desc="Print help"             },
}

cFrame = MakeBGFrame("BeanArenaCommandsFrame", UIParent, 310, 42 + #COMMANDS_LIST * 24)
cFrame:SetFrameStrata("HIGH")
cFrame:SetMovable(true); cFrame:EnableMouse(true)
cFrame:RegisterForDrag("LeftButton")
cFrame:SetScript("OnDragStart", cFrame.StartMoving)
cFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
cFrame:Hide()
RegisterEsc(cFrame)

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
        div:SetSize(274, 1); div:SetPoint("TOPLEFT", cFrame, "TOPLEFT", 18, y + 5)
        div:SetColorTexture(0.3, 0.3, 0.3, 0.3)
    end
    local cmdFS = cFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cmdFS:SetPoint("TOPLEFT", cFrame, "TOPLEFT", 18, y)
    cmdFS:SetText("|cff00CCFF" .. entry.cmd .. "|r")
    local descFS = cFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descFS:SetPoint("TOPLEFT", cFrame, "TOPLEFT", 145, y)
    descFS:SetText("|cffAAAAAA" .. entry.desc .. "|r")
end

local aliasFS = cFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
aliasFS:SetPoint("BOTTOMLEFT", cFrame, "BOTTOMLEFT", 18, 10)
aliasFS:SetText("|cff888888/beanarena also works in place of /ap|r")

OpenCommands = function()
    if cFrame:IsShown() then cFrame:Hide(); return end
    cFrame:ClearAllPoints()
    cFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    cFrame:Show()
end

-- ============================================================
-- REFRESH FUNCTIONS
-- ============================================================
function BeanArena_RefreshManual()
    local m2, m3, m5 = DB("manual2v2"), DB("manual3v3"), DB("manual5v5")
    local function FmtPts(r, bracket)
        return r > 0
            and string.format("|cffFFD700%.0f|r", CalcBracketPoints(r, bracket))
            or  "|cff666666--|r"
    end
    manResultFS["2v2"]:SetText(FmtPts(m2, "2v2"))
    manResultFS["3v3"]:SetText(FmtPts(m3, "3v3"))
    manResultFS["5v5"]:SetText(FmtPts(m5, "5v5"))
    local mb, mbb = CalcBestPoints(m2, m3, m5)
    manualBestVal:SetText(mb > 0
        and string.format("|cffFFD700%.0f|r |cffAAAAAA(%s)|r", mb, mbb)
        or  "|cff666666Enter ratings above|r")
end

local function RefreshLive()
    local r2,r3,r5,g2,g3,g5 = GetLiveRatings()
    local curAP = GetCurrentArenaPoints()
    local function GT(g)
        return g >= 10 and string.format("|cff00FF00%d|r", g)
                       or  string.format("|cffFF4444%d/10|r", g)
    end
    local function ProjTxt(r, b)
        return r > 0 and string.format("|cffFFD700%.0f|r", CalcBracketPoints(r, b)) or "|cff666666--|r"
    end
    local function TotalTxt(r, b)
        return r > 0 and string.format("|cff88FF88%.0f|r", CalcBracketPoints(r, b) + curAP) or "|cff666666--|r"
    end

    liveR2:SetText(r2>0 and tostring(r2) or "|cff666666--|r")
    liveG2:SetText(GT(g2)); liveP2:SetText(ProjTxt(r2,"2v2")); livePT2:SetText(TotalTxt(r2,"2v2"))
    liveR3:SetText(r3>0 and tostring(r3) or "|cff666666--|r")
    liveG3:SetText(GT(g3)); liveP3:SetText(ProjTxt(r3,"3v3")); livePT3:SetText(TotalTxt(r3,"3v3"))
    liveR5:SetText(r5>0 and tostring(r5) or "|cff666666--|r")
    liveG5:SetText(GT(g5)); liveP5:SetText(ProjTxt(r5,"5v5")); livePT5:SetText(TotalTxt(r5,"5v5"))

    local er2=g2>=10 and r2 or 0; local er3=g3>=10 and r3 or 0; local er5=g5>=10 and r5 or 0
    local best, bb = CalcBestPoints(er2, er3, er5)
    liveBestVal:SetText(best > 0
        and string.format("|cffFFD700%.0f|r |cffAAAAAA(%s)|r", best, bb)
        or  "|cffFF4444Need 10+ games in a bracket|r")
    apInlineVal:SetText(curAP > 0
        and string.format("|cff88FF88%d|r", curAP)
        or  "|cff666666--|r")
end

local function RefreshMisc()
    local honor = GetCurrentHonor()
    local ap    = GetCurrentArenaPoints()
    local fmt   = BreakUpLargeNumbers or tostring

    honorVal:SetText(string.format("|cffFFD700%s|r", fmt(honor)))
    arenaAPVal:SetText(string.format("|cff88FF88%s|r", fmt(ap)))
    resetVal:SetText("|cff00CCFF" .. GetDaysToReset() .. "|r")

    local marks = GetPvPMarkCounts()
    mkAV:SetText(string.format("|cffFFD700%d|r",   marks.AV   or 0))
    mkWSG:SetText(string.format("|cffFFD700%d|r",  marks.WSG  or 0))
    mkAB:SetText(string.format("|cffFFD700%d|r",   marks.AB   or 0))
    mkEotS:SetText(string.format("|cffFFD700%d|r", marks.EotS or 0))
    local mparts = {}
    for _, n in ipairs({"AV","WSG","AB","EotS"}) do
        table.insert(mparts, string.format("%s:|cffFFD700%d|r", n, marks[n] or 0))
    end
    marksVal:SetText(table.concat(mparts, "  "))

    -- Honor bar
    local honorPct = math.min(1, honor / HONOR_CAP)
    honorBarFill:SetWidth(math.max(1, math.floor(BAR_W * honorPct)))
    honorBarText:SetText(string.format("%s / 75,000  (%d%%)", fmt(honor), math.floor(honorPct * 100)))
    if honor >= 70000 then
        honorCapWarn:SetText("|cffFF4444Warning: Near cap — spend before 75k or gains are lost!|r")
        honorBarFill:SetColorTexture(1, 0.2, 0.2, 1)
    elseif honor >= 55000 then
        honorCapWarn:SetText("|cffFFAA00Getting full — consider spending soon.|r")
        honorBarFill:SetColorTexture(1, 0.7, 0.1, 1)
    else
        honorCapWarn:SetText("")
        honorBarFill:SetColorTexture(0.85, 0.75, 0.1, 1)
    end

    -- Weekly plan
    local toFill = math.max(0, HONOR_CAP - honor)
    if toFill == 0 then
        honorPlanText:SetText("|cff00FF00Honor capped! Time to spend.|r")
    else
        honorPlanText:SetText(string.format(
            "|cffAAAAAA~%d AV wins to cap|r  |cff666666(or ~%d WSG/AB/EotS)|r",
            math.ceil(toFill / 419), math.ceil(toFill / 209)))
    end

    -- Milestones
    local r2b, r3b, r5b, g2b, g3b, g5b = GetLiveRatings()
    local bestRating = math.max(r2b, r3b, r5b)
    local function MilTxt(t)
        return (t - bestRating) <= 0 and "|cff00FF00Unlocked!|r"
                                      or  string.format("|cffFF4444+%d rating|r", t - bestRating)
    end
    mileWeapon:SetText(MilTxt(1700))
    mileShoulder:SetText(MilTxt(2000))

    -- Weeks to gear
    local er2=g2b>=10 and r2b or 0; local er3=g3b>=10 and r3b or 0; local er5=g5b>=10 and r5b or 0
    local weeklyAP = CalcBestPoints(er2, er3, er5)
    for _, row in ipairs(gearRows) do
        local item   = row.item
        local canBuy = (item.rating == 0 or bestRating >= item.rating)
        local needed = math.max(0, item.cost - ap)
        if not canBuy then
            row.weeksFS:SetText("|cff666666--|r")
            row.notesFS:SetText(string.format("|cffFF4444need %d rating|r", item.rating))
        elseif needed == 0 then
            row.weeksFS:SetText("|cff00FF00Can buy!|r"); row.notesFS:SetText("")
        elseif weeklyAP <= 0 then
            row.weeksFS:SetText("|cffAAAAAA?|r"); row.notesFS:SetText("|cffAAAAAAneed 10 games|r")
        else
            local weeks = math.ceil(needed / weeklyAP)
            row.weeksFS:SetText(string.format("|cffFFD700%d wk%s|r", weeks, weeks==1 and "" or "s"))
            row.notesFS:SetText(string.format("|cffAAAAAA(%d short)|r", needed))
        end
    end

    -- Honor Gear Progress (live tracker in main frame)
    for _, row in ipairs(honorGearRows) do
        local gear        = row.gear
        local honorMet    = honor >= gear.honor
        local allMarksMet = true
        local markParts   = {}
        for bg, required in pairs(gear.marks) do
            local have = marks[bg] or 0
            local met  = have >= required
            if not met then allMarksMet = false end
            table.insert(markParts, string.format("%s|cffAAAAAA/%d %s|r",
                met  and string.format("|cff00FF00%d", have)
                     or  string.format("|cffFF4444%d", have),
                required, bg))
        end
        table.sort(markParts)
        row.marksFS:SetText(table.concat(markParts, "  "))
        local hc = honorMet and "00FF00" or "FF4444"
        row.honorFS:SetText(string.format("|cff%s%s|r|cffAAAAAA/%s|r", hc, fmt(honor), fmt(gear.honor)))
        row.statusFS:SetText(honorMet and allMarksMet and "|cff00FF00Ready!|r" or "|cffAAAAAA...|r")
    end

    -- Keep popups live
    if arenaGearFrame:IsShown() then BeanArena_RefreshArenaGearPopup() end
    if honorGearFrame:IsShown() then BeanArena_RefreshHonorGearPopup() end
end

function BeanArena_RefreshFrame()
    RefreshLive(); RefreshMisc()
    if not editFocused["manual2v2"] then man2v2Edit:SetText(tostring(DB("manual2v2"))) end
    if not editFocused["manual3v3"] then man3v3Edit:SetText(tostring(DB("manual3v3"))) end
    if not editFocused["manual5v5"] then man5v5Edit:SetText(tostring(DB("manual5v5"))) end
    BeanArena_RefreshManual()
end

-- ============================================================
-- SLASH COMMANDS
-- ============================================================
SLASH_BEANARENA1 = "/ap"; SLASH_BEANARENA2 = "/beanarena"
SlashCmdList["BEANARENA"] = function(msg)
    msg = msg:lower():trim()
    if msg == "" or msg == "show" then
        if frame:IsShown() then frame:Hide() else OpenBeanArena() end
    elseif msg == "commands" then
        if cFrame:IsShown() then cFrame:Hide() else OpenCommands() end
    elseif msg == "points" or msg == "rating" then
        local r2,r3,r5,g2,g3,g5 = GetLiveRatings()
        local curAP = GetCurrentArenaPoints()
        local er2=g2>=10 and r2 or 0; local er3=g3>=10 and r3 or 0; local er5=g5>=10 and r5 or 0
        local best, bb = CalcBestPoints(er2, er3, er5)
        print(string.format("|cffFFD700[BeanArena]|r Ratings  (Banked AP: |cff88FF88%d|r)", curAP))
        print(string.format("  2v2: %d  %dg  proj:|cffFFD700%.0f|r  total:|cff88FF88%.0f|r  %s", r2,g2,CalcBracketPoints(r2,"2v2"),CalcBracketPoints(r2,"2v2")+curAP,g2>=10 and "|cff00FF00(ok)|r" or "|cffFF4444need 10|r"))
        print(string.format("  3v3: %d  %dg  proj:|cffFFD700%.0f|r  total:|cff88FF88%.0f|r  %s", r3,g3,CalcBracketPoints(r3,"3v3"),CalcBracketPoints(r3,"3v3")+curAP,g3>=10 and "|cff00FF00(ok)|r" or "|cffFF4444need 10|r"))
        print(string.format("  5v5: %d  %dg  proj:|cffFFD700%.0f|r  total:|cff88FF88%.0f|r  %s", r5,g5,CalcBracketPoints(r5,"5v5"),CalcBracketPoints(r5,"5v5")+curAP,g5>=10 and "|cff00FF00(ok)|r" or "|cffFF4444need 10|r"))
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
    elseif msg == "debug" then
        print("|cffFFD700[BeanArena]|r === DEBUG ===")
        print("PVPFrame: " .. tostring(PVPFrame ~= nil))
        print("CharacterFrame: " .. tostring(CharacterFrame ~= nil))
        if CharacterFrame then
            for i = 1, 10 do
                local tab = _G["CharacterFrameTab" .. i]
                if tab then print(string.format("  Tab%d='%s'", i, tab:GetText() or "(nil)")) end
            end
        end
    elseif msg == "help" then
        print("|cffFFD700[BeanArena]|r Commands:")
        print("  /ap              - Toggle main window")
        print("  /ap commands     - Toggle commands window")
        print("  /ap points       - Print point breakdown")
        print("  /ap honor        - Print current honor")
        print("  /ap reset        - Print time until weekly reset")
        print("  /ap marks        - Print BG mark counts")
        print("  /ap options      - Options menu")
        print("  /ap help         - This help")
    else
        print("|cffFF4444[BeanArena]|r Unknown command. /ap help")
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
        if DB("frameX") and DB("frameY") then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", DB("frameX"), DB("frameY"))
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        UpdateMinimapPos()
        SetupHonorHook()
        print("|cffFFD700[BeanArena]|r Loaded! /ap help for commands.")
        if DB("openOnLogin") then OpenBeanArena() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if RequestPVPRewardsUpdate then RequestPVPRewardsUpdate() end
        if frame:IsShown() then BeanArena_RefreshFrame() end
    elseif event == "UPDATE_BATTLEFIELD_STATUS" then
        if frame:IsShown() then BeanArena_RefreshFrame() end
    end
end)

-- ============================================================
-- HONOR HOOK
-- ============================================================
local honorHookDone = false
SetupHonorHook = function()
    if honorHookDone then return end
    honorHookDone = true
    if PVPFrame then
        PVPFrame:HookScript("OnShow", function()
            if DB("openWithHonor") then OpenBeanArena() end
        end)
    end
end

-- ============================================================
-- TICKER
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
-- END OF FILE | BeanArena v2.0.0 | 2025-03-01
-- ============================================================
