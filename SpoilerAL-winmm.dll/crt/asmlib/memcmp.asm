.686
.xmm
.model flat

public _memcmp

extern _InstructionSet: near

.data

memcmpDispatch dd memcmpCPUDispatch

.code

; Function entry:
align 16
_memcmp proc near
	jmp     dword ptr [memcmpDispatch]                  ; Go to appropriate version, depending on instruction set
_memcmp endp

if 0
; AVX512BW Version. Use zmm register
align 16
memcmpAVX512BW proc near
	push    esi
	push    edi
	mov     esi, dword ptr [esp + 12]                   ; ptr1
	mov     edi, dword ptr [esp + 16]                   ; ptr2
	mov     ecx, dword ptr [esp + 20]                   ; size
	cmp     ecx, 40H
	jbe     L820
	cmp     ecx, 80H
	jbe     L800

	; count >= 80H
L010 label near
	; entry from memcmpAVX512F
	vmovdqu64 zmm0, zmmword ptr [esi]
	vmovdqu64 zmm1, zmmword ptr [edi]
	vpcmpd  k1, zmm0, zmm1, 4                           ; compare first 40H bytes for dwords not equal
	kortestw k1, k1
	jnz     L500                                        ; difference found

	; find 40H boundaries
	lea     edx, dword ptr [esi + ecx]                  ; end of string 1
	mov     eax, esi
	add     esi, 40H
	and     esi, -40H                                   ; first aligned boundary for esi
	sub     eax, esi                                    ; -offset
	sub     edi, eax                                    ; same offset to edi
	mov     eax, edx
	and     edx, -40H                                   ; last aligned boundary for esi
	sub     esi, edx                                    ; esi = -size of aligned blocks
	sub     edi, esi

	align   16
L100:
	; main loop
	vmovdqa64 zmm0, zmmword ptr [edx + esi]
	vmovdqu64 zmm1, zmmword ptr [edi + esi]
	vpcmpd  k1, zmm0, zmm1, 4                           ; compare first 40H bytes for not equal
	kortestw k1, k1
	jnz     L500                                        ; difference found
	add     esi, 40H
	jnz     L100

	; remaining 0-3FH bytes. Overlap with previous block
	add     edi, eax
	sub     edi, edx
	vmovdqu64 zmm0, zmmword ptr [eax - 40H]
	vmovdqu64 zmm1, zmmword ptr [edi - 40H]
	vpcmpd  k1, zmm0, zmm1, 4                           ; compare first 40H bytes for not equal
	kortestw k1, k1
	jnz     L500                                        ; difference found

	; finished. no difference found
	xor     eax, eax
	vzeroupper
	pop     edi
	pop     esi
	ret

	align   16
L500:
	; the two strings are different
	vpcompressd zmm0{k1}{z}, zmm0                       ; get first differing dword to position 0
	vpcompressd zmm1{k1}{z}, zmm1                       ; get first differing dword to position 0
	vmovd   eax, xmm0
	vmovd   edx, xmm1
	mov     ecx, eax
	xor     ecx, edx                                    ; difference
	bsf     ecx, ecx                                    ; position of lowest differing bit
	and     ecx, -8                                     ; round down to byte boundary
	shr     eax, cl                                     ; first differing byte in al
	shr     edx, cl                                     ; first differing byte in dl
	movzx   eax, al                                     ; zero-extend bytes
	movzx   edx, dl
	sub     eax, edx                                    ; signed difference between unsigned bytes
	vzeroupper
	pop     edi
	pop     esi
	ret

	align   16
L800:
	; size = 41H - 80H
	vmovdqu64 zmm0, zmmword ptr [esi]
	vmovdqu64 zmm1, zmmword ptr [edi]
	vpcmpd  k1, zmm0, zmm1, 4                           ; compare first 40H bytes for not equal
	kortestw k1, k1
	jnz     L500                                        ; difference found
	add     esi, 40H
	add     edi, 40H
	sub     ecx, 40H

L820:
	; size = 00H - 40H
	; (this is the only part that requires AVX512BW)
	or      eax, -1                                     ; if count = 1-31: |  if count = 32-63:
	bzhi    eax, eax, ecx                               ; -----------------|--------------------
	kmovd   k1, eax                                     ;       count 1's  |  all 1's
	xor     eax, eax                                    ;                  |
	sub     ecx, 32                                     ;                  |
	cmovb   ecx, eax                                    ;               0  |  count-32
	dec     eax                                         ;                  |
	bzhi    eax, eax, ecx                               ;                  |
	kmovd   k2, eax                                     ;               0  |  count-32 1's
	kunpckdq k3, k2, k1                                 ; low 32 bits from k1, high 32 bits from k2. total = count 1's

	vmovdqu8 zmm0{k3}{z}, zmmword ptr [esi]
	vmovdqu8 zmm1{k3}{z}, zmmword ptr [edi]
	vpcmpd  k1, zmm0, zmm1, 4                           ; compare
	kortestw k1, k1
	jnz     L500                                        ; difference found
	xor     eax, eax                                    ; no difference found
	vzeroupper
	pop     edi
	pop     esi
	ret
memcmpAVX512BW endp

; AVX512F Version. Use zmm register
align 16
memcmpAVX512F proc near
	push    esi
	push    edi
	mov     esi, dword ptr [esp + 12]                   ; ptr1
	mov     edi, dword ptr [esp + 16]                   ; ptr2
	mov     ecx, dword ptr [esp + 20]                   ; size
	cmp     ecx, 80H                                    ; size
	jae     L010                                        ; continue in memcmpAVX512BW
	jmp     A001                                        ; continue in memcmpAVX2 if less than 80H bytes
memcmpAVX512F endp

; AVX2 Version. Use ymm register
align 16
memcmpAVX2 proc near
	push    esi
	push    edi
	mov     esi, dword ptr [esp + 12]                   ; ptr1
	mov     edi, dword ptr [esp + 16]                   ; ptr2
	mov     ecx, dword ptr [esp + 20]                   ; size

A001 label near
	; entry from above
	add     esi, ecx                                    ; use negative index from end of memory block
	add     edi, ecx
	neg     ecx
	jz      A900
	mov     edx, 0FFFFH
	cmp     ecx, -32
	ja      A100

A000:
	; loop comparing 32 bytes
	vmovdqu ymm1, ymmword ptr [esi + ecx]
	vpcmpeqb ymm0, ymm1, ymmword ptr [edi + ecx]        ; compare 32 bytes
	vpmovmskb eax, ymm0                                 ; get byte mask
	xor     eax, -1                                     ; not eax would not set flags
	jnz     A700                                        ; difference found
	add     ecx, 32
	jz      A900                                        ; finished, equal
	cmp     ecx, -32
	jna     A000                                        ; next 32 bytes
	vzeroupper                                          ; end ymm state

A100:
	; less than 32 bytes left
	cmp     ecx, -16
	ja      A200
	movdqu  xmm1, xmmword ptr [esi + ecx]
	movdqu  xmm2, xmmword ptr [edi + ecx]
	pcmpeqb xmm1, xmm2                                  ; compare 16 bytes
	pmovmskb eax, xmm1                                  ; get byte mask
	xor     eax, edx                                    ; not ax
	jnz     A701                                        ; difference found
	add     ecx, 16
	jz      A901                                        ; finished, equal

A200:
	; less than 16 bytes left
	cmp     ecx, -8
	ja      A300
	; compare 8 bytes
	movq    xmm1, qword ptr [esi + ecx]
	movq    xmm2, qword ptr [edi + ecx]
	pcmpeqb xmm1, xmm2                                  ; compare 8 bytes
	pmovmskb eax, xmm1                                  ; get byte mask
	xor     eax, edx                                    ; not ax
	jnz     A701                                        ; difference found
	add     ecx, 8
	jz      A901

A300:
	; less than 8 bytes left
	cmp     ecx, -4
	ja      A400
	; compare 4 bytes
	movd    xmm1, dword ptr [esi + ecx]
	movd    xmm2, dword ptr [edi + ecx]
	pcmpeqb xmm1, xmm2                                  ; compare 4 bytes
	pmovmskb eax, xmm1                                  ; get byte mask
	xor     eax, edx                                    ; not ax
	jnz     A701                                        ; difference found
	add     ecx, 4
	jz      A901

A400:
	; less than 4 bytes left
	cmp     ecx, -2
	ja      A500
	movzx   eax, word ptr [esi + ecx]
	movzx   edx, word ptr [edi + ecx]
	sub     eax, edx
	jnz     A800                                        ; difference in byte 0 or 1
	add     ecx, 2
	jz      A901

A500:
	; less than 2 bytes left
	test    ecx, ecx
	jz      A901                                        ; no bytes left

A600:
	; one byte left
	movzx   eax, byte ptr [esi + ecx]
	movzx   edx, byte ptr [edi + ecx]
	sub     eax, edx                                    ; return result
	pop     edi
	pop     esi
	ret

	align   16
A700:
	; difference found. find position
	vzeroupper

A701:
	bsf     eax, eax
	add     ecx, eax
	movzx   eax, byte ptr [esi + ecx]
	movzx   edx, byte ptr [edi + ecx]
	sub     eax, edx                                    ; return result
	pop     edi
	pop     esi
	ret

	align   16
A800:
	; difference in byte 0 or 1
	neg     al
	sbb     ecx, -1                                     ; add 1 to ecx if al == 0
	movzx   eax, byte ptr [esi + ecx]
	movzx   edx, byte ptr [edi + ecx]
	sub     eax, edx                                    ; return result
	pop     edi
	pop     esi
	ret

	align   16
A900:
	; equal
	vzeroupper

A901:
	xor     eax, eax
	pop     edi
	pop     esi
	ret
memcmpAVX2 endp

; SSE2 version. Use xmm register
align 16
memcmpSSE2 proc near
	push    esi
	push    edi
	mov     esi, dword ptr [esp + 12]                   ; ptr1
	mov     edi, dword ptr [esp + 16]                   ; ptr2
	mov     ecx, dword ptr [esp + 20]                   ; size
	add     esi, ecx                                    ; use negative index from end of memory block
	add     edi, ecx
	neg     ecx
	jz      S900
	mov     edx, 0FFFFH
	cmp     ecx, -16
	ja      S200

S100:
	; loop comparing 16 bytes
	movdqu  xmm1, xmmword ptr [esi + ecx]
	movdqu  xmm2, xmmword ptr [edi + ecx]
	pcmpeqb xmm1, xmm2                                  ; compare 16 bytes
	pmovmskb eax, xmm1                                  ; get byte mask
	xor     eax, edx                                    ; not ax
	jnz     S700                                        ; difference found
	add     ecx, 16
	jz      S900                                        ; finished, equal
	cmp     ecx, -16
	jna     S100                                        ; next 16 bytes

S200:
	; less than 16 bytes left
	cmp     ecx, -8
	ja      S300
	; compare 8 bytes
	movq    xmm1, qword ptr [esi + ecx]
	movq    xmm2, qword ptr [edi + ecx]
	pcmpeqb xmm1, xmm2                                  ; compare 8 bytes
	pmovmskb eax, xmm1                                  ; get byte mask
	xor     eax, edx                                    ; not ax
	jnz     S700                                        ; difference found
	add     ecx, 8
	jz      S900

S300:
	; less than 8 bytes left
	cmp     ecx, -4
	ja      S400
	; compare 4 bytes
	movd    xmm1, dword ptr [esi + ecx]
	movd    xmm2, dword ptr [edi + ecx]
	pcmpeqb xmm1, xmm2                                  ; compare 4 bytes
	pmovmskb eax, xmm1                                  ; get byte mask
	xor     eax, edx                                    ; not ax
	jnz     S700                                        ; difference found
	add     ecx, 4
	jz      S900

S400:
	; less than 4 bytes left
	cmp     ecx, -2
	ja      S500
	movzx   eax, word ptr [esi + ecx]
	movzx   edx, word ptr [edi + ecx]
	sub     eax, edx
	jnz     S800                                        ; difference in byte 0 or 1
	add     ecx, 2
	jz      S900

S500:
	; less than 2 bytes left
	test    ecx, ecx
	jz      S900                                        ; no bytes left

	; one byte left
	movzx   eax, byte ptr [esi + ecx]
	movzx   edx, byte ptr [edi + ecx]
	sub     eax, edx                                    ; return result
	pop     edi
	pop     esi
	ret

	align   16
S700:
	; difference found. find position
	bsf     eax, eax
	add     ecx, eax
	movzx   eax, byte ptr [esi + ecx]
	movzx   edx, byte ptr [edi + ecx]
	sub     eax, edx                                    ; return result
	pop     edi
	pop     esi
	ret

	align   16
S800:
	; difference in byte 0 or 1
	neg     al
	sbb     ecx, -1                                     ; add 1 to ecx if al == 0

S820:
	movzx   eax, byte ptr [esi + ecx]
	movzx   edx, byte ptr [edi + ecx]
	sub     eax, edx                                    ; return result
	pop     edi
	pop     esi
	ret

	align   16
S900:
	; equal
	xor     eax, eax
	pop     edi
	pop     esi
	ret
memcmpSSE2 endp

; Generic version version. Use 32 bit registers
align 16
memcmp386 proc near
	; This is not perfectly optimized because it is unlikely to ever be used
	push    esi
	push    edi
	mov     esi, dword ptr [esp + 12]                   ; ptr1
	mov     edi, dword ptr [esp + 16]                   ; ptr2
	mov     ecx, dword ptr [esp + 20]                   ; size
	mov     edx, ecx
	shr     ecx, 2                                      ; size/4 = number of dwords
	repe    cmpsd                                       ; compare dwords
	jnz     M700
	mov     ecx, edx
	and     ecx, 3                                      ; remainder

M600:
	repe    cmpsb                                       ; compare bytes
	je      M800                                        ; equal
	movzx   eax, byte ptr [esi - 1]                     ; esi, edi point past the differing byte. find difference
	movzx   edx, byte ptr [edi - 1]
	sub     eax, edx                                    ; calculate return value
	pop     edi
	pop     esi
	ret

	align   16
M700:
	; dwords differ. search in last 4 bytes
	mov     ecx, 4
	sub     esi, ecx
	sub     edi, ecx
	jmp     M600

	align   16
M800:
	; equal. return zero
	xor     eax, eax
	pop     edi
	pop     esi
	ret
memcmp386 endp
else
; AVX512BW Version. Use zmm register
align 16
memcmpAVX512BW proc near
	push    esi
	push    edi
	mov     esi, dword ptr [esp + 12]                   ; ptr1
	mov     edi, dword ptr [esp + 16]                   ; ptr2
	mov     ecx, dword ptr [esp + 20]                   ; size
	xor     eax, eax
	cmp     ecx, 128
	ja      memcmpAVX512BW_entry
	cmp     ecx, 64
	ja      less_than_128_bytes_left
	test    ecx, ecx
	jnz     less_than_64_bytes_left
	pop     edi
	pop     esi
	ret

	align   16
	; count > 128
memcmpAVX512BW_entry label near
	; entry from memcmpAVX512F
	vmovdqu64 zmm0, zmmword ptr [esi]
	vmovdqu64 zmm1, zmmword ptr [edi]
	vpcmpd  k1, zmm0, zmm1, 4                           ; compare first 64 bytes for dwords not equal
	kortestw k1, k1
	jnz     difference_zmmword                          ; difference found

	; find 64 boundaries
	lea     edx, dword ptr [esi + ecx]                  ; end of string 1
	mov     eax, esi
	add     esi, 64
	and     esi, -64                                    ; first aligned boundary for esi
	sub     eax, esi                                    ; -offset
	sub     edi, eax                                    ; same offset to edi
	mov     eax, edx
	and     edx, -64                                    ; last aligned boundary for esi
	sub     esi, edx                                    ; esi = -size of aligned blocks
	sub     edi, esi

	align   16
loop_begin:
	; main loop
	vmovdqa64 zmm0, zmmword ptr [edx + esi]
	vmovdqu64 zmm1, zmmword ptr [edi + esi]
	vpcmpd  k1, zmm0, zmm1, 4                           ; compare first 64 bytes for not equal
	kortestw k1, k1
	jnz     difference_zmmword                          ; difference found
	add     esi, 64
	jnz     loop_begin

	; remaining 0-3FH bytes. Overlap with previous block
	add     edi, eax
	sub     edi, edx
	vmovdqu64 zmm0, zmmword ptr [eax - 64]
	vmovdqu64 zmm1, zmmword ptr [edi - 64]
	vpcmpd  k1, zmm0, zmm1, 4                           ; compare first 64 bytes for not equal
	kortestw k1, k1
	jnz     difference_zmmword                          ; difference found

	; finished. no difference found
	xor     eax, eax
	vzeroupper
	pop     edi
	pop     esi
	ret

	align   16
difference_zmmword:
	; the two strings are different
	vpcompressd zmm0{k1}{z}, zmm0                       ; get first differing dword to position 0
	vpcompressd zmm1{k1}{z}, zmm1                       ; get first differing dword to position 0
	vmovd   ecx, xmm0
	vmovd   edx, xmm1
	mov     eax, ecx
	xor     ecx, edx                                    ; difference
	bsf     ecx, ecx                                    ; position of lowest differing bit
	and     ecx, -8                                     ; round down to byte boundary
	shr     eax, cl                                     ; first differing byte in al
	shr     edx, cl                                     ; first differing byte in dl
	and     eax, 0FFH                                   ; zero-extend bytes
	and     edx, 0FFH
	sub     eax, edx                                    ; signed difference between unsigned bytes
	vzeroupper
	pop     edi
	pop     esi
	ret

	align   16
less_than_128_bytes_left:
	; size = 65 - 128
	vmovdqu64 zmm0, zmmword ptr [esi]
	vmovdqu64 zmm1, zmmword ptr [edi]
	vpcmpd  k1, zmm0, zmm1, 4                           ; compare first 64 bytes for not equal
	kortestw k1, k1
	jnz     difference_zmmword                          ; difference found
	add     esi, 64
	add     edi, 64
	sub     ecx, 64

less_than_64_bytes_left:
	; size = 1 - 64
	; (this is the only part that requires AVX512BW)
	or      eax, -1                                     ; if count = 1-31: |  if count = 32-63:
	bzhi    eax, eax, ecx                               ; -----------------|--------------------
	kmovd   k1, eax                                     ;       count 1's  |  all 1's
	xor     eax, eax                                    ;                  |
	sub     ecx, 32                                     ;                  |
	cmovb   ecx, eax                                    ;               0  |  count-32
	dec     eax                                         ;                  |
	bzhi    eax, eax, ecx                               ;                  |
	kmovd   k2, eax                                     ;               0  |  count-32 1's
	kunpckdq k3, k2, k1                                 ; low 32 bits from k1, high 32 bits from k2. total = count 1's

	vmovdqu8 zmm0{k3}{z}, zmmword ptr [esi]
	vmovdqu8 zmm1{k3}{z}, zmmword ptr [edi]
	vpcmpd  k1, zmm0, zmm1, 4                           ; compare
	kortestw k1, k1
	jnz     difference_zmmword                          ; difference found
	xor     eax, eax                                    ; no difference found
	vzeroupper
	pop     edi
	pop     esi
	ret
memcmpAVX512BW endp

; AVX512F Version. Use zmm register
align 16
memcmpAVX512F proc near
	push    esi
	push    edi
	mov     esi, dword ptr [esp + 12]                   ; ptr1
	mov     edi, dword ptr [esp + 16]                   ; ptr2
	mov     ecx, dword ptr [esp + 20]                   ; size
	xor     eax, eax
	cmp     ecx, 128                                    ; size
	jae     memcmpAVX512BW_entry                        ; continue in memcmpAVX512BW
	jmp     memcmpAVX2_entry                            ; continue in memcmpAVX2 if less than 128 bytes
memcmpAVX512F endp

; AVX2 Version. Use ymm register
align 16
memcmpAVX2 proc near
	push    esi
	push    edi
	mov     esi, dword ptr [esp + 12]                   ; ptr1
	mov     edi, dword ptr [esp + 16]                   ; ptr2
	mov     ecx, dword ptr [esp + 20]                   ; size
	xor     eax, eax

memcmpAVX2_entry label near
	; entry from above
	add     esi, ecx                                    ; use negative index from end of memory block
	add     edi, ecx
	xor     ecx, -1
	mov     edx, 0FFFFH
	inc     ecx
	jnz     loop_entry
	jmp     epilogue

	align   16
loop_begin:
	; loop comparing 32 bytes
	vmovdqu ymm1, ymmword ptr [esi + ecx]
	vpcmpeqb ymm0, ymm1, ymmword ptr [edi + ecx]        ; compare 32 bytes
	vpmovmskb eax, ymm0                                 ; get byte mask
	xor     eax, -1                                     ; not eax would not set flags
	jnz     difference_ymmword                          ; difference found
	add     ecx, 32
	jz      epilogue_avx                                ; finished, equal
loop_entry:
	cmp     ecx, -32
	jna     loop_begin                                  ; next 32 bytes

	; less than 32 bytes left
	vzeroupper                                          ; end ymm state
	cmp     ecx, -16
	ja      less_than_16_bytes_left
	; compare 16 bytes
	movdqu  xmm0, xmmword ptr [esi + ecx]
	movdqu  xmm1, xmmword ptr [edi + ecx]
	pcmpeqb xmm0, xmm1                                  ; compare 16 bytes
	pmovmskb eax, xmm0                                  ; get byte mask
	xor     eax, edx                                    ; not ax
	jnz     difference_xmmword                          ; difference found
	add     ecx, 16
	jz      epilogue

less_than_16_bytes_left:
	; less than 16 bytes left
	cmp     ecx, -8
	ja      less_than_8_bytes_left
	; compare 8 bytes
	movq    xmm0, qword ptr [esi + ecx]
	movq    xmm1, qword ptr [edi + ecx]
	pcmpeqb xmm0, xmm1                                  ; compare 8 bytes
	pmovmskb eax, xmm0                                  ; get byte mask
	xor     eax, edx                                    ; not ax
	jnz     difference_xmmword                          ; difference found
	add     ecx, 8
	jz      epilogue

less_than_8_bytes_left:
	; less than 8 bytes left
	cmp     ecx, -4
	ja      less_than_4_bytes_left
	; compare 4 bytes
	movd    xmm0, dword ptr [esi + ecx]
	movd    xmm1, dword ptr [edi + ecx]
	pcmpeqb xmm0, xmm1                                  ; compare 4 bytes
	pmovmskb eax, xmm0                                  ; get byte mask
	xor     eax, edx                                    ; not ax
	jnz     difference_xmmword                          ; difference found
	add     ecx, 4
	jz      epilogue

less_than_4_bytes_left:
	; less than 4 bytes left
	cmp     ecx, -2
	ja      less_than_2_bytes_left
	; compare 2 bytes
	movzx   eax, word ptr [esi + ecx]
	movzx   edx, word ptr [edi + ecx]
	sub     eax, edx
	jnz     difference_word                             ; difference found
	add     ecx, 2
	jz      epilogue

less_than_2_bytes_left:
	; less than 2 bytes left
	test    ecx, ecx
	jnz     difference_byte                             ; one byte left
	jmp     epilogue                                    ; no bytes left

	align   16
difference_ymmword:
	; difference found. find position
	vzeroupper

difference_xmmword:
	bsf     eax, eax
	add     ecx, eax
	jmp     difference_byte

	align   16
difference_word:
	; difference in byte 0 or 1
	cmp     al, 1
	adc     ecx, 0                                      ; add 1 to ecx if al == 0

difference_byte:
	movzx   eax, byte ptr [esi + ecx]
	movzx   edx, byte ptr [edi + ecx]
	sub     eax, edx                                    ; signed difference between unsigned bytes
	jmp     epilogue

	align   16
epilogue_avx:
	; equal
	vzeroupper

epilogue:
	pop     edi
	pop     esi
	ret
memcmpAVX2 endp

; SSE2 version. Use xmm register
align 16
memcmpSSE2 proc near
	push    esi
	push    edi
	mov     esi, dword ptr [esp + 12]                   ; ptr1
	mov     edi, dword ptr [esp + 16]                   ; ptr2
	mov     ecx, dword ptr [esp + 20]                   ; size
	xor     eax, eax
	add     esi, ecx                                    ; use negative index from end of memory block
	add     edi, ecx
	xor     ecx, -1
	mov     edx, 0FFFFH
	inc     ecx
	jnz     loop_entry
	jmp     epilogue

	align   16
loop_begin:
	; loop comparing 16 bytes
	movdqu  xmm0, xmmword ptr [esi + ecx]
	movdqu  xmm1, xmmword ptr [edi + ecx]
	pcmpeqb xmm0, xmm1                                  ; compare 16 bytes
	pmovmskb eax, xmm0                                  ; get byte mask
	xor     eax, edx                                    ; not ax
	jnz     difference_xmmword                          ; difference found
	add     ecx, 16
	jz      epilogue                                    ; finished, equal
loop_entry:
	cmp     ecx, -16
	jna     loop_begin                                  ; next 16 bytes

	; less than 16 bytes left
	cmp     ecx, -8
	ja      less_than_8_bytes_left
	; compare 8 bytes
	movq    xmm0, qword ptr [esi + ecx]
	movq    xmm1, qword ptr [edi + ecx]
	pcmpeqb xmm0, xmm1                                  ; compare 8 bytes
	pmovmskb eax, xmm0                                  ; get byte mask
	xor     eax, edx                                    ; not ax
	jnz     difference_xmmword                          ; difference found
	add     ecx, 8
	jz      epilogue

less_than_8_bytes_left:
	; less than 8 bytes left
	cmp     ecx, -4
	ja      less_than_4_bytes_left
	; compare 4 bytes
	movd    xmm0, dword ptr [esi + ecx]
	movd    xmm1, dword ptr [edi + ecx]
	pcmpeqb xmm0, xmm1                                  ; compare 4 bytes
	pmovmskb eax, xmm0                                  ; get byte mask
	xor     eax, edx                                    ; not ax
	jnz     difference_xmmword                          ; difference found
	add     ecx, 4
	jz      epilogue

less_than_4_bytes_left:
	; less than 4 bytes left
	cmp     ecx, -2
	ja      less_than_2_bytes_left
	; compare 2 bytes
	movzx   eax, word ptr [esi + ecx]
	movzx   edx, word ptr [edi + ecx]
	sub     eax, edx
	jnz     difference_word                             ; difference found
	add     ecx, 2
	jz      epilogue

less_than_2_bytes_left:
	; less than 2 bytes left
	test    ecx, ecx
	jnz     difference_byte                             ; one byte left
	jmp     epilogue                                    ; no bytes left

	align   16
difference_xmmword:
	; difference found. find position
	bsf     eax, eax
	add     ecx, eax
	jmp     difference_byte

	align   16
difference_word:
	; difference in byte 0 or 1
	cmp     al, 1
	adc     ecx, 0                                      ; add 1 to ecx if al == 0

difference_byte:
	movzx   eax, byte ptr [esi + ecx]
	movzx   edx, byte ptr [edi + ecx]
	sub     eax, edx                                    ; signed difference between unsigned bytes

epilogue:
	pop     edi
	pop     esi
	ret
memcmpSSE2 endp

; Generic version version. Use 32 bit registers
align 16
memcmp386 proc near
	push    esi
	push    edi
	mov     ecx, dword ptr [esp + 20]                   ; ecx = count
	mov     edi, dword ptr [esp + 16]                   ; edi = buffer2
	mov     esi, dword ptr [esp + 12]                   ; esi = buffer1
	add     edi, ecx                                    ; edi = end of buffer2
	add     esi, ecx                                    ; esi = end of buffer1
	xor     ecx, -1                                     ; ecx = -count - 1
	add     ecx, 4
	jnc     dword_loop
	jmp     compare_bytes

	align   16
dword_loop:
	mov     eax, dword ptr [esi + ecx - 3]
	mov     edx, dword ptr [edi + ecx - 3]
	cmp     eax, edx
	jne     compare_bytes
	add     ecx, 4
	jnc     dword_loop

compare_bytes:
	xor     eax, eax
	xor     edx, edx
	sub     ecx, 3
	jnz     byte_loop
	jmp     epilogue

	align   16
byte_loop:
	mov     al, byte ptr [esi + ecx]
	mov     dl, byte ptr [edi + ecx]
	sub     eax, edx
	jnz     epilogue
	inc     ecx
	jnz     byte_loop

epilogue:
	pop     edi
	pop     esi
	ret
memcmp386 endp
endif

; CPU dispatching for memcmp. This is executed only once
align 16
memcmpCPUDispatch proc near
	call    _InstructionSet                             ; get supported instruction set
	; Point to generic version of memcmp
	mov     dword ptr [memcmpDispatch], offset memcmp386
	cmp     eax, 4                                      ; check SSE2
	jb      Q100
	; SSE2 supported
	mov     dword ptr [memcmpDispatch], offset memcmpSSE2
	cmp     eax, 13                                     ; check AVX2
	jb      Q100
	; AVX2 supported
	mov     dword ptr [memcmpDispatch], offset memcmpAVX2
	cmp     eax, 15                                     ; check AVX512F
	jb      Q100
	; AVX512F supported
	mov     dword ptr [memcmpDispatch], offset memcmpAVX512F
	cmp     eax, 16                                     ; check AVX512BW
	jb      Q100
	; AVX512BW supported
	mov     dword ptr [memcmpDispatch], offset memcmpAVX512BW

Q100:
	; Continue in appropriate version of memcmp
	jmp     dword ptr [memcmpDispatch]
memcmpCPUDispatch endp

end
