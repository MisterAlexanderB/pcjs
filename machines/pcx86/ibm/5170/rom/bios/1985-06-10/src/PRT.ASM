PAGE 118,121
TITLE PRT ------ 06/10/85 PRINTER ADAPTER BIOS
.286C
.XLIST
INCLUDE DSEG.INC
INCLUDE POSTEQU.INC
.LIST
CODE	SEGMENT BYTE PUBLIC

	PUBLIC	PRINTER_IO_1
	EXTRN	DDS:NEAR

;--- INT  17 H -----------------------------------------------------------------
; PRINTER_IO								       :
;	THIS ROUTINE PROVIDES COMMUNICATION WITH THE PRINTER		       :
; INPUT 								       :
;	(AH)= 00H  PRINT THE CHARACTER IN (AL)				       :
;		    ON RETURN, (AH)= 1 IF CHARACTER NOT BE PRINTED (TIME OUT)  :
;		    OTHER BITS SET AS ON NORMAL STATUS CALL		       :
;	(AH)= 01H  INITIALIZE THE PRINTER PORT				       :
;		    RETURNS WITH (AH) SET WITH PRINTER STATUS		       :
;	(AH)= 02H  READ THE PRINTER STATUS INTO (AH)			       :
;		   7	   6	   5	   4	   3	   2-1	   0	       :
;		   |	   |	   |	   |	   |	   |	   |_TIME OUT  :
;		   |	   |	   |	   |	   |	   |		       :
;		   |	   |	   |	   |	   |	   |_ UNUSED	       :
;		   |	   |	   |	   |	   |			       :
;		   |	   |	   |	   |	   |_ 1 = I/O ERROR	       :
;		   |	   |	   |	   |				       :
;		   |	   |	   |	   |_ 1 = SELECTED		       :
;		   |	   |	   |					       :
;		   |	   |	   |_ 1 = OUT OF PAPER			       :
;		   |	   |						       :
;		   |	   |_ 1 = ACKNOWLEDGE				       :
;		   |							       :
;		   |_ 1 = NOT BUSY					       :
;									       :
;	(DX) = PRINTER TO BE USED (0,1,2) CORRESPONDING TO ACTUAL VALUES       :
;		IN @PRINTER_BASE AREA					       :
; DATA AREA @PRINTER_BASE CONTAINS THE BASE ADDRESS OF THE PRINTER CARD(S)     :
; AVAILABLE (LOCATED AT BEGINNING OF DATA SEGMENT, 408H ABSOLUTE, 3 WORDS)     :
;									       :
; DATA AREA @PRINT_TIM_OUT (BYTE) MAY BE CHANGED TO CAUSE DIFFERENT	       :
; TIME OUT WAITS. DEFAULT=20 * 4					       :
;									       :
; REGISTERS	(AH) IS MODIFIED WITH STATUS INFORMATION		       :
;		ALL OTHERS UNCHANGED					       :
;-------------------------------------------------------------------------------
	ASSUME	CS:CODE,DS:DATA

PRINTER_IO_1	PROC	FAR		; ENTRY POINT FOR ORG 0EFD2H
	STI				; INTERRUPTS BACK ON
	PUSH	DS			; SAVE SEGMENT
	PUSH	SI
	PUSH	DX
	PUSH	CX
	PUSH	BX
	CALL	DDS			; ADDRESS DATA SEGMENT
	MOV	SI,DX			; GET PRINTER PARAMETER
	MOV	BL,@PRINT_TIM_OUT[SI]	; LOAD TIMEOUT VALUE
	SHL	SI,1			; WORD OFFSET INTO TABLE INTO (SI)
	MOV	DX,@PRINTER_BASE[SI]	; GET BASE ADDRESS FOR PRINTER CARD
	OR	DX,DX			; TEST DX = ZERO, INDICATING NO PRINTER
	JZ	B10			; EXIT, NO PRINTER ADAPTER AT OFFSET
	OR	AH,AH			; TEST FOR (AH)= 00H
	JZ	B20			;  PRINT CHARACTER IN (AL)
	DEC	AH			; TEST FOR (AH)= 01H
	JZ	B80			;  INITIALIZE PRINTER
	DEC	AH			; TEST FOR (AH)= 02H
	JZ	B50			;  GET PRINTER STATUS
B10:
	POP	BX			; RETURN
	POP	CX
	POP	DX
	POP	SI			; RECOVER REGISTERS
	POP	DS
	IRET				; RETURN TO CALLING PROGRAM

;-----	PRINT THE CHARACTER IN (AL)

B20:
	PUSH	AX			; SAVE VALUE TO PRINT
	OUT	DX,AL			; OUTPUT CHARACTER TO DATA PORT
	INC	DX			; POINT TO STATUS PORT

;-----	CHECK FOR PRINTER BUSY

	PUSH	BX			; SAVE TIMEOUT BASE COUNT
	IN	AL,DX			; GET STATUS PORT VALUE
	TEST	AL,80H			; IS THE PRINTER CURRENTLY BUSY
	JNZ	B25			; SKIP SYSTEM DEVICE BUSY CALL IF NOT

;-----	INT 15 H -- DEVICE BUSY

	MOV	AX,90FEH		; FUNCTION 90 PRINTER ID
	INT	15H			; SYSTEM CALL

;-----	WAIT BUSY

B25:					; ADJUST OUTER LOOP COUNT
	SUB	BH,BH			; CLEAR (BH)
	RCL	BX,2			; MULTIPLY BY 4
B30:
	SUB	CX,CX			; INNER LOOP (64K)
B35:
	IN	AL,DX			; GET	STATUS
	MOV	AH,AL			; STATUS TO (AH) ALSO
	TEST	AL,80H			; IS THE PRINTER CURRENTLY BUSY
	JNZ	B40			; GO TO OUTPUT STROBE
	LOOP	B35			; LOOP IF NOT
	DEC	BX			; DECREMENT OUTER LOOP COUNT
	JNZ	B30			; MAKE ANOTHER PASS IF NOT ZERO

	POP	BX			; CLEAR (BX) FROM STACK
	OR	AH,1			; SET	ERROR FLAG
	AND	AH,0F9H 		; TURN OFF THE UNUSED BITS
	JMP	SHORT B70		; RETURN WITH ERROR FLAG SET

B40:					;	  SEND STROBE PULSE
	POP	BX			; RESTORE (BX) WITH TIMEOUT COUNT
	MOV	AL,0DH			; SET THE STROBE LOW (BIT ON)
	INC	DX			; OUTPUT STROBE TO CONTROL PORT
	CLI				; PREVENT INTERRUPT PULSE STRETCHING
	OUT	DX,AL			; OUTPUT STROBE BIT   > 1us  < 5us
	JMP	$+2			; I/O DELAY TO ALLOW FOR LINE LOADING
	JMP	$+2			;  AND FOR CORRECT PULSE WIDTH
	MOV	AL,0CH			; SET THE -STROBE HIGH
	OUT	DX,AL
	STI				; INTERRUPTS BACK ON
	POP	AX			; RECOVER THE OUTPUT CHAR

;-----	PRINTER STATUS

B50:
	PUSH	AX			; SAVE (AL) REGISTER
B60:
	MOV	DX,@PRINTER_BASE[SI]	; GET PRINTER ATTACHMENT BASE ADDRESS
	INC	DX			; POINT TO CONTROL PORT
	IN	AL,DX			; PRE-CHARGE +BUSY LINE IF FLOATING
	IN	AL,DX			; GET PRINTER STATUS HARDWARE BITS
	MOV	AH,AL			; SAVE
	AND	AH,0F8H 		; TURN OFF UNUSED BITS

B70:	POP	DX			; RECOVER (AL) REGISTER
	MOV	AL,DL			; MOVE CHARACTER INTO (AL)
	XOR	AH,48H			; FLIP A COUPLE OF BITS
	JMP	B10			; RETURN FROM ROUTINE WITH STATUS IN AH

;-----	INITIALIZE THE PRINTER PORT

B80:
	PUSH	AX			; SAVE (AL)
	INC	DX			; POINT TO OUTPUT PORT
	INC	DX
	MOV	AL,8			; SET INIT LINE LOW
	OUT	DX,AL
	MOV	AX,1000*4		; ADJUST FOR INITIALIZATION DELAY LOOP
B90:					; INIT_LOOP
	DEC	AX			; LOOP FOR RESET TO TAKE
	JNZ	B90			; INIT_LOOP
	MOV	AL,0CH			; NO INTERRUPTS, NON AUTO LF, INIT HIGH
	OUT	DX,AL
	JMP	B60			; EXIT THROUGH STATUS ROUTINE

PRINTER_IO_1	ENDP

	CODE	ENDS
	END
