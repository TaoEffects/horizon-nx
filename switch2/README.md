# Horizon on Nintendo Switch 2 (kaiHEN / libounce / OunceVK)

Native **Minecraft: Java Edition 26.3** (Horizon, written in Rust + `wgpu`) ported to **Nintendo Switch 2** using `libounce` and **OunceVK** (Vulkan).

## What works

- **1080p @ 120 Hz + VRR** (`nwindowSetDimensions(1920, 1080)` + `nwindowSetFrameRates(0, 0, true)`).
- **6 Switch 2 application CPU cores** (`InfoType_CoreMask` `0b111111`, 5 chunk generation/meshing workers).
- **Native Switch 2 Audio** (`audout`, 48 kHz stereo 16-bit PCM double-buffered).
- **Joy-Con 2 & Pro Controller** (`gilrs` + `libounce` pad) with **`-` (Minus)** toggling the **F3 Debug Screen** (rebindable in *Options → Controls → Controller*).
- **Built-in FPS & Frame Graph overlay** (*Options → Horizon Settings → Overlay → FPS / FPS and Graph*).
- **Joy-Con 2 Mouse Mode & USB Mouse** (`libounce` Nmouse):
  - Right Joy-Con / USB mouse moves the cursor in menus and turns the camera in-game.
  - `R` = Left Click (Break/Attack), `ZR` = Right Click (Place/Use), `R-Stick` press = Middle Click (Pick Block).
  - Left Joy-Con stick stays dedicated to walking without scrolling the hotbar.
- **Touch screen** calibrated to 1080p.
- **Switch 2 Graphics Presets** (`Performance` 10 chunks, `Balanced` 14, `Quality` 18, `Ultra` 24; render distance up to 32, simulation up to 20).
- **Shader Packs** (OptiFine/Iris GLSL `.zip` packs and Horizon WGSL packs in `shaderpacks/`).
- **Content Mods** (`.hmod` in `mods/`, toggled in *Options → Mods*).

---

## Player Installation (No Mojang files included)

> **Legal notice:** This repository and its releases **never** contain Minecraft/Mojang assets, `.jar` files, or prepared resources. You must supply your own legitimately owned copy of **Minecraft: Java Edition 26.3**.

### 1. Prepare your Minecraft 26.3 resources on PC/Mac

Install and run the official **Horizon Launcher** (or run `horizon-prepare`) on your PC/Mac with your legitimate Minecraft Java Edition 26.3 installation. It generates a prepared resource folder:

- **macOS:** `~/Library/Application Support/horizon-launcher/versions/<version>/.local/horizon-client/26.3/`
- **Windows:** `%APPDATA%\horizon-launcher\versions\<version>\.local\horizon-client\26.3\`
- **Linux:** `~/.local/share/horizon-launcher/versions/<version>/.local/horizon-client/26.3/`

Verify that this folder contains `horizon-resources.json`, `assets/`, `data/`, etc.

### 2. Copy to your Switch 2 SD card

Create `/switch/horizon/` on your SD card with the following layout:

```text
sdmc:/switch/horizon/
├── horizon.nro          # from the GitHub Release
├── client.txt           # empty/marker file forcing client mode
├── env.txt              # optional (e.g. disable telemetry/update checks offline)
├── resources/           # contents of your prepared 26.3/ folder
│   ├── horizon-resources.json
│   ├── assets/
│   └── data/
├── shaderpacks/         # optional: drop .zip OptiFine/Iris or .hshader packs here
└── mods/                # optional: drop .hmod content mods here
```

Recommended `env.txt` (especially for offline consoles):

```ini
HORIZON_TELEMETRY_URL=off
HORIZON_NO_HEARTBEAT=1
HORIZON_NO_UPDATE_CHECK=1
```

### 3. Launch

1. Launch **hbmenu** with **Title Override** (hold `R` while launching a native Switch 2 title so Horizon gets the full ~9 GiB RAM and 6 CPU cores).
2. Start **Horizon** (`horizon.nro`).

---

## Building from Source

### Prerequisites

- Rust nightly toolchain (`nightly-2026-07-02` with `rust-src` component)
- devkitA64 + `libounce` + OunceVK (`DEVKITPRO`)
- Companion Switch patches (`../horizon-switch-toolkit/switch/patches/`, with `switch2/patches/winit-switch2.patch` applied to `winit-0.30.13`)

### Compile & Package

```sh
export DEVKITPRO=/path/to/devkitpro
bash switch2/build-sysroot.sh

# IMPORTANT: package WITHOUT --alignedheader so NRO flags == 0
"$DEVKITPRO/tools/bin/elf2nro" \
  target/aarch64-switch-horizon/release/horizon-client \
  horizon.nro \
  --nacp=horizon-nx2.nacp
```

`switch2/build-sysroot.sh` automatically prepares a patched `rust-src` copy so `build-std` builds `std` against the AArch64 Switch `libc-0.2.191` layout (preventing 3DS `struct stat`/`dirent` mismatches) and links all `horizon-nx` `--wrap=` shims (including the 1024-key `pthread_key_*` table, `rename`, `fchmod`, `fcntl`, `rmdir`, `fsFileWrite`, `fsFileSetSize`, and `threadCreate`).
