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


def _get_source_types(value, obj) -> List[int]:
    """获取数据源类型列表（可能返回多个类型）
    - 数据源同时包含 is_win 和 duration 字段时，返回两个类型
    - 计算胜率时使用 is_win 字段：
      * gold_league -> 1 (冠军联赛胜率)
      * season -> 3 (决斗天梯胜率)
      * qualifying_wheel_first_combat -> 2 (武道大会(车轮战首场)胜率)
    - 计算时长时使用 duration 字段：
      * gold_league -> 4 (冠军联赛战斗时长)
      * season -> 6 (决斗天梯战斗时长)
      * qualifying_wheel_first_combat -> 5 (武道大会(车轮战首场)战斗时长)
    - 返回列表，可能包含一个或两个类型
    """
    result = []
    if isinstance(value, int):
        return [value]
    if isinstance(value, str):
        v = value.strip().lower()
        # 检查 is_win 是否有效：不为 None 且为 0 或 1
        is_win_val = obj.get("is_win")
        has_valid_win = is_win_val is not None and is_win_val in (0, 1)
        # 检查 duration 是否有效：不为 None，不为 False，且 > 0
        duration_val = obj.get("duration")
        has_valid_duration = (duration_val is not None 
                             and duration_val is not False 
                             and isinstance(duration_val, (int, float)) 
                             and duration_val > 0)
        
        if v in {"gold_league", "gold-league", "champion_league", "goldleague"}:
            # 如果 is_win 有效，添加胜率类型
            if has_valid_win:
                result.append(1)
            # 如果 duration 有效，添加时长类型
            if has_valid_duration:
                result.append(4)
            # 如果两个都无效，默认返回胜率类型
            if not result:
                result.append(1)
        elif v in {"season_play_pvp_mgr", "season", "ladder", "pvp_ladder"}:
            # 如果 is_win 有效，添加胜率类型
            if has_valid_win:
                result.append(3)
            # 如果 duration 有效，添加时长类型
            if has_valid_duration:
                result.append(6)
            # 如果两个都无效，默认返回胜率类型
            if not result:
                result.append(3)
        elif v in {"qualifying_wheel_first_combat", "qualifying-wheel-first-combat", "wheel_first"}:
            # 如果 is_win 有效，添加胜率类型
            if has_valid_win:
                result.append(2)
            # 如果 duration 有效，添加时长类型
            if has_valid_duration:
                result.append(5)
            # 如果两个都无效，默认返回胜率类型
            if not result:
                result.append(2)
        else:
            # 未知类型，尝试转换为整数
            try:
                result.append(int(value))
            except Exception:
                result.append(0)
    else:
        try:
            result.append(int(value))
        except Exception:
            result.append(0)
    
    return result if result else [0]


def _normalize_source_type(value, obj) -> int:
    """规范化数据源类型（兼容旧代码，返回第一个类型）"""
    types = _get_source_types(value, obj)
    return types[0] if types else 0


_ST_FIX_RE = re.compile(r'("source_type"\s*:\s*)(gold_league|season_play_pvp_mgr|qualifying_wheel_first_combat)\b')


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
                        # 映射 source_type - 可能返回多个类型（胜率和时长）
                        # 为每个类型创建一条记录
                        source_types = _get_source_types(obj.get("source_type"), obj)
                        for source_type in source_types:
                            obj_copy = obj.copy()
                            obj_copy["source_type"] = source_type
                            records.append(obj_copy)
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


