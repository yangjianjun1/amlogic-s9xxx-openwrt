#!/bin/bash
set -uo pipefail

CONFIG_FILE=".config"
SOURCE_CONFIG="config/lede_master/1.config"
ERROR_LOG="/tmp/make_error.log"
FIXED_FLAG="false"

echo "=========================================="
echo " OpenWrt .config Auto-Check & Fix Tool"
echo "=========================================="

# 复制配置
cp "$SOURCE_CONFIG" "$CONFIG_FILE"
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

echo ""
echo "==> [Step 1] Running make prepare-tmpinfo..."
make prepare-tmpinfo >/dev/null 2>"$ERROR_LOG"
MAKE_EXIT=$?

if [ $MAKE_EXIT -eq 0 ]; then
  echo "✅ .config syntax is valid!"
  rm -f "${CONFIG_FILE}.bak"
  echo "fixed=false" >> $GITHUB_OUTPUT 2>/dev/null || true
  exit 0
fi

echo "❌ Errors detected:"
cat "$ERROR_LOG"

# 提取报错行号
LINES_TO_FIX=$(grep -oP ':\d+:' "$ERROR_LOG" | grep -oP '\d+' | sort -n | uniq || true)

if [ -n "$LINES_TO_FIX" ]; then
  echo ""
  echo "==> [Step 2] Error lines content:"
  
  for line_num in $LINES_TO_FIX; do
    echo "--- Line $line_num (raw) ---"
    sed -n "${line_num}p" "$CONFIG_FILE" | cat -A
    echo ""
    
    # 修复：去掉行首所有空白
    sed -i "${line_num}s/^[ \t]*//" "$CONFIG_FILE"
    
    # 修复后检查语法
    NEW_LINE=$(sed -n "${line_num}p" "$CONFIG_FILE" || echo "")
    if ! echo "$NEW_LINE" | grep -qE '^(CONFIG_|# CONFIG_|#|$)'; then
      echo "  → Line $line_num has invalid syntax, commenting out..."
      sed -i "${line_num}s/^/# AUTO-FIXED-BAD-SYNTAX: /" "$CONFIG_FILE"
    else
      echo "  → Stripped leading whitespace from line $line_num"
    fi
    
    FIXED_FLAG="true"
  done
fi

# 重新验证
echo ""
echo "==> [Step 3] Re-checking..."
make prepare-tmpinfo >/dev/null 2>"$ERROR_LOG"
if [ $? -eq 0 ]; then
  echo "✅ Fixed successfully!"
  rm -f "${CONFIG_FILE}.bak"
  cp "$CONFIG_FILE" "$SOURCE_CONFIG"
  echo "fixed=true" >> $GITHUB_OUTPUT 2>/dev/null || true
  exit 0
fi

# 回退
echo "❌ Auto-fix failed. Restoring backup."
cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
cp "${CONFIG_FILE}" "$SOURCE_CONFIG"
echo "fixed=false" >> $GITHUB_OUTPUT 2>/dev/null || true
exit 1
