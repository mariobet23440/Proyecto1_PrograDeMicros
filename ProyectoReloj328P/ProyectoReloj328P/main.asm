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
.equ	TIMER_START0 = 1 ;251								; Valor inicial del Timer0 (2 ms)

// Constantes para Timer1
.equ	PRESCALER1 = (1<<CS11) | (1<<CS10)				; Prescaler de TIMER1 (1024)
.equ	TIMER_START1 = 6942								; Valor inicial de TIMER1 (60s)

// Constantes para Timer2
.equ	PRESCALER2 = (1<<CS22) | (1<<CS21) | (1<<CS20)	; Prescaler de TIMER2 (En este caso debe ser de 1024)
.equ	TIMER_START2 = 158								; Valor inicial de TIMER2 (1 ms)

// R16 y R17 quedan como registros temporales

// Contadores de Tiempo
.def	MINUTE_COUNT = R18								; Contador de Minutos
.def	HOUR_COUNT = R19								; Contador de Horas
.def	DAY_COUNT = R20									; Contador de Días
.def	MONTH_COUNT = R21								; Contador de Meses
.def	T2_AUX_COUNT = R22								; Contador auxiliar de TIMER2

// Registros auxiliares
.def	OUT_PORTD = R23									; Salida de PORTD
.def	MUX_SIGNAL = R24								; Salida de PORTC (Multiplexado de señal)

// --------------------------------------------------------------------
// | TABLAS															  |
// --------------------------------------------------------------------

// Definir la tabla en la memoria FLASH (Números del 1 al 10 en display de 7 segmentos)
.org	0x100
TABLA:
    .db 0xE7, 0x21, 0xCB, 0x6B, 0x2D, 0x6E, 0xEE, 0x23, 0xEF, 0x2F

// --------------------------------------------------------------------
// | SETUP															  |
// --------------------------------------------------------------------

START:
	// - CONFIGURACIÓN DE LA PILA - 
	LDI		R16, LOW(RAMEND)
	OUT		SPL, R16
	LDI		R16, HIGH(RAMEND)
	OUT		SPH, R16

	// - INICIALIZACIÓN DE TABLAS -
	LDI		ZL, LOW(TABLA * 2)
	LDI		ZH, HIGH(TABLA * 2)
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
	LDI		R16, (1 << CLKPS3)
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

// --------------------------------------------------------------------
// | MAINLOOP														  |
// --------------------------------------------------------------------

MAINLOOP:
	RJMP	MAINLOOP

// --------------------------------------------------------------------
// | RUTINAS NO DE INTERRUPCIÓN										  |
// --------------------------------------------------------------------

// - REINICIAR TIMER0 -
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

	// Sacar la señal de multiplexado en PORTC
	OUT		PORTC, MUX_SIGNAL

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

	// Incrementar el contador de minutos
	INC		MINUTE_COUNT

	// Si el contador de minutos no excede 60 salir
	CPI		MINUTE_COUNT, 60
	BRLO	END_T1_ISR

	// Si han pasado más de 60 minutos, reiniciar e incrementar contador de horas
	CLR		MINUTE_COUNT
	INC		HOUR_COUNT

	// Si el contador de horas no excede 24 salir
	CPI		HOUR_COUNT, 24
	BRLO	END_T1_ISR

	// Si han pasado más de 24 horas, reiniciar e incrementar el contador de días
	CLR		HOUR_COUNT
	RJMP	AUMENTAR_DIA

AUMENTAR_DIA:
	// Aumentar el contador de días
	INC		DAY_COUNT

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
	// Verificar si el contador pasa de 28
	CPI		DAY_COUNT, 28
    BRLO	END_T1_ISR

	// Si han pasado más de 28 días, reiniciar a uno
    LDI		DAY_COUNT, 1
    RJMP	AUMENTAR_MES

MESES_30:
	// Verificar si el contador pasa de 30
	CPI		DAY_COUNT, 31
    BRLO	END_T1_ISR

	// Si han pasado más de 30 días, reiniciar a uno
    LDI		DAY_COUNT, 1
    RJMP	AUMENTAR_MES

MESES_31:
	// Verificar si el contador pasa de 31
	CPI		DAY_COUNT, 32
    BRLO	END_T1_ISR

	// Si han pasado más de 31 días, reiniciar a uno
    LDI		DAY_COUNT, 1
    RJMP	AUMENTAR_MES

// Aumentar mes y reiniciar si pasan más de 12 meses
AUMENTAR_MES:
	INC		MONTH_COUNT
	CPI		MONTH_COUNT, 12
	BRLO	END_T1_ISR
	LDI		MONTH_COUNT, 1
	RJMP	END_T1_ISR

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
	CPI		T2_AUX_COUNT, 6
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
