> {-# LANGUAGE PatternGuards #-}

> module SourceLang.Lexer where

> import Prelude hiding (foldl)
> import Data.List hiding (foldl)
> import Data.Foldable hiding (elem)
> import Control.Applicative
> import Data.Monoid

> import Kit.MissingLibrary
> import Kit.BwdFwd

> data STok = Spc Int | Sym String | Open BType | Close BType
>   deriving (Show, Eq)

> type BType = (Bracket, Maybe String)
> data Bracket = Round | Square | Curly deriving (Show, Eq)

> closes :: BType -> BType -> Bool
> closes (b, Nothing) (b', Nothing) = b == b'
> closes (b, Just s) (b', Just "") = b == b'
> closes (b, Just s) (b', Just s') = b == b' && s == s'
> closes _ _ = False

> openers :: [(Char, Bracket)]
> openers = [('(', Round), ('[', Square), ('{', Curly)]

> closers :: [(Char, Bracket)]
> closers = [(')', Round), (']', Square), ('}', Curly)]

> stok :: STok -> String
> stok (Spc i)          = replicate i ' '
> stok (Sym s)          = s
> stok (Open (b, ms))   = [op] ++ maybe "" (++ "|") ms where
>   Just op = lookup b (map swap openers)
> stok (Close (b, ms))  = maybe "" (++ "|") ms ++ [cl] where
>   Just cl = lookup b (map swap closers)

> soloists :: [Char]
> soloists = "\n\r\t,;!."

> special :: [Char]
> special = " |" ++ soloists ++ map fst openers ++ map fst closers

> boring :: Char -> Bool
> boring c = not (elem c special)

> slex1 :: Char -> String -> (STok, String)
> slex1 c s =
>   case (elem c soloists, lookup c openers, lookup c closers) of
>     (True, _, _) -> (Sym [c], s)
>     (_, Just b, _)
>       | (t, '|' : u) <- span boring s -> (Open (b, Just t), u)
>       | otherwise -> (Open (b, Nothing), s)
>     (_, _, Just b) -> (Close (b, Nothing), s)
>     _ | c == ' ' -> let (t, u) = span (== ' ') s in (Spc (1 + length t), u)
>     _ | c == '|' , (t, d : u) <- span boring s , Just b <- lookup d closers
>       -> (Close (b, Just t), u)
>     _ | c == '|' -> (Sym "|", s)
>     _ -> let (t, u) = span boring s in (Sym (c : t), u)

> slex :: String -> [STok]
> slex []       = []
> slex (c : s)  = let (t , s') = slex1 c s in t : slex s'

> type Doc   = Fwd Line
> type Line  = Fwd Elt
> data Elt
>   =  E STok
>   |  M Movement
>   |  B BType Doc (Either HowOpen BType) deriving Show

> data Movement
>   = MOpen | MClose | MSOL | MEOL | MBang | MGnab deriving (Show, Eq)
> data HowOpen   = Banged | Dangling deriving (Show, Eq)

> type GStk    =  (Bwd GLayer, (Bwd Line, CLine))
> type CLine   = (Behind, Bwd Elt, (), Ahead)
> type Behind  = Bwd (Bwd Elt, GSus)
> type Ahead   = Fwd (GSus, Bwd Elt)
> type GLayer  =  (Bwd Line, (Behind, Bwd Elt, (BType, ()), Bwd Elt, Ahead))

> data GSus = BType :<> (Bwd Line, (Bwd Elt, (), Ahead))

> gEOF :: GStk -> Doc
> gEOF (yz, x) = yEOF yz (lEOF x) where
>   yEOF = ala Endo foldMap $ \ (lz, (ebz, ez, (b, ()), ez', bes)) ls -> lz <>>
>     behind ebz (ez <>> B b ls (Left Dangling) :> ez' <>> ahead bes) :> F0

> lEOF :: (Bwd Line, CLine) -> Doc
> lEOF (lz, (ebz, ez, (), bes)) = lz <>> behind ebz (ez <>> ahead bes) :> F0

> behind :: Behind -> Fwd Elt -> Fwd Elt
> behind = ala Endo foldMap $ \ (ez, g) es -> ez <>> cSus g :> es

> ahead :: Ahead -> Fwd Elt
> ahead = foldMap $ \ (g, ez) -> cSus g :> ez <>> F0

> cSus :: GSus -> Elt
> cSus (b :<> (lz, (ez, (), bes)))
>   = B b (lz <>> (ez <>> ahead bes) :> F0) (Left Banged)

> gTok :: GStk -> STok -> GStk
> gTok (yz, (lz, (ebz, ez, (), bes))) (Open b)
>   = (yz :< (lz , (ebz, ez :< M MOpen, (b, ()), B0, bes)),
>      (B0, (B0, B0 :< M MSOL, (), F0)))
> gTok (yz :< (lz', (ebz', ez', (b', ()), ez'', bes')), x) (Close b)
>   | closes b' b
>   = (yz, (lz',
>     (ebz', ez' :< B b' (lEOF x) (Right b) <|> (ez'' :< M MClose), (), bes')))
> gTok (yz, (lz, (B0, ez, (), F0))) (Sym "\n")
>   = (yz, (lz :< (ez <>> M MEOL :> F0), (B0, B0 :< M MSOL, (), F0)))
> gTok (yz, (lz, (ebz, ez, (), bes))) (Sym "\n")
>   = (yz, (lz, gNL (ebz, ez :< M MEOL, (), bes))) where
>       gNL (eb :< (ez, b), ez', (), bes) = gNL (eb, ez, (),  (b, ez') :> bes)
>       gNL (B0, ez, (), bes) = (B0, ez :< M MSOL, (), bes)
> gTok (yz, (lz, (ebz, ez, (), (b :<> (lz', (ez', (), bes')), ez'') :> bes)))
>   (Sym "!")
>   =  (yz :< (lz, (ebz, ez :< M MBang, (b, ()), ez'', bes)),
>        (lz', (B0, ez':< M MSOL, (), bes')))
> gTok (yz :< (lz, (ebz, ez, (b, ()), ez'', bes)), (lz', (ebz', ez', (), F0)))
>   (Sym "!")
>   =  (yz, (lz,
>        (ebz :< (ez, b :<> (lz', gBang (ebz', ez' :< M MGnab, (), F0))),
>          ez'', (), bes))) where
>     gBang (ebz :< (ez', b), ez, (), bes)
>       = gBang (ebz, ez', (), (b, ez) :> bes)
>     gBang (B0, ez, (), bes) = (ez, (), bes)
> gTok (yz, (lz, (ebz, ez, (), bes))) t = (yz, (lz, (ebz, ez :< E t, (), bes)))

> doc :: [STok] -> Doc
> doc = go (B0, (B0, (B0, B0 :< M MSOL, (), F0))) where
>   go g [] = gEOF g
>   go g (t : ts) = mo (gTok g t) ts
>   mo (B0, (lz, x)) ts = lz <>> go (B0, (B0, x)) ts
>   mo g ts = go g ts

> dent :: Line -> Int
> dent = go maxBound where
>   go u (M MSOL :> e :> es) = case e of
>     E (Spc i) | i < u  -> go i es
>     M _                -> go u es
>     _                  -> 0
>   go u (_ :> es)            = go u es
>   go u F0                 = u
