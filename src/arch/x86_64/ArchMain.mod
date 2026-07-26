IMPLEMENTATION MODULE ArchMain;

FROM SYSTEM IMPORT BYTE, ADDRESS, CARDINAL8, CARDINAL16, CARDINAL64;
FROM Limine IMPORT
    LIMINE_FRAMEBUFFER_RGB,
    LimineFramebuffer, LimineFramebufferPtr,
    LimineFramebufferResponse, LimineFramebufferResponsePtr,
    limineBaseRevision,
    limineFramebufferRequest;
FROM Main IMPORT Main;
FROM BitByteOps IMPORT ByteAnd;
FROM GDT IMPORT GDTInit;

CONST
    COM1 = 3F8H;

TYPE
    (* 32-bit BGRA pixel (matches RGB framebuffer layout on x86) *)
    Pixel32 = RECORD
        blue:  BYTE;
        green: BYTE;
        red:   BYTE;
        alpha: BYTE;
    END;
    Pixel32Ptr = POINTER TO Pixel32;

    (* Pointer to an array of Limine framebuffer pointers (ptr-to-ptr) *)
    LimineFramebufferPtrPtr = POINTER TO LimineFramebufferPtr;

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

PROCEDURE SerialWriteCardinal64(n: CARDINAL64);
VAR
    buffer: ARRAY [0..20] OF CHAR;
    i: CARDINAL;
BEGIN
    IF n = 0 THEN
        SerialWriteChar('0');
        RETURN;
    END;
    i := 0;
    WHILE n > 0 DO
        buffer[i] := VAL(CHAR, n MOD 10 + VAL(CARDINAL64, ORD('0')));
        INC(i);
        n := n DIV 10;
    END;
    WHILE i > 0 DO
        DEC(i);
        SerialWriteChar(buffer[i]);
    END;
END SerialWriteCardinal64;

PROCEDURE SerialWriteCardinal64Hex(n: CARDINAL64);
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
END SerialWriteCardinal64Hex;

PROCEDURE KernelMain();
VAR
    fbResp: LimineFramebufferResponsePtr;
    fbPtr: LimineFramebufferPtr;
    fbPtrPtr: LimineFramebufferPtrPtr;
    pixel: Pixel32Ptr;
    fbAddr: CARDINAL64;
    pitch, width, height: CARDINAL64;
    bpp: CARDINAL16;
    row, col: CARDINAL64;
    rowAddr: CARDINAL64;
    baseRev: CARDINAL64;
BEGIN
    SerialInit;
    SerialWriteString("Hello, World from Modula-2 Kernel (Limine)!");
    SerialWriteChar(BYTE(10)); (* Newline *)

    (* ---- Verify base revision ---- *)
    baseRev := limineBaseRevision[2];
    SerialWriteString("Base revision: requested=6, bootloader reports ");
    SerialWriteCardinal64(baseRev);
    SerialWriteChar(BYTE(10));
    IF baseRev # 0 THEN
        SerialWriteString("Error: Limine base revision 6 not supported!");
        SerialWriteChar(BYTE(10));
        HCF;
    END;

    (* ---- Set up our own GDT and TSS ---------------------------
       Limine enters with a bootloader-owned GDT (CS=0x28, DS=0x30).
       Replace it with a kernel-owned GDT that includes a 64-bit TSS
       providing rsp0 and IST stacks -- required before we enable
       interrupts or handle exceptions. *)
    SerialWriteString("Loading kernel GDT and TSS...");
    SerialWriteChar(BYTE(10));
    GDTInit();
    SerialWriteString("GDT and TSS loaded.");
    SerialWriteChar(BYTE(10));

    (* ---- Check framebuffer response ---- *)
    IF limineFramebufferRequest.response = NIL THEN
        SerialWriteString("Error: No framebuffer response from Limine!");
        SerialWriteChar(BYTE(10));
        HCF;
    END;

    fbResp := limineFramebufferRequest.response;
    SerialWriteString("Framebuffer count: ");
    SerialWriteCardinal64(fbResp^.framebufferCount);
    SerialWriteChar(BYTE(10));

    IF fbResp^.framebufferCount = 0 THEN
        SerialWriteString("Error: No framebuffers available!");
        SerialWriteChar(BYTE(10));
        HCF;
    END;

    (* Get the first framebuffer. framebuffers is a LimineFramebuffer**
       stored as a CARDINAL64 address.  We cast through ADDRESS. *)
    fbPtrPtr := VAL(LimineFramebufferPtrPtr,
                    VAL(ADDRESS, fbResp^.framebuffers));
    fbPtr := fbPtrPtr^;

    fbAddr := fbPtr^.address;
    pitch  := fbPtr^.pitch;
    width  := fbPtr^.width;
    height := fbPtr^.height;
    bpp    := fbPtr^.bpp;

    SerialWriteString("Framebuffer: ");
    SerialWriteCardinal64(width);
    SerialWriteString("x");
    SerialWriteCardinal64(height);
    SerialWriteString("x");
    SerialWriteCardinal64(VAL(CARDINAL64, bpp));
    SerialWriteString(", pitch=");
    SerialWriteCardinal64(pitch);
    SerialWriteString(", addr=");
    SerialWriteCardinal64Hex(fbAddr);
    SerialWriteChar(BYTE(10));

    SerialWriteString("Memory model: ");
    SerialWriteCardinal64(VAL(CARDINAL64, fbPtr^.memoryModel));
    SerialWriteString(" (RGB=");
    SerialWriteCardinal64(LIMINE_FRAMEBUFFER_RGB);
    SerialWriteString(")");
    SerialWriteChar(BYTE(10));

    (* ---- Fill the framebuffer with an RGB gradient (32 bpp only) ---- *)
    IF bpp = 32 THEN
        FOR row := 0 TO height - 1 DO
            rowAddr := fbAddr + row * pitch;
            FOR col := 0 TO width - 1 DO
                pixel := VAL(Pixel32Ptr,
                             VAL(ADDRESS, rowAddr + col * 4));
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
        SerialWriteString("Framebuffer filled with RGB stripes!");
    ELSE
        SerialWriteString("Framebuffer is not 32 bpp (got ");
        SerialWriteCardinal64(VAL(CARDINAL64, bpp));
        SerialWriteString(" bpp) — skipping fill");
    END;
    SerialWriteChar(BYTE(10));

    Main; (* Call the main procedure from Main.mod *)

END KernelMain;

END ArchMain.
