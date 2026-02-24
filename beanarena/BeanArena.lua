-- BeanArena.lua
-- TBC Anniversary Arena Point Calculator & History Tracker

-- ============================================================
-- SAVED VARIABLES
-- ============================================================
BeanArenaDB = BeanArenaDB or {}

local ADDON_NAME    = "BeanArena"
local RESET_WEEKDAY = 3 -- Tuesday

local defaults = {
    manual2v2        = 0,
    manual3v3        = 0,
    manual5v5        = 0,
    minimapAngle     = 45,
    frameX           = nil,
    frameY           = nil,
    historyX         = nil,
    historyY         = nil,
    openWithHonor    = false,   -- open BeanArena with honor window
    openBothWithHonor = false,  -- open BeanArena + History with honor window
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
    local candidates = { ["2v2"]=r2>0 and CalcBracketPoints(r2,"2v2") or 0,
                         ["3v3"]=r3>0 and CalcBracketPoints(r3,"3v3") or 0,
                         ["5v5"]=r5>0 and CalcBracketPoints(r5,"5v5") or 0 }
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
    return string.format("%dd %dh %dm", math.floor(hoursLeft/24), hoursLeft%24, minsLeft)
end

-- ============================================================
-- HONOR  (TBC uses GetHonorCurrency; fallback to C_CurrencyInfo)
-- ============================================================
local function GetCurrentHonor()
    -- TBC Anniversary uses GetHonorCurrency() -> returns current honor int
    if GetHonorCurrency then
        local h = GetHonorCurrency()
        if h then return h end
    end
    -- Fallback: C_CurrencyInfo table API (some builds)
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = C_CurrencyInfo.GetCurrencyInfo(1901)
        if info then return info.quantity or 0 end
    end
    -- Fallback: old non-table GetCurrencyInfo
    if GetCurrencyInfo then
        local _, count = GetCurrencyInfo(1901)
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
-- ARENA HISTORY
-- ============================================================
local inArena       = false
local matchStart    = 0
local matchBracket  = nil

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

local function ColorClass(class)
    return string.format("|cff%s%s|r", CLASS_COLORS[class] or "AAAAAA", CLASS_SHORT[class] or (class or "?"))
end

local function GetTeamSnapshot(isEnemy)
    local members = {}
    if isEnemy then
        for i = 1, 5 do
            local u = "arena"..i
            if UnitExists(u) then
                local _, cls = UnitClass(u)
                table.insert(members, { name=UnitName(u) or "?", class=cls or "UNKNOWN" })
            end
        end
    else
        local _, cls = UnitClass("player")
        table.insert(members, { name=UnitName("player") or "?", class=cls or "UNKNOWN" })
        for i = 1, 4 do
            local u = "party"..i
            if UnitExists(u) then
                local _, pc = UnitClass(u)
                table.insert(members, { name=UnitName(u) or "?", class=pc or "UNKNOWN" })
            end
        end
    end
    return members
end

local function DetectBracket()
    local count = 0
    for i = 1, 5 do if UnitExists("arena"..i) then count = count + 1 end end
    if count >= 5 then return "5v5" elseif count >= 3 then return "3v3" else return "2v2" end
end

local function SaveMatch(won)
    if not BeanArenaDB.arenaHistory then BeanArenaDB.arenaHistory = {} end
    local d = date("*t", time())
    local entry = {
        date     = string.format("%02d/%02d %02d:%02d", d.month, d.day, d.hour, d.min),
        bracket  = matchBracket or "?",
        won      = won,
        duration = math.max(0, math.floor(GetTime() - matchStart)),
        friendly = GetTeamSnapshot(false),
        enemy    = GetTeamSnapshot(true),
    }
    table.insert(BeanArenaDB.arenaHistory, 1, entry)
    while #BeanArenaDB.arenaHistory > 200 do table.remove(BeanArenaDB.arenaHistory) end
end

-- ============================================================
-- UI HELPERS
-- ============================================================
local function MakeBGFrame(name, parent, w, h)
    local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetBackdrop({
        bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
        tile=true, tileSize=32, edgeSize=32,
        insets={left=8,right=8,top=8,bottom=8},
    })
    f:SetBackdropColor(0.1,0.1,0.15,0.95)
    return f
end

local function RegisterEsc(f)
    -- Register with UISpecialFrames so ESC closes it
    tinsert(UISpecialFrames, f:GetName())
end

local function MakeRow(parent, y, lbl)
    local l = parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    l:SetPoint("TOPLEFT",parent,"TOPLEFT",18,y); l:SetText(lbl); l:SetTextColor(0.8,0.8,0.8)
    local v = parent:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    v:SetPoint("TOPLEFT",parent,"TOPLEFT",175,y); v:SetText("--")
    return v
end

local function MakeHeader(parent, y, text)
    local h = parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    h:SetPoint("TOPLEFT",parent,"TOPLEFT",18,y); h:SetText("|cff00CCFF"..text.."|r")
end

local function MakeLine(parent, y)
    local l = parent:CreateTexture(nil,"ARTWORK")
    l:SetSize(294,1); l:SetPoint("TOPLEFT",parent,"TOPLEFT",18,y)
    l:SetColorTexture(0.4,0.4,0.4,0.6)
end

local function FS(parent,x,y)
    local f = parent:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    f:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y); f:SetText("--")
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
local minimapButton = CreateFrame("Button","BeanArenaMinimapButton",Minimap)
minimapButton:SetSize(24,24)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:SetNormalTexture("Interface\\Icons\\Achievement_Arena_2v2_7")
minimapButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
minimapButton:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

local mmBorder = minimapButton:CreateTexture(nil,"OVERLAY")
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmBorder:SetSize(40,40); mmBorder:SetPoint("TOPLEFT")

local function UpdateMinimapPos()
    local a = math.rad(DB("minimapAngle"))
    minimapButton:SetPoint("CENTER",Minimap,"CENTER",math.cos(a)*80,math.sin(a)*80)
end

minimapButton:SetScript("OnDragStart",function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate",function(self)
        local mx,my = Minimap:GetCenter()
        local cx,cy = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        SetDB("minimapAngle", math.deg(math.atan2(cy/s-my, cx/s-mx)))
        UpdateMinimapPos()
    end)
end)
minimapButton:SetScript("OnDragStop",function(self)
    self:UnlockHighlight(); self:SetScript("OnUpdate",nil)
end)
minimapButton:RegisterForDrag("LeftButton")
minimapButton:RegisterForClicks("LeftButtonUp","MiddleButtonUp","RightButtonUp")

minimapButton:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_LEFT")
    GameTooltip:SetText("|cffFFD700BeanArena|r",1,1,1)
    GameTooltip:AddLine("Left-click: toggle window",0.8,0.8,0.8)
    GameTooltip:AddLine("Middle-click: commands",0.8,0.8,0.8)
    GameTooltip:AddLine("Right-click: options",0.8,0.8,0.8)
    GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave",function() GameTooltip:Hide() end)

-- ============================================================
-- OPTIONS DROPDOWN
-- ============================================================
local optDD = CreateFrame("Frame","BeanArenaOptDD",UIParent,"UIDropDownMenuTemplate")

-- Forward declarations - assigned after frames are created
local OpenBeanArena, OpenHistory, OpenCommands, frame, hFrame, cFrame, SetupHonorHook

local function ShowOptions()
    UIDropDownMenu_Initialize(optDD, function()
        -- FIX: Use raw {} tables instead of UIDropDownMenu_CreateInfo().
        -- TBC Anniversary's UIDropDownMenu_CreateInfo() returns a shared/recycled
        -- table internally. Fields like "disabled" and "isTitle" set by one call
        -- bleed into subsequent calls, making clickable buttons appear disabled.
        -- Using raw tables avoids this entirely.
        local function Btn(text, func, checked, notCheckable)
            local i = {}
            i.text              = text
            i.func              = func
            i.checked           = checked
            i.notCheckable      = notCheckable or false
            i.isNotRadio        = notCheckable or false
            i.disabled          = false
            i.isTitle           = false
            i.keepShownOnClick  = false
            UIDropDownMenu_AddButton(i)
        end
        local function Title(text)
            local i = {}
            i.text         = text
            i.isTitle      = true
            i.notCheckable = true
            i.disabled     = true
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
            SetDB("openWithHonor",    not honorOnly)
            SetDB("openBothWithHonor", false)
            CloseDropDownMenus()
        end, honorOnly, false)

        local honorBoth = DB("openBothWithHonor")
        Btn("BeanArena + History", function()
            SetDB("openBothWithHonor", not honorBoth)
            SetDB("openWithHonor",     not honorBoth)
            CloseDropDownMenus()
        end, honorBoth, false)

        local honorOff = not DB("openWithHonor") and not DB("openBothWithHonor")
        Btn("Off", function()
            SetDB("openWithHonor",     false)
            SetDB("openBothWithHonor", false)
            CloseDropDownMenus()
        end, honorOff, false)
    end, "MENU")
    ToggleDropDownMenu(1, nil, optDD, "cursor", 0, 0)
end

minimapButton:SetScript("OnClick",function(self,btn)
    if btn=="LeftButton" then
        if frame:IsShown() then frame:Hide()
        else OpenBeanArena() end
    elseif btn=="MiddleButton" then
        if cFrame:IsShown() then cFrame:Hide()
        else OpenCommands() end
    elseif btn=="RightButton" then
        ShowOptions()
    end
end)

-- ============================================================
-- MAIN FRAME
-- ============================================================
frame = MakeBGFrame("BeanArenaFrame",UIParent,330,480)
frame:SetFrameStrata("MEDIUM")
frame:SetMovable(true); frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart",frame.StartMoving)
frame:SetScript("OnDragStop",function(self)
    self:StopMovingOrSizing()
    local x,y=self:GetCenter(); SetDB("frameX",x); SetDB("frameY",y)
end)
frame:Hide()
RegisterEsc(frame)

local titleFS = frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
titleFS:SetPoint("TOP",frame,"TOP",0,-14); titleFS:SetText("|cffFFD700BeanArena|r")

local mainClose = CreateFrame("Button",nil,frame,"UIPanelCloseButton")
mainClose:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-4,-4)
mainClose:SetScript("OnClick",function() frame:Hide() end)

local histBtn = MakeSmallButton(frame,70,22,"History")
histBtn:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-10)
histBtn:SetScript("OnClick", function() OpenHistory() end)

-- ── LIVE RATINGS ─────────────────────────────────────────
MakeHeader(frame,-42,"Live Ratings (Auto)")
MakeLine(frame,-56)

local function ColHdr(x,y,txt)
    local f=frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    f:SetPoint("TOPLEFT",frame,"TOPLEFT",x,y); f:SetText("|cffAAAAAA"..txt.."|r")
end
ColHdr(18,-63,"Bracket"); ColHdr(90,-63,"Rating"); ColHdr(155,-63,"Games"); ColHdr(225,-63,"Points")
MakeLine(frame,-71)

local function LiveRow(y,label)
    local l=frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    l:SetPoint("TOPLEFT",frame,"TOPLEFT",18,y); l:SetText(label); l:SetTextColor(0.8,0.8,0.8)
    return FS(frame,90,y), FS(frame,155,y), FS(frame,225,y)
end

local liveR2,liveG2,liveP2 = LiveRow(-79, "2v2")
local liveR3,liveG3,liveP3 = LiveRow(-95, "3v3")
local liveR5,liveG5,liveP5 = LiveRow(-111,"5v5")
MakeLine(frame,-123)

-- Best Reward inline (label + value on same line, value right after label)
local bestLbl = frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
bestLbl:SetPoint("TOPLEFT",frame,"TOPLEFT",18,-129)
bestLbl:SetText("Best Reward:"); bestLbl:SetTextColor(0.8,0.8,0.8)
local liveBestVal = frame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
liveBestVal:SetPoint("LEFT",bestLbl,"RIGHT",6,0)
liveBestVal:SetText("--")

-- ── MANUAL ENTRY ──────────────────────────────────────────
MakeLine(frame,-147)
MakeHeader(frame,-153,"Manual Rating Entry")
MakeLine(frame,-167)

local editFocused = {}

local function MakeEditRow(y,labelText,dbKey)
    local l=frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    l:SetPoint("TOPLEFT",frame,"TOPLEFT",18,y); l:SetText(labelText); l:SetTextColor(0.8,0.8,0.8)
    local eb=CreateFrame("EditBox",nil,frame,"InputBoxTemplate")
    eb:SetSize(80,20); eb:SetPoint("TOPLEFT",frame,"TOPLEFT",175,y+4)
    eb:SetAutoFocus(false); eb:SetNumeric(true); eb:SetMaxLetters(4)
    eb:SetText(tostring(DB(dbKey)))
    eb:SetScript("OnEditFocusGained",function() editFocused[dbKey]=true end)
    eb:SetScript("OnEditFocusLost",function(self)
        editFocused[dbKey]=nil; SetDB(dbKey,tonumber(self:GetText()) or 0); BeanArena_RefreshManual()
    end)
    eb:SetScript("OnEnterPressed",function(self)
        SetDB(dbKey,tonumber(self:GetText()) or 0); self:ClearFocus(); BeanArena_RefreshManual()
    end)
    eb:SetScript("OnEscapePressed",function(self)
        self:SetText(tostring(DB(dbKey))); self:ClearFocus()
    end)
    return eb
end

local man2v2Edit = MakeEditRow(-173,"2v2 Rating:","manual2v2")
local man3v3Edit = MakeEditRow(-195,"3v3 Rating:","manual3v3")
local man5v5Edit = MakeEditRow(-217,"5v5 Rating:","manual5v5")

MakeLine(frame,-235)
local manualBestVal = MakeRow(frame,-241,"Manual Best:")
local manualP2Val   = MakeRow(frame,-257,"  2v2 Points:")
local manualP3Val   = MakeRow(frame,-273,"  3v3 Points:")
local manualP5Val   = MakeRow(frame,-289,"  5v5 Points:")

-- ── HONOR & BG MARKS ──────────────────────────────────────
MakeLine(frame,-305)
MakeHeader(frame,-311,"Honor and BG Marks")
MakeLine(frame,-325)

local honorVal = MakeRow(frame,-331,"Current Honor:")
local resetVal = MakeRow(frame,-349,"Reset In:")

MakeLine(frame,-365)
MakeHeader(frame,-371,"PvP Marks in Bags")
MakeLine(frame,-385)

local marksVal = frame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
marksVal:SetPoint("TOPLEFT",frame,"TOPLEFT",18,-391)
marksVal:SetText("--"); marksVal:SetJustifyH("LEFT")

-- ============================================================
-- HISTORY FRAME
-- ============================================================
hFrame = MakeBGFrame("BeanArenaHistoryFrame",UIParent,560,480)
hFrame:SetFrameStrata("HIGH")
hFrame:SetMovable(true); hFrame:EnableMouse(true)
hFrame:RegisterForDrag("LeftButton")
hFrame:SetScript("OnDragStart",hFrame.StartMoving)
hFrame:SetScript("OnDragStop",function(self)
    self:StopMovingOrSizing()
    local x,y=self:GetCenter(); SetDB("historyX",x); SetDB("historyY",y)
end)
hFrame:Hide()
RegisterEsc(hFrame)

-- ============================================================
-- COMMANDS FRAME
-- ============================================================
cFrame = MakeBGFrame("BeanArenaCommandsFrame",UIParent,310,310)
cFrame:SetFrameStrata("HIGH")
cFrame:SetMovable(true); cFrame:EnableMouse(true)
cFrame:RegisterForDrag("LeftButton")
cFrame:SetScript("OnDragStart",cFrame.StartMoving)
cFrame:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
cFrame:Hide()
RegisterEsc(cFrame)

local cTitle = cFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
cTitle:SetPoint("TOP",cFrame,"TOP",0,-14); cTitle:SetText("|cffFFD700BeanArena Commands|r")

local cClose = CreateFrame("Button",nil,cFrame,"UIPanelCloseButton")
cClose:SetPoint("TOPRIGHT",cFrame,"TOPRIGHT",-4,-4)
cClose:SetScript("OnClick",function() cFrame:Hide() end)

local COMMANDS_LIST = {
    { cmd="/ap",              desc="Toggle main window" },
    { cmd="/ap history",      desc="Toggle history window" },
    { cmd="/ap commands",     desc="Toggle this commands window" },
    { cmd="/ap points",       desc="Print point breakdown to chat" },
    { cmd="/ap honor",        desc="Print current honor to chat" },
    { cmd="/ap reset",        desc="Print time until weekly reset" },
    { cmd="/ap marks",        desc="Print BG mark counts to chat" },
    { cmd="/ap options",      desc="Open options menu at cursor" },
    { cmd="/ap help",         desc="Print help to chat" },
}

local cmdStartY = -42
for i, entry in ipairs(COMMANDS_LIST) do
    local y = cmdStartY - (i-1) * 24

    -- Divider line between rows
    if i > 1 then
        local div = cFrame:CreateTexture(nil,"ARTWORK")
        div:SetSize(274,1); div:SetPoint("TOPLEFT",cFrame,"TOPLEFT",18, y + 5)
        div:SetColorTexture(0.3,0.3,0.3,0.3)
    end

    local cmdFS = cFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    cmdFS:SetPoint("TOPLEFT",cFrame,"TOPLEFT",18, y)
    cmdFS:SetText("|cff00CCFF"..entry.cmd.."|r")

    local descFS = cFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    descFS:SetPoint("TOPLEFT",cFrame,"TOPLEFT",140, y)
    descFS:SetText("|cffAAAAAA"..entry.desc.."|r")
end

-- Alias note at bottom
local aliasFS = cFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
aliasFS:SetPoint("BOTTOMLEFT",cFrame,"BOTTOMLEFT",18,14)
aliasFS:SetText("|cff888888/beanarena also works in place of /ap|r")

-- Assign forward-declared open functions now that all frames exist
OpenBeanArena = function()
    frame:Show(); BeanArena_RefreshFrame()
end
OpenHistory = function()
    if hFrame:IsShown() then hFrame:Hide(); return end
    if DB("historyX") and DB("historyY") then
        hFrame:ClearAllPoints()
        hFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", DB("historyX"), DB("historyY"))
    else
        hFrame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end
    BeanArena_RefreshHistory()
    hFrame:Show()
end
OpenCommands = function()
    if cFrame:IsShown() then cFrame:Hide(); return end
    cFrame:ClearAllPoints()
    cFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    cFrame:Show()
end

local hTitle = hFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
hTitle:SetPoint("TOP",hFrame,"TOP",0,-14); hTitle:SetText("|cffFFD700Arena History|r")

local hClose = CreateFrame("Button",nil,hFrame,"UIPanelCloseButton")
hClose:SetPoint("TOPRIGHT",hFrame,"TOPRIGHT",-4,-4)
hClose:SetScript("OnClick",function() hFrame:Hide() end)

local clearBtn = MakeSmallButton(hFrame,110,22,"Clear History")
clearBtn:SetPoint("BOTTOMLEFT",hFrame,"BOTTOMLEFT",14,10)
clearBtn:SetScript("OnClick",function()
    BeanArenaDB.arenaHistory = {}
    BeanArena_RefreshHistory()
    print("|cffFFD700[BeanArena]|r History cleared.")
end)

-- Column headers (persistent, above scroll)
local function HdrFS(x,txt)
    local f=hFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    f:SetPoint("TOPLEFT",hFrame,"TOPLEFT",x,-38); f:SetText("|cffAAAAAA"..txt.."|r")
end
HdrFS(18,"Date"); HdrFS(105,"Bracket"); HdrFS(160,"Result")
HdrFS(210,"Time"); HdrFS(258,"Friendly Team"); HdrFS(400,"Enemy Team")

local hDivLine = hFrame:CreateTexture(nil,"ARTWORK")
hDivLine:SetSize(528,1); hDivLine:SetPoint("TOPLEFT",hFrame,"TOPLEFT",18,-52)
hDivLine:SetColorTexture(0.4,0.4,0.4,0.7)

-- Scroll area
local hScroll = CreateFrame("ScrollFrame","BeanArenaHistScroll",hFrame,"UIPanelScrollFrameTemplate")
hScroll:SetPoint("TOPLEFT",hFrame,"TOPLEFT",14,-58)
hScroll:SetPoint("BOTTOMRIGHT",hFrame,"BOTTOMRIGHT",-30,38)

local hContent = CreateFrame("Frame",nil,hScroll)
hContent:SetSize(520,10)
hScroll:SetScrollChild(hContent)

local historyRowFrames = {}

local function FormatDur(s)
    if not s or s==0 then return "?" end
    return string.format("%d:%02d", math.floor(s/60), s%60)
end

local function TeamStr(members)
    if not members or #members==0 then return "|cff666666none|r" end
    local parts={}
    for _,m in ipairs(members) do
        table.insert(parts, ColorClass(m.class).." |cff888888"..m.name.."|r")
    end
    return table.concat(parts,", ")
end

function BeanArena_RefreshHistory()
    -- Clear old rows
    for _,r in ipairs(historyRowFrames) do r:Hide() end
    historyRowFrames={}

    local hist = BeanArenaDB.arenaHistory or {}
    local ROW_H = 40

    if #hist == 0 then
        hContent:SetHeight(60)
        local empty = hContent:CreateFontString(nil,"OVERLAY","GameFontNormal")
        empty:SetPoint("TOPLEFT",hContent,"TOPLEFT",10,-20)
        empty:SetText("|cff888888No arena games recorded yet. Play some arenas and they will appear here.|r")
        table.insert(historyRowFrames, {Hide=function() empty:SetText("") end})
        return
    end

    hContent:SetHeight(math.max(10, #hist * ROW_H + 10))

    for i, entry in ipairs(hist) do
        if i > 100 then break end
        local yOff = -(i-1)*ROW_H - 4

        local row = CreateFrame("Frame",nil,hContent)
        row:SetSize(520, ROW_H-2)
        row:SetPoint("TOPLEFT",hContent,"TOPLEFT",0,yOff)

        if i%2==0 then
            local bg=row:CreateTexture(nil,"BACKGROUND")
            bg:SetAllPoints(); bg:SetColorTexture(1,1,1,0.04)
        end

        local function Cell(x, txt, w, font)
            local f=row:CreateFontString(nil,"OVERLAY",font or "GameFontNormalSmall")
            f:SetPoint("TOPLEFT",row,"TOPLEFT",x,-3)
            f:SetText(txt); f:SetWidth(w); f:SetJustifyH("LEFT"); f:SetWordWrap(false)
        end

        local resultCol = entry.won and "|cff00FF00Win|r" or "|cffFF4444Loss|r"

        Cell(0,   entry.date or "?",   85)
        Cell(87,  entry.bracket or "?",50)
        Cell(140, resultCol,            45)
        Cell(188, FormatDur(entry.duration), 45)
        -- Team strings split across two lines via two font strings
        local fs1 = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        fs1:SetPoint("TOPLEFT",row,"TOPLEFT",236,-2)
        fs1:SetText(TeamStr(entry.friendly)); fs1:SetWidth(145); fs1:SetJustifyH("LEFT"); fs1:SetWordWrap(true)

        local fs2 = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        fs2:SetPoint("TOPLEFT",row,"TOPLEFT",385,-2)
        fs2:SetText(TeamStr(entry.enemy)); fs2:SetWidth(130); fs2:SetJustifyH("LEFT"); fs2:SetWordWrap(true)

        -- Divider
        local div=row:CreateTexture(nil,"ARTWORK")
        div:SetSize(520,1); div:SetPoint("BOTTOMLEFT",row,"BOTTOMLEFT",0,0)
        div:SetColorTexture(0.3,0.3,0.3,0.4)

        table.insert(historyRowFrames, row)
    end

    if #hist > 100 then
        local more = hContent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        more:SetPoint("TOPLEFT",hContent,"TOPLEFT",10,-(100*ROW_H+12))
        more:SetText(string.format("|cff888888... %d more games stored (showing latest 100)|r", #hist-100))
    end
end

-- ============================================================
-- REFRESH
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
    local function GT(games)
        return games>=10 and string.format("|cff00FF00%d (ok)|r",games)
                          or  string.format("|cffFF4444%d/10|r",games)
    end
    liveR2:SetText(r2>0 and tostring(r2) or "|cff666666--|r")
    liveG2:SetText(GT(g2))
    liveP2:SetText(r2>0 and string.format("|cffFFD700%.0f|r",CalcBracketPoints(r2,"2v2")) or "|cff666666--|r")
    liveR3:SetText(r3>0 and tostring(r3) or "|cff666666--|r")
    liveG3:SetText(GT(g3))
    liveP3:SetText(r3>0 and string.format("|cffFFD700%.0f|r",CalcBracketPoints(r3,"3v3")) or "|cff666666--|r")
    liveR5:SetText(r5>0 and tostring(r5) or "|cff666666--|r")
    liveG5:SetText(GT(g5))
    liveP5:SetText(r5>0 and string.format("|cffFFD700%.0f|r",CalcBracketPoints(r5,"5v5")) or "|cff666666--|r")

    local er2=g2>=10 and r2 or 0; local er3=g3>=10 and r3 or 0; local er5=g5>=10 and r5 or 0
    local best,bb = CalcBestPoints(er2,er3,er5)
    liveBestVal:SetText(best>0
        and string.format("|cffFFD700%.0f|r |cffAAAAAA(%s)|r",best,bb)
        or  "|cffFF4444Need 10+ games in a bracket|r")
end

local function RefreshMisc()
    local honor = GetCurrentHonor()
    honorVal:SetText(string.format("|cffFFD700%s|r",
        BreakUpLargeNumbers and BreakUpLargeNumbers(honor) or tostring(honor)))
    resetVal:SetText("|cff00CCFF"..GetDaysToReset().."|r")
    local marks=GetPvPMarkCounts(); local parts={}
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
        local er2=g2>=10 and r2 or 0; local er3=g3>=10 and r3 or 0; local er5=g5>=10 and r5 or 0
        local best,bb=CalcBestPoints(er2,er3,er5)
        print("|cffFFD700[BeanArena]|r Ratings:")
        print(string.format("  2v2: %d  %dg  |cffFFD700%.0fpts|r  %s",r2,g2,CalcBracketPoints(r2,"2v2"),g2>=10 and "|cff00FF00(ok)|r" or "|cffFF4444need 10|r"))
        print(string.format("  3v3: %d  %dg  |cffFFD700%.0fpts|r  %s",r3,g3,CalcBracketPoints(r3,"3v3"),g3>=10 and "|cff00FF00(ok)|r" or "|cffFF4444need 10|r"))
        print(string.format("  5v5: %d  %dg  |cffFFD700%.0fpts|r  %s",r5,g5,CalcBracketPoints(r5,"5v5"),g5>=10 and "|cff00FF00(ok)|r" or "|cffFF4444need 10|r"))
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
        print("  /ap              — Toggle main window")
        print("  /ap history      — Toggle history window")
        print("  /ap commands     — Toggle commands window")
        print("  /ap points       — Print point breakdown")
        print("  /ap honor        — Print current honor")
        print("  /ap reset        — Print time until weekly reset")
        print("  /ap marks        — Print BG mark counts")
        print("  /ap options      — Options menu")
        print("  /ap help         — This help")
    else
        print("|cffFF4444[BeanArena]|r Unknown command. /ap help")
    end
end

-- ============================================================
-- EVENTS
-- ============================================================
local eFrame=CreateFrame("Frame")
eFrame:RegisterEvent("ADDON_LOADED")
eFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eFrame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
eFrame:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")

eFrame:SetScript("OnEvent",function(self,event,arg1)
    if event=="ADDON_LOADED" and arg1==ADDON_NAME then
        if not BeanArenaDB.arenaHistory then BeanArenaDB.arenaHistory={} end
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

    elseif event=="PLAYER_ENTERING_WORLD" then
        if RequestPVPRewardsUpdate then RequestPVPRewardsUpdate() end
        local _,iType=IsInInstance()
        if iType=="arena" then
            if not inArena then
                inArena=true; matchStart=GetTime(); matchBracket=nil
            end
        else
            inArena=false
        end
        if frame:IsShown() then BeanArena_RefreshFrame() end

    elseif event=="ZONE_CHANGED_NEW_AREA" then
        local _,iType=IsInInstance()
        if iType=="arena" then
            if not inArena then inArena=true; matchStart=GetTime(); matchBracket=nil end
        else
            inArena=false
        end

    elseif event=="UPDATE_BATTLEFIELD_STATUS" then
        if frame:IsShown() then BeanArena_RefreshFrame() end

    elseif event=="UPDATE_BATTLEFIELD_SCORE" then
        if not inArena then return end
        -- Snapshot bracket before resetting
        if not matchBracket then matchBracket=DetectBracket() end
        local numScores=GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
        if numScores>0 then
            local winner=GetBattlefieldWinner and GetBattlefieldWinner()
            -- winner: 0=Alliance/TeamA, 1=Horde/TeamB, nil=unknown
            local myTeamIndex = UnitFactionGroup and (UnitFactionGroup("player")=="Alliance" and 0 or 1) or 0
            local won = (winner~=nil) and (winner==myTeamIndex)
            SaveMatch(won)
            inArena=false
            if hFrame:IsShown() then BeanArena_RefreshHistory() end
        end
    end
end)

-- Hook honor window open (H key calls TogglePVPUI in TBC)
-- We hook both ShowUIPanel and TogglePVPUI to catch both keyboard and click
local function OnHonorOpen()
    if DB("openWithHonor") or DB("openBothWithHonor") then
        if frame:IsShown() then frame:Hide()
        else OpenBeanArena() end
    end
    if DB("openBothWithHonor") then
        if hFrame:IsShown() then hFrame:Hide()
        else OpenHistory() end
    end
end

-- Hook PVPFrame OnShow - fires for both H keybind and button click
-- We do this in a deferred call so PVPFrame is guaranteed to exist
local honorHookDone = false
SetupHonorHook = function()
    if honorHookDone then return end
    honorHookDone = true
    if PVPFrame then
        -- OnShow only fires when the frame opens, so we only open BeanArena here
        PVPFrame:HookScript("OnShow", function()
            if DB("openWithHonor") or DB("openBothWithHonor") then
                OpenBeanArena()
            end
            if DB("openBothWithHonor") then
                OpenHistory()
            end
        end)
    end
    -- Hook TogglePVPUI if it exists (not present in all TBC Anniversary builds)
    if TogglePVPUI and type(TogglePVPUI) == "function" then
        hooksecurefunc("TogglePVPUI", OnHonorOpen)
    end
end

-- Bracket detection ticker (runs while in arena, checks after 2s)
local bTicker=0
local bFrame=CreateFrame("Frame")
bFrame:SetScript("OnUpdate",function(self,elapsed)
    if not inArena or matchBracket then return end
    bTicker=bTicker+elapsed
    if bTicker>=2 then bTicker=0; matchBracket=DetectBracket() end
end)

-- Main refresh ticker
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
