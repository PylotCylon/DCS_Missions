from typing import Dict, Optional

from .normalizer import normalize_text

class CallsignResolver:
    def __init__(self, callsigns_cfg: Dict, awacs_callsigns: Dict):
        self.callsigns = [c.get("callsign", "").lower() for c in callsigns_cfg.get("players", [])]
        self.awacs_callsigns = [c.lower() for c in awacs_callsigns]

    def find_awacs(self, normalized_text: str) -> Optional[str]:
        for cs in self.awacs_callsigns:
            if cs and cs in normalized_text:
                return cs
        return None

    def find_caller(self, normalized_text: str, skip: Optional[str] = None) -> Optional[str]:
        for cs in self.callsigns:
            if not cs:
                continue
            if skip and cs == skip:
                continue
            if cs in normalized_text:
                return cs
        return None


def build_resolver(callsigns_cfg: Dict, doctrine_cfg: Dict) -> CallsignResolver:
    awacs = doctrine_cfg.get("awacs_callsigns", [])
    return CallsignResolver(callsigns_cfg, awacs)


__all__ = ["CallsignResolver", "build_resolver"]
