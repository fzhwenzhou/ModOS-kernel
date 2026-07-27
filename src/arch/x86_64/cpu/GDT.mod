IMPLEMENTATION MODULE GDT;

(* GDT.mod -- 64-bit Global Descriptor Table and Task State Segment.

   See GDT.def for overview.

   Layout notes:
   * The GDT is an array of seven 64-bit slots.  Each code/data descriptor
     is a single 64-bit value hand-assembled from base/limit/access/flags
     fields, which avoids any compiler-specific record padding.
   * The TSS descriptor occupies slots [5] and [6]: slot [5] holds the
     low 8 bytes (limit = sizeof(TSS)-1, access = 0x89 = present + 64-bit
     TSS available, base bits 0..23, flags nibble 0), and slot [6] holds
     base bits 32..63.
   * The TSS is a plain Modula-2 record with 64-bit fields split into
     lo/hi CARDINAL32 pairs.  GNU Modula-2 aligns fields to their natural
     boundary and does not insert padding between a CARDINAL16 and a
     following CARDINAL32, so the struct is exactly 104 bytes.
   * Ring-0 and IST stacks are static byte arrays placed in BSS by gm2.
     We force their emission by passing ADR(arr) to MemZero and to the
     helpers that program the TSS.  ADR() is the SYSTEM.AddressOf
     operator that the user explicitly asked us to use.
   * The 48-bit GDTR pseudo-descriptor is a 10-byte packed byte array;
     we build it in-place on the stack to avoid any global alignment
     surprises. *)

FROM SYSTEM IMPORT BYTE, CARDINAL16, CARDINAL32, CARDINAL64, ADDRESS, ADR;
FROM MemUtils IMPORT MemZero;

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

    (* Flags nibble (high nibble of byte 6 of a code/data descriptor) *)
    GDT_FLAG_LONG        = 20H;   (* L: 64-bit code segment *)
    GDT_FLAG_GRAN        = 80H;   (* G: 4 KiB granularity *)

    (* TSS size: 104 bytes (fixed layout, no I/O permission bitmap) *)
    TSS_SIZE             = 104;
    TSS_LIMIT            = TSS_SIZE - 1;

    (* Kernel ring-0 stack: 32 KiB *)
    KERNEL_STACK_SIZE    = 32768;

    (* Each IST stack slot: 8 KiB, seven slots total *)
    IST_STACK_SIZE       = 8192;
    IST_COUNT            = 7;

(* =====================================================================
   Types
   ===================================================================== *)

TYPE
    (* The 104-byte 64-bit TSS.  64-bit fields are split into lo/hi
       CARDINAL32 pairs so CARDINAL64 alignment never introduces padding.
       iomap is set to TSS_SIZE (104) meaning there is no I/O permission
       bitmap: every port access from CPL > IOPL raises #GP. *)
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
        iomap:      CARDINAL16;                 (* +102 IOPB offset *)
    END;

    (* The GDT is an array of seven 64-bit descriptors. *)
    GDTArray = ARRAY [0..6] OF CARDINAL64;

    (* 48-bit GDTR value passed to lgdt.  Hardware layout is:
         offset 0: 16-bit limit
         offset 2: 64-bit base
       for a total of 10 bytes.  We use a 10-byte array and fill it
       in-place on the stack to avoid alignment padding. *)
    GDTR = ARRAY [0..9] OF BYTE;

    TSSPtr      = POINTER TO TSS;
    GDTArrayPtr = POINTER TO GDTArray;

(* =====================================================================
   Module-level storage.
   Placed in BSS by gm2; ADR() calls in GDTInit force emission.
   ===================================================================== *)

VAR
    gdt:         GDTArray;                                  (* 56 B *)
    tss:         TSS;                                       (* 104 B *)
    kernelStack: ARRAY [0..KERNEL_STACK_SIZE - 1] OF BYTE;  (* 32 KiB *)
    istStacks:   ARRAY [0..IST_COUNT - 1] OF
                     ARRAY [0..IST_STACK_SIZE - 1] OF BYTE; (* 56 KiB *)

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
    baseLo  := VAL(CARDINAL64, base) MOD 65536;
    baseMi  := (VAL(CARDINAL64, base) DIV 65536) MOD 256;
    baseHi  := VAL(CARDINAL64, base) DIV 16777216;
    limitLo := VAL(CARDINAL64, limit) MOD 65536;

    (* byte 6 = (flags & 0xF0) + ((limit >> 16) & 0x0F).
       The two nibbles are disjoint so addition acts like bitwise OR. *)
    flagsLimitHi := VAL(BYTE, VAL(CARDINAL32, flags) + (limit DIV 65536));

    (* All other bit fields are disjoint too; integer addition is
       equivalent to bitwise OR (gm2 treats OR as a BOOLEAN operator
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
   Access = 0x89 (present + 64-bit TSS available).  Flags nibble = 0. *)
PROCEDURE EncodeTSSLow(base: CARDINAL64; limit: CARDINAL16): CARDINAL64;
VAR
    entry: CARDINAL64;
    baseLo, baseMi, baseHi: CARDINAL64;
BEGIN
    baseLo := base MOD 65536;
    baseMi := (base DIV 65536) MOD 256;
    baseHi := (base DIV 16777216) MOD 256;

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
   array, which must not have alignment padding. *)
PROCEDURE StU16(VAR buf: ARRAY OF BYTE; off: CARDINAL; v: CARDINAL16);
VAR 
    p: POINTER TO CARDINAL16;
BEGIN
    p := ADR(buf[off]);
    p^ := v;
END StU16;

PROCEDURE StU64(VAR buf: ARRAY OF BYTE; off: CARDINAL; v: CARDINAL64);
VAR 
    p: POINTER TO CARDINAL64;
BEGIN
    p := ADR(buf[off]);
    p^ := v;
END StU64;

(* =====================================================================
   Privileged-instruction helpers (inline assembly)
   ===================================================================== *)

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
    (* ---- Take addresses of our static BSS objects --------------
       ADR() from SYSTEM returns an ADDRESS; calling it (and passing
       the result to MemZero / WritePtr) forces gm2 to actually emit
       the BSS symbols.  We cast through ADDRESS and then to both
       TSSPtr/GDTArrayPtr (for field access) and CARDINAL64 (for
       descriptor encoding and GDTR population). *)
    tp := VAL(TSSPtr,      ADR(tss));
    gp := VAL(GDTArrayPtr, ADR(gdt));
    tssBase := VAL(CARDINAL64, VAL(ADDRESS, tp));
    gdtBase := VAL(CARDINAL64, VAL(ADDRESS, gp));

    (* ---- Zero the GDT and TSS with a single MemZero each -------
       MemZero is the efficient bulk-zero primitive from MemUtils.
       The stacks live in BSS which the bootloader already zeroed;
       we do not waste time re-zeroing them. *)
    MemZero(VAL(ADDRESS, gp), 7 * 8);         (* 56 bytes *)
    MemZero(VAL(ADDRESS, tp), TSS_SIZE);      (* 104 bytes *)

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

    (* Ring-0 stack: top of kernelStack (stacks grow downward). *)
    stackTop := VAL(CARDINAL64, VAL(ADDRESS, ADR(kernelStack))) + KERNEL_STACK_SIZE;
    WritePtr(tp^.rsp0Lo, tp^.rsp0Hi, stackTop);
    WritePtr(tp^.rsp1Lo, tp^.rsp1Hi, stackTop);
    WritePtr(tp^.rsp2Lo, tp^.rsp2Hi, stackTop);

    (* IST slots 1..7: each has a dedicated 8 KiB stack.
       ADR(istStacks[i]) takes the address of each nested array; the
       CARDINAL64 cast routes through ADDRESS first via VAL(). *)
    FOR i := 0 TO IST_COUNT - 1 DO
        stackTop := VAL(CARDINAL64, VAL(ADDRESS, ADR(istStacks[i])))
                    + IST_STACK_SIZE;
        CASE i OF
          0: WritePtr(tp^.ist1Lo, tp^.ist1Hi, stackTop);
        | 1: WritePtr(tp^.ist2Lo, tp^.ist2Hi, stackTop);
        | 2: WritePtr(tp^.ist3Lo, tp^.ist3Hi, stackTop);
        | 3: WritePtr(tp^.ist4Lo, tp^.ist4Hi, stackTop);
        | 4: WritePtr(tp^.ist5Lo, tp^.ist5Hi, stackTop);
        | 5: WritePtr(tp^.ist6Lo, tp^.ist6Hi, stackTop);
        | 6: WritePtr(tp^.ist7Lo, tp^.ist7Hi, stackTop);
        END;
    END;

    (* I/O permission bitmap offset = TSS_SIZE: no IOPB. *)
    tp^.iomap := TSS_SIZE;

    (* ---- Fill TSS descriptor in GDT slots [5] and [6] ----------- *)
    gp^[5] := EncodeTSSLow(tssBase, TSS_LIMIT);
    gp^[6] := EncodeTSSHigh(tssBase);

    (* ---- Assemble GDTR (packed 10-byte layout on the stack) -----
         [0..1] limit (16-bit) = 55 = 7*8 - 1
         [2..9] base  (64-bit) = gdtBase
       We clear the whole array then store the two fields. *)
    MemZero(VAL(ADDRESS, ADR(gdtr)), 10);
    StU16(gdtr, 0, VAL(CARDINAL16, 7 * 8 - 1));
    StU64(gdtr, 2, gdtBase);

    (* ---- Load GDT and reload segments -------------------------- *)
    ASM VOLATILE ("lgdt %[gdtr]" : : [gdtr] "m"(gdtr) : "memory");
    ReloadSegments();

    (* ---- Load TSS ---------------------------------------------- *)
    LTR(GDT_TSS);
END GDTInit;

END GDT.
