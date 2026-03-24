import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "name": {"type": "string"},
                    "price": {"type": "number"},
                    "quantity": {"type": "number"},
                    "discount": {"type": "number"},
                },
                "required": ["name", "price", "quantity"],
            },
        }
    },
    "required": ["items"],
}


PROMPT = """You are given OCR text from a receipt.

Return ONLY valid JSON matching the provided JSON Schema.

Rules:
- Output only JSON (no markdown / no code fences).
- Do not invent items.
- quantity is a number (use 1 if missing).
- price is the FINAL LINE TOTAL for that entry (i.e. the total amount for that line as printed on the receipt; not unit price).
- discount is optional; if present it must be a positive number and is the TOTAL discount associated with that same line.
"""

def post_json(url: str, payload: dict[str, Any], timeout_s: float) -> dict[str, Any]:
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        raise SystemExit(f"Ollama HTTP error {e.code}: {body}") from e
    except urllib.error.URLError as e:
        raise SystemExit(f"Failed to reach Ollama at {url}: {e}") from e


def main() -> None:
    ap = argparse.ArgumentParser(description="LLM receipt parser (Ollama structured output)")
    ap.add_argument("ocr_txt", help="Path to ocr.txt")
    ap.add_argument("--ollama-url", default="http://localhost:11434/api/generate")
    ap.add_argument("--model", default="qwen2.5:14b-instruct")
    ap.add_argument("--timeout", type=float, default=300.0, help="HTTP timeout in seconds")
    ap.add_argument("--out", default="", help="Optional output JSON file path")
    args = ap.parse_args()

    ocr_path = Path(args.ocr_txt)
    if not ocr_path.exists():
        raise SystemExit(f"ocr.txt not found: {ocr_path}")

    ocr_text = ocr_path.read_text(encoding="utf-8", errors="replace").strip()
    if not ocr_text:
        raise SystemExit("ocr.txt is empty")

    payload: dict[str, Any] = {
        "model": args.model,
        "prompt": PROMPT + "\n\nOCR TEXT:\n" + ocr_text,
        "stream": False,
        "format": SCHEMA,
        "options": {"temperature": 0.0},
    }

    resp = post_json(args.ollama_url, payload, timeout_s=args.timeout)

    out_text = (resp.get("response") or "").strip()
    if not out_text:
        raise SystemExit(f"Empty response from Ollama: {resp}")

    parsed = json.loads(out_text)
    final = json.dumps(parsed, ensure_ascii=False)

    output_path = args.out
    if output_path:
        Path(output_path).write_text(final + "\n", encoding="utf-8")
    
    sys.stdout.write(final + "\n")


if __name__ == "__main__":
    main()
