import re
from typing import List

_DIGIT_WORDS = {
    "zero": "0",
    "one": "1",
    "two": "2",
    "three": "3",
    "four": "4",
    "five": "5",
    "six": "6",
    "seven": "7",
    "eight": "8",
    "nine": "9",
}


def normalize_text(text: str) -> str:
    if not text:
        return ""
    t = text.lower()
    t = t.replace(",", " ").replace(".", " ").replace("-", " ")
    t = re.sub(r"[^a-z0-9\s]", " ", t)
    t = " ".join(t.split())
    t = _replace_digit_words(t)
    return t.strip()


def _replace_digit_words(text: str) -> str:
    tokens: List[str] = []
    for token in text.split():
        tokens.append(_DIGIT_WORDS.get(token, token))
    return " ".join(tokens)


__all__ = ["normalize_text"]
