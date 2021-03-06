#include <stddef.h>

#define INVALID_PAGE 0
#if INVALID_PAGE
extern int __cdecl InstructionSet();

static size_t __cdecl strcspnSSE42(const char *string, const char *control);
static size_t __cdecl strcspnGeneric(const char *string, const char *control);
static size_t __cdecl strcspnCPUDispatch(const char *string, const char *control);

static size_t(__cdecl * strcspnDispatch)(const char *string, const char *control) = strcspnCPUDispatch;

// function dispatching
__declspec(naked) size_t __cdecl strcspn(const char *string, const char *control)
{
	__asm
	{
		jmp     dword ptr [strcspnDispatch]                 // Go to appropriate version, depending on instruction set
	}
}

// SSE4.2 version
__declspec(naked) static size_t __cdecl strcspnSSE42(const char *string, const char *control)
{
#error Contains a bug that reads invalid page. The end of string may be on a page boundary.
	__asm
	{
		push    esi
		push    edi
		mov     esi, dword ptr [esp + 12]                   // str
		mov     edi, dword ptr [esp + 16]                   // set
		xor     ecx, ecx                                    // span counter

	str_next2:
		movdqu  xmm2, xmmword ptr [esi]                     // str
		movdqu  xmm1, xmmword ptr [edi]                     // set
		pcmpistrm xmm1, xmm2, 00110000B                     // find in set, invert valid bits, return bit mask in xmm0
		movd    eax, xmm0
		jns     set_extends2

	set_finished2:
		cmp     ax, -1
		jne     str_finished2
		// first 16 characters matched, continue with next 16 characters (a terminating zero would never match)
		add     esi, 16                                     // next 16 bytes of str
		add     ecx, 16                                     // count span
		jmp     str_next2

	str_finished2:
		not     eax
		bsf     eax, eax
		add     eax, ecx
		pop     edi
		pop     esi
		ret

	set_loop2:
		and     eax, edx                                    // accumulate matches

	set_extends2:
		// the set is more than 16 bytes
		add     edi, 16
		movdqu  xmm1, xmmword ptr [edi]                     // next part of set
		pcmpistrm xmm1, xmm2, 00110000B                     // find in set, invert valid bits, return bit mask in xmm0
		movd    edx, xmm0
		jns     set_loop2
		mov     edi, dword ptr [esp + 16]                   // restore set pointer
		and     eax, edx                                    // accumulate matches
		jmp     set_finished2
	}
}
#endif

// Generic version
#if INVALID_PAGE
__declspec(naked) static size_t __cdecl strcspnGeneric(const char *string, const char *control)
#else
__declspec(naked) size_t __cdecl strcspn(const char *string, const char *control)
#endif
{
	__asm
	{
		push    esi
		push    edi
		mov     eax, dword ptr [esp + 12]                   // str pointer
		mov     edi, dword ptr [esp + 16]                   // set pointer
		jmp     str_next20

		align   16
	str_next20:
		mov     cl, byte ptr [eax]                          // read one byte from str
		mov     esi, edi                                    // set pointer
		test    cl, cl
		jz      finished20                                  // str finished
		inc     eax
		jmp     set_next20

		align   16
	set_next20:
		mov     dl, byte ptr [esi]
		inc     esi
		test    dl, dl
		jz      str_next20                                  // end of set, mismatch found
		cmp     cl, dl
		jne     set_next20
		// character match found, stop search
		dec     eax
	finished20:
		// end of str, all match
		mov     ecx, dword ptr [esp + 12]
		pop     edi
		pop     esi
		sub     eax, ecx                                    // calculate position
		ret
	}
}

#if INVALID_PAGE
// CPU dispatching for strcspn. This is executed only once
__declspec(naked) static size_t __cdecl strcspnCPUDispatch(const char *string, const char *control)
{
	__asm
	{
		// get supported instruction set
		call    InstructionSet

		// Point to generic version of strcspn
		mov     ecx, offset strcspnGeneric

		cmp     eax, 10                                     // check SSE4.2
		jb      Q200

		// SSE4.2 supported
		// Point to SSE4.2 version of strcspn
		mov     ecx, offset strcspnSSE42

	Q200:
		mov     dword ptr [strcspnDispatch], ecx

		// Continue in appropriate version
		jmp     ecx
	}
}
#endif
