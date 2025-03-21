/*
PROGRAMACIÓN DE MICROCONTROLADORES
PROYECTO 1 - RELOJ DIGITAL
DESCRIPCIÓN: Reloj que muestra fecha y hora con modo de configuración de alarma.
FECHA DE ENTREGA: 21 de marzo de 2025
ÚLTIMA MODIFICACIÓN: 20/03/2025
ÚLTIMOS PENDIENTES: Mejorar antirrebote (En Hardware)
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

; Interrupciones por overflow de TIMER1 (Modo Normal)
.org OVF1addr				; Vector de interrupción para TIMER1_OVF
    RJMP TIMER1_ISR			; Saltar a la rutina de interrupción

; Interrupciones por overflow de TIMER2 (Modo Normal)
.org OVF2addr				; Vector de interrupción para TIMER2_OVF
    RJMP TIMER2_ISR			; Saltar a la rutina de interrupción


// --------------------------------------------------------------------
// | DEFINICIONES DE REGISTROS DE USO COMÚN Y CONSTANTES DE ASSEMBLER |
// --------------------------------------------------------------------

// CONSTANTES DE TIMERS (Para fclk = 1 MHz)
// Constantes para Timer0
.equ	PRESCALER0 = (1<<CS01) | (1<<CS00)				; Prescaler de TIMER0 (1024)
.equ	TIMER_START0 = 236								; Valor inicial del Timer0 (0.20 ms)

// Constantes para Timer1
.equ	PRESCALER1 = (1<<CS12) | (1<<CS10)				; Prescaler de TIMER1 (1024)
.equ	TIMER_START1 = 6942								; Valor inicial de TIMER1 (60s)

// Constantes para Timer2
.equ	PRESCALER2 = (1<<CS22) | (1<<CS21) | (1<<CS20)	; Prescaler de TIMER2 (1024)
.equ	TIMER_START2 = 133								; Valor inicial de TIMER2 (125 ms)

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

// Selector de bit para registro máscara T2COSC
// Este bit hace que los displays parpadeen cuando se va a cambiar un contador
.equ	CCMB = 0

// Bit Controlador de LEDs Intermitentes
.equ	ILED_CB = 2
/* 
Para un periodo entre desbordamientos de TIMER2 de 125 ms
BIT DE TCOSC2
0 - Periodo 250 ms (Bajo durante 125 ms)
1 - Periodo de 500 ms (Bajo durante 250 ms)
2 - Periodo de 1000 ms (Bajo durante 500 ms)
*/
// R16 y R17 quedan como registros temporales

// Registros inferiores (d < 16)
.def	T2_AUX_COUNT = R2
.def	T2COSC = R3										; Máscara para PORTD (*T*imer*2* *C*ustom *OSC*ilator)
.def	ALARM_MINUTES = R4								; Registro de contador de minutos de alarma
.def	ALARM_HOUR = R5									; Registro de contador de horas de alarma

// La alarma suena a las ALARM_HOUR horas y los ALARM_MINUTE minutos
// Por default, la alarma es audible sólo durante el minuto exacto para el que está programada.
// O bien se puede apagar automáticamente al presionar nuevamente PB0

// Registros auxiliares (16 <= d <= 25)
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
	.db 0x00, 0x00

// Observe que los últimos dos datos son para mostrar nada (OUT_PORTD debe ser 61)

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
	LDI		R16, 0X10
	OUT		PORTC, R16

	// Configurar los pines de PORTD como salidas
	LDI		R16, 0XFF
	OUT		DDRD, R16
	LDI		R16, 0X00
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
	CALL	RESET_TIMER1
	CALL	RESET_TIMER2
	
	// - HABILITACIÓN DE INTERRUPCIONES GLOBALES -
	SEI

	// - INICIALIZACIÓN DE REGISTROS -
	CLR		ALARM_HOUR
	CLR		ALARM_MINUTES
	CLR		T2COSC
	LDI		MUX_SIGNAL, 0X01
	CLR		MINUTE_COUNT
	CLR		HOUR_COUNT
	LDI		DAY_COUNT, 1
	LDI		MONTH_COUNT,1
	LDI		STATE, 1										; Registro de Estado
	LDI		NEXT_STATE, 0									; Registro de Estado Siguiente


// --------------------------------------------------------------------
// | MAINLOOP														  |
// --------------------------------------------------------------------
MAINLOOP:
	// Realizar multiplexado de señales a transistores
	CALL	MULTIPLEXADO
	CALL	MODE_OUTPUT
	CALL	LOOKUP_TABLE
	RJMP	MAINLOOP

// --------------------------------------------------------------------
// | RUTINA NO DE INTERRUPCIÓN 1 - MULTIPLEXADO	(Verificado)		  |
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
	BREQ	SHOW_ALARM_HOURS

	// CambiarAlarmaMinutos (S7)
	CPI		STATE, S7
	BREQ	SHOW_ALARM_HOURS

	// CambiarAlarmaHoras (S8)
	CPI		STATE, S8
	BREQ	CHANGE_ALARM_HOURS
	RET

// Modos MostrarHora (S0) y CambiarMinutos (S1)
SHOW_HOURS:
	MOV		OUT_PORTD, HOUR_COUNT
	RET

// Modo CambiarHoras (S2)
CHANGING_HOURS:
	SBRC	T2COSC, CCMB
	LDI		OUT_PORTD, 60
	SBRS	T2COSC, CCMB
	MOV		OUT_PORTD, HOUR_COUNT
	RET

// Modos MostrarFecha (S3) y MostrarDias (S4)
SHOW_MONTH:
	MOV		OUT_PORTD, MONTH_COUNT
	RET

// Modo CambiarMes (S5)
CHANGING_MONTHS:
	SBRC	T2COSC, CCMB
	LDI		OUT_PORTD, 60
	SBRS	T2COSC, CCMB
	MOV		OUT_PORTD, MONTH_COUNT
	RET

// Modos ModoAlarma (S6) y AlarmaMinutos (S7)
SHOW_ALARM_HOURS:
	MOV		OUT_PORTD, ALARM_HOUR
	RET

// Modo CambiarHoras (S2)
CHANGE_ALARM_HOURS:
	SBRC	T2COSC, CCMB
	LDI		OUT_PORTD, 60
	SBRS	T2COSC, CCMB
	MOV		OUT_PORTD, ALARM_HOUR
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
	BREQ	SHOW_ALARM_MINUTES

	// AlarmaMinutos (S7)
	CPI		STATE, S7
	BREQ	CHANGE_ALARM_MINUTES

	// AlarmaHoras (S8)
	CPI		STATE, S8
	BREQ	SHOW_ALARM_MINUTES
	RET

// Modos MostrarHora (S0) y CambiarHoras (S2)
SHOW_MINUTES:
	MOV		OUT_PORTD, MINUTE_COUNT
	RET

// Modo CambiarMinutos (S1)
CHANGING_MINUTES:
	SBRC	T2COSC, CCMB
	LDI		OUT_PORTD, 60
	SBRS	T2COSC, CCMB
	MOV		OUT_PORTD, MINUTE_COUNT
	RET

// Modos MostrarFecha (S3) y MostrarMeses (S5)
SHOW_DAY:
	MOV		OUT_PORTD, DAY_COUNT
	RET

// Modo Cambiardia (S4)
CHANGING_DAYS:
	SBRC	T2COSC, CCMB
	LDI		OUT_PORTD, 60
	SBRS	T2COSC, CCMB
	MOV		OUT_PORTD, DAY_COUNT
	RET

// Modos MostrarHora (S0) y CambiarHoras (S2)
SHOW_ALARM_MINUTES:
	MOV		OUT_PORTD, ALARM_MINUTES
	RET

// Modo CambiarMinutos (S1)
CHANGE_ALARM_MINUTES:
	SBRC	T2COSC, CCMB
	LDI		OUT_PORTD, 60
	SBRS	T2COSC, CCMB
	MOV		OUT_PORTD, ALARM_MINUTES
	RET

// --------------------------------------------------------------------
// | RUTINA NO DE INTERRUPCIÓN 3 - LOOKUP_TABLE (Verificado)		  |
// --------------------------------------------------------------------
// LOOKUP TABLE
LOOKUP_TABLE:
	// Reiniciar dirección del puntero Z
	LDI		ZH, HIGH(TABLA<<1)
	LDI		ZL, LOW(TABLA<<1)

	// Obtener dirección de tabla (Duplicando OUT_PORTD)
	MOV		R16, OUT_PORTD
	ADD		R16, OUT_PORTD

	// Incrementar puntero Z en 2*OUT_PORTD
	ADD		ZL, R16

	// Si MUX_SIGNAL es 0x04 o 0x08 sacar el siguiente número
	SBRC	MUX_SIGNAL, 1
	INC		ZL
	SBRC	MUX_SIGNAL, 3
	INC		ZL
	LPM		R16, Z

	// A partir de ahora, R16 contiene los dos bytes a la salida de un display, debemos activar o desactivar el último bit

	// Mostrar en PORTD
	OUT		PORTD, R16

	// Aquí es donde debemos implementar los LEDs intermitentes
	// Usaremos el oscilador custom con TIMER2 (T2COSC)
	// Leeremos el bit ILED_CB
	
	// Si el bit ILED_CB está apagado, apagar los LEDs
	SBRC	T2COSC, ILED_CB
	SBI		PORTD, PD7

	// Si el bit ILED_CB en T2COSC está encendido, encender los LEDss
	SBRS	T2COSC, ILED_CB
	CBI		PORTD, PD7

	// ¡Bravo! Ahora tenemos LEDs intermitentes (En teoría)
	// Es importante que para que los LEDs tititlen cada 500 ms el periodo entre desbordamientos del TIMER2
	// Debe ser el cociente entre 500ms y una potencia de 2 (Por ejemplo 250).
	// Esto, por alguna razón, también genera oscilaciones de frecuencias más estables.
	// Si ILED_CB es igual a CCMB, los LEDs se encienden cuando los displays se apagan.

	RET

// --------------------------------------------------------------------
// | RUTINA NO DE INTERRUPCIÓN 4 a 6 - Reinicio de TIMERs (Verificado)|
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
// | RUTINAS DE INTERRUPCIÓN POR CAMBIO EN PINES 	(Verificado)	  |															  |
// --------------------------------------------------------------------
// MÁQUINA DE ESTADOS FINITOS -----------------------------------------
PCINT_ISR:
	PUSH	R16
	IN		R16, SREG
	PUSH	R16

	// Si la alarma no está encendida, saltar a lo siguiente.
	SBIS	PORTB, PB5
	JMP		BUTTON_CHOOSER

	// Si está encendida, apagarla con cualquier interrupción Pin change y salir (No cambiar nada)
	CBI		PORTB, PB5
	JMP		END_PC_ISR

BUTTON_CHOOSER:
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

// ENCENDER_LEDS_MODO -----------------------------------------
ENCENDER_LEDS_MODO:
	// MostrarHoras (S0)
	CPI		STATE, S0
	BREQ	ENCENDER_LED_HORA

	// CambiarMinutos (S1)
	CPI		STATE, S1
	BREQ	ENCENDER_LED_HORA

	// CambiarHoras (S2)
	CPI		STATE, S2
	BREQ	ENCENDER_LED_HORA

	// MostrarFecha (S3)
	CPI		STATE, S3
	BREQ	ENCENDER_LED_FECHA

	// CambiarDias (S4)
	CPI		STATE, S4
	BREQ	ENCENDER_LED_FECHA

	// CambiarMeses (S5)
	CPI		STATE, S5
	BREQ	ENCENDER_LED_FECHA

	// Modo Alarma (S6)
	CPI		STATE, S6
	BREQ	ENCENDER_LED_ALARMA

	// AlarmaMinutos (S7)
	CPI		STATE, S7
	BREQ	ENCENDER_LED_ALARMA

	// AlarmaHoras (S8)
	CPI		STATE, S8
	BREQ	ENCENDER_LED_ALARMA

	// Salir (Si es que algo falla, por alguna razón)
	JMP		END_PC_ISR

// Encender LEDs Indicadores de Modo
ENCENDER_LED_HORA:
	SBI		PORTC, PC4
	CBI		PORTC, PC5
	CBI		PORTB, PB4
	JMP		END_PC_ISR

ENCENDER_LED_FECHA:
	CBI		PORTC, PC4
	SBI		PORTC, PC5
	CBI		PORTB, PB4
	JMP		END_PC_ISR

ENCENDER_LED_ALARMA:
	CBI		PORTC, PC4
	CBI		PORTC, PC5
	SBI		PORTB, PB4
	JMP		END_PC_ISR

// INCREMENTAR CONTADOR --------------------------------------------
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
	JMP		INCREMENTAR_MES

	// AlarmaMinutos (S7)
	SBRC	STATE, S7B
	RJMP	INCREMENTAR_ALARMA_MINUTOS

	// AlarmaHoras (S8)
	SBRC	STATE, S8B
	RJMP	INCREMENTAR_ALARMA_HORAS
	
	// Si no es ni fu ni fa salir
	JMP		END_PC_ISR

INCREMENTAR_ALARMA_MINUTOS:
	// Si el contador de minutos es de 59, hacer un overflow
	MOV		R16, ALARM_MINUTES
	CPI		R16, 59
	BREQ	OVERFLOW_ALARMA_MINUTOS
	
	// Si no, incrementar contador y salir
	INC		ALARM_MINUTES
	JMP		END_PC_ISR

OVERFLOW_ALARMA_MINUTOS:
	CLR		ALARM_MINUTES
	
INCREMENTAR_ALARMA_HORAS:
	// Si son las 23 horas hacer overflow
	MOV		R16, ALARM_HOUR
	CPI		R16, 23
	BREQ	OVERFLOW_ALARMA_HORAS

	// Si no, incrementar contador y salir
	INC		ALARM_HOUR
	JMP		END_PC_ISR

OVERFLOW_ALARMA_HORAS:
	CLR		ALARM_MINUTES
	JMP		END_PC_ISR


// DECREMENTAR CONTADOR --------------------------------------------
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

	// AlarmaMinutos (S7)
	SBRC	STATE, S7B
	RJMP	DECREMENTAR_ALARMA_MINUTOS

	// AlarmaHoras (S8)
	SBRC	STATE, S8B
	RJMP	DECREMENTAR_ALARMA_HORAS

	// Si no es ni fu ni fa salir
	JMP		END_PC_ISR


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

// Si el número de horas no es cero, disminuir
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

// Esta función se parece mucho a COMPARACION_DIAS_MESES_INC pero al revés
UNDERFLOW_DIAS:	
	// Verificar si el mes es marzo (Underflow a febrero)
	CPI		MONTH_COUNT, 3
	BREQ	UNDERFLOW_MARZO

	// Meses precedidos por meses de 31 días
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

	// Meses precedidos por meses de 30 días
	RJMP	UNDERFLOW_A_MES30

// Si el mes donde ocurre el overflow es marzo, cargar a 28 días
UNDERFLOW_MARZO:
    LDI		DAY_COUNT, 28
    RJMP	DECREMENTAR_MESES

// Si el mes donde ocurre el overflow es enero, febrero, abril, junio, septiembre y noviembre
UNDERFLOW_A_MES31:
    LDI		DAY_COUNT, 31
	RJMP	DECREMENTAR_MESES

// Underflow a un mes de 30 días
UNDERFLOW_A_MES30:
    LDI		DAY_COUNT, 30
	RJMP	DECREMENTAR_MESES

// INCREMENTAR MES
DECREMENTAR_MESES:
	// Comparar con uno
	CPI		MONTH_COUNT, 1
	BREQ	UNDERFLOW_MESES

	// Si el mes no es enero, decrementar contador
	DEC		MONTH_COUNT
	JMP		END_PC_ISR

UNDERFLOW_MESES:
	LDI		MONTH_COUNT, 12
	JMP		END_PC_ISR

DECREMENTAR_ALARMA_MINUTOS:
	// Si el contador de minutos es 0, hacer un underflow
	MOV		R16, ALARM_MINUTES
	CPI		R16, 0
	BREQ	UNDERFLOW_ALARMA_MINUTOS
	
	// Si no, decrementar contador y salir
	DEC		ALARM_MINUTES
	JMP		END_PC_ISR

UNDERFLOW_ALARMA_MINUTOS:
	LDI		R16, 59
	MOV		ALARM_MINUTES, R16
	
DECREMENTAR_ALARMA_HORAS:
	// Si son las 0 horas hacer underflow
	MOV		R16, ALARM_HOUR
	CPI		R16, 0
	BREQ	UNDERFLOW_ALARMA_HORAS

	// Si no, decrementar contador y salir
	DEC		ALARM_HOUR
	JMP		END_PC_ISR

UNDERFLOW_ALARMA_HORAS:
	LDI		R16, 23
	MOV		ALARM_HOUR, R16
	JMP		END_PC_ISR

END_PC_ISR:
	POP		R16
	OUT		SREG, R16
	POP		R16
	RETI


// --------------------------------------------------------------------
// | RUTINAS DE INTERRUPCIÓN CON TIMER0								  |
// --------------------------------------------------------------------
// CAMBIO DE SEÑAL DE MULTIPLEXADO
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

// - ESTAS SUBRUTINAS SE COMPARTEN CON LAS SUBRUTINAS DE PC ----------------------
COMPARACION_MINUTOS_HORAS_INC:	
	// Si MINUTE_COUNT es mayor o igual a 60, limpiarlo e incrementar HOUR_COUNT
	CPI		MINUTE_COUNT, 60
	BRLO	INTERMEDIATE_JUMP1
	CLR		MINUTE_COUNT
	INC		HOUR_COUNT

COMPARACION_HORAS_DIAS_INC:
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
	RJMP	COMPARACION_DIAS_MESES_INC

INTERMEDIATE_JUMP1:
	JMP	END_T1PC_ISR

	
// COMPARACIONES PARA INCREMENTO DE MESES
COMPARACION_DIAS_MESES_INC:	
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
	CPI		DAY_COUNT, 29
    BRLO	END_T1PC_ISR

	// Si han pasado más de 28 días, reiniciar contador de días
    LDI		DAY_COUNT, 1
    RJMP	INCREMENTAR_MES

MESES_30:
	// Verificar si el contador de días pasa de 30
	CPI		DAY_COUNT, 31
    BRLO	END_T1PC_ISR

	// Si han pasado más de 30 días, reiniciar contador de días
    LDI		DAY_COUNT, 1
	RJMP	INCREMENTAR_MES

MESES_31:
	// Verificar si el contador pasa de 31
	CPI		DAY_COUNT, 32
    BRLO	END_T1PC_ISR

	// Si han pasado más de 31 días, reiniciar contadores de días
    LDI		DAY_COUNT, 1
	RJMP	INCREMENTAR_MES

// INCREMENTAR MES
INCREMENTAR_MES:
	// INCREMENTAR contador de meses
	INC		MONTH_COUNT
	CPI		MONTH_COUNT, 13
	BRLO	END_T1PC_ISR

	// Si las unidades de meses excenden 12, reiniciar ambos contadores
	LDI		MONTH_COUNT, 1
	RJMP	END_T1PC_ISR

// Terminar Rutina de Interrupción
END_T1PC_ISR:
	// Después de haber cambiado hora y minutos, ver si hay que prender la alarma
	CALL	ALARMA_INTERRUPT

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

	// INCREMENTAR en 1 la máscara de OUTPORTD para modos de cambio de contadores
	INC		T2COSC ; INCREMENTAR en 1 el último bit de este registro

	// Aquí va a saltar a END_T2_ISR

/*
NOTA:
Obsérve cómo usamos T2COSC como un oscilador de frecuencia variable. Al tomar un bit de mayor orden incrementamos
la frecuencia de oscilación.
*/


// Terminar Rutina de Interrupción
END_T2_ISR:
	POP		R16
	OUT		SREG, R16
	POP		R16
	RETI

// --------------------------------------------------------------------
// | SUBRUTINAS_COMPARTIDAS											  |
// --------------------------------------------------------------------
// RUTINA NO DE INTERRUPCIÓN QUE PODRÍA FULMINARSE
ALARMA_INTERRUPT:
	CP		MINUTE_COUNT, ALARM_MINUTES
	BREQ	ALARMA_COMPARAR_HORAS
	RET

ALARMA_COMPARAR_HORAS:
	CP		HOUR_COUNT, ALARM_HOUR
	BRNE	NO_ACTIVAR_ALARMA
	SBI		PORTB, PB5
	RET

NO_ACTIVAR_ALARMA:
	RET
	