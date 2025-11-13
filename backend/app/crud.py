from typing import List, Optional, Tuple
from sqlalchemy.orm import Session
from sqlalchemy import select, func, asc, desc, case, exists, and_
from backend.app.models import MatchRecord, match_pet_talent_v, match_rune_v


def _apply_common_filters(q, 
                          servers: Optional[List[int]] = None,
                          start_ts: Optional[int] = None,
                          end_ts: Optional[int] = None,
                          min_level: Optional[int] = None,
                          max_level: Optional[int] = None,
                          clazz: Optional[int] = None,
                          schools: Optional[int] = None,
                          opponent_class: Optional[int] = None,
                          opponent_schools: Optional[int] = None,
                          spirit_animal: Optional[List[int]] = None,
                          spirit_animal_talents: Optional[int] = None,
                          legendary_runes: Optional[List[int]] = None,
                          super_armor: Optional[int] = None,
                          source_types: Optional[List[int]] = None):
    if servers:
        q = q.where(MatchRecord.server.in_(servers))
    if start_ts is not None:
        q = q.where(MatchRecord.timestamp >= start_ts)
    if end_ts is not None:
        q = q.where(MatchRecord.timestamp <= end_ts)
    if min_level is not None:
        q = q.where(MatchRecord.level >= min_level)
    if max_level is not None:
        q = q.where(MatchRecord.level <= max_level)
    if clazz is not None:
        q = q.where(MatchRecord.clazz == clazz)
    if schools is not None:
        q = q.where(MatchRecord.schools == schools)
    if opponent_class is not None:
        q = q.where(MatchRecord.opponent_class == opponent_class)
    if opponent_schools is not None:
        q = q.where(MatchRecord.opponent_schools == opponent_schools)
    if spirit_animal:
        pet_cond = [match_pet_talent_v.c.match_id == MatchRecord.id,
                    match_pet_talent_v.c.pet_id.in_(spirit_animal)]
        if spirit_animal_talents is not None and spirit_animal_talents != 0:
            pet_cond.append(match_pet_talent_v.c.talent_value == spirit_animal_talents)
        q = q.where(exists(select(1).where(and_(*pet_cond))))
    if legendary_runes:
        q = q.where(exists(select(1).where(and_(
            match_rune_v.c.match_id == MatchRecord.id,
            match_rune_v.c.rune_id.in_(legendary_runes)
        ))))
    if super_armor is not None:
        q = q.where(MatchRecord.super_armor == super_armor)
    if source_types:
        q = q.where(MatchRecord.source_type.in_(source_types))
    return q


def _parse_sort(sort: Optional[str], mapping: dict) -> List:
    if not sort:
        return []
    orders = []
    for part in sort.split(','):
        if not part:
            continue
        col, _, direction = part.partition(':')
        col = col.strip()
        direction = direction.strip().lower() or 'asc'
        if col in mapping:
            orders.append(asc(mapping[col]) if direction == 'asc' else desc(mapping[col]))
    return orders


def query_winrate(db: Session,
                  group_by_opponent: bool,
                  **filters):
    # 提前取出排序参数，避免传入通用过滤器
    sort_param = filters.pop('sort', None)
    # 分组字段：是否细分到对手职业与流派
    # 区服合并：8001/8002/8004 合并为同一组（以8001代表）
    # 区服合并：8024/8027 合并为同一组（以8024代表）
    server_group = case(
        (MatchRecord.server.in_([8001, 8002, 8004]), 8001),
        (MatchRecord.server.in_([8024, 8027]), 8024),
        else_=MatchRecord.server,
    ).label('server_group')
    group_cols = [
        server_group,
        MatchRecord.clazz,
        MatchRecord.schools,
        MatchRecord.source_type
    ]
    if group_by_opponent:
        group_cols += [MatchRecord.opponent_class, MatchRecord.opponent_schools]

    win_count = func.sum(case((MatchRecord.is_win == 1, 1), else_=0)).label('win_count')
    lose_count = func.sum(case((MatchRecord.is_win == 0, 1), else_=0)).label('lose_count')
    match_count = func.count().label('match_count')
    win_rate = (func.nullif(win_count, 0) / func.nullif(match_count, 0)).label('win_rate')

    q = select(*group_cols, win_count, lose_count, match_count, win_rate)
    q = _apply_common_filters(q, **filters)
    q = q.group_by(*group_cols)

    sort_mapping = {
        'server': server_group,
        'class': MatchRecord.clazz,
        'schools': MatchRecord.schools,
        'opponent_class': MatchRecord.opponent_class,
        'opponent_schools': MatchRecord.opponent_schools,
        'source_type': MatchRecord.source_type,
        'win_count': win_count,
        'lose_count': lose_count,
        'match_count': match_count,
        'win_rate': win_rate,
    }
    orders = _parse_sort(sort_param, sort_mapping)
    if orders:
        q = q.order_by(*orders)

    return db.execute(q).all()


def query_duration(db: Session,
                   group_by_opponent: bool,
                   **filters):
    # 提前取出排序参数，避免传入通用过滤器
    sort_param = filters.pop('sort', None)
    # 区服合并：8001/8002/8004 合并为同一组（以8001代表）
    # 区服合并：8024/8027 合并为同一组（以8024代表）
    server_group = case(
        (MatchRecord.server.in_([8001, 8002, 8004]), 8001),
        (MatchRecord.server.in_([8024, 8027]), 8024),
        else_=MatchRecord.server,
    ).label('server_group')
    group_cols = [
        server_group,
        MatchRecord.clazz,
        MatchRecord.schools,
        MatchRecord.source_type
    ]
    if group_by_opponent:
        group_cols += [MatchRecord.opponent_class, MatchRecord.opponent_schools]

    avg_duration = func.avg(MatchRecord.duration).label('avg_duration')
    max_duration = func.max(MatchRecord.duration).label('max_duration')
    min_duration = func.min(MatchRecord.duration).label('min_duration')
    # 近似中位数：percentile_disc(0.5) within group
    median_duration = func.percentile_disc(0.5).within_group(MatchRecord.duration).label('median_duration')

    q = select(*group_cols, avg_duration, max_duration, min_duration, median_duration)
    q = _apply_common_filters(q, **filters)
    q = q.group_by(*group_cols)

    sort_mapping = {
        'server': server_group,
        'class': MatchRecord.clazz,
        'schools': MatchRecord.schools,
        'opponent_class': MatchRecord.opponent_class,
        'opponent_schools': MatchRecord.opponent_schools,
        'source_type': MatchRecord.source_type,
        'avg_duration': avg_duration,
        'max_duration': max_duration,
        'min_duration': min_duration,
        'median_duration': median_duration,
    }
    orders = _parse_sort(sort_param, sort_mapping)
    if orders:
        q = q.order_by(*orders)

    return db.execute(q).all()


