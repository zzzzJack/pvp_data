import os
import json
from typing import List, Iterable, Set
import re

from sqlalchemy.orm import Session

from backend.app.database import SessionLocal
from backend.app.models import MatchRecord


_ST_FIX_RE = re.compile(r'("source_type"\s*:\s*)(gold_league|season_play_pvp_mgr)\b')


def _robust_json_load(line: str) -> dict | None:
    try:
        return json.loads(line)
    except Exception:
        pass
    fixed = _ST_FIX_RE.sub(lambda m: f"{m.group(1)}\"{m.group(2)}\"", line)
    if fixed != line:
        try:
            return json.loads(fixed)
        except Exception:
            return None
    return None


def _normalize_keys(obj: dict) -> dict:
    if "spirit_animal" not in obj and "pet_list" in obj:
        obj["spirit_animal"] = obj.get("pet_list")
    if "spirit_animal_talents" not in obj and "pet_talent_list" in obj:
        obj["spirit_animal_talents"] = obj.get("pet_talent_list")
    if "legendary_runes" not in obj and "rune_list" in obj:
        obj["legendary_runes"] = obj.get("rune_list")
    if "super_armor" not in obj and "armor" in obj:
        obj["super_armor"] = obj.get("armor")
    return obj


def _iter_jsonl(path: str) -> Iterable[dict]:
    with open(path, 'r', encoding='utf-8') as fp:
        for line in fp:
            line = line.strip()
            if not line:
                continue
            obj = _robust_json_load(line)
            if obj is None:
                continue
            yield _normalize_keys(obj)


def _parse_exclude_servers() -> Set[int]:
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
    try:
        return int(value)
    except Exception:
        return 0


def _bulk_insert_file(db: Session, file_path: str, batch_size: int = 2000) -> int:
    count = 0
    buf: List[MatchRecord] = []
    exclude_servers = _parse_exclude_servers()
    for obj in _iter_jsonl(file_path):
        # server 过滤
        try:
            server_val = int(obj.get("server"))
        except Exception:
            continue
        if server_val in exclude_servers:
            continue
        # source_type 规范化
        obj["source_type"] = _normalize_source_type(obj.get("source_type"), obj)
        buf.append(MatchRecord(
            server=obj["server"],
            timestamp=obj["timestamp"],
            level=obj["level"],
            clazz=obj["class"],
            schools=obj["schools"],
            opponent_class=obj.get("opponent_class", 0),
            opponent_schools=obj.get("opponent_schools", 0),
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
            count += len(buf)
            buf.clear()
    if buf:
        db.bulk_save_objects(buf)
        db.commit()
        count += len(buf)
    return count


def run_import_once(logs_dir: str = None) -> int:
    """Scan logs_dir recursively for .jsonl files without '.done' marker and import them.
    Returns imported rows count.
    """
    logs_dir = logs_dir or os.environ.get('IMPORT_DIR', 'data_logs')
    if not os.path.isdir(logs_dir):
        return 0
    imported = 0
    with SessionLocal() as db:
        for root, _, files in os.walk(logs_dir):
            for f in files:
                if not (f.endswith('.jsonl') or f.endswith('.txt')):
                    continue
                src = os.path.join(root, f)
                marker = src + '.done'
                if os.path.exists(marker):
                    continue
                imported += _bulk_insert_file(db, src)
                # 写入标记文件
                try:
                    with open(marker, 'w') as m:
                        m.write('ok')
                except Exception:
                    pass
    return imported


