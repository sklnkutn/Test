#!/bin/bash

set -euo pipefail

### Configuration ###
WORKSPACE_DIR="${WORKSPACE:-/workspace}"
FORGE_DIR="${WORKSPACE_DIR}/stable-diffusion-webui-forge"
MODELS_DIR="${FORGE_DIR}/models"
SEMAPHORE_DIR="${WORKSPACE_DIR}/download_sem_$$"
MAX_PARALLEL="${MAX_PARALLEL:-3}"

# APT packages to install (uncomment as needed)
APT_PACKAGES=(
    #"package-1"
    #"package-2"
)

# Python packages to install (uncomment as needed)
PIP_PACKAGES=(
    #"package-1"
    #"package-2"
)

# Extensions to install: "REPO_URL"
# Can also be set via EXTENSIONS env var (semicolon-separated)
# Example: EXTENSIONS="https://github.com/org/ext1;https://github.com/org/ext2"
EXTENSIONS=(
    #"https://github.com/example/extension-name"
)

# ControlNet-related extensions (merged into EXTENSIONS automatically)
# Can also be set via CONTROLNET_EXTENSIONS env var (semicolon-separated)
CONTROLNET_EXTENSIONS_DEFAULT=(
    #SD webui controlnet ~150 MB
    "https://github.com/Mikubill/sd-webui-controlnet"
)

# Model downloads use "URL|OUTPUT_PATH" format
# - If OUTPUT_PATH ends with /, filename is extracted via content-disposition
# - Can also be set via environment variables (semicolon-separated entries)
#
# Example env var format:
#   HF_MODELS="https://huggingface.co/org/repo/resolve/main/model.safetensors|/workspace/models/model.safetensors;https://huggingface.co/org/repo2/resolve/main/model2.safetensors|/workspace/models/model2.safetensors"
#   CIVITAI_MODELS="https://civitai.com/api/download/models/12345|/workspace/models/Stable-diffusion/"
#   WGET_DOWNLOADS="https://example.com/file.bin|/workspace/files/file.bin"

# HuggingFace models (requires HF_TOKEN for gated models)
HF_MODELS_DEFAULT=(
    #"https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors
    #|/workspace/stable-diffusion-webui-forge/models/Stable-diffusion/v1-5-pruned-emaonly.safetensors"
)

# CivitAI models (requires CIVITAI_TOKEN for some models)
# Use trailing / for output path to use content-disposition filename
CIVITAI_MODELS_DEFAULT=(
    #WAI ILL V16.0 6,46 GB
    "https://civitai.com/api/download/models/2514310?type=Model&format=SafeTensor&size=pruned&fp=fp16
    |$MODELS_DIR/Stable-diffusion/waiIllustriousSDXL_v160.safetensors"
)

# LoRA models (URL|OUTPUT_PATH)
# Recommended path: $MODELS_DIR/Lora/
# Can also be set via LORA_MODELS env var
LORA_MODELS_DEFAULT=(
    #Detailer IL V2 218 MB
    "https://civitai.com/api/download/models/1736373?type=Model&format=SafeTensor|$MODELS_DIR/Lora/detailer_v2_il.safetensors"
    #Realistic filter V1 55 MB
    "https://civitai.com/api/download/models/1124771?type=Model&format=SafeTensor|$MODELS_DIR/Lora/realistic_filter_v1_il.safetensors"
    #Hyperrealistic V4 ILL 435 MB
    "https://civitai.com/api/download/models/1914557?type=Model&format=SafeTensor|$MODELS_DIR/Lora/hyperrealistic_v4_ill.safetensors"
    #Niji semi realism V3.5 ILL 435 MB
    "https://civitai.com/api/download/models/1882710?type=Model&format=SafeTensor|$MODELS_DIR/Lora/niji_semi_realism_v35.safetensors"
    #ATNR Style ILL V1.1 350 MB
    "https://civitai.com/api/download/models/1711464?type=Model&format=SafeTensor|$MODELS_DIR/Lora/atnr_style_ill_v1.1.safetensors"
    #Face Enhancer Ill 218 MB
    "https://civitai.com/api/download/models/1839268?type=Model&format=SafeTensor|$MODELS_DIR/Lora/face_enhancer_ill.safetensors"
    #Smooth Detailer Booster V4 243 MB
    "https://civitai.com/api/download/models/2196453?type=Model&format=SafeTensor|$MODELS_DIR/Lora/smooth_detailer_booster_v4.safetensors"
    #USNR Style V-pred 157 MB
    "https://civitai.com/api/download/models/2555444?type=Model&format=SafeTensor|$MODELS_DIR/Lora/usnr_style_v_pred.safetensors"
    #748cm Style V1 243 MB
    "https://civitai.com/api/download/models/1056404?type=Model&format=SafeTensor|$MODELS_DIR/Lora/748cm_style_v1.safetensors"
    #Velvet's Mythic Fantasy Styles IL 218 MB
    "https://civitai.com/api/download/models/2620790?type=Model&format=SafeTensor|$MODELS_DIR/Lora/velvets_mythic_fantasy_styles_il.safetensors"
    #"https://civitai.com/api/download/models/|$MODELS_DIR/Lora/"
)

# ControlNet/OpenPose models (URL|OUTPUT_PATH)
# Supports both HuggingFace and CivitAI URLs
# Recommended path: $MODELS_DIR/ControlNet/
# Can also be set via CONTROLNET_MODELS env var
CONTROLNET_MODELS_DEFAULT=(
    #t2i-adapter_xl_openpose 151 MB
    "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/t2i-adapter_xl_openpose.safetensors|$MODELS_DIR/ControlNet/t2i-adapter_xl_openpose.safetensors"
    #t2i-adapter_xl_canny 148 MB
    "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/t2i-adapter_xl_canny.safetensors|$MODELS_DIR/ControlNet/t2i-adapter_xl_canny.safetensors"
    #t2i-adapter_xl_sketch 148 MB
    "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/t2i-adapter_xl_sketch.safetensors|$MODELS_DIR/ControlNet/t2i-adapter_xl_sketch.safetensors"
    #t2i-adapter_diffusers_xl_depth_midas 151 MB
    "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/t2i-adapter_diffusers_xl_depth_midas.safetensors|$MODELS_DIR/ControlNet/t2i-adapter_diffusers_xl_depth_midas.safetensors"
    #t2i-adapter_diffusers_xl_depth_zoe 151 MB
    "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/t2i-adapter_diffusers_xl_depth_zoe.safetensors|$MODELS_DIR/ControlNet/t2i-adapter_diffusers_xl_depth_zoe.safetensors"
    #t2i-adapter_diffusers_xl_lineart 151 MB
    "https://huggingface.co/lllyasviel/sd_control_collection/resolve/main/t2i-adapter_diffusers_xl_lineart.safetensors|$MODELS_DIR/ControlNet/t2i-adapter_diffusers_xl_lineart.safetensors"
)

# Generic wget downloads (no auth)
WGET_DOWNLOADS_DEFAULT=(
    #"https://example.com/file.safetensors|$MODELS_DIR/other/file.safetensors"
)

### End Configuration ###

log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message"
}

script_cleanup() {
    log "Cleaning up semaphore directory..."
    rm -rf "$SEMAPHORE_DIR"
    # Clean up any stale lock files from this run
    find "$MODELS_DIR" -name "*.lock" -type f -mmin +60 -delete 2>/dev/null || true
}

script_error() {
    local exit_code=$?
    local line_number=$1
    log "[ERROR] Provisioning script failed at line $line_number with exit code $exit_code"
    exit "$exit_code"
}

trap script_cleanup EXIT
trap 'script_error $LINENO' ERR

# Normalize a URL|PATH entry: collapse whitespace, trim, return single line
# Handles multi-line entries from array definitions
normalize_entry() {
    local entry="$1"
    # Replace newlines and multiple spaces with single space, then trim
    entry=$(echo "$entry" | tr '\n' ' ' | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')
    echo "$entry"
}

# Parse semicolon-separated string into array, filtering out comments and empty entries
# Usage: parse_env_array "ENV_VAR_NAME"
# Output: null-terminated entries (use read -r -d '' to consume)
parse_env_array() {
    local env_var_name="$1"
    local env_value="${!env_var_name:-}"

    if [[ -n "$env_value" ]]; then
        local -a result=()
        IFS=';' read -ra entries <<< "$env_value"
        for entry in "${entries[@]}"; do
            entry=$(normalize_entry "$entry")
            # Skip empty entries and comments
            [[ -z "$entry" || "$entry" == \#* ]] && continue
            result+=("$entry")
        done
        # Return array elements, null-terminated
        if [[ ${#result[@]} -gt 0 ]]; then
            printf '%s\0' "${result[@]}"
        fi
    fi
}

# Merge default array with environment variable additions, filtering comments
# Output: null-terminated entries (use read -r -d '' to consume)
# Returns via stdout, logs to stderr to avoid mixing with data
# Defaults are always included, env var entries are ADDED to defaults
merge_with_env() {
    local env_var_name="$1"
    shift
    local -a default_array=("$@")
    local env_value="${!env_var_name:-}"

    # First, output all defaults (filtered)
    if [[ ${#default_array[@]} -gt 0 ]]; then
        for entry in "${default_array[@]}"; do
            entry=$(normalize_entry "$entry")
            # Skip empty entries and comments
            [[ -z "$entry" || "$entry" == \#* ]] && continue
            printf '%s\0' "$entry"
        done
    fi

    # Then, add any entries from environment variable
    if [[ -n "$env_value" ]]; then
        echo "[merge_with_env] Adding entries from $env_var_name environment variable" >&2
        parse_env_array "$env_var_name"
    fi
}

acquire_slot() {
    local prefix="$1"
    local max_slots="$2"
    local slot_dir
    slot_dir="$(dirname "$prefix")"
    local slot_prefix
    slot_prefix="$(basename "$prefix")"

    while true; do
        local count
        count=$(find "$slot_dir" -maxdepth 1 -name "${slot_prefix}_*" 2>/dev/null | wc -l)
        if [ "$count" -lt "$max_slots" ]; then
            # Use atomic file creation with O_EXCL via bash noclobber
            local slot="${prefix}_$$_${RANDOM}_${RANDOM}"
            if (set -o noclobber; : > "$slot") 2>/dev/null; then
                echo "$slot"
                return 0
            fi
            # File creation failed (race), retry
        fi
        sleep 0.5
    done
}

release_slot() {
    rm -f "$1"
}

# Check if HF token is valid
has_valid_hf_token() {
    [[ -n "${HF_TOKEN:-}" ]] || return 1
    local response
    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET \
        "https://huggingface.co/api/whoami-v2" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")
    [[ "$response" -eq 200 ]]
}

# Check if CivitAI token is valid
has_valid_civitai_token() {
    [[ -n "${CIVITAI_TOKEN:-}" ]] || return 1
    local response
    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET \
        "https://civitai.com/api/v1/models?hidden=1&limit=1" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")
    [[ "$response" -eq 200 ]]
}

# Download a HuggingFace file using the hf CLI
# Args: URL OUTPUT_PATH
# Uses HF_TOKEN automatically if set in environment
download_hf_file() {
    local url="$1"
    local output_path="$2"
    local max_retries=5
    local retry_delay=2

    # Acquire slot for parallel download limiting
    local slot
    slot=$(acquire_slot "$SEMAPHORE_DIR/hf" "$MAX_PARALLEL")

    # Ensure slot is released on any exit from this function
    trap 'release_slot "$slot"' RETURN

    # Ensure parent directory exists
    mkdir -p "$(dirname "$output_path")"

    # Create lockfile based on output path
    local lockfile="${output_path}.lock"

    (
        # Acquire exclusive lock (wait up to 300 seconds)
        if ! flock -x -w 300 200; then
            log "[ERROR] Could not acquire lock for $output_path after 300s"
            exit 1
        fi

        # Check if file already exists (inside lock to avoid race)
        if [[ -f "$output_path" ]]; then
            log "File already exists: $output_path (skipping)"
            exit 0
        fi

        # Extract repo and file path from HuggingFace URL
        local repo file_path
        repo=$(echo "$url" | sed -n 's|https://huggingface.co/\([^/]*/[^/]*\)/resolve/.*|\1|p')
        file_path=$(echo "$url" | sed -n 's|https://huggingface.co/[^/]*/[^/]*/resolve/[^/]*/\(.*\)|\1|p')

        if [[ -z "$repo" ]] || [[ -z "$file_path" ]]; then
            log "[ERROR] Invalid HuggingFace URL: $url"
            exit 1
        fi

        local temp_dir
        temp_dir=$(mktemp -d)
        local attempt=1
        local current_delay=$retry_delay

        # Retry loop for rate limits and transient failures
        while [[ $attempt -le $max_retries ]]; do
            log "Downloading $repo/$file_path (attempt $attempt/$max_retries)..."
            hf_command=$(command -v hf || command -v huggingface-cli)
            if "$hf_command" download "$repo" \
                "$file_path" \
                --local-dir "$temp_dir" \
                --cache-dir "$temp_dir/.cache" 2>&1; then

                # Verify the file was actually downloaded
                if [[ -f "$temp_dir/$file_path" ]]; then
                    # Success - move file and clean up
                    mv "$temp_dir/$file_path" "$output_path"
                    rm -rf "$temp_dir"
                    log "Successfully downloaded: $output_path"
                    exit 0
                else
                    log "Download command succeeded but file not found at $temp_dir/$file_path"
                fi
            fi

            log "Download failed (attempt $attempt/$max_retries), retrying in ${current_delay}s..."
            sleep $current_delay
            current_delay=$((current_delay * 2))
            attempt=$((attempt + 1))
        done

        # All retries failed
        log "[ERROR] Failed to download $output_path after $max_retries attempts"
        rm -rf "$temp_dir"
        exit 1

    ) 200>"$lockfile"

    local result=$?
    rm -f "$lockfile"
    return $result
}

# Extract filename from content-disposition header via HEAD request
# Args: URL [AUTH_HEADER]
get_content_disposition_filename() {
    local url="$1"
    local auth_header="${2:-}"
    local curl_args=(-sI -L --max-time 30)

    if [[ -n "$auth_header" ]]; then
        curl_args+=(-H "$auth_header")
    fi

    local headers
    headers=$(curl "${curl_args[@]}" "$url" 2>/dev/null)

    # Try to extract filename from content-disposition header
    local filename
    filename=$(echo "$headers" | grep -i 'content-disposition:' | \
        sed -n 's/.*filename="\?\([^"]*\)"\?.*/\1/p' | \
        tail -1 | tr -d '\r')

    # Clean up the filename
    filename="${filename##*/}"
    echo "$filename"
}

# Download a file with retry logic and proper locking
# Args: URL OUTPUT_PATH [AUTH_TYPE]
# AUTH_TYPE: "hf", "civitai", or empty for no auth
# If OUTPUT_PATH ends with /, uses content-disposition for filename
download_file() {
    local url="$1"
    local output_path="$2"
    local auth_type="${3:-}"
    local max_retries=5
    local retry_delay=2

    # Acquire slot for parallel download limiting
    local slot
    slot=$(acquire_slot "$SEMAPHORE_DIR/dl" "$MAX_PARALLEL")

    # Ensure slot is released on any exit from this function
    trap 'release_slot "$slot"' RETURN

    # Determine if output is a directory (use content-disposition) or full path
    local output_dir output_file use_content_disposition=false
    if [[ "$output_path" == */ ]]; then
        output_dir="${output_path%/}"
        use_content_disposition=true
    else
        output_dir="$(dirname "$output_path")"
        output_file="$(basename "$output_path")"
    fi

    mkdir -p "$output_dir"

    # Build auth header based on auth_type
    local auth_header=""
    if [[ "$auth_type" == "hf" ]] && [[ -n "${HF_TOKEN:-}" ]]; then
        auth_header="Authorization: Bearer $HF_TOKEN"
    elif [[ "$auth_type" == "civitai" ]] && [[ -n "${CIVITAI_TOKEN:-}" ]]; then
        auth_header="Authorization: Bearer $CIVITAI_TOKEN"
    fi

    # Create lockfile based on URL hash to prevent concurrent downloads of the same resource
    local url_hash
    url_hash=$(printf '%s' "$url" | md5sum | cut -d' ' -f1)
    local lockfile="${output_dir}/.download_${url_hash}.lock"

    (
        # Acquire exclusive lock (wait up to 300 seconds)
        if ! flock -x -w 300 200; then
            log "[ERROR] Could not acquire lock for download after 300s: $url"
            exit 1
        fi

        local attempt=1
        local current_delay=$retry_delay

        while [ $attempt -le $max_retries ]; do
            log "Downloading: $url (attempt $attempt/$max_retries)..."

            local wget_args=(
                --timeout=60
                --tries=1
                --continue
                --progress=dot:giga
            )

            if [[ -n "$auth_header" ]]; then
                wget_args+=(--header="$auth_header")
            fi

            if [[ "$use_content_disposition" == true ]]; then
                # For content-disposition, check if we can determine filename from headers
                local remote_filename
                remote_filename=$(get_content_disposition_filename "$url" "$auth_header")
                if [[ -n "$remote_filename" && -f "$output_dir/$remote_filename" ]]; then
                    log "File already exists: $output_dir/$remote_filename (skipping)"
                    exit 0
                fi
                wget_args+=(--content-disposition -P "$output_dir")
            else
                # Check if file already exists
                if [[ -f "$output_dir/$output_file" ]]; then
                    log "File already exists: $output_dir/$output_file (skipping)"
                    exit 0
                fi
                wget_args+=(-O "$output_dir/$output_file")
            fi

            if wget "${wget_args[@]}" "$url" 2>&1; then
                log "Successfully downloaded to: $output_dir"
                exit 0
            fi

            log "Download failed (attempt $attempt/$max_retries), retrying in ${current_delay}s..."
            sleep $current_delay
            current_delay=$((current_delay * 2))
            attempt=$((attempt + 1))
        done

        log "[ERROR] Failed to download $url after $max_retries attempts"
        exit 1

    ) 200>"$lockfile"

    local result=$?
    rm -f "$lockfile"
    return $result
}

# Install APT packages
install_apt_packages() {
    if [[ ${#APT_PACKAGES[@]} -gt 0 && -n "${APT_PACKAGES[*]}" ]]; then
        log "Installing APT packages..."
        sudo apt-get update
        sudo apt-get install -y "${APT_PACKAGES[@]}"
    fi
}

# Install Python packages
install_pip_packages() {
    if [[ ${#PIP_PACKAGES[@]} -gt 0 && -n "${PIP_PACKAGES[*]}" ]]; then
        log "Installing Python packages..."
        uv pip install --no-cache-dir "${PIP_PACKAGES[@]}"
    fi
}

# Install extensions
install_extensions() {
    # Merge defaults with env vars (comments already filtered)
    local -a extensions=()
    while IFS= read -r -d '' entry; do
        [[ -n "$entry" ]] && extensions+=("$entry")
    done < <(merge_with_env "EXTENSIONS" "${EXTENSIONS[@]}")
    while IFS= read -r -d '' entry; do
        [[ -n "$entry" ]] && extensions+=("$entry")
    done < <(merge_with_env "CONTROLNET_EXTENSIONS" "${CONTROLNET_EXTENSIONS_DEFAULT[@]}")

    if [[ ${#extensions[@]} -eq 0 ]]; then
        log "No extensions to install"
        return 0
    fi

    log "Installing ${#extensions[@]} extension(s)..."

    # Avoid git errors because we run as root but files are owned by 'user'
    export GIT_CONFIG_GLOBAL=/tmp/temporary-git-config
    git config --file "$GIT_CONFIG_GLOBAL" --add safe.directory '*'

    for repo in "${extensions[@]}"; do
        # Skip empty entries (comments already filtered)
        [[ -z "$repo" ]] && continue

        local dir="${repo##*/}"
        dir="${dir%.git}"
        local path="${FORGE_DIR}/extensions/${dir}"

        if [[ -d "$path" ]]; then
            log "Extension already installed: $dir"
        else
            log "Installing extension: $repo"
            git clone "$repo" "$path" --recursive
        fi
    done
}

# Ensure target model directories exist before downloads
ensure_model_directories() {
    log "Ensuring model directories exist..."

    local -a required_dirs=(
        "$MODELS_DIR/Stable-diffusion"
        "$MODELS_DIR/Lora"
        "$MODELS_DIR/ControlNet"
    )

    local target_path
    for target_path in "$@"; do
        [[ -z "${target_path// }" ]] && continue

        # Trim whitespace
        target_path="${target_path#"${target_path%%[![:space:]]*}"}"
        target_path="${target_path%"${target_path##*[![:space:]]}"}"

        # If entry uses trailing slash treat as directory, otherwise use dirname(file)
        if [[ "$target_path" == */ ]]; then
            required_dirs+=("${target_path%/}")
        else
            required_dirs+=("$(dirname "$target_path")")
        fi
    done

    # Deduplicate and create
    printf '%s\n' "${required_dirs[@]}" | awk 'NF && !seen[$0]++' | while IFS= read -r dir; do
        mkdir -p "$dir"
        log "Directory ready: $dir"
    done
}

# Decide auth/downloader for a URL when auth_type is "auto"
# Output: "hf", "civitai", or ""
autodetect_auth_type() {
    local url="$1"

    if [[ "$url" == *"huggingface.co"* ]]; then
        echo "hf"
    elif [[ "$url" == *"civitai.com"* ]]; then
        echo "civitai"
    else
        echo ""
    fi
}

# Resolve HF output path when caller provides directory path ending with '/'
# Args: URL OUTPUT_PATH
# Output: resolved full file path
resolve_hf_output_path() {
    local url="$1"
    local output_path="$2"

    if [[ "$output_path" == */ ]]; then
        local filename
        filename="${url%%\?*}"
        filename="${filename##*/}"
        echo "${output_path}${filename}"
    else
        echo "$output_path"
    fi
}

# Download models from an array with specified auth type
# Args: array_name auth_type
# auth_type: "hf", "civitai", "", or "auto" (detect by URL)
download_models() {
    local -n model_array=$1
    local auth_type="$2"
    local pids=()

    for entry in "${model_array[@]}"; do
        # Skip empty entries (comments already filtered during array construction)
        [[ -z "${entry// }" ]] && continue

        local url="${entry%%|*}"
        local output_path="${entry##*|}"

        # Trim whitespace using parameter expansion (safer than xargs)
        url="${url#"${url%%[![:space:]]*}"}"
        url="${url%"${url##*[![:space:]]}"}"
        output_path="${output_path#"${output_path%%[![:space:]]*}"}"
        output_path="${output_path%"${output_path##*[![:space:]]}"}"

        log "Queuing download: $url -> $output_path"

        # Use appropriate downloader based on auth type
        local effective_auth_type="$auth_type"
        if [[ "$effective_auth_type" == "auto" ]]; then
            effective_auth_type=$(autodetect_auth_type "$url")
        fi

        if [[ "$effective_auth_type" == "hf" ]]; then
            local hf_output_path
            hf_output_path=$(resolve_hf_output_path "$url" "$output_path")
            download_hf_file "$url" "$hf_output_path" &
        else
            download_file "$url" "$output_path" "$effective_auth_type" &
        fi
        pids+=($!)
    done

    # Wait for all downloads and track failures
    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            log "[ERROR] Download process $pid failed"
            failed=1
        fi
    done

    return $failed
}

# Run Forge startup test to ensure dependencies are ready
run_startup_test() {
    log "Running Forge startup test..."

    # Avoid git errors
    export GIT_CONFIG_GLOBAL=/tmp/temporary-git-config
    git config --file "$GIT_CONFIG_GLOBAL" --add safe.directory '*'

    cd "${FORGE_DIR}"
    LD_PRELOAD=libtcmalloc_minimal.so.4 \
        python launch.py \
            --skip-python-version-check \
            --no-download-sd-model \
            --do-not-download-clip \
            --no-half \
            --port 11404 \
            --exit
}

main() {
    # Activate virtual environment
    if [[ -f /venv/main/bin/activate ]]; then
        # shellcheck source=/dev/null
        . /venv/main/bin/activate
    fi

    # Validate tokens if set
    if [[ -n "${HF_TOKEN:-}" ]]; then
        if has_valid_hf_token; then
            log "HuggingFace token validated"
        else
            log "[WARN] HF_TOKEN is set but appears invalid"
        fi
    fi

    if [[ -n "${CIVITAI_TOKEN:-}" ]]; then
        if has_valid_civitai_token; then
            log "CivitAI token validated"
        else
            log "[WARN] CIVITAI_TOKEN is set but appears invalid"
        fi
    fi

    # Build model arrays from defaults + env vars (null-terminated for multi-line entries)
    # Use lowercase names to avoid shadowing the environment variables
    local -a hf_models=()
    while IFS= read -r -d '' entry; do
        [[ -n "$entry" ]] && hf_models+=("$entry")
    done < <(merge_with_env "HF_MODELS" "${HF_MODELS_DEFAULT[@]}")

    local -a civitai_models=()
    while IFS= read -r -d '' entry; do
        [[ -n "$entry" ]] && civitai_models+=("$entry")
    done < <(merge_with_env "CIVITAI_MODELS" "${CIVITAI_MODELS_DEFAULT[@]}")

    local -a lora_models=()
    while IFS= read -r -d '' entry; do
        [[ -n "$entry" ]] && lora_models+=("$entry")
    done < <(merge_with_env "LORA_MODELS" "${LORA_MODELS_DEFAULT[@]}")

    local -a controlnet_models=()
    while IFS= read -r -d '' entry; do
        [[ -n "$entry" ]] && controlnet_models+=("$entry")
    done < <(merge_with_env "CONTROLNET_MODELS" "${CONTROLNET_MODELS_DEFAULT[@]}")

    local -a wget_downloads=()
    while IFS= read -r -d '' entry; do
        [[ -n "$entry" ]] && wget_downloads+=("$entry")
    done < <(merge_with_env "WGET_DOWNLOADS" "${WGET_DOWNLOADS_DEFAULT[@]}")

    # Log what we're going to download
    log "HF_MODELS: ${#hf_models[@]} entries"
    log "CIVITAI_MODELS: ${#civitai_models[@]} entries"
    log "LORA_MODELS: ${#lora_models[@]} entries"
    log "CONTROLNET_MODELS: ${#controlnet_models[@]} entries"
    log "WGET_DOWNLOADS: ${#wget_downloads[@]} entries"

    # Clean up any leftover semaphores and create fresh directory
    rm -rf "$SEMAPHORE_DIR"
    mkdir -p "$SEMAPHORE_DIR"

    # Install packages first
    install_apt_packages
    install_pip_packages

    # Ensure default and configured target folders exist before installing/downloading
    local -a all_output_paths=()
    local entry output_path
    for entry in "${hf_models[@]}" "${civitai_models[@]}" "${lora_models[@]}" "${controlnet_models[@]}" "${wget_downloads[@]}"; do
        output_path="${entry##*|}"
        output_path="${output_path#"${output_path%%[![:space:]]*}"}"
        output_path="${output_path%"${output_path##*[![:space:]]}"}"
        [[ -n "$output_path" ]] && all_output_paths+=("$output_path")
    done
    ensure_model_directories "${all_output_paths[@]}"

    # Install extensions
    install_extensions

    # Download all models in parallel
    local download_failed=0

    log "Starting model downloads..."

    if [[ ${#hf_models[@]} -gt 0 ]]; then
        download_models hf_models "hf" || download_failed=1
    fi

    if [[ ${#civitai_models[@]} -gt 0 ]]; then
        download_models civitai_models "civitai" || download_failed=1
    fi

    if [[ ${#lora_models[@]} -gt 0 ]]; then
        download_models lora_models "civitai" || download_failed=1
    fi

    if [[ ${#controlnet_models[@]} -gt 0 ]]; then
        download_models controlnet_models "auto" || download_failed=1
    fi

    if [[ ${#wget_downloads[@]} -gt 0 ]]; then
        download_models wget_downloads "" || download_failed=1
    fi

    if [[ $download_failed -eq 1 ]]; then
        log "[ERROR] One or more downloads failed"
        exit 1
    fi

    log "All downloads completed successfully"

    # Run startup test
    run_startup_test
}

main "$@"
