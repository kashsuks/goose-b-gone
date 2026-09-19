#!/bin/bash
# Sets up and runs the Canadian geese detector. Primarily intended for a
# Raspberry Pi (or any Debian-based Linux box with a camera), but also
# supports macOS for local testing. Installs dependencies, prompts for your
# Roboflow API key, then either detects on a single captured photo or runs
# live detection on the camera feed.
#
# Usage:
#   ./run.sh                 detect on a single captured photo (default)
#   ./run.sh live             live detection in a local window
#   ./run.sh live --stream    live detection served as an MJPEG stream over
#                              HTTP (use this on a headless machine, e.g. a
#                              Raspberry Pi with no monitor attached)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

MODE="${1:-static}"
if [ "$MODE" = "live" ]; then
    shift
fi

OS="$(uname -s)"
echo "== goose-b-gone setup ($OS, mode: $MODE) =="

# 1. System dependencies
if [ "$OS" = "Darwin" ]; then
    if [ "$MODE" = "static" ]; then
        if ! command -v brew >/dev/null 2>&1; then
            echo "Homebrew not found. Install it from https://brew.sh, or install imagesnap manually for camera capture." >&2
        elif ! command -v imagesnap >/dev/null 2>&1; then
            echo "Installing imagesnap (webcam capture tool) via Homebrew..."
            brew install imagesnap
        fi
    fi
elif command -v apt-get >/dev/null 2>&1; then
    echo "Installing system dependencies (requires sudo)..."
    sudo apt-get update
    # libgl1/libglib2.0-0 are needed for opencv-python (used by live mode) to
    # import correctly, even on a headless Pi.
    sudo apt-get install -y python3-venv python3-pip libgl1 libglib2.0-0
    if [ "$MODE" = "static" ]; then
        sudo apt-get install -y fswebcam
    fi
else
    echo "No known package manager found, skipping system package install (assuming dependencies are already present)."
fi

# 2. Python virtual environment
# inference-sdk currently requires Python < 3.13, so prefer a compatible
# interpreter over whatever "python3" happens to resolve to (e.g. Homebrew's
# python3 on macOS is often newer than that).
PYTHON_BIN=""
for candidate in python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
        version="$("$candidate" -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')"
        major="${version%%.*}"
        minor="${version##*.}"
        if [ "$major" -eq 3 ] && [ "$minor" -lt 13 ]; then
            PYTHON_BIN="$candidate"
            break
        fi
    fi
done

if [ -z "$PYTHON_BIN" ]; then
    echo "Could not find a Python interpreter < 3.13 (required by inference-sdk)." >&2
    echo "Install Python 3.10-3.12 (e.g. 'brew install python@3.12' on macOS) and re-run." >&2
    exit 1
fi

if [ ! -d .venv ]; then
    echo "Creating virtual environment with $PYTHON_BIN..."
    "$PYTHON_BIN" -m venv .venv
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

if [ "$MODE" = "live" ]; then
    # live_detect.py opens the camera itself (via OpenCV), so no separate
    # capture tool is needed here. Extra args (e.g. --stream) are forwarded.
    echo "Starting live detection..."
    exec .venv/bin/python live_detect.py "$@"
fi

# 4. Capture a photo
CAPTURE_FILE="capture.jpg"
if command -v libcamera-still >/dev/null 2>&1; then
    echo "Capturing photo with Pi Camera (libcamera-still)..."
    libcamera-still -o "$CAPTURE_FILE" -n
elif command -v fswebcam >/dev/null 2>&1; then
    echo "Capturing photo with USB webcam (fswebcam)..."
    fswebcam -r 1280x720 --no-banner "$CAPTURE_FILE"
elif command -v imagesnap >/dev/null 2>&1; then
    echo "Capturing photo with Mac webcam (imagesnap)..."
    imagesnap "$CAPTURE_FILE"
else
    echo "No camera tool found (libcamera-still, fswebcam, or imagesnap)." >&2
    if [ "$OS" = "Darwin" ]; then
        echo "Install one, e.g.: brew install imagesnap" >&2
    else
        echo "Install one, e.g.: sudo apt-get install -y fswebcam" >&2
    fi
    exit 1
fi

# 5. Run detection
echo "Running detection on $CAPTURE_FILE..."
.venv/bin/python detect.py "$CAPTURE_FILE"
