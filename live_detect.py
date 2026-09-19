import argparse
import shutil
import subprocess
import tempfile
import threading
import time

import cv2

from detect import MODEL_ID, get_client

BOX_COLOR = (0, 0, 255)  # red, BGR
TEXT_COLOR = (255, 255, 255)


class OpenCVCapture:
    """Captures frames via OpenCV's VideoCapture (works with USB/UVC webcams,
    including on macOS)."""

    def __init__(self, camera_index: int):
        self._cap = cv2.VideoCapture(camera_index)
        if not self._cap.isOpened():
            raise RuntimeError(f"Could not open camera index {camera_index}")

    def read(self):
        return self._cap.read()

    def release(self) -> None:
        self._cap.release()


class RpicamCapture:
    """Captures frames by shelling out to rpicam-still. Needed for Raspberry
    Pi Camera Module sensors managed by libcamera, which OpenCV's V4L2
    backend cannot open directly. Each call blocks for roughly a second due
    to libcamera pipeline startup, so this behaves like a periodically
    refreshed snapshot rather than a smooth video feed."""

    def __init__(self):
        if shutil.which("rpicam-still") is None:
            raise RuntimeError("rpicam-still not found on PATH")

    def read(self):
        with tempfile.NamedTemporaryFile(suffix=".jpg") as tmp:
            proc = subprocess.run(
                [
                    "rpicam-still",
                    "-n",
                    "--timeout",
                    "1",
                    "--width",
                    "1280",
                    "--height",
                    "720",
                    "-o",
                    tmp.name,
                ],
                capture_output=True,
            )
            if proc.returncode != 0:
                return False, None
            frame = cv2.imread(tmp.name)
            return frame is not None, frame

    def release(self) -> None:
        pass


def open_capture(camera_index: int, backend: str):
    if backend == "auto":
        backend = "rpicam" if shutil.which("rpicam-still") else "opencv"
    if backend == "rpicam":
        return RpicamCapture()
    return OpenCVCapture(camera_index)


class LiveDetector:
    """Continuously grabs frames from a camera and periodically runs cloud
    detection on the latest frame in a background thread, so the video feed
    stays as smooth as the capture backend allows even though inference
    happens over the network."""

    def __init__(self, camera_index: int, interval: float, backend: str):
        self.client = get_client()
        self.interval = interval
        self.capture = open_capture(camera_index, backend)

        self._frame_lock = threading.Lock()
        self._latest_frame = None
        self._pred_lock = threading.Lock()
        self._predictions = []
        self._running = True
        self._worker = threading.Thread(target=self._detect_loop, daemon=True)

    def start(self) -> None:
        self._worker.start()

    def stop(self) -> None:
        self._running = False
        self._worker.join(timeout=self.interval + 1)
        self.capture.release()

    def read_frame(self):
        ok, frame = self.capture.read()
        if ok:
            with self._frame_lock:
                self._latest_frame = frame
        return ok, frame

    def get_predictions(self):
        with self._pred_lock:
            return self._predictions

    def _detect_loop(self) -> None:
        while self._running:
            with self._frame_lock:
                frame = self._latest_frame

            if frame is not None:
                try:
                    result = self.client.infer(frame, model_id=MODEL_ID)
                    with self._pred_lock:
                        self._predictions = result.get("predictions", [])
                except Exception as exc:  # keep the loop alive on transient API errors
                    print(f"Detection error: {exc}")

            time.sleep(self.interval)


def annotate(frame, predictions):
    for pred in predictions:
        x, y, w, h = pred["x"], pred["y"], pred["width"], pred["height"]
        left, top = int(x - w / 2), int(y - h / 2)
        right, bottom = int(x + w / 2), int(y + h / 2)
        label = f'{pred["class"]} {pred["confidence"]:.0%}'

        cv2.rectangle(frame, (left, top), (right, bottom), BOX_COLOR, 2)
        (text_w, text_h), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 2)
        cv2.rectangle(frame, (left, top - text_h - 8), (left + text_w + 6, top), BOX_COLOR, -1)
        cv2.putText(frame, label, (left + 3, top - 6), cv2.FONT_HERSHEY_SIMPLEX, 0.6, TEXT_COLOR, 2)
    return frame


def run_window(detector: LiveDetector) -> None:
    print("Showing live feed in a window. Press 'q' to quit.")
    while True:
        ok, frame = detector.read_frame()
        if not ok:
            print("Failed to read frame from camera")
            break

        annotate(frame, detector.get_predictions())
        cv2.imshow("goose-b-gone: live detection", frame)
        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    cv2.destroyAllWindows()


def run_stream(detector: LiveDetector, host: str, port: int) -> None:
    from flask import Flask, Response

    app = Flask(__name__)

    def gen_frames():
        while True:
            ok, frame = detector.read_frame()
            if not ok:
                continue
            annotate(frame, detector.get_predictions())
            ok, buffer = cv2.imencode(".jpg", frame)
            if not ok:
                continue
            yield (
                b"--frame\r\nContent-Type: image/jpeg\r\n\r\n"
                + buffer.tobytes()
                + b"\r\n"
            )

    @app.route("/")
    def index():
        return (
            "<html><body style='margin:0;background:#111'>"
            "<img src='/video_feed' style='width:100%'></body></html>"
        )

    @app.route("/video_feed")
    def video_feed():
        return Response(
            gen_frames(), mimetype="multipart/x-mixed-replace; boundary=frame"
        )

    print(f"Streaming live detection at http://{host}:{port}/")
    app.run(host=host, port=port, threaded=True)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run the Canadian geese detector live on a camera feed"
    )
    parser.add_argument("--camera", type=int, default=0, help="Camera index (default: 0)")
    parser.add_argument(
        "--interval",
        type=float,
        default=1.0,
        help="Seconds between cloud detection calls (default: 1.0)",
    )
    parser.add_argument(
        "--backend",
        choices=["auto", "opencv", "rpicam"],
        default="auto",
        help="Camera capture backend. 'auto' uses rpicam-still if available "
        "(Raspberry Pi Camera Module), otherwise OpenCV (USB webcams, macOS).",
    )
    parser.add_argument(
        "--stream",
        action="store_true",
        help="Serve an MJPEG stream over HTTP instead of opening a local window "
        "(use this on a headless machine, e.g. a Raspberry Pi without a monitor)",
    )
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind for --stream")
    parser.add_argument("--port", type=int, default=8000, help="Port to bind for --stream")
    args = parser.parse_args()

    detector = LiveDetector(camera_index=args.camera, interval=args.interval, backend=args.backend)
    detector.start()
    try:
        if args.stream:
            run_stream(detector, host=args.host, port=args.port)
        else:
            run_window(detector)
    finally:
        detector.stop()


if __name__ == "__main__":
    main()
