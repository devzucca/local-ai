#!/bin/bash
# ia_optimizar_senior.sh - Optimización Profunda para Dual Xeon
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# Rango de hilos a probar (Basado en 8 machos físicos por CPU)
THREAD_TESTS=(6 8 10 12)

# Modelos a optimizar
MODELS=("glm4" "14b-n8n" "coder-raw")

echo -e "${G}🚀 Iniciando Auditoría de Rendimiento Senior...${NC}"

for model_alias in "${MODELS[@]}"; do
    service="ia-$model_alias"
    echo -e "\n${Y}🔍 Optimizando $service...${NC}"
    
    best_t=8
    best_tps=0
    
    for t in "${THREAD_TESTS[@]}"; do
        # 1. Configurar hilos y reiniciar
        service_file="/etc/systemd/system/$service.service"
        [ -f "$service_file" ] || continue
        
        # Ajustamos -t y -tb (batch = t * 1.5 o t * 2 suele ser ideal)
        tb=$(( t * 2 ))
        [ $tb -gt 16 ] && tb=16 # Límite razonable para no saturar memoria
        
        sed -i "s/-t [0-9]\+ -tb [0-9]\+/-t $t -tb $tb/" "$service_file"
        systemctl daemon-reload
        systemctl restart "$service"
        
        # 2. Esperar disponibilidad del API
        port=$(grep -oP '(?<=--port )\d+' "$service_file")
        echo -n "   Prueba con $t hilos (-tb $tb): "
        
        # Espera de hasta 120s para modelos pesados
        ready=0
        for i in {1..60}; do
            if curl -s http://127.0.0.1:$port/v1/models &>/dev/null; then ready=1; break; fi
            sleep 2
        done
        
        if [ $ready -eq 1 ]; then
            # Benchmark serio: 32 tokens para estabilizar
            res=$(curl -s http://127.0.0.1:$port/v1/chat/completions \
                -H "Content-Type: application/json" \
                -d '{"messages":[{"role":"user","content":"¿Cual es el sentido de la vida?"}],"max_tokens":32}' \
                --max-time 180)
            
            tps=$(echo "$res" | jq -r '.timings.predicted_per_second // 0')
            echo -e "${G}$tps t/s${NC}"
            
            if (( $(echo "$tps > $best_tps" | bc -l) )); then
                best_tps=$tps
                best_t=$t
            fi
        else
            echo -e "${R}TIMEOUT${NC}"
        fi
    done
    
    echo -e "${Y}📊 Configuración ganadora para $service: $best_t hilos${NC}"
    sed -i "s/-t [0-9]\+ -tb [0-9]\+/-t $best_t -tb $((best_t * 2))/" "/etc/systemd/system/$service.service"
    systemctl daemon-reload
    systemctl restart "$service"
done

echo -e "\n${G}✅ Optimización finalizada. Sistema equilibrado.${NC}"
