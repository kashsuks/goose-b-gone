import argparse
import time

from car_control import CarController, RemoteCarController
from live_detect import LiveDetector


def pick_target(predictions, min_confidence):
    candidates = [p for p in predictions if p["confidence"] >= min_confidence]
    if not candidates:
        return None
    return max(candidates, key=lambda p: p["width"] * p["height"])


def compute_command(pred, frame_width, close_threshold, speed):
    box_ratio = pred["width"] / frame_width
    if box_ratio >= close_threshold:
        return "S", 0
    return "F", speed


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Drive straight at the detected goose. No steering, no "
        "search behavior, no backward movement (no rear-facing camera) — "
        "does nothing when no goose is in frame."
    )
    parser.add_argument("--port", default="/dev/ttyUSB0", help="Arduino serial port (ignored if --relay-host is set)")
    parser.add_argument("--baud", type=int, default=9600)
    parser.add_argument(
        "--relay-host",
        default=None,
        help="If set, send drive commands over HTTP to a motor_server.py "
        "running at this host (e.g. the Pi's IP) instead of a local serial "
        "port. Use this when detection runs on a different machine than the "
        "one wired to the Arduino.",
    )
    parser.add_argument("--relay-port", type=int, default=5005, help="Port for --relay-host")
    parser.add_argument("--camera", type=int, default=0, help="Camera index (opencv backend)")
    parser.add_argument(
        "--backend",
        choices=["auto", "opencv", "rpicam"],
        default="auto",
        help="Camera capture backend (see live_detect.py)",
    )
    parser.add_argument(
        "--interval", type=float, default=1.0, help="Seconds between cloud detection calls"
    )
    parser.add_argument("--max-speed", type=int, default=150, help="Forward drive speed (0-255)")
    parser.add_argument(
        "--close-threshold",
        type=float,
        default=0.45,
        help="Fraction of frame width the goose's box must reach before stopping",
    )
    parser.add_argument(
        "--min-confidence",
        type=float,
        default=0.8,
        help="Minimum detection confidence (0-1) for a box to be considered a goose",
    )
    args = parser.parse_args()

    detector = LiveDetector(camera_index=args.camera, interval=args.interval, backend=args.backend)
    if args.relay_host:
        car = RemoteCarController(host=args.relay_host, port=args.relay_port)
    else:
        car = CarController(port=args.port, baud=args.baud)

    detector.start()
    try:
        print("Chasing. Press Ctrl+C to stop.")
        while True:
            ok, frame = detector.read_frame()
            if not ok:
                print("Failed to read frame from camera, retrying in 1s...")
                time.sleep(1)
                continue

            frame_width = frame.shape[1]
            target = pick_target(detector.get_predictions(), args.min_confidence)

            if target is None:
                # No goose in frame: do nothing. The Arduino's own watchdog
                # (goose_chaser.ino) auto-stops the motors if no command
                # arrives for 800ms, so simply not sending anything is safe.
                print("No goose detected")
                continue

            direction, speed = compute_command(target, frame_width, args.close_threshold, args.max_speed)
            box_ratio = target["width"] / frame_width
            print(
                f"target={target['class']} conf={target['confidence']:.0%} "
                f"box_ratio={box_ratio:.2f} -> {direction} {speed}"
            )

            if direction == "F":
                car.forward(speed)
            else:
                car.stop()
    except KeyboardInterrupt:
        print("Stopping...")
    finally:
        car.close()
        detector.stop()


if __name__ == "__main__":
    main()
