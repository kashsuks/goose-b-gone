import argparse
import time

from car_control import CarController
from live_detect import LiveDetector


def pick_target(predictions, min_confidence):
    candidates = [p for p in predictions if p["confidence"] >= min_confidence]
    if not candidates:
        return None
    return max(candidates, key=lambda p: p["width"] * p["height"])


def compute_command(pred, frame_width, turn_threshold, close_threshold, speed):
    box_ratio = pred["width"] / frame_width
    if box_ratio >= close_threshold:
        return "S", 0

    offset_ratio = (pred["x"] - frame_width / 2) / (frame_width / 2)
    if offset_ratio > turn_threshold:
        return "R", speed
    if offset_ratio < -turn_threshold:
        return "L", speed
    return "F", speed


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Autonomously chase the detected goose. No backward "
        "movement is supported (no rear-facing camera)."
    )
    parser.add_argument("--port", default="/dev/ttyUSB0", help="Arduino serial port")
    parser.add_argument("--baud", type=int, default=9600)
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
    parser.add_argument("--max-speed", type=int, default=150, help="Drive/turn speed (0-255)")
    parser.add_argument("--search-speed", type=int, default=120, help="Turn speed while searching (0-255)")
    parser.add_argument(
        "--turn-threshold",
        type=float,
        default=0.2,
        help="Horizontal offset (as a fraction of half frame width) beyond which "
        "the car turns instead of driving forward",
    )
    parser.add_argument(
        "--close-threshold",
        type=float,
        default=0.45,
        help="Fraction of frame width the goose's box must reach before stopping",
    )
    parser.add_argument(
        "--search-after",
        type=float,
        default=3.0,
        help="Seconds with no goose detected before the car starts scanning",
    )
    parser.add_argument(
        "--min-confidence",
        type=float,
        default=0.9,
        help="Minimum detection confidence (0-1) for a box to be considered a goose",
    )
    args = parser.parse_args()

    detector = LiveDetector(camera_index=args.camera, interval=args.interval, backend=args.backend)
    car = CarController(port=args.port, baud=args.baud)
    last_seen = time.time()

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
                if time.time() - last_seen >= args.search_after:
                    print("No goose in sight, searching...")
                    car.left(args.search_speed)
                else:
                    car.stop()
                continue

            last_seen = time.time()
            direction, speed = compute_command(
                target, frame_width, args.turn_threshold, args.close_threshold, args.max_speed
            )
            box_ratio = target["width"] / frame_width
            print(
                f"target={target['class']} conf={target['confidence']:.0%} "
                f"box_ratio={box_ratio:.2f} -> {direction} {speed}"
            )

            if direction == "F":
                car.forward(speed)
            elif direction == "L":
                car.left(speed)
            elif direction == "R":
                car.right(speed)
            else:
                car.stop()
    except KeyboardInterrupt:
        print("Stopping...")
    finally:
        car.close()
        detector.stop()


if __name__ == "__main__":
    main()
