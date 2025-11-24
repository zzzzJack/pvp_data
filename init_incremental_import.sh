#!/bin/bash

# ============================================
# 初始化增量导入位置文件
# 用于在数据库已有历史数据时，标记文件已完全导入
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
log_info "  初始化增量导入位置文件"
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

log_info "数据目录: $IMPORT_DIR"
echo ""

log_warning "此脚本将标记所有日志文件为'已完全导入'状态"
log_warning "适用于：数据库已有历史数据，且这些数据已完整导入的情况"
echo ""

read -p "确认继续？(y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "已取消"
    exit 0
fi

# 初始化位置文件
log_info "正在初始化位置文件..."
python3 << 'PYEOF'
import os
import json
import hashlib
from pathlib import Path

IMPORT_DIR = os.environ.get('IMPORT_DIR', 'data_logs')
POSITION_FILE = os.path.join(IMPORT_DIR, ".import_positions.json")

def _get_file_key(file_path: str) -> str:
    """生成文件的唯一标识（使用绝对路径的哈希）"""
    abs_path = os.path.abspath(file_path)
    return hashlib.md5(abs_path.encode('utf-8')).hexdigest()

def _count_file_lines(file_path: str) -> int:
    """统计文件总行数"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return sum(1 for _ in f)
    except Exception:
        return 0

positions = {}
file_count = 0

# 遍历所有日志文件
for root, _, files in os.walk(IMPORT_DIR):
    for f in files:
        if not (f.endswith('.jsonl') or f.endswith('.txt')):
            continue
        
        src = os.path.join(root, f)
        file_key = _get_file_key(src)
        total_lines = _count_file_lines(src)
        
        if total_lines > 0:
            positions[file_key] = total_lines
            print(f"  标记文件: {src} (共 {total_lines} 行)")
            file_count += 1

# 保存位置文件
try:
    with open(POSITION_FILE, 'w', encoding='utf-8') as f:
        json.dump(positions, f, indent=2, ensure_ascii=False)
    print(f"\n成功初始化 {file_count} 个文件的位置记录")
    print(f"位置文件已保存到: {POSITION_FILE}")
except Exception as e:
    print(f"\n错误: 保存位置文件失败: {e}")
    import sys
    sys.exit(1)
PYEOF

if [[ $? -eq 0 ]]; then
    log_success "初始化完成！"
    echo ""
    log_info "现在可以使用 ./incremental_import.sh 进行增量导入了"
    log_info "脚本将只导入文件的新增内容"
else
    log_error "初始化失败"
    exit 1
fi

