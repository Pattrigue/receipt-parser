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
                    "discount": {"type": "number", "minimum": 0},
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
- RABAT means discount. Never output an item named RABAT.
- If a RABAT line appears by itself, below an item, or next to an amount with a trailing minus sign, attach that amount as a positive discount to the nearest preceding real product line.
- Treat amounts ending in "-" as discounts or negative adjustments on the receipt, but output discount as a positive number.
- Every real product row with its own printed positive amount is a separate item, even if another product name appears on the next OCR line.
- Do not merge adjacent products that each have their own printed line total; keep both products and both prices.
- If a product line has a positive amount and the next OCR line starts a different product, the next product is not part of the previous item name.
- Ignore category headers, totals, payment lines, VAT/MOMS lines, and other non-product summary rows.
- If an item name wraps across multiple OCR lines, only combine lines that belong to the same product and do not have their own separate price.

Example:
CHAVROUX PYRAMID        25,95
CHEASY HYTTEOST
2 x 15,61        31,22
RABAT             3,22-
=> [{"name":"CHAVROUX PYRAMID","price":25.95,"quantity":1},{"name":"CHEASY HYTTEOST","price":31.22,"quantity":2,"discount":3.22}]
"""


def normalize_items(parsed: dict[str, Any]) -> dict[str, Any]:
    normalized: list[dict[str, Any]] = []

    for raw_item in parsed.get("items", []):
        item = dict(raw_item)
        name = str(item.get("name", "")).strip()

        if name.upper() == "RABAT":
            amount = item.get("discount") or item.get("price") or 0
            try:
                discount = abs(float(amount))
            except (TypeError, ValueError):
                discount = 0

            if normalized and discount > 0:
                previous = normalized[-1]
                previous["discount"] = float(previous.get("discount") or 0) + discount
            continue

        if "discount" in item:
            item["discount"] = abs(float(item["discount"]))

        normalized.append(item)

    return {"items": normalized}


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

    parsed = normalize_items(json.loads(out_text))
    final = json.dumps(parsed, ensure_ascii=False)

    output_path = args.out
    if output_path:
        Path(output_path).write_text(final + "\n", encoding="utf-8")
    
    sys.stdout.write(final + "\n")


if __name__ == "__main__":
    main()
