make nat := (Mu con ['arg (Enum ['zero 'suc]) [ (con ['done]) (con ['ind1 con ['
done]]) ] ] ) : Set ;
make zero := con ['zero] : nat ;
make suc := (\ x -> con ['suc x]) : nat -> nat ;
make one := (suc zero) : nat ;
make two := (suc one) : nat ;
make plus : nat -> nat -> nat ;
give con ? ;
give con ? ;
give [? ?] ;
lambda r ;
lambda r ;
lambda y ;
give y ;
lambda r ;
give con ? ;
lambda h ;
lambda r ;
lambda y ;
give suc (h y) ;
root ;
make x := (plus two two) : nat