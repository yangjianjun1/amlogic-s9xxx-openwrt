#!/bin/bash
set -e

CONFIG_FILE=".config"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "::error::$CONFIG_FILE not found!"
  exit 1
fi

echo "=== Step 1: Checking .config for syntax errors ==="
# 使用 make 检查，只做 prepare-tmpinfo，不编译
if make prepare-tmpinfo 2> /tmp/make_error.log; then
  echo "✅ .config has no syntax errors!"
  exit 0
else
  echo "❌ .config has errors. Attempting to fix..."
  cat /tmp/make_error.log
fi

# 提取错误行号
LINES_TO_FIX=$(grep -oP ':\d+:' /tmp/make_error.log | grep -oP '\d+' | sort -n | uniq)

if [ -z "$LINES_TO_FIX" ]; then
  echo "::warning::Could not extract line numbers from error log."
else
  echo "=== Step 2: Fixing lines: $LINES_TO_FIX ==="
  # 备份
  cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
  
  # 尝试修复：将行首的空格替换为 Tab（针对 Makefile 规则），或者删除明显错误的行
  # 对于 .config，通常不应该有 Makefile 目标。如果是被 source/include 的，变量赋值不能有多余空格。
  # 这里采用保守修复：删除空行和只包含空格的行，以及修复行首空格。
  for line_num in $LINES_TO_FIX; do
    echo "Fixing line $line_num..."
    # 查看该行内容
    sed -n "${line_num}p" "$CONFIG_FILE"
    # 如果是注释行但有多余缩进，去掉缩进
    sed -i "${line_num}s/^[ \t]*//" "$CONFIG_FILE"
    # 如果修复后还是不对，直接注释掉或删除（这里选择注释掉，保留信息）
    # 但更好的方法是：如果这一行不是有效的 CONFIG_ 或 # CONFIG_，就删除
    LINE_CONTENT=$(sed -n "${line_num}p" "$CONFIG_FILE")
    if ! echo "$LINE_CONTENT" | grep -qE '^(CONFIG_|# CONFIG_|$)'; then
      echo "Line $line_num is not a valid config line, commenting out:"
      sed -i "${line_num}s/^/# AUTO-FIXED: /" "$CONFIG_FILE"
    fi
  done
fi

echo "=== Step 3: Re-checking after fix ==="
if make prepare-tmpinfo 2> /tmp/make_error2.log; then
  echo "✅ .config fixed successfully!"
  rm -f "${CONFIG_FILE}.bak"
else
  echo "❌ Auto-fix failed. Resetting to defconfig..."
  cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
  make defconfig
  echo "::warning::Reset to defconfig. Please reconfigure manually."
fi
