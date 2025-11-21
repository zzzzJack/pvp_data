import os
import sys
from pathlib import Path

# 添加项目根目录到 Python 路径
script_dir = Path(__file__).parent
project_root = script_dir.parent
sys.path.insert(0, str(project_root))

from sqlalchemy import text
from backend.app.database import engine, Base
from backend.app.models import MatchRecord

# Set env vars if needed, though they default in database.py
os.environ.setdefault('POSTGRES_HOST', 'localhost')
os.environ.setdefault('POSTGRES_PORT', '5432')
os.environ.setdefault('POSTGRES_USER', 'app')
os.environ.setdefault('POSTGRES_PASSWORD', 'app')
os.environ.setdefault('POSTGRES_DB', 'pvp')

def reset_schema():
    print("Dropping table match_records...")
    try:
        with engine.connect() as conn:
            conn.execute(text("DROP TABLE IF EXISTS match_records CASCADE;"))
            conn.commit()
        print("Table dropped.")
    except Exception as e:
        print(f"Error dropping table: {e}")
        sys.exit(1)

    print("Creating tables...")
    try:
        Base.metadata.create_all(bind=engine)
        print("Tables created.")
    except Exception as e:
        print(f"Error creating tables: {e}")
        sys.exit(1)

if __name__ == "__main__":
    reset_schema()

