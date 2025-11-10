import argparse
import json
import os
from typing import List, Set, Optional

from sqlalchemy.orm import Session
from backend.app.database import SessionLocal, engine, Base
from backend.app.models import MatchRecord
import re


def ensure_tables():
    Base.metadata.create_all(bind=engine)


def _parse_exclude_servers() -> Set[int]:
    """Parse EXCLUDE_SERVERS env to a set of ints. e.g. "9000,9001""" 
    raw = os.environ.get("EXCLUDE_SERVERS", "9000")
    result: Set[int] = set()
    for part in raw.split(','):
        part = part.strip()
        if not part:
            continue
        try:
            result.add(int(part))
        except Exception:
            continue
    return result


def _normalize_source_type(value, obj) -> int:
    """Accept int or known strings and map to existing numeric enums.
    - gold_league: winrate->1, duration->4
    - season_play_pvp_mgr: winrate->3, duration->6
    Heuristic: if DEFAULT_*_METRIC env provided, prefer it when both metrics present.
    """
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        v = value.strip().lower()
        has_win = obj.get("is_win") is not None
        has_duration = obj.get("duration") is not None and obj.get("duration") is not False
        if v in {"gold_league", "gold-league", "champion_league", "goldleague"}:
            prefer = os.environ.get("DEFAULT_GOLD_LEAGUE_METRIC", "winrate").lower()
            if has_win and not has_duration:
                return 1
            if has_duration and not has_win:
                return 4
            return 1 if prefer == "winrate" else 4
        if v in {"season_play_pvp_mgr", "season", "ladder", "pvp_ladder"}:
            prefer = os.environ.get("DEFAULT_SEASON_METRIC", "winrate").lower()
            if has_win and not has_duration:
                return 3
            if has_duration and not has_win:
                return 6
            return 3 if prefer == "winrate" else 6
    # Fallback
    try:
        return int(value)
    except Exception:
        return 0


_ST_FIX_RE = re.compile(r'("source_type"\s*:\s*)(gold_league|season_play_pvp_mgr)\b')


def _robust_json_load(line: str) -> Optional[dict]:
    """Try strict JSON first; if failed, fix known patterns then retry."""
    try:
        return json.loads(line)
    except Exception:
        pass
    # Fix unquoted source_type tokens
    fixed = _ST_FIX_RE.sub(lambda m: f"{m.group(1)}\"{m.group(2)}\"", line)
    if fixed != line:
        try:
            return json.loads(fixed)
        except Exception:
            return None
    return None


def _normalize_keys(obj: dict) -> dict:
    # Map alternate field names to model fields
    if "spirit_animal" not in obj and "pet_list" in obj:
        obj["spirit_animal"] = obj.get("pet_list")
    if "spirit_animal_talents" not in obj and "pet_talent_list" in obj:
        obj["spirit_animal_talents"] = obj.get("pet_talent_list")
    if "legendary_runes" not in obj and "rune_list" in obj:
        obj["legendary_runes"] = obj.get("rune_list")
    if "super_armor" not in obj and "armor" in obj:
        obj["super_armor"] = obj.get("armor")
    return obj


def load_jsonl_files(logs_dir: str) -> List[dict]:
    records = []
    exclude_servers = _parse_exclude_servers()
    for root, _, files in os.walk(logs_dir):
        for f in files:
            if not (f.endswith('.jsonl') or f.endswith('.txt')):
                continue
            path = os.path.join(root, f)
            with open(path, 'r', encoding='utf-8') as fp:
                for line in fp:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = _robust_json_load(line)
                        if obj is None:
                            continue
                        obj = _normalize_keys(obj)
                        # server 过滤
                        try:
                            server_val = int(obj.get("server"))
                        except Exception:
                            continue
                        if server_val in exclude_servers:
                            continue
                        # 映射 source_type
                        obj["source_type"] = _normalize_source_type(obj.get("source_type"), obj)
                        records.append(obj)
                    except Exception:
                        continue
    return records


def bulk_insert(db: Session, rows: List[dict], batch_size: int = 2000):
    buf = []
    for obj in rows:
        buf.append(MatchRecord(
            server=obj["server"],
            timestamp=obj["timestamp"],
            level=obj["level"],
            clazz=obj["class"],
            schools=obj["schools"],
            opponent_class=obj["opponent_class"],
            opponent_schools=obj["opponent_schools"],
            is_win=obj.get("is_win", 0),
            duration=obj.get("duration", 0),
            spirit_animal=obj.get("spirit_animal"),
            spirit_animal_talents=obj.get("spirit_animal_talents"),
            legendary_runes=obj.get("legendary_runes"),
            super_armor=obj.get("super_armor"),
            source_type=obj.get("source_type", 0),
        ))
        if len(buf) >= batch_size:
            db.bulk_save_objects(buf)
            db.commit()
            buf.clear()
    if buf:
        db.bulk_save_objects(buf)
        db.commit()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--logs_dir', type=str, required=True)
    args = parser.parse_args()

    ensure_tables()
    rows = load_jsonl_files(args.logs_dir)
    with SessionLocal() as db:
        bulk_insert(db, rows)
    print(f"Imported {len(rows)} rows.")


if __name__ == '__main__':
    main()


