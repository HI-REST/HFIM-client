# Campanas de referencia del robot_arm

Cada fichero es una campana lista para lanzar. Todas usan el reloj
determinista (PC, K): repetir una campana con la misma semilla reproduce el
mismo resultado, fila a fila.

## Como se lanzan

Estos ficheros NO son fim.yaml: son overlays de campana. El fim.yaml del
benchmark ya trae el modo determinista, asi que para el caso normal basta:

    ./run.sh benchmarks/robot_arm --fault register -n 100 --seed 1234

Para un barrido por variable (fallos de memoria sobre un simbolo concreto),
usa el batch:

    ./run.sh --batch benchmarks/robot_arm/campaigns/sweep_4_targets.yaml

## El barrido de 4 objetivos (resultados locales, 2026-08-29)

n=100 por objetivo, semilla 1234, fallos de memoria byte a byte. Dos
columnas: lo que dice el inyector (SDC) y lo que dice la trayectoria del
brazo (el clasificador post-mortem).

| Objetivo | SDC | Dano fisico real | Sobreestimacion |
|---|---:|---:|---|
| target_position | 88% | 22% | 4.0x |
| posicion | 25% | 8% | 3.1x |
| tau | 21% | 2% | 10.5x |
| loop_count | 100% | **0%** | infinita |

Lectura: la tasa de SDC sobreestima el dano fisico entre 3x e infinito segun
la variable. loop_count es el caso limite: las 100 inyecciones cambian el
observable y las 100 trayectorias son perfectas, porque el contador de
vueltas no participa del lazo de control. Solo target_position (el objetivo
del movimiento) es realmente critico.

Numeros medidos en el banco local (QEMU upstream, maquina virt). Pendiente
de repetir en el servidor (C906/Xuantie).
