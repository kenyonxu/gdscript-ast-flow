# GDScript AST Flow — User Guide

> Target: Godot 4.7+ | Language: English

## Table of Contents

1. [Installation & Setup](#1-installation--setup)
2. [Single-File Analysis](#2-single-file-analysis)
3. [Analysis Panels](#3-analysis-panels)
4. [Project Scan](#4-project-scan)
5. [Graph View Navigation](#5-graph-view-navigation)
6. [CodeGraph JSON Export](#6-codegraph-json-export)
7. [FAQ](#7-faq)

---

## 1. Installation & Setup

1. Copy the `addons/gdscript_util/` directory into your Godot project's `addons/` directory
2. Open Godot Editor, menu **Project → Project Settings → Plugins**
3. Find **GDScript Util**, check **Enable**
4. Bottom panel shows: **Summary / Call Graph / Signal Flow / Def-Use / Project** tabs

---

## 2. Single-File Analysis

Analyze the currently open `.gd` script:

1. Open any `.gd` file
2. Menu **Project → Tools → GDScript AST Flow → Parse Current**
3. Results appear immediately in the bottom panel

> Saving a script also triggers automatic re-analysis.

---

## 3. Analysis Panels

### Summary

Displays analysis summary for the current file: function count, signal count, variable count, call edges, errors.

### Call Graph

- Lists all call relationships by function: who calls whom (caller → callee)
- Edge type labels: `[self]`, `[super]`, `[ext]` (external object), `[connect]` (signal connection), `[emit]`
- Built-in functions (60+ like `print`, `range`) are automatically filtered out

### Signal Flow

- Lists all signal declarations in the file
- Each signal shows: declaration line, emit site list, connect site list

### Def-Use

- Lists all variables in the file
- Each variable shows: definition location, read site list, write site list

### Project

- Shows project scan results: file list + cross-file reference count per file
- Expand a file to see outbound references (→) and inbound references (←)

---

## 4. Project Scan

Scan all `.gd` files in your project (or specified directories) for cross-file analysis.

### Configure Scan Directories

1. Menu **Project → Tools → GDScript AST Flow → Scan Settings...**
2. Check **Enable Project Scan**
3. Click **Browse...** to select directories, add to Include list
4. To exclude directories, click **Browse...** in the Exclude section (defaults: `res://addons`, `res://.godot`, `res://.git`)
5. Click **Save**

> You can also click the **Scan Settings** button in the Project Tab.

### Run Scan

1. Switch to **Project** Tab
2. Click **Rebuild Project**
3. Wait for scan to complete — file list shows all `.gd` files with reference counts

### Explore Cross-File Relationships

- Expand file → `→ references` shows which other files' methods/signals this file calls
- Expand file → `← referenced by` shows which files reference this file's methods/signals

---

## 5. Graph View Navigation

The main screen "Analysis" Tab provides interactive graph views.

### Scope Switching

| Scope | Description |
|-------|-------------|
| Current File | Call graph / signal flow for the open file |
| Project | Project-level file coupling graph / cross-file signal flow |

### Graph Type Switching

| Graph | Description |
|-------|-------------|
| Call | Method call relationships. Entry functions marked green ▶, hubs (degree≥5) marked orange ● |
| Signal | Signal flow. Emit edges in red, connect edges in blue |

### Toolbar

| Button | Function |
|--------|----------|
| Re-layout | Auto-arrange nodes + center view |
| Min degree | Filter: hide nodes below degree threshold |
| Export JSON | Export CodeGraph JSON to file |

### Node Interaction

- **Click node** → Related nodes highlighted, unrelated nodes dimmed
- **Double-click node** → Jump to source code location
- **Legend** → Shows color meanings for current view, auto-updates on Scope/Graph switch

---

## 6. CodeGraph JSON Export

Export structured code graph for AI agent or external tool consumption.

1. Open Analysis Tab
2. Ensure project scan is complete (Project panel has data)
3. Click **Export JSON**, choose save path
4. Exported JSON includes:
   - `summary` — project statistics
   - `files` — per-file functions/signals/variables/calls/signal flow/def-use
   - `cross_file` — cross-file call/signal edges
   - `hub` — hub function list
   - `coupled` — highly coupled file pairs

---

## 7. FAQ

**Q: Project Tab shows "Project scan is OFF"?**
A: Click **Scan Settings** button → check Enable Project Scan → add directories → Save.

**Q: Analysis results not updating?**
A: Saving a script triggers auto re-analysis. You can also manually **Parse Current**.

**Q: Large project scan is slow?**
A: The current pipeline is implemented in GDScript. Analyzing ~100 files takes a few seconds. See ADR-0002 for performance optimization.

**Q: Too many nodes in graph view?**
A: Use the **Min degree** filter to hide low-degree nodes, or zoom/pan to navigate.
