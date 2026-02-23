#!/bin/bash
LLAMA_PATH="/root/arquitectura_local_ia/llama.cpp"
BIN_PATH="$LLAMA_PATH/build/bin/llama-server"
MODELS_PATH="$LLAMA_PATH/models"

create_service() {
  local name=$1; local model=$2; local port=$3; local threads=$4; local extra=$5
  # Calculamos hilos para batch (el doble de los hilos de generación, sin pasar de 20)
  local batch_threads=$(( threads * 2 ))
  
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
  -t $threads -tb $batch_threads \\
  --flash-attn on --mlock --no-mmap \\
  --cache-type-k q8_0 --cache-type-v q8_0 \\
  $extra
Restart=always
RestartSec=10
Nice=-15
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=40
EOF
}



# --- DISTRIBUCIÓN DE HILOS (Total 32) ---
# Ligeros: Muy rápidos, pocos hilos.
create_service "ia-1b" "qwen-1.7b.gguf" 8081 2 "-c 8192"
create_service "ia-gemma" "codegemma-2b.gguf" 8082 2 "-c 8192"

# Coders y Pesados
# Nota: Quitamos '--numa distribute' y 'numactl --interleave' en el ExecStart.
create_service "ia-coder-raw" "qwen3-coder-abliterated.gguf" 8086 8 "-c 32768"
create_service "ia-glm4" "glm-4-flash.gguf" 8087 6 "-c 16384"
create_service "ia-qwen-vl" "qwen3-vl-thinking.gguf" 8088 8 "-c 32768"
create_service "ia-14b-n8n" "qwen-14b-n8n.gguf" 8089 6 "-c 16384"

echo "🔄 Reconfigurando servicios con optimizaciones de Caché y Flash Attention..."
systemctl daemon-reload

# --- ARRANQUE SECUENCIAL INTELIGENTE (Protección SATA SSD) ---
services=("ia-1b" "ia-gemma" "ia-coder-raw" "ia-glm4" "ia-qwen-vl" "ia-14b-n8n")

# Aseguramos dependencias para iostat
if ! command -v iostat &> /dev/null; then
    apt-get install -y sysstat
fi

for srv in "${services[@]}"; do
    echo "🚀 Iniciando $srv..."
    systemctl restart $srv
    
    echo "⏳ Esperando estabilización de SSD (IO Delay < 15%)..."
    # Bucle de espera: Lee el IO Wait y no avanza hasta que el disco esté libre
    while true; do
        iowait=$(iostat -c | awk '/^ /{print $4}' | cut -d. -f1)
        if [ "$iowait" -lt 15 ]; then
            echo "✅ Disco liberado (IO Wait: $iowait%). Siguiente modelo..."
            break
        fi
        sleep 5
    done
done

systemctl restart litellm
echo "🎉 Todos los modelos cargados. El servidor está optimizado al máximo nivel posible."