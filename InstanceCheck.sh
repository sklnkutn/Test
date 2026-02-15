#!/usr/bin/env bash

set -u

CONFIG_FILE="./config.txt"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Создай файл $CONFIG_FILE с переменными, каждая на новой строке."
    exit 1
fi

for cmd in vastai jq curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Ошибка: не найдена команда '$cmd'. Установи её и повтори запуск." >&2
        exit 1
    fi
done

# Значения по умолчанию
DEFAULT_CHECK_INTERVAL="300"
DEFAULT_SEARCH_TYPE="on-demand"
DEFAULT_MAX_RESULTS="3"
DEFAULT_DISK_GB="40"
DEFAULT_IMAGE_NAME="vastai/pytorch"
DEFAULT_TG_PARSE_MODE="Markdown"
DEFAULT_LOG_FILE="./logs/instance_check.log"
DEFAULT_LOG_TAG="vastai-monitor"
DEFAULT_DEDUP_CYCLES="5"
DEFAULT_DEDUP_STATE_FILE="./state/dedup_state.txt"

MAX_PRICE=""
BOT_TOKEN=""
CHAT_ID=""
CHECK_INTERVAL="$DEFAULT_CHECK_INTERVAL"
TEMPLATE_HASH=""
SEARCH_TYPE="$DEFAULT_SEARCH_TYPE"
MAX_RESULTS="$DEFAULT_MAX_RESULTS"
DISK_GB="$DEFAULT_DISK_GB"
IMAGE_NAME="$DEFAULT_IMAGE_NAME"
TG_PARSE_MODE="$DEFAULT_TG_PARSE_MODE"
LOG_FILE="$DEFAULT_LOG_FILE"
LOG_TAG="$DEFAULT_LOG_TAG"
DEDUP_CYCLES="$DEFAULT_DEDUP_CYCLES"
DEDUP_STATE_FILE="$DEFAULT_DEDUP_STATE_FILE"
SEARCH_FILTERS=()

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

log_message() {
    local msg="$1"
    local ts
    ts="$(date '+%F %T')"

    echo "[$ts] $msg"

    if [[ -n "$LOG_FILE" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        printf '[%s] %s\n' "$ts" "$msg" >>"$LOG_FILE"
    fi

    if command -v logger >/dev/null 2>&1; then
        logger -t "$LOG_TAG" -- "$msg"
    fi
}

is_non_negative_int() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

load_config() {
    MAX_PRICE=""
    BOT_TOKEN=""
    CHAT_ID=""
    CHECK_INTERVAL="$DEFAULT_CHECK_INTERVAL"
    TEMPLATE_HASH=""
    SEARCH_TYPE="$DEFAULT_SEARCH_TYPE"
    MAX_RESULTS="$DEFAULT_MAX_RESULTS"
    DISK_GB="$DEFAULT_DISK_GB"
    IMAGE_NAME="$DEFAULT_IMAGE_NAME"
    TG_PARSE_MODE="$DEFAULT_TG_PARSE_MODE"
    LOG_FILE="$DEFAULT_LOG_FILE"
    LOG_TAG="$DEFAULT_LOG_TAG"
    DEDUP_CYCLES="$DEFAULT_DEDUP_CYCLES"
    DEDUP_STATE_FILE="$DEFAULT_DEDUP_STATE_FILE"
    SEARCH_FILTERS=()

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        local line
        line="$(trim "${raw_line%%#*}")"

        [[ -z "$line" ]] && continue

        case "$line" in
            MAX_PRICE=*) MAX_PRICE="${line#MAX_PRICE=}" ;;
            BOT_TOKEN=*) BOT_TOKEN="${line#BOT_TOKEN=}" ;;
            CHAT_ID=*) CHAT_ID="${line#CHAT_ID=}" ;;
            CHECK_INTERVAL=*) CHECK_INTERVAL="${line#CHECK_INTERVAL=}" ;;
            TEMPLATE_HASH=*) TEMPLATE_HASH="${line#TEMPLATE_HASH=}" ;;
            SEARCH_TYPE=*) SEARCH_TYPE="${line#SEARCH_TYPE=}" ;;
            MAX_RESULTS=*) MAX_RESULTS="${line#MAX_RESULTS=}" ;;
            DISK_GB=*) DISK_GB="${line#DISK_GB=}" ;;
            IMAGE_NAME=*) IMAGE_NAME="${line#IMAGE_NAME=}" ;;
            TG_PARSE_MODE=*) TG_PARSE_MODE="${line#TG_PARSE_MODE=}" ;;
            LOG_FILE=*) LOG_FILE="${line#LOG_FILE=}" ;;
            LOG_TAG=*) LOG_TAG="${line#LOG_TAG=}" ;;
            DEDUP_CYCLES=*) DEDUP_CYCLES="${line#DEDUP_CYCLES=}" ;;
            DEDUP_STATE_FILE=*) DEDUP_STATE_FILE="${line#DEDUP_STATE_FILE=}" ;;
            *) SEARCH_FILTERS+=("$line") ;;
        esac
    done < "$CONFIG_FILE"

    if [[ -n "$MAX_PRICE" ]]; then
        SEARCH_FILTERS+=("dph_total<=$MAX_PRICE")
    fi

    if ! is_non_negative_int "$DEDUP_CYCLES"; then
        log_message "DEDUP_CYCLES='$DEDUP_CYCLES' некорректен. Использую default $DEFAULT_DEDUP_CYCLES."
        DEDUP_CYCLES="$DEFAULT_DEDUP_CYCLES"
    fi

    mkdir -p "$(dirname "$DEDUP_STATE_FILE")"
}

decrement_dedup_state() {
    local tmp_file
    tmp_file="$(mktemp)"

    if [[ -f "$DEDUP_STATE_FILE" ]]; then
        while IFS='|' read -r signature cycles_left || [[ -n "$signature" ]]; do
            signature="$(trim "$signature")"
            cycles_left="$(trim "$cycles_left")"

            [[ -z "$signature" ]] && continue
            is_non_negative_int "$cycles_left" || continue

            if (( cycles_left > 0 )); then
                cycles_left=$((cycles_left - 1))
            fi

            if (( cycles_left > 0 )); then
                printf '%s|%s\n' "$signature" "$cycles_left" >>"$tmp_file"
            fi
        done < "$DEDUP_STATE_FILE"
    fi

    mv "$tmp_file" "$DEDUP_STATE_FILE"
}

get_dedup_cycles_left() {
    local target_signature="$1"

    [[ -f "$DEDUP_STATE_FILE" ]] || {
        echo "0"
        return
    }

    while IFS='|' read -r signature cycles_left || [[ -n "$signature" ]]; do
        signature="$(trim "$signature")"
        cycles_left="$(trim "$cycles_left")"

        if [[ "$signature" == "$target_signature" ]] && is_non_negative_int "$cycles_left"; then
            echo "$cycles_left"
            return
        fi
    done < "$DEDUP_STATE_FILE"

    echo "0"
}

set_dedup_cycles() {
    local target_signature="$1"
    local target_cycles="$2"
    local tmp_file
    tmp_file="$(mktemp)"

    if [[ -f "$DEDUP_STATE_FILE" ]]; then
        while IFS='|' read -r signature cycles_left || [[ -n "$signature" ]]; do
            signature="$(trim "$signature")"
            cycles_left="$(trim "$cycles_left")"

            [[ -z "$signature" ]] && continue
            [[ "$signature" == "$target_signature" ]] && continue
            is_non_negative_int "$cycles_left" || continue
            (( cycles_left <= 0 )) && continue

            printf '%s|%s\n' "$signature" "$cycles_left" >>"$tmp_file"
        done < "$DEDUP_STATE_FILE"
    fi

    if (( target_cycles > 0 )); then
        printf '%s|%s\n' "$target_signature" "$target_cycles" >>"$tmp_file"
    fi

    mv "$tmp_file" "$DEDUP_STATE_FILE"
}

send_telegram() {
    local message="$1"

    [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]] && return 0

    curl -sS -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="$message" \
        -d parse_mode="${TG_PARSE_MODE}" >/dev/null || {
        log_message "Предупреждение: не удалось отправить сообщение в Telegram."
    }
}

while true; do
    load_config

    SEARCH_QUERY="${SEARCH_FILTERS[*]}"
    log_message "SEARCH_QUERY: ${SEARCH_QUERY:-<пусто>}"

    log_message "Команда: vastai search offers \"$SEARCH_QUERY\" --order price+ --raw --type $SEARCH_TYPE --max $MAX_RESULTS"
    OFFERS="$(vastai search offers "$SEARCH_QUERY" --order price+ --raw --type "$SEARCH_TYPE" --max "$MAX_RESULTS" 2>/dev/null || true)"

    if [[ -z "$OFFERS" ]] || ! jq -e . >/dev/null 2>&1 <<<"$OFFERS"; then
        log_message "Результат поиска пустой или не JSON."
        decrement_dedup_state
        log_message "Ожидание ${CHECK_INTERVAL} сек."
        sleep "$CHECK_INTERVAL"
        continue
    fi

    OFFER_COUNT="$(jq -r 'length' <<<"$OFFERS")"
    log_message "Найдено предложений: $OFFER_COUNT"

    if (( OFFER_COUNT >= 1 )); then
        MACHINE_ID="$(jq -r '.[0].id // "?"' <<<"$OFFERS")"
        PRICE="$(jq -r '.[0].dph_total // "?"' <<<"$OFFERS")"
        RELIABILITY="$(jq -r '.[0].reliability2 // .[0].reliability // "?"' <<<"$OFFERS")"
        VRAM_GB="$(jq -r 'if (.[0].gpu_ram // null) == null then "?" else ((.[0].gpu_ram / 1024) | floor | tostring) end' <<<"$OFFERS")"
        CUDA="$(jq -r '.[0].cuda_max_good // "?"' <<<"$OFFERS")"
        DISK="$(jq -r '.[0].disk_space // "?"' <<<"$OFFERS")"
        INET_UP="$(jq -r '.[0].inet_up // "?"' <<<"$OFFERS")"
        INET_DOWN="$(jq -r '.[0].inet_down // "?"' <<<"$OFFERS")"
        HOST="$(jq -r '.[0].geolocation // "unknown"' <<<"$OFFERS")"

        OFFER_SIGNATURE="${MACHINE_ID}@${PRICE}"
        CYCLES_LEFT="$(get_dedup_cycles_left "$OFFER_SIGNATURE")"

        if (( CYCLES_LEFT > 0 )); then
            log_message "Повтор оффера ${OFFER_SIGNATURE}: до следующего уведомления осталось циклов ${CYCLES_LEFT}."
        else
            LAUNCH_CMD="vastai create instance ${MACHINE_ID} --disk ${DISK_GB} --image ${IMAGE_NAME}"
            if [[ -n "$TEMPLATE_HASH" ]]; then
                LAUNCH_CMD="vastai create instance ${MACHINE_ID} --template_hash ${TEMPLATE_HASH} --disk ${DISK_GB}"
            fi

            MSG="🚨 Нашлись предложения на Vast.ai! (Топ-1)"
            MSG+=$'\n\n'
            MSG+="Цена: \$${PRICE}/час"
            MSG+=$'\n'
            MSG+="ID: ${MACHINE_ID}"
            MSG+=$'\n'
            MSG+="Reliability: ${RELIABILITY}"
            MSG+=$'\n'
            MSG+="VRAM: ${VRAM_GB} GB"
            MSG+=$'\n'
            MSG+="CUDA: ${CUDA}"
            MSG+=$'\n'
            MSG+="Disk: ${DISK} GB"
            MSG+=$'\n'
            MSG+="Inet Up/Down: ${INET_UP}/${INET_DOWN} Mbps"
            MSG+=$'\n'
            MSG+="Локация: ${HOST}"
            MSG+=$'\n\n'
            MSG+="Запуск:"
            MSG+=$'\n'
            MSG+="${LAUNCH_CMD}"
            MSG+=$'\n'
            MSG+="Смотри: https://console.vast.ai/"

            send_telegram "$MSG"
            set_dedup_cycles "$OFFER_SIGNATURE" "$((DEDUP_CYCLES + 1))"
            log_message "Уведомление отправлено. Повтор этого оффера отключён на ${DEDUP_CYCLES} циклов."
        fi
    else
        log_message "Подходящих предложений нет."
    fi

    decrement_dedup_state
    log_message "Ожидание ${CHECK_INTERVAL} сек."
    sleep "$CHECK_INTERVAL"
done