#!/bin/bash
# Sets up and runs the Canadian geese detector on a Raspberry Pi (or any
# Debian-based Linux box with a camera). Installs dependencies, prompts for
# your Roboflow API key, captures a photo, and runs detection on it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "== goose-b-gone setup =="

# 1. System dependencies
if command -v apt-get >/dev/null 2>&1; then
    echo "Installing system dependencies (requires sudo)..."
    sudo apt-get update
    sudo apt-get install -y python3-venv python3-pip
else
    echo "apt-get not found, skipping system package install (assuming dependencies are already present)."
fi

# 2. Python virtual environment
if [ ! -d .venv ]; then
    echo "Creating virtual environment..."
    python3 -m venv .venv
fi

echo "Installing Python dependencies..."
.venv/bin/pip install --upgrade pip -q
.venv/bin/pip install -q -r requirements.txt

# 3. Roboflow API key
if [ -f .env ] && grep -q '^ROBOFLOW_API_KEY=.\+' .env; then
    read -r -p "A Roboflow API key is already set in .env. Replace it? [y/N] " REPLACE_KEY
    if [[ ! "$REPLACE_KEY" =~ ^[Yy]$ ]]; then
        SKIP_KEY_PROMPT=1
    fi
fi

if [ -z "${SKIP_KEY_PROMPT:-}" ]; then
    read -r -s -p "Enter your Roboflow API key: " ROBOFLOW_API_KEY
    echo
    if [ -z "$ROBOFLOW_API_KEY" ]; then
        echo "No API key entered, aborting." >&2
        exit 1
    fi
    grep -v '^ROBOFLOW_API_KEY=' .env 2>/dev/null > .env.tmp || true
    echo "ROBOFLOW_API_KEY=$ROBOFLOW_API_KEY" >> .env.tmp
    mv .env.tmp .env
    echo "Saved API key to .env"
fi

set -a
source .env
set +a

# 4. Capture a photo
CAPTURE_FILE="capture.jpg"
if command -v libcamera-still >/dev/null 2>&1; then
    echo "Capturing photo with Pi Camera (libcamera-still)..."
    libcamera-still -o "$CAPTURE_FILE" -n
elif command -v fswebcam >/dev/null 2>&1; then
    echo "Capturing photo with USB webcam (fswebcam)..."
    fswebcam -r 1280x720 --no-banner "$CAPTURE_FILE"
else
    echo "No camera tool found (libcamera-still or fswebcam)." >&2
    echo "Install one, e.g.: sudo apt-get install -y fswebcam" >&2
    exit 1
fi

# 5. Run detection
echo "Running detection on $CAPTURE_FILE..."
.venv/bin/python detect.py "$CAPTURE_FILE"
