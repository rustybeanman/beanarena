"""
embed_ref.py  —  BeanArena v0.3.7 navigation revamp
  • "Menu" dropdown at top-left of main frame (replaces Reference+Honor buttons)
  • Everything in ONE window — no popup windows
  • Sections: Calculator | Honor | Arena Gear | Weapons | Honor Gear | CC/DR Table | Help
  • CC/DR table revamped: Quick Reference + Full Breakdown, fixed font glitches
"""
import sys, re

PATH = r"C:\Users\jedol\Documents\development\beanarena\beanarena\BeanArena.lua"

with open(PATH, encoding="utf-8") as f:
    content = f.read()
print(f"Read {len(content)} chars")

def die(label, hint=""):
    print(f"FAIL [{label}]{' — ' + hint if hint else ''}"); sys.exit(1)

def check(content, marker, label):
    if marker not in content: die(label, repr(marker[:80]))

def rep1(content, old, new, label):
    check(content, old, label)
    return content.replace(old, new, 1)

def slice_replace(content, start_marker, end_marker, new_text, label):
    check(content, start_marker, label+"-start")
    check(content, end_marker,   label+"-end")
    i0 = content.index(start_marker)
    i1 = content.index(end_marker)
    if i0 >= i1: die(label, "markers out of order")
    return content[:i0] + new_text + content[i1:]

# ── 1. Fix arrow (U+2192 →) and em-dash (U+2014 —) in DR descs ──────────
content = content.replace("→", ">")
print("op1: fixed U+2192 arrow chars")

# ── 2. Update versionFS text ─────────────────────────────────────────────
content = rep1(content,
    'versionFS:SetText("|cff666666v0.3.3  •  TBC Anniversary|r")',
    'versionFS:SetText("|cff666666v0.3.7  •  TBC Anniversary|r")',
    "versionFS")
print("op2: updated versionFS")

# ── 3. Update forward declarations (remove honorFrame, refFrame, RefreshHonorFrame) ──
OLD_FWD = ("local honorFrame, charViewFrame, refFrame\n"
           "local BeanArena_RefreshRefFrame, BeanArena_OpenRefFrame\n"
           "local BeanArena_RefreshHonorFrame")
NEW_FWD = ("local charViewFrame\n"
           "local BeanArena_RefreshRefFrame, BeanArena_OpenRefFrame")
content = rep1(content, OLD_FWD, NEW_FWD, "fwd-decl")
print("op3: updated forward declarations")

# ── 4. Replace 2-button row with Menu dropdown button ────────────────────
BTNS_MARKER = "local BTNW2 = math.floor((CW - 4) / 2)"
CHAR_MARKER  = "local charDDLbl = frame:CreateFontString"
check(content, BTNS_MARKER, "btn-row-start")
check(content, CHAR_MARKER,  "charDD-start")
i0 = content.index(BTNS_MARKER)
i1 = content.index(CHAR_MARKER)
if i0 >= i1: die("btn-row", "markers out of order")

NEW_MENU_BTN = (
    "-- ── Menu dropdown (top-left of frame) ──────────────────────────────\n"
    'local MENU_SECTIONS = {"Calculator","Honor","Arena Gear","Weapons","Honor Gear","CC/DR Table","Help"}\n'
    'local mainMenuBtn = CreateFrame("Button", "BeanArenaMenuBtn", frame, "UIPanelButtonTemplate")\n'
    "mainMenuBtn:SetSize(120, 22)\n"
    'mainMenuBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)\n'
    'mainMenuBtn:GetFontString():SetFontObject("GameFontNormalSmall")\n'
    'mainMenuBtn:SetText("Menu  v")\n'
    'local mainMenuDD = CreateFrame("Frame", "BeanArenaMainMenuDD", UIParent, "UIDropDownMenuTemplate")\n'
    "mainMenuBtn:SetScript(\"OnClick\", function(self)\n"
    "    UIDropDownMenu_Initialize(mainMenuDD, function()\n"
    "        for _, sec in ipairs(MENU_SECTIONS) do\n"
    "            local info = UIDropDownMenu_CreateInfo()\n"
    "            info.text = sec; info.notCheckable = true\n"
    "            info.func = function() BeanArena_OpenRefFrame(sec); CloseDropDownMenus() end\n"
    "            UIDropDownMenu_AddButton(info)\n"
    "        end\n"
    '    end, "MENU")\n'
    "    ToggleDropDownMenu(1, nil, mainMenuDD, self, 0, -4)\n"
    "end)\n\n"
)
content = content[:i0] + NEW_MENU_BTN + content[i1:]
print("op4: replaced button row with Menu button")

# ── 5. Update RefreshMisc ─────────────────────────────────────────────────
OLD_RM = ("local function RefreshMisc()\n"
          "    if refFrame:IsShown()   then BeanArena_RefreshRefFrame()    end\n"
          "    if honorFrame:IsShown() and BeanArena_RefreshHonorFrame then\n"
          "        BeanArena_RefreshHonorFrame()\n"
          "    end\n"
          "end")
NEW_RM = ("local function RefreshMisc()\n"
          "    if BeanArena_RefreshRefFrame then BeanArena_RefreshRefFrame() end\n"
          "end")
content = rep1(content, OLD_RM, NEW_RM, "RefreshMisc")
print("op5: updated RefreshMisc")

# ── 6. Remove honorFrame block ────────────────────────────────────────────
H_START = ("-- ============================================================\n"
           "-- POPUP: HONOR WINDOW\n"
           "-- Full honor data, marks, weekly plan, gear progress.\n"
           "-- ============================================================")
F_START = ("-- ============================================================\n"
           "-- FORWARD DECLARATION ASSIGNMENT\n"
           "-- ============================================================")
content = slice_replace(content, H_START, F_START, "", "honorFrame")
print("op6: removed honorFrame block")

# ── 7. Extract build functions from old refFrame block ────────────────────
RS_MARKER = ("-- ============================================================\n"
             "-- POPUP: UNIFIED REFERENCE FRAME\n"
             "-- Arena Gear / Weapons / Honor Gear / CC/DR Table / Info\n"
             "-- ============================================================\ndo")
SC_MARKER = ("-- ============================================================\n"
             "-- SLASH COMMANDS  ( /ba  and  /beanarena )\n"
             "-- ============================================================")
check(content, RS_MARKER, "ref-start")
check(content, SC_MARKER, "slash-start")
i_rs = content.index(RS_MARKER)
i_sc = content.index(SC_MARKER)
ref_block = content[i_rs:i_sc]

AF = "    local function BuildArenaContent()"
WF = "    local function BuildWeaponsContent()"
HF = "    local function BuildHonorContent()"
DF = "    local function BuildDRContent()"
for m, lbl in [(AF,"arena"),(WF,"weap"),(HF,"honor"),(DF,"dr")]:
    if m not in ref_block: die(lbl+"-fn", "not found in ref_block")

arena_fn = ref_block[ref_block.index(AF) : ref_block.index(WF)]
weap_fn  = ref_block[ref_block.index(WF) : ref_block.index(HF)]
honor_fn = ref_block[ref_block.index(HF) : ref_block.index(DF)]

def rename_vars(s):
    s = s.replace("rfSeason", "ovSeason")
    s = s.replace("rfClass",  "ovClass")
    s = s.replace("rfCnt",    "ovCnt")
    s = re.sub(r'\bRCW\b', 'OV_RCW', s)
    return s

arena_fn = rename_vars(arena_fn)
weap_fn  = rename_vars(weap_fn)
honor_fn = rename_vars(honor_fn)
print(f"op7: extracted build fns: arena={len(arena_fn)}, weap={len(weap_fn)}, honor={len(honor_fn)}")

# ── 8. Compose new embedded overlay block ────────────────────────────────
NEW_BLOCK = (
"""-- ============================================================
-- EMBEDDED REFERENCE OVERLAY  (v0.3.7)
-- Single-window content panel, switched via Menu dropdown.
-- Sections: Calculator | Honor | Arena Gear | Weapons | Honor Gear | CC/DR Table | Help
-- ============================================================
do
    local OV_RCW = FW - 4 - 8 - 20  -- 398 px: overlay_w - left_pad - scrollbar

    -- ── Overlay frame (child of frame, covers calc content below title bar) ──
    local ovTmpl = (BackdropTemplateMixin ~= nil) and "BackdropTemplate" or nil
    local refOverlay = CreateFrame("Frame", "BeanArenaRefOv", frame, ovTmpl)
    refOverlay:SetPoint("TOPLEFT",     frame, "TOPLEFT",     2, -40)
    refOverlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2,  2)
    if not refOverlay.SetBackdrop and BackdropTemplateMixin then
        Mixin(refOverlay, BackdropTemplateMixin)
    end
    if refOverlay.SetBackdrop then
        refOverlay:SetBackdrop({
            bgFile = "Interface\\\\DialogFrame\\\\UI-DialogBox-Background",
            tile = true, tileSize = 32,
        })
        refOverlay:SetBackdropColor(0, 0, 0, 1)
    end
    refOverlay:Hide()

    local ovSection = "Calculator"
    local ovSeason  = 2
    local ovClass   = "Warrior"

    -- ── Season toggle buttons (hidden for Honor, CC/DR Table, Help) ───────
    local ovS1Btn = CreateFrame("Button", nil, refOverlay, "UIPanelButtonTemplate")
    ovS1Btn:SetSize(48, 22)
    ovS1Btn:SetPoint("TOPLEFT", refOverlay, "TOPLEFT", 8, -6)
    ovS1Btn:SetText("S1"); ovS1Btn:GetFontString():SetFontObject("GameFontNormalSmall")
    ovS1Btn:Hide()
    local ovS2Btn = CreateFrame("Button", nil, refOverlay, "UIPanelButtonTemplate")
    ovS2Btn:SetSize(48, 22)
    ovS2Btn:SetPoint("LEFT", ovS1Btn, "RIGHT", 4, 0)
    ovS2Btn:SetText("S2"); ovS2Btn:GetFontString():SetFontObject("GameFontNormalSmall")
    ovS2Btn:Hide()

    -- ── Class selector (Arena Gear only) ─────────────────────────────
    local ovClassBtn = CreateFrame("Button", nil, refOverlay, "UIPanelButtonTemplate")
    ovClassBtn:SetSize(138, 22)
    ovClassBtn:SetPoint("LEFT", ovS2Btn, "RIGHT", 6, 0)
    ovClassBtn:GetFontString():SetFontObject("GameFontNormalSmall")
    ovClassBtn:SetText("Warrior  v"); ovClassBtn:Hide()
    local ovClassDD = CreateFrame("Frame", "BeanArenaOvClassDD", UIParent, "UIDropDownMenuTemplate")

    -- ── Scroll area ───────────────────────────────────────────────────
    local ovScr = CreateFrame("ScrollFrame", "BeanArenaOvScr", refOverlay, "UIPanelScrollFrameTemplate")
    ovScr:SetPoint("TOPLEFT",     refOverlay, "TOPLEFT",      8, -34)
    ovScr:SetPoint("BOTTOMRIGHT", refOverlay, "BOTTOMRIGHT", -20,   4)
    local ovCnt = CreateFrame("Frame", nil, ovScr)
    ovCnt:SetWidth(OV_RCW); ovCnt:SetHeight(10)
    ovScr:SetScrollChild(ovCnt)

    local function ClearContent()
        for _, ch in ipairs({ovCnt:GetChildren()}) do ch:Hide() end
        for _, r  in ipairs({ovCnt:GetRegions()})  do r:Hide()  end
    end

    local SwitchPage  -- forward decl

    -- ================================================================
    -- HONOR TRACKING PAGE
    -- ================================================================
    local ovHonorRefs = {}

    local function BuildHonorPage()
        ClearContent(); ovHonorRefs = {}
        local cy = -2; local PAD = 6; local BARW = OV_RCW - PAD * 2
        local function OLine()
            local d = ovCnt:CreateTexture(nil,"ARTWORK")
            d:SetSize(OV_RCW,1); d:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",0,cy-2)
            d:SetColorTexture(0.3,0.3,0.3,0.5); cy=cy-8
        end
        local function OHdr(txt)
            local h=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormal")
            h:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD,cy)
            h:SetText("|cff00CCFF"..txt.."|r"); cy=cy-16
        end
        local function ORow(lbl)
            local l=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormal")
            l:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD,cy)
            l:SetText(lbl); l:SetTextColor(0.8,0.8,0.8)
            local v=ovCnt:CreateFontString(nil,"OVERLAY","GameFontHighlight")
            v:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",160,cy); v:SetText("--"); cy=cy-18; return v
        end
        OHdr("Current Status"); OLine()
        ovHonorRefs.honorVal = ORow("Current Honor:")
        ovHonorRefs.resetVal = ORow("Reset In:")
        ovHonorRefs.apVal    = ORow("Arena Points:")
        OLine()
        local barBG=ovCnt:CreateTexture(nil,"BACKGROUND")
        barBG:SetSize(BARW,14); barBG:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD,cy-2)
        barBG:SetColorTexture(0.12,0.12,0.12,0.9)
        local barFill=ovCnt:CreateTexture(nil,"ARTWORK")
        barFill:SetSize(1,14); barFill:SetPoint("TOPLEFT",barBG,"TOPLEFT",0,0)
        barFill:SetColorTexture(0.85,0.75,0.1,1)
        local barText=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        barText:SetPoint("CENTER",barBG,"CENTER",0,0); barText:SetText("0 / 75,000")
        ovHonorRefs.barFill=barFill; ovHonorRefs.barWidth=BARW; ovHonorRefs.barText=barText
        cy=cy-20
        local capWarn=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        capWarn:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD,cy); capWarn:SetText(""); cy=cy-16
        ovHonorRefs.capWarn=capWarn
        OLine(); OHdr("PvP Marks in Bags"); OLine()
        ovHonorRefs.mkAV   = ORow("Alterac Valley:")
        ovHonorRefs.mkWSG  = ORow("Warsong Gulch:")
        ovHonorRefs.mkAB   = ORow("Arathi Basin:")
        ovHonorRefs.mkEotS = ORow("Eye of the Storm:")
        OLine(); OHdr("Weekly Plan"); OLine()
        local planFS=ovCnt:CreateFontString(nil,"OVERLAY","GameFontHighlight")
        planFS:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD,cy)
        planFS:SetWidth(OV_RCW-PAD*2); planFS:SetJustifyH("LEFT")
        planFS:SetText("--"); cy=cy-36; ovHonorRefs.planFS=planFS
        OLine(); OHdr("Honor Gear Progress"); OLine()
        local COL={slot=PAD,marks=PAD+120,honor=PAD+255,ready=PAD+345}
        local function CHdr(x,t)
            local f=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            f:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",x,cy); f:SetText("|cffAAAAAA"..t.."|r")
        end
        CHdr(COL.slot,"Slot"); CHdr(COL.marks,"Marks"); CHdr(COL.honor,"Honor"); CHdr(COL.ready,"Ready?")
        cy=cy-14
        local dL=ovCnt:CreateTexture(nil,"ARTWORK")
        dL:SetSize(OV_RCW,1); dL:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",0,cy)
        dL:SetColorTexture(0.3,0.3,0.3,0.5); cy=cy-8
        local gearRefs={}
        for _,gear in ipairs(HONOR_GEAR_FULL) do
            local slFS=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            slFS:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",COL.slot,cy)
            slFS:SetText("|cffCCCCCC"..gear.slot.."|r")
            local mkFS=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            mkFS:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",COL.marks,cy); mkFS:SetText("--")
            local hoFS=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            hoFS:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",COL.honor,cy); hoFS:SetText("--")
            local rdFS=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            rdFS:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",COL.ready,cy); rdFS:SetText("--")
            gearRefs[#gearRefs+1]={gear=gear,mkFS=mkFS,hoFS=hoFS,rdFS=rdFS}; cy=cy-15
        end
        ovHonorRefs.gearRefs=gearRefs; ovCnt:SetHeight(math.abs(cy)+20)
    end

    local function RefreshHonorPage()
        if not ovHonorRefs.honorVal then return end
        local honor=GetCurrentHonor(); local ap=GetCurrentArenaPoints()
        local marks=GetPvPMarkCounts(); local fmt=BreakUpLargeNumbers or tostring
        ovHonorRefs.honorVal:SetText(string.format("|cffFFD700%s|r",fmt(honor)))
        ovHonorRefs.apVal:SetText(string.format("|cff88FF88%s|r",fmt(ap)))
        ovHonorRefs.resetVal:SetText("|cff00CCFF"..GetDaysToReset().."|r")
        local pct=math.min(1,honor/HONOR_CAP)
        ovHonorRefs.barFill:SetWidth(math.max(1,math.floor(ovHonorRefs.barWidth*pct)))
        ovHonorRefs.barText:SetText(string.format("%s / 75,000  (%d%%)",fmt(honor),math.floor(pct*100)))
        if honor>=70000 then
            ovHonorRefs.capWarn:SetText("|cffFF4444Warning: Near cap — spend before 75k or gains are lost!|r")
            ovHonorRefs.barFill:SetColorTexture(1,0.2,0.2,1)
        elseif honor>=55000 then
            ovHonorRefs.capWarn:SetText("|cffFFAA00Getting full — consider spending soon.|r")
            ovHonorRefs.barFill:SetColorTexture(1,0.7,0.1,1)
        else
            ovHonorRefs.capWarn:SetText(""); ovHonorRefs.barFill:SetColorTexture(0.85,0.75,0.1,1)
        end
        local toFill=math.max(0,HONOR_CAP-honor)
        if toFill==0 then
            ovHonorRefs.planFS:SetText("|cff00FF00Honor capped! Time to spend.|r")
        else
            ovHonorRefs.planFS:SetText(string.format(
                "|cffAAAAAA~%d AV wins to cap|r  |cff666666(or ~%d WSG/AB/EotS)|r",
                math.ceil(toFill/419),math.ceil(toFill/209)))
        end
        ovHonorRefs.mkAV:SetText(string.format("|cffFFD700%d|r",marks.AV or 0))
        ovHonorRefs.mkWSG:SetText(string.format("|cffFFD700%d|r",marks.WSG or 0))
        ovHonorRefs.mkAB:SetText(string.format("|cffFFD700%d|r",marks.AB or 0))
        ovHonorRefs.mkEotS:SetText(string.format("|cffFFD700%d|r",marks.EotS or 0))
        if ovHonorRefs.gearRefs then
            for _,row in ipairs(ovHonorRefs.gearRefs) do
                local gear=row.gear; local honorMet=honor>=gear.honor
                local allMet=true; local mparts={}
                for bg,req in pairs(gear.marks) do
                    local have=marks[bg] or 0; local met=have>=req
                    if not met then allMet=false end
                    mparts[#mparts+1]=string.format("%s|cffAAAAAA/%d %s|r",
                        met and string.format("|cff00FF00%d",have)
                            or  string.format("|cffFF4444%d",have),req,bg)
                end
                table.sort(mparts); row.mkFS:SetText(table.concat(mparts,"  "))
                local hc=honorMet and "00FF00" or "FF4444"
                row.hoFS:SetText(string.format("|cff%s%s|r|cffAAAAAA/%s|r",hc,fmt(honor),fmt(gear.honor)))
                row.rdFS:SetText(honorMet and allMet and "|cff00FF00Ready!|r" or "|cffAAAAAA...|r")
            end
        end
    end

"""
+
    arena_fn
+
    weap_fn
+
    honor_fn
+
"""    -- ================================================================
    -- CC/DR TABLE  (revamped: Quick Reference + Full Breakdown)
    -- ================================================================
    local function BuildDRContent()
        ClearContent()
        local crossRef = BuildDRCrossRef()
        local cy = -4; local PAD = 6

        -- Part 1: Quick Reference — one row per DR category, all sharing spells listed
        local qHdr = ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormal")
        qHdr:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD,cy)
        qHdr:SetText("|cff00CCFFQuick Reference|r  |cffAAAAAA— abilities in the same row share a DR|r")
        cy=cy-17
        local qdiv=ovCnt:CreateTexture(nil,"ARTWORK")
        qdiv:SetSize(OV_RCW,1); qdiv:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",0,cy)
        qdiv:SetColorTexture(0.3,0.3,0.3,0.5); cy=cy-6

        for _,cat in ipairs(DR_CATEGORIES) do
            local entries=crossRef[cat.id]
            local catLbl=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            catLbl:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD,cy)
            catLbl:SetText(string.format("|cff%s%-16s|r",cat.color,cat.name))
            if cat.id=="SILENCE" then
                local nodrFS=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                nodrFS:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD+140,cy)
                nodrFS:SetText("|cffFF4444NO DR in TBC — chain freely|r")
            elseif entries and #entries>0 then
                local spells={}
                for _,e in ipairs(entries) do spells[#spells+1]=e.spell end
                local spFS=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                spFS:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD+140,cy)
                spFS:SetWidth(OV_RCW-PAD-145)
                spFS:SetText("|cffCCCCCC"..table.concat(spells,"  ·  ").."|r")
            else
                local neFS=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                neFS:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD+140,cy)
                neFS:SetText("|cff555555(none)|r")
            end
            cy=cy-14
        end

        cy=cy-6
        local midDiv=ovCnt:CreateTexture(nil,"ARTWORK")
        midDiv:SetSize(OV_RCW,2); midDiv:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",0,cy)
        midDiv:SetColorTexture(0.4,0.35,0.15,0.8); cy=cy-10

        -- Part 2: Full Breakdown per category
        local fHdr=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormal")
        fHdr:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD,cy)
        fHdr:SetText("|cff00CCFFFull Breakdown|r  |cffAAAAAA— sequence: Full > 50% > 25% > immune|r")
        cy=cy-17

        for _,cat in ipairs(DR_CATEGORIES) do
            local entries=crossRef[cat.id]
            local catBG=ovCnt:CreateTexture(nil,"BACKGROUND")
            catBG:SetSize(OV_RCW,16); catBG:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",0,cy)
            local cr=tonumber(cat.color:sub(1,2),16)/255
            local cg=tonumber(cat.color:sub(3,4),16)/255
            local cb=tonumber(cat.color:sub(5,6),16)/255
            catBG:SetColorTexture(cr,cg,cb,0.20)
            local catFS=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormal")
            catFS:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD,cy)
            catFS:SetText(string.format("|cff%s%s|r  |cffAAAAAA%s|r",cat.color,cat.name,cat.desc))
            cy=cy-17
            if not entries or #entries==0 then
                local ne=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                ne:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD+8,cy)
                ne:SetText("|cff555555(none)|r"); cy=cy-14
            else
                for _,e in ipairs(entries) do
                    local ln=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                    ln:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD+8,cy)
                    ln:SetText(string.format("|cffFFD700%-10s|r  |cffFFFFFF%-22s|r  |cffAAAAAA%s|r",
                        e.class,e.spell,e.dur))
                    cy=cy-14
                end
            end
            cy=cy-4
        end

        local noteDiv=ovCnt:CreateTexture(nil,"ARTWORK")
        noteDiv:SetSize(OV_RCW,1); noteDiv:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",0,cy-4)
        noteDiv:SetColorTexture(0.4,0.35,0.25,0.6); cy=cy-14
        local noteHdr=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormal")
        noteHdr:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD,cy)
        noteHdr:SetText("|cff00CCFFKey TBC Rules|r"); cy=cy-16
        local tbcNotes={
            "|cffFFFFFFDR Sequence|r  |cffAAAAAAFull > 50% > 25% > immune  (resets ~18 sec out of combat)|r",
            "|cffFFFFFFBlind|r  |cffAAAAAAshares Fear DR in TBC (differs from later expansions)|r",
            "|cffFFFFFFCyclone|r  |cffAAAAAADRs with itself only in TBC|r",
            "|cffFFFFFFKidney Shot|r  |cffAAAAAAown stun DR, independent of all other stuns|r",
            "|cffFFFFFFSilences|r  |cffFF4444ZERO DR in TBC|r|cffAAAAAA — chain Garrote, Silence, Spell Lock freely|r",
            "|cffFFFFFFDeath Coil|r  |cffAAAAAAHorror category, NOT Fear DR|r",
            "|cffFFFFFFProc Stuns|r  |cffAAAAAA(Mace Spec) separate DR from activated stuns|r",
        }
        for _,note in ipairs(tbcNotes) do
            local nFS=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            nFS:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD+8,cy)
            nFS:SetText(note); cy=cy-14
        end
        ovCnt:SetHeight(math.abs(cy)+20)
    end

    -- ================================================================
    -- HELP  (formerly Info)
    -- ================================================================
    local function BuildInfoContent()
        ClearContent()
        local INFO_SECTIONS={
            {hdr="Overview",body=
                "BeanArena is a PvP utility for WoW TBC Anniversary. Live arena ratings, AP projections, honor tracking, gear cost reference, and CC/DR rules — all in a single window."},
            {hdr="Menu Navigation  (top-left Menu button)",body=
                "Calculator — live ratings, AP calc, rating target\\n"..
                "Honor — current honor, marks, weekly plan, gear checklist\\n"..
                "Arena Gear — S1/S2 armor icons + AP/rating costs  (S1/S2 + class buttons)\\n"..
                "Weapons — all PvP weapons, relics, off-hands  (S1/S2 toggle)\\n"..
                "Honor Gear — S1/S2 honor costs, auto-detects your class\\n"..
                "CC/DR Table — quick reference + full breakdown for all classes\\n"..
                "Help — this guide"},
            {hdr="Arena Point Calculator  ( /ba calc )",body=
                "Enter any rating to simulate AP. Banked AP shown so you can track progress."},
            {hdr="Character Viewer  ( /ba chars )",body=
                "Tracks AP/honor/rating for all your characters. Any character that logs in\\n"..
                "with BeanArena installed will appear in the Viewing dropdown."},
            {hdr="Slash Commands",body=
                "/ba calc [#]    AP for all brackets\\n"..
                "/ba honor [slot] Honor gear cost + your progress\\n"..
                "/ba arena [slot] Arena gear cost + your progress\\n"..
                "/ba dr [class]  CC & DR list for a class\\n"..
                "/ba marks       BG mark counts\\n"..
                "/ba help        All commands"},
            {hdr="Tips",body=
                "BeanArena opens alongside the PvP panel (H key) automatically.\\n"..
                "Minimap: left-click = main window, middle-click = commands.\\n"..
                "/ba calc 1750 checks AP for any rating.\\n"..
                "/ba dr mage lists Mage CC + DR categories.\\n"..
                "Frame position is saved between sessions."},
        }
        local cy=-8; local PAD_L=6
        for _,sec in ipairs(INFO_SECTIONS) do
            local hdrFS=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormal")
            hdrFS:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD_L,cy)
            hdrFS:SetText("|cffFFD700"..sec.hdr.."|r"); cy=cy-18
            for line in (sec.body.."\\n"):gmatch("([^\\n]*)\\n") do
                local bodyFS=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                bodyFS:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD_L+6,cy)
                bodyFS:SetWidth(OV_RCW-PAD_L-10); bodyFS:SetJustifyH("LEFT")
                bodyFS:SetText("|cffCCCCCC"..line.."|r")
                local wrapEst=math.max(1,math.ceil(#line/62))
                cy=cy-(14*wrapEst)
            end
            cy=cy-10
        end
        ovCnt:SetHeight(math.abs(cy)+20)
    end

    -- ================================================================
    -- SwitchPage dispatcher
    -- ================================================================
    SwitchPage = function(name)
        ovSection = name
        local hasSeasons=(name=="Arena Gear" or name=="Weapons" or name=="Honor Gear")
        if hasSeasons then ovS1Btn:Show(); ovS2Btn:Show() else ovS1Btn:Hide(); ovS2Btn:Hide() end
        if name=="Arena Gear" then ovClassBtn:Show() else ovClassBtn:Hide() end
        ovScr:SetVerticalScroll(0)
        if name=="Honor" then
            BuildHonorPage(); RefreshHonorPage()
        elseif name=="Arena Gear" then
            BuildArenaContent()
        elseif name=="Weapons" then
            for _,wlist in ipairs({S1_WEAPONS,S2_WEAPONS}) do
                for _,wep in ipairs(wlist) do
                    if wep.ids then for _,id in ipairs(wep.ids) do GetItemInfo(id) end end
                end
            end
            BuildWeaponsContent()
        elseif name=="Honor Gear" then
            local _,cf=UnitClass("player")
            local cm={WARRIOR="Warrior",PALADIN="Paladin",HUNTER="Hunter",ROGUE="Rogue",
                      PRIEST="Priest",SHAMAN="Shaman",MAGE="Mage",WARLOCK="Warlock",DRUID="Druid"}
            ovClass=cm[cf or ""] or "Warrior"; ovClassBtn:SetText(ovClass.."  v")
            for _,list in ipairs({S1_HONOR_UNIVERSAL,S2_HONOR_UNIVERSAL}) do
                for _,slot in ipairs(list) do
                    for _,item in ipairs(slot.items) do GetItemInfo(item.id) end
                end
            end
            for _,byArmor in ipairs({S1_HONOR_BYARMOR,S2_HONOR_BYARMOR}) do
                for _,armorList in pairs(byArmor) do
                    for _,slot in ipairs(armorList) do
                        for _,item in ipairs(slot.items) do GetItemInfo(item.id) end
                    end
                end
            end
            BuildHonorContent()
        elseif name=="CC/DR Table" then
            BuildDRContent()
        elseif name=="Help" then
            BuildInfoContent()
        end
    end

    -- ── Control button wiring ────────────────────────────────────────────
    ovS1Btn:SetScript("OnClick", function() ovSeason=1; SwitchPage(ovSection) end)
    ovS2Btn:SetScript("OnClick", function() ovSeason=2; SwitchPage(ovSection) end)
    ovClassBtn:SetScript("OnClick", function(self)
        UIDropDownMenu_Initialize(ovClassDD, function()
            for _,cls in ipairs(CLASS_LIST) do
                local info=UIDropDownMenu_CreateInfo()
                info.text=cls; info.value=cls; info.notCheckable=true
                info.func=function()
                    ovClass=cls; ovClassBtn:SetText(cls.."  v")
                    BuildArenaContent(); CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info)
            end
        end,"MENU")
        ToggleDropDownMenu(1,nil,ovClassDD,self,0,-4)
    end)

    BeanArena_OpenRefFrame = function(section)
        if not frame:IsShown() then OpenBeanArena() end
        if section=="Calculator" then
            refOverlay:Hide(); ovSection="Calculator"
        else
            local _,cf=UnitClass("player")
            local cm={WARRIOR="Warrior",PALADIN="Paladin",HUNTER="Hunter",ROGUE="Rogue",
                      PRIEST="Priest",SHAMAN="Shaman",MAGE="Mage",WARLOCK="Warlock",DRUID="Druid"}
            ovClass=cm[cf or ""] or "Warrior"; ovClassBtn:SetText(ovClass.."  v")
            SwitchPage(section); refOverlay:Show()
        end
    end

    BeanArena_RefreshRefFrame = function()
        if refOverlay:IsShown() then
            if ovSection=="Honor" then RefreshHonorPage()
            else SwitchPage(ovSection) end
        end
    end
end

"""
)

# Replace old refFrame block with new one
content = slice_replace(content, RS_MARKER, SC_MARKER, NEW_BLOCK, "refFrame-block")
print(f"op8: replaced refFrame block with embedded overlay ({len(NEW_BLOCK)} chars)")

# ── 9. Update GET_ITEM_INFO_RECEIVED event handler ────────────────────────
OLD_ITEM_EV = (
    "    elseif event == \"GET_ITEM_INFO_RECEIVED\" then\n"
    "        -- Flag a rebuild so icons that loaded after a popup opened get shown.\n"
    "        -- The OnUpdate ticker consumes the flag and does a single rebuild.\n"
    "        if refFrame and refFrame:IsShown() then\n"
    "            itemRefreshPending = true\n"
    "        end\n"
    "    end\n"
    "end)")
NEW_ITEM_EV = (
    "    elseif event == \"GET_ITEM_INFO_RECEIVED\" then\n"
    "        -- Flag a rebuild so icons finish loading before the overlay rebuilds.\n"
    "        itemRefreshPending = true\n"
    "    end\n"
    "end)")
content = rep1(content, OLD_ITEM_EV, NEW_ITEM_EV, "GET_ITEM_INFO_RECEIVED")
print("op9: updated GET_ITEM_INFO_RECEIVED")

# ── 10. Update OnUpdate ticker ────────────────────────────────────────────
OLD_TICK = ("    if itemRefreshPending then\n"
            "        itemRefreshPending = false\n"
            "        if refFrame:IsShown() then BeanArena_RefreshRefFrame() end\n"
            "    end")
NEW_TICK = ("    if itemRefreshPending then\n"
            "        itemRefreshPending = false\n"
            "        if BeanArena_RefreshRefFrame then BeanArena_RefreshRefFrame() end\n"
            "    end")
content = rep1(content, OLD_TICK, NEW_TICK, "ticker")
print("op10: updated ticker")

# ── 11. Update slash commands ─────────────────────────────────────────────
# /ba honor (no arg): was Toggle(honorFrame, frame)
content = rep1(content,
    '        if args == "" then\n'
    '            Toggle(honorFrame, frame)\n',
    '        if args == "" then\n'
    '            OpenBeanArena(); BeanArena_OpenRefFrame("Honor")\n',
    "slash-honor")

# /ba arena (no arg): remove second arg from BeanArena_OpenRefFrame
content = rep1(content,
    '            BeanArena_OpenRefFrame("Arena Gear", frame)\n',
    '            BeanArena_OpenRefFrame("Arena Gear")\n',
    "slash-arena")

# /ba dr (no arg)
content = rep1(content,
    '            BeanArena_OpenRefFrame("CC/DR Table", frame)\n',
    '            BeanArena_OpenRefFrame("CC/DR Table")\n',
    "slash-dr")

# /ba gear / /ba hgear
content = rep1(content,
    '        BeanArena_OpenRefFrame("Arena Gear", frame)\n'
    '    elseif cmd == "hgear" or cmd == "honorgear" then\n'
    '        BeanArena_OpenRefFrame("Honor Gear", frame)\n'
    '    elseif cmd == "weapons" then\n'
    '        BeanArena_OpenRefFrame("Weapons", frame)\n',
    '        BeanArena_OpenRefFrame("Arena Gear")\n'
    '    elseif cmd == "hgear" or cmd == "honorgear" then\n'
    '        BeanArena_OpenRefFrame("Honor Gear")\n'
    '    elseif cmd == "weapons" then\n'
    '        BeanArena_OpenRefFrame("Weapons")\n',
    "slash-gear-hgear-weapons")

# /ba info → Help section
content = rep1(content,
    '        BeanArena_OpenRefFrame("Info", frame)\n',
    '        BeanArena_OpenRefFrame("Help")\n',
    "slash-info")
print("op11: updated slash commands")

# ── 12. Bump version numbers ──────────────────────────────────────────────
content = rep1(content, "-- CURRENT: v0.3.6", "-- CURRENT: v0.3.7", "version-current")
content = rep1(content,
    "-- v0.3.6 | 2026-05-21 | Unified reference frame with section dropdown",
    ("-- v0.3.6 | 2026-05-21 | Unified reference frame with section dropdown\n"
     "-- v0.3.7 | 2026-05-21 | Single-window with Menu dropdown; embedded overlay;\n"
     "--         |             CC/DR table revamp (Quick Ref + Full Breakdown); Honor page"),
    "version-history")
content = rep1(content,
    "-- END OF FILE | BeanArena v0.3.6 | 2026-05-21",
    "-- END OF FILE | BeanArena v0.3.7 | 2026-05-21",
    "version-eof")
# Also update loaded message
content = rep1(content,
    'print("|cffFFD700[BeanArena]|r v0.3.6 loaded! /ba help")',
    'print("|cffFFD700[BeanArena]|r v0.3.7 loaded! /ba help")',
    "version-loaded")
print("op12: bumped versions")

# ── Write output ──────────────────────────────────────────────────────────
with open(PATH, "w", encoding="utf-8") as f:
    f.write(content)
print(f"Done. {len(content)} chars (delta {len(content)-130000:+d} from baseline)")
