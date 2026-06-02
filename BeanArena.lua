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
-- v0.3.0 | 2026-03-17 | Full command set: /ba calc, /ba honor [slot], /ba arena [slot], /ba dr [class]
--         |             Minimap: standardized frame, BA text icon, addon-compatible
--         |             Notes: robust persistence (nf.initialized), char-aware reload
-- v0.3.1 | 2026-03-28 | Remove notes buttons, fix ApplyCharView nil crash, fix minimap border
-- v0.3.2 | 2026-05-19 | S2 honor gear table (Veteran's only: Neck/Ring/Bracers/Belt/Boots)
--         |             Rating Target calculator (enter AP goal, shows needed rating per bracket)
-- v0.3.3 | 2026-05-20 | Arena Gear & Honor Gear popups: class dropdown + season toggle (S1/S2)
--         |             Per-class weapon/relic filtering; Veteran's & General's off-pieces by armor type
--         |             Item tooltip on hover for all weapons, off-hands, relics, and honor pieces
-- v0.3.4 | 2026-05-20 | Dedicated Weapons & Relics popup — all variants, one icon per item ID
--         |             Fixes missing relics (3 icons per type, not 1); Weapons button on main frame
--         |             Arena Gear popup now shows armor icon grid with per-class set variants
-- v0.3.5 | 2026-05-20 | Arena Gear: real item icons + full WoW item tooltips (SetHyperlink)
--         |             5-slot icon grid (Head/Chest/Legs/Gloves/Shoulders) x N variant cols
--         |             All 17 S1 + 17 S2 set item IDs from AtlasLootClassic/Data/ItemSet.lua
--         |             Shaman Earthshaker variant added to S1 & S2; Unicode chars fixed
-- v0.3.6 | 2026-05-21 | Unified reference frame with section dropdown
-- v0.3.7 | 2026-05-21 | Single-window with Menu dropdown; embedded overlay;
--         |             CC/DR table revamp (Quick Ref + Full Breakdown); Honor page
--         |             Arena Gear / Weapons / Honor Gear / CC/DR / Info in one window
--         |             Honor Gear auto-detects player class (no class switcher)
-- v0.3.8 | 2026-05-22 | Fix stack overflow: BeanArena_RefreshRefFrame no longer calls
--         |             SwitchPage from 5-second ticker (only RefreshHonorPage); add
--         |             BeanArena_RebuildRefPage for one-shot item-icon refresh
--         |             Fix nil crash: add missing SLOT_DEFS, EQUIP_TO_SLOT, IC_SZ,
--         |             IC_CELL, SL_W constants required by BuildArenaContent
-- v1.0    | 2026-05-22 | Public release — CurseForge
-- v1.1    | 2026-06-01 | My Gear: renamed from Char Plan; paper-doll layout (18px icons),
--         |             smart PvP indicators (ReadyCheck textures), center stats panel,
--         |             built-in char dropdown in the My Gear panel
-- v1.2    | 2026-06-01 | Team BGs: party honor+marks sharing via addon messages,
--         |             Team BGs menu page, /ba bgshare, /ba bgprint
-- CURRENT: v1.2
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

-- @project-version@ is replaced by BigWigs Packager at release time.
-- Falls back to GetAddOnMetadata (if available) or "dev" for local runs.
local BA_VERSION = (function()
    local v = "@project-version@"
    if v:sub(1, 1) ~= "@" then return v end
    return (GetAddOnMetadata and GetAddOnMetadata("BeanArena", "Version")) or "dev"
end)()
local BA_MSG_PREFIX    = "BeanArena"
local versionWarnShown = false

-- Character identity (populated on PLAYER_LOGIN)
local CHAR_NAME, CHAR_REALM

local defaults = {
    manual2v2    = 0,
    manual3v3    = 0,
    manual5v5    = 0,
    targetAP     = 0,
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

-- Forward-declared so SnapshotCharData/WriteAltSnapshot (defined before the
-- bodies below) capture them as upvalues rather than nil global lookups.
local GetLiveRatings, GetCurrentArenaPoints, GetCurrentHonor

-- Snapshot current char data into the cross-char roster
local function SnapshotCharData()
    if not CHAR_NAME or not CHAR_REALM then return end
    BeanArenaDB.chars = BeanArenaDB.chars or {}
    local key = CHAR_NAME .. "-" .. CHAR_REALM
    local r2,r3,r5,g2,g3,g5 = GetLiveRatings()
    local marks = GetPvPMarkCounts and GetPvPMarkCounts() or {}
    -- Save equipped gear links so My Gear can show them when viewing this alt
    local gearLinks = {}
    if GetInventoryItemLink then
        for slotID = 1, 18 do
            local link = GetInventoryItemLink("player", slotID)
            if link then gearLinks[slotID] = link end
        end
    end
    local snap = {
        name         = CHAR_NAME,
        realm        = CHAR_REALM,
        arenaPoints  = GetCurrentArenaPoints(),
        honor        = GetCurrentHonor(),
        marks        = marks,
        gearLinks    = gearLinks,
        r2=r2, r3=r3, r5=r5, g2=g2, g3=g3, g5=g5,
        timestamp    = time(),
    }
    BeanArenaDB.chars[key] = snap
end

-- Write a fresh alt snapshot into BeanArenaDB.altData for the current character.
-- Called on PLAYER_ENTERING_WORLD (delayed 3s so ratings are populated).
local function WriteAltSnapshot()
    if not CHAR_NAME or not CHAR_REALM then return end
    BeanArenaDB.altData = BeanArenaDB.altData or {}
    local key = CHAR_NAME .. "-" .. CHAR_REALM
    local r2,r3,r5,g2,g3,g5 = GetLiveRatings()
    local _, classFile = UnitClass("player")
    BeanArenaDB.altData[key] = {
        name           = CHAR_NAME,
        realm          = CHAR_REALM,
        class          = classFile or "WARRIOR",
        arenaPoints    = GetCurrentArenaPoints(),
        rating2v2      = r2,
        rating3v3      = r3,
        personalRating = math.max(r2, r3, r5),
        honorPoints    = GetCurrentHonor(),
        lastSeen       = time(),
    }
end

-- Returns all alt snapshots sorted by lastSeen descending (most recent first).
function BeanArena_GetAltData()
    local out = {}
    for _, snap in pairs(BeanArenaDB.altData or {}) do
        out[#out+1] = snap
    end
    table.sort(out, function(a, b)
        return (a.lastSeen or 0) > (b.lastSeen or 0)
    end)
    return out
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

-- Inverse of CalcBracketPoints: given a target AP and bracket, returns the rating needed.
-- Returns nil if the AP is above the bracket's theoretical maximum (~2478 for 5v5).
-- Returns 0 if the AP is so low any rating achieves it.
local function CalcRatingForPoints(targetAP, bracket)
    local mult = (bracket == "2v2") and 0.76 or (bracket == "3v3") and 0.88 or 1.0
    local base = targetAP / mult
    local inner = base / 1.5 - 475
    if inner <= 0 then return 0 end
    if inner >= 1176.94 then return nil end
    local x = 1176.94 / inner - 1
    if x <= 0 then return nil end
    local rating = -math.log(x / 2500000) / 0.009
    return math.max(0, math.ceil(rating))
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

-- Season 2 (Veteran's) honor off-pieces only.
-- Main armor slots (helm/chest/legs/shoulders/gloves) come from the Merciless Gladiator arena set.
-- Item IDs from AtlasLoot S2 data: Neck=33066, Ring=33057, Bracers/Belt/Boots per armor type (32xxx).
-- Prices need in-game vendor verification — kept from S1 as placeholder until confirmed.
local HONOR_GEAR_FULL = {
    { slot="Neck",    honor=12695, marks={ EotS=5  } },
    { slot="Ring",    honor=12695, marks={ AV=5    } },
    { slot="Bracers", honor=9785,  marks={ WSG=10  } },
    { slot="Belt",    honor=14815, marks={ AB=10   } },
    { slot="Boots",   honor=14815, marks={ EotS=20 } },
}

-- ============================================================
-- PVP GEAR ITEM DATABASE  (item IDs confirmed from AtlasLoot TBC data)
-- ============================================================

-- Class > armor type (for honor off-piece filtering)
local CLASS_ARMOR_TYPE = {
    Druid="Leather", Hunter="Mail",   Mage="Cloth",
    Paladin="Plate", Priest="Cloth",  Rogue="Leather",
    Shaman="Mail",   Warlock="Cloth", Warrior="Plate",
}
local CLASS_LIST = {"Druid","Hunter","Mage","Paladin","Priest","Rogue","Shaman","Warlock","Warrior"}

-- Arena set variant names per class per season.
-- Each class lists all named set variants (spec-specific); 5 item icons shown per variant.
-- Source: AtlasLootClassic/Data/ItemSet.lua (all item IDs verified).
local CLASS_SETS_S1 = {
    Warrior  = {"Gladiator's Plate"},
    Paladin  = {"Gladiator's Redemption", "Gladiator's Vindication", "Gladiator's Aegis"},
    Druid    = {"Gladiator's Kodohide", "Gladiator's Dragonhide", "Gladiator's Wildhide"},
    Hunter   = {"Gladiator's Chain"},
    Mage     = {"Gladiator's Silk"},
    Priest   = {"Gladiator's Mooncloth", "Gladiator's Satin"},
    Rogue    = {"Gladiator's Leather"},
    Shaman   = {"Gladiator's Mail", "Gladiator's Linked", "Gladiator's Earthshaker"},
    Warlock  = {"Gladiator's Dreadweave", "Gladiator's Felweave"},
}
local CLASS_SETS_S2 = {
    Warrior  = {"Merciless Gladiator's Plate"},
    Paladin  = {"Merciless Gladiator's Redemption", "Merciless Gladiator's Vindication", "Merciless Gladiator's Aegis"},
    Druid    = {"Merciless Gladiator's Kodohide", "Merciless Gladiator's Dragonhide", "Merciless Gladiator's Wildhide"},
    Hunter   = {"Merciless Gladiator's Chain"},
    Mage     = {"Merciless Gladiator's Silk"},
    Priest   = {"Merciless Gladiator's Mooncloth", "Merciless Gladiator's Satin"},
    Rogue    = {"Merciless Gladiator's Leather"},
    Shaman   = {"Merciless Gladiator's Mail", "Merciless Gladiator's Linked", "Merciless Gladiator's Earthshaker"},
    Warlock  = {"Merciless Gladiator's Dreadweave", "Merciless Gladiator's Felweave"},
}

-- Full item ID list per arena set variant name.
-- 5 item IDs per set sourced from AtlasLootClassic/Data/ItemSet.lua (all verified).
-- Items are NOT in slot order; slot is detected at runtime via GetItemInfo equipLoc.
local ARMOR_SET_IDS = {
    -- Season 1 (Gladiator's) ─────────────────────────────────────────────────
    ["Gladiator's Plate"]        = {24545,24546,24544,24549,24547},  -- set 567 Warrior
    ["Gladiator's Dreadweave"]   = {24553,24554,24552,24556,24555},  -- set 568 Warlock
    ["Gladiator's Leather"]      = {25830,25832,25831,25834,25833},  -- set 577 Rogue
    ["Gladiator's Earthshaker"]  = {25998,25999,25997,26000,26001},  -- set 578 Shaman Enh
    ["Gladiator's Silk"]         = {25855,25854,25856,25857,25858},  -- set 579 Mage
    ["Gladiator's Mail"]         = {27471,27473,27469,27470,27472},  -- set 580 Shaman Heal
    ["Gladiator's Satin"]        = {27708,27710,27711,27707,27709},  -- set 581 Priest Shadow
    ["Gladiator's Aegis"]        = {27704,27706,27702,27703,27705},  -- set 582 Paladin Prot
    ["Gladiator's Vindication"]  = {27881,27883,27879,27880,27882},  -- set 583 Paladin Ret
    ["Gladiator's Wildhide"]     = {28127,28129,28130,28126,28128},  -- set 584 Druid Feral
    ["Gladiator's Dragonhide"]   = {28137,28139,28140,28136,28138},  -- set 585 Druid Balance
    ["Gladiator's Chain"]        = {28331,28333,28334,28335,28332},  -- set 586 Hunter
    ["Gladiator's Felweave"]     = {30187,30186,30200,30188,30201},  -- set 615 Warlock
    ["Gladiator's Kodohide"]     = {31376,31378,31379,31375,31377},  -- set 685 Druid Heal
    ["Gladiator's Linked"]       = {31400,31407,31396,31397,31406},  -- set 686 Shaman Ele
    ["Gladiator's Mooncloth"]    = {31410,31412,31413,31409,31411},  -- set 687 Priest Heal
    ["Gladiator's Redemption"]   = {31616,31619,31613,31614,31618},  -- set 690 Paladin Heal
    -- Season 2 (Merciless Gladiator's) ────────────────────────────────────────
    ["Merciless Gladiator's Aegis"]        = {31997,31996,31992,31993,31995},  -- set 700 Paladin Prot
    ["Merciless Gladiator's Plate"]        = {30488,30490,30486,30487,30489},  -- set 701 Warrior
    ["Merciless Gladiator's Dreadweave"]   = {31974,31976,31977,31973,31975},  -- set 702 Warlock
    ["Merciless Gladiator's Earthshaker"]  = {32006,32008,32004,32005,32007},  -- set 703 Shaman Enh
    ["Merciless Gladiator's Felweave"]     = {31980,31979,31982,31981,31983},  -- set 704 Warlock
    ["Merciless Gladiator's Mooncloth"]    = {32016,32018,32019,32015,32017},  -- set 705 Priest Heal
    ["Merciless Gladiator's Chain"]        = {31962,31964,31960,31961,31963},  -- set 706 Hunter
    ["Merciless Gladiator's Satin"]        = {32035,32037,32038,32034,32036},  -- set 707 Priest Shadow
    ["Merciless Gladiator's Redemption"]   = {32022,32024,32020,32021,32023},  -- set 708 Paladin Heal
    ["Merciless Gladiator's Kodohide"]     = {31988,31990,31991,31987,31989},  -- set 709 Druid Heal
    ["Merciless Gladiator's Silk"]         = {32048,32047,32050,32049,32051},  -- set 710 Mage
    ["Merciless Gladiator's Wildhide"]     = {31968,31971,31972,31967,31969},  -- set 711 Druid Feral
    ["Merciless Gladiator's Mail"]         = {32011,32013,32009,32010,32012},  -- set 712 Shaman Heal
    ["Merciless Gladiator's Leather"]      = {31999,32001,32002,31998,32000},  -- set 713 Rogue
    ["Merciless Gladiator's Vindication"]  = {32041,32043,32039,32040,32042},  -- set 714 Paladin Ret
    ["Merciless Gladiator's Linked"]       = {32031,32033,32029,32030,32032},  -- set 715 Shaman Ele
    ["Merciless Gladiator's Dragonhide"]   = {32057,32059,32060,32056,32058},  -- set 716 Druid Balance
}

-- Weapon slot keys each class can equip (used to filter arena weapon list)
local CLASS_WEAPONS = {
    Warrior = {["1H-Sword"]=1,["1H-Axe"]=1,["1H-Mace"]=1,["1H-Fist"]=1,
               ["2H-Sword"]=1,["2H-Axe"]=1,["2H-Mace"]=1,
               ["Shield"]=1,["Thrown"]=1},
    Paladin = {["1H-Mace"]=1,["1H-Sword"]=1,["1H-Axe"]=1,["1H-MaceHeal"]=1,
               ["2H-Mace"]=1,["2H-Sword"]=1,["2H-Axe"]=1,
               ["Shield"]=1,["Libram"]=1},
    Druid   = {["2H-Polearm"]=1,["2H-Staff"]=1,["2H-StaffFeral"]=1,
               ["1H-MaceHeal"]=1,["Off-Tome"]=1,["Idol"]=1},
    Hunter  = {["Crossbow"]=1,["Thrown"]=1,["1H-Sword"]=1,["1H-Axe"]=1,
               ["1H-Fist"]=1,["2H-Sword"]=1,["2H-Axe"]=1,["2H-Polearm"]=1},
    Mage    = {["1H-SwordCaster"]=1,["2H-Staff"]=1,["Wand"]=1,["Off-Orb"]=1},
    Priest  = {["1H-MaceHeal"]=1,["2H-Staff"]=1,["Wand"]=1,["Off-Tome"]=1},
    Rogue   = {["1H-Dagger"]=1,["1H-Sword"]=1,["1H-Mace"]=1,["1H-Fist"]=1,
               ["1H-Axe"]=1,["Thrown"]=1},
    Shaman  = {["1H-Mace"]=1,["1H-Axe"]=1,["1H-Fist"]=1,
               ["2H-Mace"]=1,["2H-Axe"]=1,
               ["Shield"]=1,["Totem"]=1},
    Warlock = {["1H-SwordCaster"]=1,["2H-Staff"]=1,["Wand"]=1,["Off-Orb"]=1},
}

-- Season 2 (Merciless Gladiator's) weapons/offhands/relics with confirmed item IDs
-- ids = list of item variants; first is shown in tooltip header, others listed below
local S2_WEAPONS = {
    {slot="1H Dagger",         key="1H-Dagger",      ids={32044,32046},       ap=2175, rating=1700},
    {slot="1H Sword (Phys)",   key="1H-Sword",       ids={32052,32027},       ap=2175, rating=1700},
    {slot="1H Mace (Phys)",    key="1H-Mace",        ids={32026,31958},       ap=2175, rating=1700},
    {slot="1H Axe",            key="1H-Axe",         ids={31965,31985},       ap=2175, rating=1700},
    {slot="1H Fist Weapon",    key="1H-Fist",        ids={32028,32003},       ap=2175, rating=1700},
    {slot="1H Caster Sword",   key="1H-SwordCaster", ids={32053},             ap=2175, rating=1700},
    {slot="1H Mace (Heal)",    key="1H-MaceHeal",    ids={32963,32964},       ap=2610, rating=1700},
    {slot="2H Sword",          key="2H-Sword",       ids={31984},             ap=3110, rating=1700},
    {slot="2H Axe",            key="2H-Axe",         ids={31966},             ap=3110, rating=1700},
    {slot="2H Mace",           key="2H-Mace",        ids={32014},             ap=3110, rating=1700},
    {slot="2H Polearm",        key="2H-Polearm",     ids={32025},             ap=3110, rating=1700},
    {slot="2H Staff (Caster)", key="2H-Staff",       ids={32055},             ap=3110, rating=1700},
    {slot="2H Staff (Feral)",  key="2H-StaffFeral",  ids={31959},             ap=3110, rating=1700},
    {slot="Crossbow",          key="Crossbow",       ids={31986},             ap=3110, rating=1700},
    {slot="Thrown",            key="Thrown",         ids={32054},             ap=830,  rating=1700},
    {slot="Wand",              key="Wand",           ids={32962},             ap=830,  rating=1700},
    {slot="Shield (Tank/Heal)",key="Shield",         ids={32045},             ap=1550, rating=1700},
    {slot="Shield (DPS/Alt)",  key="Shield",         ids={33309,33313},       ap=1550, rating=1700},
    {slot="Off-hand Tome",     key="Off-Tome",       ids={31978},             ap=930,  rating=1700},
    {slot="Off-hand Orb",      key="Off-Orb",        ids={32961},             ap=930,  rating=1700},
    {slot="Relic — Idol",      key="Idol",           ids={33943,33946,33076}, ap=930,  rating=0   },
    {slot="Relic — Libram",    key="Libram",         ids={33077,33937,33949}, ap=930,  rating=0   },
    {slot="Relic — Totem",     key="Totem",          ids={33078,33952,33940}, ap=930,  rating=0   },
}

-- Season 1 (Gladiator's) weapons/offhands/relics with confirmed item IDs
local S1_WEAPONS = {
    {slot="1H Dagger",         key="1H-Dagger",      ids={28312,28310},       ap=1875, rating=1500},
    {slot="1H Sword (Phys)",   key="1H-Sword",       ids={28295,28307},       ap=1875, rating=1500},
    {slot="1H Mace (Phys)",    key="1H-Mace",        ids={28305,28302},       ap=1875, rating=1500},
    {slot="1H Axe",            key="1H-Axe",         ids={28308,28309},       ap=1875, rating=1500},
    {slot="1H Fist Weapon",    key="1H-Fist",        ids={28313,28314},       ap=1875, rating=1500},
    {slot="1H Caster Sword",   key="1H-SwordCaster", ids={28297},             ap=1875, rating=1500},
    {slot="1H Mace (Heal)",    key="1H-MaceHeal",    ids={32450,32451},       ap=2250, rating=1500},
    {slot="2H Sword",          key="2H-Sword",       ids={24550},             ap=2625, rating=1500},
    {slot="2H Axe",            key="2H-Axe",         ids={28298},             ap=2625, rating=1500},
    {slot="2H Mace",           key="2H-Mace",        ids={28476},             ap=2625, rating=1500},
    {slot="2H Polearm",        key="2H-Polearm",     ids={28300},             ap=2625, rating=1500},
    {slot="2H Staff (Caster)", key="2H-Staff",       ids={24557},             ap=2625, rating=1500},
    {slot="2H Staff (Feral)",  key="2H-StaffFeral",  ids={28299},             ap=2625, rating=1500},
    {slot="Crossbow",          key="Crossbow",       ids={28294},             ap=2625, rating=1500},
    {slot="Thrown",            key="Thrown",         ids={28319},             ap=700,  rating=1500},
    {slot="Wand",              key="Wand",           ids={28320},             ap=700,  rating=1500},
    {slot="Shield",            key="Shield",         ids={28358},             ap=1375, rating=1500},
    {slot="Off-hand Tome",     key="Off-Tome",       ids={28346},             ap=875,  rating=1500},
    {slot="Off-hand Orb",      key="Off-Orb",        ids={32452},             ap=875,  rating=1500},
    {slot="Relic — Idol",      key="Idol",           ids={33942,33945,28355}, ap=875,  rating=0   },
    {slot="Relic — Libram",    key="Libram",         ids={28356,33936,33948}, ap=875,  rating=0   },
    {slot="Relic — Totem",     key="Totem",          ids={28357,33951,33939}, ap=875,  rating=0   },
}

-- S2 Veteran's honor off-pieces by armor type: { id, name, honor, marks }
-- Neck/Ring universal; Bracers/Belt/Boots per armor type (multiple style variants listed)
local S2_HONOR_UNIVERSAL = {
    { slot="Neck", items={
        {id=33066,name="Veteran's Pendant of Triumph"},
        {id=33068,name="Veteran's Pendant of Salvation"},
        {id=33065,name="Veteran's Pendant of Dominance"},
        {id=33067,name="Veteran's Pendant of Conquest"},
    }, honor=12695, marks={EotS=5} },
    { slot="Ring", items={
        {id=33057,name="Veteran's Band of Triumph"},
        {id=33064,name="Veteran's Band of Salvation"},
        {id=33056,name="Veteran's Band of Dominance"},
    }, honor=12695, marks={AV=5} },
}
local S2_HONOR_BYARMOR = {
    Cloth = {
        { slot="Bracers", honor=9785,  marks={WSG=10}, items={
            {id=32820,name="Veteran's Silk Cuffs"},
            {id=32811,name="Veteran's Dreadweave Cuffs"},
            {id=32980,name="Veteran's Mooncloth Cuffs"},
        }},
        { slot="Belt", honor=14815, marks={AB=10}, items={
            {id=32807,name="Veteran's Silk Belt"},
            {id=32799,name="Veteran's Dreadweave Belt"},
            {id=32979,name="Veteran's Mooncloth Belt"},
        }},
        { slot="Boots", honor=14815, marks={EotS=20}, items={
            {id=32795,name="Veteran's Silk Footguards"},
            {id=32787,name="Veteran's Dreadweave Stalkers"},
            {id=32981,name="Veteran's Mooncloth Slippers"},
        }},
    },
    Leather = {
        { slot="Bracers", honor=9785,  marks={WSG=10}, items={
            {id=32810,name="Veteran's Dragonhide Bracers"},
            {id=32814,name="Veteran's Leather Bracers"},
            {id=32812,name="Veteran's Kodohide Bracers"},
            {id=32821,name="Veteran's Wyrmhide Bracers"},
        }},
        { slot="Belt", honor=14815, marks={AB=10}, items={
            {id=32798,name="Veteran's Dragonhide Belt"},
            {id=32802,name="Veteran's Leather Belt"},
            {id=32800,name="Veteran's Kodohide Belt"},
            {id=32808,name="Veteran's Wyrmhide Belt"},
        }},
        { slot="Boots", honor=14815, marks={EotS=20}, items={
            {id=32786,name="Veteran's Dragonhide Boots"},
            {id=32790,name="Veteran's Leather Boots"},
            {id=32788,name="Veteran's Kodohide Boots"},
            {id=32796,name="Veteran's Wyrmhide Boots"},
        }},
    },
    Mail = {
        { slot="Bracers", honor=9785,  marks={WSG=10}, items={
            {id=32997,name="Veteran's Ringmail Bracers"},
            {id=32817,name="Veteran's Mail Bracers"},
            {id=32816,name="Veteran's Linked Bracers"},
            {id=32809,name="Veteran's Chain Bracers"},
        }},
        { slot="Belt", honor=14815, marks={AB=10}, items={
            {id=32998,name="Veteran's Ringmail Girdle"},
            {id=32804,name="Veteran's Mail Girdle"},
            {id=32803,name="Veteran's Linked Girdle"},
            {id=32797,name="Veteran's Chain Girdle"},
        }},
        { slot="Boots", honor=14815, marks={EotS=20}, items={
            {id=32999,name="Veteran's Ringmail Sabatons"},
            {id=32792,name="Veteran's Mail Sabatons"},
            {id=32791,name="Veteran's Linked Sabatons"},
            {id=32785,name="Veteran's Chain Sabatons"},
        }},
    },
    Plate = {
        { slot="Bracers", honor=9785,  marks={WSG=10}, items={
            {id=32819,name="Veteran's Scaled Bracers"},
            {id=32818,name="Veteran's Plate Bracers"},
            {id=32989,name="Veteran's Ornamented Bracers"},
            {id=32813,name="Veteran's Lamellar Bracers"},
        }},
        { slot="Belt", honor=14815, marks={AB=10}, items={
            {id=32806,name="Veteran's Scaled Belt"},
            {id=32805,name="Veteran's Plate Belt"},
            {id=32988,name="Veteran's Ornamented Belt"},
            {id=32801,name="Veteran's Lamellar Belt"},
        }},
        { slot="Boots", honor=14815, marks={EotS=20}, items={
            {id=32794,name="Veteran's Scaled Greaves"},
            {id=32793,name="Veteran's Plate Greaves"},
            {id=32990,name="Veteran's Ornamented Greaves"},
            {id=32789,name="Veteran's Lamellar Greaves"},
        }},
    },
}

-- S1 General's/Marshal's honor off-pieces (faction variants both listed)
local S1_HONOR_UNIVERSAL = {
    { slot="Neck", items={
        {id=28244,name="Pendant of Triumph"},{id=28245,name="Pendant of Dominance"},
    }, honor=11650, marks={} },
    { slot="Ring", items={
        {id=28246,name="Band of Triumph"},{id=28247,name="Band of Dominance"},
    }, honor=11650, marks={} },
}
local S1_HONOR_BYARMOR = {
    Cloth = {
        { slot="Bracers", honor=8910, marks={WSG=10}, items={
            {id=29002,name="Marshal's Silk Cuffs"},{id=28411,name="General's Silk Cuffs"},
            {id=28981,name="Marshal's Dreadweave Cuffs"},{id=28405,name="General's Dreadweave Cuffs"},
            {id=32977,name="Marshal's Mooncloth Cuffs"},{id=32973,name="General's Mooncloth Cuffs"},
        }},
        { slot="Belt", honor=13310, marks={AB=10}, items={
            {id=29001,name="Marshal's Silk Belt"},{id=28409,name="General's Silk Belt"},
            {id=28980,name="Marshal's Dreadweave Belt"},{id=28404,name="General's Dreadweave Belt"},
            {id=32976,name="Marshal's Mooncloth Belt"},{id=32974,name="General's Mooncloth Belt"},
        }},
        { slot="Boots", honor=13310, marks={EotS=20}, items={
            {id=29003,name="Marshal's Silk Footguards"},{id=28410,name="General's Silk Footguards"},
            {id=28982,name="Marshal's Dreadweave Stalkers"},{id=28402,name="General's Dreadweave Stalkers"},
            {id=32978,name="Marshal's Mooncloth Slippers"},{id=32975,name="General's Mooncloth Slippers"},
        }},
    },
    Leather = {
        { slot="Bracers", honor=8910, marks={WSG=10}, items={
            {id=28978,name="Marshal's Dragonhide Bracers"},{id=28445,name="General's Dragonhide Bracers"},
            {id=28988,name="Marshal's Leather Bracers"},{id=28424,name="General's Leather Bracers"},
            {id=31599,name="Marshal's Kodohide Bracers"},{id=31598,name="General's Kodohide Bracers"},
            {id=29006,name="Marshal's Wyrmhide Bracers"},{id=28448,name="General's Wyrmhide Bracers"},
        }},
        { slot="Belt", honor=13310, marks={AB=10}, items={
            {id=28976,name="Marshal's Dragonhide Belt"},{id=28443,name="General's Dragonhide Belt"},
            {id=28986,name="Marshal's Leather Belt"},{id=28423,name="General's Leather Belt"},
            {id=31596,name="Marshal's Kodohide Belt"},{id=31594,name="General's Kodohide Belt"},
            {id=29004,name="Marshal's Wyrmhide Belt"},{id=28446,name="General's Wyrmhide Belt"},
        }},
        { slot="Boots", honor=13310, marks={EotS=20}, items={
            {id=28977,name="Marshal's Dragonhide Boots"},{id=28444,name="General's Dragonhide Boots"},
            {id=28987,name="Marshal's Leather Boots"},{id=28422,name="General's Leather Boots"},
            {id=31597,name="Marshal's Kodohide Boots"},{id=31595,name="General's Kodohide Boots"},
            {id=29005,name="Marshal's Wyrmhide Boots"},{id=28447,name="General's Wyrmhide Boots"},
        }},
    },
    Mail = {
        { slot="Bracers", honor=8910, marks={WSG=10}, items={
            {id=32994,name="Marshal's Ringmail Bracers"},{id=32991,name="General's Ringmail Bracers"},
            {id=28992,name="Marshal's Mail Bracers"},{id=28638,name="General's Mail Bracers"},
            {id=28989,name="Marshal's Linked Bracers"},{id=28605,name="General's Linked Bracers"},
            {id=28973,name="Marshal's Chain Bracers"},{id=28451,name="General's Chain Bracers"},
        }},
        { slot="Belt", honor=13310, marks={AB=10}, items={
            {id=32995,name="Marshal's Ringmail Girdle"},{id=32992,name="General's Ringmail Girdle"},
            {id=28993,name="Marshal's Mail Girdle"},{id=28639,name="General's Mail Girdle"},
            {id=28990,name="Marshal's Linked Girdle"},{id=28629,name="General's Linked Girdle"},
            {id=28974,name="Marshal's Chain Girdle"},{id=28450,name="General's Chain Girdle"},
        }},
        { slot="Boots", honor=13310, marks={EotS=20}, items={
            {id=32996,name="Marshal's Ringmail Sabatons"},{id=32993,name="General's Ringmail Sabatons"},
            {id=28994,name="Marshal's Mail Sabatons"},{id=28640,name="General's Mail Sabatons"},
            {id=28991,name="Marshal's Linked Sabatons"},{id=28630,name="General's Linked Sabatons"},
            {id=28975,name="Marshal's Chain Sabatons"},{id=28449,name="General's Chain Sabatons"},
        }},
    },
    Plate = {
        { slot="Bracers", honor=8910, marks={WSG=10}, items={
            {id=28999,name="Marshal's Scaled Bracers"},{id=28646,name="General's Scaled Bracers"},
            {id=28996,name="Marshal's Plate Bracers"},{id=28381,name="General's Plate Bracers"},
            {id=32986,name="Marshal's Ornamented Bracers"},{id=32983,name="General's Ornamented Bracers"},
            {id=28984,name="Marshal's Lamellar Bracers"},{id=28643,name="General's Lamellar Bracers"},
        }},
        { slot="Belt", honor=13310, marks={AB=10}, items={
            {id=28998,name="Marshal's Scaled Belt"},{id=28644,name="General's Scaled Belt"},
            {id=28995,name="Marshal's Plate Belt"},{id=28385,name="General's Plate Belt"},
            {id=32985,name="Marshal's Ornamented Belt"},{id=32982,name="General's Ornamented Belt"},
            {id=28983,name="Marshal's Lamellar Belt"},{id=28641,name="General's Lamellar Belt"},
        }},
        { slot="Boots", honor=13310, marks={EotS=20}, items={
            {id=29000,name="Marshal's Scaled Greaves"},{id=28645,name="General's Scaled Greaves"},
            {id=28997,name="Marshal's Plate Greaves"},{id=28383,name="General's Plate Greaves"},
            {id=32987,name="Marshal's Ornamented Greaves"},{id=32984,name="General's Ornamented Greaves"},
            {id=28985,name="Marshal's Lamellar Greaves"},{id=28642,name="General's Lamellar Greaves"},
        }},
    },
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

GetCurrentHonor = function()
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

GetCurrentArenaPoints = function()
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
GetLiveRatings = function()
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
    -- Detect BackdropTemplate availability (TBC Anniversary supports it)
    local tmpl = (BackdropTemplateMixin ~= nil) and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", name, parent, tmpl)
    f:SetSize(w, h)
    -- Apply backdrop if methods are available (via template or mixin)
    if not f.SetBackdrop and BackdropTemplateMixin then
        Mixin(f, BackdropTemplateMixin)
    end
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left=11, right=12, top=12, bottom=11 },
        })
        f:SetBackdropColor(0, 0, 0, 1)
        f:SetBackdropBorderColor(1, 1, 1, 1)
    end
    -- Title bar highlight strip
    local tb = f:CreateTexture(nil, "ARTWORK")
    tb:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
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
-- MINIMAP BUTTON  (reference implementation pattern)
-- DB stored under BeanArenaDB.minimap
-- Textures: overlay=136430, background=136467, icon=achievement_pvp_a_01
-- ============================================================

-- Minimap shape quadrant table — handles non-circular minimaps
local MinimapShapes = {
    ["ROUND"]                  = {true,  true,  true,  true },
    ["SQUARE"]                 = {false, false, false, false},
    ["CORNER-TOPLEFT"]         = {true,  false, false, false},
    ["CORNER-TOPRIGHT"]        = {false, false, true,  false},
    ["CORNER-BOTTOMLEFT"]      = {false, true,  false, false},
    ["CORNER-BOTTOMRIGHT"]     = {false, false, false, true },
    ["SIDE-LEFT"]              = {true,  true,  false, false},
    ["SIDE-RIGHT"]             = {false, false, true,  true },
    ["SIDE-TOP"]               = {true,  false, true,  false},
    ["SIDE-BOTTOM"]            = {false, true,  false, true },
    ["TRICORNER-TOPLEFT"]      = {true,  true,  true,  false},
    ["TRICORNER-TOPRIGHT"]     = {true,  false, true,  true },
    ["TRICORNER-BOTTOMLEFT"]   = {true,  true,  false, true },
    ["TRICORNER-BOTTOMRIGHT"]  = {false, true,  true,  true },
}

local minimapButton = CreateFrame("Button", "BeanArenaMinimapButton", Minimap)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetSize(31, 31)
minimapButton:SetFrameLevel(8)
minimapButton:RegisterForClicks("anyUp")
minimapButton:RegisterForDrag("LeftButton")
minimapButton:SetHighlightTexture(136477) -- UI-Minimap-ZoomButton-Highlight
minimapButton:SetClampedToScreen(true)
minimapButton:SetClampRectInsets(0, -3, 0, 0)

local mmOverlay = minimapButton:CreateTexture(nil, "OVERLAY")
mmOverlay:SetSize(53, 53)
mmOverlay:SetTexture(136430) -- MiniMap-TrackingBorder
mmOverlay:SetPoint("TOPLEFT")

local mmBackground = minimapButton:CreateTexture(nil, "BACKGROUND")
mmBackground:SetSize(20, 20)
mmBackground:SetTexture(136467) -- UI-Minimap-Background
mmBackground:SetPoint("TOPLEFT", 7, -5)

local mmIcon = minimapButton:CreateTexture(nil, "ARTWORK")
mmIcon:SetSize(17, 17)
mmIcon:SetTexture("Interface\\Icons\\achievement_pvp_a_01")
mmIcon:SetPoint("TOPLEFT", 7, -6)

-- icon zoom: pull edges in slightly when not pressed
local function MMIconZoom(isDown)
    local d = isDown and 0 or 0.05
    mmIcon:SetTexCoord(d, 1-d, d, 1-d)
end
MMIconZoom(false)

local mmIsDragging = false
local mmIsDown = false

local function UpdateMinimapPos()
    local mmDB = BeanArenaDB.minimap
    -- radius offset + distance ratio, matching the reference exactly
    local w = (math.floor(Minimap:GetWidth()  / 2) + 10) * mmDB.distance
    local h = (math.floor(Minimap:GetHeight() / 2) + 10) * mmDB.distance
    local angle = math.rad(mmDB.position)
    local x = math.cos(angle)
    local y = math.sin(angle)
    -- quadrant: 1=upper-left, 2=lower-left, 3=upper-right, 4=lower-right
    local q = 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local quadTable = MinimapShapes[shape] or MinimapShapes["ROUND"]
    if quadTable[q] then
        x = x * w
        y = y * h
    else
        local diagW = math.sqrt(2 * w^2) - 10
        local diagH = math.sqrt(2 * h^2) - 10
        x = math.max(-w, math.min(x * diagW, w))
        y = math.max(-h, math.min(y * diagH, h))
    end
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

minimapButton:SetScript("OnDragStart", function(self)
    mmIsDown = true
    if BeanArenaDB.minimap.lock then return end
    self:LockHighlight()
    MMIconZoom(false)
    mmIsDragging = true
    GameTooltip:Hide()
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale  = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        local dx, dy = px - mx, py - my
        BeanArenaDB.minimap.position = math.deg(math.atan2(dy, dx)) % 360
        if BeanArenaDB.minimap.lockDistance then
            BeanArenaDB.minimap.distance = 1
        else
            local radius = (Minimap:GetWidth() / 2) + 5
            local dist = math.sqrt(dx*dx + dy*dy) / radius
            BeanArenaDB.minimap.distance = math.max(1, math.min(dist, 2))
        end
        UpdateMinimapPos()
    end)
end)

minimapButton:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    mmIsDown = false
    MMIconZoom(false)
    self:UnlockHighlight()
    mmIsDragging = false
end)

minimapButton:SetScript("OnMouseDown", function()
    mmIsDown = true
    MMIconZoom(true)
end)

minimapButton:SetScript("OnMouseUp", function()
    mmIsDown = false
    MMIconZoom(false)
end)

minimapButton:SetScript("OnEnter", function(self)
    if mmIsDragging then return end
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
        GameTooltip:AddLine(string.format("Best reward: |cffFFD700%.0f Arena Points|r  (%s)", best, bb), 0.8,0.8,0.8)
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
local charViewFrame
local BeanArena_RefreshRefFrame, BeanArena_OpenRefFrame, BeanArena_RebuildRefPage, BeanArena_RefreshCharPlan
local BeanArena_RefreshTeamBGPage
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
local FW, FH = 430, 510   -- expanded for Rating Target section
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
    -- Rating Target (AP > Rating)
    TLINE   = -318, THEAD   = -330, TLINE2  = -343,
    TINPUT  = -358, TRES    = -378, TLINE3  = -395,
    -- Bottom button rows (shifted down from original -330/-355/-380)
    BTNS    = -410, BTNROW2 = -430, CHARDD  = -453,
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
versionFS:SetText("|cff666666v" .. BA_VERSION .. "  •  TBC Anniversary|r")
versionFS:SetJustifyH("RIGHT")

local mainClose = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
mainClose:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
mainClose:SetScript("OnClick", function() frame:Hide() end)



-- Calculator content container — hidden when a reference section is shown.
-- Created here (last child of frame) so show/hide is one call.
local calcPanel = CreateFrame("Frame", nil, frame)
calcPanel:SetAllPoints(frame)

-- ── Helpers scoped to calcPanel ──────────────────────────────
local function SmallHdr(x, y, txt)
    local f = calcPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f:SetPoint("TOPLEFT", calcPanel, "TOPLEFT", x, y)
    f:SetText("|cffAAAAAA" .. txt .. "|r")
end

-- ══════════════════════════════════════════════════════════════
-- SECTION: CURRENT ARENA RATINGS
-- ══════════════════════════════════════════════════════════════
MakeHeader(calcPanel, Y.LHEAD, "Current Arena Ratings", LC)
MakeLine(calcPanel, Y.LLINE1, CW, LC)

-- Bracket | Games | Rating | Reward AP | Total AP
local LCOL = { br=LC, gms=LC+60, rat=LC+112, pts=LC+182, tot=LC+268 }
SmallHdr(LCOL.br,  Y.LCOLHDR, "Bracket")
SmallHdr(LCOL.gms, Y.LCOLHDR, "Games")
SmallHdr(LCOL.rat, Y.LCOLHDR, "Rating")
SmallHdr(LCOL.pts, Y.LCOLHDR, "Reward")
SmallHdr(LCOL.tot, Y.LCOLHDR, "Total Arena Points")
MakeLine(calcPanel, Y.LLINE2, CW, LC)

local function LiveRow(y, label)
    local l = calcPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l:SetPoint("TOPLEFT", calcPanel, "TOPLEFT", LCOL.br, y)
    l:SetText(label); l:SetTextColor(0.8, 0.8, 0.8)
    local function F(x) return FS(calcPanel, x, y) end
    -- liveR=rating, liveG=games, liveP=reward AP, liveT=total AP
    return F(LCOL.rat), F(LCOL.gms), F(LCOL.pts), F(LCOL.tot)
end

local liveR2, liveG2, liveP2, liveT2 = LiveRow(Y.L2V2, "2v2")
local liveR3, liveG3, liveP3, liveT3 = LiveRow(Y.L3V3, "3v3")
local liveR5, liveG5, liveP5, liveT5 = LiveRow(Y.L5V5, "5v5")
MakeLine(calcPanel, Y.LLINE3, CW, LC)

local apLbl = calcPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
apLbl:SetPoint("TOPLEFT", calcPanel, "TOPLEFT", LC, Y.LBANKED)
apLbl:SetText("Arena Points:"); apLbl:SetTextColor(0.8, 0.8, 0.8)
local apInlineVal = calcPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
apInlineVal:SetPoint("LEFT", apLbl, "RIGHT", 8, 0); apInlineVal:SetText("--")

local honLbl = calcPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
honLbl:SetPoint("TOPLEFT", calcPanel, "TOPLEFT", LC + 200, Y.LBANKED)
honLbl:SetText("Honor:"); honLbl:SetTextColor(0.8, 0.8, 0.8)
local honorInlineVal = calcPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
honorInlineVal:SetPoint("LEFT", honLbl, "RIGHT", 8, 0); honorInlineVal:SetText("--")

-- ══════════════════════════════════════════════════════════════
-- SECTION: ARENA POINT CALCULATOR
-- ══════════════════════════════════════════════════════════════
MakeLine(calcPanel, Y.LLINE4, CW, LC)
MakeHeader(calcPanel, Y.MHEAD, "Arena Point Calculator", LC)
MakeLine(calcPanel, Y.MLINE1, CW, LC)

local CALC = { lbl=LC, eb=LC+110, res=LC+240 }
SmallHdr(CALC.lbl, Y.MCALCHDR, "Bracket")
SmallHdr(CALC.eb,  Y.MCALCHDR, "Rating")
SmallHdr(CALC.res, Y.MCALCHDR, "Arena Points")
MakeLine(calcPanel, Y.MLINE1B, CW, LC)

local editFocused = {}
local manResultFS = {}

local function MakeCalcRow(y, labelText, dbKey, bracket)
    local l = calcPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l:SetPoint("TOPLEFT", calcPanel, "TOPLEFT", CALC.lbl, y)
    l:SetText(labelText); l:SetTextColor(0.8, 0.8, 0.8)
    local eb = CreateFrame("EditBox", nil, calcPanel, "InputBoxTemplate")
    eb:SetSize(88, 20)
    eb:SetPoint("TOPLEFT", calcPanel, "TOPLEFT", CALC.eb, y + 4)
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
    local res = calcPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    res:SetPoint("TOPLEFT", calcPanel, "TOPLEFT", CALC.res, y); res:SetText("--")
    manResultFS[bracket] = res
    return eb
end

local man2v2Edit = MakeCalcRow(Y.M2V2, "2v2:", "manual2v2", "2v2")
local man3v3Edit = MakeCalcRow(Y.M3V3, "3v3:", "manual3v3", "3v3")
local man5v5Edit = MakeCalcRow(Y.M5V5, "5v5:", "manual5v5", "5v5")

MakeLine(calcPanel, Y.MLINE2, CW, LC)

-- ══════════════════════════════════════════════════════════════
-- SECTION: RATING TARGET  (AP > Rating inverse calculator)
-- ══════════════════════════════════════════════════════════════
MakeLine(calcPanel, Y.TLINE, CW, LC)
MakeHeader(calcPanel, Y.THEAD, "Rating Target", LC)
MakeLine(calcPanel, Y.TLINE2, CW, LC)

SmallHdr(CALC.lbl,  Y.TINPUT + 10, "Arena Points Goal")

local targetLbl = calcPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
targetLbl:SetPoint("TOPLEFT", calcPanel, "TOPLEFT", CALC.lbl, Y.TINPUT)
targetLbl:SetText("Arena Points:"); targetLbl:SetTextColor(0.8, 0.8, 0.8)

local targetResultFS = calcPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
targetResultFS:SetPoint("TOPLEFT", calcPanel, "TOPLEFT", LC, Y.TRES)
targetResultFS:SetWidth(CW)
targetResultFS:SetText("--")

local targetAPEdit = CreateFrame("EditBox", nil, calcPanel, "InputBoxTemplate")
targetAPEdit:SetSize(88, 20)
targetAPEdit:SetPoint("TOPLEFT", calcPanel, "TOPLEFT", CALC.eb, Y.TINPUT + 4)
targetAPEdit:SetAutoFocus(false); targetAPEdit:SetNumeric(true); targetAPEdit:SetMaxLetters(4)
targetAPEdit:SetText(DB("targetAP") > 0 and tostring(DB("targetAP")) or "")

local RefreshTargetCalc
targetAPEdit:SetScript("OnEditFocusGained", function() editFocused["targetAP"] = true end)
targetAPEdit:SetScript("OnEditFocusLost", function(self)
    editFocused["targetAP"] = nil
    SetDB("targetAP", tonumber(self:GetText()) or 0)
    RefreshTargetCalc()
end)
targetAPEdit:SetScript("OnEnterPressed", function(self)
    SetDB("targetAP", tonumber(self:GetText()) or 0)
    self:ClearFocus(); RefreshTargetCalc()
end)
targetAPEdit:SetScript("OnEscapePressed", function(self)
    local v = DB("targetAP")
    self:SetText(v > 0 and tostring(v) or ""); self:ClearFocus()
end)

local BRACKET_MAX_AP = { ["2v2"] = 1883, ["3v3"] = 2181, ["5v5"] = 2478 }

RefreshTargetCalc = function()
    local ap = DB("targetAP")
    if ap <= 0 then
        targetResultFS:SetText("|cff666666—|r")
        return
    end
    local parts = {}
    for _, bkt in ipairs({"2v2", "3v3", "5v5"}) do
        local r = CalcRatingForPoints(ap, bkt)
        if r == nil then
            parts[#parts+1] = string.format("%s: |cffFF4444n/a|r|cff666666(~%d max)|r", bkt, BRACKET_MAX_AP[bkt])
        elseif r == 0 then
            parts[#parts+1] = bkt .. ": |cff00FF00any|r"
        else
            parts[#parts+1] = bkt .. ": |cffFFD700" .. tostring(r) .. "|r"
        end
    end
    targetResultFS:SetText(table.concat(parts, "  |cff444444·|r  "))
end

MakeLine(calcPanel, Y.TLINE3, CW, LC)

-- ── Row 1: Arena Gear | Weapons | Honor Gear ──────────────────────────
-- ── Menu dropdown (top-left of frame) ──────────────────────────────
local MENU_SECTIONS = {"Calculator","Honor","Arena Gear","Weapons","Honor Gear","My Gear","Team BGs","CC/DR Table","Help"}
local mainMenuBtn = CreateFrame("Button", "BeanArenaMenuBtn", frame, "UIPanelButtonTemplate")
mainMenuBtn:SetSize(120, 22)
mainMenuBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
mainMenuBtn:GetFontString():SetFontObject("GameFontNormalSmall")
mainMenuBtn:SetText("Menu")
local mainMenuDD = CreateFrame("Frame", "BeanArenaMainMenuDD", UIParent, "UIDropDownMenuTemplate")
mainMenuBtn:SetScript("OnClick", function(self)
    UIDropDownMenu_Initialize(mainMenuDD, function()
        for _, sec in ipairs(MENU_SECTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = sec; info.notCheckable = true
            info.func = function() BeanArena_OpenRefFrame(sec); CloseDropDownMenus() end
            UIDropDownMenu_AddButton(info)
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, mainMenuDD, self, 0, -4)
end)

local charDDLbl = calcPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
charDDLbl:SetPoint("TOP", calcPanel, "TOP", 0, Y.CHARDD + 16)
charDDLbl:SetText("|cff888888Viewing:|r")
charDDLbl:SetJustifyH("CENTER")

local charDD = CreateFrame("Frame", "BeanArenaCharDD", calcPanel, "UIDropDownMenuTemplate")
UIDropDownMenu_SetWidth(charDD, 260)
charDD:SetPoint("TOP", calcPanel, "TOP", 0, Y.CHARDD - 4)

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
        -- Restore live data for current character
        UIDropDownMenu_SetText(charDD, "|cffFFD700" .. (CHAR_NAME or "Current") .. " (you)|r")
        if UIDropDownMenu_JustifyText then UIDropDownMenu_JustifyText(charDD, "CENTER") end
        BeanArena_RefreshFrame()
    else
        -- Show a different character's snapshot
        UIDropDownMenu_SetText(charDD, snap.name)
        if UIDropDownMenu_JustifyText then UIDropDownMenu_JustifyText(charDD, "CENTER") end
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
        local sfmt = BreakUpLargeNumbers or tostring
        local shon = snap.honor or 0
        honorInlineVal:SetText(shon > 0
            and string.format("|cffFFD700%s|r", sfmt(shon))
            or  "|cff666666--|r")
    end
end

UIDropDownMenu_Initialize(charDD, function()
    if UIDropDownMenu_JustifyText then UIDropDownMenu_JustifyText(charDD, "CENTER") end
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
-- FORWARD DECLARATION ASSIGNMENT
-- ============================================================
OpenBeanArena = function()
    frame:Show(); BeanArena_RefreshFrame()
end

-- ============================================================
-- COMMANDS FRAME  (updated to /ba)
-- ============================================================
local COMMANDS_LIST = {
    { cmd="/ba",                desc="Toggle main window"              },
    { cmd="/ba calc [rating]",  desc="AP for live ratings or a number" },
    { cmd="/ba target <ap>",   desc="Rating needed to earn that AP"   },
    { cmd="/ba honor [slot]",   desc="Honor window or gear slot info"  },
    { cmd="/ba arena [slot]",   desc="Arena gear window or slot info"  },
    { cmd="/ba dr [class]",     desc="CC/DR window or class CC list"   },
    { cmd="/ba gear",           desc="Arena gear costs window"         },
    { cmd="/ba hgear",          desc="Honor gear costs window"         },
    { cmd="/ba plan",           desc="My Gear — PvP gear status view"  },
    { cmd="/ba bgshare",        desc="Share your honor+marks with party" },
    { cmd="/ba bgprint",        desc="Print full party BG stats to chat" },
    { cmd="/ba info",           desc="Info window"                     },
    { cmd="/ba chars",          desc="Character viewer"                },
    { cmd="/ba alts",              desc="Print all alt PvP snapshots to chat"  },
    { cmd="/ba points",            desc="Live rating AP breakdown"              },
    { cmd="/ba marks",          desc="Current BG mark counts"          },
    { cmd="/ba reset",          desc="Time until weekly reset"         },
    { cmd="/ba commands",       desc="This window"                     },
    { cmd="/ba help",           desc="Print all commands to chat"      },
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
    RefreshTargetCalc()
end

local function RefreshLive()
    local r2,r3,r5,g2,g3,g5 = GetLiveRatings()
    local curAP   = GetCurrentArenaPoints()
    local curHon  = GetCurrentHonor()
    local fmt     = BreakUpLargeNumbers or tostring
    honorInlineVal:SetText(curHon > 0
        and string.format("|cffFFD700%s|r", fmt(curHon))
        or  "|cff666666--|r")
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
    if BeanArena_RefreshRefFrame then BeanArena_RefreshRefFrame() end
end

BeanArena_RefreshFrame = function()
    if viewingSnap == nil then RefreshLive() end; RefreshMisc()
    if not editFocused["manual2v2"] then man2v2Edit:SetText(tostring(DB("manual2v2"))) end
    if not editFocused["manual3v3"] then man3v3Edit:SetText(tostring(DB("manual3v3"))) end
    if not editFocused["manual5v5"] then man5v5Edit:SetText(tostring(DB("manual5v5"))) end
    if not editFocused["targetAP"] then
        local v = DB("targetAP"); targetAPEdit:SetText(v > 0 and tostring(v) or "")
    end
    BeanArena_RefreshManual()
end

-- ============================================================
-- DR DATA  (TBC 2.4.3 / Anniversary)
-- ============================================================
local DR_CATEGORIES = {
    { id="STUN_CTRL", name="Controlled Stun",  color="FF4444", desc="Activated stun abilities. Full>50%>25%>immune." },
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
    -- dur format: "Xs" = no DR, "Xs/Ys/Zs" = full/50%/25% (immune after 3rd)
    ["Druid"]   = {
        { spell="Cyclone",            dr="CYCLONE",   dur="6s/3s/1.5s", notes="Immunity, no dmg/heal" },
        { spell="Bash",               dr="STUN_CTRL", dur="3s/1.5s/0.75s", notes="Bear form" },
        { spell="Pounce",             dr="STUN_CTRL", dur="3s/1.5s/0.75s", notes="Cat stealth opener" },
        { spell="Maim",               dr="STUN_CTRL", dur="5s/2.5s/1s",    notes="Cat finisher (5cp)" },
        { spell="Hibernate",          dr="SLEEP",     dur="8s/4s/2s",  notes="Beasts/Dragonkin" },
        { spell="Entangling Roots",   dr="ROOT_CTRL", dur="8s/4s/2s",  notes="Breaks on dmg" },
        { spell="Nature's Grasp",     dr="ROOT_CTRL", dur="8s/4s/2s",  notes="Proc root on hit" },
        { spell="Feral Charge",       dr="ROOT_CTRL", dur="4s/2s/1s",  notes="Bear interrupt+root" },
    },
    ["Hunter"]  = {
        { spell="Freezing Trap",  dr="INCAP",     dur="8s/4s/2s",   notes="Target walks in" },
        { spell="Wyvern Sting",   dr="SLEEP",     dur="8s/4s/2s",   notes="Survival, 1 min CD" },
        { spell="Scatter Shot",   dr="FEAR",      dur="4s/2s/1s",   notes="Breaks on dmg" },
        { spell="Intimidation",   dr="STUN_CTRL", dur="3s/1.5s/0.75s", notes="Pet, BM talent" },
        { spell="Silencing Shot", dr="SILENCE",   dur="3s",         notes="NO DR in TBC" },
        { spell="Entrapment",     dr="ROOT_CTRL", dur="4s/2s/1s",   notes="Frost Trap proc" },
        { spell="Scare Beast",    dr="FEAR",      dur="8s/4s/2s",   notes="Beasts only" },
    },
    ["Mage"]    = {
        { spell="Polymorph",         dr="INCAP",     dur="8s/4s/2s", notes="Humanoids, heals target" },
        { spell="Frost Nova",        dr="ROOT_CTRL", dur="8s/4s/2s", notes="Melee AoE" },
        { spell="Freeze",            dr="ROOT_CTRL", dur="8s/4s/2s", notes="Water Elemental" },
        { spell="Frostbite",         dr="ROOT_CTRL", dur="5s/2.5s/1s", notes="Chill proc, 2.1+" },
        { spell="Dragon's Breath",   dr="INCAP",     dur="5s/2.5s/1s", notes="Fire 41pt, breaks on dmg" },
        { spell="Counterspell",      dr="SILENCE",   dur="8s",       notes="Interrupt+lock; NO DR" },
        { spell="Imp. Counterspell", dr="SILENCE",   dur="4s",       notes="Silence; NO DR" },
    },
    ["Paladin"] = {
        { spell="Hammer of Justice", dr="STUN_CTRL", dur="6s/3s/1.5s", notes="Any target" },
        { spell="Repentance",        dr="INCAP",     dur="6s/3s/1.5s", notes="Humanoids/Undead/Demons" },
        { spell="Turn Evil",         dr="FEAR",      dur="10s/5s/2.5s", notes="Undead/Demons" },
    },
    ["Priest"]  = {
        { spell="Psychic Scream",   dr="FEAR",    dur="8s/4s/2s", notes="AoE fear" },
        { spell="Mind Control",     dr="NONE",    dur="—",        notes="No DR; breaks on dmg" },
        { spell="Shackle Undead",   dr="NONE",    dur="50s",      notes="Undead only; no DR" },
        { spell="Silence (Shadow)", dr="SILENCE", dur="5s",       notes="Shadow spec; NO DR" },
    },
    ["Rogue"]   = {
        { spell="Sap",         dr="INCAP",     dur="10s/5s/2.5s", notes="OOC; breaks on dmg" },
        { spell="Gouge",       dr="INCAP",     dur="4s/2s/1s",    notes="Breaks on dmg" },
        { spell="Cheap Shot",  dr="STUN_CTRL", dur="4s/2s/1s",    notes="Stealth opener" },
        { spell="Kidney Shot", dr="STUN_KS",   dur="6s/3s/1.5s",  notes="5cp; own DR" },
        { spell="Blind",       dr="FEAR",      dur="10s/5s/2.5s", notes="Shares Fear DR in TBC" },
        { spell="Garrote",     dr="SILENCE",   dur="3s",          notes="Stealth silence; NO DR" },
    },
    ["Shaman"]  = {
        { spell="Earthbind Totem",   dr="NONE",    dur="—",  notes="Slow pulse; no DR" },
        { spell="Frost Shock",       dr="NONE",    dur="8s", notes="Snare only; no DR" },
        { spell="Earth Shock",       dr="SILENCE", dur="2s", notes="Interrupt; NO DR" },
        { spell="Frostbrand Weapon", dr="NONE",    dur="5s", notes="Snare proc; no DR" },
    },
    ["Warlock"] = {
        { spell="Fear",           dr="FEAR",      dur="8s/4s/2s",   notes="Breaks on dmg" },
        { spell="Howl of Terror", dr="FEAR",      dur="8s/4s/2s",   notes="AoE; breaks on dmg" },
        { spell="Death Coil",     dr="HORROR",    dur="3s/1.5s/0.75s", notes="Horror category" },
        { spell="Seduction",      dr="FEAR",      dur="15s/7.5s/3.75s", notes="Succubus; humanoids" },
        { spell="Shadowfury",     dr="STUN_CTRL", dur="3s/1.5s/0.75s", notes="Destro 41pt AoE" },
        { spell="Spell Lock",     dr="SILENCE",   dur="3s",         notes="Felhunter; NO DR" },
        { spell="Banish",         dr="NONE",      dur="30s",        notes="Demons/Elementals; no DR" },
    },
    ["Warrior"] = {
        { spell="Intimidating Shout", dr="FEAR",      dur="8s/4s/2s",      notes="AoE; primary immob." },
        { spell="Intercept",          dr="STUN_CTRL", dur="3s/1.5s/0.75s", notes="Charge stun" },
        { spell="Concussion Blow",    dr="STUN_CTRL", dur="5s/2.5s/1s",    notes="Prot talent" },
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
-- EMBEDDED REFERENCE OVERLAY
-- Single-window content panel, switched via Menu dropdown.
-- Sections: Calculator | Honor | Arena Gear | Weapons | Honor Gear | CC/DR Table | Help
-- ============================================================
-- ── My Gear slot layout (paper-doll style, used inside the do block) ────
local GEAR_LAYOUT = {
    { id=1,  col="L", row=1, name="Head"      },
    { id=2,  col="L", row=2, name="Neck"      },
    { id=3,  col="L", row=3, name="Shoulders" },
    { id=15, col="L", row=4, name="Back"      },
    { id=5,  col="L", row=5, name="Chest"     },
    { id=9,  col="L", row=6, name="Bracers"   },
    { id=6,  col="L", row=7, name="Belt"      },
    { id=10, col="R", row=1, name="Gloves"    },
    { id=7,  col="R", row=2, name="Legs"      },
    { id=8,  col="R", row=3, name="Boots"     },
    { id=11, col="R", row=4, name="Ring 1"    },
    { id=12, col="R", row=5, name="Ring 2"    },
    { id=13, col="R", row=6, name="Trinket 1" },
    { id=14, col="R", row=7, name="Trinket 2" },
    { id=16, col="B", row=1, name="Main Hand" },
    { id=17, col="B", row=2, name="Off Hand"  },
    { id=18, col="B", row=3, name="Ranged"    },
}

-- SendAddonMessage moved to C_ChatInfo in newer client builds; try both.
-- Defined before the do block so BuildTeamBGContent (inside do) can call them.
local function BA_RegisterPrefix(prefix)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(prefix)
    end
end
local function BA_SendAddonMsg(prefix, message, chatType)
    -- Re-register prefix each call to be safe; registration is idempotent
    BA_RegisterPrefix(prefix)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(prefix, message, chatType)
    elseif SendAddonMessage then
        SendAddonMessage(prefix, message, chatType)
    else
        print("|cffFF4444[BA]|r Addon messaging unavailable — cannot share stats.")
    end
end

do
    local OV_RCW = FW - 4 - 8 - 20  -- 398 px content width inside scroll frame

    -- ── Standalone reference window — own MakeBGFrame backdrop, no overlay tricks
    local refFrame = MakeBGFrame("BeanArenaRefFrame", UIParent, FW, FH)
    refFrame:SetFrameStrata("MEDIUM")
    refFrame:SetMovable(true); refFrame:EnableMouse(true)
    refFrame:RegisterForDrag("LeftButton")
    refFrame:SetScript("OnDragStart", refFrame.StartMoving)
    refFrame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    refFrame:Hide()
    RegisterEsc(refFrame)

    -- Title (right-aligned, matches main frame style)
    local rfTitleFS = refFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    rfTitleFS:SetPoint("TOPRIGHT", refFrame, "TOPRIGHT", -36, -10)
    rfTitleFS:SetText("|cffFF6600«|r |cffFFD700BeanArena|r |cffFF6600»|r")
    rfTitleFS:SetJustifyH("RIGHT")

    -- Section label below title
    local rfSectionFS = refFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rfSectionFS:SetPoint("TOPRIGHT", refFrame, "TOPRIGHT", -36, -27)
    rfSectionFS:SetText("|cff666666Reference|r")
    rfSectionFS:SetJustifyH("RIGHT")

    local rfClose = CreateFrame("Button", nil, refFrame, "UIPanelCloseButton")
    rfClose:SetPoint("TOPRIGHT", refFrame, "TOPRIGHT", -4, -4)
    rfClose:SetScript("OnClick", function() refFrame:Hide() end)

    local ovSection = "Calculator"
    local ovSeason  = 2
    local ovClass   = "Warrior"

    -- ── Season toggle buttons (hidden for Honor, CC/DR Table, Help) ───────
    local ovS1Btn = CreateFrame("Button", nil, refFrame, "UIPanelButtonTemplate")
    ovS1Btn:SetSize(48, 22)
    ovS1Btn:SetPoint("TOPLEFT", refFrame, "TOPLEFT", 8, -8)
    ovS1Btn:SetText("S1"); ovS1Btn:GetFontString():SetFontObject("GameFontNormalSmall")
    ovS1Btn:Hide()
    local ovS2Btn = CreateFrame("Button", nil, refFrame, "UIPanelButtonTemplate")
    ovS2Btn:SetSize(48, 22)
    ovS2Btn:SetPoint("LEFT", ovS1Btn, "RIGHT", 4, 0)
    ovS2Btn:SetText("S2"); ovS2Btn:GetFontString():SetFontObject("GameFontNormalSmall")
    ovS2Btn:Hide()

    -- ── Class selector (Arena Gear only) ─────────────────────────────
    local ovClassBtn = CreateFrame("Button", nil, refFrame, "UIPanelButtonTemplate")
    ovClassBtn:SetSize(138, 22)
    ovClassBtn:SetPoint("LEFT", ovS2Btn, "RIGHT", 6, 0)
    ovClassBtn:GetFontString():SetFontObject("GameFontNormalSmall")
    ovClassBtn:SetText("Warrior"); ovClassBtn:Hide()
    local ovClassDD = CreateFrame("Frame", "BeanArenaOvClassDD", UIParent, "UIDropDownMenuTemplate")

    -- ── Scroll area ───────────────────────────────────────────────────
    local ovScr = CreateFrame("ScrollFrame", "BeanArenaOvScr", refFrame, "UIPanelScrollFrameTemplate")
    ovScr:SetPoint("TOPLEFT",     refFrame, "TOPLEFT",      8, -36)
    ovScr:SetPoint("BOTTOMRIGHT", refFrame, "BOTTOMRIGHT", -20,   6)
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

    -- ── Arena gear layout constants ───────────────────────────────────────────
    local IC_SZ   = 36          -- icon size (px)
    local IC_CELL = IC_SZ + 4   -- icon cell width (icon + gap)
    local SL_W    = 82          -- slot-label column width (px)

    -- Maps WoW equipLoc string → friendly slot name used in slotGrid / SLOT_DEFS
    local EQUIP_TO_SLOT = {
        INVTYPE_HEAD     = "Head",
        INVTYPE_SHOULDER = "Shoulders",
        INVTYPE_CHEST    = "Chest",
        INVTYPE_ROBE     = "Chest",
        INVTYPE_LEGS     = "Legs",
        INVTYPE_HAND     = "Gloves",
    }

    -- Ordered slot list with AP cost and personal-rating gate per season.
    -- apS1/apS2: arena points required.
    -- ratingS1/ratingS2: personal rating required (0 = no gate).
    local SLOT_DEFS = {
        { slot="Head",      apS1=620,  apS2=1550, ratingS1=0,    ratingS2=0    },
        { slot="Shoulders", apS1=495,  apS2=1245, ratingS1=2000, ratingS2=2000 },
        { slot="Chest",     apS1=620,  apS2=1550, ratingS1=0,    ratingS2=0    },
        { slot="Legs",      apS1=620,  apS2=1550, ratingS1=0,    ratingS2=0    },
        { slot="Gloves",    apS1=370,  apS2=930,  ratingS1=0,    ratingS2=0    },
    }

    local function BuildArenaContent()
        ClearContent()
        local setList    = ovSeason == 2 and CLASS_SETS_S2 or CLASS_SETS_S1
        local r2,r3,r5   = GetLiveRatings()
        local bestRating = math.max(r2, r3, r5)
        local curAP      = GetCurrentArenaPoints()
        local cy = -2

        local function AGLine()
            local d = ovCnt:CreateTexture(nil,"ARTWORK")
            d:SetSize(OV_RCW,1); d:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",0,cy-2)
            d:SetColorTexture(0.3,0.3,0.3,0.5); cy=cy-8
        end
        local function AGHdr(txt)
            local h = ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormal")
            h:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",0,cy)
            h:SetText("|cff00CCFF"..txt.."|r"); cy=cy-16
        end

        local variants = setList[ovClass] or {ovClass.." Set"}
        local nV = #variants
        AGHdr(string.format("Armor Set  |cffAAAAAA— %s  (%d variant%s)|r",
            ovClass, nV, nV > 1 and "s" or ""))
        if nV > 1 then
            local vLine = ""
            for vi, varName in ipairs(variants) do
                local tail = varName:match("(%S+)$") or varName
                vLine = vLine .. (vi > 1 and "  |  " or "") .. vi .. ":" .. tail
            end
            local vLbl = ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            vLbl:SetPoint("TOPLEFT", ovCnt,"TOPLEFT", 0, cy)
            vLbl:SetWidth(OV_RCW)
            vLbl:SetText("|cff888888Cols: " .. vLine .. "|r")
            cy = cy - 14
        end
        AGLine(); cy = cy - 4

        local slotGrid = {}
        for vi, varName in ipairs(variants) do
            slotGrid[vi] = {}
            for _, id in ipairs(ARMOR_SET_IDS[varName] or {}) do
                local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(id)
                if equipLoc and equipLoc ~= "" then
                    local sn = EQUIP_TO_SLOT[equipLoc]
                    if sn then slotGrid[vi][sn] = id end
                end
            end
        end

        for _, def in ipairs(SLOT_DEFS) do
            local slotName = def.slot
            local sLbl = ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            sLbl:SetPoint("TOPLEFT", ovCnt,"TOPLEFT", 0, cy - 13)
            sLbl:SetText("|cffAAAAAA"..slotName.."|r")
            for vi = 1, nV do
                local itemID  = slotGrid[vi] and slotGrid[vi][slotName]
                local iconPath
                if itemID then
                    local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(itemID)
                    iconPath = tex
                end
                local iconBtn = CreateFrame("Button", nil, ovCnt)
                iconBtn:SetSize(IC_SZ, IC_SZ)
                iconBtn:SetPoint("TOPLEFT", ovCnt,"TOPLEFT", SL_W + (vi-1)*IC_CELL, cy)
                local bg = iconBtn:CreateTexture(nil,"BACKGROUND")
                bg:SetAllPoints(); bg:SetColorTexture(0.10, 0.10, 0.12, 1)
                local iconTex = iconBtn:CreateTexture(nil,"ARTWORK")
                iconTex:SetAllPoints()
                iconTex:SetTexture(iconPath or "Interface\Icons\INV_Misc_QuestionMark")
                iconBtn:SetHighlightTexture("Interface\Buttons\ButtonHilight-Square")
                if itemID then
                    local capID = itemID
                    iconBtn:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink("item:"..capID)
                        GameTooltip:Show()
                    end)
                    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    iconBtn:SetScript("OnClick", function(self, btn)
                        if IsShiftKeyDown() then
                            local _, link = GetItemInfo(capID)
                            if link and ChatEdit_InsertLink then
                                ChatEdit_InsertLink(link)
                            end
                        end
                    end)
                end
            end
            cy = cy - (IC_SZ + 4)
        end

        cy = cy - 4; AGLine(); cy = cy - 4
        local costHdr = ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        costHdr:SetPoint("TOPLEFT", ovCnt,"TOPLEFT", 0, cy)
        costHdr:SetText("|cff888888Costs (S"..ovSeason.."):|r")
        cy = cy - 15
        for _, def in ipairs(SLOT_DEFS) do
            local ap     = ovSeason == 2 and def.apS2    or def.apS1
            local rating = ovSeason == 2 and def.ratingS2 or def.ratingS1
            local rMet   = rating == 0 or bestRating >= rating
            local aMet   = curAP >= ap
            local allMet = aMet and rMet
            local cLbl = ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            cLbl:SetPoint("TOPLEFT", ovCnt,"TOPLEFT", 0, cy)
            cLbl:SetText("|cffAAAAAA"..def.slot.."|r")
            local apLbl = ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            apLbl:SetPoint("TOPLEFT", ovCnt,"TOPLEFT", 82, cy)
            apLbl:SetText(string.format("|cff%s%d Arena Points|r", aMet and "FFD700" or "FF6666", ap))
            if rating > 0 then
                local rLbl = ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                rLbl:SetPoint("TOPLEFT", ovCnt,"TOPLEFT", 155, cy)
                rLbl:SetText(string.format("|cff%s%d rating|r",
                    rMet and "00FF00" or "FF4444", rating))
            end
            local tick = ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            tick:SetPoint("TOPRIGHT", ovCnt,"TOPRIGHT", 0, cy)
            tick:SetText(allMet and "|cff00FF00[OK]|r" or
                         (not aMet and "|cffFF4444[NO]|r" or "|cffFFAA00[!]|r"))
            cy = cy - 16
        end
        ovCnt:SetHeight(math.abs(cy) + 20)
    end

    -- ================================================================
    -- WEAPONS
    -- ================================================================
    local WICON    = 36
    local WCELL_W  = WICON + 4
    local WPER_ROW = math.floor(OV_RCW / (WICON + 4))
    local WEAPON_GROUPS = {
        { label="1H Weapons",          keys={"1H-Dagger","1H-Sword","1H-Mace","1H-Axe","1H-Fist","1H-SwordCaster","1H-MaceHeal"} },
        { label="2H Weapons",          keys={"2H-Sword","2H-Axe","2H-Mace","2H-Polearm","2H-Staff","2H-StaffFeral"} },
        { label="Ranged & Wands",      keys={"Crossbow","Thrown","Wand"} },
        { label="Shields & Off-hands", keys={"Shield","Off-Tome","Off-Orb"} },
        { label="Relics",              keys={"Idol","Libram","Totem"} },
    }

    local function BuildWeaponsContent()
        ClearContent()
        local weaponList = ovSeason == 2 and S2_WEAPONS or S1_WEAPONS
        local r2,r3,r5   = GetLiveRatings()
        local bestRating = math.max(r2, r3, r5)
        local curAP      = GetCurrentArenaPoints()
        local cy = -2
        local function WHdr(txt)
            local h = ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormal")
            h:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",0,cy)
            h:SetText("|cff00CCFF"..txt.."|r"); cy=cy-18
        end
        local function WLine()
            local d = ovCnt:CreateTexture(nil,"ARTWORK")
            d:SetSize(OV_RCW,1); d:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",0,cy-2)
            d:SetColorTexture(0.3,0.3,0.3,0.5); cy=cy-7
        end
        local byKey = {}
        for _, wep in ipairs(weaponList) do
            if not byKey[wep.key] then byKey[wep.key] = {} end
            byKey[wep.key][#byKey[wep.key]+1] = wep
        end
        for _, grp in ipairs(WEAPON_GROUPS) do
            local items = {}
            for _, k in ipairs(grp.keys) do
                for _, wep in ipairs(byKey[k] or {}) do
                    for _, id in ipairs(wep.ids or {}) do
                        items[#items+1] = {id=id, wep=wep}
                    end
                end
            end
            if #items > 0 then
                WHdr(grp.label.."  |cffAAAAAA("..#items.." item"..(#items~=1 and "s" or "")..")|r")
                WLine()
                local col  = 0
                local rowY = cy - 4
                for _, itm in ipairs(items) do
                    local id        = itm.id
                    local wep       = itm.wep
                    local canAfford = curAP >= wep.ap
                    local ratingMet = wep.rating == 0 or bestRating >= wep.rating
                    local iconBtn = CreateFrame("Button", nil, ovCnt)
                    iconBtn:SetSize(WICON, WICON)
                    iconBtn:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", col * WCELL_W, rowY)
                    local iconTex = iconBtn:CreateTexture(nil, "BACKGROUND")
                    iconTex:SetAllPoints()
                    local _,_,_,_,_,_,_,_,_,iconPath = GetItemInfo(id)
                    iconTex:SetTexture(iconPath or "Interface\Icons\INV_Misc_QuestionMark")
                    if not (canAfford and ratingMet) then
                        iconTex:SetDesaturated(true); iconTex:SetVertexColor(0.55, 0.55, 0.55)
                    end
                    iconBtn:SetHighlightTexture("Interface\Buttons\ButtonHilight-Square")
                    local capID, capWep, capCA, capRM = id, wep, canAfford, ratingMet
                    iconBtn:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink("item:"..capID)
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine(string.format("|cff%s%d Arena Points|r",
                            capCA and "FFD700" or "FF6666", capWep.ap))
                        if capWep.rating > 0 then
                            GameTooltip:AddLine(string.format("|cff%sRequires %d Rating|r",
                                capRM and "00FF00" or "FF4444", capWep.rating))
                        else
                            GameTooltip:AddLine("|cff00FF00No Rating Requirement|r")
                        end
                        GameTooltip:Show()
                    end)
                    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    iconBtn:SetScript("OnClick", function(self, btn)
                        if IsShiftKeyDown() then
                            local _, link = GetItemInfo(capID)
                            if link and ChatEdit_InsertLink then
                                ChatEdit_InsertLink(link)
                            end
                        end
                    end)
                    col = col + 1
                    if col >= WPER_ROW then col = 0; rowY = rowY - WCELL_W end
                end
                if col > 0 then rowY = rowY - WCELL_W end
                cy = rowY - 6
            end
        end
        ovCnt:SetHeight(math.abs(cy) + 20)
    end

    -- ================================================================
    -- HONOR GEAR  (class auto-detected, no manual switcher)
    -- ================================================================
    local HICON = 20

    local function BuildHonorContent()
        ClearContent()
        local armorType  = CLASS_ARMOR_TYPE[ovClass] or "Cloth"
        local universal  = ovSeason == 2 and S2_HONOR_UNIVERSAL or S1_HONOR_UNIVERSAL
        local byArmor    = ovSeason == 2 and S2_HONOR_BYARMOR   or S1_HONOR_BYARMOR
        local armorRows  = byArmor[armorType] or {}
        local honor      = GetCurrentHonor()
        local marks      = GetPvPMarkCounts()
        local fmt        = BreakUpLargeNumbers or tostring
        local cy         = -2
        local HCOL = { name=HICON+2, honor=OV_RCW-195, marks=OV_RCW-130, have=OV_RCW-48 }

        local function HLine()
            local d=ovCnt:CreateTexture(nil,"ARTWORK")
            d:SetSize(OV_RCW,1); d:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",0,cy-2)
            d:SetColorTexture(0.3,0.3,0.3,0.5); cy=cy-8
        end
        local function HGHdr(txt)
            local h=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormal")
            h:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",0,cy)
            h:SetText("|cff00CCFF"..txt.."|r"); cy=cy-16
        end
        local function ColHdrs()
            local function CH(x,t)
                local f=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                f:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",x,cy); f:SetText("|cffAAAAAA"..t.."|r")
            end
            CH(HCOL.name,"Item"); CH(HCOL.honor,"Honor"); CH(HCOL.marks,"Marks"); CH(HCOL.have,"You Have")
            cy=cy-14; HLine()
        end

        local function ItemRow(item, slotData)
            local honorMet = honor >= slotData.honor
            local hCol = honorMet and "00FF00" or "FF4444"
            local allMet = true
            local mparts = {}
            for bg, req in pairs(slotData.marks) do
                local have = marks[bg] or 0
                if have < req then allMet = false end
                local mc = have >= req and "00FF00" or "FF4444"
                mparts[#mparts+1] = string.format("|cff%s%d|r|cffAAAAAA/%d %s|r", mc, have, req, bg)
            end
            if #mparts == 0 then mparts[#mparts+1] = "|cff00FF00—|r" end
            local rowBtn = CreateFrame("Button", nil, ovCnt)
            rowBtn:SetSize(OV_RCW, HICON)
            rowBtn:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", 0, cy)
            rowBtn:SetHighlightTexture("Interface\Buttons\ButtonHilight-Square")
            local iconTex = rowBtn:CreateTexture(nil, "BACKGROUND")
            iconTex:SetSize(HICON, HICON)
            iconTex:SetPoint("LEFT", rowBtn, "LEFT", 0, 0)
            local _,_,_,_,_,_,_,_,_,iconPath = GetItemInfo(item.id)
            iconTex:SetTexture(iconPath or "Interface\Icons\INV_Misc_QuestionMark")
            if not (honorMet and allMet) then
                iconTex:SetDesaturated(true); iconTex:SetVertexColor(0.55, 0.55, 0.55)
            end
            local function BFS(x, t)
                local f = rowBtn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                f:SetPoint("LEFT",rowBtn,"LEFT",x,0); f:SetText(t)
            end
            local dispName = item.name or ("item:"..item.id)
            local cached = GetItemInfo(item.id)
            if cached then dispName = cached end
            BFS(HCOL.name,  "|cffCCCCCC"..dispName.."|r")
            BFS(HCOL.honor, string.format("|cff%s%s|r", hCol, fmt(slotData.honor)))
            BFS(HCOL.marks, table.concat(mparts,"  "))
            BFS(HCOL.have,  (honorMet and allMet) and "|cff00FF00Ready!|r" or "|cffAAAAAA...|r")
            local capturedID = item.id
            rowBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("item:"..capturedID)
                GameTooltip:Show()
            end)
            rowBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            rowBtn:SetScript("OnClick", function(self, btn)
                if IsShiftKeyDown() then
                    local _, link = GetItemInfo(capturedID)
                    if link and ChatEdit_InsertLink then
                        ChatEdit_InsertLink(link)
                    end
                end
            end)
            cy = cy - (HICON + 2)
        end

        HGHdr("Neck & Ring  |cffAAAAAA— all classes|r")
        ColHdrs()
        for _, slotData in ipairs(universal) do
            local prev_cy = cy
            for _, item in ipairs(slotData.items) do ItemRow(item, slotData) end
            if cy ~= prev_cy then cy = cy - 4 end
        end
        cy = cy - 4
        HGHdr("Off-pieces  |cffAAAAAA— "..armorType.." ("..ovClass..")|r")
        ColHdrs()
        if #armorRows == 0 then
            local nf=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            nf:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",0,cy)
            nf:SetText("|cff666666No data for "..armorType.."|r"); cy=cy-15
        else
            for _, slotData in ipairs(armorRows) do
                local slbl=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormal")
                slbl:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",0,cy)
                slbl:SetText("|cff888888— "..slotData.slot.." —|r"); cy=cy-14
                for _, item in ipairs(slotData.items) do ItemRow(item, slotData) end
                cy = cy - 4
            end
        end
        ovCnt:SetHeight(math.abs(cy)+20)
    end

    -- ================================================================
    -- CC/DR TABLE
    -- ================================================================
    -- ================================================================
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

        -- Cat name column is 128 px; spell list gets the rest
        local CAT_COL_W = 128
        local SP_COL_X  = PAD + CAT_COL_W
        local SP_COL_W  = OV_RCW - SP_COL_X - PAD
        -- Approximate chars that fit on one line at GameFontNormalSmall (~7 px/char)
        local CHARS_PER_LINE = math.floor(SP_COL_W / 7)

        for _,cat in ipairs(DR_CATEGORIES) do
            local entries=crossRef[cat.id]
            local catLbl=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            catLbl:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD,cy)
            catLbl:SetText("|cff"..cat.color..cat.name.."|r")

            local spellText, rawLen
            if cat.id=="SILENCE" then
                spellText = "|cffFF4444NO DR in TBC — chain freely|r"
                rawLen    = 32
            elseif entries and #entries>0 then
                local spells={}
                for _,e in ipairs(entries) do spells[#spells+1]=e.spell end
                local joined = table.concat(spells,"  ·  ")
                spellText = "|cffCCCCCC"..joined.."|r"
                rawLen    = #joined
            else
                spellText = "|cff555555(none)|r"
                rawLen    = 6
            end

            local spFS=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            spFS:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",SP_COL_X,cy)
            spFS:SetWidth(SP_COL_W)
            spFS:SetText(spellText)

            -- Advance by estimated wrapped height so rows never collide
            local lines = math.max(1, math.ceil(rawLen / CHARS_PER_LINE))
            cy = cy - (lines * 13 + 5)
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
                    local clsFS=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                    clsFS:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD+8,cy)
                    clsFS:SetText("|cffFFD700"..e.class.."|r")
                    local spFS=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                    spFS:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD+88,cy)
                    spFS:SetText("|cffFFFFFF"..e.spell.."|r")
                    local durFS=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                    durFS:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD+250,cy)
                    durFS:SetText("|cffAAAAAA"..e.dur.."|r")
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
                "Calculator — live ratings, AP calc, rating target\n"..
                "Honor — current honor, marks, weekly plan, gear checklist\n"..
                "Arena Gear — S1/S2 armor icons + AP/rating costs  (S1/S2 + class buttons)\n"..
                "Weapons — all PvP weapons, relics, off-hands  (S1/S2 toggle)\n"..
                "Honor Gear — S1/S2 honor costs, auto-detects your class\n"..
                "My Gear — paper-doll gear view, PvP status per slot, live combat stats\n"..
                "CC/DR Table — quick reference + full breakdown for all classes\n"..
                "Help — this guide"},
            {hdr="Arena Point Calculator  ( /ba calc )",body=
                "Enter any rating to simulate AP. Banked AP shown so you can track progress."},
            {hdr="Character Viewer  ( /ba chars )",body=
                "Tracks AP/honor/rating for all your characters. Any character that logs in\n"..
                "with BeanArena installed will appear in the Viewing dropdown."},
            {hdr="Slash Commands",body=
                "/ba calc [#]    AP for all brackets\n"..
                "/ba honor [slot] Honor gear cost + your progress\n"..
                "/ba arena [slot] Arena gear cost + your progress\n"..
                "/ba dr [class]  CC & DR list for a class\n"..
                "/ba marks       BG mark counts\n"..
                "/ba help        All commands"},
            {hdr="Tips",body=
                "BeanArena opens alongside the PvP panel (H key) automatically.\n"..
                "Minimap: left-click = main window, middle-click = commands.\n"..
                "/ba calc 1750 checks AP for any rating.\n"..
                "/ba dr mage lists Mage CC + DR categories.\n"..
                "Frame position is saved between sessions."},
        }
        local cy=-8; local PAD_L=6
        for _,sec in ipairs(INFO_SECTIONS) do
            local hdrFS=ovCnt:CreateFontString(nil,"OVERLAY","GameFontNormal")
            hdrFS:SetPoint("TOPLEFT",ovCnt,"TOPLEFT",PAD_L,cy)
            hdrFS:SetText("|cffFFD700"..sec.hdr.."|r"); cy=cy-18
            for line in (sec.body.."\n"):gmatch("([^\n]*)\n") do
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
    -- MY GEAR PAGE  — character-pane style layout
    -- ================================================================

    -- Which character snapshot is being shown in My Gear (nil = live player)
    local myGearSnap = nil

    -- PvP stat helpers.
    -- CR_* globals may be nil at file-load time (before ADDON_LOADED) so all IDs
    -- are evaluated at CALL time.  Each function checks the WoW global first then
    -- falls back to the known TBC numeric value.
    local function CR(global, fallback)
        local v = rawget(_G, global)
        return (type(v) == "number" and v > 0) and v or fallback
    end

    local function GetResilienceRating()
        if not GetCombatRating then return 0 end
        -- Valid range confirmed 1-32 in TBC Anniversary client.
        -- Try all three crit-taken IDs; use pcall to skip any out-of-range ones.
        for _, id in ipairs({
            CR("CR_CRIT_TAKEN_SPELL", 17),
            CR("CR_CRIT_TAKEN_RANGED", 16),
            CR("CR_CRIT_TAKEN_MELEE", 15),
        }) do
            if type(id) == "number" and id >= 1 and id <= 32 then
                local ok, v = pcall(GetCombatRating, id)
                if ok and (v or 0) > 0 then return v end
            end
        end
        return 0
    end
    local function GetSpellDmgBonus()
        if not GetSpellBonusDamage then return 0 end
        local best = 0
        for s = 2, 7 do
            local v = GetSpellBonusDamage(s) or 0
            if v > best then best = v end
        end
        return best
    end
    local function GetSpellHealBonus()
        if GetSpellBonusHealing then return GetSpellBonusHealing() or 0 end
        return 0
    end
    local function GetHitRatingVal()
        if not GetCombatRating then return 0 end
        return GetCombatRating(CR("CR_HIT_SPELL", 8)) or 0
    end
    local function GetMeleeHitRatingVal()
        if not GetCombatRating then return 0 end
        return GetCombatRating(CR("CR_HIT_MELEE", 6)) or 0
    end
    local function GetCritRatingVal()
        if not GetCombatRating then return 0 end
        return GetCombatRating(CR("CR_CRIT_SPELL", 11)) or 0
    end
    local function GetMeleeCritRatingVal()
        if not GetCombatRating then return 0 end
        return GetCombatRating(CR("CR_CRIT_MELEE", 9)) or 0
    end
    local function GetManaRegen5()
        if GetManaRegen then return math.floor((GetManaRegen() or 0) * 5) end
        return 0
    end
    local function GetMeleeAPVal()
        if UnitAttackPower then
            local base, pos, neg = UnitAttackPower("player")
            return math.max(0, (base or 0) + (pos or 0) + (neg or 0))
        end
        return 0
    end
    local function GetRangedAPVal()
        if UnitRangedAttackPower then
            local base, pos, neg = UnitRangedAttackPower("player")
            return math.max(0, (base or 0) + (pos or 0) + (neg or 0))
        end
        return 0
    end
    local function GetRangedHitRatingVal()
        if not GetCombatRating then return 0 end
        return GetCombatRating(CR("CR_HIT_RANGED", 7)) or 0
    end

    -- Scan tooltip used to detect resilience when GetItemStats is unavailable/wrong key
    local _resiTT
    local function ItemHasResilience(link)
        if not link then return false end
        -- Try GetItemStats first; iterate keys so naming variations don't matter
        if GetItemStats then
            local ok, stats = pcall(function()
                local t = {}; GetItemStats(link, t); return t
            end)
            if ok and stats then
                for k, v in pairs(stats) do
                    if type(k) == "string" and k:upper():find("RESIL")
                       and (tonumber(v) or 0) > 0 then
                        return true
                    end
                end
            end
        end
        -- Fallback: hidden tooltip scan for "Resilience" text
        if not _resiTT then
            _resiTT = CreateFrame("GameTooltip", "BeanArenaResiScanTT",
                                  nil, "GameTooltipTemplate")
            _resiTT:SetOwner(WorldFrame, "ANCHOR_NONE")
        end
        pcall(_resiTT.SetHyperlink, _resiTT, link)
        for i = 1, (_resiTT:NumLines() or 0) do
            local line = _G["BeanArenaResiScanTTTextLeft" .. i]
            if line and (line:GetText() or ""):lower():find("resilience") then
                return true
            end
        end
        return false
    end

    -- Returns status code for a slot.
    -- dismissed overrides pvp_good → marked so users can light-check any slot.
    local function GetSlotStatus(slotID, link, dismissed)
        if not link then return "empty" end
        if ItemHasResilience(link) then
            if dismissed[slotID] then return "marked" end
            return "pvp_good"
        end
        if dismissed[slotID] then return "marked" end
        return "pve"
    end

    -- Draws a WoW ready-check style indicator texture
    local function DrawStatusIndicator(parent, status, x, y, sz)
        sz = sz or 14
        local ic = parent:CreateTexture(nil, "OVERLAY")
        ic:SetSize(sz, sz)
        ic:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        if status == "pvp_good" then
            -- Bright green checkmark
            ic:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            ic:SetVertexColor(0.2, 1.0, 0.2, 1.0)
        elseif status == "pve" then
            -- Red X — no resilience, not dismissed
            ic:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        elseif status == "marked" then
            -- Light green checkmark — user acknowledged non-pvp slot
            ic:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            ic:SetVertexColor(0.55, 0.90, 0.55, 0.85)
        end
        return ic
    end

    local function BuildCharPlanContent()
        ClearContent()

        local IC     = 18
        local IC_PAD = 2
        local IND_SZ = 12
        local CELL_H = IC + 4
        local ROWS   = 7

        local SIDE_COL_W = IND_SZ + IC_PAD + IC + 4
        local CENTER_W   = OV_RCW - SIDE_COL_W * 2
        local L_ICON_X   = 0
        local L_IND_X    = IC + IC_PAD
        local R_ICON_X   = OV_RCW - SIDE_COL_W + IND_SZ + IC_PAD
        local R_IND_X    = OV_RCW - SIDE_COL_W
        local C_X        = SIDE_COL_W

        -- Character dropdown at top
        local ddBtn = CreateFrame("Button", nil, ovCnt, "UIPanelButtonTemplate")
        ddBtn:SetSize(OV_RCW, 20)
        ddBtn:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", 0, -2)
        ddBtn:GetFontString():SetFontObject("GameFontNormalSmall")

        local function UpdateDDText()
            if myGearSnap == nil then
                ddBtn:SetText("|cffFFD700" .. (CHAR_NAME or "?") .. " (you)|r")
            else
                ddBtn:SetText(myGearSnap.name)
            end
        end
        UpdateDDText()

        local gearCharDD = CreateFrame("Frame", "BeanArenaGearCharDD", UIParent, "UIDropDownMenuTemplate")
        ddBtn:SetScript("OnClick", function(self)
            UIDropDownMenu_Initialize(gearCharDD, function()
                local info = UIDropDownMenu_CreateInfo()
                info.text = "|cffFFD700" .. (CHAR_NAME or "Current") .. " (you)|r"
                info.notCheckable = false
                info.checked = (myGearSnap == nil)
                info.func = function()
                    myGearSnap = nil
                    CloseDropDownMenus()
                    SwitchPage("My Gear")
                end
                UIDropDownMenu_AddButton(info)
                local chars = BeanArenaDB.chars or {}
                local rows = {}
                for _, snap in pairs(chars) do
                    if type(snap) == "table" and snap.name then
                        if not (snap.name == CHAR_NAME and snap.realm == CHAR_REALM) then
                            rows[#rows+1] = snap
                        end
                    end
                end
                table.sort(rows, function(a,b) return (a.name or "") < (b.name or "") end)
                for _, snap in ipairs(rows) do
                    local i = UIDropDownMenu_CreateInfo()
                    i.text = snap.name .. " |cff888888(" .. (snap.realm or "?") .. ")|r"
                    i.notCheckable = false
                    i.checked = (myGearSnap and myGearSnap.name == snap.name)
                    local capSnap = snap
                    i.func = function()
                        myGearSnap = capSnap
                        CloseDropDownMenus()
                        SwitchPage("My Gear")
                    end
                    UIDropDownMenu_AddButton(i)
                end
            end, "MENU")
            ToggleDropDownMenu(1, nil, gearCharDD, self, 0, -4)
        end)

        local divTex = ovCnt:CreateTexture(nil, "ARTWORK")
        divTex:SetSize(OV_RCW, 1); divTex:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", 0, -24)
        divTex:SetColorTexture(0.3, 0.3, 0.3, 0.5)

        local gearTop = -28
        local isLive  = (myGearSnap == nil)
        local dismissed = (BeanArenaCharDB.charPlan and BeanArenaCharDB.charPlan.dismissed) or {}

        local function DrawGearSlot(slotDef, iconX, indicatorX, gy)
            local slotID = slotDef.id
            local link, tex
            if isLive then
                link = GetInventoryItemLink("player", slotID)
                tex  = GetInventoryItemTexture("player", slotID)
            else
                -- Use saved gear links from the character snapshot
                link = myGearSnap.gearLinks and myGearSnap.gearLinks[slotID] or nil
                if link then
                    local _, _, _, _, _, _, _, _, _, t = GetItemInfo(link)
                    tex = t
                end
            end

            local iconBtn = CreateFrame("Button", nil, ovCnt)
            iconBtn:SetSize(IC, IC)
            iconBtn:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", iconX, gy)

            local bg = iconBtn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(); bg:SetColorTexture(0.10, 0.10, 0.12, 1)

            local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
            iconTex:SetAllPoints()
            if tex then
                iconTex:SetTexture(tex)
            else
                iconTex:SetTexture("Interface\\PaperDollInfoFrame\\UI-Backpack-EmptySlot")
                iconTex:SetVertexColor(0.35, 0.35, 0.35, 0.5)
            end
            iconBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

            local capName = slotDef.name
            if link then
                local capLink = link
                iconBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(capLink)
                    GameTooltip:Show()
                end)
                iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                iconBtn:SetScript("OnClick", function()
                    if IsShiftKeyDown() then
                        local _, iLink = GetItemInfo(capLink)
                        if iLink and ChatEdit_InsertLink then ChatEdit_InsertLink(iLink) end
                    end
                end)
            else
                iconBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("|cff666666" .. capName .. " (empty)|r")
                    GameTooltip:Show()
                end)
                iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end

            local status  = GetSlotStatus(slotID, link, dismissed)
            -- For empty slots that have been dismissed, show a light-green check
            local drawStatus = status
            if status == "empty" and dismissed[slotID] then drawStatus = "marked" end
            local indOffY = gy - (IC / 2) + (IND_SZ / 2) - 1
            DrawStatusIndicator(ovCnt, drawStatus, indicatorX, indOffY, IND_SZ)

            do  -- click area on ALL slots, regardless of status
                local capID     = slotID
                local capStatus = drawStatus   -- use the display status, not raw status
                local clickArea = CreateFrame("Button", nil, ovCnt)
                clickArea:SetSize(IND_SZ + 4, IND_SZ + 4)
                clickArea:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", indicatorX - 2, indOffY + 2)
                clickArea:SetScript("OnClick", function()
                    BeanArenaCharDB.charPlan = BeanArenaCharDB.charPlan or { dismissed = {} }
                    if BeanArenaCharDB.charPlan.dismissed[capID] then
                        BeanArenaCharDB.charPlan.dismissed[capID] = nil
                    else
                        BeanArenaCharDB.charPlan.dismissed[capID] = true
                    end
                    SwitchPage("My Gear")
                end)
                clickArea:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if capStatus == "pvp_good" then
                        GameTooltip:SetText("|cff00FF00PvP Item|r\n|cffAAAAAAClick to light-check|r")
                    elseif capStatus == "pve" then
                        GameTooltip:SetText("|cffFF6666No Resilience|r\n|cffAAAAAAPvE item — click to mark as OK|r")
                    elseif capStatus == "marked" then
                        GameTooltip:SetText("|cff88FF88Marked OK|r\n|cffAAAAAAClick to un-mark|r")
                    else
                        GameTooltip:SetText("|cff666666Empty slot|r\n|cffAAAAAAClick to mark as intentionally empty|r")
                    end
                    GameTooltip:Show()
                end)
                clickArea:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
        end

        -- Left column
        for _, slotDef in ipairs(GEAR_LAYOUT) do
            if slotDef.col == "L" then
                local gy = gearTop - (slotDef.row - 1) * (CELL_H + 2)
                DrawGearSlot(slotDef, L_ICON_X, L_IND_X, gy)
            end
        end

        -- Right column
        for _, slotDef in ipairs(GEAR_LAYOUT) do
            if slotDef.col == "R" then
                local gy = gearTop - (slotDef.row - 1) * (CELL_H + 2)
                DrawGearSlot(slotDef, R_ICON_X, R_IND_X, gy)
            end
        end

        -- Center stats panel
        local sx = C_X + 4
        local sy = gearTop - 2
        local SW = CENTER_W - 8

        local function StatHdr(txt)
            local f = ovCnt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            f:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", sx, sy)
            f:SetText("|cff00CCFF" .. txt .. "|r"); f:SetWidth(SW)
            sy = sy - 14
        end
        local function StatDiv()
            local d = ovCnt:CreateTexture(nil, "ARTWORK")
            d:SetSize(SW, 1); d:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", sx, sy - 1)
            d:SetColorTexture(0.25, 0.25, 0.25, 0.8); sy = sy - 5
        end
        local function StatRow(label, value, col)
            local lbl = ovCnt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", sx, sy)
            lbl:SetText("|cff888888" .. label .. "|r")
            local val = ovCnt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            val:SetPoint("TOPRIGHT", ovCnt, "TOPLEFT", sx + SW, sy)
            val:SetJustifyH("RIGHT")
            val:SetText("|cff" .. (col or "EEEEEE") .. tostring(value) .. "|r")
            sy = sy - 13
        end

        if isLive then
            StatHdr("PvP Stats")
            StatDiv()
            StatRow("Resilience",  GetResilienceRating(),   "FF9900")
            StatDiv()
            StatRow("Spell Dmg",   GetSpellDmgBonus(),      "88CCFF")
            StatRow("Healing",     GetSpellHealBonus(),     "00EE88")
            StatRow("Spell Hit",   GetHitRatingVal(),       "FFD700")
            StatRow("Spell Crit",  GetCritRatingVal(),      "FFD700")
            StatRow("Mana /5s",    GetManaRegen5(),         "88FFFF")
            StatDiv()
            StatRow("Melee AP",    GetMeleeAPVal(),         "FF8844")
            StatRow("Melee Hit",   GetMeleeHitRatingVal(),  "FFD700")
            StatRow("Melee Crit",  GetMeleeCritRatingVal(), "FFD700")
            StatDiv()
            StatRow("Ranged AP",   GetRangedAPVal(),        "FF8844")
            StatRow("Ranged Hit",  GetRangedHitRatingVal(), "FFD700")
        else
            StatHdr(myGearSnap.name)
            StatDiv()
            local ts = myGearSnap.lastSeen and date("%Y-%m-%d", myGearSnap.lastSeen) or "?"
            StatRow("Last Seen",  ts,                            "888888")
            StatRow("Arena Pts",  myGearSnap.arenaPoints or 0,  "88FF88")
            StatRow("Honor",      myGearSnap.honor or 0,        "FFD700")
            StatDiv()
            StatRow("2v2",        myGearSnap.r2 or 0,           "AADDFF")
            StatRow("3v3",        myGearSnap.r3 or 0,           "AADDFF")
            sy = sy - 6
            local noteFS = ovCnt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noteFS:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", sx, sy)
            noteFS:SetWidth(SW); noteFS:SetJustifyH("CENTER")
            noteFS:SetText("|cff555555Gear from last\nlogin snapshot.|r")
        end

        -- Bottom row: weapon slots
        local bottomY  = gearTop - ROWS * (CELL_H + 2) - 4
        local wepXPositions = {
            L_ICON_X,
            C_X + (CENTER_W / 2) - (IC / 2),
            R_ICON_X,
        }
        local wepIndPositions = {
            L_IND_X,
            C_X + (CENTER_W / 2) - (IC / 2) + IC + IC_PAD,
            R_IND_X,
        }
        local wi = 1
        for _, slotDef in ipairs(GEAR_LAYOUT) do
            if slotDef.col == "B" then
                DrawGearSlot(slotDef, wepXPositions[wi], wepIndPositions[wi], bottomY)
                wi = wi + 1
            end
        end

        -- Legend
        local legendY = bottomY - CELL_H - 6
        local function LegendItem(lx, status, label)
            DrawStatusIndicator(ovCnt, status, lx, legendY, 10)
            local lf = ovCnt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lf:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", lx + 12, legendY + 1)
            lf:SetText("|cff777777" .. label .. "|r")
        end
        LegendItem(0,            "pvp_good", "Good")
        LegendItem(60,           "pve",      "No Resil")
        LegendItem(130,          "marked",   "Marked OK")

        -- ── Stats section below legend ───────────────────────────────────
        local COL_W = OV_RCW / 2
        local bsY   = legendY - 22

        local function BsHdr(txt)
            local f = ovCnt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            f:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", 0, bsY)
            f:SetText("|cff00CCFF" .. txt .. "|r")
            bsY = bsY - 15
            local d = ovCnt:CreateTexture(nil, "ARTWORK")
            d:SetSize(OV_RCW, 1); d:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", 0, bsY)
            d:SetColorTexture(0.3, 0.3, 0.3, 0.5); bsY = bsY - 6
        end
        local function BsRow(ox, label, value, color)
            local lbl = ovCnt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", ox, bsY)
            lbl:SetText("|cff888888" .. label .. "|r")
            local val = ovCnt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            val:SetPoint("TOPRIGHT", ovCnt, "TOPLEFT", ox + COL_W - 4, bsY)
            val:SetJustifyH("RIGHT")
            val:SetText("|cff" .. (color or "EEEEEE") .. tostring(value) .. "|r")
        end
        local function BsPair(l1, v1, c1, l2, v2, c2)
            BsRow(0,     l1, v1, c1)
            BsRow(COL_W, l2, v2, c2)
            bsY = bsY - 13
        end

        if isLive then
            BsHdr("Character Stats")
            local sta = UnitStat and (UnitStat("player", 3)) or 0
            local str = UnitStat and (UnitStat("player", 1)) or 0
            local agi = UnitStat and (UnitStat("player", 2)) or 0
            local int = UnitStat and (UnitStat("player", 4)) or 0
            local spi = UnitStat and (UnitStat("player", 5)) or 0
            BsPair("Resilience",  GetResilienceRating(),   "FF9900",
                   "Stamina",     sta,                     "FFFFFF")
            BsPair("Spell Power", GetSpellDmgBonus(),      "88CCFF",
                   "Healing",     GetSpellHealBonus(),     "00EE88")
            BsPair("Melee AP",    GetMeleeAPVal(),         "FF8844",
                   "Ranged AP",   GetRangedAPVal(),        "FF8844")
            BsPair("Strength",    str,                     "FFAAAA",
                   "Agility",     agi,                     "AAFFAA")
            BsPair("Intellect",   int,                     "88CCFF",
                   "Spirit",      spi,                     "AAAAFF")
            BsPair("Melee Hit",   GetMeleeHitRatingVal(),  "FFD700",
                   "Spell Hit",   GetHitRatingVal(),       "FFD700")
            BsPair("Melee Crit",  GetMeleeCritRatingVal(), "FFD700",
                   "Spell Crit",  GetCritRatingVal(),      "FFD700")
            BsPair("Mana /5s",    GetManaRegen5(),         "88FFFF",
                   "Ranged Hit",  GetRangedHitRatingVal(), "FFD700")
        else
            BsHdr(myGearSnap.name .. " — Snapshot")
            local ts = myGearSnap.lastSeen and date("%Y-%m-%d", myGearSnap.lastSeen) or "?"
            BsRow(0, "Last Seen", ts, "888888"); bsY = bsY - 13
            BsPair("Arena Pts", myGearSnap.arenaPoints or 0, "88FF88",
                   "Honor",     myGearSnap.honor or 0,       "FFD700")
            BsPair("2v2", myGearSnap.r2 or 0, "AADDFF",
                   "3v3", myGearSnap.r3 or 0, "AADDFF")
        end

        ovCnt:SetHeight(math.abs(bsY) + 20)
    end

    -- ================================================================
    -- TEAM BGS PAGE
    -- ================================================================
    BeanArena_RefreshTeamBGPage = nil  -- forward decl, assigned below

    local function BuildTeamBGContent()
        ClearContent()
        local cy  = -2
        local PAD = 4
        local fmt = BreakUpLargeNumbers or tostring

        -- ── Buttons ───────────────────────────────────────────────
        local shareBtn = CreateFrame("Button", nil, ovCnt, "UIPanelButtonTemplate")
        shareBtn:SetSize(110, 22)
        shareBtn:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", 0, cy)
        shareBtn:GetFontString():SetFontObject("GameFontNormalSmall")
        shareBtn:SetText("Share Mine")
        shareBtn:SetScript("OnClick", function()
            local fmt    = BreakUpLargeNumbers or tostring
            local honor  = GetCurrentHonor()
            local marks  = GetPvPMarkCounts()
            local name   = CHAR_NAME or UnitName("player") or "Me"
            local channel = IsInGroup() and "PARTY" or "SAY"
            -- Addon message syncs data to other BeanArena users
            local payload = string.format("BGDATA:%d:%d:%d:%d:%d",
                honor, marks.AV or 0, marks.WSG or 0, marks.AB or 0, marks.EotS or 0)
            BA_SendAddonMsg(BA_MSG_PREFIX, payload, channel)
            -- Chat message for visible confirmation
            SendChatMessage(string.format("[BA] %s - Honor: %s  AV:%d WSG:%d AB:%d EotS:%d",
                name, fmt(honor),
                marks.AV or 0, marks.WSG or 0, marks.AB or 0, marks.EotS or 0), channel)
            -- Write own data locally (addon messages not echoed back to sender)
            BeanArenaDB.teamBG = BeanArenaDB.teamBG or {}
            BeanArenaDB.teamBG[name] = {
                honor=honor, AV=marks.AV or 0, WSG=marks.WSG or 0,
                AB=marks.AB or 0, EotS=marks.EotS or 0, timestamp=time(),
            }
            SwitchPage("Team BGs")
        end)

        local printBtn = CreateFrame("Button", nil, ovCnt, "UIPanelButtonTemplate")
        printBtn:SetSize(110, 22)
        printBtn:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", 118, cy)
        printBtn:GetFontString():SetFontObject("GameFontNormalSmall")
        printBtn:SetText("Print Party")
        printBtn:SetScript("OnClick", function()
            if not IsInGroup() then
                print("|cffFFD700[BA]|r Not in a party.")
                return
            end
            -- Print self first (player unit is not in party1..N)
            local selfMarksP = GetPvPMarkCounts()
            local selfName = CHAR_NAME or UnitName("player") or "Me"
            SendChatMessage(string.format(
                "[BA] %s - Honor: %s  AV:%d WSG:%d AB:%d EotS:%d",
                selfName, fmt(GetCurrentHonor()),
                selfMarksP.AV or 0, selfMarksP.WSG or 0,
                selfMarksP.AB or 0, selfMarksP.EotS or 0
            ), "PARTY")
            -- Print other party members
            local numMembers = GetNumGroupMembers()
            for i = 1, numMembers do
                local unit = "party"..i
                local memberName = UnitName(unit)
                if memberName then
                    local shortName = memberName:match("^([^%-]+)") or memberName
                    local data = BeanArenaDB.teamBG and BeanArenaDB.teamBG[shortName]
                    if data then
                        SendChatMessage(string.format(
                            "[BA] %s - Honor: %s  AV:%d WSG:%d AB:%d EotS:%d",
                            shortName, fmt(data.honor), data.AV, data.WSG, data.AB, data.EotS
                        ), "PARTY")
                    else
                        SendChatMessage(string.format(
                            "[BA] %s: BeanArena not installed", shortName
                        ), "PARTY")
                    end
                end
            end
        end)

        cy = cy - 28

        -- ── Divider + column headers ──────────────────────────────
        local function TBLine()
            local d = ovCnt:CreateTexture(nil, "ARTWORK")
            d:SetSize(OV_RCW, 1); d:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", 0, cy - 2)
            d:SetColorTexture(0.3, 0.3, 0.3, 0.5); cy = cy - 8
        end
        local COL = { name=0, honor=130, av=230, wsg=258, ab=286, eots=314, age=350 }
        local function CHdr(x, t)
            local f = ovCnt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            f:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", x, cy)
            f:SetText("|cffAAAAAA"..t.."|r")
        end
        TBLine()
        CHdr(COL.name,  "Name")
        CHdr(COL.honor, "Honor")
        CHdr(COL.av,    "AV")
        CHdr(COL.wsg,   "WSG")
        CHdr(COL.ab,    "AB")
        CHdr(COL.eots,  "EotS")
        CHdr(COL.age,   "Updated")
        cy = cy - 14
        TBLine()

        -- ── Not in party guard ────────────────────────────────────
        if not IsInGroup() then
            local nf = ovCnt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nf:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", PAD, cy)
            nf:SetText("|cff888888Not in a party.|r")
            ovCnt:SetHeight(math.abs(cy) + 20)
            return
        end

        -- ── Build rows ────────────────────────────────────────────
        local myName = CHAR_NAME or UnitName("player") or ""
        local baRows, noBARows = {}, {}
        local numMembers = GetNumGroupMembers()

        for i = 1, numMembers do
            local memberName = UnitName("party"..i)
            if memberName then
                local shortName = memberName:match("^([^%-]+)") or memberName
                local data = BeanArenaDB.teamBG and BeanArenaDB.teamBG[shortName]
                if data then
                    baRows[#baRows+1] = { name=shortName, data=data }
                else
                    noBARows[#noBARows+1] = shortName
                end
            end
        end

        -- Self row uses live data
        local selfMarks = GetPvPMarkCounts()
        local selfData = {
            honor     = GetCurrentHonor(),
            AV        = selfMarks.AV   or 0,
            WSG       = selfMarks.WSG  or 0,
            AB        = selfMarks.AB   or 0,
            EotS      = selfMarks.EotS or 0,
            timestamp = time(),
        }
        table.sort(baRows, function(a,b) return (a.data.honor or 0) > (b.data.honor or 0) end)

        local function DrawRow(name, data, isMe)
            local nameCol = isMe and "|cffFFD700"..name.."|r" or "|cffCCCCCC"..name.."|r"
            local function RF(x, t, col)
                local f = ovCnt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                f:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", x, cy)
                f:SetText(col and ("|cff"..col..t.."|r") or t)
            end
            local age = data.timestamp and (time() - data.timestamp) or 0
            local ageStr = age < 10 and "just now" or (age.."s ago")
            RF(COL.name,  nameCol)
            RF(COL.honor, fmt(data.honor),    "FFD700")
            RF(COL.av,    tostring(data.AV),  "AAAAAA")
            RF(COL.wsg,   tostring(data.WSG), "AAAAAA")
            RF(COL.ab,    tostring(data.AB),  "AAAAAA")
            RF(COL.eots,  tostring(data.EotS),"AAAAAA")
            RF(COL.age,   ageStr,             "555555")
            cy = cy - 16
        end

        DrawRow(myName, selfData, true)
        for _, row in ipairs(baRows) do
            DrawRow(row.name, row.data, false)
        end
        for _, name in ipairs(noBARows) do
            local f = ovCnt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            f:SetPoint("TOPLEFT", ovCnt, "TOPLEFT", 0, cy)
            f:SetWidth(OV_RCW)
            f:SetText("|cff555555"..name..": BeanArena not installed|r")
            cy = cy - 16
        end

        TBLine()
        ovCnt:SetHeight(math.abs(cy) + 20)
    end

    BeanArena_RefreshTeamBGPage = function()
        if refFrame:IsShown() and ovSection == "Team BGs" then
            BuildTeamBGContent()
        end
    end

    -- ================================================================
    -- SwitchPage dispatcher
    -- ================================================================
    SwitchPage = function(name)
        ovSection = name
        local hasSeasons=(name=="Arena Gear" or name=="Weapons")
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
            local savedSeason = ovSeason  -- preserve caller's season for Arena Gear / Weapons
            ovSeason = 2                  -- Honor Gear only has S2 data
            local _,cf=UnitClass("player")
            local cm={WARRIOR="Warrior",PALADIN="Paladin",HUNTER="Hunter",ROGUE="Rogue",
                      PRIEST="Priest",SHAMAN="Shaman",MAGE="Mage",WARLOCK="Warlock",DRUID="Druid"}
            ovClass=cm[cf or ""] or "Warrior"; ovClassBtn:SetText(ovClass)
            for _,list in ipairs({S2_HONOR_UNIVERSAL}) do
                for _,slot in ipairs(list) do
                    for _,item in ipairs(slot.items) do GetItemInfo(item.id) end
                end
            end
            for _,armorList in pairs(S2_HONOR_BYARMOR) do
                for _,slot in ipairs(armorList) do
                    for _,item in ipairs(slot.items) do GetItemInfo(item.id) end
                end
            end
            BuildHonorContent()
            ovSeason = savedSeason        -- restore so Arena Gear / Weapons keep their season
        elseif name=="My Gear" then
            -- Pre-cache alt's items so icons and tooltips load
            if myGearSnap and myGearSnap.gearLinks then
                for _, link in pairs(myGearSnap.gearLinks) do
                    GetItemInfo(link)
                end
            end
            BuildCharPlanContent()
        elseif name=="Team BGs" then
            BuildTeamBGContent()
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
                    ovClass=cls; ovClassBtn:SetText(cls)
                    BuildArenaContent(); CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info)
            end
        end,"MENU")
        ToggleDropDownMenu(1,nil,ovClassDD,self,0,-4)
    end)

    BeanArena_OpenRefFrame = function(section)
        if section == "Calculator" then
            refFrame:Hide()
            if not frame:IsShown() then OpenBeanArena() end
            return
        end
        -- Open main window too if it's not visible
        if not frame:IsShown() then OpenBeanArena() end
        -- Position refFrame next to main frame on first open
        if not refFrame:IsShown() then
            refFrame:ClearAllPoints()
            refFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
        end
        local _,cf = UnitClass("player")
        local cm = { WARRIOR="Warrior", PALADIN="Paladin", HUNTER="Hunter", ROGUE="Rogue",
                     PRIEST="Priest", SHAMAN="Shaman", MAGE="Mage", WARLOCK="Warlock", DRUID="Druid" }
        ovClass = cm[cf or ""] or "Warrior"; ovClassBtn:SetText(ovClass)
        SwitchPage(section)
        rfSectionFS:SetText("|cff888888"..section.."|r")
        refFrame:Show()
    end

    BeanArena_RefreshRefFrame = function()
        -- Only Honor and Team BGs live-update on the 5-second ticker.
        -- All other pages are static to avoid GetChildren() stack overflow.
        if refFrame:IsShown() and ovSection == "Honor" then
            RefreshHonorPage()
        elseif refFrame:IsShown() and ovSection == "Team BGs" then
            BeanArena_RefreshTeamBGPage()
        end
    end

    -- Rebuilds My Gear when UNIT_INVENTORY_CHANGED fires for "player".
    BeanArena_RefreshCharPlan = function()
        if refFrame:IsShown() and ovSection == "My Gear" then
            SwitchPage("My Gear")
        end
    end

    -- Called ONCE when GET_ITEM_INFO_RECEIVED fires, to refresh icon textures on
    -- non-Honor pages (item info wasn't cached on first build so icons were blank).
    BeanArena_RebuildRefPage = function()
        if refFrame:IsShown() and ovSection ~= "Honor" then
            SwitchPage(ovSection)
        end
    end
end

-- ============================================================
-- SLASH COMMANDS  ( /ba  and  /beanarena )
-- ============================================================
SLASH_BEANARENA1 = "/ba"; SLASH_BEANARENA2 = "/beanarena"
SlashCmdList["BEANARENA"] = function(msg)
    msg = (msg or ""):lower():trim()
    local cmd, args = msg:match("^(%S+)%s*(.*)$")
    if not cmd then cmd = ""; args = "" end

    local BA = "|cffFFD700[BA]|r"

    local function Toggle(f, anchorTo)
        if f:IsShown() then f:Hide()
        else
            f:ClearAllPoints()
            if anchorTo then f:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT", 6, 0)
            else              f:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
            f:Show()
        end
    end

    -- ── /ba  or  /ba show ─────────────────────────────────────
    if cmd == "" or cmd == "show" then
        if frame:IsShown() then frame:Hide() else OpenBeanArena() end

    -- ── /ba honor [slot] ──────────────────────────────────────
    -- No arg: open Honor window.  With arg: print cost info for that slot.
    elseif cmd == "honor" then
        if args == "" then
            OpenBeanArena(); BeanArena_OpenRefFrame("Honor")
        else
            local search = args:lower()
            local found = false
            for _, g in ipairs(HONOR_GEAR_FULL) do
                if g.slot:lower():find(search, 1, true) then
                    found = true
                    local honor = GetCurrentHonor()
                    local marks = GetPvPMarkCounts()
                    local have  = honor
                    local need  = g.honor
                    local pct   = math.min(100, math.floor(have / need * 100))
                    local diff  = math.max(0, need - have)
                    local markParts = {}
                    for bg, req in pairs(g.marks) do
                        local h = marks[bg] or 0
                        local mdiff = math.max(0, req - h)
                        local col = h >= req and "00FF00" or "FF4444"
                        markParts[#markParts+1] = string.format("|cff%s%d|r|cffAAAAAA/%d|r %s", col, h, req, bg)
                        if mdiff > 0 then markParts[#markParts] = markParts[#markParts] .. string.format(" |cffFF4444(-%d)|r", mdiff) end
                    end
                    print(string.format("%s Honor Gear: |cffFFD700%s|r", BA, g.slot))
                    print(string.format("  Cost: |cffFFD700%d|r honor  |cffAAAAAA(you have %d — %d%%)|r", need, have, pct))
                    if diff > 0 then
                        print(string.format("  Need: |cffFF4444%d|r more honor  (~|cffAAAAAA%d|r AV wins)", diff, math.ceil(diff/419)))
                    else
                        print("  Honor: |cff00FF00Ready!|r")
                    end
                    print("  Marks: " .. table.concat(markParts, "  "))
                end
            end
            if not found then
                print(BA .. " No honor gear found for: |cffFF4444" .. args .. "|r")
                print("  Slots: Neck, Ring, Bracers, Belt, Boots")
            end
        end

    -- ── /ba arena [slot] ──────────────────────────────────────
    -- No arg: open Arena Gear window.  With arg: print cost info for that slot.
    elseif cmd == "arena" then
        if args == "" then
            BeanArena_OpenRefFrame("Arena Gear")
        else
            local search = args:lower()
            local found = false
            local curAP = GetCurrentArenaPoints()
            for _, g in ipairs(ARENA_GEAR_FULL) do
                if g.slot:lower():find(search, 1, true) then
                    found = true
                    local pct  = math.min(100, math.floor(curAP / g.ap * 100))
                    local diff = math.max(0, g.ap - curAP)
                    print(string.format("%s Arena Gear: |cffFFD700%s|r", BA, g.slot))
                    print(string.format("  Cost: |cffFFD700%d AP|r  |cffAAAAAA(you have %d — %d%%)|r", g.ap, curAP, pct))
                    if diff > 0 then
                        print(string.format("  Need: |cffFF4444%d|r more AP", diff))
                    else
                        print("  AP: |cff00FF00Ready!|r")
                    end
                    if g.rating > 0 then
                        local r2,r3,r5 = GetLiveRatings()
                        local best = math.max(r2,r3,r5)
                        local rCol = best >= g.rating and "00FF00" or "FF4444"
                        print(string.format("  Rating req: |cff%s%d|r  |cffAAAAAA(your best: %d)|r", rCol, g.rating, best))
                    else
                        print("  Rating req: |cff00FF00None|r")
                    end
                end
            end
            if not found then
                print(BA .. " No arena gear found for: |cffFF4444" .. args .. "|r")
                print("  Slots: Gloves, Helmet, Legs, Chest, Shoulders, Shield, Main-hand, etc.")
            end
        end

    -- ── /ba target <ap> ───────────────────────────────────────
    elseif cmd == "target" then
        local ap = tonumber(args)
        if not ap or ap <= 0 then
            print(BA .. " Usage: /ba target <arena points>  e.g. /ba target 1500")
        else
            print(string.format("%s Rating needed to earn |cffFFD700%d AP|r per week:", BA, ap))
            for _, bkt in ipairs({"2v2", "3v3", "5v5"}) do
                local r = CalcRatingForPoints(ap, bkt)
                if r == nil then
                    print(string.format("  %s: |cffFF4444Unreachable|r  |cffAAAAAA(bracket max ~%d AP)|r", bkt, BRACKET_MAX_AP[bkt]))
                elseif r == 0 then
                    print(string.format("  %s: |cff00FF00Any rating|r", bkt))
                else
                    print(string.format("  %s: |cffFFD700%d|r", bkt, r))
                end
            end
        end

    -- ── /ba calc [rating] ─────────────────────────────────────
    -- No arg: use live ratings.  With number: calc that rating for all brackets.
    elseif cmd == "calc" then
        local rating = tonumber(args)
        if rating then
            -- Single rating — show all 3 brackets
            print(string.format("%s Arena Points for rating |cffFFD700%d|r:", BA, rating))
            print(string.format("  2v2: |cffFFD700%.0f AP|r", CalcBracketPoints(rating, "2v2")))
            print(string.format("  3v3: |cffFFD700%.0f AP|r", CalcBracketPoints(rating, "3v3")))
            print(string.format("  5v5: |cffFFD700%.0f AP|r", CalcBracketPoints(rating, "5v5")))
        else
            -- No arg — use live ratings with game check
            local r2,r3,r5,g2,g3,g5 = GetLiveRatings()
            local curAP = GetCurrentArenaPoints()
            local er2=g2>=10 and r2 or 0; local er3=g3>=10 and r3 or 0; local er5=g5>=10 and r5 or 0
            local best, bb = CalcBestPoints(er2,er3,er5)
            print(string.format("%s AP Breakdown  |cffAAAAAA(Banked: %d)|r", BA, curAP))
            local function row(bracket, r, g, er)
                local eligible = er > 0
                local ap = CalcBracketPoints(r, bracket)
                local gstr = g >= 10 and string.format("|cff00FF00%dg|r", g)
                                      or  string.format("|cffFF4444%dg/10|r", g)
                print(string.format("  %s: %d  %s  |cffFFD700%.0f AP|r  total:|cff88FF88%.0f|r%s",
                    bracket, r, gstr, ap, curAP+ap,
                    eligible and "" or "  |cffAAAAAA(need 10 games)|r"))
            end
            row("2v2", r2, g2, er2)
            row("3v3", r3, g3, er3)
            row("5v5", r5, g5, er5)
            if best > 0 then
                print(string.format("  Best eligible: |cffFFD700%.0f AP|r from |cffFFD700%s|r", best, bb))
            end
        end

    -- ── /ba dr [class] ────────────────────────────────────────
    -- No arg: list all classes.  With class: print that class's CC and shared DRs.
    elseif cmd == "dr" or cmd == "cc" then
        if args == "" then
            BeanArena_OpenRefFrame("CC/DR Table")
        else
            -- Match class name (partial ok)
            local search = args:lower()
            local matchClass, matchData = nil, nil
            for cls, data in pairs(CLASS_CC) do
                if cls:lower():find(search, 1, true) then
                    matchClass = cls; matchData = data; break
                end
            end
            if not matchClass then
                print(BA .. " Unknown class: |cffFF4444" .. args .. "|r")
                local cls_list = {}
                for c in pairs(CLASS_CC) do cls_list[#cls_list+1] = c end
                table.sort(cls_list)
                print("  Classes: " .. table.concat(cls_list, ", "))
            else
                print(string.format("%s DR table for |cffFFD700%s|r:", BA, matchClass))
                -- Group by DR category
                local byDR = {}
                for _, cc in ipairs(matchData) do
                    byDR[cc.dr] = byDR[cc.dr] or {}
                    table.insert(byDR[cc.dr], cc)
                end
                for drId, spells in pairs(byDR) do
                    -- Find DR category info
                    local catName, catColor = drId, "AAAAAA"
                    for _, cat in ipairs(DR_CATEGORIES) do
                        if cat.id == drId then catName = cat.name; catColor = cat.color; break end
                    end
                    -- Collect all OTHER classes that share this DR
                    local sharedWith = {}
                    for cls2, data2 in pairs(CLASS_CC) do
                        if cls2 ~= matchClass then
                            for _, cc2 in ipairs(data2) do
                                if cc2.dr == drId then
                                    sharedWith[cls2] = true; break
                                end
                            end
                        end
                    end
                    local shareList = {}
                    for c in pairs(sharedWith) do shareList[#shareList+1] = c end
                    table.sort(shareList)
                    local shareStr = #shareList > 0 and ("|cffAAAAAA(shared w/ " .. table.concat(shareList, ", ") .. ")|r") or ""
                    print(string.format("  |cff%s[%s]|r %s", catColor, catName, shareStr))
                    for _, s in ipairs(spells) do
                        print(string.format("    |cffFFD700%s|r %s  |cffAAAAAA%s|r", s.spell, s.dur, s.notes))
                    end
                end
            end
        end

    -- ── /ba points ────────────────────────────────────────────
    elseif cmd == "points" or cmd == "rating" then
        -- Same as /ba calc with no arg
        local r2,r3,r5,g2,g3,g5 = GetLiveRatings()
        local curAP = GetCurrentArenaPoints()
        local er2=g2>=10 and r2 or 0; local er3=g3>=10 and r3 or 0; local er5=g5>=10 and r5 or 0
        local best, bb = CalcBestPoints(er2, er3, er5)
        print(string.format("%s Ratings  |cffAAAAAA(Banked: %d AP)|r", BA, curAP))
        local function pr(b, r, g)
            local ap = CalcBracketPoints(r, b)
            print(string.format("  %s: %d  %s  |cffFFD700%.0fAP|r",
                b, r, g>=10 and string.format("|cff00FF00%dg|r",g) or string.format("|cffFF4444%dg/10|r",g), ap))
        end
        pr("2v2",r2,g2); pr("3v3",r3,g3); pr("5v5",r5,g5)
        print(best>0 and string.format("  Best: |cffFFD700%.0fAP|r (%s)", best, bb) or "  |cffAAAAAA(No eligible bracket — need 10 games)|r")

    -- ── /ba alts ──────────────────────────────────────────────
    elseif cmd == "alts" then
        local alts = BeanArena_GetAltData()
        -- Class color table (TBC class file names > hex)
        local CLASS_COLORS = {
            WARRIOR="C79C6E", PALADIN="F58CBA", HUNTER="ABD473", ROGUE="FFF569",
            PRIEST="FFFFFF", SHAMAN="0070DE", MAGE="69CCF0", WARLOCK="9482C9",
            DRUID="FF7D0A", DEATHKNIGHT="C41F3B",
        }
        local myKey = (CHAR_NAME or "") .. "-" .. (CHAR_REALM or "")
        local printed = 0
        print("|cffFFD700[BA]|r Alts:")
        for _, a in ipairs(alts) do
            local key = a.name .. "-" .. (a.realm or "")
            if key ~= myKey then
                local cc = CLASS_COLORS[a.class] or "AAAAAA"
                local ts = a.lastSeen and date("%m/%d", a.lastSeen) or "?"
                print(string.format("  |cff%s%-12s|r  2v2:|cffFFD700%d|r  3v3:|cffFFD700%d|r  AP:|cff88FF88%d|r  |cffAAAAAA(%s)|r",
                    cc, a.name, a.rating2v2 or 0, a.rating3v3 or 0, a.arenaPoints or 0, ts))
                printed = printed + 1
            end
        end
        if printed == 0 then
            print("  |cffAAAAAANo alt data yet. Log in on your alts to populate.|r")
        end

    -- ── /ba reset ─────────────────────────────────────────────
    elseif cmd == "reset" then
        print(BA .. " Reset in: |cff00CCFF" .. GetDaysToReset() .. "|r")

    -- ── /ba marks ─────────────────────────────────────────────
    elseif cmd == "marks" then
        local m = GetPvPMarkCounts()
        print(BA .. " BG Marks:")
        local order = {"AV","WSG","AB","EotS"}
        for _, bg in ipairs(order) do
            print(string.format("  %s: |cffFFD700%d|r", bg, m[bg] or 0))
        end

    -- ── /ba slots [arena|honor] ──────────────────────────────────
    elseif cmd == "slots" then
        local which = args:lower()
        if which == "" or which == "arena" then
            local slots = {}
            for _, g in ipairs(ARENA_GEAR_FULL) do slots[#slots+1] = g.slot end
            print("|cffFFD700[BA]|r Arena slots: " .. table.concat(slots, ", "))
        end
        if which == "" or which == "honor" then
            local slots = {}
            for _, g in ipairs(HONOR_GEAR_FULL) do slots[#slots+1] = g.slot end
            print("|cffFFD700[BA]|r Honor slots: " .. table.concat(slots, ", "))
        end
        if which ~= "" and which ~= "arena" and which ~= "honor" then
            print("|cffFFD700[BA]|r Usage: /ba slots  |  /ba slots arena  |  /ba slots honor")
        end

    -- ── /ba gear  /ba hgear ───────────────────────────────────
    elseif cmd == "gear" or cmd == "arenagear" then
        BeanArena_OpenRefFrame("Arena Gear")
    elseif cmd == "hgear" or cmd == "honorgear" then
        BeanArena_OpenRefFrame("Honor Gear")
    elseif cmd == "plan" then
        BeanArena_OpenRefFrame("My Gear")

    -- ── /ba bgshare  /ba bgprint ──────────────────────────────
    elseif cmd == "bgshare" then
        local fmtS  = BreakUpLargeNumbers or tostring
        local honor = GetCurrentHonor()
        local marks = GetPvPMarkCounts()
        local name  = CHAR_NAME or UnitName("player") or "Me"
        local msg   = string.format("[BA] %s - Honor: %s  AV:%d WSG:%d AB:%d EotS:%d",
            name, fmtS(honor),
            marks.AV or 0, marks.WSG or 0, marks.AB or 0, marks.EotS or 0)
        local channel = IsInGroup() and "PARTY" or "SAY"
        SendChatMessage(msg, channel)

    elseif cmd == "bgprint" then
        if not IsInGroup() then
            print(BA .. " Not in a party.")
        else
            local fmtN = BreakUpLargeNumbers or tostring
            -- Print self first
            local selfMarksC = GetPvPMarkCounts()
            local selfNameC  = CHAR_NAME or UnitName("player") or "Me"
            SendChatMessage(string.format(
                "[BA] %s - Honor: %s  AV:%d WSG:%d AB:%d EotS:%d",
                selfNameC, fmtN(GetCurrentHonor()),
                selfMarksC.AV or 0, selfMarksC.WSG or 0,
                selfMarksC.AB or 0, selfMarksC.EotS or 0
            ), "PARTY")
            -- Print other party members
            for i = 1, GetNumGroupMembers() do
                local memberName = UnitName("party"..i)
                if memberName then
                    local shortName = memberName:match("^([^%-]+)") or memberName
                    local data = BeanArenaDB.teamBG and BeanArenaDB.teamBG[shortName]
                    if data then
                        SendChatMessage(string.format(
                            "[BA] %s - Honor: %s  AV:%d WSG:%d AB:%d EotS:%d",
                            shortName, fmtN(data.honor), data.AV, data.WSG, data.AB, data.EotS
                        ), "PARTY")
                    else
                        SendChatMessage(string.format(
                            "[BA] %s: BeanArena not installed", shortName
                        ), "PARTY")
                    end
                end
            end
        end
    elseif cmd == "weapons" then
        BeanArena_OpenRefFrame("Weapons")

    -- ── /ba info  /ba chars  /ba commands ─────────────────────
    elseif cmd == "info" then
        BeanArena_OpenRefFrame("Help")
    elseif cmd == "chars" or cmd == "characters" then
        Toggle(charViewFrame, frame)
    elseif cmd == "commands" then
        if cFrame:IsShown() then cFrame:Hide() else OpenCommands() end

    -- ── /ba options ───────────────────────────────────────────
    elseif cmd == "options" then ShowOptions()

    -- ── /ba help ──────────────────────────────────────────────
    elseif cmd == "help" then
        print("|cffFFD700[BA]|r Commands — /ba {command}")
        print("  |cffFFD700Windows:|r  /ba  honor  gear  hgear  cc  info  chars")
        print("  |cffFFD700Lookup:|r   calc [#]  target <ap>  honor [slot]  arena [slot]  dr [class]")
        print("  |cffFFD700Lists:|r    slots  slots arena  slots honor")
        print("  |cffFFD700Other:|r    alts  points  marks  reset  help")
        print("  |cffFFD700BG Team:|r  bgshare  bgprint")

    else
        print(BA .. " Unknown: |cffFF4444/ba " .. cmd .. "|r  —  try |cffFFD700/ba help|r")
    end
end

-- ============================================================
-- EVENTS
-- ============================================================
-- Set when GET_ITEM_INFO_RECEIVED fires while a gear popup is open;
-- cleared by the OnUpdate ticker which then rebuilds the popup once.
local itemRefreshPending = false

-- ============================================================
-- VERSION BROADCAST  (peer-to-peer via addon message channel)
-- ============================================================
-- BA_MSG_PREFIX and versionWarnShown declared at top of file (line ~88)

-- Returns true if version string a is strictly newer than b.
-- Compares up to three dot-separated numeric parts: major.minor.patch
local function VersionIsNewer(a, b)
    local function parts(v)
        local x,y,z = tostring(v):match("(%d+)%.?(%d*)%.?(%d*)")
        return tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
    end
    local a1,a2,a3 = parts(a)
    local b1,b2,b3 = parts(b)
    if a1 ~= b1 then return a1 > b1 end
    if a2 ~= b2 then return a2 > b2 end
    return a3 > b3
end

local function BroadcastVersion()
    BA_RegisterPrefix(BA_MSG_PREFIX)
    local payload = "VERSION:" .. BA_VERSION
    if IsInRaid and IsInRaid() then
        BA_SendAddonMsg(BA_MSG_PREFIX, payload, "RAID")
    elseif IsInGroup and IsInGroup() then
        BA_SendAddonMsg(BA_MSG_PREFIX, payload, "PARTY")
    end
    if IsInGuild and IsInGuild() then
        BA_SendAddonMsg(BA_MSG_PREFIX, payload, "GUILD")
    end
end

local eFrame = CreateFrame("Frame")
eFrame:RegisterEvent("ADDON_LOADED")
eFrame:RegisterEvent("PLAYER_LOGIN")
eFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eFrame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
eFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eFrame:RegisterEvent("CHAT_MSG_ADDON")
eFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
eFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
BA_RegisterPrefix(BA_MSG_PREFIX)

eFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
    if event == "ADDON_LOADED" and type(arg1)=="string" and arg1:lower() == ADDON_NAME:lower() then
        -- Initialize minimap sub-table with defaults
        BeanArenaDB.minimap = BeanArenaDB.minimap or {}
        local mm = BeanArenaDB.minimap
        if mm.position     == nil then mm.position     = 225   end
        if mm.distance     == nil then mm.distance     = 1     end
        if mm.visible      == nil then mm.visible      = true  end
        if mm.lock         == nil then mm.lock         = false end
        if mm.lockDistance == nil then mm.lockDistance = false end
        -- Initialize alt data table
        BeanArenaDB.altData = BeanArenaDB.altData or {}
        -- Initialize per-character char plan
        BeanArenaCharDB.charPlan = BeanArenaCharDB.charPlan or { dismissed = {} }
        -- Team BG sharing — cleared on every load, not persisted
        BeanArenaDB.teamBG = {}
        -- Restore main frame position
        if DB("frameX") and DB("frameY") then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", DB("frameX"), DB("frameY"))
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        UpdateMinimapPos()
        SetupPVPHook()
        print("|cffFFD700[BeanArena]|r v" .. BA_VERSION .. " loaded! /ba help")
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
        -- Update snapshots and broadcast version after ratings have loaded
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function()
                SnapshotCharData()
                WriteAltSnapshot()
                BroadcastVersion()
            end)
        end
    elseif event == "CHAT_MSG_ADDON" then
        -- arg1=prefix, arg2=message, arg3=channel, arg4=sender
        local prefix, message, _, sender = arg1, arg2, arg3, arg4
        if prefix == BA_MSG_PREFIX and message then
            local theirVersion = message:match("^VERSION:(.+)$")
            if theirVersion and not versionWarnShown then
                if VersionIsNewer(theirVersion, BA_VERSION) then
                    versionWarnShown = true
                    print(string.format(
                        "|cffFFD700[BeanArena]|r Your version |cffFF6666%s|r is outdated. " ..
                        "|cff%s%s|r has version |cff00FF00%s|r. " ..
                        "Get the latest at |cffAAAAAAcurseforge.com|r (/ba help)",
                        BA_VERSION,
                        "AAAAAA", sender,
                        theirVersion))
                end
            end
            local bgPayload = message:match("^BGDATA:(.+)$")
            if bgPayload then
                local honor, av, wsg, ab, eots = bgPayload:match("^(%d+):(%d+):(%d+):(%d+):(%d+)$")
                if honor then
                    local senderName = sender:match("^([^%-]+)") or sender
                    BeanArenaDB.teamBG = BeanArenaDB.teamBG or {}
                    BeanArenaDB.teamBG[senderName] = {
                        honor     = tonumber(honor),
                        AV        = tonumber(av),
                        WSG       = tonumber(wsg),
                        AB        = tonumber(ab),
                        EotS      = tonumber(eots),
                        timestamp = time(),
                    }
                    if BeanArena_RefreshTeamBGPage then
                        BeanArena_RefreshTeamBGPage()
                    end
                end
            end
        end
    elseif event == "UPDATE_BATTLEFIELD_STATUS" then
        if frame:IsShown() then BeanArena_RefreshFrame() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- Flag a rebuild so icons finish loading before the overlay rebuilds.
        itemRefreshPending = true
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" and BeanArena_RefreshCharPlan then
            BeanArena_RefreshCharPlan()
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        if BeanArenaDB.teamBG then
            for name in pairs(BeanArenaDB.teamBG) do
                local found = false
                for i = 1, GetNumGroupMembers() do
                    local memberName = UnitName("party"..i) or UnitName("raid"..i)
                    if memberName and memberName:match("^([^%-]+)") == name then
                        found = true; break
                    end
                end
                if not found then BeanArenaDB.teamBG[name] = nil end
            end
        end
        if BeanArena_RefreshTeamBGPage then BeanArena_RefreshTeamBGPage() end
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
    -- Rebuild gear/weapons page once after item icons finish loading.
    -- Uses RebuildRefPage (not RefreshRefFrame) so it calls SwitchPage exactly
    -- once and does not fire on the 5-second ticker path.
    if itemRefreshPending then
        itemRefreshPending = false
        if BeanArena_RebuildRefPage then BeanArena_RebuildRefPage() end
    end
    ticker = ticker + elapsed
    if ticker >= 5 then
        ticker = 0
        if viewingSnap == nil then RefreshLive() end; RefreshMisc()
        if not editFocused["manual2v2"] then man2v2Edit:SetText(tostring(DB("manual2v2"))) end
        if not editFocused["manual3v3"] then man3v3Edit:SetText(tostring(DB("manual3v3"))) end
        if not editFocused["manual5v5"] then man5v5Edit:SetText(tostring(DB("manual5v5"))) end
    end
end)

-- ============================================================
-- END OF FILE | BeanArena v1.0.4 | 2026-05-22
-- ============================================================
