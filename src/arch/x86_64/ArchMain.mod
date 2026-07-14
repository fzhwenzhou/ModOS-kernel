IMPLEMENTATION MODULE ArchMain;

FROM SYSTEM IMPORT BYTE, BITSET8, ADDRESS, CARDINAL8;
FROM Multiboot2 IMPORT
    MULTIBOOT2_BOOTLOADER_MAGIC, MULTIBOOT_INFO_ALIGN, MULTIBOOT_TAG_ALIGN,
    MULTIBOOT_TAG_TYPE_END, MULTIBOOT_TAG_TYPE_FRAMEBUFFER,
    MULTIBOOT_FRAMEBUFFER_TYPE_RGB,
    MultibootTag, MultibootTagPtr,
    MultibootTagFramebuffer, MultibootTagFramebufferPtr;
FROM Main IMPORT Main;

CONST
    COM1 = 3F8H;

TYPE
    (* 32-bit BGRA pixel (matches VBE RGB framebuffer layout) *)
    Pixel32 = RECORD
        blue:  BYTE;
        green: BYTE;
        red:   BYTE;
        alpha: BYTE;
    END;
    Pixel32Ptr = POINTER TO Pixel32;

(*
   ByteAnd - returns a bitwise (left AND right)
*)

PROCEDURE ByteAnd (left, right: BYTE): BYTE;
BEGIN
   RETURN VAL(BYTE, VAL(BITSET8, left) * VAL(BITSET8, right));
END ByteAnd;

PROCEDURE HCF;
BEGIN
    LOOP
        ASM VOLATILE ("hlt");
    END;
END HCF;

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

PROCEDURE SerialInit;
BEGIN
    OUTB(COM1 + 1, 000H);    (* Disable all interrupts *)
    OUTB(COM1 + 3, 080H);  (* Enable DLAB (set baud rate divisor) *)
    OUTB(COM1 + 0, 003H);  (* Set divisor to 3 (lo byte) 38400 baud *)
    OUTB(COM1 + 1, 000H);  (*                  (hi byte) *)
    OUTB(COM1 + 3, 003H);  (* 8 bits, no parity, one stop bit *)
    OUTB(COM1 + 2, 0C7H);  (* Enable FIFO, clear them, with 14-byte threshold *)
    OUTB(COM1 + 4, 00BH);  (* IRQs enabled, RTS/DSR set *)
END SerialInit;

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

PROCEDURE SerialWriteLongCard(n: LONGCARD);
VAR
    buffer: ARRAY [0..10] OF CHAR;
    i: CARDINAL;
BEGIN
    IF n = 0 THEN
        SerialWriteChar('0');
        RETURN;
    END;
    i := 0;
    WHILE n > 0 DO
        buffer[i] := VAL(CHAR, n MOD 10 + VAL(LONGCARD, ORD('0')));
        INC(i);
        n := n DIV 10;
    END;
    WHILE i > 0 DO
        DEC(i);
        SerialWriteChar(buffer[i]);
    END;
END SerialWriteLongCard;

PROCEDURE SerialWriteLongCardHex(n: LONGCARD);
VAR
    buffer: ARRAY [0..8] OF CHAR;
    i: CARDINAL;
    digit: LONGCARD;
BEGIN
    i := 0;
    WHILE i < 8 DO
        digit := n MOD 16;
        IF digit < 10 THEN
            buffer[7 - i] := VAL(CHAR, digit + VAL(LONGCARD, ORD('0')));
        ELSE
            buffer[7 - i] := VAL(CHAR, digit - 10 + VAL(LONGCARD, ORD('A')));
        END;
        n := n DIV 16;
        INC(i);
    END;
    SerialWriteString("0x");
    FOR i := 0 TO 7 DO
        SerialWriteChar(buffer[i]);
    END;
END SerialWriteLongCardHex;

PROCEDURE KernelMain(magic, infoAddr: LONGCARD);
VAR
    tag: MultibootTagPtr;
    fbTag: MultibootTagFramebufferPtr;
    pixel: Pixel32Ptr;
    fbAddr: LONGCARD;
    pitch, width, height: CARDINAL;
    bpp: CARDINAL8;
    row, col: CARDINAL;
    rowAddr: LONGCARD;
    emptyArgs: ARRAY [0..0] OF ARRAY [0..0] OF CHAR;
BEGIN
    SerialInit;
    SerialWriteString("Hello, World from Modula-2 Kernel!");
    SerialWriteChar(BYTE(10)); (* Newline *)

    (* Check if the magic number is correct *)
    IF magic # MULTIBOOT2_BOOTLOADER_MAGIC THEN
        SerialWriteString("Error: Invalid magic number! Expected: ");
        SerialWriteLongCardHex(MULTIBOOT2_BOOTLOADER_MAGIC);
        SerialWriteChar(BYTE(10)); (* Newline *)
        HCF;
    END;

    (* Check alignment *)
    IF infoAddr MOD MULTIBOOT_INFO_ALIGN # 0 THEN
        SerialWriteString("Error: Info address is not properly aligned!");
        SerialWriteChar(BYTE(10)); (* Newline *)
        HCF;
    END;

    (* ---- Find the framebuffer tag in the multiboot2 info structure ---- *)
    tag := VAL(MultibootTagPtr, VAL(ADDRESS, infoAddr + 8));
    WHILE (tag # NIL) AND (tag^.tagType # MULTIBOOT_TAG_TYPE_FRAMEBUFFER) DO
        IF tag^.tagType = MULTIBOOT_TAG_TYPE_END THEN
            tag := NIL;
        ELSE
            (* Advance to next tag: align (addr + size) to 8 bytes *)
            tag := VAL(MultibootTagPtr,
                       VAL(ADDRESS,
                           (VAL(LONGCARD, VAL(ADDRESS, tag))
                            + VAL(LONGCARD, tag^.size) + 7) DIV 8 * 8));
        END;
    END;

    IF tag = NIL THEN
        SerialWriteString("Error: No framebuffer tag found!");
        SerialWriteChar(BYTE(10));
        HCF;
    END;

    (* ---- Read framebuffer parameters ---- *)
    fbTag := VAL(MultibootTagFramebufferPtr, VAL(ADDRESS, tag));
    fbAddr := VAL(LONGCARD, fbTag^.framebufferAddr);
    pitch  := fbTag^.framebufferPitch;
    width  := fbTag^.framebufferWidth;
    height := fbTag^.framebufferHeight;
    bpp    := fbTag^.framebufferBpp;

    SerialWriteString("Framebuffer: ");
    SerialWriteLongCard(width);
    SerialWriteString("x");
    SerialWriteLongCard(height);
    SerialWriteString("x");
    SerialWriteLongCard(VAL(LONGCARD, bpp));
    SerialWriteString(", pitch=");
    SerialWriteLongCard(pitch);
    SerialWriteString(", addr=");
    SerialWriteLongCardHex(fbAddr);
    SerialWriteChar(BYTE(10));

    (* ---- Fill the framebuffer with an RGB gradient (32 bpp only) ---- *)
    IF bpp = VAL(CARDINAL8, 32) THEN
        FOR row := 0 TO height - 1 DO
            rowAddr := fbAddr + VAL(LONGCARD, row) * VAL(LONGCARD, pitch);
            FOR col := 0 TO width - 1 DO
                pixel := VAL(Pixel32Ptr,
                             VAL(ADDRESS, rowAddr + VAL(LONGCARD, col) * 4));
                pixel^.blue := BYTE(0);
                pixel^.green := BYTE(0);
                pixel^.red := BYTE(0);
                IF col < width DIV 3 THEN
                    pixel^.red := BYTE(255);
                ELSIF col < 2 * width DIV 3 THEN
                    pixel^.green := BYTE(255);
                ELSE
                    pixel^.blue := BYTE(255);
                END;
                pixel^.alpha := BYTE(255);
            END;
        END;
        SerialWriteString("Framebuffer filled with RGB!");
    ELSE
        SerialWriteString("Framebuffer is not 32 bpp (got ");
        SerialWriteLongCard(VAL(LONGCARD, bpp));
        SerialWriteString(" bpp) — skipping fill");
    END;
    SerialWriteChar(BYTE(10));

    Main(0, NIL); (* Call the main procedure from Main.mod *)

END KernelMain;

END ArchMain.