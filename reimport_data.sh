#!/bin/bash

# ============================================
# 快速重新导入数据脚本
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
log_info "  快速重新导入数据"
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
else
    log_error "虚拟环境不存在，请先运行部署脚本"
    exit 1
fi

# 检查数据目录
if [[ ! -d "$IMPORT_DIR" ]]; then
    log_error "数据目录不存在: $IMPORT_DIR"
    exit 1
fi

# 删除所有 .done 标记
log_info "删除所有 .done 标记文件..."
done_count=$(find "$IMPORT_DIR" -type f -name "*.done" | wc -l)
find "$IMPORT_DIR" -type f -name "*.done" -delete 2>/dev/null || true
log_success "已删除 $done_count 个 .done 标记文件"

# 设置环境变量
export IMPORT_DIR="$IMPORT_DIR"
export EXCLUDE_SERVERS="${EXCLUDE_SERVERS:-9000}"
export POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
export POSTGRES_USER="${POSTGRES_USER:-app}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-app}"
export POSTGRES_DB="${POSTGRES_DB:-pvp}"

# 开始导入
log_info "开始导入数据..."
python3 << 'PYEOF'
import os
import sys
from backend.app.auto_importer import run_import_once

logs_dir = os.environ.get('IMPORT_DIR', 'data_logs')
count = run_import_once(logs_dir)
print(f"\n导入完成！共导入 {count} 条记录")
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

