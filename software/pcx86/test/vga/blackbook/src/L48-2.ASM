; Mode X (320x240, 256 colors) rectangle 4x4 pattern fill routine.
; Upper left corner of pattern is always aligned to a multiple-of-4
; row and column. Works on all VGAs. Uses approach of copying the
; pattern to off-screen display memory, then loading the latches with
; the pattern for each scan line and filling each scan line four
; pixels at a time. Fills up to but not including the column at EndX
; and the row at EndY. No clipping is performed. All ASM code tested
; with TASM. C near-callable as:
;
;    void FillPatternX(int StartX, int StartY, int EndX, int EndY,
;	unsigned int PageBase, char* Pattern);

SC_INDEX	equ	03c4h	;Sequence Controller Index register port
MAP_MASK	equ	02h	;index in SC of Map Mask register
GC_INDEX	equ	03ceh	;Graphics Controller Index register port
BIT_MASK	equ	08h	;index in GC of Bit Mask register
PATTERN_BUFFER	equ	0fffch	;offset in screen memory of the buffer used
				; to store each pattern during drawing
SCREEN_SEG	equ	0a000h	;segment of display memory in Mode X
SCREEN_WIDTH	equ	80	;width of screen in addresses from one scan
				; line to the next
parms	struc
	dw	2 dup (?)	;pushed BP and return address
StartX	dw	?		;X coordinate of upper left corner of rect
StartY	dw	?		;Y coordinate of upper left corner of rect
EndX	dw	?		;X coordinate of lower right corner of rect
				; (the row at EndX is not filled)
EndY	dw	?		;Y coordinate of lower right corner of rect
				; (the column at EndY is not filled)
PageBase dw	?		;base offset in display memory of page in
				; which to fill rectangle
Pattern dw	?		;4x4 pattern with which to fill rectangle
parms	ends

NextScanOffset	 equ   -2	;local storage for distance from end of one
				; scan line to start of next
RectAddrWidth	 equ   -4	;local storage for address width of rectangle
Height		 equ   -6	;local storage for height of rectangle
STACK_FRAME_SIZE equ	6

	.model	small
	.data
; Plane masks for clipping left and right edges of rectangle.
LeftClipPlaneMask	db	00fh,00eh,00ch,008h
RightClipPlaneMask	db	00fh,001h,003h,007h
	.code
	public	_FillPatternX
_FillPatternX proc    near
	push	bp		;preserve caller's stack frame
	mov	bp,sp		;point to local stack frame
	sub	sp,STACK_FRAME_SIZE ;allocate space for local vars
	push	si		;preserve caller's register variables
	push	di

	cld
	mov	ax,SCREEN_SEG	;point ES to display memory
	mov	es,ax
				;copy pattern to display memory buffer
	mov	si,[bp+Pattern] ;point to pattern to fill with
	mov	di,PATTERN_BUFFER ;point ES:DI to pattern buffer
	mov	dx,SC_INDEX	;point Sequence Controller Index to
	mov	al,MAP_MASK	; Map Mask
	out	dx,al
	inc	dx		;point to SC Data register
	mov	cx,4		;4 pixel quadruplets in pattern
DownloadPatternLoop:
	mov	al,1		;
	out	dx,al		;select plane 0 for writes
	movsb			;copy over next plane 0 pattern pixel
	dec	di		;stay at same address for next plane
	mov	al,2		;
	out	dx,al		;select plane 1 for writes
	movsb			;copy over next plane 1 pattern pixel
	dec	di		;stay at same address for next plane
	mov	al,4		;
	out	dx,al		;select plane 2 for writes
	movsb			;copy over next plane 2 pattern pixel
	dec	di		;stay at same address for next plane
	mov	al,8		;
	out	dx,al		;select plane 3 for writes
	movsb			;copy over next plane 3 pattern pixel
				; and advance address
	loop	DownloadPatternLoop

	mov	dx,GC_INDEX	;set the bit mask to select all bits
	mov	ax,00000h+BIT_MASK ; from the latches and none from
	out	dx,ax		; the CPU, so that we can write the
				; latch contents directly to memory
	mov	ax,[bp+StartY]	;top rectangle scan line
	mov	si,ax
	and	si,011b		;top rect scan line modulo 4
	add	si,PATTERN_BUFFER ;point to pattern scan line that
				; maps to top line of rect to draw
	mov	dx,SCREEN_WIDTH
	mul	dx		;offset in page of top rectangle scan line
	mov	di,[bp+StartX]
	mov	bx,di
	shr	di,1		;X/4 = offset of first rectangle pixel in scan
	shr	di,1		; line
	add	di,ax		;offset of first rectangle pixel in page
	add	di,[bp+PageBase] ;offset of first rectangle pixel in
				; display memory
	and	bx,0003h	;look up left edge plane mask
	mov	ah,LeftClipPlaneMask[bx] ; to clip
	mov	bx,[bp+EndX]
	and	bx,0003h	;look up right edge plane
	mov	al,RightClipPlaneMask[bx] ; mask to clip
	mov	bx,ax		;put the masks in BX

	mov	cx,[bp+EndX]	;calculate # of addresses across rect
	mov	ax,[bp+StartX]
	cmp	cx,ax
	jle	FillDone	;skip if 0 or negative width
	dec	cx
	and	ax,not 011b
	sub	cx,ax
	shr	cx,1
	shr	cx,1		;# of addresses across rectangle to fill - 1
	jnz	MasksSet	;there's more than one pixel to draw
	and	bh,bl		;there's only one pixel, so combine the left
				; and right edge clip masks
MasksSet:
	mov	ax,[bp+EndY]
	sub	ax,[bp+StartY]	;AX = height of rectangle
	jle	FillDone	;skip if 0 or negative height
	mov	[bp+Height],ax
	mov	ax,SCREEN_WIDTH
	sub	ax,cx		;distance from end of one scan line to start
	dec	ax		; of next
	mov	[bp+NextScanOffset],ax
	mov	[bp+RectAddrWidth],cx ;remember width in addresses - 1
	mov	dx,SC_INDEX+1	;point to Sequence Controller Data reg
				; (SC Index still points to Map Mask)
FillRowsLoop:
	mov	cx,[bp+RectAddrWidth] ;width across - 1
	mov	al,es:[si]	;read display memory to latch this scan
				; line's pattern
	inc	si		;point to the next pattern scan line, wrapping
	jnz	short NoWrap	; back to the start of the pattern if
	sub	si,4		; we've run off the end
NoWrap:
	mov	al,bh		;put left-edge clip mask in AL
	out	dx,al		;set the left-edge plane (clip) mask
	stosb			;draw the left edge (pixels come from latches;
				; value written by CPU doesn't matter)
	dec	cx		;count off left edge address
	js	FillLoopBottom	;that's the only address
	jz	DoRightEdge	;there are only two addresses
	mov	al,00fh		;middle addresses are drawn 4 pixels at a pop
	out	dx,al		;set the middle pixel mask to no clip
	rep	stosb		;draw the middle addresses four pixels apiece
				; (from latches; value written doesn't matter)
DoRightEdge:
	mov	al,bl		;put right-edge clip mask in AL
	out	dx,al		;set the right-edge plane (clip) mask
	stosb			;draw the right edge (from latches; value
				; written doesn't matter)
FillLoopBottom:
	add	di,[bp+NextScanOffset] ;point to the start of the next scan
				; line of the rectangle
	dec	word ptr [bp+Height] ;count down scan lines
	jnz	FillRowsLoop
FillDone:
	mov	dx,GC_INDEX+1	;restore the bit mask to its default,
	mov	al,0ffh		; which selects all bits from the CPU
	out	dx,al		; and none from the latches (the GC
				; Index still points to Bit Mask)
	pop	di		;restore caller's register variables
	pop	si
	mov	sp,bp		;discard storage for local variables
	pop	bp		;restore caller's stack frame
	ret
_FillPatternX endp
	end
