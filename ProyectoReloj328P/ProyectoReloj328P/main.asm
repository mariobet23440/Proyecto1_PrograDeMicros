/*
PROGRAMACIÓN DE MICROCONTROLADORES
PROYECTO 1 - RELOJ DIGITAL
DESCRIPCIÓN: Reloj que muestra fecha y hora con modo de configuración de alarma.
FECHA DE ENTREGA: 21 de marzo de 2025
*/

/*
ENSAYO DE RECONSTRUCCIÓN
Para probar el correcto funcionamiento de las distintas partes del código, integraremos el código original
(La última versión) un módulo a la vez.
1. Multiplexado
2. Interrupts por PC
*/

/* 
VERSIÓN 1 - SÓLO MULTIPLEXADO
- ¿Qué se esperaría?: Los cuatro displays deberían mostrar el mismo número.
- ¿Funciona?: Si

VERSIÓN 2 - MULTIPLEXADO + MÁQUINA DE ESTADOS
- ¿Qué se esperaría? Los cuatro displays muestran un número cualquiera al mismo tiempo.
  Si se presiona uno de los botones de cambio de modo los LEDs cambian. Sin MODE_OUTPUT
- ¿Funciona? Sí. Las transiciones entre LEDs y la alarma de prueba funcionan bien

VERSIÓN 3 - MOSTRAR SALIDAS SEGÚN MODO Y LOOKUP TABLE
- Todavía no configuramos el incremento automático de unidades de tiempo (Con TIMER1). 
  Introducimos los registros MINUTE_COUNT, HOUR_COUNT, DAY_COUNT, MONTH_COUNT. La idea es que
  el programa muestre cada número en el display correspondiente.
+ AQUÍ SE OBSERVARON PROBLEMAS. Los dos displays muestran el indicador de días.
+ La lookup table parece funcionar correctamente (Muestra los números correctos).
+ Se procederá a revisar el selector de salidas según modo
*/

// --------------------------------------------------------------------
// | DIRECTIVAS DEL ENSAMBLADOR                                       |
// --------------------------------------------------------------------
; Iniciar el código
.cseg		
.org	0x0000
	RJMP	START

; Interrupciones PIN CHANGE
.org PCI0addr
	RJMP PCINT_ISR		; Vector de interrupción de Pin Change

; Interrupciones por overflow de TIMER0 (Modo Normal)
.org OVF0addr				; Vector de interrupción para TIMER0_OVF
    RJMP TIMER0_ISR			; Saltar a la rutina de interrupción

// --------------------------------------------------------------------
// | DEFINICIONES DE REGISTROS DE USO COMÚN Y CONSTANTES DE ASSEMBLER |
// --------------------------------------------------------------------

// Constantes para Timer0
.equ	PRESCALER0 = (1<<CS01) | (1<<CS00)				; Prescaler de TIMER0 (1024)
.equ	TIMER_START0 = 236								; Valor inicial del Timer0 (1.25 ms)

// Estados de Máquina de estados finitos
.equ	S0 = 0X00					; MostrarHora
.equ	S1 = 0X01					; CambiarMinutos
.equ	S2 = 0X02					; CambiarHora
.equ	S3 = 0X04					; MostrarFecha
.equ	S4 = 0X08					; CambiarDias
.equ	S5 = 0X10					; CambiarMeses
.equ	S6 = 0X20					; ModoAlarma
.equ	S7 = 0X40					; AlarmaMinutos
.equ	S8 = 0X80					; AlarmaHoras
; Observe que el registro que almacena el estado es ONE-HOT

// Bits para comparar con máquina de estados
.equ	S1B = 0
.equ	S2B = 1
.equ	S3B = 2
.equ	S4B = 3
.equ	S5B = 4
.equ	S6B = 5
.equ	S7B = 6
.equ	S8B = 7

; Nótese que S0 = 0x00 y todos los bits están apagados, sus comparaciones son diferentes

// Constantes de Lookup Table
.equ	T0 = 0b1110111
.equ	T1 = 0b1000100
.equ	T2 = 0b1101011
.equ	T3 = 0b1101101
.equ	T4 = 0b1011100
.equ	T5 = 0b0111101
.equ	T6 = 0b0111111
.equ	T7 = 0b1100100
.equ	T8 = 0b1111111
.equ	T9 = 0b1111100 

// R16 y R17 quedan como registros temporales

// Registros auxiliares
.def	MINUTE_COUNT = R18
.def	HOUR_COUNT = R19
.def	DAY_COUNT = R20
.def	MONTH_COUNT = R21
.def	OUT_PORTD = R22									; Salida de PORTD
.def	MUX_SIGNAL = R23								; Salida de PORTC (Multiplexado de señal)
.def	STATE = R24										; Registro de Estado
.def	NEXT_STATE = R25								; Registro de estado siguiente

// --------------------------------------------------------------------
// | TABLAS															  |
// --------------------------------------------------------------------
// Definir la tabla en la memoria FLASH (Números del 1 al 10 en display de 7 segmentos)
.org	0x500
TABLA:
	.db T0, T0, T0, T1, T0, T2, T0, T3, T0, T4, T0, T5, T0, T6, T0, T7, T0, T8, T0, T9
	.db T1, T0, T1, T1, T1, T2, T1, T3, T1, T4, T1, T5, T1, T6, T1, T7, T1, T8, T1, T9
	.db T2, T0, T2, T1, T2, T2, T2, T3, T2, T4, T2, T5, T2, T6, T2, T7, T2, T8, T2, T9
	.db T3, T0, T3, T1, T3, T2, T3, T3, T3, T4, T3, T5, T3, T6, T3, T7, T3, T8, T3, T9
	.db T4, T0, T4, T1, T4, T2, T4, T3, T4, T4, T4, T5, T4, T6, T4, T7, T4, T8, T4, T9
	.db T5, T0, T5, T1, T5, T2, T5, T3, T5, T4, T5, T5, T5, T6, T5, T7, T5, T8, T5, T9

// --------------------------------------------------------------------
// | SETUP															  |
// --------------------------------------------------------------------
START:
	// - CONFIGURACIÓN DE LA PILA - 
	// Hacemos que el puntero de la pila apunte hacia el final de la RAM
	LDI		R16, LOW(RAMEND)
	OUT		SPL, R16
	LDI		R16, HIGH(RAMEND)
	OUT		SPH, R16

	// - INICIALIZACIÓN DE TABLAS -
	LDI		ZL, LOW(TABLA << 1)
	LDI		ZH, HIGH(TABLA << 1)
	LPM		OUT_PORTD, Z
	OUT		PORTD, OUT_PORTD
	
	// - CONFIGURACIÓN DE PINES -
	// Configurar los pines PB1-PB4 de PORTB como entradas (Habilitar pull-ups)
	LDI		R16, (1 << PB0) | (1 << PB1)  | (1 << PB2) | (1 << PB3)
	OUT		PORTB, R16

	// Configurar los pines PB4 y PB5 como salidas
	LDI		R16, (1 << PB4) | (1 << PB5)
	OUT		DDRB, R16
	CBI		PORTB, PB5

	// Configurar todos los pines de PORTC como salidas
	LDI		R16, 0XFF
	OUT		DDRC, R16
	LDI		R16, 0X00
	OUT		PORTC, R16

	// Configurar los pines de PORTD como salidas
	LDI		R16, 0XFF
	OUT		DDRD, R16
	LDI		R16, 0XFF
	OUT		PORTD, R16

	// - CONFIGURACIÓN DEL RELOJ DE SISTEMA - (fclk = 1 MHz)
	LDI		R16, (1 << CLKPCE)
	STS		CLKPR, R16
	LDI		R16, (1 << CLKPS2)
	STS		CLKPR, R16
	
	// - HABILITACIÓN DE INTERRUPCIONES PC -
	LDI		R16, (1 << PCIE0)													// Habilitar interrupciones PC en PORTB
	STS		PCICR, R16
	LDI		R16, (1 << PCINT0) | (1 << PCINT1) | (1 << PCINT2) | (1 << PCINT3)	// Habilitar Interrupciones en PB0-PB3
	STS		PCMSK0, R16	

	// - REINICIAR TIMERS Y HABILITAR INTERRUPCIONES POR OVERFLOWS DE TIMERS -
	CALL	RESET_TIMER0
	
	// - HABILITACIÓN DE INTERRUPCIONES GLOBALES -
	SEI

	// - INICIALIZACIÓN DE REGISTROS -
	LDI		MUX_SIGNAL, 0X01
	;CLR		MINUTE_COUNT
	;CLR		HOUR_COUNT
	;LDI		DAY_COUNT, 1
	;LDI		MONTH_COUNT,1
	LDI		STATE, 1										; Registro de Estado
	LDI		NEXT_STATE, 1									; Registro de Estado Siguiente

	// PRUEBA DE DISPLAYS (QUITAR)
	LDI		MINUTE_COUNT, 0X01
	LDI		HOUR_COUNT, 0X02
	LDI		DAY_COUNT, 0X03
	LDI		MONTH_COUNT,0X04

	


// --------------------------------------------------------------------
// | MAINLOOP														  |
// --------------------------------------------------------------------
MAINLOOP:
	// Realizar multiplexado de señales a transistores
	CALL	MULTIPLEXADO
	CALL	MODE_OUTPUT
	RJMP	MAINLOOP

// --------------------------------------------------------------------
// | RUTINA NO DE INTERRUPCIÓN 1 - MULTIPLEXADO						  |
// --------------------------------------------------------------------
// - ACTUALIZAR DISPLAYS -
MULTIPLEXADO:
	CPI		MUX_SIGNAL, 0X01
	BREQ	MUX_DISPLAY4
	CPI		MUX_SIGNAL, 0X02
	BREQ	MUX_DISPLAY3
	CPI		MUX_SIGNAL, 0X04
	BREQ	MUX_DISPLAY2
	CPI		MUX_SIGNAL, 0X08
	BREQ	MUX_DISPLAY1


// ENCENDER DISPLAYS
MUX_DISPLAY4:
	SBI		PORTC, PC0
	CBI		PORTC, PC1
	CBI		PORTC, PC2
	CBI		PORTC, PC3
	RET

MUX_DISPLAY3:
	CBI		PORTC, PC0
	SBI		PORTC, PC1
	CBI		PORTC, PC2
	CBI		PORTC, PC3
	RET

MUX_DISPLAY2:
	CBI		PORTC, PC0
	CBI		PORTC, PC1
	SBI		PORTC, PC2
	CBI		PORTC, PC3
	RET

MUX_DISPLAY1:
	CBI		PORTC, PC0
	CBI		PORTC, PC1
	CBI		PORTC, PC2
	SBI		PORTC, PC3
	RET

// --------------------------------------------------------------------
// | RUTINA NO DE INTERRUPCIÓN 2 - MODE_OUTPUT						  |
// --------------------------------------------------------------------
// CONFIGURACION DE MODOS (Escoger salidas)
MODE_OUTPUT:
	CPI		MUX_SIGNAL, 0X01
	BREQ	MODE_DISPLAY43
	CPI		MUX_SIGNAL, 0X02
	BREQ	MODE_DISPLAY43
	CPI		MUX_SIGNAL, 0X04
	BREQ	MODE_DISPLAY21
	CPI		MUX_SIGNAL, 0X08
	BREQ	MODE_DISPLAY21

// Salida a displays 4 y 3
MODE_DISPLAY43:
	// MostrarHoras (S0)
	CPI		STATE, S0
	BREQ	SHOW_HOURS

	// CambiarMinutos (S1)
	CPI		STATE, S1
	BREQ	SHOW_HOURS

	// CambiarHoras (S2)
	CPI		STATE, S2
	BREQ	SHOW_HOURS
	
	// MostrarFecha (S3)
	CPI		STATE, S3
	BREQ	SHOW_MONTH

	// CambiarDia (S4)
	CPI		STATE, S4
	BREQ	SHOW_MONTH

	// CambiarMes (S5)
	CPI		STATE, S5
	BREQ	SHOW_MONTH

	// ModoAlarma (S6)
	CPI		STATE, S6
	BREQ	SHOW_HOURS

	// AlarmaMinutos (S7)
	CPI		STATE, S7
	BREQ	SHOW_HOURS

	// AlarmaHoras (S8)
	CPI		STATE, S8
	BREQ	SHOW_HOURS
	RET

SHOW_HOURS:
	MOV		OUT_PORTD, HOUR_COUNT

SHOW_MONTH:
	MOV		OUT_PORTD, MONTH_COUNT

// Salida a displays 2 Y 1
MODE_DISPLAY21:
	// MostrarHoras (S0)
	CPI		STATE, S0
	BREQ	SHOW_MINUTES

	// CambiarMinutos (S1)
	CPI		STATE, S1
	BREQ	SHOW_MINUTES

	// CambiarHoras (S2)
	CPI		STATE, S2
	BREQ	SHOW_MINUTES
	
	// MostrarFecha (S3)
	CPI		STATE, S3
	BREQ	SHOW_DAY

	// CambiarDia (S4)
	CPI		STATE, S4
	BREQ	SHOW_DAY

	// CambiarMes (S5)
	CPI		STATE, S5
	BREQ	SHOW_DAY

	// ModoAlarma (S6)
	CPI		STATE, S6
	BREQ	SHOW_MINUTES

	// AlarmaMinutos (S7)
	CPI		STATE, S7
	BREQ	SHOW_MINUTES

	// AlarmaHoras (S8)
	CPI		STATE, S8
	BREQ	SHOW_MINUTES
	RET

SHOW_MINUTES:
	MOV		OUT_PORTD, MINUTE_COUNT

SHOW_DAY:
	MOV		OUT_PORTD, DAY_COUNT


// --------------------------------------------------------------------
// | RUTINA NO DE INTERRUPCIÓN 3 - LOOKUP_TABLE						  |
// --------------------------------------------------------------------

// LOOKUP TABLE
LOOKUP_TABLE:
	// Guardar bit 7 de PORTD en el Bit T del SREG
	IN		R17, PORTD
	BST		R17, 7
	
	// Sacar dato de tabla
	LDI		ZH, HIGH(TABLA<<1)
	LDI		ZL, LOW(TABLA<<1)

	// Obtener dirección de tabla (Duplicando OUT_PORTD)
	MOV		R16, OUT_PORTD
	ADD		R16, OUT_PORTD

	// Incrementar puntero Z en 2*OUT_PORTD
	ADD		ZL, R16

	// Sacar el primer dígitooo
	LPM		R16, Z
	
	// Si MUX_SIGNAL es 0x04 o 0x08 sacar el siguiente número
	SBRC	MUX_SIGNAL, 1
	INC		ZL
	SBRC	MUX_SIGNAL, 3
	INC		ZL
	LPM		R16, Z

	// Cargar bit de leds intermitentes
	BLD		R16, 7

	// Mostrar en PORTD
	OUT		PORTD, R16

	RET

// --------------------------------------------------------------------
// | RUTINA NO DE INTERRUPCIÓN 3 - Reinicio de TIMER0				  |
// --------------------------------------------------------------------
// Reiniciar Timer0
RESET_TIMER0:
	// - PRESCALER Y VALOR INICIAL -
	LDI     R16, PRESCALER0
    OUT     TCCR0B, R16
    LDI     R16, TIMER_START0
    OUT     TCNT0, R16

	// - HABILITACIÓN DE INTERRUPCIONES POR OVERFLOW EN TIMER0 -
	LDI		R16, (1 << TOIE0)
	STS		TIMSK0, R16
	RET

// --------------------------------------------------------------------
// | RUTINAS DE INTERRUPCIÓN POR CAMBIO EN PINES					  |															  |
// --------------------------------------------------------------------
PCINT_ISR:
	PUSH	R16
	IN		R16, SREG
	PUSH	R16

	// Cambiar Estados con PB0
	SBIS	PINB, PB0
	JMP		NEXT_STATE_LOGIC_PB0

	// Cambiar Estados con PB1
	SBIS	PINB, PB1
	JMP		NEXT_STATE_LOGIC_PB1
	
	// Si no se detecta nada, ir al final
	JMP		END_PC_ISR
	
// Lógica de Siguiente estado si se presiona PB0
NEXT_STATE_LOGIC_PB0:
	// CambiarMinutos (S1) -> MostrarHora (S0)
	SBRC	STATE, S1B
	LDI		NEXT_STATE, S0

	// CambiarHoras (S2) -> MostrarHora (S0)
	SBRC	STATE, S2B
	LDI		NEXT_STATE, S0

	// MostrarFecha (S3) -> ModoAlarma (S6)
	SBRC	STATE, S3B
	LDI		NEXT_STATE, S6

	// CambiarDías (S4) -> MostrarFecha (S3)
	SBRC	STATE, S4B
	LDI		NEXT_STATE, S3

	// CambiarMeses (S5) -> MostrarFecha (S3)
	SBRC	STATE, S5B
	LDI		NEXT_STATE, S3

	// MostrarFecha (S3) -> ModoAlarma (S6)
	SBRC	STATE, S3B
	LDI		NEXT_STATE, S6

	// ModoAlarma (S6) -> MostrarHora (S0)
	SBRC	STATE, S6B
	LDI		NEXT_STATE, S0

	// AlarmaMinutos (S7) -> ModoAlarma (S6)
	SBRC	STATE, S7B
	LDI		NEXT_STATE, S6

	// AlarmaHoras (S8) -> ModoAlarma (S6)
	SBRC	STATE, S8B
	LDI		NEXT_STATE, S6

	// MostrarHoras (S0) -> MostrarFecha (S3)
	CPI		STATE, 0
	BRNE	INTERMEDIATE_JUMP_PCINT_ISR
	LDI		NEXT_STATE, S3
	JMP		COPY_NEXT_STATE

// Salto intermedio por limitaciones de BRNE
INTERMEDIATE_JUMP_PCINT_ISR:
	JMP		COPY_NEXT_STATE
	

// Lógica de Siguiente estado si se presiona PB1
NEXT_STATE_LOGIC_PB1:
	// CambiarMinutos (S1) -> CambiarHoras (S2)
	SBRC	STATE, S1B
	LDI		NEXT_STATE, S2

	// CambiarHoras (S2) -> MostrarHora (S0)
	SBRC	STATE, S2B
	LDI		NEXT_STATE, S0

	// MostrarFecha (S3) -> CambiarDias (S4)
	SBRC	STATE, S3B
	LDI		NEXT_STATE, S4

	// CambiarDías (S4) -> CambiarMeses (S5)
	SBRC	STATE, S4B
	LDI		NEXT_STATE, S5

	// CambiarMeses (S5) -> MostrarFecha (S3)
	SBRC	STATE, S5B
	LDI		NEXT_STATE, S3

	// ModoAlarma (S6) -> AlarmaMinutos (S7)
	SBRC	STATE, S6B
	LDI		NEXT_STATE, S7

	// AlarmaMinutos (S7) -> AlarmaHoras (S8)
	SBRC	STATE, S7B
	LDI		NEXT_STATE, S8

	// AlarmaHoras (S8) -> ModoAlarma (S6)
	SBRC	STATE, S8B
	LDI		NEXT_STATE, S6

	// MostrarHoras (S0) -> CambiarMinutos (S2)
	CPI		STATE, S0
	BRNE	COPY_NEXT_STATE
	LDI		NEXT_STATE, S1
	JMP		COPY_NEXT_STATE

// Copiar NEXT_STATE en STATE
COPY_NEXT_STATE:
	MOV		STATE, NEXT_STATE
	JMP		ENCENDER_LEDS_MODO

ENCENDER_LEDS_MODO:
	// MostrarHoras (S0)
	CPI		STATE, S0
	BREQ	ENCENDER_LED_HORA

	// CambiarMinutos (S1)
	CPI		STATE, S1
	BREQ	PRUEBA_ALARMA			; ENCENDER_LED_HORA

	// CambiarHoras (S2)
	CPI		STATE, S2
	BREQ	PRUEBA_ALARMA			; ENCENDER_LED_HORA

	// MostrarFecha (S3)
	CPI		STATE, S3
	BREQ	ENCENDER_LED_FECHA

	// CambiarDias (S4)
	CPI		STATE, S4
	BREQ	PRUEBA_ALARMA			; ENCENDER_LED_FECHA

	// CambiarMeses (S5)
	CPI		STATE, S5
	BREQ	PRUEBA_ALARMA			; ENCENDER_LED_FECHA

	// Modo Alarma (S6)
	CPI		STATE, S6
	BREQ	ENCENDER_LED_ALARMA

	// AlarmaMinutos (S7)
	CPI		STATE, S7
	BREQ	PRUEBA_ALARMA			; ENCENDER_LED_ALARMA

	// AlarmaHoras (S8)
	CPI		STATE, S8
	BREQ	PRUEBA_ALARMA			; ENCENDER_LED_ALARMA

	// Salir (Si es que algo falla, por alguna razón)
	JMP		END_PC_ISR

// Encender LEDs Indicadores de Modo
ENCENDER_LED_HORA:
	SBI		PORTC, PC4
	CBI		PORTC, PC5
	CBI		PORTB, PB4
	CBI		PORTB, PB5		; Quitar esta línea en el programa final
	JMP		END_PC_ISR

ENCENDER_LED_FECHA:
	CBI		PORTC, PC4
	SBI		PORTC, PC5
	CBI		PORTB, PB4
	CBI		PORTB, PB5		; Quitar esta línea en el programa final
	JMP		END_PC_ISR

ENCENDER_LED_ALARMA:
	CBI		PORTC, PC4
	CBI		PORTC, PC5
	SBI		PORTB, PB4
	CBI		PORTB, PB5		; Quitar esta línea en el programa final
	JMP		END_PC_ISR

// Quitar esto en el programa final
PRUEBA_ALARMA:
	SBI		PORTB, PB5

END_PC_ISR:
	POP		R16
	OUT		SREG, R16
	POP		R16
	RETI


// --------------------------------------------------------------------
// | RUTINAS DE INTERRUPCIÓN CON TIMER0								  |
// --------------------------------------------------------------------
TIMER0_ISR:
	PUSH	R16
	IN		R16, SREG
	PUSH	R16

	// Reiniciar el TIMER0
	CALL	RESET_TIMER0

	// Rotar señal de multiplexado a la izquierda (Valor Inicial 0X01)
	ROL		MUX_SIGNAL

	// Aplicar máscara para PC1-PC3
	ANDI	MUX_SIGNAL, 0X0F

	// Si el bit de encendido desaparece, reiniciar
	CPI		MUX_SIGNAL, 0
	BRNE	END_T0_ISR
	LDI		MUX_SIGNAL, 0X01
	RJMP	END_T0_ISR


END_T0_ISR:
	POP		R16
	OUT		SREG, R16
	POP		R16
	RETI