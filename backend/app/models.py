from sqlalchemy import Column, Integer, BigInteger, SmallInteger, String, DateTime, JSON
from sqlalchemy import Index
from sqlalchemy.dialects.postgresql import ARRAY
from backend.app.database import Base
from sqlalchemy import Table


class MatchRecord(Base):
    __tablename__ = "match_records"

    id = Column(BigInteger, primary_key=True, autoincrement=True)

    # 核心维度
    server = Column(Integer, nullable=False)
    timestamp = Column(BigInteger, nullable=False)  # 秒级时间戳
    level = Column(Integer, nullable=False)

    # 职业/流派（己方）
    clazz = Column(SmallInteger, nullable=False)
    schools = Column(SmallInteger, nullable=False)

    # 职业/流派（对手）
    opponent_class = Column(SmallInteger, nullable=False)
    opponent_schools = Column(SmallInteger, nullable=False)

    # 结果/时长
    is_win = Column(SmallInteger, nullable=False)  # 1 or 0
    duration = Column(Integer, nullable=False)     # 秒

    # SP 装配
    spirit_animal = Column(ARRAY(Integer), nullable=True)          # 最多3个
    spirit_animal_talents = Column(ARRAY(Integer), nullable=True)  # 与上对应
    legendary_runes = Column(ARRAY(Integer), nullable=True)        # 最多3个
    super_armor = Column(Integer, nullable=True)

    # 来源类型：1..8
    source_type = Column(SmallInteger, nullable=False)
    score_ratio = Column(Integer, nullable=False, default=0)  # 千分比


# 常用组合索引
Index("ix_records_time", MatchRecord.timestamp)
Index("ix_records_server", MatchRecord.server)
Index("ix_records_level", MatchRecord.level)
Index("ix_records_class_school", MatchRecord.clazz, MatchRecord.schools)
Index("ix_records_opp_class_school", MatchRecord.opponent_class, MatchRecord.opponent_schools)
Index("ix_records_source_type", MatchRecord.source_type)
Index("ix_records_score_ratio", MatchRecord.score_ratio)


# Helper views as tables for querying (created via SQL in scripts/migration_001_views.sql)
match_pet_talent_v = Table(
    "match_pet_talent_v",
    Base.metadata,
    Column("match_id", BigInteger),
    Column("pet_id", Integer),
    Column("talent_value", Integer),
    extend_existing=True,
)

match_rune_v = Table(
    "match_rune_v",
    Base.metadata,
    Column("match_id", BigInteger),
    Column("rune_id", Integer),
    extend_existing=True,
)

