#!/bin/bash
# AI新闻GitHub Actions脚本
# 直接调用OpenClaw API获取并发送AI新闻

set -e  # 出错时退出

API_URL="https://openclaw-min.fly.dev/tools/invoke"
API_TOKEN="ca60adddfd3d65d2cc124c1f0576ead8e5268b6aa8b02089e7c0c78dcc998c58"
TELEGRAM_CHAT_ID="8604429591"

echo "🚀 开始获取AI新闻..."

# 1. 获取AI新闻
echo "搜索AI新闻..."
NEWS_RESPONSE=$(curl -s -X POST "$API_URL" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "tool": "web_search",
    "args": {
      "query": "最新AI新闻 人工智能 发展 突破 研究 2026年",
      "count": 5
    }
  }')

# 检查API响应
if echo "$NEWS_RESPONSE" | grep -q '"ok":false'; then
    echo "❌ 获取新闻失败"
    echo "响应: $NEWS_RESPONSE"
    exit 1
fi

echo "✅ 新闻获取成功"

# 2. 提取并格式化新闻内容
echo "格式化新闻内容..."

# 使用jq解析JSON（如果可用）
if command -v jq &> /dev/null; then
    # 提取content字段
    NEWS_CONTENT=$(echo "$NEWS_RESPONSE" | jq -r '.result.content[0].text' 2>/dev/null || echo "")
    
    if [ -n "$NEWS_CONTENT" ]; then
        # 尝试从嵌套JSON中提取内容
        ACTUAL_CONTENT=$(echo "$NEWS_CONTENT" | jq -r '.content' 2>/dev/null || echo "$NEWS_CONTENT")
    else
        ACTUAL_CONTENT="无法解析新闻内容"
    fi
else
    # 简单文本提取（备用方案）
    ACTUAL_CONTENT=$(echo "$NEWS_RESPONSE" | \
        grep -o '"content":"[^"]*"' | \
        head -1 | \
        sed 's/"content":"//' | \
        sed 's/"$//' | \
        sed 's/\\n/\n/g')
fi

# 清理内容（移除EXTERNAL_UNTRUSTED_CONTENT标记）
CLEANED_CONTENT=$(echo "$ACTUAL_CONTENT" | \
    sed 's/<<<EXTERNAL_UNTRUSTED_CONTENT[^>]*>>>//g' | \
    sed 's/<<<END_EXTERNAL_UNTRUSTED_CONTENT[^>]*>>>//g' | \
    sed 's/Source: Web Search//g' | \
    sed 's/---//g' | \
    sed 's/^[[:space:]]*//' | \
    sed '/^$/d')

# 限制长度（Telegram限制约4096字符）
MAX_LENGTH=3500
if [ ${#CLEANED_CONTENT} -gt $MAX_LENGTH ]; then
    CLEANED_CONTENT="${CLEANED_CONTENT:0:$MAX_LENGTH}..."
fi

# 添加标题
FINAL_MESSAGE="📰 今日AI新闻摘要 ($(date '+%Y-%m-%d'))\n\n${CLEANED_CONTENT}\n\n来源：OpenClaw AI新闻服务"

echo "新闻内容已格式化，长度: ${#FINAL_MESSAGE} 字符"

# 3. 发送到Telegram
echo "发送到Telegram..."
MESSAGE_RESPONSE=$(curl -s -X POST "$API_URL" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "tool": "message",
    "args": {
      "action": "send",
      "to": "'"$TELEGRAM_CHAT_ID"'",
      "message": "'"$(echo "$FINAL_MESSAGE" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')"'",
      "channel": "telegram"
    }
  }')

# 检查发送结果
if echo "$MESSAGE_RESPONSE" | grep -q '"ok":true'; then
    echo "✅ AI新闻已成功发送到Telegram"
    MESSAGE_ID=$(echo "$MESSAGE_RESPONSE" | grep -o '"messageId":"[^"]*"' | head -1 | sed 's/"messageId":"//' | sed 's/"$//')
    echo "消息ID: $MESSAGE_ID"
else
    echo "❌ 发送到Telegram失败"
    echo "响应: $MESSAGE_RESPONSE"
    
    # 尝试发送简化版本
    echo "尝试发送简化版本..."
    SIMPLE_MESSAGE="📰 今日AI新闻摘要 ($(date '+%Y-%m-%d'))\n\nAI新闻已获取，但格式化时遇到问题。请查看OpenClaw日志获取详细信息。"
    
    curl -X POST "$API_URL" \
      -H "Authorization: Bearer $API_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{
        "tool": "message",
        "args": {
          "action": "send",
          "to": "'"$TELEGRAM_CHAT_ID"'",
          "message": "'"$(echo "$SIMPLE_MESSAGE" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')"'",
          "channel": "telegram"
        }
      }'
    
    exit 1
fi
