/*
PROGRAMACI�N DE MICROCONTROLADORES
PROYECTO 1 - RELOJ DIGITAL
DESCRIPCI�N: Reloj que muestra fecha y hora con modo de configuraci�n de alarma.
FECHA DE ENTREGA: 21 de marzo de 2025
*/

/*
ENSAYO DE RECONSTRUCCI�N
Para probar el correcto funcionamiento de las distintas partes del c�digo, integraremos el c�digo original
(La �ltima versi�n) un m�dulo a la vez.
1. Multiplexado
2. Interrupts por PC
*/

/* 
VERSI�N 1 - S�LO MULTIPLEXADO
- �Qu� se esperar�a?: Los cuatro displays deber�an mostrar el mismo n�mero.
- �Funciona?: Si
*/

// --------------------------------------------------------------------
// | DIRECTIVAS DEL ENSAMBLADOR                                       |
// --------------------------------------------------------------------
; Iniciar el c�digo
.cseg		
.org	0x0000
	RJMP	START

; Interrupciones por overflow de TIMER0 (Modo Normal)
.org OVF0addr				; Vector de interrupci�n para TIMER0_OVF
    RJMP TIMER0_ISR			; Saltar a la rutina de interrupci�n

// --------------------------------------------------------------------
// | DEFINICIONES DE REGISTROS DE USO COM�N Y CONSTANTES DE ASSEMBLER |
// --------------------------------------------------------------------

// Constantes para Timer0
.equ	PRESCALER0 = (1<<CS01) | (1<<CS00)				; Prescaler de TIMER0 (1024)
.equ	TIMER_START0 = 236								; Valor inicial del Timer0 (1.25 ms)

// Registros auxiliares
.def	OUT_PORTD = R22									; Salida de PORTD
.def	MUX_SIGNAL = R23								; Salida de PORTC (Multiplexado de se�al)

// --------------------------------------------------------------------
// | SETUP															  |
// --------------------------------------------------------------------
START:
	// - CONFIGURACI�N DE LA PILA - 
	// Hacemos que el puntero de la pila apunte hacia el final de la RAM
	LDI		R16, LOW(RAMEND)
	OUT		SPL, R16
	LDI		R16, HIGH(RAMEND)
	OUT		SPH, R16
	
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

	// - CONFIGURACI�N DEL RELOJ DE SISTEMA - (fclk = 1 MHz)
	LDI		R16, (1 << CLKPCE)
	STS		CLKPR, R16
	LDI		R16, (1 << CLKPS2)
	STS		CLKPR, R16
		
	// - REINICIAR TIMERS Y HABILITAR INTERRUPCIONES POR OVERFLOWS DE TIMERS -
	CALL	RESET_TIMER0
	
	// - HABILITACI�N DE INTERRUPCIONES GLOBALES -
	SEI

	// - INICIALIZACI�N DE REGISTROS -
	LDI		MUX_SIGNAL, 0X01


// --------------------------------------------------------------------
// | MAINLOOP														  |
// --------------------------------------------------------------------
MAINLOOP:
	// Realizar multiplexado de se�ales a transistores
	CALL	MULTIPLEXADO
	RJMP	MAINLOOP

// --------------------------------------------------------------------
// | RUTINA NO DE INTERRUPCI�N 1 - MULTIPLEXADO						  |
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
// | RUTINA NO DE INTERRUPCI�N 2 - Reinicio de TIMER0				  |
// --------------------------------------------------------------------
// Reiniciar Timer0
RESET_TIMER0:
	// - PRESCALER Y VALOR INICIAL -
	LDI     R16, PRESCALER0
    OUT     TCCR0B, R16
    LDI     R16, TIMER_START0
    OUT     TCNT0, R16

	// - HABILITACI�N DE INTERRUPCIONES POR OVERFLOW EN TIMER0 -
	LDI		R16, (1 << TOIE0)
	STS		TIMSK0, R16
	RET

// --------------------------------------------------------------------
// | RUTINAS DE INTERRUPCI�N CON TIMER0								  |
// --------------------------------------------------------------------
TIMER0_ISR:
	PUSH	R16
	IN		R16, SREG
	PUSH	R16

	// Reiniciar el TIMER0
	CALL	RESET_TIMER0

	// Rotar se�al de multiplexado a la izquierda (Valor Inicial 0X01)
	ROL		MUX_SIGNAL

	// Aplicar m�scara para PC1-PC3
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