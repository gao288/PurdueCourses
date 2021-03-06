;***********************************************************************
; ECE 362 - Lab 9 Demo Code
;***********************************************************************
;
; This program demonstrates ATD-PWM audio digitization and reconstruction 
; as well as a "digital volume control". The ATD input sampling frequency 
; is 10,000 HZ and the PWM output sampling frequency is 47,059 Hz.
;
;***********************************************************************
;
; Resources used:
;  - TIM TC7  - interrupt every 0.1 ms, used to initiate ATD conversion
;  - ATD Ch 0 - audio input (PIN 5 on BREADBOARD HEADER)
;  - ATD Ch 1 - potentiometer input for digital volume control (PIN 6 on
;               BREADBOARD HEADER)
;  - PWM Ch 0 - audio output (PIN 27 on BREADBOARD HEADER)
;
; CAUTION: Carefully adjust the function generator analog output for   va
;          D.C. offset of +2.0 V and a peak voltage no greater than 4.0 V
;          (use the oscilloscope to confirm).  Failure to do so may
;          damage your microcontroller chip.
;
;======================================================================== 
;
; 9S12C32 REGISTER MAP

INITRM	EQU	$0010	; INITRM - INTERNAL RAM POSITION REGISTER
INITRG	EQU	$0011	; INITRG - INTERNAL REGISTER POSITION REGISTER

; ==== CRG - Clock and Reset Generator

SYNR	EQU	$0034	; CRG synthesizer register
REFDV	EQU	$0035	; CRG reference divider register
CRGFLG	EQU	$0037	; CRG flags register
CRGINT	EQU	$0038
CLKSEL	EQU	$0039	; CRG clock select register
PLLCTL	EQU	$003A	; CRG PLL control register
RTICTL	EQU	$003B
COPCTL	EQU	$003C

; ==== ATD (analog to Digital) Converter 

ATDCTL2	EQU	$0082	; ATDCTL2 control register
ATDCTL3	EQU	$0083	; ATDCTL3 control register
ATDCTL4	EQU	$0084	; ATDCTL4 control register
ATDCTL5	EQU	$0085	; ATDCTL5 control register
ATDSTAT	EQU	$0086	; ATDSTAT0 status register

ATDDR0	EQU	$0090	; result register array (16-bit values)
ATDDR1 	EQU	$0092

; ==== Direct Port Pin Access/Control - Port T

PTT	EQU	$0240	; Port T data register
DDRT	EQU	$0242	; Port T data direction register

; ==== TIM - Timer 16 Bit 8 Channels

TIOS	EQU	$0040	;TIOS - TIMER INPUT CAPTURE/OUTPUT COMPARE SELECT
TCNT	EQU	$0044
TSCR1	EQU	$0046	;TSCR - TIMER SYSTEM CONTROL REGISTER
TIE	EQU	$004C
TSCR2	EQU	$004D
TFLG1	EQU	$004E	;TFLG1 - TIMER INTERRUPT FLAG 1
TC7	EQU	$005E	;TC7 - TIMER INPUT/CAPTURE COMPARE HIGH REGISTER

; ==== IMPORTANT -- Routing register for Port T (selects TIM vs PWM mapping)

MODRR	EQU	$0247	; Port T module routing register	
			; NOTE: Used to select TIM or PWM mapping to Port T pins

; ==== PWM - Pulse width Modulator

PWME	 EQU	$00E0	; PWM enable
PWMPOL	 EQU	$00E1	; PWM polarity
PWMCLK	 EQU	$00E2	; PWM clock source select
PWMPRCLK EQU	$00E3	; PWM pre-scale clock select
PWMCAE	 EQU	$00E4	; PWM center align enable
PWMCTL	 EQU	$00E5	; PWM control (concatenate enable)
PWMSCLA	 EQU	$00E8	; PWM clock A scaler
PWMPER0	 EQU	$00F2	; PWM period registers
PWMDTY0	 EQU	$00F8	; PWM duty registers


; ======================================================================

REGBASE	EQU	$0	; registers start at 0000
RAMBASE	EQU	$3800	; 2KB SRAM located at 3800-3FFF

;***********************************************************************
;  BOOT-UP ENTRY POINT
;***********************************************************************

	org	$8000
startup	sei			; Disable interrupts
	movb	#$00,INITRG	; set registers to $0000
	movb	#$39,INITRM	; map RAM ($3800 - $3FFF)
	lds	#$3FCE		; initialize stack pointer

;
; Set the PLL speed (bus clock = 24 MHz)
;

	bclr	CLKSEL,$80	; disengage PLL from system
	bset	PLLCTL,$40	; turn on PLL
	movb	#$2,SYNR	; set PLL multiplier
	movb	#$0,REFDV	; set PLL divider
	nop
	nop
plp	brclr	CRGFLG,$08,plp	; while (!(crg.crgflg.bit.lock==1))
	bset	CLKSEL,$80	; engage PLL 

;
; Disable watchdog timer (COPCTL register)
;
	movb	#$40,COPCTL	; COP off - RTI and COP stopped in BDM-mode


;***********************************************************************
;  START OF CODE 
;***********************************************************************

; initialize ATD (8 bit, unsigned, nominal sample time, seq length = 2)

	movb	#$80,ATDCTL2	; power up ATD
	movb	#$10,ATDCTL3	; set conversion sequence length to TWO
	movb	#$85,ATDCTL4	; select resolution and sample time

; initialize PWM Ch 0 (left aligned, positive polarity, max 8-bit period)

	movb	#$01,MODRR	; PT0 used as PWM Ch 0 output
	movb	#$01,PWME	; enable PWM Ch 0
	movb	#$01,PWMPOL	; set active high polarity
	movb	#$00,PWMCTL	; no concatenate (8-bit)
	movb	#$00,PWMCAE	; left-aligned output mode
	movb	#$FF,PWMPER0	; set maximum 8-bit period
	movb	#$00,PWMDTY0	; initially clear DUTY register
	movb	#$00,PWMCLK	; select Clock A for Ch 0
	movb	#$01,PWMPRCLK	; set Clock A = 12 MHz (prescaler = 2) rate

; initialize TIM Ch 7 (periodic 0.1 ms interrupt)

	movb    #$80,TSCR1	; enable TC7
	movb    #$0C,TSCR2	; set TIM prescale factor to 16
				; and enable counter reset after OC7
	movb    #$80,TIOS 	; set TIM TC7 for Output Compare  
	movb    #$80,TIE 	; enable TIM TC7 interrupt
	movw    #150,TC7	; set up TIM TC7 to generate 0.1 ms interrupt rate

; enable IRQ interrupts

	cli			; enable IRQ interrupts

; do nothing after initialization complete

eloop	bra	eloop		; wait loop	

;***********************************************************************
;
; TIM interrupt service routine
;
; Interrupt generated every 0.1 ms 
;
; Initiate ATD conversion on Chs 0 and 1
;
; Multiply analog input sample by potentiometer sample -> PWM Ch 0
;

tim_isr
	
	bset	TFLG1,$80	; clear TC7 interrupt flag

	movb	#$10,ATDCTL5	; start conversion on ATD Ch 0 (seq. length = 2)
				; NOTE: "mult" (bit 4) needs to be set

await	brclr   ATDSTAT,$80,await

	ldaa	ATDDR0		; analog input sample
	ldab	ATDDR1		; potentiometer sample
	mul			; multiply input sample x potentiometer setting
	adca	#0		; round upper 8 bits of result
	staa	PWMDTY0		; copy result to PWM Ch 0

	rti



;***********************************************************************
;
; Define 'where you want to go today' (reset and interrupt vectors)
;
; If get a "bad" interrupt, just return from it

BadInt	rti

; ------------------ VECTOR TABLE --------------------

	org	$FF8A
	fdb	BadInt	;$FF8A: VREG LVI
	fdb	BadInt	;$FF8C: PWM emergency shutdown
	fdb	BadInt	;$FF8E: PortP
	fdb	BadInt	;$FF90: Reserved
	fdb	BadInt	;$FF92: Reserved
	fdb	BadInt	;$FF94: Reserved
	fdb	BadInt	;$FF96: Reserved
	fdb	BadInt	;$FF98: Reserved
	fdb	BadInt	;$FF9A: Reserved
	fdb	BadInt	;$FF9C: Reserved
	fdb	BadInt	;$FF9E: Reserved
	fdb	BadInt	;$FFA0: Reserved
	fdb	BadInt	;$FFA2: Reserved
	fdb	BadInt	;$FFA4: Reserved
	fdb	BadInt	;$FFA6: Reserved
	fdb	BadInt	;$FFA8: Reserved
	fdb	BadInt	;$FFAA: Reserved
	fdb	BadInt	;$FFAC: Reserved
	fdb	BadInt	;$FFAE: Reserved
	fdb	BadInt	;$FFB0: CAN transmit
	fdb	BadInt	;$FFB2: CAN receive
	fdb	BadInt	;$FFB4: CAN errors
	fdb	BadInt	;$FFB6: CAN wake-up
	fdb	BadInt	;$FFB8: FLASH
	fdb	BadInt	;$FFBA: Reserved
	fdb	BadInt	;$FFBC: Reserved
	fdb	BadInt	;$FFBE: Reserved
	fdb	BadInt	;$FFC0: Reserved
	fdb	BadInt	;$FFC2: Reserved
	fdb	BadInt	;$FFC4: CRG self-clock-mode
	fdb	BadInt	;$FFC6: CRG PLL Lock
	fdb	BadInt	;$FFC8: Reserved
	fdb	BadInt	;$FFCA: Reserved
	fdb	BadInt	;$FFCC: Reserved
	fdb	BadInt	;$FFCE: PORTJ
	fdb	BadInt	;$FFD0: Reserved
	fdb	BadInt	;$FFD2: ATD
	fdb	BadInt	;$FFD4: Reserved
	fdb	BadInt	;$FFD6: SCI Serial System
	fdb	BadInt	;$FFD8: SPI Serial Transfer Complete
	fdb	BadInt	;$FFDA: Pulse Accumulator Input Edge
	fdb	BadInt	;$FFDC: Pulse Accumulator Overflow
	fdb	BadInt	;$FFDE: Timer Overflow
	fdb	tim_isr	;$FFE0: Standard Timer Channel 7
	fdb	BadInt	;$FFE2: Standard Timer Channel 6
	fdb	BadInt	;$FFE4: Standard Timer Channel 5
	fdb	BadInt	;$FFE6: Standard Timer Channel 4
	fdb	BadInt	;$FFE8: Standard Timer Channel 3
	fdb	BadInt	;$FFEA: Standard Timer Channel 2
	fdb	BadInt	;$FFEC: Standard Timer Channel 1
	fdb	BadInt	;$FFEE: Standard Timer Channel 0
	fdb	BadInt	;$FFF0: Real Time Interrupt (RTI)
	fdb	BadInt	;$FFF2: IRQ (External Pin or Parallel I/O) (IRQ)
	fdb	BadInt	;$FFF4: XIRQ (Pseudo Non-Maskable Interrupt) (XIRQ)
	fdb	BadInt	;$FFF6: Software Interrupt (SWI)
	fdb	BadInt	;$FFF8: Illegal Opcode Trap ()
	fdb	startup	;$FFFA: COP Failure (Reset) ()
	fdb	BadInt	;$FFFC: Clock Monitor Fail (Reset) ()
	fdb	startup	;$FFFE: /RESET
	end


