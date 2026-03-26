#!/bin/bash
set -e
shift || true  # игнорируем лишние аргументы от Vast.ai / RunPod

source /venv/main/bin/activate

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

# ─── Определяем платформу ─────────────────────────────────────────────────────
if [[ -n "${RUNPOD_POD_ID:-}" ]]; then
    PLATFORM="RunPod"
else
    PLATFORM="Vast.ai"
fi

# ─── Утилиты для красивого вывода ─────────────────────────────────────────────
BOLD="\033[1m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[1;33m"
RESET="\033[0m"

function section() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}  ${BOLD}$1${RESET}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${RESET}"
}

function log_info()    { echo -e "  ${GREEN}✔${RESET}  $1"; }
function log_warn()    { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
function log_skip()    { echo -e "  ${CYAN}↷${RESET}  $1 ${YELLOW}(уже есть, пропускаем)${RESET}"; }
function log_dl()      { echo -e "  ${CYAN}↓${RESET}  $1"; }

# ─── Модели ───────────────────────────────────────────────────────────────────

CLIP_MODELS=(
    "https://huggingface.co/f5aiteam/CLIP/resolve/main/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
)

CLIP_VISION_MODELS=(
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"
)

VAE_MODELS=(
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors"
)

DIFFUSION_MODELS=(
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
    "https://huggingface.co/Tongyi-MAI/Z-Image/resolve/main/transformer/diffusion_pytorch_model-00001-of-00002.safetensors"
    "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/Wan22Animate/Wan2_2-Animate-14B_fp8_scaled_e4m3fn_KJ_v2.safetensors"
)

DETECTION_MODELS=(
    "https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx"
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_data.bin"
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_model.onnx"
    "https://huggingface.co/wissxi/Wan_2.2_Ki4ra/resolve/main/models/detection/vitpose-l-wholebody.onnx"
)

LORA_MODELS=(
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank256_bf16.safetensors"
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors"
    "https://huggingface.co/alibaba-pai/Wan2.2-Fun-Reward-LoRAs/resolve/main/Wan2.2-Fun-A14B-InP-low-noise-HPS2.1.safetensors"
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Pusa/Wan21_PusaV1_LoRA_14B_rank512_bf16.safetensors"
)

UPSCALER_MODELS=(
    "https://huggingface.co/GerbyHorty76/videoloras/resolve/main/4xUltrasharp_4xUltrasharpV10.pt"
)

# ─── Функции ──────────────────────────────────────────────────────────────────

function provisioning_get_files() {
    if [[ $# -lt 2 ]]; then return; fi
    local dir="$1"
    shift
    local files=("$@")

    mkdir -p "$dir"
    echo -e "  ${BOLD}Папка:${RESET} $dir  (${#files[@]} файл(ов))"

    for url in "${files[@]}"; do
        local filename
        filename=$(basename "$url" | cut -d'?' -f1)

        if [[ -f "$dir/$filename" ]]; then
            log_skip "$filename"
            continue
        fi

        log_dl "$filename"

        local wget_args=(-q --content-disposition --show-progress
                         --progress=bar:force:noscroll
                         -e dotbytes=4M -P "$dir")

        if [[ -n "${HF_TOKEN:-}" && "$url" =~ huggingface\.co ]]; then
            wget_args+=(--header="Authorization: Bearer $HF_TOKEN")
        elif [[ -n "${CIVITAI_TOKEN:-}" && "$url" =~ civitai\.com ]]; then
            wget_args+=(--header="Authorization: Bearer $CIVITAI_TOKEN")
        fi

        wget "${wget_args[@]}" "$url" 2>&1 \
            || log_warn "Не удалось скачать: $url"
    done
}

function provisioning_clone_comfyui() {
    if [[ ! -d "${COMFYUI_DIR}" ]]; then
        log_info "Клонируем ComfyUI..."
        git clone -q https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}"
    else
        log_skip "ComfyUI уже клонирован"
    fi
    cd "${COMFYUI_DIR}"
}

function provisioning_install_base_reqs() {
    if [[ -f requirements.txt ]]; then
        log_info "Устанавливаем базовые зависимости ComfyUI..."
        pip install --no-cache-dir --root-user-action=ignore -q -r requirements.txt
        log_info "Базовые зависимости установлены"
    fi
}

function provisioning_install_custom_nodes() {
    log_info "Скачиваем архив кастомных нодов..."
    cd "${WORKSPACE}"

    wget -q --show-progress --progress=bar:force:noscroll \
        ${HF_TOKEN:+--header="Authorization: Bearer $HF_TOKEN"} \
        "https://huggingface.co/wissxi/Wan_2.2_Ki4ra/resolve/main/custom_nodes.zip" \
        -O custom_nodes.zip 2>&1

    log_info "Распаковываем кастомные ноды..."
    unzip -o -q custom_nodes.zip -d /
    rm -f custom_nodes.zip
    log_info "Кастомные ноды установлены"
}

function provisioning_install_pip_requirements() {
    log_info "Скачиваем requirements.txt..."
    cd "${WORKSPACE}"

    wget -q \
        ${HF_TOKEN:+--header="Authorization: Bearer $HF_TOKEN"} \
        "https://huggingface.co/wissxi/Wan_2.2_Ki4ra/resolve/main/requirements.txt" \
        -O requirements_custom.txt

    log_info "Устанавливаем pip-зависимости..."
    pip install --no-cache-dir --root-user-action=ignore -q -r requirements_custom.txt
    rm -f requirements_custom.txt
    log_info "Pip-зависимости установлены"
}

function provisioning_start() {
    START_TIME=$(date +%s)

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}  ${BOLD}Ki4ra Template  —  Wan 2.2${RESET}"
    echo -e "${CYAN}║${RESET}  Платформа : ${BOLD}${PLATFORM}${RESET}"
    echo -e "${CYAN}║${RESET}  Начало    : $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${RESET}"

    section "ComfyUI"
    provisioning_clone_comfyui
    provisioning_install_base_reqs

    section "Кастомные ноды"
    provisioning_install_custom_nodes

    section "Pip зависимости"
    provisioning_install_pip_requirements

    section "Загрузка моделей"
    provisioning_get_files "${COMFYUI_DIR}/models/clip"               "${CLIP_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip_vision"        "${CLIP_VISION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae"                "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models"   "${DIFFUSION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/detection"          "${DETECTION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/loras"              "${LORA_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/upscale_models"     "${UPSCALER_MODELS[@]}"

    END_TIME=$(date +%s)
    ELAPSED=$(( END_TIME - START_TIME ))
    MINS=$(( ELAPSED / 60 ))
    SECS=$(( ELAPSED % 60 ))

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}║${RESET}  ${BOLD}✔  Провизионинг завершён${RESET}"
    echo -e "${GREEN}║${RESET}  Время: ${BOLD}${MINS}м ${SECS}с${RESET}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# ─── Запуск ───────────────────────────────────────────────────────────────────

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi

cd "${COMFYUI_DIR}"
