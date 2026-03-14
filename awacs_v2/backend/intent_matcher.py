from typing import Dict, List, Optional


def build_phrase_index(intents_cfg: Dict) -> List[Dict]:
    intents = intents_cfg.get("intents", [])
    ordered = sorted(intents, key=lambda i: i.get("priority", 99))
    phrase_index = []
    for intent in ordered:
        for phrase in intent.get("phrases", []):
            phrase_index.append({
                "phrase": phrase.lower(),
                "intent": intent.get("id"),
                "priority": intent.get("priority", 99),
            })
    return phrase_index


def match_intent(normalized_text: str, phrase_index: List[Dict]) -> Optional[str]:
    for entry in phrase_index:
        if entry["phrase"] in normalized_text:
            return entry["intent"]
    return None


__all__ = ["build_phrase_index", "match_intent"]
