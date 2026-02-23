#!/bin/bash
# check_ia_health_v2.sh - Edición Xeon Dual-Socket Optimizado

# --- CONFIGURACIÓN ---
MODELS_PATH="/root/arquitectura_local_ia/llama.cpp/models"
LITELLM_PORT=4000
declare -A MODELS=( ["8081"]="Qwen-1.7b" ["8082"]="CodeGemma-2b" ["8086"]="Qwen-Coder-Raw" ["8087"]="GLM-4-Flash" ["8088"]="Qwen3-VL-Thinking" ["8089"]="Qwen-14B-n8n" )
declare -A FILES=( ["8081"]="qwen-1.7b.gguf" ["8082"]="codegemma-2b.gguf" ["8086"]="qwen3-coder-abliterated.gguf" ["8087"]="glm-4-flash.gguf" ["8088"]="qwen3-vl-thinking.gguf" ["8089"]="qwen-14b-n8n.gguf" )

# Colores
G='\033[0;32m' # Verde
Y='\033[1;33m' # Amarillo
R='\033[0;31m' # Rojo
NC='\033[0m'    # Sin color

echo -e "\n${G}🖥️  [1/5] HARDWARE & CARGA DEL SISTEMA${NC}"
echo "--------------------------------------------------------------------------------"
# CPU Load y IO Wait real
read load1 load5 load15 <<< $(cut -d' ' -f1,2,3 /proc/loadavg)
iowait=$(iostat -c | awk '/^ /{print $4}')
echo -e "Load Average: $load1, $load5, $load15  |  ${Y}IO Wait: $iowait%${NC}"
free -h | awk '/Mem/{printf "RAM: Total %s | Usada %s | Libre %s\n", $2, $3, $4}'
echo "--------------------------------------------------------------------------------"

echo -e "\n${G}📊 [2/5] ESTADO DE DESPLIEGUE (RSS vs GGUF)${NC}"
printf "%-8s %-20s %-12s %-10s %-12s\n" "PORT" "MODELO" "RAM(RSS)" "THREADS" "ESTADO"
echo "--------------------------------------------------------------------------------"

for port in 8081 8082 8086 8087 8088 8089; do
    pid=$(lsof -t -i:$port 2>/dev/null)
    m_name=${MODELS[$port]}
    
    if [ -z "$pid" ]; then
        printf "%-8s %-20s %-12s %-10s ${R}%-12s${NC}\n" "$port" "$m_name" "0" "-" "OFFLINE"
    else
        # Obtener hilos reales y RAM
        threads=$(ps -o nlwp= -p $pid | tr -d ' ')
        rss_mb=$(($(ps -o rss= -p $pid) / 1024))
        
        # Calcular % de carga basado en archivo
        f_path="$MODELS_PATH/${FILES[$port]}"
        if [ -f "$f_path" ]; then
            f_size_mb=$(($(stat -c%s "$f_path") / 1048576))
            pct=$(( rss_mb * 100 / f_size_mb ))
            [ $pct -gt 100 ] && pct=100
            
            if [ $pct -lt 95 ]; then status="${Y}⏳ $pct%${NC}"; else status="${G}✅ OK${NC}"; fi
        else
            status="${R}⚠ NO FILE${NC}"
        fi
        printf "%-8s %-20s %-12s %-10s %-12b\n" "$port" "$m_name" "${rss_mb}MB" "$threads" "$status"
    fi
done

echo -e "\n${G}🚀 [3/5] BENCHMARK DE INFERENCIA (Velocidad Real)${NC}"
echo "--------------------------------------------------------------------------------"
for port in 8081 8082 8086 8087 8088 8089; do
    if (echo > /dev/tcp/127.0.0.1/$port) >/dev/null 2>&1; then
        start=$(date +%s.%N)
        # Usamos 16 tokens (algunos modelos fallan con 10 por bugs internos de parseo)
        res=$(curl -s http://127.0.0.1:$port/v1/chat/completions \
            -H "Content-Type: application/json" \
            -d '{"messages":[{"role":"user","content":"Hi"}],"max_tokens":16}' --max-time 60)
        end=$(date +%s.%N)
        
        if [[ $res == *"choices"* ]]; then
            duration=$(echo "$end - $start" | bc)
            # Extraer tokens reales generados para un cálculo preciso
            tokens=$(echo "$res" | jq -r '.usage.completion_tokens')
            tps=$(echo "scale=2; $tokens / $duration" | bc)
            echo -e "PORT $port [${MODELS[$port]}]: ${G}ONLINE${NC} -> ${Y}${tps} t/s${NC} (Latencia: ${duration}s)"
        else
            echo -e "PORT $port [${MODELS[$port]}]: ${R}ERROR / TIMEOUT${NC}"
            # Debug del error si no es timeout
            if [ ! -z "$res" ]; then echo -e "   ${R}Respuesta: $res${NC}"; fi
        fi
    fi
done

echo -e "\n${G}🌐 [4/5] GATEWAY LITELLM & ROUTING${NC}"
echo "--------------------------------------------------------------------------------"
if curl -s --max-time 5 http://127.0.0.1:$LITELLM_PORT/v1/models > /dev/null; then
    echo -e "LiteLLM Proxy: ${G}ACTIVO${NC} en puerto $LITELLM_PORT"
    printf "%-20s %-15s\n" "MODELO LITELLM" "ESTADO"
    echo "--------------------------------------------------------------------------------"
    
    # Lista de modelos configurados en LiteLLM
    declare -A LITE_MAP=( 
        ["qwen-general"]="8081" ["codegemma"]="8082" ["qwen-coder-raw"]="8086" 
        ["glm-4-flash"]="8087" ["qwen3-vl"]="8088" ["qwen-14b-n8n"]="8089" 
    )

    for m in "qwen-general" "codegemma" "qwen-coder-raw" "glm-4-flash" "qwen3-vl" "qwen-14b-n8n"; do
        res_proxy=$(curl -s http://127.0.0.1:$LITELLM_PORT/v1/chat/completions \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer sk-DAzu.0429*" \
            -d "{\"model\": \"$m\", \"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}], \"max_tokens\":5}" --max-time 30)
        
        if [[ $res_proxy == *"choices"* ]]; then
            printf "%-20s ${G}%-15s${NC}\n" "$m" "✅ OK"
        else
            printf "%-20s ${R}%-15s${NC}\n" "$m" "❌ ERROR"
        fi
    done
else
    echo -e "LiteLLM Proxy: ${R}CAÍDO o SIN RESPUESTA${NC} (Revisa: systemctl status litellm)"
fi

echo -e "\n${G}🔑 [5/5] ACCESO & RESUMEN${NC}"
echo "--------------------------------------------------------------------------------"
IP_IA=$(hostname -I | awk '{print $1}')
echo "Endpoint Local:  http://127.0.0.1:$LITELLM_PORT/v1"
echo "Endpoint Red:    http://$IP_IA:$LITELLM_PORT/v1"
echo "API KEY:          sk-DAzu.0429*"
echo "--------------------------------------------------------------------------------"
