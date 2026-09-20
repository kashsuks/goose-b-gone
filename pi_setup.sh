#!/bin/bash
# Sets up and troubleshoots the Pi side of the goose-chaser: dependencies,
# the Arduino serial connection, and the motor relay server (motor_server.py)
# that chase.py (running here or on another machine) sends drive commands to.
#
# Usage: ./pi_setup.sh [-- <extra args for motor_server.py>]
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "== goose-b-gone Pi setup/troubleshoot =="

# 1. Power check. This class of bug (Arduino silently dropping off /dev/ttyUSB*,
# renumbering, or the whole Pi acting flaky) has repeatedly turned out to be
# undervoltage, not software. Check it first so it's not chased as a code bug.
if command -v vcgencmd >/dev/null 2>&1; then
    THROTTLED=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)
    if [ "$THROTTLED" != "0x0" ]; then
        echo
        echo "!! WARNING: vcgencmd get_throttled reports $THROTTLED (not 0x0)."
        echo "!! This means the Pi has hit undervoltage/throttling, which causes"
        echo "!! USB devices (the Arduino) to drop and re-enumerate under a"
        echo "!! different /dev/ttyUSB* name, and generally flaky behavior."
        echo "!! Fix: use a proper 5V/2.5A+ power supply and a short, thick"
        echo "!! micro-USB cable -- not a phone power bank/charge cable."
        echo "!! Continuing anyway, but expect instability until this is fixed."
        echo
    else
        echo "Power OK (throttled=0x0)."
    fi
fi

# 2. System dependencies
if command -v apt-get >/dev/null 2>&1; then
    echo "Checking system dependencies (requires sudo)..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq python3-venv python3-pip libgl1 libglib2.0-0 >/dev/null
    sudo apt-get install -y -qq rpicam-apps >/dev/null 2>&1 || true
fi

# 3. Ensure the pi user can access serial devices without sudo
if ! groups "$USER" | grep -q '\bdialout\b'; then
    echo "Adding $USER to the 'dialout' group (needed for serial port access)..."
    sudo usermod -aG dialout "$USER"
    echo "!! You must log out and back in (or reboot) for this to take effect."
fi

# 4. Python virtual environment (mirrors run.sh's uv fallback for Python 3.13+ systems)
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
    export PATH="$HOME/.local/bin:$PATH"
    if ! command -v uv >/dev/null 2>&1; then
        echo "No system Python < 3.13 found; installing uv to fetch one..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi
    USE_UV=1
fi

if [ ! -d .venv ]; then
    echo "Creating virtual environment..."
    if [ -n "$USE_UV" ]; then
        uv venv --python 3.12 .venv
    else
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

# 5. Find the Arduino
echo "Looking for the Arduino..."
ARDUINO_PORT=""
for p in /dev/serial/by-id/*; do
    [ -e "$p" ] && ARDUINO_PORT="$p" && break
done
if [ -z "$ARDUINO_PORT" ]; then
    for p in /dev/ttyUSB* /dev/ttyACM*; do
        [ -e "$p" ] && ARDUINO_PORT="$p" && break
    done
fi

if [ -z "$ARDUINO_PORT" ]; then
    echo "!! No Arduino found on any /dev/ttyUSB*, /dev/ttyACM*, or /dev/serial/by-id/ device." >&2
    echo "!! Check the USB cable is plugged into both the Pi and the Arduino." >&2
    echo "!! Also re-check the power warning above if one was printed." >&2
    exit 1
fi
echo "Found Arduino at $ARDUINO_PORT"

# 6. Free port 5005 if a stale motor_server.py is already holding it
EXISTING_PID=$(pgrep -f "motor_server.py" || true)
if [ -n "$EXISTING_PID" ]; then
    echo "Stopping existing motor_server.py process(es): $EXISTING_PID"
    kill $EXISTING_PID 2>/dev/null
    sleep 1
    kill -9 $EXISTING_PID 2>/dev/null || true
fi

# 7. Start the motor relay server
echo "Starting motor_server.py on $ARDUINO_PORT..."
exec .venv/bin/python motor_server.py --arduino-port "$ARDUINO_PORT" "$@"
