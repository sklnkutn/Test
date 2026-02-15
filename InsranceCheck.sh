#!/usr/bin/env bash

# ==================== НАСТРОЙКИ ====================
CONFIG_FILE="./config.txt"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Создай файл $CONFIG_FILE с переменными, каждая на новой строке:"
    echo "MAX_PRICE=0.1"
    echo "BOT_TOKEN=123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
    echo "CHAT_ID=123456789"
    echo "CHECK_INTERVAL=300"
    echo "type=on-demand"
    echo "disk_space>=30"
    echo "cuda_max_good>=12.9"
    echo "inet_up_cost<=0.5"
    echo "inet_down_cost<=0.5"
    echo "num_gpus=1"
    echo "gpu_ram>20000"
    echo "inet_up>=100"
    echo "inet_down>=100"
    echo "verified=true"
    exit 1
fi

TEMPLATE_HASH=""  # по умолчанию пусто
while IFS= read -r line; do
    ...
    if [[ $$   line =~ ^TEMPLATE_HASH=(.+)   $$ ]]; then
        TEMPLATE_HASH="${BASH_REMATCH[1]}"
    fi
done < "$CONFIG_FILE"

# ==================== ФУНКЦИЯ отправки в Telegram ====================
send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="${message}" \
        -d parse_mode="Markdown" > /dev/null
}

# ==================== ОСНОВНАЯ ЛОГИКА ====================

while true; do
    # Перечитываем config каждый цикл (чтобы можно было редактировать на лету)
    unset MAX_PRICE BOT_TOKEN CHAT_ID CHECK_INTERVAL
    SEARCH_QUERY=""
    while IFS= read -r line; do
        line="${line//[$'\t\r\n']}"  # Убрать лишние пробелы/переносы
        if [[ -z "$line" || "$line" == "#"* ]]; then continue; fi  # Пропуск пустых/комментов
        if [[ $line =~ ^([A-Za-z_]+)=(.+)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            case "$key" in
                MAX_PRICE|BOT_TOKEN|CHAT_ID|CHECK_INTERVAL) export "$key=$value" ;;
            esac
        else
            SEARCH_QUERY+="$line "
        fi
    done < "$CONFIG_FILE"

    # Обрезаем trailing space в SEARCH_QUERY
    SEARCH_QUERY="${SEARCH_QUERY%" "}"

    # Добавляем dph_total<=$MAX_PRICE в QUERY (если MAX_PRICE задан)
    if [[ -n "$MAX_PRICE" ]]; then
        SEARCH_QUERY+=" dph_total<=$MAX_PRICE"
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SEARCH_QUERY: $SEARCH_QUERY"

    # Получаем топ-3 самых дешёвых подходящих предложения (json)
    OFFERS=$(vastai search offers "${SEARCH_QUERY}" --order price+ --raw --type on-demand --max 3 2>/dev/null)

    echo "Результат поиска: $OFFERS"

    if [[ -z "$OFFERS" || "$OFFERS" == "[]" ]]; then
        echo "Нет подходящих предложений"
    else
    # Нашли >=1 — отправляем в TG детали топ-1
    MACHINE_ID=$(echo "$OFFERS" | jq -r '.[0].id // "?"')
    PRICE=$(echo "$OFFERS" | jq -r '.[0].dph_total // "?"')
    RELIABILITY=$(echo "$OFFERS" | jq -r '.[0].reliability2 // .[0].reliability // "?"')
    VRAM=$(echo "$OFFERS" | jq -r '.[0].gpu_ram / 1024 // "?"')  # в GB
    CUDA=$(echo "$OFFERS" | jq -r '.[0].cuda_max_good // "?"')
    DISK=$(echo "$OFFERS" | jq -r '.[0].disk_space // "?"')
    INET_UP=$(echo "$OFFERS" | jq -r '.[0].inet_up // "?"')
    INET_DOWN=$(echo "$OFFERS" | jq -r '.[0].inet_down // "?"')
    HOST=$(echo "$OFFERS" | jq -r '.[0].geolocation // "unknown"')

    # Формируем команду запуска
    LAUNCH_CMD="vastai create instance ${MACHINE_ID} --disk 40 --image vastai/pytorch"  # дефолт, если нет кастомного шаблона

    if [[ -n "$TEMPLATE_HASH" ]]; then
        LAUNCH_CMD="vastai create instance ${MACHINE_ID} --template_hash ${TEMPLATE_HASH} --disk 40"
        # Если в твоём шаблоне уже задан нужный --image, --disk и другие параметры — их можно опустить,
        # но --disk часто лучше указывать явно, чтобы переопределить дефолт шаблона
    fi

    MSG="🚨 Нашлись предложения на Vast.ai! (Топ-1)\n\n"
    MSG+="Цена: \$${PRICE}/час\n"
    MSG+="ID: ${MACHINE_ID}\n"
    MSG+="Reliability: ${RELIABILITY}\n"
    MSG+="VRAM: ${VRAM} GB\n"
    MSG+="CUDA: ${CUDA}\n"
    MSG+="Disk: ${DISK} GB\n"
    MSG+="Inet Up/Down: ${INET_UP}/${INET_DOWN} Mbps\n"
    MSG+="Локация: ${HOST}\n\n"
    MSG+="Запуск:\n${LAUNCH_CMD}\n"
    MSG+="Смотри: https://console.vast.ai/"

    send_telegram "$MSG"
    echo "Уведомление отправлено!"
fi

# Ожидание перед следующим циклом
sleep "${CHECK_INTERVAL:-60}"  # Дефолт 1 мин, если не задан
done