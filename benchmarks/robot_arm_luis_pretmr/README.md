# robot_arm_luis_pretmr

Benchmark de replica para comparar metodos de inyeccion (2026-08-30).
El main.c viene del snapshot de una campana PRE-TMR de Luis
(robot_arm_riscv64_20260701_180224_342551_96d9bc), sin las copias
_mod_1/_mod_2 de la redundancia.

Diferencias con el robot_arm estandar: DT = 1/1000 (no 1/100), otras
ganancias del PID, y el brazo tarda 3475 ticks en converger en vez de 94.
Por eso su feeder usa max_iterations = 4000 y el timeout sube a 300 s.

## El simulador no esta versionado aqui

Las mallas del URDF pesan ~6.7 MB y ya viven en benchmarks/robot_arm.
Antes de lanzar una campana con este benchmark, copialas:

    cp -r benchmarks/robot_arm/simulador_enrique benchmarks/robot_arm_luis_pretmr/
    # y el feeder de 4000 iteraciones que necesita este main.c:
    scp <servidor>:/srv/fim/users/luis/benchmarks/robot_arm/simulador_enrique/pybullet_feeder.py \
        benchmarks/robot_arm_luis_pretmr/simulador_enrique/

## Que mide cada uno

- **robot_arm_luis_pretmr**: su fim.yaml tal cual (ancla fim_breakpoint,
  memory_access_size 4). Reproduce sus numeros de julio dentro de +-2.2%.
- **robot_arm_luis_enhanced**: mismo main.c con el metodo determinista
  (marcador fuera, injection_pc_exclude, testigos, clasificador de
  trayectorias, memory_access_size 1).

Resultados en docs/deterministic-campaigns.md.
