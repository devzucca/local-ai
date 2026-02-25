#!/bin/bash
# check_ia_health.sh - Senior AI Infrastructure Diagnostics
# Optimizado para Dual Xeon & LiteLLM Gateway

# --- CONFIGURACIÓN ---
MODELS_PATH="/root/arquitectura_local_ia/llama.cpp/models"
LITELLM_PORT=4000
LITELLM_KEY="sk-DAzu.0429*"

# Definir servicios activos
declare -A MODELS=( ["8087"]="GLM-4-Flash" )
declare -A FILES=( ["8087"]="glm-4-flash.gguf" )
declare -A LITE_MAP=( ["glm-4-flash"]="8087" )

# Colores y Formato
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[0;34m'; NC='\033[0m'
CHECK="✅"; BOLD="\033[1m"

clear
echo -e "${BOLD}${B}=== AI INFRASTRUCTURE HEALTH CHECK ===${NC}"
echo -e "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')\n"

# --- 1. HARDWARE ---
echo -e "${G}${BOLD}[1/5] RECURSOS DEL SISTEMA${NC}"
row_format="%-20s %-40s %-10s\n"
read load1 load5 load15 <<< $(cut -d' ' -f1,2,3 /proc/loadavg)
# iowait robusto
iowait=$(iostat -c 1 2 | awk '/^ /{wait=$4} END {print wait}')
printf "$row_format" "CPU Load (1m/5m):" "$load1 / $load5" "L:$load1"
printf "$row_format" "IO Wait:" "$iowait%" "[OK]"
free -h | awk '/Mem/{printf "%-20s %-40s %-10s\n", "RAM Actual:", "Total: "$2" | Usada: "$3" | Libre: "$4, "[OK]"}'
echo "--------------------------------------------------------------------------------"

# --- 2. DOCKER SERVICES ---
echo -e "\n${G}${BOLD}[2/5] ESTADO DE DOCKER (GATEWAY)${NC}"
docker_format="%-20s %-15s %-25s %-10s\n"
printf "$BOLD$docker_format$NC" "CONTAINER" "STATUS" "HEALTH" "PORTS"
for container in litellm-proxy litellm-db; do
    status=$(docker inspect -f '{{.State.Status}}' $container 2>/dev/null || echo "NON-EXISTENT")
    health=$(docker inspect -f '{{.State.Health.Status}}' $container 2>/dev/null || echo "N/A")
    ports=$(docker inspect -f '{{range $p, $conf := .NetworkSettings.Ports}}{{$p}} {{end}}' $container 2>/dev/null)
    
    color=$G; [ "$status" != "running" ] && color=$R
    h_color=$G; [[ "$health" == "unhealthy" ]] && h_color=$R; [[ "$health" == "starting" ]] && h_color=$Y
    
    printf "$docker_format" "$container" "$(echo -e "${color}$status${NC}")" "$(echo -e "${h_color}$health${NC}")" "$ports"
done
echo "--------------------------------------------------------------------------------"

# --- 3. BACKEND (LLAMA.CPP) ---
echo -e "\n${G}${BOLD}[3/5] BACKEND DE INFERENCIA (HOST)${NC}"
printf "$BOLD%-8s %-20s %-12s %-10s %-12s$NC\n" "PORT" "MODELO" "RAM(RSS)" "THREADS" "ESTADO"
for port in "${!MODELS[@]}"; do
    pid=$(lsof -t -i:$port 2>/dev/null)
    m_name=${MODELS[$port]}
    
    if [ -z "$pid" ]; then
        printf "%-8s %-20s %-12s %-10s ${R}%-12s${NC}\n" "$port" "$m_name" "0" "-" "OFFLINE"
    else
        threads=$(ps -o nlwp= -p $pid | tr -d ' ')
        rss_mb=$(($(ps -o rss= -p $pid) / 1024))
        f_path="$MODELS_PATH/${FILES[$port]}"
        status="${G}✅ READY${NC}"
        
        # Verificar si está cargando
        if curl -s -f --max-time 1 http://127.0.0.1:$port/health | grep -q "Loading model"; then
            status="${Y}⏳ LOADING${NC}"
        fi
        printf "%-8s %-20s %-12s %-10s %-12b\n" "$port" "$m_name" "${rss_mb}MB" "$threads" "$status"
    fi
done
echo "--------------------------------------------------------------------------------"

# --- 4. BENCHMARKS ---
echo -e "\n${G}${BOLD}[4/5] BENCHMARK DE INFERENCIA (DIRECTO)${NC}"
for port in "${!MODELS[@]}"; do
    if (echo > /dev/tcp/127.0.0.1/$port) >/dev/null 2>&1; then
        start=$(date +%s.%N)
        res=$(curl -s -f -X POST http://127.0.0.1:$port/v1/chat/completions \
            -H "Content-Type: application/json" \
            -d '{"messages":[{"role":"user","content":"Respond exactly with OK"}],"max_tokens":5}' --max-time 30)
        end=$(date +%s.%N)
        
        if [[ $res == *"choices"* ]]; then
            duration=$(echo "$end - $start" | bc)
            tokens=$(echo "$res" | jq -r '.usage.completion_tokens')
            tps=$(echo "scale=2; $tokens / $duration" | bc)
            echo -e "PORT $port [${MODELS[$port]}]: ${G}ONLINE${NC} -> ${Y}${tps} t/s${NC} (Latencia: ${duration}s)"
        else
            echo -e "PORT $port [${MODELS[$port]}]: ${R}FAILED / RETRYING${NC}"
        fi
    fi
done

# --- 5. GATEWAY TEST ---
echo -e "\n${G}${BOLD}[5/5] GATEWAY LITELLM END-TO-END${NC}"
if curl -s --max-time 2 http://127.0.0.1:$LITELLM_PORT/health > /dev/null; then
    for m in "${!LITE_MAP[@]}"; do
        printf "Testing routing for %-20s " "$m..."
        res_proxy=$(curl -s -X POST http://127.0.0.1:$LITELLM_PORT/v1/chat/completions \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $LITELLM_KEY" \
            -d "{\"model\": \"$m\", \"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}], \"max_tokens\":2}" --max-time 15)
        
        if [[ $res_proxy == *"choices"* ]]; then
            echo -e "${G}✅ ROUTED${NC}"
        else
            echo -e "${R}❌ FAILED${NC}"
            # Debug info
            if [[ $res_proxy == *"error"* ]]; then
                echo -e "   Error: $(echo $res_proxy | jq -r '.error.message' 2>/dev/null || echo $res_proxy)"
            fi
        fi
    done
else
    echo -e "LiteLLM Gateway: ${R}UNREACHABLE${NC} (Check: docker logs litellm-proxy)"
fi

echo -e "\n${B}${BOLD}=== DIAGNÓSTICO FINALIZADO ===${NC}\n"
