import glob
import time

import requests
import serial

DEFAULT_BAUD = 9600
DEFAULT_RELAY_PORT = 5005


def find_arduino_port() -> str:
    """Finds the Arduino's serial device. Prefers /dev/serial/by-id/, which
    stays stable across reconnects, since /dev/ttyUSB* numbering can shift
    (e.g. ttyUSB0 -> ttyUSB1) on replug or a flaky USB/power connection."""
    by_id = sorted(glob.glob("/dev/serial/by-id/*"))
    if by_id:
        return by_id[0]

    candidates = sorted(glob.glob("/dev/ttyUSB*") + glob.glob("/dev/ttyACM*"))
    if candidates:
        return candidates[0]

    raise RuntimeError(
        "No Arduino serial device found (checked /dev/serial/by-id/, "
        "/dev/ttyUSB*, /dev/ttyACM*). Is it plugged in? Run "
        "`vcgencmd get_throttled` too — a non-zero result means the Pi's "
        "power supply is dropping the USB connection."
    )


class CarController:
    """Sends drive commands to the Arduino over serial. Matches the command
    set parsed by arduino/goose_chaser/goose_chaser.ino: F/L/R with a
    0-255 speed, or S to stop. No backward command — there's no rear-facing
    camera to drive by."""

    def __init__(self, port: str | None = None, baud: int = DEFAULT_BAUD):
        port = port or find_arduino_port()
        print(f"Connecting to Arduino on {port}...")
        self._serial = serial.Serial(port, baud, timeout=1)
        # The Arduino resets when the serial connection opens (DTR toggle);
        # give it time to finish booting before sending commands.
        time.sleep(2)

    def forward(self, speed: int) -> None:
        self._send("F", speed)

    def left(self, speed: int) -> None:
        self._send("L", speed)

    def right(self, speed: int) -> None:
        self._send("R", speed)

    def stop(self) -> None:
        self._serial.write(b"S\n")

    def _send(self, direction: str, speed: int) -> None:
        speed = max(0, min(255, int(speed)))
        self._serial.write(f"{direction} {speed}\n".encode())

    def close(self) -> None:
        self.stop()
        self._serial.close()


class RemoteCarController:
    """Same interface as CarController, but sends commands over HTTP to a
    motor_server.py running elsewhere (e.g. on the Pi) instead of talking to
    a local serial port. Use this when detection runs on a different machine
    than the one physically wired to the Arduino."""

    def __init__(self, host: str, port: int = DEFAULT_RELAY_PORT):
        self._base_url = f"http://{host}:{port}"

    def forward(self, speed: int) -> None:
        self._send("F", speed)

    def left(self, speed: int) -> None:
        self._send("L", speed)

    def right(self, speed: int) -> None:
        self._send("R", speed)

    def stop(self) -> None:
        self._send("S", 0)

    def _send(self, direction: str, speed: int) -> None:
        speed = max(0, min(255, int(speed)))
        try:
            requests.post(
                f"{self._base_url}/drive",
                json={"direction": direction, "speed": speed},
                timeout=1,
            )
        except requests.RequestException as exc:
            print(f"Relay error sending to {self._base_url}: {exc}")

    def close(self) -> None:
        self.stop()
