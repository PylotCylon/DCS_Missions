import json
import pathlib
import sys
from typing import Any, Dict, List

from .parser import default_parser

ROOT = pathlib.Path(__file__).resolve().parent.parent
INTENT_SCHEMA_PATH = ROOT / "schemas" / "intent.schema.json"


def _load_intent_schema() -> Dict[str, Any]:
    return json.loads(INTENT_SCHEMA_PATH.read_text(encoding="utf-8"))


def _ensure_jsonschema():
    try:
        import jsonschema  # type: ignore
    except ModuleNotFoundError:
        print("jsonschema not installed. Install with: pip install jsonschema", file=sys.stderr)
        return None
    return jsonschema


def run_parser_samples() -> List[Dict[str, Any]]:
    parser = default_parser()
    samples = [
        {
            "text": "Magic, Colt one one, request picture",
            "frequency": 251.0,
            "coalition": "blue",
            "confidence": 0.91,
        },
        {
            "text": "Colt 1-1 declare",
            "frequency": 251.0,
            "coalition": "blue",
            "confidence": 0.88,
        },
        {
            "text": "Colt 1-1 vector to tanker",
            "frequency": 251.0,
            "coalition": "blue",
            "confidence": 0.90,
        },
    ]
    return [parser.parse(s) for s in samples]


def validate_against_schema(docs: List[Dict[str, Any]]) -> bool:
    js = _ensure_jsonschema()
    if js is None:
        print("Skipping JSON Schema validation", file=sys.stderr)
        return False

    schema = _load_intent_schema()
    validator = js.Draft202012Validator(schema)
    ok = True
    for doc in docs:
        errors = sorted(validator.iter_errors(doc), key=lambda e: list(e.path))
        if errors:
            ok = False
            label = doc.get("raw_transcript") or doc.get("text") or "<no text>"
            print(f"Schema errors for: {label}")
            for err in errors:
                path = "/".join([str(p) for p in err.path])
                print(f" - {path}: {err.message}")
        else:
            print(f"OK intent={doc.get('intent')} caller={doc.get('caller')} addressee={doc.get('addressee')}")
    return ok


def main() -> None:
    docs = run_parser_samples()
    all_ok = validate_against_schema(docs)
    if all_ok:
        print("Validation passed.")
    else:
        print("Validation failed.")
        sys.exit(1)


if __name__ == "__main__":
    main()
