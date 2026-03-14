import json
import pathlib

import jsonschema
import pytest

from backend.parser import default_parser

ROOT = pathlib.Path(__file__).resolve().parents[2]
INTENT_SCHEMA = json.loads((ROOT / "schemas" / "intent.schema.json").read_text(encoding="utf-8"))
VALIDATOR = jsonschema.Draft202012Validator(INTENT_SCHEMA)


@pytest.mark.parametrize(
    "text, expected_intent, expected_caller, expected_addressee",
    [
        ("Magic, Colt one one, request picture", "request_picture", "colt 1 1", "magic"),
        ("Colt 1-1 declare", "declare", "colt 1 1", None),
        ("Colt 1-1 vector to tanker", "vector_tanker", "colt 1 1", None),
    ],
)
def test_parser_output_matches_contract(text, expected_intent, expected_caller, expected_addressee):
    parser = default_parser()
    parsed = parser.parse(
        {
            "text": text,
            "frequency": 251.0,
            "coalition": "blue",
            "confidence": 0.9,
        }
    )

    assert parsed["intent"] == expected_intent
    assert parsed["caller"] == expected_caller
    assert parsed["addressee"] == expected_addressee

    errors = sorted(VALIDATOR.iter_errors(parsed), key=lambda e: list(e.path))
    assert errors == [], [f"{'/'.join(str(p) for p in e.path)}: {e.message}" for e in errors]


def test_unknown_phrase_returns_no_intent():
    parser = default_parser()
    parsed = parser.parse(
        {
            "text": "Magic Colt 1-1 say again",
            "frequency": 251.0,
            "coalition": "blue",
            "confidence": 0.7,
        }
    )

    assert parsed["intent"] is None
