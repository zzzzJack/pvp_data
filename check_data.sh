#!/bin/bash

# ============================================
# 数据文件诊断脚本
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
log_info "  数据文件诊断工具"
log_info "=========================================="
echo ""

# 检查数据目录
if [[ ! -d "$IMPORT_DIR" ]]; then
    log_error "数据目录不存在: $IMPORT_DIR"
    exit 1
fi

# 激活虚拟环境
if [[ -f ".venv/bin/activate" ]]; then
    source .venv/bin/activate
else
    log_error "虚拟环境不存在"
    exit 1
fi

# 设置环境变量
export POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
export POSTGRES_USER="${POSTGRES_USER:-app}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-app}"
export POSTGRES_DB="${POSTGRES_DB:-pvp}"
export EXCLUDE_SERVERS="${EXCLUDE_SERVERS:-9000}"

log_info "扫描数据文件..."
echo ""

# 统计文件
total_files=0
done_files=0
new_files=0
total_lines=0
valid_lines=0

while IFS= read -r -d '' file; do
    total_files=$((total_files + 1))
    marker="${file}.done"
    
    if [[ -f "$marker" ]]; then
        done_files=$((done_files + 1))
    else
        new_files=$((new_files + 1))
    fi
    
    # 检查文件内容
    line_count=$(wc -l < "$file" 2>/dev/null || echo "0")
    total_lines=$((total_lines + line_count))
    
    # 尝试解析第一行
    first_line=$(head -n 1 "$file" 2>/dev/null)
    if [[ -n "$first_line" ]]; then
        python3 << PYEOF
import json
import sys
import os

line = '''$first_line'''.strip()
if line:
    try:
        obj = json.loads(line)
        if isinstance(obj, dict):
            print("VALID")
            sys.exit(0)
    except:
        pass
print("INVALID")
sys.exit(1)
PYEOF
        if [[ $? -eq 0 ]]; then
            valid_lines=$((valid_lines + 1))
        fi
    fi
    
    echo "文件: $file"
    echo "  大小: $(du -h "$file" | cut -f1)"
    echo "  行数: $line_count"
    if [[ -f "$marker" ]]; then
        echo "  状态: ${GREEN}已导入${NC} (有 .done 标记)"
    else
        echo "  状态: ${YELLOW}待导入${NC}"
    fi
    echo ""
done < <(find "$IMPORT_DIR" -type f \( -name "*.jsonl" -o -name "*.txt" \) -print0)

log_info "==================== 统计信息 ===================="
log_info "总文件数: $total_files"
log_info "已导入: $done_files"
log_info "待导入: $new_files"
log_info "总行数: $total_lines"
echo ""

# 检查数据库连接
log_info "检查数据库连接..."
python3 << 'PYEOF'
import os
from sqlalchemy import text
from backend.app.database import SessionLocal

try:
    with SessionLocal() as db:
        result = db.execute(text("SELECT COUNT(*) FROM match_records;"))
        total = result.scalar()
        print(f"数据库当前记录数: {total}")
        
        # 检查最近的记录
        result = db.execute(text("SELECT MAX(timestamp) FROM match_records;"))
        max_ts = result.scalar()
        if max_ts:
            from datetime import datetime
            dt = datetime.fromtimestamp(max_ts)
            print(f"最新记录时间: {dt.strftime('%Y-%m-%d %H:%M:%S')}")
        else:
            print("数据库为空")
except Exception as e:
    print(f"数据库连接失败: {e}")
PYEOF

echo ""
log_info "=========================================="

