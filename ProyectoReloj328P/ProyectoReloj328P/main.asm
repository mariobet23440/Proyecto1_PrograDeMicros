;
; Lab3_Interrupciones.asm
;
; Created: 20/02/2025 22:52:46
; Author : Mario Alejandro Betancourt Franco
;

; NOTA: De aquí en adelante trabajaré la entrega del POSTLAB

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
.org OVF0addr           ; Vector de interrupción para TIMER0_OVF
    RJMP TIMER0_ISR        ; Saltar a la rutina de interrupción

// --------------------------------------------------------------------
// | DEFINICIONES DE REGISTROS DE USO COMÚN Y CONSTANTES DE ASSEMBLER |
// --------------------------------------------------------------------

// Constantes
.equ	PRESCALER = (1<<CS02) | (1<<CS00)	; Prescaler de TIMER0 (En este caso debe ser de 1024)
.equ	TIMER_START = 178					; Valor inicial del Timer0 (para un delay de 5 ms)
.equ	OVF_TOP	= 200						; Número de overflows de TIMER0 en un segundo

// Registros
.def	BTN_COUNTER = R17	; Contador de botones
.def	SCOUNTER1 = R18		; Contador de segundos
.def	SCOUNTER2 = R19		; Contador de decenas de segundos
.def	OUT_PORTC = R20		; Salida a PORTC
.def	OUT_PORTD = R21		; Salida a PORTD
.def	OVF_COUNTER = R22	; Contador de Overflows en Timer0

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

	// - INICIALIZACIÓN DE TABLA -
	LDI		ZL, LOW(TABLA * 2)
	LDI		ZH, HIGH(TABLA * 2)
	LPM		OUT_PORTD, Z
	OUT		PORTD, OUT_PORTD
	
	// - CONFIGURACIÓN DE PINES -
	// Configurar los pines 0 y 1 de PORTB como entradas
	LDI		R16, (1 << PB0) | (1 << PB1)
	OUT		PORTB, R16

	// Configurar los pines 2 y 3 de PORTB como salidas
	LDI		R16, (1 << PB2) | (1 << PB3)
	OUT		DDRB, R16

	// Configurar los pines de PORTC como salidas
	LDI		R16, 0XFF
	OUT		DDRC, R16
	
	// Configurar los pines de PORTD como salidas
	LDI		R16, 0XFF
	OUT		DDRD, R16

	// - CONFIGURACIÓN DEL RELOJ DE SISTEMA -
	// No es necesaria, usaremos los 16 MHz

	// - HABILITACIÓN DE INTERRUPCIONES PC -
	LDI		R16, (1 << PCIE0)
	STS		PCICR, R16
	LDI		R16, (1 << PCINT0) | (1 << PCINT1)
	STS		PCMSK0, R16
	
	// - INICIALIZACIÓN DE TIMER0 -
	// No cambiamos los bits WGM dado que la configuración por default es el modo normal
	LDI     R16, PRESCALER				// Configurar un registro para setear las posiciones de CS01 y CS00
    OUT     TCCR0B, R16					// Setear prescaler del TIMER0 a 64 (CS01 = 1 y CS00 = 0)
    LDI     R16, TIMER_START			// Empezar el conteo con un valor de 158
    OUT     TCNT0, R16					// Cargar valor inicial en TCNT0

	// - HABILITACIÓN DE INTERRUPCIONES POR OVERFLOW EN TIMER0 -
	LDI		R16, (1 << TOIE0)
	STS		TIMSK0, R16

	// - HABILITACIÓN DE INTERRUPCIONES GLOBALES -
	SEI

	// - INICIALIZACIÓN DE REGISTROS DE PROPÓSITO GENERAL -
	CLR		BTN_COUNTER
	CLR		SCOUNTER1
	CLR		SCOUNTER2
	CLR		OVF_COUNTER

// --------------------------------------------------------------------
// | MAINLOOP														  |
// --------------------------------------------------------------------

MAINLOOP:
	RJMP	MAINLOOP

// --------------------------------------------------------------------
// | RUTINAS NO DE INTERRUPCIÓN										  |
// --------------------------------------------------------------------

// Actualizar display 1 (Unidades)
UPDATE_DISPLAY1:
	LDI		ZL, LOW(TABLA * 2)
	LDI		ZH, HIGH(TABLA * 2)
	
	; Sumar el contador de segundos 1 a Z
    MOV		R16, SCOUNTER1
    ADD		ZL, R16
    CLR		R1				; Asegurar que no haya residuos en R1
    ADC		ZH, R1			; Sumar acarreo a ZH

    ; Extraer el valor de la dirección a la que Z está apuntando
    LPM		OUT_PORTD, Z
	OUT		PORTD, OUT_PORTD

	RET

// Actualizar display 2 (Unidades)
UPDATE_DISPLAY2:
	LDI		ZL, LOW(TABLA * 2)
	LDI		ZH, HIGH(TABLA * 2)
	
	; Sumar el contador de segundos 1 a Z
    MOV		R16, SCOUNTER2
    ADD		ZL, R16
    CLR		R1				; Asegurar que no haya residuos en R1
    ADC		ZH, R1			; Sumar acarreo a ZH

    ; Extraer el valor de la dirección a la que Z está apuntando
    LPM		OUT_PORTD, Z
	OUT		PORTD, OUT_PORTD

	RET

// --------------------------------------------------------------------
// | RUTINAS DE INTERRUPCIÓN POR CAMBIO EN PINES					  |															  |
// --------------------------------------------------------------------
PCINT_ISR:
	PUSH	R16  ; Guardar registro random
	IN      R16, SREG   ; Guardar el estado de los flags
	PUSH	R16  ; Guardar registro random

	// Si PB0 está presionado, incrementar
	SBIC	PINB, PB0
	INC		BTN_COUNTER

	// Si PB1 está presionado, decrementar
	SBIC	PINB, PB1
	DEC		BTN_COUNTER

	OUT		PORTC, BTN_COUNTER

	POP		R16
    OUT		SREG, R16
	POP		R16  ; Sacar registro random
	RETI

// --------------------------------------------------------------------
// | RUTINAS DE INTERRUPCIÓN CON TIMER0								  |
// --------------------------------------------------------------------
// Cuando ocurre un overflow en TIMER0 solo se incrementarán los contadores
TIMER0_ISR: 
    PUSH	R16
    IN		R16, SREG
    PUSH	R16

	// Reiniciar el TIMER0
	LDI		R16, TIMER_START
    OUT		TCNT0, R16

	// Incrementar el contador de Overflows hasta alcanzar 1 segundo y luego reiniciar
	INC		OVF_COUNTER
	CPI		OVF_COUNTER, OVF_TOP
	BRLO	SHOW_NUMBERS
	LDI		OVF_COUNTER, 0

	// Incrementar contador de segundos (unidades)
	INC		SCOUNTER1
    CPI		SCOUNTER1, 10
    BRLO	SHOW_NUMBERS 

	// Incrementar contador de decenas de segundos
    LDI		SCOUNTER1, 0
    INC		SCOUNTER2

	// Si el contador de decenas es mayor o igual a 6 reiniciar y mostrar números
    CPI		SCOUNTER2, 6
    BRLO	SHOW_NUMBERS
	LDI		SCOUNTER2, 0
	RJMP	SHOW_NUMBERS

// Mostrar los números en los displays
SHOW_NUMBERS:
    SBIS	PORTB, PB2  ; Si PB2 está apagado, encenderlo y apagar PB3
    RJMP	ACTIVATE_DISPLAY1
    RJMP	ACTIVATE_DISPLAY2

ACTIVATE_DISPLAY1:
    SBI		PORTB, PB2   ; Activar display 1
    CBI		PORTB, PB3   ; Desactivar display 2
    CALL	UPDATE_DISPLAY1
    RJMP	END_ISR

ACTIVATE_DISPLAY2:
    CBI		PORTB, PB2   ; Desactivar display 1
    SBI		PORTB, PB3   ; Activar display 2
    CALL	UPDATE_DISPLAY2

END_ISR:
    POP		R16
    OUT		SREG, R16
    POP		R16
    RETI
