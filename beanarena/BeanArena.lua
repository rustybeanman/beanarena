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
-- CURRENT: v0.3.3
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
    local snap = {
        name         = CHAR_NAME,
        realm        = CHAR_REALM,
        arenaPoints  = GetCurrentArenaPoints(),
        honor        = GetCurrentHonor(),
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

-- Class → armor type (for honor off-piece filtering)
local CLASS_ARMOR_TYPE = {
    Druid="Leather", Hunter="Mail",   Mage="Cloth",
    Paladin="Plate", Priest="Cloth",  Rogue="Leather",
    Shaman="Mail",   Warlock="Cloth", Warrior="Plate",
}
local CLASS_LIST = {"Druid","Hunter","Mage","Paladin","Priest","Rogue","Shaman","Warlock","Warrior"}

-- Arena set name prefix per class (no individual item IDs — verify in-game before adding)
local CLASS_SET_S1 = {
    Warrior="Gladiator's Plate",         Paladin="Gladiator's Redemption",
    Druid="Gladiator's Kodohide/Dragonhide", Hunter="Gladiator's Chain",
    Mage="Gladiator's Silk",             Priest="Gladiator's Mooncloth/Satin",
    Rogue="Gladiator's Leather",         Shaman="Gladiator's Mail/Linked",
    Warlock="Gladiator's Dreadweave",
}
local CLASS_SET_S2 = {
    Warrior="Merciless Gladiator's Plate",   Paladin="Merciless Gladiator's Redemption",
    Druid="Merciless Gladiator's Kodohide/Dragonhide", Hunter="Merciless Gladiator's Chain",
    Mage="Merciless Gladiator's Silk",       Priest="Merciless Gladiator's Mooncloth/Satin",
    Rogue="Merciless Gladiator's Leather",   Shaman="Merciless Gladiator's Mail/Linked",
    Warlock="Merciless Gladiator's Dreadweave/Felweave",
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
        f:SetBackdropColor(0, 0, 0, 0.9)
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
local arenaGearFrame, honorGearFrame, honorFrame, drFrame
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
    -- Rating Target (AP → Rating)
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
versionFS:SetText("|cff666666v0.3.3  •  TBC Anniversary|r")
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

-- ══════════════════════════════════════════════════════════════
-- SECTION: RATING TARGET  (AP → Rating inverse calculator)
-- ══════════════════════════════════════════════════════════════
MakeLine(frame, Y.TLINE, CW, LC)
MakeHeader(frame, Y.THEAD, "Rating Target", LC)
MakeLine(frame, Y.TLINE2, CW, LC)

SmallHdr(CALC.lbl,  Y.TINPUT + 10, "AP Goal")

local targetLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
targetLbl:SetPoint("TOPLEFT", frame, "TOPLEFT", CALC.lbl, Y.TINPUT)
targetLbl:SetText("Target AP:"); targetLbl:SetTextColor(0.8, 0.8, 0.8)

local targetResultFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
targetResultFS:SetPoint("TOPLEFT", frame, "TOPLEFT", LC, Y.TRES)
targetResultFS:SetWidth(CW)
targetResultFS:SetText("--")

local targetAPEdit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
targetAPEdit:SetSize(88, 20)
targetAPEdit:SetPoint("TOPLEFT", frame, "TOPLEFT", CALC.eb, Y.TINPUT + 4)
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

MakeLine(frame, Y.TLINE3, CW, LC)

-- ── Row 1: Arena Gear | Honor Gear ─────────────────────────
local BTNW = math.floor((CW - 4) / 2)

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
-- POPUP: ARENA GEAR COSTS  (class + season aware, with item tooltips)
-- ============================================================
do
    local PW = 430
    local PH = 560
    arenaGearFrame = MakeBGFrame("BeanArenaArenaGearFrame", UIParent, PW, PH)
    arenaGearFrame:SetFrameStrata("HIGH")
    arenaGearFrame:SetMovable(true); arenaGearFrame:EnableMouse(true)
    arenaGearFrame:RegisterForDrag("LeftButton")
    arenaGearFrame:SetScript("OnDragStart", arenaGearFrame.StartMoving)
    arenaGearFrame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    arenaGearFrame:Hide()
    RegisterEsc(arenaGearFrame)

    local agTitle = arenaGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    agTitle:SetPoint("TOP", arenaGearFrame, "TOP", 0, -12)
    agTitle:SetText("|cffFFD700Arena Gear|r")

    local agClose = CreateFrame("Button", nil, arenaGearFrame, "UIPanelCloseButton")
    agClose:SetPoint("TOPRIGHT", arenaGearFrame, "TOPRIGHT", -4, -4)
    agClose:SetScript("OnClick", function() arenaGearFrame:Hide() end)

    -- Season toggle buttons
    local agSeason = 2
    local agS1Btn = CreateFrame("Button", nil, arenaGearFrame, "UIPanelButtonTemplate")
    agS1Btn:SetSize(70, 22); agS1Btn:SetPoint("TOPLEFT", arenaGearFrame, "TOPLEFT", 12, -32)
    agS1Btn:SetText("Season 1"); agS1Btn:GetFontString():SetFontObject("GameFontNormalSmall")
    local agS2Btn = CreateFrame("Button", nil, arenaGearFrame, "UIPanelButtonTemplate")
    agS2Btn:SetSize(70, 22); agS2Btn:SetPoint("LEFT", agS1Btn, "RIGHT", 4, 0)
    agS2Btn:SetText("Season 2"); agS2Btn:GetFontString():SetFontObject("GameFontNormalSmall")

    -- Class selector: visible button + hidden menu anchor
    local agClassLbl = arenaGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    agClassLbl:SetPoint("TOPLEFT", arenaGearFrame, "TOPLEFT", 156, -37)
    agClassLbl:SetText("|cffAAAAAA Class:|r")
    local agClassBtn = CreateFrame("Button", nil, arenaGearFrame, "UIPanelButtonTemplate")
    agClassBtn:SetSize(148, 22)
    agClassBtn:SetPoint("TOPLEFT", arenaGearFrame, "TOPLEFT", 196, -33)
    agClassBtn:GetFontString():SetFontObject("GameFontNormalSmall")
    -- hidden anchor for the MENU dropdown (parented to UIParent to avoid clipping)
    local agClassDD = CreateFrame("Frame", "BeanArenaAgClassDD", UIParent, "UIDropDownMenuTemplate")

    -- Scroll area
    local agScr = CreateFrame("ScrollFrame", "BeanArenaAgScr", arenaGearFrame, "UIPanelScrollFrameTemplate")
    agScr:SetPoint("TOPLEFT",     arenaGearFrame, "TOPLEFT",     10, -62)
    agScr:SetPoint("BOTTOMRIGHT", arenaGearFrame, "BOTTOMRIGHT", -28, 10)
    local agCnt = CreateFrame("Frame", nil, agScr)
    agCnt:SetWidth(PW - 52)
    agCnt:SetHeight(10)
    agScr:SetScrollChild(agCnt)

    local agClass = "Warrior"
    local CW2 = PW - 52   -- matches agCnt:SetWidth(PW-52)
    local ACOL = { slot=0, ap=CW2-140, rat=CW2-68 }

    local function BuildArenaContent()
        for _, ch in ipairs({agCnt:GetChildren()}) do ch:Hide() end
        for _, r  in ipairs({agCnt:GetRegions()})  do r:Hide()  end

        local weaponList = agSeason == 2 and S2_WEAPONS or S1_WEAPONS
        local setNames   = agSeason == 2 and CLASS_SET_S2 or CLASS_SET_S1
        local filter     = CLASS_WEAPONS[agClass] or {}
        local r2,r3,r5   = GetLiveRatings()
        local bestRating = math.max(r2, r3, r5)
        local cy = -2

        local function AGLine()
            local d = agCnt:CreateTexture(nil,"ARTWORK")
            d:SetSize(CW2,1); d:SetPoint("TOPLEFT",agCnt,"TOPLEFT",0,cy-2)
            d:SetColorTexture(0.3,0.3,0.3,0.5); cy=cy-8
        end
        local function AGHdr(txt)
            local h = agCnt:CreateFontString(nil,"OVERLAY","GameFontNormal")
            h:SetPoint("TOPLEFT",agCnt,"TOPLEFT",0,cy)
            h:SetText("|cff00CCFF"..txt.."|r"); cy=cy-16
        end
        local function AGColHdr()
            local function CH(x,t)
                local f=agCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                f:SetPoint("TOPLEFT",agCnt,"TOPLEFT",x,cy)
                f:SetText("|cffAAAAAA"..t.."|r")
            end
            CH(ACOL.slot,"Slot"); CH(ACOL.ap,"AP"); CH(ACOL.rat,"Rating")
            cy=cy-14; AGLine()
        end

        -- ─── 5-piece armor set ───────────────────────────────────
        local setName = setNames[agClass] or (agClass.." Set")
        AGHdr("Armor Set  |cffAAAAAA— "..setName.."|r")
        AGColHdr()
        local armorSlots = {
            {slot="Gloves",    ap=agSeason==2 and 930  or 875,  rating=0   },
            {slot="Helmet",    ap=agSeason==2 and 1550 or 1375, rating=0   },
            {slot="Chest",     ap=agSeason==2 and 1550 or 1375, rating=0   },
            {slot="Legs",      ap=agSeason==2 and 1550 or 1375, rating=0   },
            {slot="Shoulders", ap=agSeason==2 and 1245 or 1125, rating=2000},
        }
        for _, row in ipairs(armorSlots) do
            local rCol = (row.rating==0 or bestRating>=row.rating) and "00FF00" or "FF4444"
            local function FS2(x,t)
                local f=agCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                f:SetPoint("TOPLEFT",agCnt,"TOPLEFT",x,cy); f:SetText(t)
            end
            FS2(ACOL.slot, "|cffCCCCCC"..row.slot.."|r")
            FS2(ACOL.ap,   "|cffFFD700"..row.ap.."|r")
            FS2(ACOL.rat,  row.rating>0 and ("|cff"..rCol..row.rating.."|r") or "|cff00FF00None|r")
            cy=cy-15
        end
        cy=cy-4

        -- ─── Weapons / off-hands / relics ────────────────────────
        AGHdr("Weapons & Off-hands  |cffAAAAAA— "..agClass.." (hover for tooltip)|r")
        AGColHdr()
        local anyShown = false
        for _, wep in ipairs(weaponList) do
            if filter[wep.key] then
                anyShown = true
                local rCol = (wep.rating==0 or bestRating>=wep.rating) and "00FF00" or "FF4444"
                local rowBtn = CreateFrame("Button", nil, agCnt)
                rowBtn:SetSize(CW2, 15)
                rowBtn:SetPoint("TOPLEFT", agCnt, "TOPLEFT", 0, cy)
                rowBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
                local function BFS(x,t)
                    local f=rowBtn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                    f:SetPoint("LEFT",rowBtn,"LEFT",x,0); f:SetText(t)
                end
                BFS(ACOL.slot, "|cffCCCCCC"..wep.slot.."|r")
                BFS(ACOL.ap,   "|cffFFD700"..wep.ap.."|r")
                BFS(ACOL.rat,  wep.rating>0 and ("|cff"..rCol..wep.rating.."|r") or "|cff00FF00None|r")
                -- Tooltip on hover
                local capturedWep = wep
                rowBtn:SetScript("OnEnter", function(self)
                    if capturedWep.ids and capturedWep.ids[1] then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink("item:"..capturedWep.ids[1])
                        if #capturedWep.ids > 1 then
                            GameTooltip:AddLine(string.format(
                                "|cffAAAAAA+ %d more style variant%s (same stats)|r",
                                #capturedWep.ids-1, #capturedWep.ids>2 and "s" or ""))
                        end
                        GameTooltip:Show()
                    end
                end)
                rowBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                cy=cy-15
            end
        end
        if not anyShown then
            local nf=agCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            nf:SetPoint("TOPLEFT",agCnt,"TOPLEFT",0,cy)
            nf:SetText("|cff666666No weapons defined for "..agClass.."|r")
            cy=cy-15
        end
        agCnt:SetHeight(math.abs(cy)+20)
    end

    agClassBtn:SetScript("OnClick", function(self)
        UIDropDownMenu_Initialize(agClassDD, function()
            for _, cls in ipairs(CLASS_LIST) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = cls; info.value = cls
                info.notCheckable = true
                info.func = function()
                    agClass = cls
                    agClassBtn:SetText(cls .. "  v")
                    BuildArenaContent()
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info)
            end
        end, "MENU")
        ToggleDropDownMenu(1, nil, agClassDD, self, 0, -4)
    end)

    agS1Btn:SetScript("OnClick", function() agSeason = 1; BuildArenaContent() end)
    agS2Btn:SetScript("OnClick", function() agSeason = 2; BuildArenaContent() end)

    arenaGearFrame:SetScript("OnShow", function()
        local _, cf = UnitClass("player")
        local cm = {WARRIOR="Warrior",PALADIN="Paladin",HUNTER="Hunter",ROGUE="Rogue",
                    PRIEST="Priest",SHAMAN="Shaman",MAGE="Mage",WARLOCK="Warlock",DRUID="Druid"}
        agClass = cm[cf or ""] or "Warrior"
        agClassBtn:SetText(agClass .. "  v")
        BuildArenaContent()
    end)

    BeanArena_RefreshArenaGearPopup = function()
        if arenaGearFrame:IsShown() then BuildArenaContent() end
    end
end

-- ============================================================
-- POPUP: HONOR GEAR COSTS  (class + season aware, with item tooltips)
-- ============================================================
do
    local PW = 480
    local PH = 560
    honorGearFrame = MakeBGFrame("BeanArenaHonorGearFrame", UIParent, PW, PH)
    honorGearFrame:SetFrameStrata("HIGH")
    honorGearFrame:SetMovable(true); honorGearFrame:EnableMouse(true)
    honorGearFrame:RegisterForDrag("LeftButton")
    honorGearFrame:SetScript("OnDragStart", honorGearFrame.StartMoving)
    honorGearFrame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    honorGearFrame:Hide()
    RegisterEsc(honorGearFrame)

    local hgTitle = honorGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hgTitle:SetPoint("TOP", honorGearFrame, "TOP", 0, -12)
    hgTitle:SetText("|cffFFD700Honor Gear|r")

    local hgClose = CreateFrame("Button", nil, honorGearFrame, "UIPanelCloseButton")
    hgClose:SetPoint("TOPRIGHT", honorGearFrame, "TOPRIGHT", -4, -4)
    hgClose:SetScript("OnClick", function() honorGearFrame:Hide() end)

    -- Season toggle buttons
    local hgSeason = 2
    local hgS1Btn = CreateFrame("Button", nil, honorGearFrame, "UIPanelButtonTemplate")
    hgS1Btn:SetSize(70, 22); hgS1Btn:SetPoint("TOPLEFT", honorGearFrame, "TOPLEFT", 12, -32)
    hgS1Btn:SetText("Season 1"); hgS1Btn:GetFontString():SetFontObject("GameFontNormalSmall")
    local hgS2Btn = CreateFrame("Button", nil, honorGearFrame, "UIPanelButtonTemplate")
    hgS2Btn:SetSize(70, 22); hgS2Btn:SetPoint("LEFT", hgS1Btn, "RIGHT", 4, 0)
    hgS2Btn:SetText("Season 2"); hgS2Btn:GetFontString():SetFontObject("GameFontNormalSmall")

    -- Class dropdown  (UIPanelButtonTemplate button + hidden menu anchor)
    local hgClassLbl = honorGearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hgClassLbl:SetPoint("TOPLEFT", honorGearFrame, "TOPLEFT", 162, -37)
    hgClassLbl:SetText("|cffAAAAAA Class:|r")
    local hgClassBtn = CreateFrame("Button", nil, honorGearFrame, "UIPanelButtonTemplate")
    hgClassBtn:SetSize(148, 22)
    hgClassBtn:SetPoint("TOPLEFT", honorGearFrame, "TOPLEFT", 207, -33)
    -- Hidden anchor for the dropdown menu — parented to UIParent so it renders above everything
    local hgClassDD = CreateFrame("Frame", "BeanArenaHgClassDD", UIParent, "UIDropDownMenuTemplate")
    hgClassDD:Hide()

    -- Scroll area
    local hgScr = CreateFrame("ScrollFrame", "BeanArenaHgScr", honorGearFrame, "UIPanelScrollFrameTemplate")
    hgScr:SetPoint("TOPLEFT",     honorGearFrame, "TOPLEFT",     10, -62)
    hgScr:SetPoint("BOTTOMRIGHT", honorGearFrame, "BOTTOMRIGHT", -28, 10)
    local hgCnt = CreateFrame("Frame", nil, hgScr)
    hgCnt:SetWidth(PW - 52)
    hgCnt:SetHeight(10)
    hgScr:SetScrollChild(hgCnt)

    local hgClass = "Warrior"
    local HCW = PW - 52   -- matches hgCnt:SetWidth(PW-52)
    local HCOL = { name=0, honor=HCW-195, marks=HCW-130, have=HCW-48 }

    local function BuildHonorContent()
        for _, ch in ipairs({hgCnt:GetChildren()}) do ch:Hide() end
        for _, r  in ipairs({hgCnt:GetRegions()})  do r:Hide()  end

        local armorType  = CLASS_ARMOR_TYPE[hgClass] or "Cloth"
        local universal  = hgSeason == 2 and S2_HONOR_UNIVERSAL or S1_HONOR_UNIVERSAL
        local byArmor    = hgSeason == 2 and S2_HONOR_BYARMOR   or S1_HONOR_BYARMOR
        local armorRows  = byArmor[armorType] or {}
        local honor      = GetCurrentHonor()
        local marks      = GetPvPMarkCounts()
        local fmt        = BreakUpLargeNumbers or tostring
        local cy         = -2

        local function HLine()
            local d=hgCnt:CreateTexture(nil,"ARTWORK")
            d:SetSize(HCW,1); d:SetPoint("TOPLEFT",hgCnt,"TOPLEFT",0,cy-2)
            d:SetColorTexture(0.3,0.3,0.3,0.5); cy=cy-8
        end
        local function HGHdr(txt)
            local h=hgCnt:CreateFontString(nil,"OVERLAY","GameFontNormal")
            h:SetPoint("TOPLEFT",hgCnt,"TOPLEFT",0,cy)
            h:SetText("|cff00CCFF"..txt.."|r"); cy=cy-16
        end
        local function ColHdrs()
            local function CH(x,t)
                local f=hgCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                f:SetPoint("TOPLEFT",hgCnt,"TOPLEFT",x,cy)
                f:SetText("|cffAAAAAA"..t.."|r")
            end
            CH(HCOL.name,"Item"); CH(HCOL.honor,"Honor"); CH(HCOL.marks,"Marks"); CH(HCOL.have,"You Have")
            cy=cy-14; HLine()
        end

        -- Helper: build one item row (hoverable for tooltip)
        local function ItemRow(item, slotData)
            local honorMet = honor >= slotData.honor
            local hCol = honorMet and "00FF00" or "FF4444"
            -- Marks check
            local allMet = true
            local mparts = {}
            for bg, req in pairs(slotData.marks) do
                local have = marks[bg] or 0
                if have < req then allMet = false end
                local mc = have >= req and "00FF00" or "FF4444"
                mparts[#mparts+1] = string.format("|cff%s%d|r|cffAAAAAA/%d %s|r", mc, have, req, bg)
            end
            if #mparts == 0 then mparts[#mparts+1] = "|cff00FF00—|r" end

            local rowBtn = CreateFrame("Button", nil, hgCnt)
            rowBtn:SetSize(HCW, 15)
            rowBtn:SetPoint("TOPLEFT", hgCnt, "TOPLEFT", 0, cy)
            rowBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

            local function BFS(x, t)
                local f = rowBtn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                f:SetPoint("LEFT",rowBtn,"LEFT",x,0); f:SetText(t)
            end
            -- Item name (truncated to fit)
            local dispName = item.name or ("item:"..item.id)
            local cached = GetItemInfo(item.id)
            if cached then dispName = cached end
            BFS(HCOL.name,  "|cffCCCCCC"..dispName.."|r")
            BFS(HCOL.honor, string.format("|cff%s%s|r", hCol, fmt(slotData.honor)))
            BFS(HCOL.marks, table.concat(mparts,"  "))
            BFS(HCOL.have,  (honorMet and allMet) and "|cff00FF00Ready!|r" or "|cffAAAAAA...|r")

            -- Tooltip on hover
            local capturedID = item.id
            rowBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("item:"..capturedID)
                GameTooltip:Show()
            end)
            rowBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            cy = cy - 15
        end

        -- ─── Neck & Ring (universal) ─────────────────────────────
        HGHdr("Neck & Ring  |cffAAAAAA— all classes|r")
        ColHdrs()
        for _, slotData in ipairs(universal) do
            local prev_cy = cy
            for _, item in ipairs(slotData.items) do
                ItemRow(item, slotData)
            end
            -- slot label on left of first item
            if cy ~= prev_cy then cy = cy - 4 end
        end
        cy = cy - 4

        -- ─── Bracers / Belt / Boots (armor-type specific) ─────────
        HGHdr("Off-pieces  |cffAAAAAA— "..armorType.." ("..hgClass..")|r")
        ColHdrs()
        if #armorRows == 0 then
            local nf=hgCnt:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            nf:SetPoint("TOPLEFT",hgCnt,"TOPLEFT",0,cy)
            nf:SetText("|cff666666No data for "..armorType.."|r"); cy=cy-15
        else
            for _, slotData in ipairs(armorRows) do
                -- Slot label
                local slbl=hgCnt:CreateFontString(nil,"OVERLAY","GameFontNormal")
                slbl:SetPoint("TOPLEFT",hgCnt,"TOPLEFT",0,cy)
                slbl:SetText("|cff888888— "..slotData.slot.." —|r"); cy=cy-14
                for _, item in ipairs(slotData.items) do
                    ItemRow(item, slotData)
                end
                cy = cy - 4
            end
        end

        hgCnt:SetHeight(math.abs(cy)+20)
    end

    -- Class button click: open dropdown anchored to the button
    hgClassBtn:SetScript("OnClick", function(self)
        UIDropDownMenu_Initialize(hgClassDD, function()
            for _, cls in ipairs(CLASS_LIST) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = cls; info.value = cls
                info.notCheckable = false
                info.checked = (hgClass == cls)
                info.func = function()
                    hgClass = cls
                    hgClassBtn:SetText(cls .. "  v")
                    BuildHonorContent()
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info)
            end
        end, "MENU")
        ToggleDropDownMenu(1, nil, hgClassDD, self, 0, -4)
    end)

    hgS1Btn:SetScript("OnClick", function()
        hgSeason = 1; BuildHonorContent()
    end)
    hgS2Btn:SetScript("OnClick", function()
        hgSeason = 2; BuildHonorContent()
    end)

    honorGearFrame:SetScript("OnShow", function()
        local _, cf = UnitClass("player")
        local cm = {WARRIOR="Warrior",PALADIN="Paladin",HUNTER="Hunter",ROGUE="Rogue",
                    PRIEST="Priest",SHAMAN="Shaman",MAGE="Mage",WARLOCK="Warlock",DRUID="Druid"}
        hgClass = cm[cf or ""] or "Warrior"
        hgClassBtn:SetText(hgClass .. "  v")
        BuildHonorContent()
    end)

    BeanArena_RefreshHonorGearPopup = function()
        if honorGearFrame:IsShown() then BuildHonorContent() end
    end
end


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
    iTitle:SetText("|cffFFD700BeanArena|r  |cff888888v0.3.3|r")

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
        { hdr="Character Viewer  ( /ba chars )", body=
            "View comp notes and arena/honor data for your other characters on the same account. Any character that has logged in with BeanArena installed will appear here. Useful for checking your alt's notes or comparing progress." },
        { hdr="Slash Commands", body=
            "/ba calc [#]       AP for all brackets\n/ba honor [slot]   Honor gear cost+progress\n/ba arena [slot]   Arena gear cost+progress\n/ba dr [class]     CC & DR for a class\n/ba slots          List gear slot names\n/ba points         Live rating breakdown\n/ba marks          BG mark counts\n/ba reset          Time until reset\n/ba help           All commands" },
        { hdr="Tips", body=
            "• BeanArena opens alongside the PvP panel (H key) automatically.\n• Minimap: left-click = main window, middle-click = commands, right-click = options.\n• /ba calc 1750 checks AP for any rating.  /ba dr mage lists Mage DR spells.\n• /ba slots shows all gear slot names for use with /ba arena and /ba honor.\n• Frame position is saved between sessions." },
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
            Toggle(honorFrame, frame)
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
            Toggle(arenaGearFrame, frame)
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
            Toggle(drFrame, frame)
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
        -- Class color table (TBC class file names → hex)
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
        Toggle(arenaGearFrame, frame)
    elseif cmd == "hgear" or cmd == "honorgear" then
        Toggle(honorGearFrame, frame)

    -- ── /ba info  /ba chars  /ba commands ─────────────────────
    elseif cmd == "info" then
        Toggle(infoFrame, frame)
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

    else
        print(BA .. " Unknown: |cffFF4444/ba " .. cmd .. "|r  —  try |cffFFD700/ba help|r")
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
        -- Restore main frame position
        if DB("frameX") and DB("frameY") then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", DB("frameX"), DB("frameY"))
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        UpdateMinimapPos()
        SetupPVPHook()
        print("|cffFFD700[BeanArena]|r v0.3.3 loaded! /ba help")
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
        -- Update snapshots with fresh live data after ratings have loaded
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function()
                SnapshotCharData()
                WriteAltSnapshot()
            end)
        end
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
        if viewingSnap == nil then RefreshLive() end; RefreshMisc()
        if not editFocused["manual2v2"] then man2v2Edit:SetText(tostring(DB("manual2v2"))) end
        if not editFocused["manual3v3"] then man3v3Edit:SetText(tostring(DB("manual3v3"))) end
        if not editFocused["manual5v5"] then man5v5Edit:SetText(tostring(DB("manual5v5"))) end
    end
end)

-- ============================================================
-- END OF FILE | BeanArena v0.3.1 | 2026-03-17
-- ============================================================
