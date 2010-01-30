\section{Tm}

%if False

> {-# OPTIONS_GHC -F -pgmF she #-}
> {-# LANGUAGE TypeOperators, GADTs, KindSignatures, RankNTypes,
>     TypeSynonymInstances, FlexibleInstances, FlexibleContexts, ScopedTypeVariables #-}

> module Evidences.Tm where

> import Control.Applicative
> import Control.Monad.Error
> import Control.Monad.Identity
> import qualified Data.Monoid as M
> import Data.Foldable hiding (foldl)
> import Data.List
> import Data.Traversable

> import Kit.MissingLibrary
> import Kit.BwdFwd

> import Features.Features

> import NameSupply.NameSupply

%endif

%format :$ = ":\!\!\$"
%format :@ = ":\!\!@"
%format :? = ":\!\in"
%format Set = "\star"
%format Pi = "\Pi"
%format :. = "\bullet"
%format :>: = "\ni"
%format :<: = "\in"
%format :=>: = "\Downarrow"

\subsection{Syntax of Terms and Values}


We distinguish |In|Terms (into which we push types) and |Ex|Terms
(from which we pull types).

> data Dir    = In | Ex

This is the by-now traditional bidirectional
type-checking~\cite{turner:bidirectional_tc} story: there are
\emph{checkable} terms that are checked against given types, and there
are \emph{inferable} terms which type are inferred relatively to a
typing context. We push types in checkable terms, pull types from
inferable terms.

We also distinguish the representations of |TT| terms and |VV| values.


> data Phase  = TT | VV

And, of course, we're polymorphic in the representation of free
variables, like your mother always told you. This gives the following
signature for a term:

> data Tm :: {Dir, Phase} -> * -> * where

We can push types into:
\begin{itemize}
\item lambda terms;
\item canonical terms; and
\item inferred terms.
\end{itemize}

>   L     :: Scope p x             -> Tm {In, p}   x -- \(\lambda\)
>   C     :: Can (Tm {In, p} x)    -> Tm {In, p}   x -- canonical
>   N     :: Tm {Ex, p} x          -> Tm {In, p}   x -- |Ex| to |In|

And we can infer types from:
\begin{itemize}
\item parameters, because they carry their types;
\item variables, by reading the context;
\item fully applied operators, by |opTy| defined below;
\item elimination, by the type of the eliminator; and
\item type ascription on a checkable term, by the ascripted type.
\end{itemize}

>   P     :: x                                    -> Tm {Ex, p}   x -- parameter
>   V     :: Int                                  -> Tm {Ex, TT}  x -- variable
>   (:@)  :: Op -> [Tm {In, p} x]                 -> Tm {Ex, p}   x -- fully applied op
>   (:$)  :: Tm {Ex, p} x -> Elim (Tm {In, p} x)  -> Tm {Ex, p}   x -- elim
>   (:?)  :: Tm {In, TT} x -> Tm {In, TT} x       -> Tm {Ex, TT}  x -- typing

To put some flesh on these bones, we define and use the |Scope|,
|Can|, |Op|, and |Elim| data-types. Their role is described
below. Before that, let us point out an important invariant. Non
implementers are advised to skip the following.

\begin{danger}[Neutral terms and Operators]

In the world of values, ie. |Tm {In, VV} p|, the neutral terms are
exactly the |N t| terms. Enforcing this invariant requires some
caution in the way we deal with operators and how we turn them into
values, so this statement relies on the hypothesis that the evaluation
of operators is correct: it is not enforced by Haskell type-system.

To prove that statement, we first show that any |Tm {In, VV} p| which
is not a |N t| is not a neutral term. This obvious as we are left with
lambda and canonicals, which cannot be stuck. Then, we have to prove
that a |N t| in |Tm {In, VV} p| form is a stuck term. We do so by case
analysis on the term |t| inside the |N|:
\begin{itemize}

\item Typing and variable will not let you get a value, so a neutral
value is not one of those.

\item This is also easy if you have a parameter: it is stuck waiting
for its definition.

\item An eliminator in value form consists in an elimination applied
to a value in |Ex|, which is -- by induction -- a neutral term. Hence,
the eliminator is stuck too.

\item The case for fully applied operator is more problematic: we need
one of the arguments to be a |N t|, and to be used by |Op|. This way,
the operation is indeed a neutral term. We can hardly enforce this
constraint in Haskell type system, so we have to deal with this
approximation.

\end{itemize}

As a consequence, fully applied operators call for some care. If you
are to explicitly write a |:@| term wrapped inside a |N|, you must be
sure that the operator is indeed applied to a stuck term \emph{which
is used} by the operator. During evaluation, for example, we have been
careful in returning a neutral operator if and only if the operator
was consuming a stuck term. As a corollary, if the operator can be
fully computed, then it \emph{must} be so. 

More tricky but for the same reason: when \emph{implementing} term
builders (not when using them), we are indeed making terms,
potentially involving operators. Again, we must be careful of not
building a stuck operator for no good reason.

\end{danger}


\subsubsection{Scopes}

A |Scope| represents bodies of binders, but the representation differs
with phase. In \emph{terms}, |x :. t| is a \emph{binder}: the |t| is a
de Bruijn term with a new bound variable 0, and the old ones
incremented. The |x| is just advice for display-name selection.

In values, |HF x body| is an higher-order binding. As previously, |x|
is just a name advice. On the other hand, |body| is a stored function
awaiting a value, the bound variable, to compute a \emph{fully
evaluated} value. The substitution is therefore partially inherited
from Haskell. 

\begin{danger}
It is important to ensure that |body| computes to a
fully evaluated value, otherwise say "good bye" to strong
normalisation.
\end{danger}

In both cases, we represent constant functions with |K t|, equivalent
of |\ _ -> t |.

> data Scope :: {Phase} -> * -> * where
>   (:.)  :: String -> Tm {In, TT} x           -> Scope {TT} x  -- binding
>   HF    :: String -> (VAL -> Tm {In, VV} x)  -> Scope {VV} x   
>   K     :: Tm {In, p} x                      -> Scope p x     -- constant



\subsubsection{Canonical objects}

The |Can| functor explains how canonical objects are constructed from
sub-objects (terms or values, as appropriate). Lambda is not included
here: morally, it belongs; practically, adapting |Can| to support
binding complicates the definition. Note the presence of the @import@
She-ism: this means that canonical constructors can be later plugged
in using a She aspect.

> data Can :: * -> * where
>   Set   :: Can t                                   -- set of sets
>   Pi    :: t -> t -> Can t                         -- functions
>   Con   :: t -> Can t                              -- packing
>   import <- CanConstructors
>   deriving (Show, Eq)


The |Con| object is used and abused in many circumstances. However,
all ilts usages share the same pattern: |Con| is used wheneveer we
need to ''pack'' an object |t| into something else, to avoid
ambiguities. For example, we use |Con| in the following case:

\begin{prooftree}
\AxiomC{|desc x (Mu x) :>: y|}
\UnaryInfC{|Mu x :>: Con y|}
\end{prooftree}


\subsubsection{Eliminators}

The |Elim| functor explains how eliminators are constructed from their
sub-objects. It's a sort of logarithm~\cite{hancock:amen}. Projective
eliminators for types with \(\eta\)-laws go here.

> data Elim :: * -> * where
>   A     :: t -> Elim t                             -- application
>   Out   :: Elim t                                  -- unpacks Con
>   import <- ElimConstructors
>   deriving (Show, Eq)

Just as |Con| was packing things up, we define here |Out| to unpack
them.

%format $:$ = "\mathbin{\$\!:\!\$}"

Eliminators can be chained up in a \emph{spine}. A |Spine| is a list
of eliminators for terms, typically representing a list of arguments
that can be applied to a term with the |$:$| operator.

> type Spine p x = [Elim (Tm {In, p} x)]
>
> ($:$) :: Tm {Ex, p} x -> Spine p x -> Tm {Ex, p} x
> ($:$) = foldl (:$)


\subsubsection{Operators}

Other computation is performed by a fixed repertoire of operators. To
construct an operator, you need a name (for scope resolution and
printing), an arity (so the resolver can manage fully applied usage),
a typing telescope, a computation strategy, and a simplification
method.

> data Op = Op
>   { opName  :: String
>   , opArity :: Int
>   , opTyTel :: TEL TY
>   , opSimp  :: Alternative m => [VAL] -> NameSupply -> m NEU
>   , opRun   :: [VAL] -> Either NEU VAL
>   }

A key component of the definition of operators is the typing
telescope. Hence, we first describe the implementation of the
telescope.

\paragraph{Telescope}

A telescope |TEL| represents the standard notion of telescope in Type
Theory. This consists in a sequence of types which definition might
rely on any term inhabiting the previous types. A telescope is
terminated by a |Target|.

> data TEL x  = Target x
>             | (String :<: TY) :-: (VAL -> TEL x)
> infix 3 :-:

\question{Couldn't we derive |TEL| in |Foldable| or equivalent and get
|telCheck| as a |fold|?}

Easily, a telescope can be turned into a sequence of $\Pi$ types:

> pity :: TEL TY -> TY
> pity (Target t)          = t
> pity (x :<: s :-: t)  = PI s (L (HF x $ pity . t))

> laty :: TEL (TY :>: VAL) -> (TY :>: VAL)
> laty (Target t)        = t
> laty (x :<: s :-: t)   =
>   PI s (body (\(ty :>: _) -> ty)) :>: body (\(_ :>: val) -> val)
>     where body f = L (HF x $ f . laty . t)


And, similarly, as a sequence of $\forall$s:

> allty :: TEL VAL -> VAL
> allty (Target t)          = t
> allty (x :<: s :-: t)  = ALL s (L (HF x $ allty . t))

The interpretation of the telescope is carried by |telCheck|. On the
model of |opTy| defined below, this interpretation uses a generic
checker-evaluator |chev|. Based on this chev, it simply goes over the
telescope, checking and evaluating as it moves further.

> telCheck ::  (Alternative m, MonadError [String] m) =>
>              (TY :>: t -> m (s :=>: VAL)) -> 
>              (TEL x :>: [t]) -> m ([s :=>: VAL] , x) 
> telCheck chev (Target x :>: []) = return ([] , x)
> telCheck chev ((_ :<: sS :-: tT) :>: (s : t)) = do
>     ssv@(s :=>: sv) <- chev (sS :>: s) 
>     (svs , x) <- telCheck chev ((tT sv) :>: t)
>     return (ssv : svs , x) 
> telCheck _ _ = throwError' "telCheck: opTy mismatch"


\paragraph{Type-checking operators}

The |opTy| function explains how to interpret the telescope |opTyTel|:
it labels the operator's arguments with the types they must have and
delivers the type of the whole application. To do that, one must be
able to evaluate arguments. It is vital to type-check the sub-terms
(left to right) before trusting the type at the end. This corresponds
to the following type:

< opTy :: forall t. (t -> VAL) -> [t] -> Maybe ([TY :>: t] , TY)
< opTy ev args = (...)

Where we are provided an evaluator |ev| and the list of arguments,
which length should be the arity of the operator. If the type of the
arguments is correct, we return them labelled with their type and the
type of the result.

However, we had to generalize it. Following the evolution of |canTy|
in Section~\ref{sec:canTy}, we have adopted the following scheme:

< opTy    :: (Alternative m, MonadError StackError m) =>
<            (TY :>: t -> m (s :=>: VAL)) -> 
<            [t] -> 
<            m ([s :=>: VAL] , TY)

First, being kind of |MonadPlus| allows a seamless integration in the
world of things that might fail. Second, we have extended the
evaluation function to perform type-checking at the same time. We also
liberalize the return type to |s|, to give more freedom in the choice
of the checker-evaluator. This change impacts on |exQuote|, |infer|,
and |useOp|. If this definition is not clear now, it should become
clear after the definition of |canTy| in Section~\ref{sec:canTy}.

> opTy ::  (Alternative m, MonadError StackError m) =>
>          Op -> (TY :>: t -> m (s :=>: VAL)) -> [t] ->
>          m ([s :=>: VAL], TY)
> opTy op chev ss
>   | length ss == opArity op = telCheck chev (opTyTel op :>: ss)
> opTy op _ _ = throwError ["operator arity error: " ++ opName op]


\paragraph{Running the operator}

The |opRun| argument implements the computational behavior: given
suitable arguments, we should receive a value, or failing that, the
neutral term to blame for the failure of computation. For example, if
|append| were an operator, it would compute if the first list is nil
or cons, but complain about the first list if it is neutral.






\subsection{Useful Abbreviations}

We have some pattern synonyms for common, er, patterns.

> pattern SET       = C Set                -- set of sets
> pattern ARR s t   = C (Pi s (L (K t)))   -- simple arrow
> pattern PI s t    = C (Pi s t)           -- dependent functions
> pattern CON t     = C (Con t)
> pattern NV n      = N (V n)
> pattern NP n      = N (P n)
> pattern LAV x t   = L (x :. t)
> pattern PIV x s t = PI s (LAV x t)
> pattern LK t      = L (K t)
> import <- CanPats

We have some type synonyms for commonly occurring instances of |Tm|.

> type InTm   = Tm {In, TT}
> type ExTm   = Tm {Ex, TT}
> type INTM   = InTm REF
> type EXTM   = ExTm REF
> type VAL    = Tm {In, VV} REF
> type TY     = VAL
> type NEU    = Tm {Ex, VV} REF
> type ENV    = Bwd VAL

We have special pairs for types going into and coming out of
stuff. That is, we write |typ :>: thing| to say that |typ| accepts the
term |thing| -- we can push the |typ| in the |thing|. Conversely, we
write |thing :<: typ| to say that |thing| is of infered type |typ| --
we can pull the type |typ| out of the |thing|. Therefore, we can read
|:>:| as ``accepts'' and |:<:| as ``has inferred type''.

> data ty :>: tm = ty :>: tm  deriving (Show,Eq)
> infix 4 :>:
> data tm :<: ty = tm :<: ty  deriving (Show,Eq)
> infix 4 :<:

As we are discussing syntactic sugar, let me introduce the ``reduces
to'' symbol:

> data t :=>: v = t :=>: v deriving (Show, Eq)
> infix 5 :=>:

With the associated projections:

> valueOf :: (t :=>: v) -> v
> valueOf (_ :=>: v) = v
>
> termOf :: (t :=>: v) -> t
> termOf (t :=>: _) = t

Intuitively, |t :=>: v| can be read as ``the term |t| reduces to the
value |v|''.


\subsection{Syntactic Equality}
\label{sec:syntactic_equality}


In the following, we implement definitional equality on terms. In this
case, it's mainly structural.

> instance Eq x => Eq (Tm {d, TT} x) where

First, a bunch of straightforward structural inductions:

>   L s0          == L s1          = s0 == s1
>   C c0          == C c1          = c0 == c1
>   N n0          == N n1          = n0 == n1
>   P x0          == P x1          = x0 == x1
>   V i0          == V i1          = i0 == i1
>   (t0 :$ e0)    == (t1 :$ e1)    = t0 == t1 && e0 == e1
>   (op0 :@ vs0)  == (op1 :@ vs1)  = op0 == op1 && vs0 == vs1

Then, equality in a set means having equal canonical element:

>   (t0 :? _)     == (t1 :? _)     = t0 == t1

Otherwise, they are clearly not equal:

>   _             == _             = False


For scopes, we should only ever see full binders, and we compare them
ignoring name advice: de Bruijn indexing gets rid of \(\alpha\)-conversion
issues.

> instance Eq x => Eq (Scope {TT} x) where
>   (_ :. t0)  == (_ :. t1)  = t0 == t1
>   K t0       == _          = error "unexpected K"
>   _          == K t1       = error "unexpected K"
>   _          == _          = False

Operators are compared by name!

> instance Eq Op where
>   op0 == op1 = opName op0 == opName op1

We provide a smashing operator, for things whose precise values are
irrelevant. We intend this for proofs, but there may be other things
(like name advice) for which we should use it.

> data Irr x = Irr x deriving Show
> instance Eq (Irr x) where
>   _ == _ = True

In this section, we have defined the syntactic equality on terms. The
general definition of syntactic equality remains to be done. It is
the subject of Section~\ref{sec:rules}: there, we rely on
\emph{quotation} to turn values into terms. Once turned into terms, 
we fall back to the equality defined above.


\subsection{References}
\label{sec:references}

References are the key way we represent free variables, declared,
defined, and deluded. References carry not only names, but types and
values, and are shared.

> data REF = (:=) { refName :: Name, refBody :: (RKind :<: TY)}
> infix 2 :=

References are compared by name, as the |NameSupply| guarantees a
source of unique, fresh names. Note however that |REF|s being shared,
one could thing of using physical pointer equality to implement this
test (!).

> instance Eq REF where
>   (x := _) == (y := _) = x == y

%if false 

> instance Show REF where
>   show (name := kt) = intercalate "." (map (\(x,n) -> x ++ "_" ++ show n) name) ++ " := " ++ show kt

%endif

A |REF| can be of one of those kinds:
\begin{itemize}
\item |DECL|: used a binder, a declaration
\item |DEFN|: computed, a definition
\item |HOLE|: not computed yet, a definition-to-be
\item |FAKE|: a hysterectomized definition, used to make labels
\end{itemize}

> data RKind
>   =  DECL
>   |  DEFN VAL
>   |  HOLE
>   |  FAKE
>   deriving Show

We can already define some handy operators on |REF|s. First, we can
turn a |REF| to a |VAL|ue by using |pval|. If the reference is already
defined, then we pick the computed value. Otherwise, it is dealt as a
neutral parameter.

> pval :: REF -> VAL
> pval (_ := DEFN v :<: _)  = v
> pval r                    = NP r

Second, we can extract the type of a reference thanks to the following
code:

> pty :: REF -> VAL
> pty (_ := _ :<: ty) = ty


\subsection{Labels}

Labels are tucked into strange places, in order to record the
high-level presentation of low-level stuff.  A typical label is the
neutral application of a fake reference --- a definition whose
hysterectomy stops it computing.

> data Labelled f t
>   = Maybe t :?=: f t
>   deriving (Show)

For example, labels are used in the presentation of the |Enum|
(Section~\ref{sec:enum}) and |Desc| (Section~\ref{sec:desc})
data-types. These data-types are themselves implemented as fix-points
of non human-readable descriptions, hence we hide the details behind a
label. The curious reader is referred to their implementation. Any
body in his right mind would ignore labels for now.

Label equality is sound but not complete for equality of what has been
labelled.

> instance (Traversable f, HalfZip f, Eq t) => Eq (Labelled f t) where
>   (Just a  :?=: _)  ==  (Just b  :?=: _) | a == b  = True
>   (_       :?=: s)  ==  (_       :?=: t)           = case halfZip s t of
>     Nothing -> False 
>     Just x -> M.getAll (crush (M.All . uncurry (==)) x) 

If we have a labelled |INTM|, we can try to extract the name from the label.

> extractLabelName :: Labelled f INTM -> Maybe Name
> extractLabelName (Just (N l) :?=: _) = extractName l
>   where
>     extractName :: EXTM -> Maybe Name
>     extractName (P ref)    = Just (refName ref)
>     extractName (tm :$ _)  = extractName tm
>     extractName _          = Nothing
> extractLabelName _ = Nothing

We can also throw away a label, should we want to.

> dropLabel :: Labelled f t -> Labelled f t
> dropLabel (_ :?=: a) = (Nothing :?=: a)


\subsection{Term Construction}

> idTM :: String -> INTM
> idTM x   = L (x :. (N (V 0)))

> idVAL :: String -> VAL
> idVAL x  = L (HF x id)

> ($#) :: Int -> [Int] -> InTm x
> f $# xs = N (foldl (\ g x -> g :$ A (NV x)) (V f) xs)

> ($##) :: Tm {Ex, p} x -> [Tm {In, p} x] -> Tm {Ex, p} x
> f $## xs = f $:$ (map A xs)

> fortran :: Tm {In, p} x -> String
> fortran (L (x :. _))   | not (null x) = x
> fortran (L (HF x  _))  | not (null x) = x
> fortran _ = "x"


%if False

> instance Traversable Can where
>   traverse f Set       = (|Set|)
>   traverse f (Pi s t)  = (|Pi (f s) (f t)|)
>   traverse f (Con t)   = (|Con (f t)|)
>   import <- CanTraverse

> instance HalfZip Can where
>    halfZip Set        Set        = Just Set
>    halfZip (Pi s1 t1) (Pi s2 t2) = Just $ Pi (s1,s2) (t1,t2)
>    halfZip (Con t1)   (Con t2)   = Just $ Con (t1,t2)
>    import <- CanHalfZip
>    halfZip _          _          = Nothing

> instance Functor Can where
>   fmap = fmapDefault
> instance Foldable Can where
>   foldMap = foldMapDefault

> instance Traversable Elim where
>   traverse f (A s)  = (|A (f s)|)
>   traverse _ Out    = (|Out|)
>   import <- TraverseElim

> instance Functor Irr where
>   fmap = fmapDefault
> instance Foldable Irr where
>   foldMap = foldMapDefault
> instance Traversable Irr where
>    traverse f (Irr x) = (|Irr (f x)|)

> instance Functor Elim where
>   fmap = fmapDefault
> instance Foldable Elim where
>   foldMap = foldMapDefault

> instance Show x => Show (Tm dp x) where
>   show (L s)       = "L (" ++ show s ++ ")"
>   show (C c)       = "C (" ++ show c ++ ")"
>   show (N n)       = "N (" ++ show n ++ ")"
>   show (P x)       = "P (" ++ show x ++ ")"
>   show (V i)       = "V " ++ show i
>   show (n :$ e)    = "(" ++ show n ++ " :$ " ++ show e ++ ")"
>   show (op :@ vs)  = "(" ++ opName op ++ " :@ " ++ show vs ++ ")"
>   show (t :? y)    = "(" ++ show t ++ " :? " ++ show y ++ ")"
>
> instance Show x => Show (Scope p x) where
>   show (x :. t)   = show x ++ " :. " ++ show t
>   show (HF x t)  = "..."
>   show (K t) = "K (" ++ show t ++")"

> instance Show Op where
>   show = opName

> instance Functor (Scope {TT}) where
>   fmap = fmapDefault
> instance Foldable (Scope {TT}) where
>   foldMap = foldMapDefault
> instance Traversable (Scope {TT}) where
>   traverse f (x :. t)   = (|(x :.) (traverse f t)|)
>   traverse f (K t)      = (|K (traverse f t)|)

> instance Traversable f => Functor (Labelled f) where
>   fmap = fmapDefault
> instance (Traversable f, Foldable f) => Foldable (Labelled f) where
>   foldMap = foldMapDefault
> instance Traversable f => Traversable (Labelled f) where
>   traverse f (mt :?=: ft)  = (| traverse f mt :?=: traverse f ft |)

> instance (Traversable f, HalfZip f) => HalfZip (Labelled f) where
>   halfZip (Just a  :?=: fs)  (Just b :?=: ft)  = 
>     (| (Just (a, b)  :?=:) (halfZip fs ft) |)
>   halfZip (_       :?=: fs)  (_      :?=: ft)  = 
>     (| (Nothing  :?=:) (halfZip fs ft) |)

> instance Functor (Tm {d,TT}) where
>   fmap = fmapDefault
> instance Foldable (Tm {d,TT}) where
>   foldMap = foldMapDefault
> instance Traversable (Tm {d,TT}) where
>   traverse f (L sc)     = (|L (traverse f sc)|)
>   traverse f (C c)      = (|C (traverse (traverse f) c)|)
>   traverse f (N n)      = (|N (traverse f n)|)
>   traverse f (P x)      = (|P (f x)|)
>   traverse f (V i)      = pure (V i)
>   traverse f (t :$ u)   = (|(:$) (traverse f t) (traverse (traverse f) u)|)
>   traverse f (op :@ ts) = (|(op :@) (traverse (traverse f) ts)|)
>   traverse f (tm :? ty) = (|(:?) (traverse f tm) (traverse f ty)|)


%endif
