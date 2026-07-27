IMPLEMENTATION MODULE IDT;

(* IDT.mod -- 64-bit Interrupt Descriptor Table.

   See IDT.def for overview.

   Layout notes:
   * The IDT is an array of 256 16-byte gate descriptors.  Each
     descriptor is a plain Modula-2 record with CARDINAL16 and
     CARDINAL32 fields.  The fields are laid out so that the two
     CARDINAL32 fields (offsetHi, reserved) fall at offsets 8 and 12
     -- both naturally 4-byte aligned -- so gm2 inserts no padding
     and the record is exactly 16 bytes.
   * The 10-byte IDTR pseudo-descriptor uses the same packed byte-
     array technique as GDTR in GDT.mod: StU16 writes the 16-bit
     limit at offset 0, StU64 writes the 64-bit base at offset 2.
   * lidt is issued via inline assembly with the "m"(idtr) constraint,
     which binds to the local variable's own stack address -- the
     same pattern proven in GDT.mod for lgdt. *)

FROM SYSTEM IMPORT BYTE, CARDINAL16, CARDINAL32, CARDINAL64, ADDRESS, ADR, TSIZE;
FROM MemUtils IMPORT MemZero;

(* =====================================================================
   Constants
   ===================================================================== *)

CONST
    IDT_ENTRIES  = 256;
    IDT_ENTRY_SZ = 16;
    IDT_LIMIT    = IDT_ENTRIES * IDT_ENTRY_SZ - 1;   (* 4095 *)

    (* GDT kernel code selector -- must match GDT.mod. *)
    KERNEL_CODE_SEGMENT = 08H;

    (* IDT gate types (bits 8..11 of the flags word). *)
    GATE_INTERRUPT = 0EH;   (* interrupt gate -- CPU clears IF on entry *)
    GATE_TRAP      = 0FH;   (* trap gate -- IF unchanged *)

    (* Flags word bit masks (all disjoint). *)
    FLAG_PRESENT  = 8000H;  (* bit 15 *)
    FLAG_DPL_USER = 6000H;  (* bits 13..14 = 3 << 13 *)

(* =====================================================================
   Types
   ===================================================================== *)

TYPE
    (* 16-byte IDT gate descriptor (x86_64 long mode). *)
    IDTEntry = RECORD
        offsetLo:  CARDINAL16;   (* +0  handler bits 0..15   *)
        segment:   CARDINAL16;   (* +2  code segment selector *)
        flags:     CARDINAL16;   (* +4  IST / type / DPL / P  *)
        offsetMid: CARDINAL16;   (* +6  handler bits 16..31  *)
        offsetHi:  CARDINAL32;   (* +8  handler bits 32..63  *)
        reserved:  CARDINAL32;   (* +12 must be zero          *)
    END;

    IDT = ARRAY [0..IDT_ENTRIES - 1] OF IDTEntry;

    (* 10-byte IDTR pseudo-descriptor (packed, like GDTR). *)
    IDTR = ARRAY [0..9] OF BYTE;

    IDTEntryPtr = POINTER TO IDTEntry;

(* =====================================================================
   Module-level storage (BSS)
   ===================================================================== *)

VAR
    idt: IDT;                       (* 4096 bytes *)

(* =====================================================================
   Helpers -- little-endian stores into a byte array
   ===================================================================== *)

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
   Public procedures
   ===================================================================== *)

(* InstallInterrupt -- program one IDT gate descriptor. *)
PROCEDURE InstallInterrupt(handler: CARDINAL64; segment: CARDINAL16;
                           ist, dpl, gateType, vector: CARDINAL);
VAR
    entry: IDTEntryPtr;
    flags: CARDINAL16;
BEGIN
    entry := ADR(idt[vector]);

    (* Split the 64-bit handler address into lo/mid/hi. *)
    entry^.offsetLo  := VAL(CARDINAL16, handler MOD 65536);
    entry^.offsetMid := VAL(CARDINAL16, (handler DIV 65536) MOD 65536);
    entry^.offsetHi  := VAL(CARDINAL32, handler DIV 4294967296);

    (* Segment selector. *)
    entry^.segment := segment;

    (* Flags word: present | DPL | type | IST.
       All bit fields are disjoint -- addition == bitwise OR
       (gm2 treats OR as BOOLEAN on CARDINAL types). *)
    flags := VAL(CARDINAL16,
                 FLAG_PRESENT
                 + (dpl MOD 4) * 2000H         (* DPL << 13 *)
                 + (gateType MOD 16) * 100H    (* type << 8 *)
                 + (ist MOD 8));               (* IST bits 0..2 *)
    entry^.flags := flags;

    entry^.reserved := 0;
END InstallInterrupt;

(* IDTInit -- zero the IDT and load the IDTR. *)
PROCEDURE IDTInit();
VAR
    idtr: IDTR;
    idtBase: CARDINAL64;
BEGIN
    (* Zero all 256 entries (4096 bytes). *)
    MemZero(VAL(ADDRESS, ADR(idt)), TSIZE(IDT));

    (* Build the 10-byte IDTR:
         [0..1] limit (16-bit) = 4095
         [2..9] base  (64-bit) = address of idt *)
    idtBase := VAL(CARDINAL64, VAL(ADDRESS, ADR(idt)));
    StU16(idtr, 0, VAL(CARDINAL16, IDT_LIMIT));
    StU64(idtr, 2, idtBase);

    (* Load the IDTR.  "m"(idtr) binds to the local variable's own
       stack address -- the same pattern used for lgdt in GDT.mod. *)
    ASM VOLATILE ("lidt %[idtr]" : : [idtr] "m"(idtr) : "memory");
END IDTInit;

END IDT.
