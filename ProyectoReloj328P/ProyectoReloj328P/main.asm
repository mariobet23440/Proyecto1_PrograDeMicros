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
.equ	HOUR_STATE = 0x01
.equ	DATE_STATE = 0x02
.equ	ALARM_STATE	= 0x04

// R16 y R17 quedan como registros temporales

// Contadores de unidades y decenas de tiempo
// IMPORTANTE CONSIDERAR QUE R1 Y R0 SE USAN PARA ALGUNAS INSTRUCCIONES (MUL)
.def	MINUTE_UNITS = R2
.def	MINUTE_TENS = R3
.def	HOUR_UNITS = R4
.def	HOUR_TENS = R5
.def	DAY_UNITS = R6									; Decenas de meses
.def	DAY_TENS = R7									; Decenas de días
.def	MONTH_UNITS = R8 								; Unidades de meses
.def	MONTH_TENS = R9									; Decenas de meses

// R16, R17 se utilizan como registros de uso común

// Registros auxiliares
.def	DAY_COUNT = R18
.def	MONTH_COUNT = R19
.def	T2_AUX_COUNT = R20								; Contador auxiliar de TIMER2 (Acceder con MOV)
.def	OUT_PORTD = R21									; Salida de PORTD
.def	MUX_SIGNAL = R22								; Salida de PORTC (Multiplexado de señal)
.def	STATE = R23										; Registro de Estado

// No podemos usar registros más allá del 24 porque son los punteros X, Y y Z

// --------------------------------------------------------------------
// | TABLAS															  |
// --------------------------------------------------------------------

// Definir la tabla en la memoria FLASH (Números del 1 al 10 en display de 7 segmentos)
.org	0x500
TABLA:
	.db 0b1110111, 0b1000100, 0b1101011, 0b1101101, 0b1011100, 0b0111101, 0b0111111, 0b1100100, 0b1111111, 0b1111100 


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

// --------------------------------------------------------------------
// | MAINLOOP														  |
// --------------------------------------------------------------------

MAINLOOP:
	CALL	UPDATE_DISPLAYS
	RJMP	MAINLOOP


// --------------------------------------------------------------------
// | RUTINAS NO DE INTERRUPCIÓN										  |
// --------------------------------------------------------------------

// - ACTUALIZAR DISPLAYS -
UPDATE_DISPLAYS:
	CPI		MUX_SIGNAL, 0X01
	BREQ	DISPLAY4
	CPI		MUX_SIGNAL, 0X02
	BREQ	DISPLAY3
	CPI		MUX_SIGNAL, 0X04
	BREQ	DISPLAY2
	CPI		MUX_SIGNAL, 0X08
	BREQ	DISPLAY1

// - MODIFICAR DISPLAYS -
DISPLAY4:
	LDI		R16, 0X01
	OUT		PORTC, R16
	MOV		OUT_PORTD, HOUR_TENS
	RJMP	SHOW_NUMBER

DISPLAY3:
	LDI		R16, 0X02
	OUT		PORTC, R16
	MOV		OUT_PORTD, HOUR_UNITS
	RJMP	SHOW_NUMBER

DISPLAY2:
	LDI		R16, 0X04
	OUT		PORTC, R16
	MOV		OUT_PORTD, MINUTE_TENS
	RJMP	SHOW_NUMBER

DISPLAY1:
	LDI		R16, 0X08
	OUT		PORTC, R16
	MOV		OUT_PORTD, MINUTE_UNITS
	RJMP	SHOW_NUMBER

// Sacar el número correspondiente en PORTD
SHOW_NUMBER:
	// Guardar bit en displays
	IN		R17, PORTD
	BST		R17, 7
	
	// Sacar dato de tabla
	LDI		ZH, HIGH(TABLA<<1)
	LDI		ZL, LOW(TABLA<<1)
	ADD		ZL, OUT_PORTD
	LPM		R16, Z
	
	// Cargar bit de leds intermitentes
	BLD		R16, 7

	// Mostrar en PORTD
	OUT		PORTD, R16
	RET

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

	// INCREMENTO DE UNIDADES DE MINUTOS
	// Incrementar MINUTE_UNITS
	MOV		R16, MINUTE_UNITS
	INC		R16
	MOV		MINUTE_UNITS, R16	
	
	// INCREMENTO DE DECENAS DE MINUTOS
	// Si MINUTE_UNITS es mayor o igual a 10, limpiarlo e incrementar MINUTE_TENS
	CPI		R16, 10
	BRLO	INTERMEDIATE_JUMP1
	CLR		MINUTE_UNITS
	MOV		R16, MINUTE_TENS
	INC		R16
	MOV		MINUTE_TENS, R16
	
	// INCREMENTO DE UNIDADES DE HORAS
	// Si MINUTE_TENS es mayor o igual a 6, limpiarlo e incrementar HOUR_UNITS
	CPI		R16, 6
	BRLO	INTERMEDIATE_JUMP1
	CLR		MINUTE_TENS
	MOV		R16, HOUR_UNITS
	INC		R16
	MOV		HOUR_UNITS, R16

	// INCREMENTO DE DECENAS DE HORAS
	// Si HOUR_UNITS es mayor o igual a 10, limpiarlo e incrementar HOUR_TENS
	CPI		R16, 10
	BRLO	INTERMEDIATE_JUMP1
	CLR		HOUR_UNITS
	MOV		R16, HOUR_TENS
	INC		R16
	MOV		HOUR_TENS, R16

	// INCREMENTO DE UNIDADES DE DÍA
	// Si HOUR_TENS no es igual a 2 terminar subrutina
	CPI		R16, 2
	BRLO	INTERMEDIATE_JUMP1

	// Si HOUR_UNITS es menor que 4 terminar subrutina
	MOV		R16, HOUR_UNITS		; Importante cargar los contenidos de HOUR_UNITS
	CPI		R16, 4
	BRLO	INTERMEDIATE_JUMP1

	// Si no, limpiar ambos contadores e incrementar DAY_UNITS
	CLR		HOUR_UNITS
	CLR		HOUR_TENS
	MOV		R16, DAY_UNITS
	INC		R16
	MOV		DAY_UNITS, R16

	// INCREMENTO DE DECENAS DE DÍAS
	CPI		R16, 10
	BRLO	INTERMEDIATE_JUMP1
	CLR		DAY_UNITS
	MOV		R16, DAY_TENS
	INC		R16
	MOV		DAY_TENS, R16
	
	// Antes de ejecutar todo lo siguiente, determinar si el número de días no excede 28
	CPI		R16, 2			; Comparar DAY_TENS con 2
	BRLO	INTERMEDIATE_JUMP1
	MOV		R16, DAY_UNITS
	CPI		R16, 8
	BRLO	INTERMEDIATE_JUMP1
	// Esto ayudará a evitar las comparaciones para incrementar meses cuando no sean necesarias
	
	// Pero, si ese no es el caso
	// "Goku eta vaina se puso seria"
	// Si el número de días excede 29, incrementar mes (Muchas comparaciones)
	RJMP	COMPARACIONES_MES

INTERMEDIATE_JUMP1:
	JMP	END_T1_ISR

	
// COMPARACIONES PARA INCREMENTO DE MESES
COMPARACIONES_MES:
	// Calcular el número de días usando las decenas y unidades de día
	MOV		R16, DAY_UNITS		; Cargamos DAY_UNITS a R16
	ADD		DAY_COUNT, R16		; Sumamos unidades a R18
	LDI		R16, 10				; Cargamos 10 a R16
	MUL		R16, DAY_TENS		; Multiplicar DAY_TENS por 10
	MOV		R16, R0				; El byte bajo de la multiplicación se guarda en R0 (Limitado a 10)
	ADD		DAY_COUNT, R16		; Ahora R18 contiene el número de días transcurridos

	// Hacemos lo mismo con MONTH_COUNT
	MOV		R16, MONTH_UNITS	; Cargamos MONTH_UNITS a R16
	ADD		MONTH_COUNT, R16	; Sumamos unidades a R18
	LDI		R16, 10				; Cargamos 10 a R16
	MUL		R16, MONTH_TENS		; Multiplicar MONTH_TENS por 10
	MOV		R16, R0				; El byte bajo de la multiplicación se guarda en R0 (Limitado a 10)
	ADD		MONTH_COUNT, R16	; Ahora R18 contiene el número de meses transcurridos
	
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

	// Si han pasado más de 28 días, reiniciar contadores de días
    LDI		R16, 1
	MOV		DAY_UNITS, R16
	CLR		DAY_TENS
    RJMP	AUMENTAR_MES

MESES_30:
	// Verificar si el contador pasa de 30
	CPI		DAY_COUNT, 30
    BRLO	END_T1_ISR

	// Si han pasado más de 30 días, reiniciar contadores de días
    LDI		R16, 1
	MOV		DAY_UNITS, R16
	CLR		DAY_TENS
    RJMP	AUMENTAR_MES

MESES_31:
	// Verificar si el contador pasa de 31
	CPI		DAY_COUNT, 31
    BRLO	END_T1_ISR

	// Si han pasado más de 31 días, reiniciar contadores de días
    LDI		R16, 1
	MOV		DAY_UNITS, R16
	CLR		DAY_TENS
    RJMP	AUMENTAR_MES


// AUMENTAR MES
AUMENTAR_MES:
	// Aumentar contador de meses
	INC		MONTH_COUNT
	CPI		MONTH_COUNT, 12
	BRLO	NO_DICIEMBRE

	// Si las unidades de meses excenden 12, reiniciar ambos contadores
	CPI		MONTH_COUNT, 12
	BRLO	END_T1_ISR
	LDI		R16, 1
	MOV		MONTH_UNITS, R16
	CLR		MONTH_TENS
	RJMP	END_T1_ISR

// Meses que NO son diciembre
NO_DICIEMBRE:
	// Incrementar contador de unidades
	MOV		R16, MONTH_UNITS
	INC		R16
	MOV		MONTH_UNITS, R16
	CPI		R16, 10
	BRLO	END_T1_ISR

	// Incrementar contador de decenas
	CLR		MONTH_UNITS
	MOV		R16, MONTH_TENS
	INC		R16
	MOV		MONTH_TENS, R16

	// No hacer nada
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
