# Removal Editor

Pick world objects (nodes) in Cyberpunk 2077 with RedHotTools and create ArchiveXL `.xl` presets to remove them.

## Installation

Install this mod and its requirements:

- [Cyber Engine Tweaks](https://www.nexusmods.com/cyberpunk2077/mods/107) (CET), which runs the editor.
- [RedHotTools](https://github.com/psiberx/cp2077-red-hot-tools) (RHT), with all its dependencies.
- [ArchiveXL](https://github.com/psiberx/cp2077-archive-xl), to apply the removals.

For game version 2.5, use **RedHotTools 1.3.0+** and **ArchiveXL 1.28.6+**.

## Quick start

1. Open the CET overlay and find the `Removal Editor` window.
2. In `Presets`, enter a name in `Name...` and click `Create`. Expand the preset and click `Edit`.
3. Find an object in RHT: use `Inspect` for targetable objects and collisions, or `Scan` for other nodes.
4. Click `Send node to Removal Editor` in RHT. Repeat for each object you want to remove.
5. **Make a Quick-Save**, then click the preset's `Install & Reload` button. It installs the preset and reloads the last save; a game must be loaded.

Presets are saved in the mod's `data` folder. To install one manually, copy its `.xl` file to the game's
`archive\pc\mod` folder. **Creating a preset alone does not apply its removals.**

Sending a node from RHT temporarily hides it when supported (for example, mesh nodes). This preview resets when
the game unloads and reloads the node.

## Editing presets

Each preset is a collection of removals. In `Presets`, expand one to edit, install or delete it.
Unreadable files appear in red with an explanation; fix the file, then click its reload icon.

In the `Edit` tab:

- Add the object targeted in RHT's `Inspect` tab with the CET hotkey `Add [Inspect] node`.
- Use `Add all scanned & filtered nodes` to add matching world nodes from RHT's `Scan` results.
- Untick `Add nodes directly from RedHotTools window` to review a node and add a note before clicking `Add Staged Node`.
- Expand a node to edit its note, choose its removed actors or instances, or remove it from the preset.
- Search by type, sector, index, debug name, resource or note. Use `a|b` for either, `a&b` for both, and `a!b` to exclude b. Example: `collision & 8_0_2 ! exterior_6`.
- Right-click the search field to clear it; middle-click a value to copy it. Buttons above the list expand or collapse the results.

## Game version compatibility

**Patch 2.5 reordered sector node indices. Presets made for earlier versions can remove the wrong objects.**

Convert older presets with [ArchiveXL Sector Updater](https://github.com/Akiway/ArchiveXL-Sector-Updater), then
check the results. For YAML presets, click `Mark as made for <version>` after checking or converting them.

New YAML presets record their game version in a `# Game version: 2.5` comment. JSON presets cannot store this
comment, so their version is unknown. A mismatched or unknown version shows a warning and requires a second
click (`Install anyway`) to install.

Nodes commented out by Sector Updater are ignored by ArchiveXL but preserved when saving. Their count and
reasons appear in `Presets`; inspect or search them under `COMMENTED OUT BY AXLSU` in `Edit`.

## Node behaviour and limitations

- **Collisions:** `Inspect` removes only the actor you hit. Target more actors or select them in `Collision Actors` to remove more. Adding a collision from `Scan` removes the whole node.
- **Collision warnings:** removals with `actorDeletions` but no `expectedActors` appear in red because ArchiveXL removes the whole node. Re-send the node from RHT's `Inspect` tab to fix it.
- **Instanced meshes:** targeting an instance removes only that instance.
- **Instanced folliages** are not supported by ArchiveXL at the moment.
- **Occluders:** RHT does not detect instanced mesh occluder nodes. Try [VS2077](https://github.com/notaspirit/VolumetricSelection2077) to find them.

## Settings and file storage

In `Settings`, choose YAML or JSON for new presets, toggle deletion confirmation, choose whether to teleport
back after `Install & Reload`, or enable staged editing. `Advanced` shows the data folder and lets you reset
settings; `Dependencies` checks required versions and optional integrations. Settings are saved in `data\config.json`.

Presets keep their original format; new ones default to YAML. YAML preserves comments and key order while
normalising indentation and list layout. Comments attached to a deleted node are removed with it; entries
commented out by Sector Updater are kept, including sectors containing only those entries.

Notes are stored in each removal's `note` field, ignored by ArchiveXL, and follow the node when converted with
Sector Updater. Older `data\notes.json` files are migrated automatically into readable presets, then renamed
to `notes.migrated.json`. Unmatched notes remain in that backup. To retry migration, rename it to `notes.json`
and restart the game.
