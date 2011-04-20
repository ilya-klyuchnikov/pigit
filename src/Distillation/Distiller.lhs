\section{The distiller}
\label{sec:Distillation.Distiller}

%if False

> {-# OPTIONS_GHC -F -pgmF she #-}
> {-# LANGUAGE GADTs, TypeOperators, PatternGuards #-}

> module Distillation.Distiller where

> import Data.Maybe

> import Evidences.Tm
> import Evidences.NameSupply
> import Evidences.TypeCheckRules

> import DisplayLang.DisplayTm
> import DisplayLang.Name

> import ProofState.Structure.Developments
> import ProofState.Edition.ProofState
> import ProofState.Edition.GetSet

> import Kit.BwdFwd
> import Kit.NatFinVec
> import Kit.MissingLibrary 

%endif


> distillPS :: (EXP :>: EXP) -> ProofState DInTmRN
> distillPS (ty :>: tm) = do
>     lev <- getDevLev
>     return $ distill (ev ty :>: ev tm) lev


> distill :: VAL :>: VAL -> Int -> DInTmRN
> distill (ty :>: L g n b) l = case fromJust $ lambdable ty of
>   (k, s, t) -> DLAV n $ distill (ev (t (P (l, n, s) :$ B0)) 
>                                   :>: ((g <:< (P (l, n, s) :$ B0)) // b)) (l + 1)
> distill (ty :>: LK b) l = case fromJust $ lambdable ty of
>   (_, s, t) -> DLK $ 
>     distill (ev (t (P (l,"s",s) :$ B0)) :>: ev b) (l+1)

> distill (ty :>: h :$ as) l =
>     let (dh, ty, ss) = distillHead h
>         das = distillSpine (ev ty :>: (h :$ B0, ss ++ trail as)) l
>     in DN (dh ::$ das)

> distill ((tyc :- tyas) :>: (c :- as)) l = case canTy ((tyc , tyas) :>: c) of
>   Nothing -> error "Tin thadger wasp unit"
>   Just tel -> DC c $ distillCan (tel :>: as) l

> distill tt _ = error $ "Distiller can't cope with " ++ show tt

> distillCan :: (VAL :>: [EXP]) -> Int -> [DInTmRN]
> distillCan (ONE :>: []) l = []
> distillCan (SIGMA s t :>: a : as) l = 
>   distill (ev s :>: ev a) l : distillCan (ev (t $$ A a) :>: as) l


> distillHead :: Tm {p, s, Z} -> (DHead RelName, TY, [Elim EXP])
> distillHead (P (l', n, s)) = (DP [(n,Abs l')], s, [])
> distillHead (D def ss op)  = (DP (nameToRelName (defName def)),
>                                  defTy def,
>                                  map A (rewindStk ss []))
> distillHead t = error $ "distillHead: barf " ++ show t


> distillSpine :: VAL :>: (VAL, [Elim (Tm {Body, Exp, Z})]) -> Int -> [Elim DInTmRN]
> distillSpine (_ :>: (_, [])) _ = []
> distillSpine (ty :>: (h :$ az, A a : as)) l = case fromJust $ lambdable ty of 
>   (k, s, t) ->     A (distill (ev s :>: (ev a)) l) 
>                 :  distillSpine (ev (t a) :>: (h :$ (az :< A a), as)) l
> distillSpine (ty :>: (h :$ az , Hd : as)) l = case fromJust $ projable ty of
>   (s, t) -> Hd : distillSpine (ev s :>: (h :$ (az :< Hd) , as)) l
> distillSpine (ty :>: (h :$ az , Tl : as)) l = case fromJust $ projable ty of
>   (s, t) -> Tl : distillSpine (ev (t (h :$ (az :< Hd))) :>: (h :$ (az :< Tl) , as)) l
> distillSpine _ _  = error "Deep!"
