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

    # Si se proporciona un template, usamos los flags específicos para cargarlo
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
# Cambia la línea de ExecStart para forzar la carga en RAM
ExecStart=/usr/bin/numactl --interleave=all $BIN_PATH \\
    -m $MODELS_PATH/$model \\
    --port $port \\
    -t $threads --no-mmap \\ # <--- ESTO fuerzo la carga en RAM
    --mlock \\               # <--- Bloquea la RAM para que no se vaya al SWAP
    --numa distribute \\
    --chat-template file://$MODELS_PATH/glm4_template.jinja \\
    $extra
Restart=always
RestartSec=10
KillMode=process
EOM
}

# --- DISTRIBUCIÓN ---
create_service "ia-1b" "qwen-1.7b.gguf" 8081 8 "q4_0" "q4_0" "-c 16384"
create_service "ia-gemma" "codegemma-2b.gguf" 8082 8 "q4_0" "q4_0" "-c 16384"

# GLM-4: Pasamos la ruta del .jinja como octavo parámetro
create_service "ia-glm4" "glm-4-flash.gguf" 8087 12 "f16" "f16" "--special --repeat-penalty 1.0 --temp 0.1 -c 8192" "/root/arquitectura_local_ia/llama.cpp/models/glm4_template.jinja"

create_service "ia-coder-raw" "qwen3-coder-abliterated.gguf" 8086 12 "q4_0" "q4_0" "-c 16384"
create_service "ia-14b-n8n" "qwen-14b-n8n.gguf" 8089 12 "q4_0" "q4_0" "-c 16384"

systemctl daemon-reload
systemctl restart ia-glm4
systemctl restart litellm
echo "✅ Servicios actualizados. Verificando log..."
sleep 2
journalctl -u ia-glm4 -n 20 --no-pager | grep "Chat format"
