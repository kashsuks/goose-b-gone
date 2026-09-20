import time

import serial

DEFAULT_PORT = "/dev/ttyUSB0"
DEFAULT_BAUD = 9600


class CarController:
    """Sends drive commands to the Arduino over serial. Matches the command
    set parsed by arduino/goose_chaser/goose_chaser.ino: F/L/R with a
    0-255 speed, or S to stop. No backward command — there's no rear-facing
    camera to drive by."""

    def __init__(self, port: str = DEFAULT_PORT, baud: int = DEFAULT_BAUD):
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
