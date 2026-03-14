import json
import pathlib
from typing import Any, Dict

try:
    import yaml
except ModuleNotFoundError as exc:
    raise RuntimeError("PyYAML is required: pip install pyyaml") from exc

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG_DIR = ROOT / "config"

_cache: Dict[str, Any] = {}


def _load_yaml(path: pathlib.Path) -> Any:
    if path in _cache:
        return _cache[path]
    with path.open("r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    _cache[path] = data
    return data


def load_intents() -> Dict[str, Any]:
    return _load_yaml(CONFIG_DIR / "intents.yaml")


def load_doctrine() -> Dict[str, Any]:
    return _load_yaml(CONFIG_DIR / "doctrine.yaml")


def load_callsigns() -> Dict[str, Any]:
    return _load_yaml(CONFIG_DIR / "callsigns.yaml")


def load_airfields() -> Dict[str, Any]:
    return _load_yaml(CONFIG_DIR / "airfields.yaml")


def load_tankers() -> Dict[str, Any]:
    return _load_yaml(CONFIG_DIR / "tankers.yaml")


def reset_cache():
    _cache.clear()


__all__ = [
    "load_intents",
    "load_doctrine",
    "load_callsigns",
    "load_airfields",
    "load_tankers",
    "reset_cache",
    "CONFIG_DIR",
]
