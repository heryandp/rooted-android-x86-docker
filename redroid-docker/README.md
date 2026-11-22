# `redroid-docker` — VPS Linux + Redroid (Android 12 Rooted) + `ws-scrcpy` + Nginx

Run a full **Android 12 (64-bit) + Magisk + MindTheGapps (Play Store) + ARM64 (`libndk`)** instance inside Docker on a **standard Linux VPS without nested virtualization (`/dev/kvm` not required)**, with a browser-based screen controller (`ws-scrcpy`) protected by Nginx HTTP Basic Auth.

---

## Requirements

- **OS:** Ubuntu 22.04 / 24.04 LTS or Debian 12 (`x86_64`)
- **Kernel:** Linux kernel with `binder_linux` / `binderfs` (pre-installed on Ubuntu 24.04 kernel `6.8`!)
- **Resources:** Minimum 2 vCPU, 2.5–3 GB free RAM, ~10 GB free disk

---

## Quick Install on VPS

```bash
git clone https://github.com/heryandp/rooted-android-x86-docker.git
cd rooted-android-x86-docker/redroid-docker
chmod +x install-vps.sh scripts/*.sh

# Option 1: Full (Android 12 + MindTheGapps Play Store + libndk ARM64 + Magisk)
./install-vps.sh --full

# Option 2: Full + automatically expose Web UI on port 8000 with Nginx Basic Auth
./install-vps.sh --full --expose-nginx --port 8000

# Option 3: Lightweight (no Play Store, keeps Magisk + libndk ARM64)
./install-vps.sh --lite --mem 1536m
```

---

## Accessing Your Cloud Android

### Method A: SSH Tunnel (Most Secure, Zero Public Ports)
```bash
ssh -L 8000:127.0.0.1:18000 -L 5555:127.0.0.1:5555 ubuntu@<YOUR_VPS_IP>
```
- Open **Web UI** in your browser: `http://localhost:8000`
- Connect **ADB** from your PC: `adb connect 127.0.0.1:5555`

### Method B: Online Web UI via Nginx + HTTP Basic Auth
```bash
/opt/redroid/scripts/setup-nginx-auth.sh --port 8000
```
- Open `http://<YOUR_VPS_IP>:8000` and enter the generated credentials.
- Click `redroid:5555` → choose **Broadway.js** or **Tiny H264** (recommended over HTTP; use HTTPS subdomain for WebCodecs/H264 Converter).
- **ADB port `5555` remains locked to `127.0.0.1`** and is never exposed to the public internet.

---

## Day-to-Day Management

```bash
/opt/redroid/scripts/manage.sh status     # Check containers & ADB link
/opt/redroid/scripts/manage.sh stats      # Check CPU & RAM usage
/opt/redroid/scripts/manage.sh stop       # Stop when idle (saves ~1.8 GB RAM)
/opt/redroid/scripts/manage.sh start      # Start back up
/opt/redroid/scripts/manage.sh logs       # Follow container logs
/opt/redroid/scripts/manage.sh gsf-id     # Print GSF Android ID for Play Protect
```

Disable public port `8000` anytime:
```bash
/opt/redroid/scripts/setup-nginx-auth.sh --disable
```
