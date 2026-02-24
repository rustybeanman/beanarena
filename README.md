# BeanArena

**Arena Point Calculator & History Tracker for WoW TBC Anniversary**

BeanArena is a lightweight addon that calculates your weekly arena point rewards, tracks your match history, and keeps your honor and battleground mark counts in one place.

---

## Features

### Arena Point Calculator
- **Live ratings** pulled automatically from the game API for 2v2, 3v3, and 5v5
- **Games played tracking** with a visual indicator showing whether you've hit the 10-game minimum to qualify for points
- **Best reward** calculation that identifies which bracket will earn you the most points this week
- **Manual rating entry** to theorycraft "what if" scenarios without affecting live data

### Arena History
- Automatically records every arena match you play
- Logs date, bracket, win/loss, match duration, and full team compositions (both friendly and enemy)
- Class-colored player names for easy scanning
- Stores up to 200 matches with the latest 100 displayed in a scrollable list
- One-click history clear

### Honor & Battleground Marks
- Current honor total
- Countdown timer to the next weekly Tuesday reset
- PvP mark counts for AV, WSG, AB, and EotS scanned directly from your bags

### Quality of Life
- **Minimap button** — draggable to any position around your minimap
- **Honor window integration** — optionally open BeanArena (and/or History) whenever you open the PvP/Honor panel
- All windows are draggable and remember their positions between sessions
- ESC closes any open BeanArena window

---

## Installation

1. Download or clone this repository
2. Copy the `BeanArena` folder into your TBC Anniversary AddOns directory:
   ```
   C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\BeanArena\
   ```
3. The folder should contain:
   ```
   BeanArena/
   ├── BeanArena.toc
   ├── BeanArena.lua
   └── README.md
   ```
4. Restart WoW or type `/reload` if you're already in-game

---

## Usage

### Minimap Button

| Click | Action |
|---|---|
| Left-click | Toggle main BeanArena window |
| Middle-click | Toggle commands reference window |
| Right-click | Open options menu |

### Slash Commands

All commands use `/ap` (or `/beanarena` as an alias):

| Command | Description |
|---|---|
| `/ap` | Toggle main window |
| `/ap history` | Toggle history window |
| `/ap commands` | Toggle commands reference window |
| `/ap points` | Print point breakdown to chat |
| `/ap honor` | Print current honor to chat |
| `/ap reset` | Print time until weekly reset |
| `/ap marks` | Print BG mark counts to chat |
| `/ap options` | Open options menu at cursor |
| `/ap help` | Print help to chat |

### Options Menu

Right-click the minimap button to access options:

- **Toggle BeanArena Window** — show/hide the main calculator
- **Toggle History Window** — show/hide match history
- **Toggle Commands Window** — show/hide the command reference
- **Open With Honor Window** — automatically open BeanArena when you open the PvP/Honor panel (H key), with three modes:
  - *BeanArena only* — just the main window
  - *BeanArena + History* — both windows
  - *Off* — disabled

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

BeanArena stores all data in `BeanArenaDB` (a WoW SavedVariable). This includes your manual rating entries, window positions, minimap button angle, option preferences, and your full arena match history. No data is sent externally.

---

## Compatibility

- **Game version:** WoW TBC Anniversary (Interface 20504)
- **Dependencies:** None
- **Conflicts:** None known

---

## Author

**Nicepriest**

---

## License

This project is provided as-is for personal use. Feel free to modify and share.
