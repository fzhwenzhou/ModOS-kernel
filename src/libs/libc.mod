(* libc.mod — Implementation of the minimal C library in pure Modula-2.

   Provides the memory functions the compiler generates calls to,
   plus stubs for abort, exit, and printf that a bare-metal kernel
   cannot meaningfully implement. *)

IMPLEMENTATION MODULE libc ;

FROM SYSTEM IMPORT ADDRESS, BYTE, CARDINAL64 ;

TYPE
    BytePtr = POINTER TO BYTE ;


(*
   memcpy — copy n bytes from src to dest (non-overlapping).
*)

PROCEDURE memcpy (dest, src: ADDRESS; n: CARDINAL) : ADDRESS ;
VAR
    d, s: BytePtr ;
    i: CARDINAL ;
BEGIN
    d := VAL (BytePtr, dest) ;
    s := VAL (BytePtr, src) ;
    i := n ;
    WHILE i > 0 DO
        d^ := s^ ;
        d := VAL (BytePtr, VAL (ADDRESS, VAL (CARDINAL64, VAL (ADDRESS, d)) + 1)) ;
        s := VAL (BytePtr, VAL (ADDRESS, VAL (CARDINAL64, VAL (ADDRESS, s)) + 1)) ;
        DEC (i) ;
    END ;
    RETURN dest ;
END memcpy ;


(*
   memset — set n bytes starting at s to byte value c.
*)

PROCEDURE memset (s: ADDRESS; c: INTEGER; n: CARDINAL) : ADDRESS ;
VAR
    p: BytePtr ;
    i: CARDINAL ;
BEGIN
    p := VAL (BytePtr, s) ;
    i := n ;
    WHILE i > 0 DO
        p^ := VAL (BYTE, c) ;
        p := VAL (BytePtr, VAL (ADDRESS, VAL (CARDINAL64, VAL (ADDRESS, p)) + 1)) ;
        DEC (i) ;
    END ;
    RETURN s ;
END memset ;


(*
   memmove — copy n bytes from src to dest (handles overlap).
*)

PROCEDURE memmove (dest, src: ADDRESS; n: CARDINAL) : ADDRESS ;
VAR
    d, s: BytePtr ;
    dAddr, sAddr: CARDINAL64 ;
    i: CARDINAL ;
BEGIN
    dAddr := VAL (CARDINAL64, VAL (ADDRESS, dest)) ;
    sAddr := VAL (CARDINAL64, VAL (ADDRESS, src)) ;
    IF dAddr < sAddr THEN
        (* Copy forward *)
        d := VAL (BytePtr, dest) ;
        s := VAL (BytePtr, src) ;
        i := n ;
        WHILE i > 0 DO
            d^ := s^ ;
            d := VAL (BytePtr, VAL (ADDRESS, VAL (CARDINAL64, VAL (ADDRESS, d)) + 1)) ;
            s := VAL (BytePtr, VAL (ADDRESS, VAL (CARDINAL64, VAL (ADDRESS, s)) + 1)) ;
            DEC (i) ;
        END ;
    ELSE
        (* Copy backward *)
        d := VAL (BytePtr, VAL (ADDRESS, dAddr + VAL (CARDINAL64, n) - 1)) ;
        s := VAL (BytePtr, VAL (ADDRESS, sAddr + VAL (CARDINAL64, n) - 1)) ;
        i := n ;
        WHILE i > 0 DO
            d^ := s^ ;
            d := VAL (BytePtr, VAL (ADDRESS, VAL (CARDINAL64, VAL (ADDRESS, d)) - 1)) ;
            s := VAL (BytePtr, VAL (ADDRESS, VAL (CARDINAL64, VAL (ADDRESS, s)) - 1)) ;
            DEC (i) ;
        END ;
    END ;
    RETURN dest ;
END memmove ;


(*
   memcmp — compare n bytes of s1 and s2.
   Returns 0 if equal, <0 if s1 < s2, >0 if s1 > s2.
*)

PROCEDURE memcmp (s1, s2: ADDRESS; n: CARDINAL) : INTEGER ;
VAR
    p1, p2: BytePtr ;
    i: CARDINAL ;
BEGIN
    p1 := VAL (BytePtr, s1) ;
    p2 := VAL (BytePtr, s2) ;
    i := n ;
    WHILE i > 0 DO
        IF p1^ # p2^ THEN
            IF VAL (CARDINAL, p1^) < VAL (CARDINAL, p2^) THEN
                RETURN -1 ;
            ELSE
                RETURN 1 ;
            END ;
        END ;
        p1 := VAL (BytePtr, VAL (ADDRESS, VAL (CARDINAL64, VAL (ADDRESS, p1)) + 1)) ;
        p2 := VAL (BytePtr, VAL (ADDRESS, VAL (CARDINAL64, VAL (ADDRESS, p2)) + 1)) ;
        DEC (i) ;
    END ;
    RETURN 0 ;
END memcmp ;


END libc.