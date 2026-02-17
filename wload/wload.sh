#!/usr/bin/env bash
set -euo pipefail

# Vast.ai-only helper script.
# Purpose: prepare directories, install/update ControlNet extension,
# and download ControlNet models, WAI checkpoint, and LoRA files.

BASE_DIR="${BASE_DIR:-/workspace}"
FORGE_DIR="${FORGE_DIR:-${BASE_DIR}/stable-diffusion-webui-forge}"
MODELS_DIR="${MODELS_DIR:-${FORGE_DIR}/models/Stable-diffusion}"
LORA_DIR="${LORA_DIR:-${FORGE_DIR}/models/Lora}"
EXTENSIONS_DIR="${EXTENSIONS_DIR:-${FORGE_DIR}/extensions}"
CONTROLNET_DIR="${CONTROLNET_DIR:-${EXTENSIONS_DIR}/sd-webui-controlnet}"
CONTROLNET_MODELS_DIR="${CONTROLNET_MODELS_DIR:-${CONTROLNET_DIR}/models}"

CONTROLNET_REPO_URL="https://github.com/Mikubill/sd-webui-controlnet"
CONTROLNET_INSTALL_MODE="${CONTROLNET_INSTALL_MODE:-reinstall}" # reinstall|update|skip
MIN_VALID_FILE_BYTES="${MIN_VALID_FILE_BYTES:-1000000}"

CIVITAI_TOKEN="${CIVITAI_TOKEN:-}"
HF_TOKEN="${HF_TOKEN:-}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

ensure_aria2c() {
  if require_cmd aria2c; then
    echo "aria2c already installed"
    return
  fi

  echo "aria2c not found, installing..."
  apt-get update -qq
  apt-get install -y -qq aria2
  echo "aria2c installed"
}

ensure_dirs() {
  mkdir -p "$MODELS_DIR" "$LORA_DIR" "$EXTENSIONS_DIR" "$CONTROLNET_MODELS_DIR"
  echo "Directories are ready"
}

install_or_update_controlnet() {
  case "$CONTROLNET_INSTALL_MODE" in
    reinstall|update|skip) ;;
    *)
      echo "ERROR: CONTROLNET_INSTALL_MODE must be one of: reinstall, update, skip"
      exit 1
      ;;
  esac

  echo "ControlNet path: $CONTROLNET_DIR"
  echo "Install mode: $CONTROLNET_INSTALL_MODE"

  if [[ "$CONTROLNET_INSTALL_MODE" == "skip" ]]; then
    echo "ControlNet install skipped"
    return
  fi

  if [[ -d "$CONTROLNET_DIR" && "$CONTROLNET_INSTALL_MODE" == "reinstall" ]]; then
    echo "Removing existing ControlNet directory..."
    rm -rf "$CONTROLNET_DIR"
  fi

  if [[ ! -d "$CONTROLNET_DIR/.git" ]]; then
    rm -rf "$CONTROLNET_DIR"
    echo "Cloning ControlNet..."
    git clone "$CONTROLNET_REPO_URL" "$CONTROLNET_DIR"
  else
    echo "Updating ControlNet..."
    git -C "$CONTROLNET_DIR" pull --ff-only
  fi

  mkdir -p "$CONTROLNET_MODELS_DIR"
}

looks_valid_file() {
  local path="$1"
  [[ -f "$path" ]] && [[ "$(stat -c%s "$path")" -gt "$MIN_VALID_FILE_BYTES" ]]
}

download_with_aria2c() {
  local label="$1"
  local url="$2"
  local out_name="$3"
  local token_kind="$4"
  local target_dir="$5"

  local output_path="${target_dir}/${out_name}"
  local token=""

  case "$token_kind" in
    CIVITAI) token="$CIVITAI_TOKEN" ;;
    HF_TOKEN) token="$HF_TOKEN" ;;
    NONE) token="" ;;
    *)
      echo "ERROR: unknown token kind '$token_kind' for '$label'"
      return 1
      ;;
  esac

  if looks_valid_file "$output_path"; then
    echo "[SKIP] $label -> already exists"
    return 0
  fi

  local final_url="$url"
  local -a headers=()

  if [[ "$token_kind" == "CIVITAI" ]]; then
    if [[ -z "$token" ]]; then
      echo "ERROR: CIVITAI_TOKEN is required for '$label'"
      return 1
    fi
    if [[ "$final_url" != *"token="* ]]; then
      if [[ "$final_url" == *"?"* ]]; then
        final_url+="&token=${token}"
      else
        final_url+="?token=${token}"
      fi
    fi
  fi

  if [[ "$token_kind" == "HF_TOKEN" ]]; then
    if [[ -z "$token" ]]; then
      echo "ERROR: HF_TOKEN is required for '$label'"
      return 1
    fi
    headers+=("Authorization: Bearer ${token}")
  fi

  echo "[DL] $label"
  mkdir -p "$target_dir"

  local -a cmd=(
    aria2c
    --allow-overwrite=true
    --auto-file-renaming=false
    --file-allocation=none
    --summary-interval=0
    --console-log-level=warn
    --max-connection-per-server=8
    --split=8
    --retry-wait=5
    --max-tries=20
    --timeout=30
    --dir="$target_dir"
    --out="$out_name"
  )

  for h in "${headers[@]}"; do
    cmd+=(--header="$h")
  done

  cmd+=("$final_url")
  "${cmd[@]}"

  if ! looks_valid_file "$output_path"; then
    echo "ERROR: downloaded file is missing or too small: $output_path"
    return 1
  fi

  echo "[OK] $label"
}

main() {
  ensure_aria2c
  ensure_dirs
  install_or_update_controlnet

  # ControlNet models
  download_with_aria2c "t2i-adapter_xl_openpose 151 MB" \
    "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/t2i-adapter_xl_openpose.safetensors" \
    "t2i-adapter_xl_openpose.safetensors" "HF_TOKEN" "$CONTROLNET_MODELS_DIR"

  download_with_aria2c "t2i-adapter_xl_canny 148 MB" \
    "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/t2i-adapter_xl_canny.safetensors" \
    "t2i-adapter_xl_canny.safetensors" "HF_TOKEN" "$CONTROLNET_MODELS_DIR"

  download_with_aria2c "t2i-adapter_xl_sketch 148 MB" \
    "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/t2i-adapter_xl_sketch.safetensors" \
    "t2i-adapter_xl_sketch.safetensors" "HF_TOKEN" "$CONTROLNET_MODELS_DIR"

  download_with_aria2c "t2i-adapter_diffusers_xl_depth_midas 151 MB" \
    "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/t2i-adapter_diffusers_xl_depth_midas.safetensors" \
    "t2i-adapter_diffusers_xl_depth_midas.safetensors" "HF_TOKEN" "$CONTROLNET_MODELS_DIR"

  download_with_aria2c "t2i-adapter_diffusers_xl_depth_zoe 151 MB" \
    "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/t2i-adapter_diffusers_xl_depth_zoe.safetensors" \
    "t2i-adapter_diffusers_xl_depth_zoe.safetensors" "HF_TOKEN" "$CONTROLNET_MODELS_DIR"

  download_with_aria2c "t2i-adapter_diffusers_xl_lineart 151 MB" \
    "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/t2i-adapter_diffusers_xl_lineart.safetensors" \
    "t2i-adapter_diffusers_xl_lineart.safetensors" "HF_TOKEN" "$CONTROLNET_MODELS_DIR"

  # WAI checkpoint
  download_with_aria2c "WAI ILL V16.0 6,46 GB" \
    "https://civitai.com/api/download/models/2514310?type=Model&format=SafeTensor&size=pruned&fp=fp16" \
    "wai_v160.safetensors" "CIVITAI" "$MODELS_DIR"

  # LoRA
  download_with_aria2c "Detailer IL V2 218 MB" \
    "https://civitai.com/api/download/models/1736373?type=Model&format=SafeTensor" \
    "detailer_v2_il.safetensors" "CIVITAI" "$LORA_DIR"

  download_with_aria2c "Realistic filter V1 55 MB" \
    "https://civitai.com/api/download/models/1124771?type=Model&format=SafeTensor" \
    "realistic_filter_v1_il.safetensors" "CIVITAI" "$LORA_DIR"

  download_with_aria2c "Hyperrealistic V4 ILL 435 MB" \
    "https://civitai.com/api/download/models/1914557?type=Model&format=SafeTensor" \
    "hyperrealistic_v4_ill.safetensors" "CIVITAI" "$LORA_DIR"

  download_with_aria2c "Niji semi realism V3.5 ILL 435 MB" \
    "https://civitai.com/api/download/models/1882710?type=Model&format=SafeTensor" \
    "niji_v35.safetensors" "CIVITAI" "$LORA_DIR"

  download_with_aria2c "ATNR Style ILL V1.1 350 MB" \
    "https://civitai.com/api/download/models/1711464?type=Model&format=SafeTensor" \
    "atnr_style_ill_v1.1.safetensors" "CIVITAI" "$LORA_DIR"

  download_with_aria2c "Face Enhancer Ill 218 MB" \
    "https://civitai.com/api/download/models/1839268?type=Model&format=SafeTensor" \
    "face_enhancer_ill.safetensors" "CIVITAI" "$LORA_DIR"

  download_with_aria2c "Smooth Detailer Booster V4 243 MB" \
    "https://civitai.com/api/download/models/2196453?type=Model&format=SafeTensor" \
    "smooth_detailer_booster_v4.safetensors" "CIVITAI" "$LORA_DIR"

  download_with_aria2c "USNR Style V-pred 157 MB" \
    "https://civitai.com/api/download/models/2555444?type=Model&format=SafeTensor" \
    "usnr_style.safetensors" "CIVITAI" "$LORA_DIR"

  download_with_aria2c "748cm Style V1 243 MB" \
    "https://civitai.com/api/download/models/1056404?type=Model&format=SafeTensor" \
    "748cm_style_v1.safetensors" "CIVITAI" "$LORA_DIR"

  download_with_aria2c "Velvet's Mythic Fantasy Styles IL 218 MB" \
    "https://civitai.com/api/download/models/2620790?type=Model&format=SafeTensor" \
    "velvets_styles.safetensors" "CIVITAI" "$LORA_DIR"

  download_with_aria2c "Pixel Art Style IL V7 435 MB" \
    "https://civitai.com/api/download/models/2661972?type=Model&format=SafeTensor" \
    "pixel_art.safetensors" "CIVITAI" "$LORA_DIR"

  echo "Done. Assets are prepared for Vast.ai."
}

main "$@"
