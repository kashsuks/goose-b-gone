# Raspberry Pi 3B Setup

This project calls Roboflow's serverless cloud API (`inference-sdk`) rather than
running the model locally. A Pi 3B has no NPU/GPU and only 1GB RAM, so it can't
run object detection inference itself — but it's plenty capable of capturing a
photo and making an HTTP request, which is all this setup needs.

## 1. Flash the OS

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) to flash
**Raspberry Pi OS Lite** (32-bit or 64-bit) to an SD card. The Lite (headless)
image avoids the desktop environment's RAM/CPU overhead, which matters on a 3B.

In the Imager's advanced options, you can pre-configure Wi-Fi, hostname, and
SSH so it boots ready to connect to.

## 2. Boot and connect

```bash
ssh pi@<pi-hostname-or-ip>
```

## Quickstart

Once you've cloned the repo onto the Pi (step 4 below), you can skip steps
5-8 and just run:

```bash
./run.sh
```

This installs system + Python dependencies, prompts for your Roboflow API
key (saved to `.env`), captures a photo from a Pi Camera or USB webcam, and
runs detection on it. Re-run it any time to capture and detect again.

For continuous live detection instead of a single photo, see
[Live detection](#live-detection) below.

## 3. Install system dependencies

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y python3-venv python3-pip git
```

## 4. Get the project onto the Pi

```bash
git clone <this-repo-url> goose-b-gone
cd goose-b-gone
```

(Or `scp` the folder over if you're not using git on the Pi.)

## 5. Create a virtual environment and install dependencies

```bash
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r requirements.txt
```

`opencv-python` (needed for live detection) is a larger package — on a Pi 3B
this install can take several minutes even with prebuilt [piwheels](https://www.piwheels.org/)
wheels, which Raspberry Pi OS's pip is preconfigured to use.

## 6. Set your Roboflow API key

Never hardcode the key or commit it. Create a local `.env` file (already
gitignored):

```bash
cp .env.example .env
# edit .env and set ROBOFLOW_API_KEY=your_key_here
```

Load it before running the script:

```bash
set -a; source .env; set +a
```

Or export it once for the pi user by adding the line to `~/.bashrc`.

## 7. Set up a camera

- **Pi Camera Module**: enable it via `sudo raspi-config` → Interface Options
  → Camera, then reboot. Capture a still with:
  ```bash
  libcamera-still -o capture.jpg
  ```
- **USB webcam**: capture a still with `fswebcam` (`sudo apt install fswebcam`):
  ```bash
  fswebcam -r 1280x720 --no-banner capture.jpg
  ```

## 8. Run detection

```bash
.venv/bin/python detect.py capture.jpg
```

This sends `capture.jpg` to Roboflow's serverless API and prints the JSON
predictions (bounding boxes, class, confidence).

## 9. (Optional) Automate capture + detect

Combine steps 7 and 8 in a small shell script or cron job / systemd timer to
run periodically, e.g. every 30 seconds:

```bash
#!/bin/bash
cd /home/pi/goose-b-gone
set -a; source .env; set +a
libcamera-still -o capture.jpg -n
.venv/bin/python detect.py capture.jpg
```

Ask if you'd like this turned into an actual scheduled/looping script with
alerting (e.g. trigger a deterrent, send a notification) when a goose is
detected.

## Live detection

Instead of capturing one photo at a time, `live_detect.py` keeps the camera
feed running and periodically sends the latest frame to Roboflow (every 1
second by default — this interval is deliberately throttled so a continuous
video feed doesn't hammer the cloud API), drawing the most recent detection
boxes on every displayed frame.

```bash
./run.sh live            # opens a local window (needs a monitor + desktop)
./run.sh live --stream   # serves the feed over HTTP instead (headless-friendly)
```

Since a Pi 3B running Raspberry Pi OS **Lite** has no desktop/display server,
use `--stream` on a headless Pi: it starts a small web server and prints a
URL like `http://<pi-ip>:8000/` — open that in a browser on any device on
the same network to watch the live annotated feed.

Useful flags (pass after `live`, e.g. `./run.sh live --stream --interval 2`):
- `--interval SECONDS` — how often to call the cloud API (default `1.0`).
  Lower = more responsive detection but more API calls; raise this if you hit
  rate limits or want to reduce data usage.
- `--camera INDEX` — camera device index if you have more than one (default `0`).
- `--port PORT` — port for `--stream` mode (default `8000`).

You can also run it directly without `run.sh`:

```bash
.venv/bin/python live_detect.py --stream
```

**Camera compatibility note:** `live_detect.py` captures frames via OpenCV,
which works out of the box with USB webcams (`/dev/video0`). The Pi Camera
Module is not guaranteed to show up as a V4L2 device under the modern
`libcamera` stack on Raspberry Pi OS Bookworm — if `--camera 0` fails to
open, either enable the legacy camera stack in `raspi-config`, or use a USB
webcam instead.

## Notes

- All inference runs in Roboflow's cloud — the Pi needs a working internet
  connection for every detection call.
- Network calls only; no model weights are downloaded or run on the Pi, so
  this works fine even on the Pi 3B's limited RAM/CPU.
- Keep `ROBOFLOW_API_KEY` out of git. `.env` is already in `.gitignore`.
