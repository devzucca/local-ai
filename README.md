# Arquitectura Local de IA

Este repositorio contiene los scripts de automatización y despliegue para una arquitectura local de IA optimizada para servidores Xeon Dual-Socket.

## Archivos Principales

- `setup_ia.sh`: Script de instalación inicial (dependencias, compilación de llama.cpp, descarga de modelos y LiteLLM).
- `create_services.sh`: Genera y activa los servicios de systemd para cada modelo con optimizaciones de memoria (mlock, numactl).
- `check_ia_health.sh`: Sistema de monitoreo avanzado (RAM, IO Wait, Benchmark de inferencia y estado de LiteLLM).
- `ia`: Herramienta CLI para gestionar modelos (`ia lista`, `ia subir`, `ia bajar`, `ia estado`, `ia test`).

## Uso

1. Clonar el repositorio.
2. Ejecutar `./setup_ia.sh` para la instalación base.
3. Ejecutar `./create_services.sh` para configurar los servicios.
4. Usar el comando `ia` para gestionar los modelos.
