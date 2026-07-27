IMPLEMENTATION MODULE Exceptions;

(* Exceptions.mod -- CPU exception handlers for x86_64.

   See Exceptions.def for overview.

   This module provides:
   * InstallExceptions  -- registers 20 assembly stubs (vectors 0-21)
     into the IDT with appropriate IST assignments.
   * ExceptionHandler   -- the Modula-2 procedure called by every stub.
     It prints a diagnostic dump (exception name, error code, register
     values, and CR2/CR3 for page faults) to the serial port and halts.

   Serial output is duplicated locally (COM1 at 0x3F8) because the
   serial procedures in ArchMain are not exported.  ByteAnd from
   BitByteOps is used for the transmit-buffer-empty check. *)

FROM SYSTEM IMPORT BYTE, CARDINAL16, CARDINAL64, ADDRESS, ADR;
FROM IDT IMPORT InstallInterrupt;
FROM BitByteOps IMPORT ByteAnd;

(* =====================================================================
   Constants
   ===================================================================== *)

CONST
    COM1 = 3F8H;

    (* GDT kernel code selector -- must match GDT.mod / IDT.mod. *)
    KERNEL_CODE_SEGMENT = 08H;

    (* IDT gate type: interrupt gate (CPU clears IF on entry). *)
    GATE_INTERRUPT = 0EH;

(* =====================================================================
   Types
   ===================================================================== *)

TYPE
    (* Stub table: 32 entries indexed by vector number (0 = unused). *)
    StubTable    = ARRAY [0..31] OF CARDINAL64;
    StubTablePtr = POINTER TO StubTable;

(* =====================================================================
   Serial output (local copy -- mirrors ArchMain.mod)
   ===================================================================== *)

PROCEDURE OUTB(port: SHORTCARD; value: BYTE);
BEGIN
    ASM VOLATILE ("outb %0, %1" : : "a"(value), "Nd"(port));
END OUTB;

PROCEDURE INB(port: SHORTCARD): BYTE;
VAR
    value: BYTE;
BEGIN
    ASM VOLATILE ("inb %1, %0" : "=a"(value) : "Nd"(port));
    RETURN value;
END INB;

PROCEDURE SerialWriteChar(c: CHAR);
BEGIN
    WHILE ByteAnd(INB(COM1 + 5), 20H) = 0 DO
        (* Wait for the transmit buffer to be empty *)
    END;
    OUTB(COM1, BYTE(c));
END SerialWriteChar;

PROCEDURE SerialWriteString(s: ARRAY OF CHAR);
VAR
    i: CARDINAL;
BEGIN
    i := 0;
    WHILE (i < HIGH(s)) AND (s[i] # BYTE(0)) DO
        SerialWriteChar(s[i]);
        INC(i);
    END;
END SerialWriteString;

PROCEDURE SerialWriteHex64(n: CARDINAL64);
VAR
    buffer: ARRAY [0..16] OF CHAR;
    i: CARDINAL;
    digit: CARDINAL64;
BEGIN
    i := 0;
    WHILE i < 16 DO
        digit := n MOD 16;
        IF digit < 10 THEN
            buffer[15 - i] := VAL(CHAR, digit + VAL(CARDINAL64, ORD('0')));
        ELSE
            buffer[15 - i] := VAL(CHAR, digit - 10 + VAL(CARDINAL64, ORD('A')));
        END;
        n := n DIV 16;
        INC(i);
    END;
    SerialWriteString("0x");
    FOR i := 0 TO 15 DO
        SerialWriteChar(buffer[i]);
    END;
END SerialWriteHex64;

PROCEDURE SerialNewLine;
BEGIN
    SerialWriteChar(BYTE(10));
END SerialNewLine;

(* =====================================================================
   Control-register readers
   ===================================================================== *)

PROCEDURE ReadCR2(): CARDINAL64;
VAR
    val: CARDINAL64;
BEGIN
    ASM VOLATILE ("movq %%cr2, %0" : "=r"(val));
    RETURN val;
END ReadCR2;

PROCEDURE ReadCR3(): CARDINAL64;
VAR
    val: CARDINAL64;
BEGIN
    ASM VOLATILE ("movq %%cr3, %0" : "=r"(val));
    RETURN val;
END ReadCR3;

(* =====================================================================
   Stub-table access
   ===================================================================== *)

(* GetStubTableAddr -- return the address of the ExceptionStubs table
   defined in exceptions.S.  Uses RIP-relative leaq, which works in
   any code model as long as the symbol is in the same image. *)
PROCEDURE GetStubTableAddr(): ADDRESS;
VAR
    addr: ADDRESS;
BEGIN
    ASM VOLATILE ("leaq ExceptionStubs(%%rip), %0" : "=r"(addr));
    RETURN addr;
END GetStubTableAddr;

(* =====================================================================
   IST assignment
   ===================================================================== *)

(* ISTForVector -- return the IST index (1..7) for a given exception
   vector, or 0 (use current stack) for non-critical exceptions.
   Critical exceptions (NMI, Double Fault, Stack Fault, GP, Page Fault,
   Machine Check, Debug) get dedicated IST stacks so they cannot
   corrupt the current stack. *)
PROCEDURE ISTForVector(v: CARDINAL): CARDINAL;
BEGIN
    CASE v OF
      1:  RETURN 7;   (* Debug       -> IST7 *)
    | 2:  RETURN 1;   (* NMI         -> IST1 *)
    | 8:  RETURN 2;   (* Double Fault-> IST2 *)
    | 12: RETURN 3;   (* Stack Fault -> IST3 *)
    | 13: RETURN 4;   (* GP Fault    -> IST4 *)
    | 14: RETURN 5;   (* Page Fault  -> IST5 *)
    | 18: RETURN 6;   (* Machine Chk -> IST6 *)
    ELSE
        RETURN 0;     (* all others: use current stack *)
    END;
END ISTForVector;

(* =====================================================================
   Public procedures
   ===================================================================== *)

(* InstallExceptions -- register all CPU exception stubs in the IDT. *)
PROCEDURE InstallExceptions();
VAR
    table: StubTablePtr;
    handler: CARDINAL64;
    v: CARDINAL;
BEGIN
    table := VAL(StubTablePtr, GetStubTableAddr());

    FOR v := 0 TO 31 DO
        handler := table^[v];
        IF handler # 0 THEN
            InstallInterrupt(handler, KERNEL_CODE_SEGMENT,
                             ISTForVector(v), 0, GATE_INTERRUPT, v);
        END;
    END;
END InstallExceptions;

(* ExceptionHandler -- called from assembly stubs.  Prints a full
   diagnostic dump and halts.  Never returns. *)
PROCEDURE ExceptionHandler(vector: CARDINAL64; errorCode: CARDINAL64;
                           frame: InterruptFramePtr);
BEGIN
    SerialNewLine;
    SerialWriteString("===== CPU EXCEPTION =====");
    SerialNewLine;

    (* Exception name *)
    CASE vector OF
      0:  SerialWriteString("Divide Error (#DE)");
    | 1:  SerialWriteString("Debug (#DB)");
    | 2:  SerialWriteString("Non-Maskable Interrupt (#NMI)");
    | 3:  SerialWriteString("Breakpoint (#BP)");
    | 4:  SerialWriteString("Overflow (#OF)");
    | 5:  SerialWriteString("BOUND Range Exceeded (#BR)");
    | 6:  SerialWriteString("Invalid Opcode (#UD)");
    | 7:  SerialWriteString("Device Not Available (#NM)");
    | 8:  SerialWriteString("Double Fault (#DF)");
    | 10: SerialWriteString("Invalid TSS (#TS)");
    | 11: SerialWriteString("Segment Not Present (#NP)");
    | 12: SerialWriteString("Stack Segment Fault (#SS)");
    | 13: SerialWriteString("General Protection Fault (#GP)");
    | 14: SerialWriteString("Page Fault (#PF)");
    | 16: SerialWriteString("x87 FPU Error (#MF)");
    | 17: SerialWriteString("Alignment Check (#AC)");
    | 18: SerialWriteString("Machine Check (#MC)");
    | 19: SerialWriteString("SIMD Exception (#XM)");
    | 20: SerialWriteString("Virtualization Exception (#VE)");
    | 21: SerialWriteString("Control Protection (#CP)");
    ELSE
        SerialWriteString("Unknown exception");
    END;
    SerialNewLine;

    (* Vector and error code *)
    SerialWriteString("  vector: ");
    SerialWriteHex64(vector);
    SerialNewLine;
    SerialWriteString("  error code: ");
    SerialWriteHex64(errorCode);
    SerialNewLine;

    (* Page-fault-specific info *)
    IF vector = 14 THEN
        SerialWriteString("  faulting address (CR2): ");
        SerialWriteHex64(ReadCR2());
        SerialNewLine;
    END;

    (* Register dump *)
    SerialWriteString("  rax: ");
    SerialWriteHex64(frame^.rax);
    SerialWriteString("  rbx: ");
    SerialWriteHex64(frame^.rbx);
    SerialWriteString("  rcx: ");
    SerialWriteHex64(frame^.rcx);
    SerialNewLine;
    SerialWriteString("  rdx: ");
    SerialWriteHex64(frame^.rdx);
    SerialWriteString("  rsi: ");
    SerialWriteHex64(frame^.rsi);
    SerialWriteString("  rdi: ");
    SerialWriteHex64(frame^.rdi);
    SerialNewLine;
    SerialWriteString("  rbp: ");
    SerialWriteHex64(frame^.rbp);
    SerialWriteString("  rsp: ");
    SerialWriteHex64(frame^.rsp);
    SerialWriteString("  r08: ");
    SerialWriteHex64(frame^.r8);
    SerialNewLine;
    SerialWriteString("  r09: ");
    SerialWriteHex64(frame^.r9);
    SerialWriteString("  r10: ");
    SerialWriteHex64(frame^.r10);
    SerialWriteString("  r11: ");
    SerialWriteHex64(frame^.r11);
    SerialNewLine;
    SerialWriteString("  r12: ");
    SerialWriteHex64(frame^.r12);
    SerialWriteString("  r13: ");
    SerialWriteHex64(frame^.r13);
    SerialWriteString("  r14: ");
    SerialWriteHex64(frame^.r14);
    SerialNewLine;
    SerialWriteString("  r15: ");
    SerialWriteHex64(frame^.r15);
    SerialNewLine;
    SerialWriteString("  rip: ");
    SerialWriteHex64(frame^.rip);
    SerialWriteString("  cs: ");
    SerialWriteHex64(frame^.cs);
    SerialWriteString("  ss: ");
    SerialWriteHex64(frame^.ss);
    SerialNewLine;
    SerialWriteString("  rflags: ");
    SerialWriteHex64(frame^.rflags);
    SerialNewLine;
    SerialWriteString("  cr2: ");
    SerialWriteHex64(ReadCR2());
    SerialWriteString("  cr3: ");
    SerialWriteHex64(ReadCR3());
    SerialNewLine;

    SerialWriteString("===== HALTING =====");
    SerialNewLine;

    (* Halt permanently. *)
    LOOP
        ASM VOLATILE ("hlt");
    END;
END ExceptionHandler;

END Exceptions.
