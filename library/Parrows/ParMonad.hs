{-
The MIT License (MIT)

Copyright (c) 2016 Martin Braun

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-}
{-# LANGUAGE FlexibleInstances, UndecidableInstances, MultiParamTypeClasses #-}
module Parrows.ParMonad where

import Parrows.Definition
import Control.Monad.Par
import Control.Arrow

zipWithArrM :: (ArrowApply arr, ArrowChoice arr, Applicative m) => (arr (a, b) (m c)) -> arr ([a], [b]) (m [c])
zipWithArrM f = (arr $ \abs -> (zipWithArr f, abs)) >>> app >>> arr sequenceA

parEval' :: (ArrowApply arr, ArrowChoice arr, NFData b) => arr ([arr a b], [a]) (Par [b])
parEval' = (arr $ \fas ->
                    (zipWithArrM (app >>> arr return >>> arr Control.Monad.Par.spawn), fas)) >>>
            app >>> arr (>>= \ibs -> mapM get ibs)

instance (ArrowApply arr, ArrowChoice arr, NFData b) => ParallelSpawn arr a b where
    parEvalN = (arr $ \fs -> ((arr $ \as -> (parEval', (fs, as))) >>> app >>> arr runPar))

instance (NFData b, NFData d) => SyntacticSugar (->) a b c d where
    f |***| g = parEval2 (f, g)

instance (Monad m, NFData b, NFData d) => SyntacticSugar (Kleisli m) a b c d where
    f |***| g = (arr $ \ac -> ((parEval2, (f, g)), ac)) >>> (first $ app) >>> app