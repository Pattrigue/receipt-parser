import argparse
import contextlib
import io
import os
import warnings
from pathlib import Path

import torch
from transformers import AutoModel, AutoTokenizer
from transformers.utils import logging as hf_logging


DEFAULT_PROMPT = "<image>\nFree OCR. "


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="DeepSeek-OCR-2: run OCR and output raw text.")
    p.add_argument("image", help="Path to image file")
    p.add_argument("out", nargs="?", default="output", help="Output directory (default: ./output)")
    p.add_argument("--prompt", default=DEFAULT_PROMPT)
    p.add_argument("--dtype", choices=["bf16", "fp16", "fp32"], default="bf16")
    p.add_argument("--attn", choices=["eager", "sdpa", "flash_attention_2"], default="eager")
    p.add_argument("--base-size", type=int, default=1024)
    p.add_argument("--image-size", type=int, default=768)
    p.add_argument("--no-crop", action="store_true")
    p.add_argument("--no-save", action="store_true")
    p.add_argument("--quiet", action="store_true", help="Suppress HF/transformers warnings/logging")
    return p.parse_args()


def main() -> None:
    args = parse_args()

    if args.quiet:
        os.environ["TRANSFORMERS_VERBOSITY"] = "error"
        os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
        warnings.filterwarnings("ignore", category=FutureWarning)
        warnings.filterwarnings("ignore", category=UserWarning)
        hf_logging.set_verbosity_error()

    image_file = Path(args.image).expanduser().resolve()
    out_dir = Path(args.out).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    if not image_file.exists():
        raise SystemExit(f"Image not found: {image_file}")

    if not torch.cuda.is_available():
        raise SystemExit("CUDA not available. Ensure Docker is run with --gpus all.")

    dtype = {"bf16": torch.bfloat16, "fp16": torch.float16, "fp32": torch.float32}[args.dtype]

    model_name = "deepseek-ai/DeepSeek-OCR-2"
    tokenizer = AutoTokenizer.from_pretrained(model_name, trust_remote_code=True)
    model = AutoModel.from_pretrained(
        model_name,
        trust_remote_code=True,
        use_safetensors=True,
        _attn_implementation=args.attn,
        torch_dtype=dtype,
        device_map="auto",
    ).eval()

    buf_out = io.StringIO()
    buf_err = io.StringIO()

    # DeepSeek's infer() prints output and often returns None
    with contextlib.redirect_stdout(buf_out), contextlib.redirect_stderr(buf_err):
        _ = model.infer(
            tokenizer,
            prompt=args.prompt,
            image_file=str(image_file),
            output_path=str(out_dir),
            base_size=args.base_size,
            image_size=args.image_size,
            crop_mode=not args.no_crop,
            save_results=not args.no_save,
        )

    ocr_text = buf_out.getvalue().strip()

    # Save raw OCR text for downstream parsing
    (out_dir / "ocr.txt").write_text(ocr_text + "\n", encoding="utf-8")

    # Optionally save captured stderr for debugging
    if not args.quiet:
        err = buf_err.getvalue().strip()
        if err:
            (out_dir / "ocr_stderr.txt").write_text(err + "\n", encoding="utf-8")

    # Print ONLY the OCR text to stdout
    print(ocr_text)


if __name__ == "__main__":
    main()