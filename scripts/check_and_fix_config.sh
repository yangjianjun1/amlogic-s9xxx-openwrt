#!/bin/bash
set -euo pipefail

# 配置文件路径（OpenWrt 编译只认根目录 .config）
CONFIG_FILE=".config"
SOURCE_CONFIG="config/lede_master/1.config"
ERROR_LOG="/tmp/make_error.log"
FIXED_FLAG="false"

echo "=========================================="
echo " OpenWrt .config Auto-Check & Fix Tool"
echo " Source: $SOURCE_CONFIG"
echo "=========================================="

# 1. 检查源文件是否存在
if [ ! -f "$SOURCE_CONFIG" ]; then
  echo "::error::$SOURCE_CONFIG not found!"
  exit 1
fi

# 2. 复制到根目录（make 只认 .config）
cp "$SOURCE_CONFIG" "$CONFIG_FILE"

# 3. 备份
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

echo ""
echo "==> [Step 1] Running 'make prepare-tmpinfo' to detect errors..."
if make prepare-tmpinfo >/dev/null 2>"$ERROR_LOG"; then
  echo "✅ .config syntax is OK! No errors found."
  rm -f "${CONFIG_FILE}.bak"
  # 同步回源路径
  cp "$CONFIG_FILE" "$SOURCE_CONFIG"
  echo "fixed=false" >> $GITHUB_OUTPUT 2>/dev/null || true
  exit 0
else
  echo "❌ Errors detected:"
  cat "$ERROR_LOG"
fi

# 4. 提取报错行号
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

    # 修复策略 1：去掉行首所有空格/Tab
    sed -i "${line_num}s/^[ \t]*//" "$CONFIG_FILE"

    # 修复策略 2：非法 Kconfig 语法 → 注释掉
    NEW_LINE=$(sed -n "${line_num}p" "$CONFIG_FILE" || echo "")
    if ! echo "$NEW_LINE" | grep -qE '^(CONFIG_|# CONFIG_|#|$)'; then
      echo "Line $line_num is not valid Kconfig syntax, commenting out..."
      sed -i "${line_num}s/^/# AUTO-FIXED-BAD-SYNTAX: /" "$CONFIG_FILE"
    fi

    FIXED_FLAG="true"
    echo "Fixed line $line_num"
  done
fi

# 5. 重新检查
echo ""
echo "==> [Step 3] Re-checking after fix..."
if make prepare-tmpinfo >/dev/null 2>"$ERROR_LOG"; then
  echo "✅ .config fixed successfully!"
  rm -f "${CONFIG_FILE}.bak"
  # 同步回源路径
  cp "$CONFIG_FILE" "$SOURCE_CONFIG"
  echo "fixed=true" >> $GITHUB_OUTPUT 2>/dev/null || true
  exit 0
else
  echo "❌ Auto-fix failed. Resetting to defconfig..."
  cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"

  echo "==> [Step 4] Falling back to 'make defconfig'..."
  make defconfig

  if make prepare-tmpinfo >/dev/null 2>&1; then
    echo "✅ Reset to defconfig successfully."
    cp "$CONFIG_FILE" "$SOURCE_CONFIG"
    echo "::warning::Original config was broken. Reset to default."
    echo "fixed=true" >> $GITHUB_OUTPUT 2>/dev/null || true
    exit 0
  else
    echo "::error::Even defconfig failed!"
    exit 2
  fi
fi
