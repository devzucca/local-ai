#!/bin/bash
LLAMA_PATH="/root/arquitectura_local_ia/llama.cpp"
BIN_PATH="$LLAMA_PATH/build/bin/llama-server"
MODELS_PATH="$LLAMA_PATH/models"

create_service() {
    local name=$1
    local model=$2
    local port=$3
    local threads=$4
    local ck=$5
    local cv=$6
    local extra=$7
    local template_file=$8

    # Si hay template, usamos el flag jinja explícito con prefijo file://
    local template_flags=""
    if [ ! -z "$template_file" ]; then
        template_flags="--jinja --chat-template file://$template_file"
    else
        template_flags="--chat-template auto"
    fi

    cat << EOM > /etc/systemd/system/$name.service
[Unit]
Description=IA Service $name
After=network.target

[Service]
Type=simple
WorkingDirectory=$LLAMA_PATH
# Comando en una sola línea para evitar errores de escape. Forzamos RAM con --no-mmap y --mlock
ExecStart=$BIN_PATH --host 0.0.0.0 -m $MODELS_PATH/$model --port $port -t $threads --no-mmap --mlock --numa distribute --flash-attn on --cache-type-k $ck --cache-type-v $cv $template_flags $extra
Restart=always
RestartSec=10
KillMode=process
EOM
}

# GLM-4: Forzamos f16 en caché para precisión de herramientas y carga total de 20GB en RAM
# GLM-4.7-Flash: Configuración optimizada para Agentic Tool-Calling
create_service "ia-glm4" "glm-4-flash.gguf" 8087 12 "f16" "f16" \
"--special --repeat-penalty 1.0 --temp 0.7 --top-p 1.0 --min-p 0.01 -c 8192 --chat-template-tool-calls" \
"/root/arquitectura_local_ia/llama.cpp/models/glm4_template.jinja"

systemctl daemon-reload
systemctl restart ia-glm4
systemctl restart litellm
echo "✅ Backend reiniciado. Verifica RAM con 'free -h' ahora mismo."
