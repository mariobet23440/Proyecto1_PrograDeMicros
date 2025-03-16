;
; ProyectoReloj328P.asm
;
; Created: 20/02/2025 22:52:46
; Author : Mario Alejandro Betancourt Franco
;


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

; Interrupciones por overflow de TIMER1 (Modo Normal)
.org OVF1addr				; Vector de interrupción para TIMER1_OVF
    RJMP TIMER1_ISR			; Saltar a la rutina de interrupción

; Interrupciones por overflow de TIMER2 (Modo Normal)
.org OVF2addr				; Vector de interrupción para TIMER2_OVF
    RJMP TIMER2_ISR			; Saltar a la rutina de interrupción

// --------------------------------------------------------------------
// | DEFINICIONES DE REGISTROS DE USO COMÚN Y CONSTANTES DE ASSEMBLER |
// --------------------------------------------------------------------

// Constantes para Timer0
.equ	PRESCALER0 = (1<<CS01) | (1<<CS00)				; Prescaler de TIMER0 (1024)
.equ	TIMER_START0 = 251								; Valor inicial del Timer0 (10 ms)

// Constantes para Timer1
.equ	PRESCALER1 = (1<<CS11) | (1<<CS10)				; Prescaler de TIMER1 (1024)
.equ	TIMER_START1 = 65438							; Valor inicial de TIMER1 (60s)
; Para hacer pruebas usar 65438
; Para medición de tiempo real usar 6942

// Constantes para Timer2
.equ	PRESCALER2 = (1<<CS22) | (1<<CS21) | (1<<CS20)	; Prescaler de TIMER2 (1024)
.equ	TIMER_START2 = 158								; Valor inicial de TIMER2 (100 ms)

// Máquina de estados finitos
.equ	MINUTE_CHANGE =	0X01							; Estado CambiarMinutos
.equ	HOUR_CHANGE = 0X02 								; Estado CambiarHoras
.equ	DAY_CHANGE = 0X04								; Estado CambiarDias
.equ	MONTH_CHANGE = 0X08								; Estado CambiarMeses
.equ	ALARM_STATE	= 0X10								; Modo Alarma

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


// Registros inferiores
.def	T2_AUX_COUNT = R2

// R16, R17 se utilizan como registros de uso común

// Registros auxiliares
.def	MINUTE_COUNT = R18
.def	HOUR_COUNT = R19
.def	DAY_COUNT = R20
.def	MONTH_COUNT = R21
.def	OUT_PORTD = R22									; Salida de PORTD
.def	MUX_SIGNAL = R23								; Salida de PORTC (Multiplexado de señal)
.def	STATE = R24										; Registro de Estado

// No podemos usar registros más allá del 24 porque son los punteros X, Y y Z

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
// ¿Quién tiene tiempo para hacer tantas comparaciones? Mejor hagamos una buena lookup table
// Importante observar que para apuntar a las unidades es necesario usar el doble de un registro


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
	LDI		R16, (1 << PB0) | (1 << PB1)  | (1 << PB2) | (1 << PB3) | (1 << PB4)
	OUT		PORTB, R16

	// Configurar el pin PB5 como una salida
	LDI		R16, (1 << PB5)
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
	LDI		R16, (1 << PCIE0)																	// Habilitar interrupciones PC en PORTB
	STS		PCICR, R16
	LDI		R16, (1 << PCINT0) | (1 << PCINT1) | (1 << PCINT2) | (1 << PCINT3) | (1 << PCINT4)	// Habilitar Interrupciones en PB1-PB4
	STS		PCMSK0, R16
	
	// - REINICIAR TIMERS Y HABILITAR INTERRUPCIONES POR OVERFLOWS DE TIMERS -
	CALL	RESET_TIMER0
	CALL	RESET_TIMER1
	CALL	RESET_TIMER2

	// - HABILITACIÓN DE INTERRUPCIONES GLOBALES -
	SEI

	// - INICIALIZACIÓN DE REGISTROS -
	CLR		T2_AUX_COUNT
	LDI		MUX_SIGNAL, 0X01
	CLR		MINUTE_COUNT
	CLR		HOUR_COUNT
	LDI		DAY_COUNT, 1
	LDI		MONTH_COUNT,1
	LDI		STATE, 1										; Registro de Estado

// --------------------------------------------------------------------
// | MAINLOOP														  |
// --------------------------------------------------------------------

MAINLOOP:
	// Realizar multiplexado de señales a transistores
	CALL	MULTIPLEXADO
	OUT		PORTC, R16
	CALL	MODE_OUTPUT
	CALL	LOOKUP_TABLE

	// Mostrar número en PORTD
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
	LDI		R16, 0X01
	RET

MUX_DISPLAY3:
	LDI		R16, 0X02
	RET

MUX_DISPLAY2:
	LDI		R16, 0X04
	RET

MUX_DISPLAY1:
	LDI		R16, 0X08
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
	SBRC	STATE, 0
	MOV		OUT_PORTD, HOUR_COUNT
	SBRC	STATE, 1
	MOV		OUT_PORTD, HOUR_COUNT
	SBRC	STATE, 2
	MOV		OUT_PORTD, MONTH_COUNT
	SBRC	STATE, 3
	MOV		OUT_PORTD, MONTH_COUNT
	RET

// Salida a displays 2 y 1
MODE_DISPLAY21:
	SBRC	STATE, 1
	MOV		OUT_PORTD, MINUTE_COUNT
	SBRC	STATE, 2
	MOV		OUT_PORTD, MINUTE_COUNT
	SBRC	STATE, 3
	MOV		OUT_PORTD, DAY_COUNT
	SBRC	STATE, 4
	MOV		OUT_PORTD, DAY_COUNT
	RET

; Si se debe mostrar la salida en DISPLAYS 3 y 4, mostrar horas y meses
; Si se debe mostrar la salida en DISPLAYS 2 y 1, mostrar minutos y días

// --------------------------------------------------------------------
// | RUTINA NO DE INTERRUPCIÓN 2 - LOOKUP_TABLE						  |
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
// | RUTINAS NO DE INTERRUPCIÓN 3-5 : REINICIO DE TIMERS			  |
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


// - REINICIAR TIMER1 -
RESET_TIMER1:
	// - PRESCALER Y VALOR INICIAL -
	LDI     R16, PRESCALER1
    STS     TCCR1B, R16
    LDI     R16, LOW(TIMER_START1)
    STS     TCNT1L, R16
	LDI     R16, HIGH(TIMER_START1)
    STS     TCNT1H, R16

	// - HABILITACIÓN DE INTERRUPCIONES POR OVERFLOW EN TIMER1 -
	LDI		R16, (1 << TOIE1)
	STS		TIMSK1, R16
	RET

// - REINICIAR TIMER2 -
RESET_TIMER2:
	// - PRESCALER Y VALOR INICIAL -
	LDI     R16, PRESCALER2
    STS     TCCR2B, R16
    LDI     R16, TIMER_START2
    STS     TCNT2, R16

	// - HABILITACIÓN DE INTERRUPCIONES POR OVERFLOW EN TIMER2 -
	LDI		R16, (1 << TOIE2)
	STS		TIMSK2, R16
	RET

// --------------------------------------------------------------------
// | RUTINAS DE INTERRUPCIÓN POR CAMBIO EN PINES					  |															  |
// --------------------------------------------------------------------
PCINT_ISR:
	PUSH	R16
	IN		R16, SREG
	PUSH	R16

	// Decrementar contador con botones
	SBIC	PINB, PB0
	JMP		DECREMENTAR_PC

	// Incrementar contador con botones
	SBIC	PINB, PB1
	JMP		INCREMENTAR_PC

	// Cambiar Estados
	SBIC	PINB, PB2
	JMP		CAMBIAR_ESTADOS
	
	// Si no se detecta nada, ir al final
	JMP		END_PC_ISR
	

CAMBIAR_ESTADOS:
	// Leer el SREG
	IN		R16, SREG

	// Cambiar Minutos -> Cambiar Horas
	CPI		STATE, MINUTE_CHANGE
	SBRC	R16, SREG_Z
	LDI		STATE, HOUR_CHANGE

	// Cambiar Horas -> Cambiar Dias
	CPI		STATE, HOUR_CHANGE
	SBRC	R16, SREG_Z
	LDI		STATE, DAY_CHANGE

	// Cambiar Dias -> Cambiar Meses
	CPI		STATE, DAY_CHANGE
	SBRC	R16, SREG_Z
	LDI		STATE, MONTH_CHANGE

	// Cambiar Meses -> Alarma
	CPI		STATE, MONTH_CHANGE
	SBRC	R16, SREG_Z
	LDI		STATE, ALARM_STATE

	// Alarma -> Cambiar Minutos
	CPI		STATE, ALARM_STATE
	SBRC	R16, SREG_Z
	LDI		STATE, MINUTE_CHANGE
	
	// Saltar al final
	RJMP	END_PC_ISR

DECREMENTAR_PC:
	JMP		END_PC_ISR

INCREMENTAR_PC:
	JMP		END_PC_ISR

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


// --------------------------------------------------------------------
// | RUTINAS DE INTERRUPCIÓN CON TIMER1								  |
// --------------------------------------------------------------------
TIMER1_ISR:
	PUSH	R16
	IN		R16, SREG
	PUSH	R16

	// Reiniciar el TIMER1
	CALL	RESET_TIMER1

	// INCREMENTO DE MINUTOS
	INC		MINUTE_COUNT
	
	// INCREMENTO DE HORAS
	// Si MINUTE_TENS es mayor o igual a 60, limpiarlo e incrementar HOUR_COUNT
	CPI		MINUTE_COUNT, 60
	BRLO	INTERMEDIATE_JUMP1
	CLR		MINUTE_COUNT
	INC		HOUR_COUNT

	// INCREMENTO DE DÍAS
	// Si HOUR_COUNT es mayor o igual a 24, limpiarlo e incrementar DAY_COUNT
	CPI		HOUR_COUNT, 24
	BRLO	INTERMEDIATE_JUMP1
	CLR		HOUR_COUNT
	INC		DAY_COUNT

	// Si el número de días no excede 28 (El mínimo para cambiar de mes) salir para
	// evitar comparaciones innecesarias
	CPI		DAY_COUNT, 28
	BRLO	INTERMEDIATE_JUMP1
		
	// Pero, si ese no es el caso
	// "Goku eta vaina se puso seria"
	// Si el número de días excede 29, incrementar mes (Muchas comparaciones)
	RJMP	COMPARACIONES_MES

INTERMEDIATE_JUMP1:
	JMP	END_T1_ISR

	
// COMPARACIONES PARA INCREMENTO DE MESES
COMPARACIONES_MES:	
	// Verificar si el mes es febrero
	CPI		MONTH_COUNT, 2
	BREQ	FEBRERO

	// Meses con 30 días (abril, junio, septiembre, noviembre)
    CPI		MONTH_COUNT, 4
    BREQ	MESES_30
    CPI		MONTH_COUNT, 6
    BREQ	MESES_30
    CPI		MONTH_COUNT, 9
    BREQ	MESES_30
    CPI		MONTH_COUNT, 11
    BREQ	MESES_30

	// Si el mes no es de 30 días y no es febrero, es de 31 días
	RJMP	MESES_31

FEBRERO:
	// Verificar si el contador de días pasa de 28
	CPI		DAY_COUNT, 28
    BRLO	END_T1_ISR

	// Si han pasado más de 28 días, reiniciar contador de días
    LDI		DAY_COUNT, 1
    RJMP	AUMENTAR_MES

MESES_30:
	// Verificar si el contador de días pasa de 30
	CPI		DAY_COUNT, 30
    BRLO	END_T1_ISR

	// Si han pasado más de 30 días, reiniciar contador de días
    LDI		DAY_COUNT, 1
	RJMP	AUMENTAR_MES

MESES_31:
	// Verificar si el contador pasa de 31
	CPI		DAY_COUNT, 31
    BRLO	END_T1_ISR

	// Si han pasado más de 31 días, reiniciar contadores de días
    LDI		DAY_COUNT, 1
	RJMP	AUMENTAR_MES


// AUMENTAR MES
AUMENTAR_MES:
	// Aumentar contador de meses
	INC		MONTH_COUNT
	CPI		MONTH_COUNT, 12
	BRLO	NO_DICIEMBRE

	// Si las unidades de meses excenden 12, reiniciar ambos contadores
	CPI		MONTH_COUNT, 12
	LDI		MONTH_COUNT, 1
	RJMP	END_T1_ISR

// Meses que NO son diciembre
NO_DICIEMBRE:
	INC		MONTH_COUNT
	BRLO	END_T1_ISR


// Terminar Rutina de Interrupción
END_T1_ISR:
	POP		R16
	OUT		SREG, R16
	POP		R16
	RETI


// --------------------------------------------------------------------
// | RUTINAS DE INTERRUPCIÓN CON TIMER2								  |
// --------------------------------------------------------------------
TIMER2_ISR:
	PUSH	R16
	IN		R16, SREG
	PUSH	R16

	// Reiniciar el TIMER2
	CALL	RESET_TIMER2

	

	// Incrementar el contador auxiliar hasta 6
	INC		T2_AUX_COUNT
	
	// Leer T2_AUX_COUNT y comparar
	MOV		R16, T2_AUX_COUNT 
	CPI		R16, 6
	BRLO	END_T2_ISR

	// Si el contador rebasa 6, reiniciar y alternar el bit PD7
	CLR		T2_AUX_COUNT		; Guardar el reinicio del contador
	IN		R16, PORTD			; Leer estado actual de PORTD
	LDI		R17, (1 << PD7)
    EOR		R16, R17			; Alternar bit PD7 (D7)
    OUT		PORTD, R16			; Escribir nuevo estado
	

// Terminar Rutina de Interrupción
END_T2_ISR:
	POP		R16
	OUT		SREG, R16
	POP		R16
	RETI
