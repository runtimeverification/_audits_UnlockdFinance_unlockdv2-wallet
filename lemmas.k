requires "evm.md"
requires "foundry.md"

module PROJECT-LEMMAS
    imports BOOL
    imports FOUNDRY
    imports INT-SYMBOLIC

    // Cancellativity #1
    rule A +Int ( (B -Int A) +Int C ) => B +Int C [simplification]

    // Cancellativity #2
    rule (A -Int B) -Int (C -Int B) => A -Int C [simplification]

    // Cancellativity #3
    rule A -Int (A +Int B) => 0 -Int B [simplification]

    // Various inequalities
    rule X  <Int A &Int B => true requires X <Int 0 andBool 0 <=Int A andBool 0 <=Int B [concrete(X), simplification]
    rule X  <Int A +Int B => true requires X <Int 0 andBool 0 <=Int A andBool 0 <=Int B [concrete(X), simplification]
    rule X <=Int A +Int B => true requires X <Int 0 andBool 0 <=Int A andBool 0 <=Int B [concrete(X), simplification]

    // Upper bound on (pow256 - 32) &Int lengthBytes(X)
    rule notMaxUInt5 &Int Y <=Int Y => true
      requires 0 <=Int Y
      [simplification]

    // Bounds on notMaxUInt5 &Int ( X +Int 31 )
    rule X <=Int   notMaxUInt5 &Int ( X +Int 31 )          => true requires 0 <=Int X                   [simplification]
    rule X <=Int   notMaxUInt5 &Int ( Y +Int 31 )          => true requires X <=Int 0 andBool 0 <=Int Y [simplification, concrete(X)]
    rule X <=Int ( notMaxUInt5 &Int ( X +Int 31 ) ) +Int Y => true requires 0 <=Int X andBool 0 <=Int Y [simplification, concrete(Y)]

    rule notMaxUInt5 &Int X +Int 31 <Int Y => true requires 0 <=Int X andBool X +Int 32 <=Int Y [simplification, concrete(Y)]

    rule notMaxUInt5 &Int X +Int 31 <Int X +Int 32 => true requires 0 <=Int X [simplification]

    // Move to function parameters
    rule { #asWord ( BA1 ) #Equals #asWord ( BA2 ) } => #Top
      requires BA1 ==K BA2
      [simplification]

    // #asWord ignores leading zeros
    rule #asWord ( BA1 +Bytes BA2 ) => #asWord ( BA2 )
      requires #asInteger(BA1) ==Int 0
      [simplification, concrete(BA1)]

    // `#asWord` of a byte array cannot equal a number that cannot fit within the byte array
    rule #asWord ( BA ) ==Int Y => false
        requires lengthBytes(BA) <=Int 32
         andBool (2 ^Int (8 *Int lengthBytes(BA))) <=Int Y
        [concrete(Y), simplification]

    // Conversion from bytes always yields a non-negative integer
    rule 0 <=Int #asInteger ( _ ) => true [simplification]

    // Definitional expansion
    rule #padRightToWidth (W, BA) => BA +Bytes #buf(W -Int lengthBytes(BA), 0)
      [concrete(W), simplification]

    // Parameter equality
    rule { #range (BA, S, W1) #Equals #range (BA, S, W2) } => #Top
      requires W1 ==Int W2
      [simplification]

    // Byte indexing in terms of #asWord
    rule BA [ X ] => #asWord ( #range (BA, X, 1) )
      requires X <=Int lengthBytes(BA)
      [simplification(40)]

    // Empty update has no effect
    rule BA [ START := b"" ] => BA
      requires 0 <=Int START andBool START <=Int lengthBytes(BA)
      [simplification]

    // Update passes to right operand of concat if start position is beyond the left operand
    rule ( BA1 +Bytes BA2 ) [ S := BA ] => BA1 +Bytes ( BA2 [ S -Int lengthBytes(BA1) := BA ] )
      requires lengthBytes(BA1) <=Int S
      [simplification]

    // Consecutive quasi-contiguous byte-array update
    rule BA [ S1 := BA1 ] [ S2 := BA2 ] => BA [ S1 := #range(BA1, 0, S2 -Int S1) +Bytes BA2 ]
      requires 0 <=Int S1 andBool S1 <=Int S2 andBool S2 <=Int S1 +Int lengthBytes(BA1)
      [simplification]

    // Parameter equality: byte-array update
    rule { BA1:Bytes [ S1 := BA2 ] #Equals BA3:Bytes [ S2 := BA4 ] } => #Top
      requires BA1 ==K BA3 andBool S1 ==Int S2 andBool BA2 ==K BA4
      [simplification]

    // KECCAK lemmas

    // Required for #Ceil(#buf)
    rule 0 <=Int keccak( _ )             => true [simplification]
    rule         keccak( _ ) <Int pow256 => true [simplification]

    // keccak does not equal a concrete value
    rule [keccak-eq-conc-false]: keccak(_A)  ==Int _B => false [symbolic(_A), concrete(_B), simplification]
    rule [keccak-neq-conc-true]: keccak(_A) =/=Int _B => true  [symbolic(_A), concrete(_B), simplification]

    // corollary of `keccak-eq-conc-false`
    rule [keccak-eq-conc-false-extended]:
      ( ( keccak ( _X ) +Int _A ) modInt pow256 ) ==Int _Y => false
      [simplification, symbolic(_X), concrete(_A, _Y)]

    // keccak is injective
    rule [keccak-inj]: keccak(A) ==Int keccak(B) => A ==K B [simplification]

    // keccak has no "fixpoint"
    rule [keccak-no-fix-eq-false]: #buf(32, keccak(X))  ==K X => false [simplification]
    rule [keccak-no-fix-neq-true]: #buf(32, keccak(X)) =/=K X => true  [simplification]

    // disequality of keccak under shifting
    rule ( ( keccak ( _X ) +Int A ) modInt pow256 ) ==Int keccak ( _Y ) => false
      requires 0 <Int A andBool A <Int pow256
      [simplification, symbolic(_X, _Y), concrete(A)]

    // lookup simplification lemma 
    rule M:Map [ KEY <- #lookup(M, KEY) ] => M [simplification]

    //
    // #lookup
    //
    rule #lookup(.Map, _) => 0
      [simplification]

    rule #lookup((K:Int |-> _:Int) M:Map, X:Int) => #lookup(M, X)
      requires X =/=Int K
      [simplification]

    rule #lookup(M:Map [K:Int <- _], X:Int) => #lookup(M, X)
      requires X =/=Int K
      [simplification]

    rule M:Map [ K:Int <- V:Int ] => M
      requires V ==Int #lookup(M, K)
       andBool V =/=Int 0
       [simplification]


    // Deconstruction of (maxUInt &Int ...)
    rule maxUInt8   &Int #asWord ( BA ) => #asWord ( #range(BA, 31,  1) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt16  &Int #asWord ( BA ) => #asWord ( #range(BA, 30,  2) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt24  &Int #asWord ( BA ) => #asWord ( #range(BA, 29,  3) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt32  &Int #asWord ( BA ) => #asWord ( #range(BA, 28,  4) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt40  &Int #asWord ( BA ) => #asWord ( #range(BA, 27,  5) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt48  &Int #asWord ( BA ) => #asWord ( #range(BA, 26,  6) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt56  &Int #asWord ( BA ) => #asWord ( #range(BA, 25,  7) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt64  &Int #asWord ( BA ) => #asWord ( #range(BA, 24,  8) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt72  &Int #asWord ( BA ) => #asWord ( #range(BA, 23,  9) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt80  &Int #asWord ( BA ) => #asWord ( #range(BA, 22, 10) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt88  &Int #asWord ( BA ) => #asWord ( #range(BA, 21, 11) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt96  &Int #asWord ( BA ) => #asWord ( #range(BA, 20, 12) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt104 &Int #asWord ( BA ) => #asWord ( #range(BA, 19, 13) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt112 &Int #asWord ( BA ) => #asWord ( #range(BA, 18, 14) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt120 &Int #asWord ( BA ) => #asWord ( #range(BA, 17, 15) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt128 &Int #asWord ( BA ) => #asWord ( #range(BA, 16, 16) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt136 &Int #asWord ( BA ) => #asWord ( #range(BA, 15, 17) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt144 &Int #asWord ( BA ) => #asWord ( #range(BA, 14, 18) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt152 &Int #asWord ( BA ) => #asWord ( #range(BA, 13, 19) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt160 &Int #asWord ( BA ) => #asWord ( #range(BA, 12, 20) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt168 &Int #asWord ( BA ) => #asWord ( #range(BA, 11, 21) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt176 &Int #asWord ( BA ) => #asWord ( #range(BA, 10, 22) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt184 &Int #asWord ( BA ) => #asWord ( #range(BA,  9, 23) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt192 &Int #asWord ( BA ) => #asWord ( #range(BA,  8, 24) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt200 &Int #asWord ( BA ) => #asWord ( #range(BA,  7, 25) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt208 &Int #asWord ( BA ) => #asWord ( #range(BA,  6, 26) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt216 &Int #asWord ( BA ) => #asWord ( #range(BA,  5, 27) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt224 &Int #asWord ( BA ) => #asWord ( #range(BA,  4, 28) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt232 &Int #asWord ( BA ) => #asWord ( #range(BA,  3, 29) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt240 &Int #asWord ( BA ) => #asWord ( #range(BA,  2, 30) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt248 &Int #asWord ( BA ) => #asWord ( #range(BA,  1, 31) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule maxUInt256 &Int #asWord ( BA ) => #asWord ( #range(BA,  0, 32) ) requires lengthBytes(BA) ==Int 32 [simplification]
    // Deconstruction of (notMaxUInt &Int ...)
    rule notMaxUInt8   &Int #asWord ( BA ) => #asWord ( #range(BA, 0, 31) +Bytes #buf (  1, 0 ) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule notMaxUInt16  &Int #asWord ( BA ) => #asWord ( #range(BA, 0, 30) +Bytes #buf (  2, 0 ) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule notMaxUInt32  &Int #asWord ( BA ) => #asWord ( #range(BA, 0, 28) +Bytes #buf (  4, 0 ) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule notMaxUInt64  &Int #asWord ( BA ) => #asWord ( #range(BA, 0, 24) +Bytes #buf (  8, 0 ) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule notMaxUInt96  &Int #asWord ( BA ) => #asWord ( #range(BA, 0, 20) +Bytes #buf ( 12, 0 ) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule notMaxUInt128 &Int #asWord ( BA ) => #asWord ( #range(BA, 0, 16) +Bytes #buf ( 16, 0 ) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule notMaxUInt160 &Int #asWord ( BA ) => #asWord ( #range(BA, 0, 12) +Bytes #buf ( 20, 0 ) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule notMaxUInt192 &Int #asWord ( BA ) => #asWord ( #range(BA, 0, 8)  +Bytes #buf ( 24, 0 ) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule notMaxUInt208 &Int #asWord ( BA ) => #asWord ( #range(BA, 0, 6)  +Bytes #buf ( 26, 0 ) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule notMaxUInt224 &Int #asWord ( BA ) => #asWord ( #range(BA, 0, 4)  +Bytes #buf ( 28, 0 ) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule notMaxUInt240 &Int #asWord ( BA ) => #asWord ( #range(BA, 0, 2)  +Bytes #buf ( 30, 0 ) ) requires lengthBytes(BA) ==Int 32 [simplification]
    rule notMaxUInt248 &Int #asWord ( BA ) => #asWord ( #range(BA, 0, 1)  +Bytes #buf ( 31, 0 ) ) requires lengthBytes(BA) ==Int 32 [simplification]
    // Irrelevance of lower bits
    rule notMaxUInt8   &Int (X |Int (maxUInt8   &Int _)) => notMaxUInt8   &Int X [simplification]
    rule notMaxUInt16  &Int (X |Int (maxUInt16  &Int _)) => notMaxUInt16  &Int X [simplification]
    rule notMaxUInt32  &Int (X |Int (maxUInt32  &Int _)) => notMaxUInt32  &Int X [simplification]
    rule notMaxUInt64  &Int (X |Int (maxUInt64  &Int _)) => notMaxUInt64  &Int X [simplification]
    rule notMaxUInt96  &Int (X |Int (maxUInt96  &Int _)) => notMaxUInt96  &Int X [simplification]
    rule notMaxUInt128 &Int (X |Int (maxUInt128 &Int _)) => notMaxUInt128 &Int X [simplification]
    rule notMaxUInt160 &Int (X |Int (maxUInt160 &Int _)) => notMaxUInt160 &Int X [simplification]
    rule notMaxUInt192 &Int (X |Int (maxUInt192 &Int _)) => notMaxUInt192 &Int X [simplification]
    rule notMaxUInt208 &Int (X |Int (maxUInt208 &Int _)) => notMaxUInt208 &Int X [simplification]
    rule notMaxUInt224 &Int (X |Int (maxUInt224 &Int _)) => notMaxUInt224 &Int X [simplification]
    rule notMaxUInt240 &Int (X |Int (maxUInt240 &Int _)) => notMaxUInt240 &Int X [simplification]
    rule notMaxUInt248 &Int (X |Int (maxUInt248 &Int _)) => notMaxUInt248 &Int X [simplification]

endmodule