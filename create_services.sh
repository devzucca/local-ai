#!/bin/bash
LLAMA_PATH="/root/arquitectura_local_ia/llama.cpp"
BIN_PATH="$LLAMA_PATH/build/bin/llama-server"
MODELS_PATH="$LLAMA_PATH/models"

create_service() {
  local name=$1; local model=$2; local port=$3; local threads=$4; local extra=$5
  
  # Configuramos el chat-template por defecto si no se pasa en extra
  local template_flag="--chat-template auto"
  if [[ "$extra" == *"--chat-template"* ]]; then
    template_flag=""
  fi

  cat << EOF > /etc/systemd/system/$name.service
[Unit]
Description=IA Service $name
After=network.target

[Service]
Type=simple
WorkingDirectory=$LLAMA_PATH
ExecStart=/usr/bin/numactl --interleave=all $BIN_PATH \\
  -m $MODELS_PATH/$model \\
  --port $port \\
  -t $threads -tb 16 \\
  --numa distribute \\
  --prio 2 \\
  --poll 50 \\
  -b 2048 -ub 512 \\
  --cont-batching \\
  --kv-unified \\
  --flash-attn on --no-mmap \\
  --cache-type-k q4_0 --cache-type-v q4_0 \\
  $template_flag \\
  $extra
Restart=always
RestartSec=15
Nice=-10
LimitMEMLOCK=infinity
LimitNOFILE=65535
TimeoutStartSec=600
EOF
}

# --- DISTRIBUCIÓN DE PRODUCCIÓN ---
# Ligeros (Siempre arriba)
create_service "ia-1b" "qwen-1.7b.gguf" 8081 8 "-c 16384"
create_service "ia-gemma" "codegemma-2b.gguf" 8082 8 "-c 16384"

# Pesados (Ajustado Contexto para Estabilidad)
create_service "ia-coder-raw" "qwen3-coder-abliterated.gguf" 8086 12 "-c 16384"

# GLM-4 Optimización (Intento de rescate con ChatML)
# Añadimos --special para que procese tokens de parada correctamente
create_service "ia-glm4" "glm-4-flash.gguf" 8087 12 "-c 8192 --chat-template chatml --special --min-p 0.05 --temp 0.6"

create_service "ia-qwen-vl" "qwen3-vl-thinking.gguf" 8088 12 "-c 8192"
create_service "ia-14b-n8n" "qwen-14b-n8n.gguf" 8089 12 "-c 16384"

echo "🔄 Reconfigurando arquitectura para máxima estabilidad..."
systemctl daemon-reload

# --- ARRANQUE SECUENCIAL SELECTIVO ---
# Solo arrancamos los ligeros por defecto para que el sistema sea usable de inmediato.
# Los pesados se suben con 'ia subir <nombre>'
services_light=("ia-1b" "ia-gemma")
services_all=("ia-1b" "ia-gemma" "ia-coder-raw" "ia-glm4" "ia-qwen-vl" "ia-14b-n8n")

for srv in "${services_light[@]}"; do
    echo "🚀 Iniciando modelo ligero: $srv..."
    systemctl restart $srv
    sleep 5
done

# Detenemos los pesados para liberar RAM y permitir limpieza de Proxmox
for srv in "ia-coder-raw" "ia-glm4" "ia-qwen-vl" "ia-14b-n8n"; do
    echo "💤 Dejando en standby (ahorro de RAM): $srv"
    systemctl stop $srv
done

systemctl restart litellm
echo "🎉 Todos los modelos cargados. El servidor está optimizado al máximo nivel posible."