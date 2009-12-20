> module  Tests.DevLoad where

> import Control.Monad.State
> import Data.List

> import BwdFwd
> import DevLoad
> import Elaborator
> import Parsley
> import PrettyPrint
> import Lexer
> import TmParse
> import Tm

> fromRight :: Either a b -> b
> fromRight (Left x) = error "fromRight: haha!"
> fromRight (Right x) = x



> testChunkTerms =  [ "( X : * ) -> X"
>                   , "( X : * ) ( t : X -> X ) ( y : X ) -> t y"
>                   , "( X : * ) ( Y : * )" ++
>                     "( t : X -> Y -> X )" ++
>                     "( y : X ) ( z : Y )  -> t y z"
>                   ]

> testChunk = 
>     Prelude.sequence_ $
>     map (\tm -> 
>         let Right tm' = parse tokenize tm
>             Right tm2 = parse (termParse B0) tm'
>             r = evalStateT (introTm tm2) emptyContext
>         in do
>           putStrLn $ "\n" ++ show tm 
>           case r of
>            Left ss -> do
>                 putStrLn $ "Error: " ++ intercalate "\n" ss
>            Right x@(hs, t) -> do
>                 putStrLn "Internal hyp.: "
>                 sequence_ $ map (putStrLn . show) hs
>                 putStrLn "Goal:"
>                 putStrLn $ show t)
>     testChunkTerms
>     where introTm tm = do
>               make ("" :<: tm)
>               goIn
>               r <- chunkGoal 
>               return r

> testCheckElimTerms = [ ("(N : *)(x : N)(P : N -> *) -> P x", [(),()])
>                      , ("(N : *)(Z : *)(x : N)(y : Z)(P : N -> Z -> *) -> P x y", [(),(),(),()])
>                      , ("(N : *)(x : N)(z : N)(P : N -> *) (pz : P z) -> P x", [(),(),()])
>                      ]


> testCheckElim = 
>     Prelude.sequence_ $
>     map (\(ty, ctxt) -> 
>         let Right ty' = parse (termParse B0) $ fromRight $ parse tokenize ty
>             e = [("eHa",1001)] := (DECL :<: evTm ty')
>             name = [("e",1000)] := (DEFN (N (P e)) :<: evTm ty')
>             r = evalStateT (checkElim ctxt name) emptyContext
>         in do
>           putStrLn $ "\n" ++ show ty 
>           case r of
>            Left ss -> do
>                 putStrLn $ "Error: " ++ intercalate "\n" ss
>            Right x@(motive, methods, targets) -> do
>                 putStrLn "Motive: "
>                 putStrLn $ show motive
>                 putStrLn "Methods:"
>                 sequence_ $ map (putStrLn . show) methods
>                 putStrLn "Args:"
>                 sequence_ $ map (putStrLn . show) targets)
>     testCheckElimTerms

> eliminators = [ "switchOp(e, p, b, x)",
>                 "splitOp(a, b, c, f, t)",
>                 "nEOp(p, t)",
>                 "(d, bp, v, p)" ]

> testCheckElim2 = 
>     Prelude.sequence_ $
>     map (\tm -> 
>         let Right tm' = parse (termParse B0) $ fromRight $ parse tokenize tm
>             r = evalStateT (checkElimWrap tm') emptyContext
>         in do
>           putStrLn $ "\n" ++ show tm
>           case r of
>            Left ss -> do
>                 putStrLn $ "Error: " ++ intercalate "\n" ss
>            Right x@(motive, methods, targets) -> do
>                 putStrLn "Motive: "
>                 putStrLn $ show motive
>                 putStrLn "Methods:"
>                 sequence_ $ map (putStrLn . show) methods
>                 putStrLn "Args:"
>                 sequence_ $ map (putStrLn . show) targets)
>     testCheckElimTerms
>         where checkElimWrap tm = do
>                 


These are not quite motive signature, but that's fine for this test:

> testCheckMotiveTerms = [ "(N : *)(n : N) -> *"
>                        , "(N : *)(n : N)(m : N) -> *"
>                        , "(N : *)(Z : *)(n : N)(z : Z) -> *"
>                        ]

> testCheckMotive =
>     Prelude.sequence_ $
>     map (\ty -> 
>         let Right ty' = parse (termParse B0) $ fromRight $ parse tokenize ty
>             name = [("e",1000)] := (DECL :<: evTm ty')
>             r = evalStateT (checkMotive name) emptyContext
>         in do
>           putStrLn $ "\n" ++ show ty 
>           case r of
>            Left ss -> do
>                 putStrLn $ "Error: " ++ intercalate "\n" ss
>            Right x@(hyps) -> do
>                 putStrLn "Hypotheses:"
>                 sequence_ $ map (putStrLn . show) hyps)
>     testCheckMotiveTerms

> testMkMotiveTerms = [ ("(N : *) -> N",
>                        "(N : *)(P : N -> *)(x : N) -> P x")
>                     ]

> {-
>                     , ("",
>                        "(N : *)(Z : *)(x : N)(y : Z)(P : N -> Z -> *) -> P x y")
>                     , ("",
>                        "(N : *)(x : N)(z : N)(P : N -> *) (pz : P z) -> P x")
> -}

> testMkMotive =
>     Prelude.sequence_ $
>     map (\(goal,eTy) -> 
>         let Right goal' = parse (termParse B0) $ fromRight $ parse tokenize goal
>             Right eTy' = parse (termParse B0) $ fromRight $ parse tokenize eTy
>             e = [("eHa",1001)] := (DECL :<: evTm eTy')
>             name = [("e",1000)] := (DEFN (N (P e)) :<: evTm eTy')
>             r = evalStateT (test goal' name) emptyContext
>         in do
>           putStrLn $ "\n" ++ show goal
>           case r of
>            Left ss -> do
>                 putStrLn $ "Error: " ++ intercalate "\n" ss
>            Right x -> do
>                 putStrLn $ show x)
>     testMkMotiveTerms
>         where test tm e = do
>                           make ("" :<: tm)
>                           goIn
>                           (internHyps, goal) <- chunkGoal
>                           (motive, methods, motiveArgs) <- checkElim internHyps e
>                           motiveHyps <- checkMotive motive
>                           checkMethods methods
>                           motive <- mkMotive motive motiveHyps motiveArgs internHyps goal
>                           return motive