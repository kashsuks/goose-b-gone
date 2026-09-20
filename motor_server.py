import argparse

from flask import Flask, request

from car_control import CarController

app = Flask(__name__)
car: CarController


@app.route("/drive", methods=["POST"])
def drive():
    data = request.get_json(force=True)
    direction = data.get("direction", "S")
    speed = int(data.get("speed", 0))

    if direction == "F":
        car.forward(speed)
    elif direction == "L":
        car.left(speed)
    elif direction == "R":
        car.right(speed)
    else:
        car.stop()

    return {"ok": True}


def main() -> None:
    global car
    parser = argparse.ArgumentParser(
        description="Receives drive commands over HTTP (from chase.py running "
        "on another machine) and forwards them to the Arduino over serial."
    )
    parser.add_argument(
        "--arduino-port",
        default=None,
        help="Arduino serial port (default: auto-detect via /dev/serial/by-id/)",
    )
    parser.add_argument("--baud", type=int, default=9600)
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind the HTTP server on")
    parser.add_argument("--port", type=int, default=5005, help="Port to bind the HTTP server on")
    args = parser.parse_args()

    car = CarController(port=args.arduino_port, baud=args.baud)
    try:
        print(f"Motor relay listening on http://{args.host}:{args.port}")
        app.run(host=args.host, port=args.port)
    finally:
        car.close()


if __name__ == "__main__":
    main()
