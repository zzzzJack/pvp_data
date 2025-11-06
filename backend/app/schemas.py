from pydantic import BaseModel, Field
from typing import Optional, List


# 区服映射
SERVER_MAP = {
    8001: "国服圣斗服",
    8002: "国服圣斗服", 
    8004: "国服圣斗服",
    8024: "国服怀旧",
    9001: "港台怀旧",
    8010: "公会服"
}

# 职业映射
CLASS_MAP = {
    1: "法师", 2: "弓手", 3: "圣言", 4: "剑骑士", 5: "隐刺",
    6: "格斗家", 7: "枪手", 8: "战锤", 9: "行者", 10: "噬魂", 11: "驯兽师"
}

# 流派映射
SCHOOL_MAP = {
    0: "", 1: "火系", 2: "风系"
}

# 职业流派映射
SCHOOLS_MAP = {
    (0, 1): "魔导", (1, 1): "火术士", (2, 1): "冰法师",
    (0, 2): "弓手", (1, 2): "神射手", (2, 2): "风语者",
    (0, 3): "圣言", (1, 3): "审判者", (2, 3): "白贤者",
    (0, 4): "剑骑士", (1, 4): "守护者", (2, 4): "毁灭者",
    (0, 5): "隐刺", (1, 5): "瞬杀者", (2, 5): "影舞者",
    (0, 6): "格斗家", (1, 6): "阿修罗", (2, 6): "气功师",
    (0, 7): "枪手", (1, 7): "枪炮师", (2, 7): "指挥官",
    (0, 8): "战锤", (1, 8): "终结者", (2, 8): "征服者",
    (0, 9): "行者", (1, 9): "炎斗流", (2, 9): "幻武流",
    (0, 10): "噬魂", (1, 10): "虹吸流", (2, 10): "献祭流",
    (0, 11): "驯兽师", (1, 11): "万兽王", (2, 11): "通灵王"
}

def get_class_school_name(class_id: int, school_id: int) -> str:
    """根据 (流派索引, 职业ID) 返回中文名；若未配置则回退到职业名。"""
    # 注意：SCHOOLS_MAP 的键是 (school_id, class_id)
    name = SCHOOLS_MAP.get((school_id, class_id))
    if name:
        return name
    return CLASS_MAP.get(class_id, f"职业{class_id}")

# 数据源类型映射
SOURCE_TYPE_MAP = {
    1: "冠军联赛胜率",
    2: "武道大会(车轮战首场)胜率", 
    3: "决斗天梯胜率",
    4: "冠军联赛战斗时长",
    5: "武道大会(车轮战首场)战斗时长",
    6: "决斗天梯战斗时长",
    7: "武道大会非车轮战胜率",
    8: "武道大会非车轮战战斗时长"
}


class WinrateRow(BaseModel):
    server: int
    clazz: int
    schools: int
    opponent_class: Optional[int] = None
    opponent_schools: Optional[int] = None
    source_type: int
    win_count: int
    lose_count: int
    match_count: int
    win_rate: float


class DurationRow(BaseModel):
    server: int
    clazz: int
    schools: int
    opponent_class: Optional[int] = None
    opponent_schools: Optional[int] = None
    source_type: int
    avg_duration: float
    max_duration: int
    min_duration: int
    median_duration: float


class ExportResponse(BaseModel):
    url: str


