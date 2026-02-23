#!/bin/bash
set -e

BASE_DIR="/root/arquitectura_local_ia/llama.cpp"
MODELS_DIR="$BASE_DIR/models"

echo "🛠️ 1. Dependencias..."
apt update && apt install -y build-essential cmake git wget curl python3-pip python3-venv numactl bc

echo "🏗️ 2. Compilación..."
mkdir -p $MODELS_DIR
cd /root/arquitectura_local_ia
[ -d "llama.cpp" ] || git clone https://github.com/ggerganov/llama.cpp.git
cd $BASE_DIR
mkdir -p build && cd build
cmake .. -DGGML_NATIVE=ON
cmake --build . --config Release -j $(nproc)

echo "📥 3. Descarga de Modelos..."
cd $MODELS_DIR

download_verified() {
    local file=$1
    local url=$2
    local expected_min_size=${3:-1000000} # Por defecto 1MB
    
    if [ ! -f "$file" ] || [ $(stat -c%s "$file") -lt $expected_min_size ]; then
        echo "Descargando $file..."
        curl -L -O "$file" "$url"
    else
        echo "✅ $file ya existe y tiene un tamaño válido."
    fi
}

# Modelos Ligeros
download_verified "qwen-1.7b.gguf" "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"
download_verified "codegemma-2b.gguf" "https://huggingface.co/bartowski/codegemma-2b-GGUF/resolve/main/codegemma-2b-Q4_K_M.gguf"

# Modelos Coder y Vision
download_verified "qwen3-coder-abliterated.gguf" "https://huggingface.co/bartowski/huihui-ai_Qwen3-Coder-Next-abliterated-GGUF/resolve/main/huihui-ai_Qwen3-Coder-Next-abliterated-Q4_K_M.gguf?download=true"
download_verified "glm-4-flash.gguf" "https://huggingface.co/unsloth/GLM-4.7-Flash-GGUF/resolve/main/GLM-4.7-Flash-Q4_K_M.gguf?download=true"
download_verified "qwen3-vl-thinking.gguf" "https://huggingface.co/unsloth/Qwen3-VL-32B-Thinking-GGUF/resolve/main/Qwen3-VL-32B-Thinking-UD-Q6_K_XL.gguf?download=true"
download_verified "qwen-14b-n8n.gguf" "https://huggingface.co/mbakgun/Qwen2.5-Coder-14B-n8n-Workflow-Generator/resolve/main/gguf/qwen25-coder-14b-n8n-q4_k_m.gguf?download=true"

# Proyectores de Visión (Necesarios para procesar imágenes)
# Usamos repositorios públicos verificados para evitar errores 401
download_verified "ia-qwen-vl_mmproj.gguf" "https://huggingface.co/lmstudio-community/Qwen2-VL-7B-Instruct-GGUF/resolve/main/qwen2-vl-7b-instruct-mmproj-f16.gguf"
download_verified "ia-glm4_mmproj.gguf" "https://huggingface.co/lmstudio-community/glm-4v-9b-GGUF/resolve/main/glm-4v-9b-mmproj-f16.gguf"

echo "🏗️ 4. LiteLLM Setup..."
cd /root
[ -d "litellm_env" ] || python3 -m venv litellm_env
./litellm_env/bin/pip install litellm[proxy]

cat << 'EOF' > /root/litellm_config.yaml
model_list:
  - model_name: qwen-general
    litellm_params:
      model: openai/qwen-1.7b
      api_base: http://127.0.0.1:8081/v1
      api_key: "not-needed"
  - model_name: codegemma
    litellm_params:
      model: openai/codegemma
      api_base: http://127.0.0.1:8082/v1
      api_key: "not-needed"
  - model_name: qwen-coder-raw
    litellm_params:
      model: openai/qwen-coder-abliterated
      api_base: http://127.0.0.1:8086/v1
      api_key: "not-needed"
  - model_name: glm-4-flash
    litellm_params:
      model: openai/glm-4-flash
      api_base: http://127.0.0.1:8087/v1
      api_key: "not-needed"
  - model_name: qwen3-vl
    litellm_params:
      model: openai/qwen3-vl
      api_base: http://127.0.0.1:8088/v1
      api_key: "not-needed"
  - model_name: qwen-14b-n8n
    litellm_params:
      model: openai/qwen-14b-n8n
      api_base: http://127.0.0.1:8089/v1
      api_key: "not-needed"

general_settings:
  database_url: "postgresql://litellm_admin:litellm_pass@127.0.0.1:5433/litellm_db"
  master_key: "sk-DAzu.0429*"
  ui_inherited_access: true
  store_model_in_db: true

litellm_settings:
  set_verbose: false
  drop_params: true

EOF
echo "✅ Instalación y descarga completas."