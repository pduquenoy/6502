; Motorola S record (run) file loader

; Constants

        ESC     = $1B
        CR      = $0D
        LF      = $0A
        NUL     = $00

; Zero page addresses

        address = $38           ; Instruction address, 2 bytes (low/high)

; External routines

        GetKey  = $E9C4         ; ROM get character routine
        PrintString = $EAF9     ; ROM print string routine
        PrintCR     = $EAE9     ; Print CR

        .org    $2000

start:
        lda     #0
        sta     checksum        ; Checksum = 0
        sta     bytesRead       ; BytesRead = 0
        sta     byteCount       ; ByteCount = 0
        sta     address         ; Address = 0
        sta     address+1

loop:
        jsr     GetKey          ; Get character
        cmp     #ESC
        bne     notesc
        rts                     ; Return if <ESC>
notesc:
        cmp     #CR             ; Ignore if <CR>
        beq     loop
        cmp     #LF             ; Ignore if <LF>
        beq     loop
        cmp     #NUL            ; Ignore if <NUL>
        beq     loop

        cmp     #'S'            ; Should be 'S'
        bne     invalidRecord   ; If not, error

        jsr     GetKey          ; Get record type character
        cmp     #'0'            ; Should be '0', '1', '5', '6' or '9'
        beq     validType
        cmp     #'1'
        beq     validType
        cmp     #'5'
        beq     validType
        cmp     #'6'
        beq     validType
        cmp     #'9'
        beq     validType

invalidRecord:
        ldx     #<SInvalidRecord
        ldy     #>SInvalidRecord
        jsr     PrintString     ; Display "Invalid record"
        jsr     PrintCR
        rts                     ; Return

validType:
        sta     recordType      ; Save char as record type '0'..'9'

        jsr     getHexByte      ; Get byte count
        bcs     invalidRecord 
        cmp     #3              ; Invalid if byteCount  < 3
        bmi     invalidRecord
        sta     byteCount       ; Save as byte count

        clc
        adc     checksum        ; Add byte count to checksum

; TODO: If record type is 9, byte count should be 3. Should we check
; this?

        jsr     getHexAddress   ; Get 16-bit start address
        bcs     invalidRecord

        stx     address         ; Save as address
        sty     address+1

        clc
        txa
        adc     checksum        ; Add address bytes to checksum
        clc
        tya
        adc     checksum

readRecord:

        lda     bytesRead       ; If bytesRead = byteCount
        cmp     byteCount
        beq     dataend         ; ...break out of loop

        jsr     getHexByte      ; Get two hex digits
        bcs     invalidRecord   ; Exit if invalid

        clc
        adc     checksum        ; Add data read to checksum

        sta     temp1           ; Save data
        lda     recordType
        cmp     #1              ; Is record type 1?
        bne     nowrite
        lda     temp1           ; Get data back
        ldy     #0
        sta     (address),y     ; Write data to address

; TODO: Could verify data written, but not necessarily an error.

nowrite:
        inc     address         ; Increment address (low byte)
        bne     nocarry
        inc     address+1       ; Increment address (high byte)
nocarry:        
        inc     bytesRead       ; Increment bytesRead
        jmp     readRecord      ; Go back and read more data

dataend:
        jsr     getHexByte      ; Get two hex digits (checksum)
        bcs     invalidRecord

        eor     #$FF            ; Calculate 1's complement

        cmp     checksum        ; Compare to calculated checksum
        beq     sumokay         ; branch if matches
        ldx     #<SChecksumError
        ldy     #>SChecksumError
        jsr     PrintString     ; Display "Checksum error"
        jsr     PrintCR
        rts                     ; Return

sumokay:
        lda     recordType      ; Get record type
        cmp     #'9'            ; S9 (end of file)?
        beq     s9
        jmp     start           ; If not go back and read more records
s9:
        lda     address         ; If start address != 0
        bne     notz
        lda     address+1
        bne     notz
        jmp     (address)       ; ...start execution at start address

notz:
        rts                     ; Return

; Read character corresponding to hex number ('0'-'9','A'-'F').
; If valid, return binary value in A and carry bit clear.
; If not valid, return with carry bit set.
getHexChar:
        jsr     GetKey          ; Read character
        cmp     #'0'            ; Error if < '0'
        bmi     error1
        cmp     #'9'+1          ; Valid if <= '9'
        bmi     number1
        cmp     #'F'            ; Error if >'F'
        bpl     error1
        cmp     #'A'            ; Error if < 'A'
        bmi     error1
        sec
        sbc     #'A'-10         ; Value is character-('A'-10)
        jmp     good1
number1:
        sec
        sbc     #'0'            ; Value is character-'0'
        jmp     good1
error1:
        sec                     ; Set carry to indicate error
        rts                     ; Return
good1:
        clc                     ; Clear carry to indicate valid
        rts                     ; Return

; Read two characters corresponding to 8-bit hex number.
; If valid, return binary value in A and carry bit clear.
; If not valid, return with carry bit set.
getHexByte:
        jsr     getHexChar      ; Get high nybble
        bcs     bad1            ; Branch if invalid
        asl                     ; Shift return value left to upper nybble
        asl 
        asl 
        asl 
        sta     temp1           ; Save value
        jsr     getHexChar      ; Get low nybble
        bcs     bad1            ; Branch if invalid
        ora     temp1           ; Add (OR) return value to previous value
        rts                     ; Return with carry clear

; Read four characters corresponding to 16-bit hex address.
; If valid, return binary value in X (low) and Y (high) and carry bit clear.
; If not valid, return with carry bit set.
getHexAddress:
        jsr     getHexByte      ; Get high order byte
        bcs     bad1            ; Branch if invalid
        tax                     ; Save value in Y
        jsr     getHexByte      ; Get low order byte
        bcs     bad1            ; Branch if invalid
        tay                     ; Save value in X
        rts                     ; Return with carry clear
bad1:
        rts                     ; Return with carry set

; Strings

SInvalidRecord:
        .asciiz "Invalid record"
SChecksumError:
        .asciiz "Checksum error"

; Variables

temp1:      .res  1             ; Temporary
checksum:   .res 1              ; Calculated checksum
bytesRead:  .res 1              ; Number of record bytes read 
recordType: .res 1              ; S record type field, e.g '9'
byteCount:  .res 1              ; S record byte count field