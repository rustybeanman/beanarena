-- BeanArena.lua
-- TBC Anniversary Arena Point Calculator & History Tracker
-- v1.4.0

-- ============================================================
-- SAVED VARIABLES
-- ============================================================
BeanArenaDB     = BeanArenaDB     or {}
BeanArenaCharDB = BeanArenaCharDB or {}  -- per-character saved variables

local ADDON_NAME    = "BeanArena"
local RESET_WEEKDAY = 3 -- Tuesday

local defaults = {
    manual2v2         = 0,
    manual3v3         = 0,
    manual5v5         = 0,
    minimapAngle      = 45,
    frameX            = nil,
    frameY            = nil,
    historyX          = nil,
    historyY          = nil,
    historyW          = 820,
    historyH          = 520,
    openWithHonor     = false,
    openBothWithHonor = false,
    histFilter        = "ALL",   -- "ALL","2v2","3v3","5v5"
    histResultFilter  = "ALL",   -- "ALL","WIN","LOSS"
}

local function DB(key)
    if BeanArenaDB[key] == nil then return defaults[key] end
    return BeanArenaDB[key]
end
local function SetDB(key, val) BeanArenaDB[key] = val end

-- ============================================================
-- PER-CHARACTER STORAGE
-- ============================================================
-- History is stored in BeanArenaDB.chars["CharName-Realm"].arenaHistory
-- so it is account-wide SavedVariables (always reliable) but keyed per char.
-- BeanArenaCharDB is kept as SavedVariablesPerChar for forward compat but
-- we primarily use the chars table approach which has no timing issues.
local currentCharKey = nil  -- set at PLAYER_LOGIN when UnitName is valid

local function CharDB()
    if not currentCharKey then return nil end
    if not BeanArenaDB.chars then BeanArenaDB.chars = {} end
    if not BeanArenaDB.chars[currentCharKey] then
        BeanArenaDB.chars[currentCharKey] = { arenaHistory = {} }
    end
    return BeanArenaDB.chars[currentCharKey]
end

local function CharHistory()
    local db = CharDB()
    if not db then return {} end  -- not logged in yet, return empty
    if not db.arenaHistory then db.arenaHistory = {} end
    return db.arenaHistory
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
-- HONOR
-- ============================================================
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

-- ============================================================
-- ARENA POINTS (banked)
-- ============================================================
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
local PVP_MARKS = { [20560]="AV", [20558]="WSG", [20559]="AB", [29025]="EotS" }

local function GetPvPMarkCounts()
    local counts = { AV=0, WSG=0, AB=0, EotS=0 }
    for bag = 0, 4 do
        local numSlots = C_Container and C_Container.GetContainerNumSlots(bag) or GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local link = C_Container and C_Container.GetContainerItemLink(bag, slot) or GetContainerItemLink(bag, slot)
            if link then
                for itemID, markName in pairs(PVP_MARKS) do
                    if link:find("item:" .. itemID .. ":") then
                        local info = C_Container and C_Container.GetContainerItemInfo(bag, slot)
                        counts[markName] = counts[markName] + (info and info.stackCount or 1)
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
        local e,_,_,_,_,f = GetPersonalRatedInfo(3); r5=tonumber(e)  or 0; g5=tonumber(f) or 0
    end
    return r2,r3,r5,g2,g3,g5
end

-- ============================================================
-- CLASS DATA
-- ============================================================
local CLASS_COLORS = {
    WARRIOR="C79C6E", PALADIN="F58CBA", HUNTER="ABD473", ROGUE="FFF569",
    PRIEST="FFFFFF",  SHAMAN="0070DE",  MAGE="69CCF0",   WARLOCK="9482C9",
    DRUID="FF7D0A",   DEATHKNIGHT="C41F3B",
}
local CLASS_SHORT = {
    WARRIOR="War", PALADIN="Pal", HUNTER="Hunt", ROGUE="Rog",
    PRIEST="Pri",  SHAMAN="Sha",  MAGE="Mag",    WARLOCK="Lock",
    DRUID="Dru",   DEATHKNIGHT="DK",
}
local CLASS_ICON_TCOORDS = {
    WARRIOR     = {0,    0.25, 0,    0.25},
    MAGE        = {0.25, 0.5,  0,    0.25},
    ROGUE       = {0.5,  0.75, 0,    0.25},
    DRUID       = {0.75, 1.0,  0,    0.25},
    HUNTER      = {0,    0.25, 0.25, 0.5 },
    SHAMAN      = {0.25, 0.5,  0.25, 0.5 },
    PRIEST      = {0.5,  0.75, 0.25, 0.5 },
    WARLOCK     = {0.75, 1.0,  0.25, 0.5 },
    PALADIN     = {0,    0.25, 0.5,  0.75},
    DEATHKNIGHT = {0.25, 0.5,  0.5,  0.75},
}
local CLASS_ICON_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

-- ============================================================
-- ARENA HISTORY TRACKING
-- ============================================================
local inArena      = false
local matchStart   = 0
local matchBracket = nil

local function GetTeamSnapshot(isOpponent)
    local members = {}
    if isOpponent then
        -- Capture all 5 possible arena slots immediately
        for i = 1, 5 do
            local u = "arena" .. i
            if UnitExists(u) then
                local _, cls = UnitClass(u)
                table.insert(members, { name = UnitName(u) or "?", class = cls or "UNKNOWN" })
            end
        end
    else
        local _, cls = UnitClass("player")
        table.insert(members, { name = UnitName("player") or "?", class = cls or "UNKNOWN" })
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) then
                local _, pc = UnitClass(u)
                table.insert(members, { name = UnitName(u) or "?", class = pc or "UNKNOWN" })
            end
        end
    end
    return members
end

local function DetectBracket()
    -- Method 1: count our side (party + self) - most reliable in TBC
    local partyCount = 0
    for i = 1, 4 do if UnitExists("party"..i) then partyCount = partyCount + 1 end end
    local ourSize = partyCount + 1  -- include self

    -- Method 2: count visible opponents
    local opponentCount = 0
    for i = 1, 5 do if UnitExists("arena"..i) then opponentCount = opponentCount + 1 end end

    -- Use whichever count is higher (opponents may not all be loaded yet,
    -- our party is always known)
    local maxCount = math.max(ourSize, opponentCount)
    if maxCount >= 5 then return "5v5"
    elseif maxCount >= 3 then return "3v3"
    else return "2v2" end
end

-- Snapshot opponent data early (before they leave after death)
local pendingOpponents = nil

local function SnapshotOpponents()
    local members = {}
    for i = 1, 5 do
        local u = "arena" .. i
        if UnitExists(u) then
            local _, cls = UnitClass(u)
            table.insert(members, { name = UnitName(u) or "?", class = cls or "UNKNOWN" })
        end
    end
    if #members > 0 then
        pendingOpponents = members
    end
end

local function SaveMatch(won)
    -- history stored via CharHistory() keyed per character
    local d = date("*t", time())
    -- Use snapshotted opponents if available (they may have left by now)
    local opponents = pendingOpponents or GetTeamSnapshot(true)
    local entry = {
        date     = string.format("%02d/%02d %02d:%02d", d.month, d.day, d.hour, d.min),
        bracket  = matchBracket or DetectBracket(),
        won      = won,
        duration = math.max(0, math.floor(GetTime() - matchStart)),
        friendly = GetTeamSnapshot(false),
        opponent = opponents,
        note     = "",
    }
    pendingOpponents = nil
    local hist = CharHistory()
    table.insert(hist, 1, entry)
    while #hist > 200 do table.remove(hist) end
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
    f:SetBackdropColor(0, 0, 0, 1)
    f:SetBackdropBorderColor(0.4, 0.35, 0.25, 1)
    return f
end

local function RegisterEsc(f)
    tinsert(UISpecialFrames, f:GetName())
end

local function MakeRow(parent, y, lbl)
    local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, y)
    l:SetText(lbl); l:SetTextColor(0.8, 0.8, 0.8)
    local v = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    v:SetPoint("TOPLEFT", parent, "TOPLEFT", 185, y)
    v:SetText("--")
    return v
end

local function MakeHeader(parent, y, text)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, y)
    h:SetText("|cff00CCFF" .. text .. "|r")
end

local function MakeLine(parent, y, w)
    local l = parent:CreateTexture(nil, "ARTWORK")
    l:SetSize(w or 294, 1)
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, y)
    l:SetColorTexture(0.4, 0.4, 0.4, 0.6)
end

local function FS(parent, x, y)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    f:SetText("--")
    return f
end

local function MakeSmallButton(parent, w, h, label)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h); b:SetText(label)
    b:GetFontString():SetFontObject("GameFontNormalSmall")
    return b
end

-- ============================================================
-- MINIMAP BUTTON
-- ============================================================
-- Minimap button - standard LibDBIcon/TBC addon approach
-- Button: 31px hitbox. Icon: cropped texture in ARTWORK. Border ring: OVERLAY child.
-- MiniMap-TrackingBorder is the gold ring texture present in all WoW versions.
local minimapButton = CreateFrame("Button", "BeanArenaMinimapButton", Minimap)
minimapButton:SetSize(31, 31)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
minimapButton:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

-- Icon: sits in ARTWORK layer, centered, slight texcoord crop for clean edges
local mmIcon = minimapButton:CreateTexture(nil, "ARTWORK")
mmIcon:SetSize(20, 20)
mmIcon:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)
mmIcon:SetTexture("Interface\\Icons\\Achievement_Arena_2v2_7")
mmIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

-- No border ring on minimap button

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
    GameTooltip:AddLine("Left-click: toggle window", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Middle-click: commands", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: options", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ============================================================
-- FORWARD DECLARATIONS
-- ============================================================
local OpenBeanArena, OpenHistory, OpenCommands, frame, hFrame, cFrame, SetupHonorHook

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
        Btn("Toggle History Window", function()
            if hFrame:IsShown() then hFrame:Hide() else OpenHistory() end
            CloseDropDownMenus()
        end, nil, true)

        Btn("Toggle Commands Window", function()
            if cFrame:IsShown() then cFrame:Hide() else OpenCommands() end
            CloseDropDownMenus()
        end, nil, true)

        Title("Open With Honor Window")
        local honorOnly = DB("openWithHonor") and not DB("openBothWithHonor")
        Btn("BeanArena only", function()
            SetDB("openWithHonor", not honorOnly); SetDB("openBothWithHonor", false)
            CloseDropDownMenus()
        end, honorOnly, false)
        local honorBoth = DB("openBothWithHonor")
        Btn("BeanArena + History", function()
            SetDB("openBothWithHonor", not honorBoth); SetDB("openWithHonor", not honorBoth)
            CloseDropDownMenus()
        end, honorBoth, false)
        local honorOff = not DB("openWithHonor") and not DB("openBothWithHonor")
        Btn("Off", function()
            SetDB("openWithHonor", false); SetDB("openBothWithHonor", false)
            CloseDropDownMenus()
        end, honorOff, false)
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
-- MAIN FRAME
-- ============================================================
frame = MakeBGFrame("BeanArenaFrame", UIParent, 345, 510)
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

local histBtn = MakeSmallButton(frame, 70, 22, "History")
histBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
histBtn:SetScript("OnClick", function() OpenHistory() end)

-- ── LIVE RATINGS ─────────────────────────────────────────
-- Columns: Bracket | Rating | Games | Proj.AP | Proj Total
MakeHeader(frame, -42, "Live Ratings (Auto)")
MakeLine(frame, -56, 315)

local COL = { br=18, rat=90, gms=150, proj=208, total=272 }

local function ColHdr(x, txt)
    local f = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -63)
    f:SetText("|cffAAAAAA" .. txt .. "|r")
end
ColHdr(COL.br,    "Bracket")
ColHdr(COL.rat,   "Rating")
ColHdr(COL.gms,   "Games")
ColHdr(COL.proj,  "Proj.AP")
ColHdr(COL.total, "Proj Total")
MakeLine(frame, -71, 315)

local function LiveRow(y, label)
    local l = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l:SetPoint("TOPLEFT", frame, "TOPLEFT", COL.br, y)
    l:SetText(label); l:SetTextColor(0.8, 0.8, 0.8)
    return FS(frame, COL.rat, y),
           FS(frame, COL.gms, y),
           FS(frame, COL.proj, y),
           FS(frame, COL.total, y)
end

local liveR2, liveG2, liveP2, livePT2 = LiveRow(-79,  "2v2")
local liveR3, liveG3, liveP3, livePT3 = LiveRow(-95,  "3v3")
local liveR5, liveG5, liveP5, livePT5 = LiveRow(-111, "5v5")
MakeLine(frame, -123, 315)

local bestLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bestLbl:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -129)
bestLbl:SetText("Best Reward:"); bestLbl:SetTextColor(0.8, 0.8, 0.8)
local liveBestVal = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
liveBestVal:SetPoint("LEFT", bestLbl, "RIGHT", 6, 0)
liveBestVal:SetText("--")

local apInlineLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
apInlineLbl:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -145)
apInlineLbl:SetText("Banked Arena Points:"); apInlineLbl:SetTextColor(0.8, 0.8, 0.8)
local apInlineVal = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
apInlineVal:SetPoint("LEFT", apInlineLbl, "RIGHT", 6, 0)
apInlineVal:SetText("--")

-- ── MANUAL ENTRY ──────────────────────────────────────────
MakeLine(frame, -161, 315)
MakeHeader(frame, -167, "Manual Rating Entry")
MakeLine(frame, -181, 315)

local editFocused = {}

local function MakeEditRow(y, labelText, dbKey)
    local l = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, y)
    l:SetText(labelText); l:SetTextColor(0.8, 0.8, 0.8)
    local eb = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    eb:SetSize(80, 20); eb:SetPoint("TOPLEFT", frame, "TOPLEFT", 185, y + 4)
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
    return eb
end

local man2v2Edit = MakeEditRow(-187, "2v2 Rating:", "manual2v2")
local man3v3Edit = MakeEditRow(-209, "3v3 Rating:", "manual3v3")
local man5v5Edit = MakeEditRow(-231, "5v5 Rating:", "manual5v5")

MakeLine(frame, -249, 315)
local manualBestVal = MakeRow(frame, -255, "Manual Best:")
local manualP2Val   = MakeRow(frame, -271, "  2v2 Points:")
local manualP3Val   = MakeRow(frame, -287, "  3v3 Points:")
local manualP5Val   = MakeRow(frame, -303, "  5v5 Points:")

-- ── HONOR & BG MARKS ──────────────────────────────────────
MakeLine(frame, -319, 315)
MakeHeader(frame, -325, "Honor and BG Marks")
MakeLine(frame, -339, 315)

local honorVal   = MakeRow(frame, -345, "Current Honor:")
local arenaAPVal = MakeRow(frame, -361, "Arena Points:")
local resetVal   = MakeRow(frame, -377, "Reset In:")

MakeLine(frame, -393, 315)
MakeHeader(frame, -399, "PvP Marks in Bags")
MakeLine(frame, -413, 315)

local marksVal = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
marksVal:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -419)
marksVal:SetText("--"); marksVal:SetJustifyH("LEFT")

-- ============================================================
-- HISTORY FRAME
-- ============================================================
hFrame = CreateFrame("Frame", "BeanArenaHistoryFrame", UIParent, "BackdropTemplate")
hFrame:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = false, tileSize = 32, edgeSize = 26,
    insets = { left=8, right=8, top=8, bottom=8 },
})
hFrame:SetBackdropColor(0, 0, 0, 1)
hFrame:SetBackdropBorderColor(0.4, 0.35, 0.25, 1)
hFrame:SetSize(DB("historyW"), DB("historyH"))
hFrame:SetResizable(true)
hFrame:SetFrameStrata("HIGH")
hFrame:SetMovable(true); hFrame:EnableMouse(true)
hFrame:RegisterForDrag("LeftButton")
hFrame:SetScript("OnDragStart", hFrame.StartMoving)
hFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetCenter(); SetDB("historyX", x); SetDB("historyY", y)
end)
hFrame:Hide()
RegisterEsc(hFrame)

-- Resize grip
local resizeGrip = CreateFrame("Button", nil, hFrame)
resizeGrip:SetSize(16, 16)
resizeGrip:SetPoint("BOTTOMRIGHT", hFrame, "BOTTOMRIGHT", -4, 4)
resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeGrip:SetScript("OnMouseDown", function() hFrame:StartSizing("BOTTOMRIGHT") end)
resizeGrip:SetScript("OnMouseUp", function()
    hFrame:StopMovingOrSizing()
    SetDB("historyW", math.floor(hFrame:GetWidth()))
    SetDB("historyH", math.floor(hFrame:GetHeight()))
    BeanArena_RefreshHistory()
end)

-- Title
local hTitle = hFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
hTitle:SetPoint("TOP", hFrame, "TOP", 0, -14)
hTitle:SetText("|cffFFD700Arena History|r")

-- Close
local hClose = CreateFrame("Button", nil, hFrame, "UIPanelCloseButton")
hClose:SetPoint("TOPRIGHT", hFrame, "TOPRIGHT", -4, -4)
hClose:SetScript("OnClick", function() hFrame:Hide() end)

-- ── FILTER BAR ────────────────────────────────────────────
-- Bracket filter buttons
local filterY = -36
local function MakeFilterBtn(label, xOff, dbKey, value, group)
    local b = CreateFrame("Button", nil, hFrame, "UIPanelButtonTemplate")
    b:SetSize(52, 20); b:SetText(label)
    b:GetFontString():SetFontObject("GameFontNormalSmall")
    b:SetPoint("TOPLEFT", hFrame, "TOPLEFT", xOff, filterY)
    b.dbKey = dbKey; b.value = value; b.group = group

    local function UpdateHighlight()
        if DB(dbKey) == value then
            b:GetFontString():SetTextColor(1, 1, 0)
        else
            b:GetFontString():SetTextColor(1, 1, 1)
        end
    end
    b:SetScript("OnClick", function()
        SetDB(dbKey, value)
        -- refresh all buttons in same group
        if group then
            for _, gb in ipairs(group) do
                if gb.UpdateHighlight then gb:UpdateHighlight() end
            end
        end
        BeanArena_RefreshHistory()
    end)
    b.UpdateHighlight = UpdateHighlight
    UpdateHighlight()
    return b
end

local bracketGroup = {}
local resultGroup  = {}

local bfAll  = MakeFilterBtn("All",  18, "histFilter", "ALL",  bracketGroup)
local bf2v2  = MakeFilterBtn("2v2",  74, "histFilter", "2v2",  bracketGroup)
local bf3v3  = MakeFilterBtn("3v3", 130, "histFilter", "3v3",  bracketGroup)
local bf5v5  = MakeFilterBtn("5v5", 186, "histFilter", "5v5",  bracketGroup)
bracketGroup[1]=bfAll; bracketGroup[2]=bf2v2; bracketGroup[3]=bf3v3; bracketGroup[4]=bf5v5

local rfAll  = MakeFilterBtn("All",  260, "histResultFilter", "ALL",  resultGroup)
local rfWin  = MakeFilterBtn("Wins", 316, "histResultFilter", "WIN",  resultGroup)
local rfLoss = MakeFilterBtn("Loss", 372, "histResultFilter", "LOSS", resultGroup)
resultGroup[1]=rfAll; resultGroup[2]=rfWin; resultGroup[3]=rfLoss

-- Filter labels
local bfLbl = hFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
bfLbl:SetPoint("TOPLEFT",hFrame,"TOPLEFT",18,-24); bfLbl:SetText("|cffAAAAAA Bracket:|r")
local rfLbl = hFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
rfLbl:SetPoint("TOPLEFT",hFrame,"TOPLEFT",260,-24); rfLbl:SetText("|cffAAAAAA Result:|r")

-- Divider below filter bar
local filterDiv = hFrame:CreateTexture(nil,"ARTWORK")
filterDiv:SetHeight(1)
filterDiv:SetPoint("TOPLEFT", hFrame,"TOPLEFT",18,-60)
filterDiv:SetPoint("TOPRIGHT",hFrame,"TOPRIGHT",-18,-60)
filterDiv:SetColorTexture(0.4,0.4,0.4,0.7)

-- Column headers (anchored to hFrame, static)
-- Layout: Date | Bracket | Result | Time | Friendly | Opponent | Note
-- We'll position Friendly/Opponent/Note dynamically in RefreshHistory
local HDR_Y = -68
local H_COL_DATE     = 18
local H_COL_BRACKET  = 96
local H_COL_RESULT   = 148
local H_COL_TIME     = 200
local H_COL_FRIENDLY = 250
-- opponent and note cols set in refresh

local function StaticHdr(x, txt)
    local f = hFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    f:SetPoint("TOPLEFT",hFrame,"TOPLEFT",x,HDR_Y)
    f:SetText("|cffAAAAAA"..txt.."|r")
    return f
end
StaticHdr(H_COL_DATE,    "Date")
StaticHdr(H_COL_BRACKET, "Bracket")
StaticHdr(H_COL_RESULT,  "Result")
StaticHdr(H_COL_TIME,    "Time")
StaticHdr(H_COL_FRIENDLY,"Friendly")
local oppHdrFS  = StaticHdr(0, "Opponent")
local noteHdrFS = StaticHdr(0, "Note")

local hDivLine2 = hFrame:CreateTexture(nil,"ARTWORK")
hDivLine2:SetHeight(1)
hDivLine2:SetPoint("TOPLEFT", hFrame,"TOPLEFT",18,-80)
hDivLine2:SetPoint("TOPRIGHT",hFrame,"TOPRIGHT",-18,-80)
hDivLine2:SetColorTexture(0.5,0.5,0.5,0.8)

-- Scroll
local hScroll = CreateFrame("ScrollFrame","BeanArenaHistScroll",hFrame,"UIPanelScrollFrameTemplate")
hScroll:SetPoint("TOPLEFT",  hFrame,"TOPLEFT",  14,-84)
hScroll:SetPoint("BOTTOMRIGHT",hFrame,"BOTTOMRIGHT",-30,38)

local hContent = CreateFrame("Frame",nil,hScroll)
hContent:SetWidth(1); hContent:SetHeight(10)
hScroll:SetScrollChild(hContent)

local clearBtn = MakeSmallButton(hFrame,110,22,"Clear History")
clearBtn:SetPoint("BOTTOMLEFT",hFrame,"BOTTOMLEFT",14,10)
clearBtn:SetScript("OnClick",function()
    local db = CharDB()
    if db then db.arenaHistory = {} end
    BeanArena_RefreshHistory()
    print("|cffFFD700[BeanArena]|r History cleared.")
end)

-- Pool of row frames
local historyRowPool = {}

local ICON_SIZE  = 14
local ROW_LINE_H = 16

local function DrawMember(parent, x, y, member, maxNameW)
    local cls = member.class or "UNKNOWN"
    local tc  = CLASS_ICON_TCOORDS[cls]
    if tc then
        local tex = parent:CreateTexture(nil,"OVERLAY")
        tex:SetSize(ICON_SIZE, ICON_SIZE)
        tex:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y-1)
        tex:SetTexture(CLASS_ICON_TEX)
        tex:SetTexCoord(tc[1],tc[2],tc[3],tc[4])
    end
    local nfs = parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    nfs:SetPoint("TOPLEFT",parent,"TOPLEFT",x+ICON_SIZE+2,y)
    local color = CLASS_COLORS[cls] or "AAAAAA"
    nfs:SetText(string.format("|cff%s%s|r",color,member.name or "?"))
    nfs:SetWidth(maxNameW)
    nfs:SetJustifyH("LEFT")
    nfs:SetWordWrap(false)
end

-- Active note editbox (only one at a time)
local activeNoteEB = nil

local function MakeNoteCell(row, x, rowH, entryIdx)
    local noteEB = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    noteEB:SetSize(120, 16)
    noteEB:SetPoint("TOPLEFT", row, "TOPLEFT", x, -2)
    noteEB:SetAutoFocus(false)
    noteEB:SetMaxLetters(80)
    noteEB:SetFontObject("GameFontNormalSmall")
    local entry = CharHistory()[entryIdx]
    noteEB:SetText(entry and entry.note or "")

    noteEB:SetScript("OnEditFocusGained", function(self)
        if activeNoteEB and activeNoteEB ~= self then activeNoteEB:ClearFocus() end
        activeNoteEB = self
    end)
    noteEB:SetScript("OnEnterPressed", function(self)
        if CharHistory()[entryIdx] then
            CharHistory()[entryIdx].note = self:GetText()
        end
        self:ClearFocus()
    end)
    noteEB:SetScript("OnEditFocusLost", function(self)
        if CharHistory()[entryIdx] then
            CharHistory()[entryIdx].note = self:GetText()
        end
        if activeNoteEB == self then activeNoteEB = nil end
    end)
    noteEB:SetScript("OnEscapePressed", function(self)
        self:SetText(CharHistory()[entryIdx] and CharHistory()[entryIdx].note or "")
        self:ClearFocus()
    end)
    return noteEB
end

function BeanArena_RefreshHistory()
    for _, r in ipairs(historyRowPool) do r:Hide() end
    historyRowPool = {}

    -- Refresh filter button highlights
    for _, b in ipairs(bracketGroup) do if b.UpdateHighlight then b:UpdateHighlight() end end
    for _, b in ipairs(resultGroup)  do if b.UpdateHighlight then b:UpdateHighlight() end end

    local hist    = CharHistory()
    local bFilter = DB("histFilter")
    local rFilter = DB("histResultFilter")

    -- Build filtered list (preserve original indices for note editing)
    local filtered = {}
    for i, entry in ipairs(hist) do
        local bMatch = (bFilter == "ALL") or (entry.bracket == bFilter)
        local rMatch = (rFilter == "ALL")
            or (rFilter == "WIN"  and entry.won  == true)
            or (rFilter == "LOSS" and entry.won  == false)
        if bMatch and rMatch then
            table.insert(filtered, { idx=i, entry=entry })
        end
    end

    -- Dynamic column layout from frame width
    local fw       = math.floor(hFrame:GetWidth())
    local innerW   = fw - 50
    local fixedW   = H_COL_FRIENDLY + 4   -- space used by fixed cols
    local remaining = innerW - fixedW
    -- Split: 38% friendly, 38% opponent, 24% note
    local teamW  = math.floor(remaining * 0.38)
    local noteW  = math.max(90, remaining - teamW * 2 - 8)
    local oppX   = H_COL_FRIENDLY + teamW + 6
    local noteX  = oppX + teamW + 6

    -- Reposition dynamic headers
    oppHdrFS:ClearAllPoints()
    oppHdrFS:SetPoint("TOPLEFT",hFrame,"TOPLEFT",oppX,HDR_Y)
    noteHdrFS:ClearAllPoints()
    noteHdrFS:SetPoint("TOPLEFT",hFrame,"TOPLEFT",noteX,HDR_Y)

    hContent:SetWidth(innerW)

    if #filtered == 0 then
        hContent:SetHeight(50)
        local r = CreateFrame("Frame",nil,hContent)
        r:SetSize(innerW,40); r:SetPoint("TOPLEFT",hContent,"TOPLEFT",0,0)
        local fs = r:CreateFontString(nil,"OVERLAY","GameFontNormal")
        fs:SetPoint("TOPLEFT",r,"TOPLEFT",10,-12)
        local msg = #hist == 0
            and "|cff888888No arena games recorded yet. Play arenas and they will appear here.|r"
            or  "|cff888888No games match current filters.|r"
        fs:SetText(msg)
        table.insert(historyRowPool,r)
        return
    end

    local totalH = 0
    for i, item in ipairs(filtered) do
        if i > 100 then break end
        local entry   = item.entry
        local origIdx = item.idx

        local teamSize = math.max(
            entry.friendly  and #entry.friendly  or 0,
            entry.opponent  and #entry.opponent  or 0,
            entry.enemy     and #entry.enemy     or 0,
            1
        )
        local rowH = teamSize * ROW_LINE_H + 10

        local row = CreateFrame("Frame",nil,hContent)
        row:SetSize(innerW, rowH)
        row:SetPoint("TOPLEFT",hContent,"TOPLEFT",0,-totalH)

        if i % 2 == 0 then
            local bg = row:CreateTexture(nil,"BACKGROUND")
            bg:SetAllPoints(); bg:SetColorTexture(1,1,1,0.05)
        end

        -- Text cell helper: centered vertically in row
        local function Cell(x, txt, w, centerY)
            local f = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            if centerY then
                f:SetPoint("LEFT",row,"TOPLEFT",x, -rowH/2 + 6)
            else
                f:SetPoint("TOPLEFT",row,"TOPLEFT",x,-3)
            end
            f:SetText(txt); f:SetWidth(w)
            f:SetJustifyH("LEFT"); f:SetWordWrap(false)
        end

        local resultColor = entry.won and "|cff00FF00Win|r" or "|cffFF4444Loss|r"
        Cell(H_COL_DATE    - 18, entry.date    or "?",            76,  true)
        Cell(H_COL_BRACKET - 18, entry.bracket or "?",            46,  true)
        Cell(H_COL_RESULT  - 18, resultColor,                     44,  true)
        Cell(H_COL_TIME    - 18, (function()
            local s = entry.duration or 0
            return s>0 and string.format("%d:%02d",math.floor(s/60),s%60) or "?"
        end)(),                                                    42,  true)

        local friendly = entry.friendly  or {}
        local opponent = entry.opponent  or entry.enemy or {}

        for idx, m in ipairs(friendly) do
            DrawMember(row, H_COL_FRIENDLY-18, -2-(idx-1)*ROW_LINE_H, m, teamW-ICON_SIZE-4)
        end
        for idx, m in ipairs(opponent) do
            DrawMember(row, oppX-18, -2-(idx-1)*ROW_LINE_H, m, teamW-ICON_SIZE-4)
        end

        -- Note editbox
        MakeNoteCell(row, noteX-18, rowH, origIdx)

        -- Divider
        local div = row:CreateTexture(nil,"ARTWORK")
        div:SetHeight(1)
        div:SetPoint("BOTTOMLEFT",row,"BOTTOMLEFT",0,0)
        div:SetPoint("BOTTOMRIGHT",row,"BOTTOMRIGHT",0,0)
        div:SetColorTexture(0.25,0.25,0.25,0.5)

        totalH = totalH + rowH
        table.insert(historyRowPool, row)
    end

    hContent:SetHeight(totalH + 10)

    -- Show total count vs filtered
    local countStr = #filtered == #hist
        and string.format("|cffAAAAAA%d games|r",#hist)
        or  string.format("|cffAAAAAA%d of %d games|r",#filtered,#hist)
    -- Reuse or create count label
    if not hFrame.countFS then
        hFrame.countFS = hFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        hFrame.countFS:SetPoint("BOTTOMRIGHT",hFrame,"BOTTOMRIGHT",-20,14)
    end
    hFrame.countFS:SetText(countStr)

    if #hist > 100 then
        local more = hContent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        more:SetPoint("TOPLEFT",hContent,"TOPLEFT",10,-(totalH+6))
        more:SetText(string.format("|cff888888... %d more stored (showing latest 100 matching)|r",#hist-100))
    end
end

-- ============================================================
-- ASSIGN FORWARD DECLARATIONS
-- ============================================================
OpenBeanArena = function()
    frame:Show(); BeanArena_RefreshFrame()
end

OpenHistory = function()
    if hFrame:IsShown() then hFrame:Hide(); return end
    if DB("historyX") and DB("historyY") then
        hFrame:ClearAllPoints()
        hFrame:SetPoint("CENTER",UIParent,"BOTTOMLEFT",DB("historyX"),DB("historyY"))
    else
        hFrame:SetPoint("CENTER",UIParent,"CENTER",220,0)
    end
    local w, h = BeanArenaDB.historyW, BeanArenaDB.historyH
    if w and h then hFrame:SetSize(w,h) end
    BeanArena_RefreshHistory()
    hFrame:Show()
end

-- ============================================================
-- COMMANDS FRAME
-- ============================================================
local COMMANDS_LIST = {
    { cmd="/ap",          desc="Toggle main window" },
    { cmd="/ap history",  desc="Toggle history window" },
    { cmd="/ap commands", desc="Toggle this window" },
    { cmd="/ap points",   desc="Print point breakdown" },
    { cmd="/ap honor",    desc="Print current honor" },
    { cmd="/ap reset",    desc="Print time until reset" },
    { cmd="/ap marks",    desc="Print BG mark counts" },
    { cmd="/ap options",  desc="Open options menu" },
    { cmd="/ap help",     desc="Print help" },
}

cFrame = MakeBGFrame("BeanArenaCommandsFrame", UIParent, 310, 42 + #COMMANDS_LIST * 24)
cFrame:SetFrameStrata("HIGH")
cFrame:SetMovable(true); cFrame:EnableMouse(true)
cFrame:RegisterForDrag("LeftButton")
cFrame:SetScript("OnDragStart", cFrame.StartMoving)
cFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
cFrame:Hide()
RegisterEsc(cFrame)

local cTitle = cFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
cTitle:SetPoint("TOP",cFrame,"TOP",0,-14)
cTitle:SetText("|cffFFD700BeanArena Commands|r")

local cClose = CreateFrame("Button",nil,cFrame,"UIPanelCloseButton")
cClose:SetPoint("TOPRIGHT",cFrame,"TOPRIGHT",-4,-4)
cClose:SetScript("OnClick",function() cFrame:Hide() end)

for i, entry in ipairs(COMMANDS_LIST) do
    local y = -38 - (i-1)*24
    if i > 1 then
        local div = cFrame:CreateTexture(nil,"ARTWORK")
        div:SetSize(274,1); div:SetPoint("TOPLEFT",cFrame,"TOPLEFT",18,y+5)
        div:SetColorTexture(0.3,0.3,0.3,0.3)
    end
    local cmdFS = cFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    cmdFS:SetPoint("TOPLEFT",cFrame,"TOPLEFT",18,y)
    cmdFS:SetText("|cff00CCFF"..entry.cmd.."|r")
    local descFS = cFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    descFS:SetPoint("TOPLEFT",cFrame,"TOPLEFT",145,y)
    descFS:SetText("|cffAAAAAA"..entry.desc.."|r")
end

local aliasFS = cFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
aliasFS:SetPoint("BOTTOMLEFT",cFrame,"BOTTOMLEFT",18,10)
aliasFS:SetText("|cff888888/beanarena also works in place of /ap|r")

OpenCommands = function()
    if cFrame:IsShown() then cFrame:Hide(); return end
    cFrame:ClearAllPoints()
    cFrame:SetPoint("CENTER",UIParent,"CENTER",0,0)
    cFrame:Show()
end

-- ============================================================
-- REFRESH FUNCTIONS
-- ============================================================
function BeanArena_RefreshManual()
    local m2,m3,m5 = DB("manual2v2"),DB("manual3v3"),DB("manual5v5")
    manualP2Val:SetText(m2>0 and string.format("|cffFFD700%.0f|r",CalcBracketPoints(m2,"2v2")) or "|cff666666--|r")
    manualP3Val:SetText(m3>0 and string.format("|cffFFD700%.0f|r",CalcBracketPoints(m3,"3v3")) or "|cff666666--|r")
    manualP5Val:SetText(m5>0 and string.format("|cffFFD700%.0f|r",CalcBracketPoints(m5,"5v5")) or "|cff666666--|r")
    local mb,mbb = CalcBestPoints(m2,m3,m5)
    manualBestVal:SetText(mb>0 and string.format("|cffFFD700%.0f|r |cffAAAAAA(%s)|r",mb,mbb) or "|cff666666Enter ratings above|r")
end

local function RefreshLive()
    local r2,r3,r5,g2,g3,g5 = GetLiveRatings()
    local curAP = GetCurrentArenaPoints()

    local function GT(games)
        return games>=10 and string.format("|cff00FF00%d (ok)|r",games)
                          or  string.format("|cffFF4444%d/10|r",games)
    end
    local function ProjTxt(r, bracket)
        if r<=0 then return "|cff666666--|r" end
        return string.format("|cffFFD700%.0f|r",CalcBracketPoints(r,bracket))
    end
    local function TotalTxt(r, bracket)
        if r<=0 then return "|cff666666--|r" end
        return string.format("|cff88FF88%.0f|r",CalcBracketPoints(r,bracket)+curAP)
    end

    liveR2:SetText(r2>0 and tostring(r2) or "|cff666666--|r")
    liveG2:SetText(GT(g2)); liveP2:SetText(ProjTxt(r2,"2v2")); livePT2:SetText(TotalTxt(r2,"2v2"))
    liveR3:SetText(r3>0 and tostring(r3) or "|cff666666--|r")
    liveG3:SetText(GT(g3)); liveP3:SetText(ProjTxt(r3,"3v3")); livePT3:SetText(TotalTxt(r3,"3v3"))
    liveR5:SetText(r5>0 and tostring(r5) or "|cff666666--|r")
    liveG5:SetText(GT(g5)); liveP5:SetText(ProjTxt(r5,"5v5")); livePT5:SetText(TotalTxt(r5,"5v5"))

    local er2=g2>=10 and r2 or 0; local er3=g3>=10 and r3 or 0; local er5=g5>=10 and r5 or 0
    local best,bb = CalcBestPoints(er2,er3,er5)
    liveBestVal:SetText(best>0
        and string.format("|cffFFD700%.0f|r |cffAAAAAA(%s)|r",best,bb)
        or  "|cffFF4444Need 10+ games in a bracket|r")
    apInlineVal:SetText(curAP>0
        and string.format("|cff88FF88%d|r",curAP)
        or  "|cff666666--|r")
end

local function RefreshMisc()
    local honor = GetCurrentHonor()
    honorVal:SetText(string.format("|cffFFD700%s|r",
        BreakUpLargeNumbers and BreakUpLargeNumbers(honor) or tostring(honor)))
    local ap = GetCurrentArenaPoints()
    arenaAPVal:SetText(string.format("|cff88FF88%s|r",
        BreakUpLargeNumbers and BreakUpLargeNumbers(ap) or tostring(ap)))
    resetVal:SetText("|cff00CCFF"..GetDaysToReset().."|r")
    local marks = GetPvPMarkCounts(); local parts={}
    for _,n in ipairs({"AV","WSG","AB","EotS"}) do
        table.insert(parts,string.format("%s: |cffFFD700%d|r",n,marks[n] or 0))
    end
    marksVal:SetText(table.concat(parts,"  "))
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
SLASH_BEANARENA1="/ap"; SLASH_BEANARENA2="/beanarena"
SlashCmdList["BEANARENA"]=function(msg)
    msg=msg:lower():trim()
    if msg=="" or msg=="show" then
        if frame:IsShown() then frame:Hide() else OpenBeanArena() end
    elseif msg=="history" then
        if hFrame:IsShown() then hFrame:Hide() else OpenHistory() end
    elseif msg=="commands" then
        if cFrame:IsShown() then cFrame:Hide() else OpenCommands() end
    elseif msg=="points" or msg=="rating" then
        local r2,r3,r5,g2,g3,g5=GetLiveRatings()
        local curAP=GetCurrentArenaPoints()
        local er2=g2>=10 and r2 or 0; local er3=g3>=10 and r3 or 0; local er5=g5>=10 and r5 or 0
        local best,bb=CalcBestPoints(er2,er3,er5)
        print(string.format("|cffFFD700[BeanArena]|r Ratings  (Banked AP: |cff88FF88%d|r)",curAP))
        print(string.format("  2v2: %d  %dg  proj:|cffFFD700%.0f|r  total:|cff88FF88%.0f|r  %s",r2,g2,CalcBracketPoints(r2,"2v2"),CalcBracketPoints(r2,"2v2")+curAP,g2>=10 and "|cff00FF00(ok)|r" or "|cffFF4444need 10|r"))
        print(string.format("  3v3: %d  %dg  proj:|cffFFD700%.0f|r  total:|cff88FF88%.0f|r  %s",r3,g3,CalcBracketPoints(r3,"3v3"),CalcBracketPoints(r3,"3v3")+curAP,g3>=10 and "|cff00FF00(ok)|r" or "|cffFF4444need 10|r"))
        print(string.format("  5v5: %d  %dg  proj:|cffFFD700%.0f|r  total:|cff88FF88%.0f|r  %s",r5,g5,CalcBracketPoints(r5,"5v5"),CalcBracketPoints(r5,"5v5")+curAP,g5>=10 and "|cff00FF00(ok)|r" or "|cffFF4444need 10|r"))
        print(best>0 and string.format("  Best: |cffFFD700%.0f|r from |cffFFD700%s|r",best,bb) or "  |cffFF4444No eligible bracket|r")
    elseif msg=="honor" then
        print(string.format("|cffFFD700[BeanArena]|r Honor: |cffFFD700%d|r",GetCurrentHonor()))
    elseif msg=="reset" then
        print("|cffFFD700[BeanArena]|r Reset in: |cff00CCFF"..GetDaysToReset().."|r")
    elseif msg=="marks" then
        local m=GetPvPMarkCounts(); print("|cffFFD700[BeanArena]|r Marks:")
        for n,c in pairs(m) do print("  "..n..": |cffFFD700"..c.."|r") end
    elseif msg=="options" then ShowOptions()
    elseif msg=="help" then
        print("|cffFFD700[BeanArena]|r Commands:")
        print("  /ap              - Toggle main window")
        print("  /ap history      - Toggle history window")
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
local eFrame=CreateFrame("Frame")
eFrame:RegisterEvent("ADDON_LOADED")
eFrame:RegisterEvent("PLAYER_LOGIN")
eFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eFrame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
eFrame:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
-- Snapshot opponents on unit change (catches before they leave after death)
eFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
eFrame:RegisterEvent("UNIT_HEALTH")

eFrame:SetScript("OnEvent",function(self,event,arg1)
    if event=="ADDON_LOADED" and arg1==ADDON_NAME then
        if DB("frameX") and DB("frameY") then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER",UIParent,"BOTTOMLEFT",DB("frameX"),DB("frameY"))
        else
            frame:SetPoint("CENTER",UIParent,"CENTER",0,0)
        end
        if DB("historyX") and DB("historyY") then
            hFrame:ClearAllPoints()
            hFrame:SetPoint("CENTER",UIParent,"BOTTOMLEFT",DB("historyX"),DB("historyY"))
        else
            hFrame:SetPoint("CENTER",UIParent,"CENTER",220,0)
        end
        UpdateMinimapPos()
        SetupHonorHook()
        print("|cffFFD700[BeanArena]|r Loaded! /ap help for commands.")

    elseif event=="PLAYER_LOGIN" then
        -- Set per-character key (UnitName is valid here, unlike ADDON_LOADED)
        local name  = UnitName("player") or "Unknown"
        local realm = GetRealmName and GetRealmName() or "Unknown"
        currentCharKey = name .. "-" .. realm

        -- Migrate old flat arenaHistory (pre-v1.4) into chars table
        if BeanArenaDB.arenaHistory and #BeanArenaDB.arenaHistory > 0 then
            local hist = CharHistory()
            print(string.format("|cffFFD700[BeanArena]|r Migrating %d games for %s.",
                #BeanArenaDB.arenaHistory, currentCharKey))
            for _,e in ipairs(BeanArenaDB.arenaHistory) do
                table.insert(hist, e)
            end
            BeanArenaDB.arenaHistory = nil
        end

        -- Migrate old BeanArenaCharDB.arenaHistory (v1.4 per-char that wasn't persisted)
        if BeanArenaCharDB and BeanArenaCharDB.arenaHistory and #BeanArenaCharDB.arenaHistory > 0 then
            local hist = CharHistory()
            print(string.format("|cffFFD700[BeanArena]|r Migrating %d games from CharDB for %s.",
                #BeanArenaCharDB.arenaHistory, currentCharKey))
            for _,e in ipairs(BeanArenaCharDB.arenaHistory) do
                table.insert(hist, e)
            end
            BeanArenaCharDB.arenaHistory = nil
        end

        -- Ensure note field and opponent key on all entries
        for _,entry in ipairs(CharHistory()) do
            if entry.enemy and not entry.opponent then
                entry.opponent = entry.enemy; entry.enemy = nil
            end
            if entry.note == nil then entry.note = "" end
        end

    elseif event=="PLAYER_ENTERING_WORLD" then
        if RequestPVPRewardsUpdate then RequestPVPRewardsUpdate() end
        local _,iType=IsInInstance()
        if iType=="arena" then
            if not inArena then
                inArena=true; matchStart=GetTime(); matchBracket=nil; pendingOpponents=nil
            end
        else
            inArena=false; pendingOpponents=nil
        end
        if frame:IsShown() then BeanArena_RefreshFrame() end

    elseif event=="ZONE_CHANGED_NEW_AREA" then
        local _,iType=IsInInstance()
        if iType=="arena" then
            if not inArena then
                inArena=true; matchStart=GetTime(); matchBracket=nil; pendingOpponents=nil
            end
        else
            inArena=false; pendingOpponents=nil
        end

    elseif event=="ARENA_OPPONENT_UPDATE" or (event=="UNIT_HEALTH" and arg1 and arg1:find("^arena")) then
        -- Snapshot opponents while units are still present
        if inArena then SnapshotOpponents() end

    elseif event=="UPDATE_BATTLEFIELD_STATUS" then
        if frame:IsShown() then BeanArena_RefreshFrame() end

    elseif event=="UPDATE_BATTLEFIELD_SCORE" then
        if not inArena then return end
        -- Final snapshot before units disappear
        SnapshotOpponents()
        if not matchBracket then matchBracket=DetectBracket() end
        local numScores=GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
        if numScores>0 then
            -- Find our team index by scanning score entries for the player's name
            local playerName=UnitName("player")
            local myTeam=nil
            for i=1,numScores do
                local name,_,_,_,_,_,_,_,_,_,_,_,teamIndex=GetBattlefieldScore(i)
                if name and name:find(playerName or "",1,true) then
                    myTeam=teamIndex; break
                end
            end
            local winner=GetBattlefieldWinner and GetBattlefieldWinner()
            local won
            if myTeam~=nil and winner~=nil then
                won=(winner==myTeam)
            else
                won=(winner==0)
            end
            SaveMatch(won)
            inArena=false
            if hFrame:IsShown() then BeanArena_RefreshHistory() end
        end
    end
end)

-- ============================================================
-- HONOR HOOK + PVP UI BUTTON
-- ============================================================
local honorHookDone = false

SetupHonorHook=function()
    if honorHookDone then return end
    honorHookDone=true

    -- PVPUIFrame is the standalone H-key honor/arena window in TBC Anniversary.
    -- It is always available as a global by the time the addon loads.
    -- PVPUIFrame is the standalone H-key window. It exists at load time in TBC.
    -- Try now, and also retry at PLAYER_LOGIN in case it loads late.
    local function TryAttachPVPButton()
        local pvpUI = PVPUIFrame
        if not pvpUI or _G["BeanArenaPVPButton"] then return end
        -- Button sits in the top-left, well clear of the close X (top-right)
        local pvpBtn = CreateFrame("Button","BeanArenaPVPButton",pvpUI,"UIPanelButtonTemplate")
        pvpBtn:SetSize(72,18)
        pvpBtn:SetText("BeanArena")
        pvpBtn:GetFontString():SetFontObject("GameFontNormalSmall")
        pvpBtn:SetPoint("TOPLEFT",pvpUI,"TOPLEFT",8,-4)
        pvpBtn:SetScript("OnClick",function()
            if frame:IsShown() then frame:Hide() else OpenBeanArena() end
        end)
        pvpUI:HookScript("OnShow",function()
            if DB("openWithHonor") or DB("openBothWithHonor") then OpenBeanArena() end
            if DB("openBothWithHonor") then OpenHistory() end
        end)
    end

    TryAttachPVPButton()

    -- Fallback: retry at PLAYER_LOGIN via a one-shot OnUpdate (frame may load late)
    if not _G["BeanArenaPVPButton"] then
        local retryElapsed = 0
        local retryFrame = CreateFrame("Frame")
        retryFrame:SetScript("OnUpdate", function(self, elapsed)
            retryElapsed = retryElapsed + elapsed
            TryAttachPVPButton()
            if _G["BeanArenaPVPButton"] or retryElapsed > 10 then
                self:SetScript("OnUpdate", nil)
            end
        end)
    end
end

-- ============================================================
-- TICKERS
-- ============================================================
-- Re-detect bracket every second for up to 15s after entering arena
-- (opponents may not all be loaded immediately on entry)
local bTicker = 0
local bCheckCount = 0
local bFrame = CreateFrame("Frame")
bFrame:SetScript("OnUpdate", function(self, elapsed)
    if not inArena then bCheckCount = 0; return end
    -- Once bracket is confirmed by seeing enough units, stop checking
    -- A "confirmed" bracket means we saw the expected number of opponents
    bTicker = bTicker + elapsed
    if bTicker >= 1 then
        bTicker = 0
        bCheckCount = bCheckCount + 1
        local detected = DetectBracket()
        -- Update matchBracket if not yet set, or if new detection sees more units
        -- (i.e. we saw 2 opponents earlier, now we see 3 = 3v3)
        if not matchBracket then
            matchBracket = detected
        else
            -- Upgrade bracket if we're seeing more opponents now
            local order = {["2v2"]=1, ["3v3"]=2, ["5v5"]=3}
            if (order[detected] or 0) > (order[matchBracket] or 0) then
                matchBracket = detected
            end
        end
        -- Stop after 15 checks (15 seconds)
        if bCheckCount >= 15 then
            bCheckCount = 0
        end
    end
end)

local ticker=0
frame:SetScript("OnUpdate",function(self,elapsed)
    ticker=ticker+elapsed
    if ticker>=5 then
        ticker=0; RefreshLive(); RefreshMisc()
        if not editFocused["manual2v2"] then man2v2Edit:SetText(tostring(DB("manual2v2"))) end
        if not editFocused["manual3v3"] then man3v3Edit:SetText(tostring(DB("manual3v3"))) end
        if not editFocused["manual5v5"] then man5v5Edit:SetText(tostring(DB("manual5v5"))) end
    end
end)
