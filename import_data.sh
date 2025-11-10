#!/bin/bash

# ============================================
# 数据导入脚本
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

# 默认配置
IMPORT_DIR="${IMPORT_DIR:-./data_logs}"
EXCLUDE_SERVERS="${EXCLUDE_SERVERS:-9000}"

echo ""
log_info "=========================================="
log_info "  数据导入工具"
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
    log_info "请确保数据文件在 $IMPORT_DIR 目录下"
    exit 1
fi

# 统计数据文件
log_info "扫描数据文件..."
jsonl_files=$(find "$IMPORT_DIR" -type f \( -name "*.jsonl" -o -name "*.txt" \) 2>/dev/null | wc -l)
done_files=$(find "$IMPORT_DIR" -type f -name "*.done" 2>/dev/null | wc -l)
new_files=$((jsonl_files - done_files))

log_info "数据目录: $IMPORT_DIR"
log_info "JSONL 文件总数: $jsonl_files"
log_info "已导入文件数: $done_files"
log_info "待导入文件数: $new_files"

if [[ $new_files -eq 0 ]] && [[ $jsonl_files -gt 0 ]]; then
    log_warning "所有文件都已导入"
    
    # 检查数据库是否有数据
    log_info "检查数据库记录数..."
    db_count=$(python3 << 'PYEOF'
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
        print(total)
except Exception as e:
    print("0")
PYEOF
)
    
    if [[ "$db_count" == "0" ]]; then
        log_warning "数据库中没有记录，但文件已标记为已导入"
        log_info "可能是之前的导入失败，建议重新导入"
        read -p "是否删除 .done 标记并重新导入? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "删除 .done 标记文件..."
            find "$IMPORT_DIR" -type f -name "*.done" -delete 2>/dev/null || true
            log_success "已清除导入标记，将重新导入所有数据"
            new_files=$jsonl_files
        else
            log_info "取消导入"
            exit 0
        fi
    else
        log_info "数据库已有 $db_count 条记录"
        read -p "是否重新导入所有数据（删除 .done 标记）? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "删除 .done 标记文件..."
            find "$IMPORT_DIR" -type f -name "*.done" -delete 2>/dev/null || true
            log_success "已清除导入标记，将重新导入所有数据"
            new_files=$jsonl_files
        else
            log_info "取消导入"
            exit 0
        fi
    fi
fi

if [[ $jsonl_files -eq 0 ]]; then
    log_error "未找到数据文件（.jsonl 或 .txt）"
    log_info "请将数据文件放入 $IMPORT_DIR 目录"
    exit 1
fi

echo ""
log_info "==================== 导入选项 ===================="
log_info "1. 自动导入（跳过已导入的文件，推荐）"
log_info "2. 强制重新导入所有文件"
log_info "3. 指定目录导入"
echo ""
read -p "请选择导入方式 (1/2/3): " -n 1 -r
echo ""

case $REPLY in
    1)
        log_info "使用自动导入模式（跳过已导入的文件）..."
        
        # 先测试解析一个文件，检查数据格式
        log_info "检查数据文件格式..."
        test_file=$(find "$IMPORT_DIR" -type f \( -name "*.jsonl" -o -name "*.txt" \) ! -name "*.done" | head -n 1)
        if [[ -n "$test_file" ]]; then
            test_result=$(python3 << PYEOF
import json
import sys

test_file = '''$test_file'''
try:
    with open(test_file, 'r', encoding='utf-8') as f:
        line_count = 0
        valid_count = 0
        for line in f:
            line = line.strip()
            if not line:
                continue
            line_count += 1
            try:
                obj = json.loads(line)
                if isinstance(obj, dict) and 'server' in obj and 'timestamp' in obj:
                    valid_count += 1
            except:
                pass
            if line_count >= 10:  # 只检查前10行
                break
        if line_count == 0:
            print("EMPTY")
        elif valid_count == 0:
            print("INVALID")
        else:
            print(f"OK:{valid_count}/{line_count}")
except Exception as e:
    print(f"ERROR:{e}")
PYEOF
)
            if [[ "$test_result" == "EMPTY" ]]; then
                log_error "数据文件为空: $test_file"
                exit 1
            elif [[ "$test_result" == "INVALID" ]]; then
                log_error "数据文件格式无效: $test_file"
                log_info "请检查文件是否为有效的 JSONL 格式（每行一个 JSON 对象）"
                exit 1
            elif [[ "$test_result" =~ ^ERROR: ]]; then
                log_error "读取文件失败: ${test_result#ERROR:}"
                exit 1
            else
                log_success "数据文件格式检查通过: ${test_result#OK:}"
            fi
        fi
        
        log_info "设置环境变量..."
        export IMPORT_DIR="$IMPORT_DIR"
        export EXCLUDE_SERVERS="$EXCLUDE_SERVERS"
        export POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
        export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
        export POSTGRES_USER="${POSTGRES_USER:-app}"
        export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-app}"
        export POSTGRES_DB="${POSTGRES_DB:-pvp}"
        
        log_info "开始导入数据..."
        python3 << 'PYEOF'
import os
import sys
from backend.app.auto_importer import run_import_once

logs_dir = os.environ.get('IMPORT_DIR', 'data_logs')
count = run_import_once(logs_dir)
print(f"\n导入完成！共导入 {count} 条记录")
if count == 0:
    print("\n提示: 如果文件已存在 .done 标记，将被跳过")
    print("      如需重新导入，请选择选项 2 或先删除 .done 标记文件")
sys.exit(0 if count >= 0 else 1)
PYEOF
        
        if [[ $? -eq 0 ]]; then
            log_success "数据导入成功"
        else
            log_error "数据导入失败"
            exit 1
        fi
        ;;
    2)
        log_warning "强制重新导入所有文件（将删除 .done 标记）..."
        read -p "确认继续? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "取消导入"
            exit 0
        fi
        
        log_info "删除所有 .done 标记文件..."
        find "$IMPORT_DIR" -type f -name "*.done" -delete 2>/dev/null || true
        
        log_info "开始导入数据..."
        export IMPORT_DIR="$IMPORT_DIR"
        export EXCLUDE_SERVERS="$EXCLUDE_SERVERS"
        export POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
        export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
        export POSTGRES_USER="${POSTGRES_USER:-app}"
        export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-app}"
        export POSTGRES_DB="${POSTGRES_DB:-pvp}"
        
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
        else
            log_error "数据导入失败"
            exit 1
        fi
        ;;
    3)
        read -p "请输入数据目录路径: " custom_dir
        if [[ ! -d "$custom_dir" ]]; then
            log_error "目录不存在: $custom_dir"
            exit 1
        fi
        IMPORT_DIR="$custom_dir"
        log_info "使用自定义目录: $IMPORT_DIR"
        
        export IMPORT_DIR="$IMPORT_DIR"
        export EXCLUDE_SERVERS="$EXCLUDE_SERVERS"
        export POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
        export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
        export POSTGRES_USER="${POSTGRES_USER:-app}"
        export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-app}"
        export POSTGRES_DB="${POSTGRES_DB:-pvp}"
        
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
        else
            log_error "数据导入失败"
            exit 1
        fi
        ;;
    *)
        log_error "无效的选择"
        exit 1
        ;;
esac

echo ""
log_info "==================== 导入统计 ===================="

# 查询数据库中的记录数
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
except Exception as e:
    print(f"查询失败: {e}")
PYEOF

echo ""
log_info "=========================================="
log_success "导入完成！"

