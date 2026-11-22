# AGENTS.md

Instructions and operating guidelines for AI coding agents (Antigravity, OpenBot, Codex, Claude Code, Gemini CLI, Cursor, etc.) working with this repository or connecting to its Android environments.

---

## 1. Repository Overview

This repository provides two independent rooted **Android 12 (API 31)** stacks:

| Directory | Target Environment | Stack | Entry Points |
|---|---|---|---|
| `emu-root/` | Local workstation (Windows, macOS Intel & Apple Silicon, Ubuntu/Debian) | Official Android Emulator AVD (`Pixel_7_API_31_Rooted`) + Google Play + Magisk (`rootAVD`) | `emu-root/bin/emu-root.cmd`, `emu-root/bin/emu-root`, `emu-root/installers/*` |
| `redroid-docker/` | Standard Linux VPS (**no `/dev/kvm` required**) | Redroid Android 12 (`64only`) + MindTheGapps + `libndk` ARM64 + Magisk + `ws-scrcpy` + Nginx Basic Auth | `redroid-docker/install-vps.sh`, `redroid-docker/docker-compose.yml`, `redroid-docker/scripts/*` |

### Choosing the Right Stack
- **Has hardware virtualization** (Windows WHPX/HAXM, macOS HVF, Linux `/dev/kvm`) → use **`emu-root/`**.
- **Standard cloud VPS without `/dev/kvm`** (e.g., Ubuntu 22.04/24.04 with `binder_linux` / `binderfs`) → use **`redroid-docker/`**.
- **Google Colab / unprivileged containers** without `/dev/kvm` AND without `binder_linux` → neither stack is viable; recommend a Linux VPS with `binder_linux` or a Cloud VM with nested KVM.

---

## 2. Connecting an AI Agent to the Running Android Environment

### A. Local `emu-root`
Always target the emulator explicitly using `adb -e` so physical USB devices are never disturbed.

```bash
# Start emulator (cold boot, waits until sys.boot_completed=1)
emu-root                 # or: emu-root --headless

# Verify status & root
emu-root --status
adb -e shell getprop sys.boot_completed
adb -e shell su -c id

# Inspect screen & UI tree for agentic automation
adb -e exec-out screencap -p > /tmp/screen.png
adb -e shell uiautomator dump /sdcard/window_dump.xml
adb -e pull /sdcard/window_dump.xml /tmp/window_dump.xml

# Stop cleanly when done
emu-root --stop
```

### B. Cloud VPS `redroid-docker`
On the VPS host (or over an SSH tunnel `ssh -L 5555:127.0.0.1:5555 <user>@<vps-ip>`):

```bash
# Check container & ADB health
/opt/redroid/scripts/manage.sh status
/opt/redroid/scripts/manage.sh stats

# Connect ADB locally (port 5555 is strictly bound to 127.0.0.1)
adb connect 127.0.0.1:5555
adb -s 127.0.0.1:5555 shell getprop ro.build.version.release
adb -s 127.0.0.1:5555 shell getprop ro.product.cpu.abilist

# Note: Magisk `su` requires initial approval in the Magisk Manager app
# (accessible via ws-scrcpy Web UI), or use `adb -s 127.0.0.1:5555 root` on Redroid userdebug builds.

# Free RAM on shared VPS when idle (~1.8 GB saved)
/opt/redroid/scripts/manage.sh stop
```

> **Note for non-interactive shells / piped scripts:** Always redirect stdin with `</dev/null` when running `adb shell` inside piped `bash -s` loops, otherwise `adb shell` consumes the remaining script from stdin.

---

## 3. Hard Security & Operational Guardrails

Agents MUST follow these rules at all times:

1. **Never expose ADB (`5555`) to `0.0.0.0`:**
   - Keep `ADB_BIND=127.0.0.1:5555` in `redroid-docker/docker-compose.yml` and `.env`.
   - Remote ADB must always go through an SSH tunnel, WireGuard, or Tailscale.
2. **Never expose `ws-scrcpy` without authentication:**
   - `ws-scrcpy` provides interactive screen control, shell, and file access to a privileged Android container.
   - Always front public Web UI access with `redroid-docker/scripts/setup-nginx-auth.sh` (HTTP Basic Auth) or an authenticated HTTPS reverse proxy.
3. **Never commit secrets or host-specific data:**
   - Never commit `.env`, `.htpasswd*`, private IP addresses, SSH passwords/keys, tokens, or personal emails.
   - Always use placeholders (`<YOUR_VPS_IP>`, `ubuntu`) in docs, templates, and examples.
4. **Respect VPS resource caps:**
   - Keep `mem_limit` (`2560m` default for `redroid`, `256m` for `ws-scrcpy`) intact on multi-tenant VPS hosts.
   - Keep `ramdisk.img.backup` intact when patching AVDs with `rootAVD`.
5. **Respect platform architecture differences:**
   - macOS Apple Silicon (`arm64`) must use `arm64-v8a` system images and `/opt/homebrew`.
   - macOS Intel (`x86_64`), Windows, and Linux `x86_64` use `x86_64` system images.
   - Ubuntu 24.04 (kernel 6.8+) uses `binderfs` + `androidboot.use_memfd=true` (do not require `ashmem_linux`).

---

## 4. Development & Verification Checklist

When modifying scripts, installers, or packaging in this repository:

- **Line Endings (`.gitattributes`):**
  - Keep **LF** for all `.sh`, `emu-root/bin/emu-root`, `emu-root/packaging/deb/DEBIAN/*`, `.yml`, and `.conf.template`.
  - Keep **CRLF** for `.cmd`, `.bat`, and `.ps1`.
- **Executable Permissions:**
  - Ensure all shell scripts and POSIX binaries retain mode `100755` in Git (`git update-index --chmod=+x <file>`).
- **Mandatory Validation Before Push:**
  ```bash
  # 1. Bash syntax & lint
  bash -n emu-root/bin/emu-root \
    emu-root/installers/macos/install-macos.sh \
    emu-root/installers/ubuntu/install-ubuntu.sh \
    emu-root/installers/ubuntu/build-deb.sh \
    emu-root/packaging/deb/DEBIAN/postinst \
    redroid-docker/install-vps.sh \
    redroid-docker/scripts/setup-nginx-auth.sh \
    redroid-docker/scripts/manage.sh

  shellcheck -S error \
    emu-root/bin/emu-root \
    emu-root/installers/macos/install-macos.sh \
    emu-root/installers/ubuntu/install-ubuntu.sh \
    emu-root/installers/ubuntu/build-deb.sh \
    redroid-docker/install-vps.sh \
    redroid-docker/scripts/setup-nginx-auth.sh \
    redroid-docker/scripts/manage.sh

  # 2. Docker Compose validation
  (cd redroid-docker && cp .env.example .env && docker compose config -q && rm -f .env)

  # 3. Debian .deb package build test (Ubuntu/Debian)
  ./emu-root/installers/ubuntu/build-deb.sh 1.0.0
  ```
- **Windows PowerShell syntax check:**
  ```powershell
  $t=$null; $e=$null
  [System.Management.Automation.Language.Parser]::ParseFile("emu-root\installers\windows\install-windows.ps1",[ref]$t,[ref]$e) | Out-Null
  if ($e.Count -gt 0) { throw $e }
  ```
