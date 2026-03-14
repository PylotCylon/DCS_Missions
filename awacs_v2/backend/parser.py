import datetime as dt
from typing import Any, Dict

from . import config_loader
from .callsign_resolver import build_resolver
from .intent_matcher import build_phrase_index, match_intent
from .normalizer import normalize_text

ISO_FORMAT = "%Y-%m-%dT%H:%M:%SZ"


class Parser:
    def __init__(self):
        self.intents_cfg = config_loader.load_intents()
        self.doctrine_cfg = config_loader.load_doctrine()
        self.callsigns_cfg = config_loader.load_callsigns()
        self.phrase_index = build_phrase_index(self.intents_cfg)
        self.callsign_resolver = build_resolver(self.callsigns_cfg, self.doctrine_cfg)

    def parse(self, transcript: Dict[str, Any]) -> Dict[str, Any]:
        raw_text = transcript.get("text", "")
        normalized = normalize_text(raw_text)
        intent = match_intent(normalized, self.phrase_index)

        addressee = self.callsign_resolver.find_awacs(normalized)
        caller = self.callsign_resolver.find_caller(normalized, skip=addressee)

        return {
            "timestamp": self._ts(transcript.get("timestamp")),
            "frequency": transcript.get("frequency"),
            "coalition": transcript.get("coalition"),
            "addressee": addressee,
            "caller": caller,
            "intent": intent,
            "raw_transcript": raw_text,
            "normalized_text": normalized,
            "confidence": transcript.get("confidence"),
        }

    def _ts(self, value: Any) -> str:
        if isinstance(value, dt.datetime):
            if value.tzinfo is None:
                value = value.replace(tzinfo=dt.timezone.utc)
            else:
                value = value.astimezone(dt.timezone.utc)
            return value.strftime(ISO_FORMAT)

        if isinstance(value, (int, float)):
            return dt.datetime.fromtimestamp(value, tz=dt.timezone.utc).strftime(ISO_FORMAT)

        if isinstance(value, str):
            return value

        return dt.datetime.now(dt.timezone.utc).strftime(ISO_FORMAT)


def default_parser() -> Parser:
    return Parser()


__all__ = ["Parser", "default_parser"]
