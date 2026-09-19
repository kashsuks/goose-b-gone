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
        # rpicam-apps (Pi Camera Module support) is Raspberry Pi OS-specific
        # and may not exist on other Debian systems, so don't hard-fail.
        sudo apt-get install -y rpicam-apps || true
    fi
else
    echo "No known package manager found, skipping system package install (assuming dependencies are already present)."
fi

# 2. Python virtual environment
# inference-sdk currently requires Python < 3.13, so prefer a compatible
# interpreter over whatever "python3" happens to resolve to (e.g. Homebrew's
# python3 on macOS, or Raspberry Pi OS trixie's python3, are 3.13+).
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

USE_UV=""
if [ -z "$PYTHON_BIN" ]; then
    echo "No system Python < 3.13 found (required by inference-sdk)."
    export PATH="$HOME/.local/bin:$PATH"
    if ! command -v uv >/dev/null 2>&1; then
        echo "Installing uv to fetch a compatible Python build (avoids a slow from-source compile on the Pi)..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi
    if ! command -v uv >/dev/null 2>&1; then
        echo "Failed to install uv. Install Python 3.10-3.12 manually and re-run." >&2
        exit 1
    fi
    USE_UV=1
fi

if [ ! -d .venv ]; then
    if [ -n "$USE_UV" ]; then
        echo "Creating virtual environment with uv (Python 3.12)..."
        uv venv --python 3.12 .venv
    else
        echo "Creating virtual environment with $PYTHON_BIN..."
        "$PYTHON_BIN" -m venv .venv
    fi
fi

echo "Installing Python dependencies..."
if [ -n "$USE_UV" ]; then
    uv pip install --python .venv/bin/python -q -r requirements.txt
else
    .venv/bin/pip install --upgrade pip -q
    .venv/bin/pip install -q -r requirements.txt
fi

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
if command -v rpicam-still >/dev/null 2>&1; then
    echo "Capturing photo with Pi Camera (rpicam-still)..."
    rpicam-still -o "$CAPTURE_FILE" -n
elif command -v libcamera-still >/dev/null 2>&1; then
    echo "Capturing photo with Pi Camera (libcamera-still)..."
    libcamera-still -o "$CAPTURE_FILE" -n
elif command -v fswebcam >/dev/null 2>&1; then
    echo "Capturing photo with USB webcam (fswebcam)..."
    fswebcam -r 1280x720 --no-banner "$CAPTURE_FILE"
elif command -v imagesnap >/dev/null 2>&1; then
    echo "Capturing photo with Mac webcam (imagesnap)..."
    imagesnap "$CAPTURE_FILE"
else
    echo "No camera tool found (rpicam-still, libcamera-still, fswebcam, or imagesnap)." >&2
    if [ "$OS" = "Darwin" ]; then
        echo "Install one, e.g.: brew install imagesnap" >&2
    else
        echo "For a Pi Camera Module: sudo apt-get install -y rpicam-apps" >&2
        echo "For a USB webcam: sudo apt-get install -y fswebcam" >&2
    fi
    exit 1
fi

# 5. Run detection
echo "Running detection on $CAPTURE_FILE..."
.venv/bin/python detect.py "$CAPTURE_FILE"
