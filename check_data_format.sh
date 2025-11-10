#!/bin/bash

# ============================================
# 数据文件格式诊断工具
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

FILE_PATH="${1:-./data_logs/gold_league/2025_11_10.txt}"

if [[ ! -f "$FILE_PATH" ]]; then
    log_error "文件不存在: $FILE_PATH"
    exit 1
fi

echo ""
log_info "=========================================="
log_info "  数据文件格式诊断"
log_info "=========================================="
echo ""
log_info "文件: $FILE_PATH"
log_info "大小: $(du -h "$FILE_PATH" | cut -f1)"
log_info "行数: $(wc -l < "$FILE_PATH")"
echo ""

# 激活虚拟环境
if [[ -f ".venv/bin/activate" ]]; then
    source .venv/bin/activate
fi

# 诊断文件内容
python3 << 'PYEOF'
import json
import re
import sys
import os

# 使用与导入逻辑相同的解析方法
_ST_FIX_RE = re.compile(r'("source_type"\s*:\s*)(gold_league|season_play_pvp_mgr)\b')

def _robust_json_load(line: str):
    """Try strict JSON first; if failed, fix known patterns then retry."""
    try:
        return json.loads(line)
    except Exception:
        pass
    # Fix unquoted source_type tokens
    fixed = _ST_FIX_RE.sub(lambda m: f"{m.group(1)}\"{m.group(2)}\"", line)
    if fixed != line:
        try:
            return json.loads(fixed)
        except Exception:
            return None
    return None

file_path = '''$FILE_PATH'''

print("=" * 50)
print("前 5 行内容预览:")
print("=" * 50)

try:
    with open(file_path, 'r', encoding='utf-8') as f:
        line_num = 0
        valid_count = 0
        invalid_count = 0
        
        for line in f:
            line_num += 1
            original_line = line.rstrip()
            
            if line_num <= 5:
                print(f"\n行 {line_num}:")
                print(f"  原始: {original_line[:100]}..." if len(original_line) > 100 else f"  原始: {original_line}")
            
            line = line.strip()
            if not line:
                if line_num <= 5:
                    print("  状态: 空行（跳过）")
                continue
            
            # 尝试解析
            obj = _robust_json_load(line)
            
            if obj and isinstance(obj, dict):
                # 检查必需字段
                has_server = 'server' in obj
                has_timestamp = 'timestamp' in obj
                
                if has_server and has_timestamp:
                    valid_count += 1
                    if line_num <= 5:
                        print(f"  状态: ✓ 有效")
                        print(f"  字段: server={obj.get('server')}, timestamp={obj.get('timestamp')}, source_type={obj.get('source_type', 'N/A')}")
                else:
                    invalid_count += 1
                    missing = []
                    if not has_server:
                        missing.append('server')
                    if not has_timestamp:
                        missing.append('timestamp')
                    if line_num <= 5:
                        print(f"  状态: ✗ 缺少必需字段: {', '.join(missing)}")
            else:
                invalid_count += 1
                if line_num <= 5:
                    print(f"  状态: ✗ JSON 解析失败")
                    # 尝试显示错误信息
                    try:
                        json.loads(line)
                    except json.JSONDecodeError as e:
                        print(f"  错误: {str(e)[:80]}")
            
            if line_num >= 100:  # 只检查前100行
                break
        
        print("\n" + "=" * 50)
        print("统计信息:")
        print("=" * 50)
        print(f"总行数（前100行）: {line_num}")
        print(f"有效记录: {valid_count}")
        print(f"无效记录: {invalid_count}")
        
        if valid_count == 0:
            print("\n❌ 没有找到有效记录！")
            print("\n可能的原因:")
            print("1. 文件格式不是 JSONL（每行一个 JSON 对象）")
            print("2. JSON 格式错误（缺少引号、括号不匹配等）")
            print("3. 缺少必需字段（server, timestamp）")
            print("\n提示: 代码会自动修复未加引号的 source_type 字段")
            sys.exit(1)
        elif invalid_count > 0:
            print(f"\n⚠️  有 {invalid_count} 条无效记录将被跳过")
        else:
            print("\n✓ 所有记录格式正确")
            
except Exception as e:
    print(f"\n❌ 读取文件失败: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYEOF

