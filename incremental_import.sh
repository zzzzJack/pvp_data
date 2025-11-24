#!/bin/bash

# ============================================
# 增量导入脚本 - 支持追加日志文件
# ============================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

IMPORT_DIR="${IMPORT_DIR:-./data_logs}"

echo ""
log_info "=========================================="
log_info "  增量导入数据（支持追加日志）"
log_info "=========================================="
echo ""

# 检查是否在项目目录
if [[ ! -f "requirements.txt" ]] || [[ ! -d "backend" ]]; then
    log_error "请在项目根目录运行此脚本"
    exit 1
fi

# 激活虚拟环境
if [[ -f ".venv/bin/activate" ]]; then
    log_info "激活虚拟环境..."
    source .venv/bin/activate
elif [[ -f "venv/bin/activate" ]]; then
    log_info "激活虚拟环境..."
    source venv/bin/activate
else
    log_warning "虚拟环境不存在，使用系统 Python"
fi

# 检查数据目录
if [[ ! -d "$IMPORT_DIR" ]]; then
    log_error "数据目录不存在: $IMPORT_DIR"
    exit 1
fi

# 设置环境变量
export IMPORT_DIR="$IMPORT_DIR"
export EXCLUDE_SERVERS="${EXCLUDE_SERVERS:-9000}"
export POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
export POSTGRES_USER="${POSTGRES_USER:-app}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-app}"
export POSTGRES_DB="${POSTGRES_DB:-pvp}"

# 检查参数
if [[ "$1" == "reset" ]]; then
    log_warning "重置导入位置..."
    python3 << 'PYEOF'
import os
import sys
from pathlib import Path

# 添加项目根目录到路径
script_dir = Path(__file__).parent if '__file__' in globals() else Path.cwd()
project_root = script_dir if (script_dir / 'backend').exists() else script_dir.parent
sys.path.insert(0, str(project_root))

from backend.app.incremental_importer import reset_import_positions

logs_dir = os.environ.get('IMPORT_DIR', 'data_logs')
file_pattern = sys.argv[2] if len(sys.argv) > 2 else None
reset_import_positions(logs_dir, file_pattern)
print("重置完成")
PYEOF
    exit 0
fi

# 开始增量导入
log_info "开始增量导入数据..."
log_info "提示：只导入文件的新增内容，不会重复导入已导入的数据"
echo ""

python3 << 'PYEOF'
import os
import sys
from pathlib import Path

# 添加项目根目录到路径
script_dir = Path(__file__).parent if '__file__' in globals() else Path.cwd()
project_root = script_dir if (script_dir / 'backend').exists() else script_dir.parent
sys.path.insert(0, str(project_root))

from backend.app.incremental_importer import run_incremental_import

logs_dir = os.environ.get('IMPORT_DIR', 'data_logs')
count = run_incremental_import(logs_dir)
print(f"\n增量导入完成！共导入 {count} 条新记录")
sys.exit(0 if count >= 0 else 1)
PYEOF

if [[ $? -eq 0 ]]; then
    log_success "数据导入成功"
    
    # 查询数据库记录数
    echo ""
    log_info "==================== 导入统计 ===================="
    python3 << 'PYEOF'
import os
from sqlalchemy import text
from backend.app.database import SessionLocal

os.environ.setdefault('POSTGRES_HOST', 'localhost')
os.environ.setdefault('POSTGRES_PORT', '5432')
os.environ.setdefault('POSTGRES_USER', 'app')
os.environ.setdefault('POSTGRES_PASSWORD', 'app')
os.environ.setdefault('POSTGRES_DB', 'pvp')

try:
    with SessionLocal() as db:
        result = db.execute(text("SELECT COUNT(*) FROM match_records;"))
        total = result.scalar()
        print(f"数据库总记录数: {total}")
        
        # 查询最新记录时间
        result = db.execute(text("SELECT MAX(timestamp) FROM match_records;"))
        max_ts = result.scalar()
        if max_ts:
            from datetime import datetime
            dt = datetime.fromtimestamp(max_ts)
            print(f"最新记录时间: {dt.strftime('%Y-%m-%d %H:%M:%S')}")
except Exception as e:
    print(f"查询失败: {e}")
PYEOF
else
    log_error "数据导入失败"
    exit 1
fi

echo ""
log_info "=========================================="
log_success "完成！"
echo ""
log_info "使用说明："
log_info "  - 默认：增量导入（只导入新增内容）"
log_info "  - 重置位置：./incremental_import.sh reset"
log_info "  - 重置特定文件：./incremental_import.sh reset 2025_11_13.txt"

