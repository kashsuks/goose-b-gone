import argparse
import json
import os
import sys

from inference_sdk import InferenceHTTPClient, InferenceConfiguration

MODEL_ID = "canadian-geese-detector-5frcl/1"
DEFAULT_API_URL = "https://serverless.roboflow.com"


def get_client() -> InferenceHTTPClient:
    api_key = os.environ.get("ROBOFLOW_API_KEY")
    if not api_key:
        sys.exit("ROBOFLOW_API_KEY environment variable is not set")

    api_url = os.environ.get("ROBOFLOW_API_URL", DEFAULT_API_URL)
    client = InferenceHTTPClient(api_url=api_url, api_key=api_key)
    client.configure(InferenceConfiguration(api_key_transport="header"))
    return client


def detect(image: str) -> dict:
    client = get_client()
    return client.infer(image, model_id=MODEL_ID)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the Canadian geese detector on an image")
    parser.add_argument("image", help="Local file path or URL of the image to analyze")
    args = parser.parse_args()

    result = detect(args.image)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
