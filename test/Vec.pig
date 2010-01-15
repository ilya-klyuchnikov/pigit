make Nat := (Mu con ['arg (Enum ['zero 'suc]) [ (con ['done]) (con ['ind1 con ['done]]) ] ] ) : Set ;
make zero := con ['zero] : Nat ;
make suc := (\ x -> con ['suc x]) : Nat -> Nat ;
make one := (suc zero) : Nat ;
make two := (suc one) : Nat ;
module Vec ;
lambda A : Set ;
make Vec : Nat -> Set ;
make VecD := (\ n -> IArg (Enum ['nil 'cons]) [ (IDone ((n : Nat) == (zero : Nat))) (IArg Nat (\ m -> IArg A (\ a -> IInd1 m (IDone ((n : Nat) == (suc m : Nat)))))) ]) : Nat -> IDesc Nat ;
lambda n ;
give IMu Nat VecD n ;
make vnil := con [ 0 , [] ] : Vec zero ;
make vcons := (\ n a as -> con [ 1 n a as , [] ]) : (n : Nat) -> A -> Vec n -> Vec (suc n) ;
root ;
make ex := Vec.vcons Nat one zero (Vec.vcons Nat zero one (Vec.vnil Nat)) : Vec.Vec Nat two ; 
module BVec  ;
lambda A : Set ;
make Vec : Nat -> Set ;
make VecD : Nat -> IDesc Nat ;
give con con [ (con con (IDone TT)) (con (\ m -> con (\ h -> IArg A (\ a -> IInd1 m (IDone TT))))) ] ;
lambda n ;
give IMu Nat VecD n ;
make vnil := con [] : Vec zero ;
make vcons := (\ n a as -> con [ a as , [] ]) : (n : Nat) -> A -> Vec n -> Vec (suc n) ;
root ;
make ex2 := BVec.vcons Nat one zero (BVec.vcons Nat zero one (BVec.vnil Nat)) : BVec.Vec Nat two  


