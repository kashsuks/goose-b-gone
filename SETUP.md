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

## Notes

- All inference runs in Roboflow's cloud — the Pi needs a working internet
  connection for every detection call.
- Network calls only; no model weights are downloaded or run on the Pi, so
  this works fine even on the Pi 3B's limited RAM/CPU.
- Keep `ROBOFLOW_API_KEY` out of git. `.env` is already in `.gitignore`.
