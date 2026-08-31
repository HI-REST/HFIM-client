#include "hfim.h"

//UART
#define UART_BASE     0x10000000UL
#define UART_THR  (*(volatile uint8_t *)(UART_BASE + 0))
#define UART_RBR  (*(volatile uint8_t *)(UART_BASE + 0))
#define UART_LSR  (*(volatile uint8_t *)(UART_BASE + 5))
#define UART_LSR_THRE 0x20
#define UART_LSR_DR   0x01

// QEMU EXIT
#define QEMU_EXIT_BASE    0x100000UL
#define QEMU_EXIT         (*(volatile uint32_t *)(QEMU_EXIT_BASE))
#define QEMU_EXIT_SUCCESS 0x5555
#define QEMU_EXIT_FAILURE 0x3333


void uart_putc(char c) {
    while (!(UART_LSR & UART_LSR_THRE));
    UART_THR = c;
}

// qemu_exit removed — using fim_exit() from SDK instead

void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

char uart_getc() {
    while (!(UART_LSR & UART_LSR_DR));
    return UART_RBR;
}

void uart_put_float(float val) {
    union {
        unsigned char bytes[4];
        float value;
    } data;

    data.value = val;
    uart_putc(data.bytes[0]);
    uart_putc(data.bytes[1]);
    uart_putc(data.bytes[2]);
    uart_putc(data.bytes[3]);
}

float uart_get_float() {
    union {
        unsigned char bytes[4];
        float value;
    } data;

    data.bytes[0] = uart_getc();
    data.bytes[1] = uart_getc();
    data.bytes[2] = uart_getc();
    data.bytes[3] = uart_getc();

    return data.value;
}

// CONTROL
#define NUM_JOINTS 6
#define NUM_ACTIVE_JOINTS 4
#define DT (1.0f / 1000.0f)

// Ganancias PID para TORQUE CONTROL
static const float KP_TORQUE[NUM_ACTIVE_JOINTS] = {5.0f, 3.0f, 0.8f, 1.0f};
static const float KI_TORQUE[NUM_ACTIVE_JOINTS] = {2.0f, 2.0f, 2.0f, 0.0f};
static const float KD_TORQUE[NUM_ACTIVE_JOINTS] = {0.155f, 0.15f, 0.02f, 0.0f};

// Posiciones objetivo
/* 
Al convertir un robot de 6GDL en un robot planar, perdemos GDL, por lo tanto
solo podemos mover las articulaciones 1, 2, 4, 5 (teniendo en cuenta que
la primera es 0). Es decir, la articulación 0 y 3 siempre tienen que ser igual a 0
*/

// Observable state — FIM reads these for SDC detection
volatile float tau[NUM_ACTIVE_JOINTS];
volatile float posicion[NUM_ACTIVE_JOINTS];
volatile float target_position[NUM_ACTIVE_JOINTS];
volatile int loop_count;

int main() {

    // Inicializar objetivo ANTES del handshake: asi target_position vive en .bss
    // desde el primer instante y no solo despues del ACK (la espera del ACK domina
    // el icount, por eso una inyeccion por icount lo encontraba todavia a 0).
    target_position[0] = 0.0f;
    target_position[1] = 2.8f;
    target_position[2] = -0.3f;
    target_position[3] = 0.0f;
    loop_count = 0;
    
    for(int i = 0; i < NUM_ACTIVE_JOINTS; ++i) {
        posicion[i] = 0.0;
        tau[i] = 0.0;
    }

    // Esperar ACK inicial de Python
    char ack = uart_getc();
    while (ack != 'K') {
        ack = uart_getc();
    }

    float integral[NUM_ACTIVE_JOINTS]   = {0};
    float prev_error[NUM_ACTIVE_JOINTS] = {0};
    const int MAX_TAU = 5;
    int target_alcanzado = 0;
    int movimiento_terminado = 0;

    fim_init();

    do {
        
        for (int i = 0; i < NUM_ACTIVE_JOINTS; i++) {
            posicion[i] = uart_get_float();
        }

        for (int i = 0; i < NUM_ACTIVE_JOINTS; i++) {
            double diff = posicion[i] - target_position[i];
            if (diff < 0) 
                diff = -diff;
            if (diff >= 0.01f) {
                target_alcanzado = 0;
                break;
            }
            target_alcanzado = 1;
        }
        
        if (target_alcanzado) {
            uart_putc('S');
            fim_exit(0);
        } else {
            uart_putc('K');
        }
        
        fim_breakpoint();
        // Cálculo de valor de control por cada articulación activa
        for (int i = 0; i < NUM_ACTIVE_JOINTS; i++) {
            // Diferencia entre posición objetivo y posición real
            float error      = target_position[i] - posicion[i];
            
            // Cálculo de la componente integral acumulativa
            integral[i] += error * DT;
            
            // Cálculo del componente derivativo
            float derivative = (error - prev_error[i]) / DT;
            
            // Almacenamos el nuevo error
            prev_error[i] = error;
            
            // Cálculo del valor de control
            tau[i] = KP_TORQUE[i] * error + KI_TORQUE[i] * integral[i] + KD_TORQUE[i] * derivative;
            
            // Comprobación de que el valor de control no supere un máximo de seguridad
            if (tau[i] > MAX_TAU) {
                tau[i] = MAX_TAU;
            }
        }
    
        for (int i = 0; i < NUM_ACTIVE_JOINTS; i++) {
            uart_put_float(tau[i]);
        }

        loop_count++;        

    } while (!target_alcanzado);
}

