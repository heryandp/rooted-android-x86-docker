# `emu-root` — Local Rooted Android 12 Emulator (Play Store + Magisk)

Cross-platform CLI launcher and automated installer for running a rooted **Android 12 (API 31) Google Play** Android Virtual Device (`Pixel_7_API_31_Rooted`) with **Magisk** (via `rootAVD`) on **Windows**, **macOS (Intel `x86_64` & Apple Silicon `arm64`)**, and **Ubuntu / Debian (`.sh` & `.deb`)**.

---

## Default AVD Profile

| Setting | Value |
|---|---|
| AVD Name | `Pixel_7_API_31_Rooted` |
| Android Version | Android 12 (API 31) — Google Play Store (`google_apis_playstore`) |
| Architecture | `x86_64` (Windows / Intel Mac / Linux x86_64) · `arm64-v8a` (Apple Silicon Mac / Linux arm64) |
| Hardware | 4 vCPU, 4096 MB RAM, 512 MB VM Heap, 8 GB Data Partition, GPU `host` |
| Boot Mode | Cold Boot (`-no-snapshot -no-metrics`) |
| Root Method | Magisk ramdisk patch (`rootAVD`, original `ramdisk.img.backup` preserved) |

---

## Installation

### 1. Windows (PowerShell)
```powershell
cd emu-root\installers\windows
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1
```
- Installs/verifies JDK 17, Android SDK `cmdline-tools`, `platform-tools`, `emulator`, and `android-31;google_apis_playstore;x86_64`.
- Creates `Pixel_7_API_31_Rooted`, patches `ramdisk.img` with Magisk via `rootAVD`.
- Installs `emu-root.cmd` into `%USERPROFILE%\bin` (safe from Android SDK updates) and adds it to your User `PATH`.

### 2. macOS (Intel `x86_64` & Apple Silicon `arm64`)
```bash
cd emu-root/installers/macos
chmod +x install-macos.sh
./install-macos.sh
```
- Automatically detects `uname -m`:
  - **Apple Silicon (`arm64`)**: uses `arm64-v8a` system image & `/opt/homebrew`
  - **Intel Mac (`x86_64`)**: uses `x86_64` system image & `/usr/local`
- Sets up `~/Library/Android/sdk`, creates `Pixel_7_API_31_Rooted`, runs `rootAVD.sh`, and installs `emu-root` into `/usr/local/bin` (or `~/.local/bin`).

### 3. Ubuntu / Debian — `.sh` Installer
```bash
cd emu-root/installers/ubuntu
chmod +x install-ubuntu.sh
./install-ubuntu.sh
```

### 4. Ubuntu / Debian — `.deb` Package
Build and install the Debian package:
```bash
cd emu-root/installers/ubuntu
chmod +x build-deb.sh
./build-deb.sh 1.0.0
sudo apt install ../../../dist/emu-root_1.0.0_all.deb

# Then complete SDK, AVD & Magisk setup as your normal user:
emu-root --setup
```

---

## CLI Usage

```bash
emu-root                   # Cold-boot Pixel_7_API_31_Rooted and wait until boot_completed=1
emu-root --status          # Show SDK paths, KVM/OS info, and connected ADB devices
emu-root --root            # Open Magisk root shell (adb -e shell su)
emu-root --shell           # Open standard ADB shell (adb -e shell)
emu-root --headless        # Boot without GUI/audio (-no-window -no-audio)
emu-root --wipe            # Boot with -wipe-data
emu-root --avd My_AVD      # Launch a different AVD name
emu-root --stop            # Gracefully stop the running emulator
emu-root --help            # Show all options
```

> **Tip:** First time after rooting, open the **Magisk** app inside the Android drawer once to finish any stub setup and grant superuser prompts for `adb -e shell su`.
