"""
增量导入模块 - 支持追加日志文件的增量导入
记录每个文件的导入位置，只导入新增内容
"""
import os
import json
import hashlib
from typing import List, Iterable, Set, Optional, Tuple
from pathlib import Path
import re

from sqlalchemy.orm import Session
from sqlalchemy import text

from backend.app.database import SessionLocal
from backend.app.models import MatchRecord


_ST_FIX_RE = re.compile(r'("source_type"\s*:\s*)(gold_league|season_play_pvp_mgr|qualifying_wheel_first_combat)\b')

# 导入位置记录文件（JSON格式）
_POSITION_FILE = ".import_positions.json"


def _robust_json_load(line: str) -> Optional[dict]:
    """Try strict JSON first; if failed, fix known patterns then retry."""
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
    """Map alternate field names to model fields"""
    if "spirit_animal" not in obj and "pet_list" in obj:
        obj["spirit_animal"] = obj.get("pet_list")
    if "spirit_animal_talents" not in obj and "pet_talent_list" in obj:
        obj["spirit_animal_talents"] = obj.get("pet_talent_list")
    if "legendary_runes" not in obj and "rune_list" in obj:
        obj["legendary_runes"] = obj.get("rune_list")
    if "super_armor" not in obj and "armor" in obj:
        obj["super_armor"] = obj.get("armor")
    return obj


def _get_source_types(value, obj) -> List[int]:
    """获取数据源类型列表（可能返回多个类型）"""
    result = []
    if isinstance(value, int):
        return [value]
    if isinstance(value, str):
        v = value.strip().lower()
        is_win_val = obj.get("is_win")
        has_valid_win = is_win_val is not None and is_win_val in (0, 1)
        duration_val = obj.get("duration")
        has_valid_duration = (duration_val is not None 
                             and duration_val is not False 
                             and isinstance(duration_val, (int, float)) 
                             and duration_val > 0)
        
        if v in {"gold_league", "gold-league", "champion_league", "goldleague"}:
            if has_valid_win:
                result.append(1)
            if has_valid_duration:
                result.append(4)
            if not result:
                result.append(1)
        elif v in {"season_play_pvp_mgr", "season", "ladder", "pvp_ladder"}:
            if has_valid_win:
                result.append(3)
            if has_valid_duration:
                result.append(6)
            if not result:
                result.append(3)
        elif v in {"qualifying_wheel_first_combat", "qualifying-wheel-first-combat", "wheel_first"}:
            if has_valid_win:
                result.append(2)
            if has_valid_duration:
                result.append(5)
            if not result:
                result.append(2)
        else:
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


def _parse_exclude_servers() -> Set[int]:
    """Parse EXCLUDE_SERVERS env to a set of ints"""
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


def _load_positions(logs_dir: str) -> dict:
    """加载导入位置记录"""
    pos_file = os.path.join(logs_dir, _POSITION_FILE)
    if os.path.exists(pos_file):
        try:
            with open(pos_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception:
            return {}
    return {}


def _save_positions(logs_dir: str, positions: dict):
    """保存导入位置记录"""
    pos_file = os.path.join(logs_dir, _POSITION_FILE)
    try:
        with open(pos_file, 'w', encoding='utf-8') as f:
            json.dump(positions, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"Warning: Failed to save positions: {e}")


def _get_file_key(file_path: str) -> str:
    """生成文件的唯一标识（使用绝对路径的哈希）"""
    abs_path = os.path.abspath(file_path)
    return hashlib.md5(abs_path.encode('utf-8')).hexdigest()


def _read_lines_from_position(file_path: str, start_position: int) -> Iterable[Tuple[int, str]]:
    """从指定位置读取文件行，返回 (行号, 内容)"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            # 如果 start_position > 0，跳过已读取的行
            for _ in range(start_position):
                try:
                    f.readline()
                except Exception:
                    break
            
            # 读取剩余行
            line_num = start_position
            while True:
                line = f.readline()
                if not line:
                    break
                yield (line_num, line.rstrip('\n\r'))
                line_num += 1
    except Exception as e:
        print(f"Error reading {file_path}: {e}")


def _bulk_insert_incremental(db: Session, file_path: str, start_line: int, batch_size: int = 2000) -> int:
    """增量导入：从指定行号开始导入"""
    count = 0
    buf: List[MatchRecord] = []
    exclude_servers = _parse_exclude_servers()
    
    for line_num, line in _read_lines_from_position(file_path, start_line):
        if not line.strip():
            continue
        
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
        
        # source_type 规范化
        source_types = _get_source_types(obj.get("source_type"), obj)
        
        # 为每个 source_type 创建一条记录
        for source_type in source_types:
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
                source_type=source_type,
                score_ratio=obj.get("score_ratio", 0),
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


def _count_file_lines(file_path: str) -> int:
    """统计文件总行数"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return sum(1 for _ in f)
    except Exception:
        return 0


def run_incremental_import(logs_dir: str = None) -> int:
    """增量导入：只导入文件的新增内容
    
    工作原理：
    1. 读取 .import_positions.json 记录每个文件上次导入的行号
    2. 对于每个日志文件，从上次位置继续导入
    3. 更新位置记录
    """
    logs_dir = logs_dir or os.environ.get('IMPORT_DIR', 'data_logs')
    if not os.path.isdir(logs_dir):
        return 0
    
    positions = _load_positions(logs_dir)
    total_imported = 0
    
    with SessionLocal() as db:
        for root, _, files in os.walk(logs_dir):
            for f in files:
                if not (f.endswith('.jsonl') or f.endswith('.txt')):
                    continue
                
                src = os.path.join(root, f)
                file_key = _get_file_key(src)
                
                # 获取上次导入位置（默认为0，从头开始）
                last_position = positions.get(file_key, 0)
                
                # 获取文件当前总行数
                current_lines = _count_file_lines(src)
                
                # 如果文件没有新内容，跳过
                if current_lines <= last_position:
                    continue
                
                print(f"导入 {src} (从第 {last_position + 1} 行到第 {current_lines} 行)...")
                
                # 增量导入
                imported = _bulk_insert_incremental(db, src, last_position, batch_size=2000)
                total_imported += imported
                
                # 更新位置记录
                positions[file_key] = current_lines
                print(f"  已导入 {imported} 条记录，文件位置已更新到第 {current_lines} 行")
        
        # 保存位置记录
        _save_positions(logs_dir, positions)
    
    return total_imported


def reset_import_positions(logs_dir: str = None, file_pattern: str = None):
    """重置导入位置（用于重新导入）
    
    Args:
        logs_dir: 日志目录
        file_pattern: 可选的文件名模式（如 "2025_11_13.txt"），只重置匹配的文件
    """
    logs_dir = logs_dir or os.environ.get('IMPORT_DIR', 'data_logs')
    positions = _load_positions(logs_dir)
    
    if file_pattern:
        # 只重置匹配的文件
        for root, _, files in os.walk(logs_dir):
            for f in files:
                if file_pattern in f:
                    src = os.path.join(root, f)
                    file_key = _get_file_key(src)
                    if file_key in positions:
                        del positions[file_key]
                        print(f"已重置 {src} 的导入位置")
    else:
        # 重置所有文件
        positions.clear()
        print("已重置所有文件的导入位置")
    
    _save_positions(logs_dir, positions)


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "reset":
        reset_import_positions()
    else:
        count = run_incremental_import()
        print(f"\n增量导入完成！共导入 {count} 条新记录")

