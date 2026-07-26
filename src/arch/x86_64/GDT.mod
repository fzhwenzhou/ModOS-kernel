IMPLEMENTATION MODULE GDT;

(* GDT.mod -- 64-bit Global Descriptor Table and Task State Segment.

   See GDT.def for overview.

   Layout notes:
   * The GDT is an array of seven 64-bit slots.  Each code/data descriptor
     is a single 64-bit value hand-assembled from base/limit/access/flags
     fields, which avoids any compiler-specific record padding.
   * The TSS descriptor occupies slots [5] and [6]: slot [5] holds the
     low 8 bytes (limit = sizeof(TSS)-1, access = 0x89 = present+64-bit-
     TSS, base bits 0..23, flags nibble 0), and slot [6] holds base bits
     32..63.
   * The TSS is declared below with 64-bit fields broken into lo/hi
     CARDINAL32 pairs.  GNU Modula-2 aligns fields to their natural
     boundary and does not insert padding between a CARDINAL16 and a
     following CARDINAL32, so the resulting struct is exactly 104 bytes
     with offsets matching the hardware layout (verified against
     sizeof).
   * Ring-0 and IST stacks are static arrays placed in BSS.  Stack
     pointers stored in the TSS point to the *top* of each array
     (stacks grow downward). *)

FROM SYSTEM IMPORT BYTE, CARDINAL16, CARDINAL32, CARDINAL64, ADDRESS;

(* =====================================================================
   Constants -- GDT selectors (byte offsets into GDT)
   ===================================================================== *)

CONST
    GDT_NULL        = 0 * 8;    (* 0x00 *)
    GDT_KERNEL_CODE = 1 * 8;    (* 0x08 *)
    GDT_KERNEL_DATA = 2 * 8;    (* 0x10 *)
    GDT_USER_DATA   = 3 * 8;    (* 0x18 *)
    GDT_USER_CODE   = 4 * 8;    (* 0x20 *)
    GDT_TSS         = 5 * 8;    (* 0x28 *)

    (* Access byte bits *)
    GDT_ACCESS_PRESENT   = 80H;
    GDT_ACCESS_RW        = 02H;   (* readable (code) / writable (data) *)
    GDT_ACCESS_DC        = 04H;
    GDT_ACCESS_EXEC      = 08H;   (* code segment *)
    GDT_ACCESS_CODE_DATA = 10H;   (* descriptor type: code/data (not system) *)
    GDT_ACCESS_DPL_USER  = 60H;   (* DPL = 3 *)

    (* 64-bit TSS (available) access byte = present (0x80) | type 9 (0x09) *)
    GDT_ACCESS_TSS       = 89H;

    (* Flags nibble (high nibble of the flags/limit-high byte) *)
    GDT_FLAG_LONG        = 20H;   (* L: 64-bit code segment *)
    GDT_FLAG_GRAN        = 80H;   (* G: 4 KiB granularity *)

    (* TSS size: 104 bytes (fixed layout, no I/O permission bitmap) *)
    TSS_SIZE             = 104;
    TSS_LIMIT            = TSS_SIZE - 1;

    (* Kernel ring-0 stack: 32 KiB *)
    KERNEL_STACK_SIZE  = 32768;

    (* Each IST stack slot: 8 KiB *)
    IST_STACK_SIZE     = 8192;
    IST_COUNT          = 7;

(* =====================================================================
   Types

   The TSS and GDTR types are laid out field-by-field so that the
   generated offsets match the hardware expectation exactly (verified
   at build time via emitted sizeof).
   ===================================================================== *)

TYPE
    (* The 104-byte 64-bit TSS.  64-bit fields are split into lo/hi
       32-bit halves so no CARDINAL64 forces alignment padding.  The
       iomap field is set to TSS_SIZE (104) meaning there is no I/O
       permission bitmap: every port access from CPL > IOPL raises
       #GP. *)
    TSS = RECORD
        reserved1: CARDINAL32;                  (* +0  must be zero *)
        rsp0Lo:    CARDINAL32;                  (* +4  rsp0 low  *)
        rsp0Hi:    CARDINAL32;                  (* +8  rsp0 high *)
        rsp1Lo:    CARDINAL32;                  (* +12 *)
        rsp1Hi:    CARDINAL32;                  (* +16 *)
        rsp2Lo:    CARDINAL32;                  (* +20 *)
        rsp2Hi:    CARDINAL32;                  (* +24 *)
        reserved2a: CARDINAL32;                 (* +28 must be zero *)
        reserved2b: CARDINAL32;                 (* +32 must be zero *)
        ist1Lo:    CARDINAL32;                  (* +36 IST1 *)
        ist1Hi:    CARDINAL32;                  (* +40 *)
        ist2Lo:    CARDINAL32;                  (* +44 IST2 *)
        ist2Hi:    CARDINAL32;                  (* +48 *)
        ist3Lo:    CARDINAL32;                  (* +52 IST3 *)
        ist3Hi:    CARDINAL32;                  (* +56 *)
        ist4Lo:    CARDINAL32;                  (* +60 IST4 *)
        ist4Hi:    CARDINAL32;                  (* +64 *)
        ist5Lo:    CARDINAL32;                  (* +68 IST5 *)
        ist5Hi:    CARDINAL32;                  (* +72 *)
        ist6Lo:    CARDINAL32;                  (* +76 IST6 *)
        ist6Hi:    CARDINAL32;                  (* +80 *)
        ist7Lo:    CARDINAL32;                  (* +84 IST7 *)
        ist7Hi:    CARDINAL32;                  (* +88 *)
        reserved3a: CARDINAL32;                 (* +92 must be zero *)
        reserved3b: CARDINAL32;                 (* +96 must be zero *)
        reserved4:  CARDINAL16;                 (* +100 must be zero *)
        iomap:      CARDINAL16;                 (* +102 IOPB offset  *)
    END;

    (* 48-bit GDTR value passed to lgdt.  Hardware layout is:
         offset 0: 16-bit limit
         offset 2: 64-bit base
       for a total of 10 bytes.  We represent it as a 10-byte packed
       byte array to avoid CARDINAL32 alignment padding that gm2 would
       otherwise insert after a CARDINAL16 field, and fill it with
       WriteU16/WriteU64 helpers below. *)
    GDTR = ARRAY [0..9] OF BYTE;

(* =====================================================================
   Module-level (static) storage.
   ===================================================================== *)

(* All GDT/TSS/stack storage lives in boot/boot.S.  We extern it there
   under the gm2-mangled GDT_<name> aliases to avoid a quirk where gm2
   silently fails to emit BSS symbols for large static arrays. *)

(* Pointer types used to cast assembly-provided addresses back into
   typed views for field access. *)
TYPE
    TSSPtr = POINTER TO TSS;
    GDTArray = ARRAY [0..6] OF CARDINAL64;
    GDTArrayPtr = POINTER TO GDTArray;

(* =====================================================================
   Helpers -- encoding GDT entries
   ===================================================================== *)

(* EncodeCodeData: build a single 64-bit code/data descriptor.
     base   -- 32-bit base (ignored in long mode)
     limit  -- 20-bit limit (0xFFFFF with gran=1 covers 4 GiB)
     access -- 8-bit access byte
     flags  -- flags nibble (top 4 bits of byte 6)
*)
PROCEDURE EncodeCodeData(base: CARDINAL32; limit: CARDINAL32;
                        access: BYTE; flags: BYTE): CARDINAL64;
VAR
    entry: CARDINAL64;
    baseLo, baseMi, baseHi: CARDINAL64;
    limitLo: CARDINAL64;
    flagsLimitHi: BYTE;
BEGIN
    entry   := 0;
    baseLo  := VAL(CARDINAL64, base) MOD 65536;
    baseMi  := (VAL(CARDINAL64, base) DIV 65536) MOD 256;
    baseHi  := VAL(CARDINAL64, base) DIV 16777216;
    limitLo := VAL(CARDINAL64, limit) MOD 65536;

    (* byte 6 = (flags & 0xF0) + ((limit >> 16) & 0x0F).
       The two nibbles are disjoint so addition acts like bitwise OR. *)
    flagsLimitHi := VAL(BYTE, VAL(CARDINAL32, flags) + (limit DIV 65536));

    (* Each field occupies a disjoint set of bits, so integer addition
       is equivalent to bitwise OR (gm2 treats OR as a BOOLEAN operator
       on CARDINAL types). *)
    entry := limitLo
             + baseLo * 010000H                         (* bits 16..31 *)
             + baseMi * 100000000H                      (* bits 32..39 *)
             + VAL(CARDINAL64, access) * 10000000000H   (* bits 40..47 *)
             + VAL(CARDINAL64, flagsLimitHi) * 1000000000000H (* bits 48..55 *)
             + baseHi * 100000000000000H;               (* bits 56..63 *)

    RETURN entry;
END EncodeCodeData;

(* EncodeTSSLow: lower 64 bits of the 128-bit TSS descriptor.
     base   -- 64-bit TSS base address
     limit  -- TSS limit (TSS_SIZE - 1 = 103)
   Access = 0x89 (present + 64-bit TSS available).  Flags nibble = 0.
*)
PROCEDURE EncodeTSSLow(base: CARDINAL64; limit: CARDINAL16): CARDINAL64;
VAR
    entry: CARDINAL64;
    baseLo, baseMi, baseHi: CARDINAL64;
BEGIN
    baseLo := base MOD 65536;
    baseMi := (base DIV 65536) MOD 256;
    baseHi := (base DIV 16777216) MOD 256;

    (* All bit fields are disjoint -- addition acts as bitwise OR. *)
    entry := VAL(CARDINAL64, limit)
             + baseLo * 010000H                         (* bits 16..31 *)
             + baseMi * 100000000H                      (* bits 32..39 *)
             + VAL(CARDINAL64, GDT_ACCESS_TSS) * 10000000000H (* bits 40..47 *)
             + baseHi * 100000000000000H;               (* bits 56..63 *)

    RETURN entry;
END EncodeTSSLow;

(* EncodeTSSHigh: upper 64 bits of the 128-bit TSS descriptor
   (bits 32..63 of the TSS base address, rest zero). *)
PROCEDURE EncodeTSSHigh(base: CARDINAL64): CARDINAL64;
BEGIN
    RETURN base DIV 4294967296;    (* base >> 32 *)
END EncodeTSSHigh;

(* WritePtr: split a CARDINAL64 address into lo/hi 32-bit halves and
   store them in the two adjacent CARDINAL32 fields used for the
   rsp/ist entries in the TSS. *)
PROCEDURE WritePtr(VAR lo, hi: CARDINAL32; addr: CARDINAL64);
BEGIN
    lo := VAL(CARDINAL32, addr MOD 4294967296);     (* addr & 0xFFFFFFFF *)
    hi := VAL(CARDINAL32, addr DIV 4294967296);     (* addr >> 32 *)
END WritePtr;

(* StU16 / StU64: store a little-endian 16/64-bit value into a byte
   array at the given offset.  Used to populate the packed GDTR byte
   array, which must not have alignment padding.
   gm2 requires explicit VAL(BYTE, ...) because BYTE(...) is a size
   conversion that requires matching operand sizes. *)
PROCEDURE StU16(VAR buf: ARRAY OF BYTE; off: CARDINAL; v: CARDINAL16);
BEGIN
    buf[off]     := VAL(BYTE, v MOD 256);
    buf[off + 1] := VAL(BYTE, v DIV 256);
END StU16;

PROCEDURE StU64(VAR buf: ARRAY OF BYTE; off: CARDINAL; v: CARDINAL64);
VAR i: CARDINAL;
BEGIN
    i := 0;
    WHILE i < 8 DO
        buf[off + i] := VAL(BYTE, v MOD 256);
        v := v DIV 256;
        INC(i);
    END;
END StU64;

(* =====================================================================
   Privileged-instruction helpers (inline assembly)
   ===================================================================== *)

(* KernelStackAddr: return the address of the static kernelStack
   array (32 KiB BSS).  gm2 mangles global names as ModuleName_VarName,
   so the symbol is GDT_kernelStack. *)
PROCEDURE KernelStackAddr(): CARDINAL64;
VAR a: CARDINAL64;
BEGIN
    ASM VOLATILE ("leaq GDT_kernelStack(%%rip), %0" : "=r"(a));
    RETURN a;
END KernelStackAddr;

(* ISTStackAddr: return the address of istStacks[i]. *)
PROCEDURE ISTStackAddr(i: CARDINAL): CARDINAL64;
VAR a: CARDINAL64;
BEGIN
    (* Each IST stack is IST_STACK_SIZE bytes; index into the array. *)
    ASM VOLATILE ("leaq GDT_istStacks(%%rip), %0" : "=r"(a));
    RETURN a + VAL(CARDINAL64, i) * IST_STACK_SIZE;
END ISTStackAddr;

(* TSSAddr / GDTAddr: addresses of the TSS and GDT structs. *)
PROCEDURE TSSAddr(): CARDINAL64;
VAR a: CARDINAL64;
BEGIN
    ASM VOLATILE ("leaq GDT_tss(%%rip), %0" : "=r"(a));
    RETURN a;
END TSSAddr;

PROCEDURE GDTAddr(): CARDINAL64;
VAR a: CARDINAL64;
BEGIN
    ASM VOLATILE ("leaq GDT_gdt(%%rip), %0" : "=r"(a));
    RETURN a;
END GDTAddr;

(* LTR -- load the task register with the given TSS selector. *)
PROCEDURE LTR(selector: CARDINAL16);
VAR
    sel: CARDINAL16;
BEGIN
    sel := selector;
    ASM VOLATILE ("ltr %0" : : "r"(sel) : "memory");
END LTR;

(* ReloadSegments -- after LGDT, reload CS (via far return) and all
   data segments with the new selectors.  Interrupts stay disabled. *)
PROCEDURE ReloadSegments();
BEGIN
    ASM VOLATILE ("pushq %[kcs]; leaq .Lgdt_reload(%%rip), %%rax; pushq %%rax; lretq; .Lgdt_reload: mov %[kds], %%ax; mov %%ax, %%ds; mov %%ax, %%es; mov %%ax, %%ss; xor %%ax, %%ax; mov %%ax, %%fs; mov %%ax, %%gs;"
        : : [kcs] "i"(GDT_KERNEL_CODE), [kds] "i"(GDT_KERNEL_DATA) : "rax", "memory");
END ReloadSegments;

(* =====================================================================
   Public entry point
   ===================================================================== *)

PROCEDURE GDTInit();
VAR
    tssBase, gdtBase: CARDINAL64;
    tp: TSSPtr;
    gp: GDTArrayPtr;
    gdtr: GDTR;
    i: CARDINAL;
    stackTop: CARDINAL64;
    access, flags: BYTE;
BEGIN
    (* ---- Obtain pointers to assembly-provided storage ---------- *)
    tssBase := TSSAddr();
    gdtBase := GDTAddr();
    tp := VAL(TSSPtr, VAL(ADDRESS, tssBase));
    gp := VAL(GDTArrayPtr, VAL(ADDRESS, gdtBase));

    (* ---- Zero out the GDT array (7 x 8 = 56 bytes) ------------- *)
    FOR i := 0 TO 6 DO
        gp^[i] := 0;
    END;

    (* ---- Zero out the TSS (104 bytes) --------------------------
       The TSS is in BSS which the bootloader already zeroed, but we
       clear the fields we use explicitly for safety.  Reserved and
       unused fields stay zero. *)
    tp^.reserved1  := 0;
    tp^.rsp0Lo     := 0; tp^.rsp0Hi := 0;
    tp^.rsp1Lo     := 0; tp^.rsp1Hi := 0;
    tp^.rsp2Lo     := 0; tp^.rsp2Hi := 0;
    tp^.reserved2a := 0; tp^.reserved2b := 0;
    tp^.ist1Lo     := 0; tp^.ist1Hi := 0;
    tp^.ist2Lo     := 0; tp^.ist2Hi := 0;
    tp^.ist3Lo     := 0; tp^.ist3Hi := 0;
    tp^.ist4Lo     := 0; tp^.ist4Hi := 0;
    tp^.ist5Lo     := 0; tp^.ist5Hi := 0;
    tp^.ist6Lo     := 0; tp^.ist6Hi := 0;
    tp^.ist7Lo     := 0; tp^.ist7Hi := 0;
    tp^.reserved3a := 0; tp^.reserved3b := 0;
    tp^.reserved4  := 0;
    tp^.iomap      := 0;

    (* ---- Populate code/data descriptors ------------------------ *)

    (* [1] Kernel code: present, code/data, exec, readable, DPL=0,
           long mode (L=1), 4 KiB granularity.
       Disjoint bit constants -- addition == bitwise OR. *)
    access := BYTE(GDT_ACCESS_PRESENT + GDT_ACCESS_CODE_DATA
                   + GDT_ACCESS_EXEC + GDT_ACCESS_RW);
    flags  := BYTE(GDT_FLAG_LONG + GDT_FLAG_GRAN);
    gp^[1] := EncodeCodeData(0, 0FFFFFH, access, flags);

    (* [2] Kernel data: present, code/data, writable, DPL=0, 4KiB gran. *)
    access := BYTE(GDT_ACCESS_PRESENT + GDT_ACCESS_CODE_DATA + GDT_ACCESS_RW);
    flags  := BYTE(GDT_FLAG_GRAN);
    gp^[2] := EncodeCodeData(0, 0FFFFFH, access, flags);

    (* [3] User data: DPL=3, otherwise same as kernel data. *)
    access := BYTE(GDT_ACCESS_PRESENT + GDT_ACCESS_CODE_DATA
                   + GDT_ACCESS_RW + GDT_ACCESS_DPL_USER);
    flags  := BYTE(GDT_FLAG_GRAN);
    gp^[3] := EncodeCodeData(0, 0FFFFFH, access, flags);

    (* [4] User code: exec+readable, DPL=3, long, 4KiB gran. *)
    access := BYTE(GDT_ACCESS_PRESENT + GDT_ACCESS_CODE_DATA
                   + GDT_ACCESS_EXEC + GDT_ACCESS_RW + GDT_ACCESS_DPL_USER);
    flags  := BYTE(GDT_FLAG_LONG + GDT_FLAG_GRAN);
    gp^[4] := EncodeCodeData(0, 0FFFFFH, access, flags);

    (* ---- Populate TSS ------------------------------------------ *)

    (* Ring-0 stack: top of kernelStack array (stacks grow down). *)
    stackTop := KernelStackAddr() + KERNEL_STACK_SIZE;
    WritePtr(tp^.rsp0Lo, tp^.rsp0Hi, stackTop);
    WritePtr(tp^.rsp1Lo, tp^.rsp1Hi, stackTop);
    WritePtr(tp^.rsp2Lo, tp^.rsp2Hi, stackTop);

    (* IST slots 1..7: each has a dedicated 8 KiB stack. *)
    WritePtr(tp^.ist1Lo, tp^.ist1Hi, ISTStackAddr(0) + IST_STACK_SIZE);
    WritePtr(tp^.ist2Lo, tp^.ist2Hi, ISTStackAddr(1) + IST_STACK_SIZE);
    WritePtr(tp^.ist3Lo, tp^.ist3Hi, ISTStackAddr(2) + IST_STACK_SIZE);
    WritePtr(tp^.ist4Lo, tp^.ist4Hi, ISTStackAddr(3) + IST_STACK_SIZE);
    WritePtr(tp^.ist5Lo, tp^.ist5Hi, ISTStackAddr(4) + IST_STACK_SIZE);
    WritePtr(tp^.ist6Lo, tp^.ist6Hi, ISTStackAddr(5) + IST_STACK_SIZE);
    WritePtr(tp^.ist7Lo, tp^.ist7Hi, ISTStackAddr(6) + IST_STACK_SIZE);

    (* I/O permission bitmap offset set past the TSS end: no IOPB. *)
    tp^.iomap := TSS_SIZE;

    (* ---- Fill the TSS descriptor in GDT slots [5] and [6] ------ *)
    gp^[5] := EncodeTSSLow(tssBase, TSS_LIMIT);
    gp^[6] := EncodeTSSHigh(tssBase);

    (* ---- Assemble GDTR as a packed byte array ------------------
       Hardware layout (10 bytes, little-endian):
         [0..1]  limit (16-bit)
         [2..9]  base  (64-bit)
       We fill with the StU16/StU64 helpers to guarantee no padding. *)
    FOR i := 0 TO 9 DO
        gdtr[i] := BYTE(0);
    END;
    StU16(gdtr, 0, VAL(CARDINAL16, 7 * 8 - 1));    (* limit = 55 *)
    StU64(gdtr, 2, gdtBase);                        (* GDT base address *)

    (* ---- Load GDT and reload segments -------------------------- *)
    (* Pass the gdtr byte array directly as a memory operand. *)
    ASM VOLATILE ("lgdt %[gdtr]" : : [gdtr] "m"(gdtr) : "memory");
    ReloadSegments();

    (* ---- Load TSS ---------------------------------------------- *)
    LTR(GDT_TSS);
END GDTInit;

END GDT.
