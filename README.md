<div align="center">

<img src="assets/logo.png" alt="Eclipse Animator" width="100%">

# Eclipse Animator Open

**A next-generation animation suite for Roblox Studio — built for animators who outgrew the basics.**

![Platform](https://img.shields.io/badge/Platform-Roblox%20Studio-blue?style=for-the-badge)
![Built With](https://img.shields.io/badge/Built%20With-Luau-00A2FF?style=for-the-badge)
![Type](https://img.shields.io/badge/Type-Animation%20Plugin-orange?style=for-the-badge)
![Status](https://img.shields.io/badge/Status-Pre--Paid%20Build-purple?style=for-the-badge)
![Price](https://img.shields.io/badge/Price-Free-success?style=for-the-badge)
![Source](https://img.shields.io/badge/Source-362%20unpacked%20scripts-blueviolet?style=for-the-badge)

</div>

---

> ### About this repository
>
> This repository hosts **Eclipse Animator Open** — the build of Eclipse
> Animator that was published before the plugin became a paid product.
>
> It is preserved here in the exact state it existed in when it was still freely available: one `.rbxm` plugin file, no license server, no account checks, no microtransactions. Everything loads straight into Roblox Studio and works out of the box.
>
> The goal of this repository is simple — keep the original free release accessible to the animation community that helped the project grow in the first place. As well as the original file, the repository now carries the plugin's complete source, unpacked and editable, so the build can be studied and changed instead of just installed.

## Download

| Download | Use it for |
| :--- | :--- |
| **[Eclipse Animator Open.rbxm](https://github.com/7kg2-here/Eclipse-Animator-free/releases/latest/download/Eclipse%20Animator%20Open.rbxm)** | installing the plugin (drop it in your Studio `Plugins` folder) |
| **[Eclipse Animator Open.rbxmx](https://github.com/7kg2-here/Eclipse-Animator-free/releases/latest/download/Eclipse%20Animator%20Open.rbxmx)** | reading and editing the whole plugin in VS Code or any text editor |
| **[Latest release](https://github.com/7kg2-here/Eclipse-Animator-free/releases/latest)** | both files plus the complete source archive in one zip, with checksums |

Both plugin files do the same thing — Studio opens `.rbxm` and `.rbxmx` alike.

---

> **The build is not encrypted.** It is a standard Roblox binary model (`.rbxm`)
> with LZ4-compressed chunks — that compression is all "the encryption" ever was.
> Its 362 scripts have been unpacked into plain, editable `.luau` files under
> [`src/`](#editable-source), and `tools/` can pack them back into a working
> plugin. See [Editable Source](#editable-source).

---

## Table of Contents

- [About Eclipse Animator](#about-eclipse-animator)
- [Editable Source](#editable-source)
- [Open the plugin in a text editor](#open-the-plugin-in-a-text-editor)
- [Plugin at a Glance](#plugin-at-a-glance)
- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Compatibility and Requirements](#compatibility-and-requirements)
- [Repository Contents](#repository-contents)
- [Changelog](#changelog)
- [Frequently Asked Questions](#frequently-asked-questions)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License and Disclaimer](#license-and-disclaimer)

---

## About Eclipse Animator

**Eclipse Animator** is a full-featured animation plugin for Roblox Studio. It was designed as a serious alternative to the tools animators had been forced to choose between: timeline plugins that feel too limited, and external 3D software with a steep learning curve and a painful round-trip back into Studio.

It brings the workflow animators actually want into one window:

- A timeline that behaves like a real editor.
- Rigging controls that support both Inverse and Forward Kinematics.
- Physics that can be simulated directly in the viewport.
- Collaborative editing inside Team Create.
- Export paths that take your animation from the timeline all the way into a shipped game.

Whether you are making combat animations, cinematics, cutscenes, emotes, or full character performances, Eclipse Animator is built to handle the entire pipeline without leaving Roblox Studio.

---

## Editable Source

The plugin in this repository is often described as "encrypted", but it never
was: a `.rbxm` is Roblox's binary model format and its chunks are simply
LZ4-compressed. This repository now also ships the **whole plugin unpacked into
readable, editable files**, plus the tools that do the unpacking and the
repacking.

| Path | What it is |
| :--- | :--- |
| `src/` | all 362 `Script` / `LocalScript` / `ModuleScript` sources as plain `.luau` files (6.0 MB) in a tree that mirrors the plugin hierarchy — real Luau, comments and formatting intact |
| `src/manifest.json` | the map between every file and the model: referent, class, in-plugin path, size, SHA-256 |
| `src/_tree.txt` | the complete instance tree — all 2,195 instances with their class names |
| `assets/logo.png` | the project logo — the plugin's own artwork (`rbxassetid://126656292244944`, the mark its About window and header use), recovered at 1024×1024 from the author's public Eclipse Video build, plus `assets/icon.png` as a square icon |
| `tools/rbxm.py` | a dependency-free reader/writer for the binary model format: every chunk type, every property type, LZ4 and ZSTD |
| `tools/unpack.py` | `.rbxm` → editable source tree |
| `tools/repack.py` | edited source tree → `.rbxm` |
| `tools/README.md` | full usage notes |

The sources are grouped the same way the plugin groups them, for example:

```
src/Eclipse Animator/
├── Container/
│   ├── Animation/     Core/       Effects/    Geometry/
│   ├── Input/         Interface/  Rigging/    Shared/
│   ├── Storage/       Timeline/   Utility/
│   └── (Project, Export, Recovery, Layers, RigTraversal, …)
├── manifest.json
└── _tree.txt
```

### Rebuild the plugin

```bash
# edit anything under src/ ...

python3 tools/repack.py                 # writes EclipseAnimator.rbxm
python3 tools/repack.py --verify-only    # just list the scripts that differ
python3 tools/repack.py --full           # re-encode every chunk, not only sources
```

`repack.py` re-encodes only the `Source` chunks that changed and copies every
other chunk out of the original file byte-for-byte, so editing one script can
never disturb the rest of the model. It then reads its own output back and
verifies all 362 scripts, the instance hierarchy and the shared-string table
before reporting success. Repacking an untouched `src/` reproduces the original
file byte-for-byte.

To inspect the rest of the model as text — UI sizes, colors, CFrames, keyframe
tables, everything — dump every property of every instance:

```bash
python3 tools/unpack.py "Eclipse Animator Open.rbxm" src --model-json
# -> src/_model.json
```

Install the rebuilt `EclipseAnimator.rbxm` exactly as described in
[Installation](#installation).

---

## Open the plugin in a text editor

A `.rbxm` is a packed binary container — open it in VS Code and you only get
binary noise. That is exactly why this repository also ships the **same plugin
as XML**, which is plain text:

| File | What it is |
| :--- | :--- |
| `Eclipse Animator Open.rbxm` | the plugin, packed (install this one) |
| `Eclipse Animator Open.rbxmx` | the very same plugin as readable XML — open it in VS Code, Notepad, or any text editor |
| `tools/rbxmx.py` | converts between the two |

Both files install the same way in Roblox Studio; Studio reads either format.

### Edit it by hand

1. Open `Eclipse Animator Open.rbxmx` in VS Code (it is ~10 MB of ordinary
   text; syntax highlighting works, and searching for `Deaths`, `Timeline`, a
   function name, or a dialog string jumps straight to it).
2. Every script sits in a `<ProtectedString name="Source">` element as plain
   Luau:

   ```xml
   <Item class="ModuleScript" referent="42">
     <Properties>
       <ProtectedString name="Source"><![CDATA[
   local Players = game:GetService("Players")
   -- … edit freely …
   ]]></ProtectedString>
   </Properties>
   <Item class="LocalScript" referent="43">…</Item>
   </Item>
   ```

   Every other property is readable too — `<Vector3>`, `<Color3>`, `<UDim2>`,
   `<token>` (enums), `<Ref>` (object links), `<BinaryString>` (attributes),
   `<SharedString>` definitions at the bottom of the file.
3. Convert your edited XML back into an installable plugin:

   ```bash
   python3 tools/rbxmx.py "Eclipse Animator Open.rbxmx" "Eclipse Animator Open.rbxm"
   ```

   …or open the `.rbxmx` in Studio directly with **Insert from File…** and use
   **Save as Local Plugin**.

The converter is lossless in both directions: `rbxm → rbxmx → rbxm` reproduces
every property, every parent/child link and the whole shared-string table
byte-for-byte-equal in value. Editing works, too — a change made inside the XML
shows up in the rebuilt `.rbxm`.

---

## Plugin at a Glance

| Item | Details |
| :--- | :--- |
| **Name** | Eclipse Animator |
| **Category** | Animation and rigging plugin |
| **Host application** | Roblox Studio |
| **Language** | Luau |
| **Distribution format** | `.rbxm` model file (local plugin) |
| **Interface** | Dockable viewport-anchored suite with a full timeline and curve editor |
| **Primary use cases** | Character animation, combat, emotes, cutscenes, cinematic work |
| **Supported rigs** | R6, R15, custom and imported rigs |
| **Collaboration** | Live editing in Team Create sessions |
| **Build in this repository** | Pre-paid release — fully free, no gating, no key system |
| **Current upstream status** | Continued development as a paid product |

---

## Features

### Animation and Timeline

- **Professional timeline editor** with frame-accurate scrubbing, multi-track layers, and instant playback.
- **Bezier and multi-mode easing** for every keyframe — shape motion instead of settling for linear.
- **Graph and curve editing** so you can tune ease-in, ease-out, overshoot, and snap precisely.
- **Pose system** for storing, reusing, and blending poses across an animation.
- **Keyframe manipulation tools** — move, scale, mirror, and retime selected ranges in bulk.
- **Copy and paste between track layers** to build complex sequences fast.

### Rigging and Motion Control

- **Toggleable IK and FK** — lock a hand, foot, or head in space with Inverse Kinematics, then switch back to Forward Kinematics mid-timeline without breaking your keys.
- **Custom rig support** — works with non-standard skeletons, not just default character rigs.
- **Dynamic parenting** — keyframe an object's parent so a weapon can follow a hand during a fight and detach a moment later.
- **Character and prop handling** in a single scene, so deformation and weapon motion stay in sync.
- **Blender rig import** — bring skeletons from Blender into Studio as usable Roblox rigs.

### Physics and Simulation

- **Viewport physics simulation** — animate the throw, hit Simulate, and let physics resolve the ragdoll, impact, or flying prop.
- **Hybrid workflows** — combine hand-authored keyframes with simulated motion in the same timeline.
- **Stable playback** — preview results without leaving the editor or duplicating your scene.

### Collaboration and Team Workflow

- **Live Team Create collaboration** — multiple animators can work on the same animation file at the same time.
- **Shared sessions** — review, adjust, and hand off shots without exporting files back and forth.
- **Studio-native** — nothing to install outside Roblox Studio.

### Productivity and Reliability

- **Crash recovery** — background timeline snapshots let you restore your session after an unexpected crash.
- **Picture-in-picture camera preview** — watch your camera shot in a small window while the timeline stays full size.
- **Pose and audio asset library** — a built-in library of reusable poses and audio clips.
- **Grease pencil sketching** — sketch over the viewport to plan motion and timing before committing to keys.
- **Fully customizable keybinds** — remap the entire workflow to match how you animate.
- **Customizable interface** — dock, resize, and reorganize panels to fit your screen.

### Export and In-Game Playback

- **Animation export** ready for use in your games.
- **ModuleScript exporter** to move authored motion into scriptable, reusable modules.
- **Unparented animation support** for effects, props, and rigs that do not follow the standard character hierarchy.
- **Optimized output** that stays clean when it reaches runtime.

### Rendering and Cinematic Effects

- **Camera shake presets** for impact-driven action.
- **Impact frames** for stylized hits and combat readability.
- **Cinematic helpers** for cutscene framing and shot control.

---

## Installation

Eclipse Animator ships as a single `.rbxm` file and installs as a **local plugin** in Roblox Studio. There is no key system, no login, and no dependency on any external service.

### Method 1 — Local plugin folder (recommended)

1. Download `Eclipse Animator Open.rbxm` from this repository (or build
   `EclipseAnimator.rbxm` from `src/` with `tools/repack.py`).
2. Open your Roblox Studio plugins folder:

   **Windows**

   ```
   %LOCALAPPDATA%\Roblox\Plugins
   ```

   **macOS**

   ```
   ~/Documents/Roblox/Plugins
   ```

   If the `Plugins` folder does not exist, create it manually.

3. Copy the `.rbxm` file into that folder — `Eclipse Animator Open.rbxm` as
   downloaded, or `EclipseAnimator.rbxm` if you rebuilt it from source.
4. Restart Roblox Studio completely.
5. Eclipse Animator appears in the **Plugins** tab of the ribbon.

### Method 2 — Insert from file

1. Open Roblox Studio with any place file.
2. Right-click **Workspace** or **ServerStorage** in the Explorer.
3. Choose **Insert from File...** and select the `.rbxm`.
4. Right-click the inserted object and choose **Save as Local Plugin**.

This method is useful when you want to inspect the plugin contents before installing it, or when you are setting up a temporary testing environment.

### Verifying the install

After installation, open the Plugins tab in Studio's ribbon. The Eclipse Animator button should be present and open its main window when clicked.

---

## Quick Start

1. **Prepare a rig.** Place a character model — R6, R15, or a custom rig — into the workspace.
2. **Launch Eclipse Animator** from the Plugins tab.
3. **Select your rig** in the plugin window to bind it to the timeline.
4. **Create a new animation** and give it a name.
5. **Pose your rig** in the viewport, then set keyframes at the current frame.
6. **Move the playhead** and repeat to build the sequence.
7. **Shape the motion** with easing curves and the graph editor.
8. **Preview the result** in the viewport or through the picture-in-picture camera.
9. **Export the animation**, or use the ModuleScript exporter for scriptable playback.

---

## Core Concepts

| Concept | What it means |
| :--- | :--- |
| **Timeline** | The primary workspace where frames, tracks, and keyframes live. |
| **Track layer** | A row in the timeline that holds keyframes for one rig component or object. |
| **Keyframe** | A stored pose or value at a specific frame. |
| **Easing / Bezier** | The interpolation curve that controls how motion travels between two keyframes. |
| **IK** | Inverse Kinematics — position the end of a limb and let the chain solve itself. |
| **FK** | Forward Kinematics — rotate joints directly, one link at a time. |
| **Dynamic parenting** | Parent relationships that can change over the course of an animation. |
| **Simulation** | Physics-driven motion applied on top of or instead of keyframed motion. |
| **Snapshot** | A background save of timeline state used for crash recovery. |

---

## Keyboard Shortcuts

The default bindings are listed below, and every one of them can be remapped from the plugin's settings panel.

| Action | Default binding |
| :--- | :--- |
| Play / Pause | `Space` |
| Next frame | `Right Arrow` |
| Previous frame | `Left Arrow` |
| Set keyframe | `K` |
| Delete keyframe | `Delete` |
| Toggle IK / FK | Configurable in settings |
| Simulate physics | Configurable in settings |
| Toggle camera preview | Configurable in settings |

---

## Compatibility and Requirements

| Requirement | Details |
| :--- | :--- |
| **Roblox Studio** | Current release channel recommended |
| **Operating system** | Windows and macOS |
| **Rig support** | R6, R15, custom rigs, imported Blender rigs |
| **Team Create** | Supported for live collaborative editing |
| **External dependencies** | None |
| **Account requirements** | None — the plugin runs entirely inside Studio |

---

## Repository Contents

```
.
├── Eclipse Animator Open.rbxm   # The plugin file — install this (Roblox binary model)
├── assets/
│   ├── logo.png                    # Project logo banner, shown at the top of this README
│   └── icon.png                    # Square logo mark
├── src/                            # The plugin, unpacked and editable
│   ├── Eclipse Animator/           # 362 .luau scripts mirroring the plugin tree
│   ├── manifest.json               # referent ⇄ file map with checksums
│   └── _tree.txt                   # the full instance tree (2,195 instances)
├── tools/                          # Unpack / repack toolkit
│   ├── rbxm.py                     # Binary model reader + writer
│   ├── unpack.py                   # .rbxm  →  src/
│   ├── repack.py                   # src/   →  .rbxm
│   └── README.md                   # Tool documentation
├── README.md                       # This documentation
└── LICENSE                         # Usage terms
```

Running `python3 tools/repack.py` after editing `src/` writes
`EclipseAnimator.rbxm`, the installable plugin build.

---

## Changelog

### Open release (this repository)

- Renamed to **Eclipse Animator Open**.
- Added `Eclipse Animator Open.rbxmx` — the whole plugin as readable XML that opens in any text editor.
- Added `tools/` — unpack/repack/conversion toolkit, plus the full source under `src/`.
- Added the project logo in `assets/`.

### Pre-paid release (original upload)

- Published as the original free release of Eclipse Animator.
- Includes the full animation suite: timeline, IK/FK, physics simulation, collaboration, crash recovery, exporters, and render effects.
- No license checks, no account binding, no paid tier restrictions.

### Later development

Following this release, Eclipse Animator continued development as a paid product. Newer upstream versions are not part of this repository.

---

## Frequently Asked Questions

<details>
<summary><strong>I opened the .rbxm in VS Code and it is gibberish — where is the code?</strong></summary>

A `.rbxm` is a packed binary container, so a text editor shows binary, not text.
The code lives in the **XML** twin of the same file: open
`Eclipse Animator Open.rbxmx` and every one of the 362 scripts is right there as
readable Luau inside `<ProtectedString name="Source">` elements. Edit the text,
then convert it back with `python3 tools/rbxmx.py` (see
[Open the plugin in a text editor](#open-the-plugin-in-a-text-editor)), or work
with the extracted `.luau` files in `src/` instead.
</details>

<details>
<summary><strong>Can I edit it and keep using it in Studio?</strong></summary>

Yes. Edit the `.rbxmx` in any text editor and convert it back, or edit the
`.luau` files under `src/` and run `tools/repack.py`. Either route produces a
plugin file Studio loads normally.
</details>

<details>
<summary><strong>Is this the latest version of Eclipse Animator?</strong></summary>

No. This repository contains the build that was published before the plugin became a paid product. It is frozen at that point in development and does not include anything added afterward.
</details>

<details>
<summary><strong>Does this build require a license key or payment?</strong></summary>

No. There is no key system, no login, and nothing to activate. Install the file and it works.
</details>

<details>
<summary><strong>Which Studio versions does it work with?</strong></summary>

It is intended for current Roblox Studio releases on Windows and macOS. Running older or heavily modified Studio builds may cause unexpected behavior.
</details>

<details>
<summary><strong>Can I use it with custom rigs?</strong></summary>

Yes. R6, R15, custom skeletons, and rigs imported from Blender are all supported.
</details>

<details>
<summary><strong>Does it work in Team Create?</strong></summary>

Yes. Live collaborative editing is one of its core features, letting several animators work inside the same animation file at once.
</details>

<details>
<summary><strong>Can I export animations into my own game?</strong></summary>

Yes. Animations can be exported for in-game use, and the ModuleScript exporter lets you drive motion from scripts.
</details>

<details>
<summary><strong>Is it safe to install?</strong></summary>

Yes. It is a `.rbxm` model file installed locally through Studio's own plugin system, and it contains no obfuscated code — every script is plain Luau, unpacked for you under [`src/`](#editable-source). You can also use Method 2 below to inspect it inside Studio before saving it as a local plugin.
</details>

<details>
<summary><strong>What happens if Studio crashes while I am animating?</strong></summary>

The plugin keeps background snapshots of your timeline state and can restore your session after a crash.
</details>

---

## Troubleshooting

| Problem | Solution |
| :--- | :--- |
| The plugin does not appear in the Plugins tab | Confirm the `.rbxm` is inside the correct `Plugins` folder and restart Studio completely. |
| The plugin button appears but the window is blank | Update Roblox Studio to the latest release and relaunch. |
| Playback feels choppy | Reduce scene complexity during preview, or close other viewport-heavy panels. |
| Keyframes look wrong after retiming | Check your easing curves in the graph editor, then re-scrub the timeline to refresh. |
| Physics simulation behaves unexpectedly | Confirm the rig's collision and mass properties, then re-run the simulation from a clean state. |
| Team Create edits do not sync | Verify your connection and that all collaborators are in the same session. |
| Visuals or layout look broken | Reset the plugin's interface layout from its settings, then re-dock the panels. |

---

## Contributing

- **Bug reports:** open an issue with your Studio version, operating system, and the exact steps to reproduce.
- **Feature requests:** open an issue describing the workflow you are trying to achieve.
- **Documentation fixes:** pull requests that correct or extend this README are welcome.
- **Please do not:** repackage and resell this build as your own paid product.

---

## License and Disclaimer

This build is shared for free use by the animation community, in the state it existed before Eclipse Animator became a paid product.

- You may install it, use it in your own projects, and share this repository.
- You may not resell it or redistribute it behind a paywall.
- It is provided **as is**, without warranty of any kind. The maintainers of this repository are not responsible for any loss of data, project corruption, or other damage arising from its use.
- This repository is an archive of a past release. It is not affiliated with, or supported by, any current paid distribution of the plugin.

Always keep backups of your places and animation files before adopting any plugin into a production workflow.

---

<div align="center">

**Eclipse Animator — the pre-paid release, preserved.**

*Animating in Roblox Studio, the way it should have always worked.*

</div>
