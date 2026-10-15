# Eclipse Animator

**A next-generation animation suite for Roblox Studio — built for animators who outgrew the basics.**

![Platform](https://img.shields.io/badge/Platform-Roblox%20Studio-blue?style=for-the-badge)
![Built With](https://img.shields.io/badge/Built%20With-Luau-00A2FF?style=for-the-badge)
![Type](https://img.shields.io/badge/Type-Animation%20Plugin-orange?style=for-the-badge)
![Status](https://img.shields.io/badge/Status-Pre--Paid%20Build-purple?style=for-the-badge)
![Price](https://img.shields.io/badge/Price-Free-success?style=for-the-badge)

---

> ### About this repository
>
> This repository hosts the **Eclipse Animator build that was published before the plugin became a paid product.**
>
> It is preserved here in the exact state it existed in when it was still freely available: one `.rbxm` plugin file, no license server, no account checks, no microtransactions. Everything loads straight into Roblox Studio and works out of the box.
>
> The goal of this repository is simple — keep the original free release accessible to the animation community that helped the project grow in the first place.

---

## Table of Contents

- [About Eclipse Animator](#about-eclipse-animator)
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

1. Download the `.rbxm` file from this repository.
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

3. Copy the `.rbxm` file into that folder.
4. Restart Roblox Studio completely.
5. Eclipse Animator appears in the **Plugins** tab of the ribbon.

<!-- If your .rbxm file has a different name, update the steps above to match the file you actually ship in this repository. -->

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

<!-- Confirm each default binding against your build before publishing, and adjust the table if it differs. -->

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
├── EclipseAnimator.rbxm     # The plugin file — install this
├── README.md                # This documentation
└── LICENSE                  # Usage terms
```

<!--
Replace the tree above with your real file names and folders.
If you also ship screenshots, add a screenshots/ or assets/ folder and list it here.
-->

---

## Changelog

### Pre-paid release (this repository)

- Published as the original free release of Eclipse Animator.
- Includes the full animation suite: timeline, IK/FK, physics simulation, collaboration, crash recovery, exporters, and render effects.
- No license checks, no account binding, no paid tier restrictions.

### Later development

Following this release, Eclipse Animator continued development as a paid product. Newer upstream versions are not part of this repository.

---

## Frequently Asked Questions

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

The plugin is a `.rbxm` model file installed locally through Studio's own plugin system. If you want full transparency, use Method 2 in the installation section to inspect its contents before saving it as a local plugin.
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
