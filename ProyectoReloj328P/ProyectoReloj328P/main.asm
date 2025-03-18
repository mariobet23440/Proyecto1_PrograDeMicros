;
; ProyectoReloj328P.asm
;
; Created: 20/02/2025 22:52:46
; Author : Mario Alejandro Betancourt Franco
;


// --------------------------------------------------------------------
// | DIRECTIVAS DEL ENSAMBLADOR                                       |
// --------------------------------------------------------------------

; Iniciar el c�digo
.cseg		
.org	0x0000
	RJMP	START

; Interrupciones PIN CHANGE
.org PCI0addr
	RJMP PCINT_ISR		; Vector de interrupci�n de Pin Change

; Interrupciones por overflow de TIMER0 (Modo Normal)
.org OVF0addr				; Vector de interrupci�n para TIMER0_OVF
    RJMP TIMER0_ISR			; Saltar a la rutina de interrupci�n

; Interrupciones por overflow de TIMER1 (Modo Normal)
.org OVF1addr				; Vector de interrupci�n para TIMER1_OVF
    RJMP TIMER1_ISR			; Saltar a la rutina de interrupci�n

; Interrupciones por overflow de TIMER2 (Modo Normal)
.org OVF2addr				; Vector de interrupci�n para TIMER2_OVF
    RJMP TIMER2_ISR			; Saltar a la rutina de interrupci�n

// --------------------------------------------------------------------
// | DEFINICIONES DE REGISTROS DE USO COM�N Y CONSTANTES DE ASSEMBLER |
// --------------------------------------------------------------------

// Constantes para Timer0
.equ	PRESCALER0 = (1<<CS01) | (1<<CS00)				; Prescaler de TIMER0 (1024)
.equ	TIMER_START0 = 236								; Valor inicial del Timer0 (1.25 ms)

// Constantes para Timer1
.equ	PRESCALER1 = (1<<CS11) | (1<<CS10)				; Prescaler de TIMER1 (1024)
.equ	TIMER_START1 = 65438							; Valor inicial de TIMER1 (60s)
; Para hacer pruebas usar 65438
; Para medici�n de tiempo real usar 6942

// Constantes para Timer2
.equ	PRESCALER2 = (1<<CS22) | (1<<CS21) | (1<<CS20)	; Prescaler de TIMER2 (1024)
.equ	TIMER_START2 = 158								; Valor inicial de TIMER2 (100 ms)

// Estados de M�quina de estados finitos
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

// Bits para comparar con m�quina de estados
.equ	S1B = 0
.equ	S2B = 1
.equ	S3B = 2
.equ	S4B = 3
.equ	S5B = 4
.equ	S6B = 5
.equ	S7B = 6
.equ	S8B = 7

; N�tese que S0 = 0x00 y todos los bits est�n apagados, sus comparaciones son diferentes

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

// R16, R17 se utilizan como registros de uso com�n

// Registros auxiliares
.def	MINUTE_COUNT = R18
.def	HOUR_COUNT = R19
.def	DAY_COUNT = R20
.def	MONTH_COUNT = R21
.def	OUT_PORTD = R22									; Salida de PORTD
.def	MUX_SIGNAL = R23								; Salida de PORTC (Multiplexado de se�al)
.def	STATE = R24										; Registro de Estado
.def	NEXT_STATE = R25								; Registro de estado siguiente

// No podemos usar registros m�s all� del 24 porque son los punteros X, Y y Z

// --------------------------------------------------------------------
// | TABLAS															  |
// --------------------------------------------------------------------

// Definir la tabla en la memoria FLASH (N�meros del 1 al 10 en display de 7 segmentos)
.org	0x500
TABLA:
	.db T0, T0, T0, T1, T0, T2, T0, T3, T0, T4, T0, T5, T0, T6, T0, T7, T0, T8, T0, T9
	.db T1, T0, T1, T1, T1, T2, T1, T3, T1, T4, T1, T5, T1, T6, T1, T7, T1, T8, T1, T9
	.db T2, T0, T2, T1, T2, T2, T2, T3, T2, T4, T2, T5, T2, T6, T2, T7, T2, T8, T2, T9
	.db T3, T0, T3, T1, T3, T2, T3, T3, T3, T4, T3, T5, T3, T6, T3, T7, T3, T8, T3, T9
	.db T4, T0, T4, T1, T4, T2, T4, T3, T4, T4, T4, T5, T4, T6, T4, T7, T4, T8, T4, T9
	.db T5, T0, T5, T1, T5, T2, T5, T3, T5, T4, T5, T5, T5, T6, T5, T7, T5, T8, T5, T9
// �Qui�n tiene tiempo para hacer tantas comparaciones? Mejor hagamos una buena lookup table
// Importante observar que para apuntar a las unidades es necesario usar el doble de un registro


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

	// - INICIALIZACI�N DE TABLAS -
	LDI		ZL, LOW(TABLA << 1)
	LDI		ZH, HIGH(TABLA << 1)
	LPM		OUT_PORTD, Z
	OUT		PORTD, OUT_PORTD
	
	// - CONFIGURACI�N DE PINES -
	// Configurar los pines PB1-PB4 de PORTB como entradas (Habilitar pull-ups)
	LDI		R16, (1 << PB0) | (1 << PB1)  | (1 << PB2) | (1 << PB3)
	OUT		PORTB, R16

	// Configurar los pines PB4 y PB5 como una salida
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

	// - CONFIGURACI�N DEL RELOJ DE SISTEMA - (fclk = 1 MHz)
	LDI		R16, (1 << CLKPCE)
	STS		CLKPR, R16
	LDI		R16, (1 << CLKPS2)
	STS		CLKPR, R16
	

	// - HABILITACI�N DE INTERRUPCIONES PC -
	LDI		R16, (1 << PCIE0)																	// Habilitar interrupciones PC en PORTB
	STS		PCICR, R16
	LDI		R16, (1 << PCINT0) | (1 << PCINT1) | (1 << PCINT2) | (1 << PCINT3) | (1 << PCINT4)	// Habilitar Interrupciones en PB1-PB4
	STS		PCMSK0, R16
	
	// - REINICIAR TIMERS Y HABILITAR INTERRUPCIONES POR OVERFLOWS DE TIMERS -
	CALL	RESET_TIMER0
	CALL	RESET_TIMER1
	CALL	RESET_TIMER2

	// - HABILITACI�N DE INTERRUPCIONES GLOBALES -
	SEI

	// - INICIALIZACI�N DE REGISTROS -
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
	// Realizar multiplexado de se�ales a transistores
	CALL	MULTIPLEXADO
	CALL	MODE_OUTPUT
	CALL	LOOKUP_TABLE

	// Mostrar n�mero en PORTD
	RJMP	MAINLOOP


// --------------------------------------------------------------------
// | RUTINA NO DE INTERRUPCI�N 1 - MULTIPLEXADO						  |
// --------------------------------------------------------------------
// - ACTUALIZAR DISPLAYS -
MULTIPLEXADO:
	IN		R16, PORTC
	ANDI	R16, 0X30			; Apagar todo menos los �ltimos 2 bits
	OUT		PORTC, R16
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
	RET

MUX_DISPLAY3:
	SBI		PORTC, PC1
	RET

MUX_DISPLAY2:
	SBI		PORTC, PC2
	RET

MUX_DISPLAY1:
	SBI		PORTC, PC3
	RET

// --------------------------------------------------------------------
// | RUTINA NO DE INTERRUPCI�N 2 - MODE_OUTPUT						  |
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
	SBRC	STATE, 0
	MOV		OUT_PORTD, MINUTE_COUNT
	SBRC	STATE, 1
	MOV		OUT_PORTD, MINUTE_COUNT
	SBRC	STATE, 2
	MOV		OUT_PORTD, DAY_COUNT
	SBRC	STATE, 3
	MOV		OUT_PORTD, DAY_COUNT
	RET

; Si se debe mostrar la salida en DISPLAYS 3 y 4, mostrar horas y meses
; Si se debe mostrar la salida en DISPLAYS 2 y 1, mostrar minutos y d�as

// --------------------------------------------------------------------
// | RUTINA NO DE INTERRUPCI�N 2 - LOOKUP_TABLE						  |
// --------------------------------------------------------------------

// LOOKUP TABLE
LOOKUP_TABLE:
	// Guardar bit 7 de PORTD en el Bit T del SREG
	IN		R17, PORTD
	BST		R17, 7
	
	// Sacar dato de tabla
	LDI		ZH, HIGH(TABLA<<1)
	LDI		ZL, LOW(TABLA<<1)

	// Obtener direcci�n de tabla (Duplicando OUT_PORTD)
	MOV		R16, OUT_PORTD
	ADD		R16, OUT_PORTD

	// Incrementar puntero Z en 2*OUT_PORTD
	ADD		ZL, R16

	// Sacar el primer d�gitooo
	LPM		R16, Z
	
	// Si MUX_SIGNAL es 0x04 o 0x08 sacar el siguiente n�mero
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
// | RUTINAS NO DE INTERRUPCI�N 3-5 : REINICIO DE TIMERS			  |
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


// - REINICIAR TIMER1 -
RESET_TIMER1:
	// - PRESCALER Y VALOR INICIAL -
	LDI     R16, PRESCALER1
    STS     TCCR1B, R16
    LDI     R16, LOW(TIMER_START1)
    STS     TCNT1L, R16
	LDI     R16, HIGH(TIMER_START1)
    STS     TCNT1H, R16

	// - HABILITACI�N DE INTERRUPCIONES POR OVERFLOW EN TIMER1 -
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

	// - HABILITACI�N DE INTERRUPCIONES POR OVERFLOW EN TIMER2 -
	LDI		R16, (1 << TOIE2)
	STS		TIMSK2, R16
	RET

// --------------------------------------------------------------------
// | RUTINAS DE INTERRUPCI�N POR CAMBIO EN PINES					  |															  |
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
	
// L�gica de Siguiente estado si se presiona PB0
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

	// CambiarD�as (S4) -> MostrarFecha (S3)
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
	

// L�gica de Siguiente estado si se presiona PB1
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

	// CambiarD�as (S4) -> CambiarMeses (S5)
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

	// Salir (Si es que algo falla, por alguna raz�n)
	JMP		END_PC_ISR

// Encender LEDs Indicadores de Modo
ENCENDER_LED_HORA:
	SBI		PORTC, PC4
	CBI		PORTC, PC5
	CBI		PORTB, PB4
	CBI		PORTB, PB5		; Quitar esta l�nea en el programa final
	JMP		END_PC_ISR

ENCENDER_LED_FECHA:
	CBI		PORTC, PC4
	SBI		PORTC, PC5
	CBI		PORTB, PB4
	CBI		PORTB, PB5		; Quitar esta l�nea en el programa final
	JMP		END_PC_ISR

ENCENDER_LED_ALARMA:
	CBI		PORTC, PC4
	CBI		PORTC, PC5
	SBI		PORTB, PB4
	CBI		PORTB, PB5		; Quitar esta l�nea en el programa final
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


// --------------------------------------------------------------------
// | RUTINAS DE INTERRUPCI�N CON TIMER1								  |
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

	// INCREMENTO DE D�AS
	// Si HOUR_COUNT es mayor o igual a 24, limpiarlo e incrementar DAY_COUNT
	CPI		HOUR_COUNT, 24
	BRLO	INTERMEDIATE_JUMP1
	CLR		HOUR_COUNT
	INC		DAY_COUNT

	// Si el n�mero de d�as no excede 28 (El m�nimo para cambiar de mes) salir para
	// evitar comparaciones innecesarias
	CPI		DAY_COUNT, 28
	BRLO	INTERMEDIATE_JUMP1
		
	// Pero, si ese no es el caso
	// "Goku eta vaina se puso seria"
	// Si el n�mero de d�as excede 29, incrementar mes (Muchas comparaciones)
	RJMP	COMPARACIONES_MES

INTERMEDIATE_JUMP1:
	JMP	END_T1_ISR

	
// COMPARACIONES PARA INCREMENTO DE MESES
COMPARACIONES_MES:	
	// Verificar si el mes es febrero
	CPI		MONTH_COUNT, 2
	BREQ	FEBRERO

	// Meses con 30 d�as (abril, junio, septiembre, noviembre)
    CPI		MONTH_COUNT, 4
    BREQ	MESES_30
    CPI		MONTH_COUNT, 6
    BREQ	MESES_30
    CPI		MONTH_COUNT, 9
    BREQ	MESES_30
    CPI		MONTH_COUNT, 11
    BREQ	MESES_30

	// Si el mes no es de 30 d�as y no es febrero, es de 31 d�as
	RJMP	MESES_31

FEBRERO:
	// Verificar si el contador de d�as pasa de 28
	CPI		DAY_COUNT, 29
    BRLO	END_T1_ISR

	// Si han pasado m�s de 28 d�as, reiniciar contador de d�as
    LDI		DAY_COUNT, 1
    RJMP	AUMENTAR_MES

MESES_30:
	// Verificar si el contador de d�as pasa de 30
	CPI		DAY_COUNT, 31
    BRLO	END_T1_ISR

	// Si han pasado m�s de 30 d�as, reiniciar contador de d�as
    LDI		DAY_COUNT, 1
	RJMP	AUMENTAR_MES

MESES_31:
	// Verificar si el contador pasa de 31
	CPI		DAY_COUNT, 32
    BRLO	END_T1_ISR

	// Si han pasado m�s de 31 d�as, reiniciar contadores de d�as
    LDI		DAY_COUNT, 1
	RJMP	AUMENTAR_MES


// AUMENTAR MES
AUMENTAR_MES:
	// Aumentar contador de meses
	INC		MONTH_COUNT
	CPI		MONTH_COUNT, 12
	BRLO	END_T1_ISR

	// Si las unidades de meses excenden 12, reiniciar ambos contadores
	CPI		MONTH_COUNT, 12
	LDI		MONTH_COUNT, 1
	RJMP	END_T1_ISR

// Terminar Rutina de Interrupci�n
END_T1_ISR:
	POP		R16
	OUT		SREG, R16
	POP		R16
	RETI


// --------------------------------------------------------------------
// | RUTINAS DE INTERRUPCI�N CON TIMER2								  |
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
	

// Terminar Rutina de Interrupci�n
END_T2_ISR:
	POP		R16
	OUT		SREG, R16
	POP		R16
	RETI
