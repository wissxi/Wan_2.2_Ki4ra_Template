#!/bin/bash
set -e
source /venv/main/bin/activate

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== Start provisioning ==="

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
    echo "Downloading ${#files[@]} file(s) → $dir..."

    for url in "${files[@]}"; do
        echo "→ $url"
        local auth_header=""
        if [[ -n "$HF_TOKEN" && "$url" =~ huggingface\.co ]]; then
            auth_header="--header=Authorization: Bearer $HF_TOKEN"
        elif [[ -n "$CIVITAI_TOKEN" && "$url" =~ civitai\.com ]]; then
            auth_header="--header=Authorization: Bearer $CIVITAI_TOKEN"
        fi
        wget $auth_header -nc --content-disposition --show-progress -e dotbytes=4M -P "$dir" "$url" \
            || echo " [!] Download failed: $url"
    done
}

function provisioning_clone_comfyui() {
    if [[ ! -d "${COMFYUI_DIR}" ]]; then
        echo "Cloning ComfyUI..."
        git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}"
    fi
    cd "${COMFYUI_DIR}"
}

function provisioning_install_base_reqs() {
    if [[ -f requirements.txt ]]; then
        pip install --no-cache-dir -r requirements.txt
    fi
}

function provisioning_install_custom_nodes() {
    echo "=== Installing custom nodes from archive ==="
    cd "${WORKSPACE}"

    wget -q --show-progress \
        ${HF_TOKEN:+--header="Authorization: Bearer $HF_TOKEN"} \
        "https://huggingface.co/wissxi/Wan_2.2_Ki4ra/resolve/main/custom_nodes.zip" \
        -O custom_nodes.zip

    unzip -o custom_nodes.zip -d /
    rm -f custom_nodes.zip
    echo "Custom nodes installed."
}

function provisioning_install_pip_requirements() {
    echo "=== Installing pip requirements ==="
    cd "${WORKSPACE}"

    wget -q \
        ${HF_TOKEN:+--header="Authorization: Bearer $HF_TOKEN"} \
        "https://huggingface.co/wissxi/Wan_2.2_Ki4ra/resolve/main/requirements.txt" \
        -O requirements_custom.txt

    pip install --no-cache-dir -r requirements_custom.txt
    rm -f requirements_custom.txt
    echo "Pip requirements installed."
}

function provisioning_start() {
    provisioning_clone_comfyui
    provisioning_install_base_reqs
    provisioning_install_custom_nodes
    provisioning_install_pip_requirements

    provisioning_get_files "${COMFYUI_DIR}/models/clip"               "${CLIP_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip_vision"        "${CLIP_VISION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae"                "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models"   "${DIFFUSION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/detection"          "${DETECTION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/loras"              "${LORA_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/upscale_models"     "${UPSCALER_MODELS[@]}"

    echo "=== Provisioning complete ==="
}

# ─── Запуск ───────────────────────────────────────────────────────────────────

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi

echo "Script done!"
cd "${COMFYUI_DIR}"
