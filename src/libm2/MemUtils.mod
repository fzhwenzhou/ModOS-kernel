(* MemUtils.mod provides some basic memory utilities.

   MemCopy/MemZero are thin wrappers around the libc memcpy/memset
   functions.  Their return values are discarded via the dummy
   assignment to keep gm2 happy (string.declares memcpy/memset as
   returning ADDRESS). *)

IMPLEMENTATION MODULE MemUtils;

FROM SYSTEM IMPORT WORD, ADDRESS;
FROM string IMPORT memcpy, memset;

(* MemCopy -- copy length bytes from from to to. *)
PROCEDURE MemCopy(from: ADDRESS; length: CARDINAL; to: ADDRESS);
VAR
    dummy: ADDRESS;
BEGIN
    dummy := memcpy(to, from, length);
END MemCopy;

(* MemZero -- set length bytes starting at a to zero. *)
PROCEDURE MemZero(a: ADDRESS; length: CARDINAL);
VAR
    dummy: ADDRESS;
BEGIN
    dummy := memset(a, 0, length);
END MemZero;

END MemUtils.
