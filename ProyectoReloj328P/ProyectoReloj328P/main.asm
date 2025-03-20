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

VERSI�N 1 - S�LO MULTIPLEXADO
- �Qu� se esperar�a?: Los cuatro displays deber�an mostrar el mismo n�mero.
- �Funciona?: Si

VERSI�N 2 - MULTIPLEXADO + M�QUINA DE ESTADOS
- �Qu� se esperar�a? Los cuatro displays muestran un n�mero cualquiera al mismo tiempo.
  Si se presiona uno de los botones de cambio de modo los LEDs cambian. Sin MODE_OUTPUT
- �Funciona? S�. Las transiciones entre LEDs y la alarma de prueba funcionan bien

VERSI�N 3 - MOSTRAR SALIDAS SEG�N MODO Y LOOKUP TABLE
- Todav�a no configuramos el incremento autom�tico de unidades de tiempo (Con TIMER1). 
  Introducimos los registros MINUTE_COUNT, HOUR_COUNT, DAY_COUNT, MONTH_COUNT. La idea es que
  el programa muestre cada n�mero en el display correspondiente.
+ AQU� SE OBSERVARON PROBLEMAS. Los dos displays muestran el indicador de d�as.
+ La lookup table parece funcionar correctamente (Muestra los n�meros correctos).
+ La m�quina de estados funciona correctamente.
+ El multiplexado funciona correctamente
-> Se proceder� a revisar el selector de salidas seg�n modo

ERRORES DETECTADOS
Hac�a falta un RET en una llamada. Es de esperar que por eso los errores que ten�a anteriormente fueran tan err�ticos.
Los errores fueron corregidos-

+ Ahora los displays muestran el contador correspondiente y no hay interferencias con la m�quina de estados.


VERSI�N 4 - INTEGRACI�N DE RUTINAS DE TIMER1
+ En esta versi�n se integra la ISR de TIMER1, para incrementar los valores de los contadores.
+ Todo funciona correctamente. Todav�a falta integrar incrementos y decrementos, as� como el modo alarma.

VERSI�N 5 - INTEGRACI�N DE RUTINAS DE TIMER2
+ En esta versi�n se integra la ISR de TIMER2, para LEDs intermitentes. Hasta aqu� llegu� con el c�digo original.
Los LEDs intermitentes a veces parpadean brevemente y luego se apagan. Verificaremos si eso ocurre al incrementar
el periodo entre desbordamientos del TIMER1.
*/

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

// CONSTANTES DE TIMERS (Para fclk = 1 MHz)
// Constantes para Timer0
.equ	PRESCALER0 = (1<<CS01) | (1<<CS00)				; Prescaler de TIMER0 (1024)
.equ	TIMER_START0 = 236								; Valor inicial del Timer0 (1.25 ms)

// Constantes para Timer1
.equ	PRESCALER1 = (1<<CS11) | (1<<CS10)				; Prescaler de TIMER1 (1024)
.equ	TIMER_START1 = 6942								; Valor inicial de TIMER1 (60s)
														; Para acelerar el tiempo usar 65438
														; Para que cada minuto incremente en un segundo usar 6942

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

// Selector de bit para registro m�scara CHANGE_COUNTER_MASK
.equ	CCMB = 1

// R16 y R17 quedan como registros temporales

// Registros inferiores (d < 16)
.def	T2_AUX_COUNT = R2
.def	CHANGE_COUNTER_MASK = R3						; M�scara para PORTD

// Registros auxiliares (16 <= d <= 25)
.def	MINUTE_COUNT = R18
.def	HOUR_COUNT = R19
.def	DAY_COUNT = R20
.def	MONTH_COUNT = R21
.def	OUT_PORTD = R22									; Salida de PORTD
.def	MUX_SIGNAL = R23								; Salida de PORTC (Multiplexado de se�al)
.def	STATE = R24										; Registro de Estado
.def	NEXT_STATE = R25								; Registro de estado siguiente

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
	.db 0x00, 0x00

// Observe que los �ltimos dos datos son para mostrar nada (OUT_PORTD debe ser 61)

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

	// Configurar los pines PB4 y PB5 como salidas
	LDI		R16, (1 << PB4) | (1 << PB5)
	OUT		DDRB, R16
	CBI		PORTB, PB5

	// Configurar todos los pines de PORTC como salidas
	LDI		R16, 0XFF
	OUT		DDRC, R16
	LDI		R16, 0XFF
	OUT		PORTC, R16

	// Configurar los pines de PORTD como salidas
	LDI		R16, 0XFF
	OUT		DDRD, R16
	LDI		R16, 0X00
	OUT		PORTD, R16

	// - CONFIGURACI�N DEL RELOJ DE SISTEMA - (fclk = 1 MHz)
	LDI		R16, (1 << CLKPCE)
	STS		CLKPR, R16
	LDI		R16, (1 << CLKPS2)
	STS		CLKPR, R16
	
	// - HABILITACI�N DE INTERRUPCIONES PC -
	LDI		R16, (1 << PCIE0)													// Habilitar interrupciones PC en PORTB
	STS		PCICR, R16
	LDI		R16, (1 << PCINT0) | (1 << PCINT1) | (1 << PCINT2) | (1 << PCINT3)	// Habilitar Interrupciones en PB0-PB3
	STS		PCMSK0, R16	

	// - REINICIAR TIMERS Y HABILITAR INTERRUPCIONES POR OVERFLOWS DE TIMERS -
	CALL	RESET_TIMER0
	CALL	RESET_TIMER1
	CALL	RESET_TIMER2
	
	// - HABILITACI�N DE INTERRUPCIONES GLOBALES -
	SEI

	// - INICIALIZACI�N DE REGISTROS -
	CLR		CHANGE_COUNTER_MASK
	LDI		MUX_SIGNAL, 0X01
	;CLR		MINUTE_COUNT
	;CLR		HOUR_COUNT
	;LDI		DAY_COUNT, 1
	;LDI		MONTH_COUNT,1
	LDI		STATE, 1										; Registro de Estado
	LDI		NEXT_STATE, 1									; Registro de Estado Siguiente

	// PRUEBA DE DISPLAYS (QUITAR) !!!!!!!!!!!!!!!!!!!!!!!!!!!!
	LDI		MINUTE_COUNT, 0X01
	LDI		HOUR_COUNT, 0X02
	LDI		DAY_COUNT, 0X03
	LDI		MONTH_COUNT,0X04


// --------------------------------------------------------------------
// | MAINLOOP														  |
// --------------------------------------------------------------------
MAINLOOP:
	// Realizar multiplexado de se�ales a transistores
	CALL	MULTIPLEXADO
	CALL	MODE_OUTPUT
	CALL	LOOKUP_TABLE
	RJMP	MAINLOOP

// --------------------------------------------------------------------
// | RUTINA NO DE INTERRUPCI�N 1 - MULTIPLEXADO	(Verificado)		  |
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
	// MostrarHoras (S0)
	CPI		STATE, S0
	BREQ	SHOW_HOURS

	// CambiarMinutos (S1)
	CPI		STATE, S1
	BREQ	SHOW_HOURS

	// CambiarHoras (S2)
	CPI		STATE, S2
	BREQ	CHANGING_HOURS
	
	// MostrarFecha (S3)
	CPI		STATE, S3
	BREQ	SHOW_MONTH

	// CambiarDia (S4)
	CPI		STATE, S4
	BREQ	SHOW_MONTH

	// CambiarMes (S5)
	CPI		STATE, S5
	BREQ	CHANGING_MONTHS

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

// Modos MostrarHora (S0) y CambiarMinutos (S1)
SHOW_HOURS:
	MOV		OUT_PORTD, HOUR_COUNT
	RET

// Modo CambiarHoras (S2)
CHANGING_HOURS:
	SBRC	CHANGE_COUNTER_MASK, CCMB
	LDI		OUT_PORTD, 60
	SBRS	CHANGE_COUNTER_MASK, CCMB
	MOV		OUT_PORTD, HOUR_COUNT
	RET

// Modos MostrarFecha (S3) y MostrarDias (S4)
SHOW_MONTH:
	MOV		OUT_PORTD, MONTH_COUNT
	RET

// Modo CambiarMes (S5)
CHANGING_MONTHS:
	SBRC	CHANGE_COUNTER_MASK, CCMB
	LDI		OUT_PORTD, 60
	SBRS	CHANGE_COUNTER_MASK, CCMB
	MOV		OUT_PORTD, MONTH_COUNT
	RET

// Salida a displays 2 Y 1
MODE_DISPLAY21:
	// MostrarHoras (S0)
	CPI		STATE, S0
	BREQ	SHOW_MINUTES

	// CambiarMinutos (S1)
	CPI		STATE, S1
	BREQ	CHANGING_MINUTES

	// CambiarHoras (S2)
	CPI		STATE, S2
	BREQ	SHOW_MINUTES
	
	// MostrarFecha (S3)
	CPI		STATE, S3
	BREQ	SHOW_DAY

	// CambiarDia (S4)
	CPI		STATE, S4
	BREQ	CHANGING_DAYS

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

// Modos MostrarHora (S0) y CambiarHoras (S2)
SHOW_MINUTES:
	MOV		OUT_PORTD, MINUTE_COUNT
	RET

// Modo CambiarMinutos (S1)
CHANGING_MINUTES:
	SBRC	CHANGE_COUNTER_MASK, CCMB
	LDI		OUT_PORTD, 60
	SBRS	CHANGE_COUNTER_MASK, CCMB
	MOV		OUT_PORTD, MINUTE_COUNT
	RET

// Modos MostrarFecha (S3) y MostrarMeses (S5)
SHOW_DAY:
	MOV		OUT_PORTD, DAY_COUNT
	RET

// Modo Cambiardia (S4)
CHANGING_DAYS:
	SBRC	CHANGE_COUNTER_MASK, CCMB
	LDI		OUT_PORTD, 60
	SBRS	CHANGE_COUNTER_MASK, CCMB
	MOV		OUT_PORTD, DAY_COUNT
	RET

// --------------------------------------------------------------------
// | RUTINA NO DE INTERRUPCI�N 3 - LOOKUP_TABLE (Verificado)		  |
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
// | RUTINA NO DE INTERRUPCI�N 4 a 6 - Reinicio de TIMERs (Verificado)|
// --------------------------------------------------------------------
// - REINICIAR TIMER0 -
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
// | RUTINAS DE INTERRUPCI�N POR CAMBIO EN PINES 	(Verificado)	  |															  |
// --------------------------------------------------------------------
// M�QUINA DE ESTADOS FINITOS
PCINT_ISR:
	PUSH	R16
	IN		R16, SREG
	PUSH	R16

	// Cambiar Indicador con PB0
	SBIS	PINB, PB0
	JMP		NEXT_STATE_LOGIC_PB0

	// Cambiar modo de cambio de contadores con PB1
	SBIS	PINB, PB1
	JMP		NEXT_STATE_LOGIC_PB1

	// Incrementar contador con PB2
	SBIS	PINB, PB2
	JMP		INCREMENTAR_PC

	// Decrementar contador con PB3
	SBIS	PINB, PB3
	JMP		DECREMENTAR_PC
	
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

// Incrementar contador con PC (Vamos a reciclar algunas subrutinas)
INCREMENTAR_PC:	
	// CambiarMinutos (S1)
	SBRC	STATE, S1B
	INC		MINUTE_COUNT
	SBRC	STATE, S1B
	JMP		COMPARACION_MINUTOS_HORAS_INC

	// CambiarHoras (S2)
	SBRC	STATE, S2B
	INC		HOUR_COUNT
	SBRC	STATE, S2B
	JMP		COMPARACION_HORAS_DIAS_INC
	
	// CambiarDias (S4)
	SBRC	STATE, S4B
	INC		DAY_COUNT
	SBRC	STATE, S4B
	JMP		COMPARACION_DIAS_MESES_INC

	// CambiarMeses (S5)
	SBRC	STATE, S5B
	JMP		AUMENTAR_MES

DECREMENTAR_PC:
	// CambiarMinutos (S1)
	SBRC	STATE, S1B	
	JMP		DECREMENTAR_MINUTOS

	// CambiarHoras (S2)
	SBRC	STATE, S2B
	JMP		DECREMENTAR_HORAS
		
	// CambiarDias (S4)
	SBRC	STATE, S4B
	JMP		DECREMENTAR_DIAS

	// CambiarMeses (S5)
	SBRC	STATE, S5B
	JMP		DECREMENTAR_MESES

DECREMENTAR_MINUTOS:
	// Comparar con cero
	CPI		MINUTE_COUNT, 0
	BREQ	UNDERFLOW_MINUTOS
	
	// Si el contador de minutos es mayor a cero, restar uno
	DEC		MINUTE_COUNT
	JMP		END_PC_ISR

// Si el contador de minutos da cero, cargar 59 y disminuir horas
UNDERFLOW_MINUTOS:
	LDI		MINUTE_COUNT, 59
	JMP		DECREMENTAR_HORAS

// Si el n�mero de horas no es cero, disminuir
DECREMENTAR_HORAS:
	// Comparar con cero
	CPI		HOUR_COUNT, 0
	BREQ	UNDERFLOW_HORAS
	
	// Si el contador es mayor a cero, restar uno
	DEC		HOUR_COUNT
	JMP		END_PC_ISR
	
UNDERFLOW_HORAS:
	LDI		HOUR_COUNT, 23
	JMP		DECREMENTAR_DIAS

DECREMENTAR_DIAS:
	// Comparar con uno
	CPI		DAY_COUNT, 1
	BREQ	UNDERFLOW_DIAS
	
	// Si el contador es mayor a cero, restar uno
	DEC		DAY_COUNT
	JMP		END_PC_ISR

// Esta funci�n se parece mucho a COMPARACION_DIAS_MESES_INC pero al rev�s
UNDERFLOW_DIAS:	
	// Verificar si el mes es marzo (Underflow a febrero)
	CPI		MONTH_COUNT, 3
	BREQ	UNDERFLOW_MARZO

	// Meses precedidos por meses de 31 d�as
    CPI		MONTH_COUNT, 1			; Enero (underflow a Diciembre)
    BREQ	UNDERFLOW_A_MES31
	CPI		MONTH_COUNT, 2			; Febrero (underflow a Enero)
    BREQ	UNDERFLOW_A_MES31
	CPI		MONTH_COUNT, 4			; Abril (underflow a Marzo)
    BREQ	UNDERFLOW_A_MES31
    CPI		MONTH_COUNT, 6			; Junio (underflow a Mayo)
    BREQ	UNDERFLOW_A_MES31
	CPI		MONTH_COUNT, 8			; Agosto (underflow a Junio)
    BREQ	UNDERFLOW_A_MES31
    CPI		MONTH_COUNT, 9			; Septiembre (underflow a Agosto)
    BREQ	UNDERFLOW_A_MES31
    CPI		MONTH_COUNT, 11			; Noviembre (underflow a Octubre)
    BREQ	UNDERFLOW_A_MES31

	// Meses precedidos por meses de 30 d�as
	RJMP	UNDERFLOW_A_MES30

// Si el mes donde ocurre el overflow es marzo, cargar a 28 d�as
UNDERFLOW_MARZO:
    LDI		DAY_COUNT, 28
    RJMP	DECREMENTAR_MESES

// Si el mes donde ocurre el overflow es enero, febrero, abril, junio, septiembre y noviembre
UNDERFLOW_A_MES31:
    LDI		DAY_COUNT, 31
	RJMP	DECREMENTAR_MESES

// Underflow a un mes de 30 d�as
UNDERFLOW_A_MES30:
    LDI		DAY_COUNT, 30
	RJMP	DECREMENTAR_MESES

// AUMENTAR MES
DECREMENTAR_MESES:
	// Comparar con uno
	CPI		MONTH_COUNT, 1
	BRLO	UNDERFLOW_MESES

	// Si el mes no es enero, decrementar contador
	DEC		MONTH_COUNT
	RJMP	END_PC_ISR

UNDERFLOW_MESES:
	LDI		MONTH_COUNT, 12
	RJMP	END_PC_ISR
	

END_PC_ISR:
	POP		R16
	OUT		SREG, R16
	POP		R16
	RETI


// --------------------------------------------------------------------
// | RUTINAS DE INTERRUPCI�N CON TIMER0								  |
// --------------------------------------------------------------------
// CAMBIO DE SE�AL DE MULTIPLEXADO
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

// - ESTAS SUBRUTINAS SE COMPARTEN CON LAS SUBRUTINAS DE PC -
COMPARACION_MINUTOS_HORAS_INC:	
	// INCREMENTO DE HORAS
	// Si MINUTE_COUNT es mayor o igual a 60, limpiarlo e incrementar HOUR_COUNT
	CPI		MINUTE_COUNT, 60
	BRLO	INTERMEDIATE_JUMP1
	CLR		MINUTE_COUNT
	INC		HOUR_COUNT

COMPARACION_HORAS_DIAS_INC:
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
	RJMP	COMPARACION_DIAS_MESES_INC

INTERMEDIATE_JUMP1:
	JMP	END_T1PC_ISR

	
// COMPARACIONES PARA INCREMENTO DE MESES
COMPARACION_DIAS_MESES_INC:	
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
    BRLO	END_T1PC_ISR

	// Si han pasado m�s de 28 d�as, reiniciar contador de d�as
    LDI		DAY_COUNT, 1
    RJMP	AUMENTAR_MES

MESES_30:
	// Verificar si el contador de d�as pasa de 30
	CPI		DAY_COUNT, 31
    BRLO	END_T1PC_ISR

	// Si han pasado m�s de 30 d�as, reiniciar contador de d�as
    LDI		DAY_COUNT, 1
	RJMP	AUMENTAR_MES

MESES_31:
	// Verificar si el contador pasa de 31
	CPI		DAY_COUNT, 32
    BRLO	END_T1PC_ISR

	// Si han pasado m�s de 31 d�as, reiniciar contadores de d�as
    LDI		DAY_COUNT, 1
	RJMP	AUMENTAR_MES


// AUMENTAR MES
AUMENTAR_MES:
	// Aumentar contador de meses
	INC		MONTH_COUNT
	CPI		MONTH_COUNT, 13
	BRLO	END_T1PC_ISR

	// Si las unidades de meses excenden 12, reiniciar ambos contadores
	CPI		MONTH_COUNT, 12
	LDI		MONTH_COUNT, 1
	RJMP	END_T1PC_ISR

// Terminar Rutina de Interrupci�n
END_T1PC_ISR:
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

	// Aumentar en 1 la m�scara de OUTPORTD para modos de cambio de contadores
	INC		CHANGE_COUNTER_MASK ; Aumentar en 1 el �ltimo bit de este registro

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

/*
NOTA:
Obs�rve c�mo usamos CHANGE_COUNTER_MASK como un oscilador de frecuencia variable. Al tomar un bit de mayor orden incrementamos
la frecuencia de oscilaci�n.
*/


// Terminar Rutina de Interrupci�n
END_T2_ISR:
	POP		R16
	OUT		SREG, R16
	POP		R16
	RETI
