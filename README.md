
# BeanArena

**TBC Anniversary Arena Point Calculator & Honor Tracker**

BeanArena is a lightweight addon for WoW TBC Anniversary that calculates weekly arena point rewards, tracks your honor, and provides a built-in reference for gear costs, weapons, CC/DR rules, and general PvP info — all in one place.

## Features

### Arena Point Calculator
- **Live ratings** pulled automatically from the game API for 2v2, 3v3, and 5v5
- **Games played tracking** with a visual indicator for the 10-game minimum
- **Best reward** calculation — highlights which bracket earns the most points this week
- **Manual rating entry** for "what if" theycrafting without affecting live data
- **Rating Target calculator** — enter an AP goal to see the rating needed per bracket

### Honor & Battleground Marks
- Current honor total with a cap bar and milestone markers
- Countdown timer to the next weekly Tuesday reset
- PvP mark counts for AV, WSG, AB, and EotS scanned from your bags

### Reference Window
One unified popup with a dropdown to switch between five sections:

| Section | Contents |
|---|---|
| **Arena Gear** | Icon grid + cost table for S1/S2 arena sets, per-class, season toggle |
| **Weapons** | All S1/S2 PvP weapons and relics with item tooltips |
| **Honor Gear** | S1/S2 honor gear costs, auto-detected for your class |
| **CC/DR Table** | Full cross-reference of CC categories and DR rules for all classes |
| **Info** | Formula reference, bracket multipliers, point caps, and general tips |

### Character Viewer
- Tracks arena points, honor, and rating snapshots across all your characters
- `/ba chars` or `/ba alts` to view or print alt PvP data

### Quality of Life
- **Minimap button** — draggable to any position around the minimap
- **PvP UI hook** — optionally open BeanArena when you press H to open the honor panel
- All windows are draggable and remember their positions between sessions
- ESC closes any open BeanArena window

---

## Installation

1. Download the latest zip from the [Releases](../../releases) page (or clone this repo)
2. Extract and copy the `beanarena` folder into your TBC Anniversary AddOns directory:
   ```
   World of Warcraft\_anniversary_\Interface\AddOns\beanarena\
   ```
3. The folder should contain:
   ```
   beanarena/
   ├── BeanArena.toc
   └── BeanArena.lua
   ```
4. Restart WoW or type `/reload` if you're already in-game

---

## Slash Commands

All commands use `/ba` (or `/beanarena`):

| Command | Description |
|---|---|
| `/ba` | Toggle main window |
| `/ba calc [rating]` | AP for live ratings or a specific rating |
| `/ba target <ap>` | Rating needed to earn a target AP amount |
| `/ba honor [slot]` | Open honor window, or print slot cost to chat |
| `/ba arena [slot]` | Open arena gear reference, or print slot cost to chat |
| `/ba dr [class]` | Open CC/DR table, or print a class's CC list to chat |
| `/ba gear` | Open arena gear costs section |
| `/ba hgear` | Open honor gear costs section |
| `/ba weapons` | Open weapons section |
| `/ba info` | Open info section |
| `/ba chars` | Open character viewer |
| `/ba alts` | Print all alt PvP snapshots to chat |
| `/ba points` | Print live rating AP breakdown to chat |
| `/ba marks` | Print current BG mark counts to chat |
| `/ba reset` | Print time until weekly reset |
| `/ba commands` | Toggle commands reference window |
| `/ba help` | Print all commands to chat |

---

## How Arena Points Are Calculated

BeanArena uses the TBC Anniversary arena point formula with the 1.5x multiplier:

```
Base = ((1651.94 - 475) / (1 + 2500000 × e^(-0.009 × rating)) + 475) × 1.5
```

Bracket multipliers are then applied:

| Bracket | Multiplier |
|---|---|
| 2v2 | 76% |
| 3v3 | 88% |
| 5v5 | 100% |

Your weekly reward comes from whichever **single bracket** yields the highest points, provided you have played at least 10 games in that bracket.

---

## Saved Data

BeanArena stores data in `BeanArenaDB` (account-wide) and `BeanArenaCharDB` (per-character) as WoW SavedVariables. This includes window positions, option preferences, rating snapshots, and honor data. No data is sent externally.

---

## Compatibility

- **Game version:** WoW TBC Anniversary (Interface 20505)
- **Dependencies:** None
- **Conflicts:** None known

---

## Author

**Nicepriest**

---

## License

This project is provided as-is for personal use. Feel free to modify and share.
