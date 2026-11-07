#!/bin/bash
set -euo pipefail

CONFIG_FILE=".config"
ERROR_LOG="/tmp/make_error.log"
FIXED_FLAG="false"

echo "=========================================="
echo " OpenWrt .config Auto-Check & Fix Tool"
echo "=========================================="

# 1. 检查文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
  echo "::error::$CONFIG_FILE not found! Please provide a .config file."
  exit 1
fi

# 2. 备份
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

echo ""
echo "==> [Step 1] Running 'make prepare-tmpinfo' to detect errors..."
if make prepare-tmpinfo >/dev/null 2>"$ERROR_LOG"; then
  echo "✅ .config syntax is OK! No errors found."
  rm -f "${CONFIG_FILE}.bak"
  echo "fixed=false" >> $GITHUB_OUTPUT 2>/dev/null || true
  exit 0
else
  echo "❌ Errors detected in .config:"
  cat "$ERROR_LOG"
fi

# 3. 提取报错行号（匹配 "filename:line:" 格式）
LINES_TO_FIX=$(grep -oP ':\d+:' "$ERROR_LOG" | grep -oP '\d+' | sort -n | uniq || true)

if [ -z "$LINES_TO_FIX" ]; then
  echo "::warning::Could not auto-extract line numbers from error log."
else
  echo ""
  echo "==> [Step 2] Attempting to fix lines: $LINES_TO_FIX"

  for line_num in $LINES_TO_FIX; do
    echo "--- Processing line $line_num ---"
    ORIGINAL=$(sed -n "${line_num}p" "$CONFIG_FILE" || echo "")
    echo "Original: '$ORIGINAL'"

    # 修复策略 1：去掉行首所有空格/Tab（.config 里有效行应该顶格）
    sed -i "${line_num}s/^[ \t]*//" "$CONFIG_FILE"

    # 修复策略 2：如果行不是合法的 Kconfig 格式，注释掉并标记
    NEW_LINE=$(sed -n "${line_num}p" "$CONFIG_FILE" || echo "")
    if ! echo "$NEW_LINE" | grep -qE '^(CONFIG_|# CONFIG_|#|$)'; then
      echo "Line $line_num is not valid Kconfig syntax, commenting out..."
      sed -i "${line_num}s/^/# AUTO-FIXED-BAD-SYNTAX: /" "$CONFIG_FILE"
    fi

    FIXED_FLAG="true"
    echo "Fixed line $line_num: '$NEW_LINE'"
  done
fi

# 4. 重新检查
echo ""
echo "==> [Step 3] Re-checking after fix..."
if make prepare-tmpinfo >/dev/null 2>"$ERROR_LOG"; then
  echo "✅ .config fixed successfully!"
  rm -f "${CONFIG_FILE}.bak"
  echo "fixed=true" >> $GITHUB_OUTPUT 2>/dev/null || true
  exit 0
else
  echo "❌ Auto-fix failed. Resetting to defconfig..."
  cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
  
  echo "==> [Step 4] Falling back to 'make defconfig'..."
  make defconfig
  
  if make prepare-tmpinfo >/dev/null 2>&1; then
    echo "✅ Reset to defconfig successfully (valid but default config)."
    echo "::warning::Original .config was broken beyond repair. Reset to default config."
    echo "fixed=true" >> $GITHUB_OUTPUT 2>/dev/null || true
    exit 0
  else
    echo "::error::Even defconfig failed! Check your OpenWrt source tree."
    exit 2
  fi
fi
