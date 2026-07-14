(* BitByteOps.mod provides a Logitech-3.0 compatible library *)

IMPLEMENTATION MODULE BitByteOps;

FROM SYSTEM IMPORT TSIZE, BITSET8, CARDINAL8, BYTE;

(*
    ByteAnd - returns a bitwise (left AND right)
*)
PROCEDURE ByteAnd (left, right: BYTE): BYTE;
VAR
    result: BYTE;
BEGIN
    ASM VOLATILE ("andb %1, %0" : "=a"(result) : "a"(left), "r"(right));
    RETURN result;
END ByteAnd;

(*
    ByteOr - returns a bitwise (left OR right)
*)
PROCEDURE ByteOr (left, right: BYTE): BYTE;
VAR
    result: BYTE;
BEGIN
    ASM VOLATILE ("orb %1, %0" : "=a"(result) : "a"(left), "r"(right));
    RETURN result;
END ByteOr;

(*
    ByteXor - returns a bitwise (left XOR right)
*)
PROCEDURE ByteXor (left, right: BYTE): BYTE;
VAR
    result: BYTE;
BEGIN
    ASM VOLATILE ("xorb %1, %0" : "=a"(result) : "a"(left), "r"(right));
    RETURN result;
END ByteXor;

(*
    ByteNot - returns a bitwise NOT of the input byte
*)
PROCEDURE ByteNot (input: BYTE): BYTE;
VAR
    result: BYTE;
BEGIN
    ASM VOLATILE ("notb %0" : "=a"(result) : "a"(input));
    RETURN result;
END ByteNot;

(*
    ByteShl - returns the input byte shifted left by the specified number of bits
*)
PROCEDURE ByteShl (input: BYTE; count: CARDINAL): BYTE;
VAR
    result: BYTE;
BEGIN
    ASM VOLATILE ("shlb %%cl, %0" : "=a"(result) : "a"(input), "c"(count));
    RETURN result;
END ByteShl;

(*
    ByteShr - returns the input byte shifted right by the specified number of bits
*)
PROCEDURE ByteShr (input: BYTE; count: CARDINAL): BYTE;
VAR
    result: BYTE;
BEGIN
    ASM VOLATILE ("shrb %%cl, %0" : "=a"(result) : "a"(input), "c"(count));
    RETURN result;
END ByteShr;

(*
    ByteSar - returns the input byte shifted right by the specified number of bits (arithmetic shift)
*)
PROCEDURE ByteSar (input: BYTE; count: CARDINAL): BYTE;
VAR
    result: BYTE;
BEGIN
    ASM VOLATILE ("sarb %%cl, %0" : "=a"(result) : "a"(input), "c"(count));
    RETURN result;
END ByteSar;

(*
    ByteRor - returns the input byte rotated right by the specified number of bits
*)
PROCEDURE ByteRor (input: BYTE; count: CARDINAL): BYTE;
VAR
    result: BYTE;
BEGIN
    ASM VOLATILE ("rorb %%cl, %0" : "=a"(result) : "a"(input), "c"(count));
    RETURN result;
END ByteRor;

(*
    ByteRol - returns the input byte rotated left by the specified number of bits
*)
PROCEDURE ByteRol (input: BYTE; count: CARDINAL): BYTE;
VAR
    result: BYTE;
BEGIN
    ASM VOLATILE ("rolb %%cl, %0" : "=a"(result) : "a"(input), "c"(count));
    RETURN result;
END ByteRol;

END BitByteOps.