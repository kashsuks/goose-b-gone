#!/bin/bash
# Sets up and troubleshoots the Mac side of the goose-chaser: the local
# Roboflow inference server (Docker), the Python venv, and launches chase.py
# using the Mac's own camera, relaying drive commands to the Pi.
#
# Usage: ./mac_setup.sh <pi-ip> [-- <extra chase.py args>]
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

PI_IP="${1:-}"
if [ -z "$PI_IP" ]; then
    read -r -p "Pi IP address (from 'hostname -I' on the Pi): " PI_IP
fi
if [ -z "$PI_IP" ]; then
    echo "No Pi IP given, aborting." >&2
    exit 1
fi
shift || true

INFERENCE_IMAGE="roboflow/roboflow-inference-server-cpu:latest"
INFERENCE_CONTAINER="goose-inference"
INFERENCE_PORT=9001

echo "== goose-b-gone Mac setup/troubleshoot =="

# 1. Docker daemon
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed. Install Docker Desktop from https://docker.com/products/docker-desktop then re-run." >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "Starting Docker Desktop..."
    open -a Docker
    echo -n "Waiting for Docker to start"
    for i in $(seq 1 30); do
        docker info >/dev/null 2>&1 && break
        echo -n "."
        sleep 2
    done
    echo
    if ! docker info >/dev/null 2>&1; then
        echo "Docker still isn't up after 60s. Open Docker Desktop manually and re-run." >&2
        exit 1
    fi
fi
echo "Docker is running."

# 2. Local inference server container
EXISTING_ID=$(docker ps -a --filter "name=^${INFERENCE_CONTAINER}$" --format '{{.ID}}')
RUNNING_ID=$(docker ps --filter "name=^${INFERENCE_CONTAINER}$" --format '{{.ID}}')

if [ -n "$RUNNING_ID" ]; then
    echo "Inference server container already running."
elif [ -n "$EXISTING_ID" ]; then
    echo "Starting existing inference server container..."
    docker start "$EXISTING_ID" >/dev/null
else
    echo "No inference server container found, pulling image (large, ~10GB, first time only)..."
    docker pull "$INFERENCE_IMAGE"
    echo "Starting a new inference server container..."
    docker run -d --name "$INFERENCE_CONTAINER" -p "${INFERENCE_PORT}:${INFERENCE_PORT}" "$INFERENCE_IMAGE" >/dev/null
fi

echo -n "Waiting for inference server to respond on :${INFERENCE_PORT}"
for i in $(seq 1 20); do
    code=$(curl -s -m 2 -o /dev/null -w "%{http_code}" "http://localhost:${INFERENCE_PORT}/" 2>/dev/null)
    if [ "$code" = "200" ]; then
        echo " OK"
        break
    fi
    echo -n "."
    sleep 3
done
if [ "$code" != "200" ]; then
    echo
    echo "Inference server didn't come up. Check its logs:" >&2
    echo "  docker logs ${INFERENCE_CONTAINER}" >&2
    exit 1
fi

# 3. Python virtual environment
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
if [ -z "$PYTHON_BIN" ] && [ -x /Library/Frameworks/Python.framework/Versions/3.12/bin/python3.12 ]; then
    PYTHON_BIN=/Library/Frameworks/Python.framework/Versions/3.12/bin/python3.12
fi
if [ -z "$PYTHON_BIN" ]; then
    echo "No Python < 3.13 found (needed by inference-sdk). Install Python 3.12, e.g.:" >&2
    echo "  brew install python@3.12" >&2
    exit 1
fi

if [ ! -d .venv ]; then
    echo "Creating virtual environment with $PYTHON_BIN..."
    "$PYTHON_BIN" -m venv .venv
fi
echo "Installing Python dependencies..."
.venv/bin/pip install --upgrade pip -q
.venv/bin/pip install -q -r requirements.txt

# 4. Roboflow API key
if [ -f .env ] && grep -q '^ROBOFLOW_API_KEY=.\+' .env; then
    :
else
    read -r -s -p "Enter your Roboflow API key: " ROBOFLOW_API_KEY
    echo
    if [ -z "$ROBOFLOW_API_KEY" ]; then
        echo "No API key entered, aborting." >&2
        exit 1
    fi
    grep -v '^ROBOFLOW_API_KEY=' .env 2>/dev/null > .env.tmp || true
    echo "ROBOFLOW_API_KEY=$ROBOFLOW_API_KEY" >> .env.tmp
    mv .env.tmp .env
fi
# Local server, not the cloud -- overwrite/set every run in case it changed.
grep -v '^ROBOFLOW_API_URL=' .env 2>/dev/null > .env.tmp || true
echo "ROBOFLOW_API_URL=http://localhost:${INFERENCE_PORT}" >> .env.tmp
mv .env.tmp .env

set -a
source .env
set +a

# 5. Reachability check to the Pi's motor relay before committing to a full run
echo -n "Checking connectivity to Pi at ${PI_IP}:5005..."
if curl -s -m 3 -o /dev/null "http://${PI_IP}:5005/" 2>/dev/null; then
    echo " OK"
else
    code=$?
    echo " unreachable (curl exit $code)."
    echo "!! Make sure pi_setup.sh is running on the Pi first." >&2
    echo "!! Continuing anyway -- chase.py will keep retrying and print Relay errors if this doesn't resolve." >&2
fi

# 6. Run
echo "Starting chase.py (Mac camera + local inference, relaying to Pi at ${PI_IP})..."
exec .venv/bin/python chase.py --relay-host "$PI_IP" --backend opencv "$@"
