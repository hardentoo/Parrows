Multidimensionales FFT. Parallel. Parallel?

Fuer 2D wir operieren erstmal auf Spalten und dann auf Zeilen. Die Vorgehensweise kann verallgemeinert werden.
\begin{code}
module MathObj.FFT.MultiPar where

-- import MathObj.FFT.Short (fftS) -- oder anderes 1D FFT unserer Wahl
import MathObj.FFT.Reference as R (fft)
import MathObj.Vector.Vector hiding (transpose, length, concat)
import qualified Prelude -- hide!
import Prelude hiding ((++), length)
import Data.List (transpose)

import MathObj.Primes.SimpleFactor (factor)
import MathObj.FFT.IndexTransform
import Control.Parallel.Eden.Auxiliary (unshuffle)

-- new
import Control.Parallel.Eden (RD, fetchAll, releaseAll)

import MathObj.FFT.Complex -- hilft beim debuggen
\end{code}

2D
\begin{nocode}
twoDimFft n1 n2 xss = map (fft' n2) $ transpose $ map (fft' n1) $ transpose xss
    where fft' n xs = toList $ fft (n, xs)
twoDimFftGen fft n1 n2 xss = map (fft' n2) $ transpose $ map (fft' n1) $ transpose xss
             where fft'= toList $ curry fft
\end{nocode}

transpose ist sequentiell. Auf verteiles transpose umschalten?
\begin{code}
twoDimFftG pmap sfft n1 n2 xss = pmap (fft' n2) $ transpose $ pmap (fft' n1) $ transpose xss
    where fft' n xs = toList $ sfft (n, xs)
twoDimFft = twoDimFftG map fft

\end{code}

--- NEW! use remote data! we transpose only the futures
\begin{code}
twoDimFftRD pmap sfft n1 n2 xss = map fetchAll $ pmapRD (fft' n2) $ transpose $ pmapRD (fft' n1) $ map releaseAll $ transpose xss
    where fft' n xs = toList $ sfft (n, xs)
          pmapRD f = pmap (releaseAll . f  . fetchAll)
\end{code}

Fuer n-dim. FFT brauchen wir eine Art geschachtelte Listen zu "transponieren", in array-termen: x[i,j,k,...] nicht nach i, sondern nach j, k,... durchzuiterieren.


------------------------------------

Misplaced? Move to multidim/prime factor/.... fft?

Hatten wir's nicht schon irgendwo?
\begin{nocode}
splitFactors (n, xs) = let ns = factor n
                       in splitter ns xs

splitter [] _ = []
splitter (k:ks) xs = (take k xs):splitter ks xs

splitFactor2 n1 n2 (n, xs) | n1*n2 /= n = error "Factorisation mismatch!"
                           | otherwise  = splitter ks xs
                           where ks = take n2 $ repeat n1
\end{nocode}
\begin{nocode}
twoDimFft xss = let fftList = toList $ fft $ fromList  
                    yss = map (fftList ) xss
                in map (fftList) $ transpose yss
                           
factorFftRaw n1 n2 (n, xs) =  let xss = splitFactor2 n1 n2 (n, xs)
                              in concat $ twoDimFft xss

getFactors n = let n2 = tail $ factor n
                   n1 = n `div` n2
               in (n1, n2)

factorFft (n, xs) = applyTransform (factorFftRaw n1 n2) n1 n2 (n, xs)
    where (n1, n2) = getFactors n
\end{nocode}

-----------------------------------------------------------------------------

Poor man's factor FFT.

\begin{code}
factorFft k (n, xs) | n `mod` k /=0 = error "Bad factorisation"
                    | gcd k (n `div` k) /= 1 = error "Input length not OK"
                    | otherwise = let l = n `div` k
                                      oneLineFft = fromList . concat . 
                                                   (twoDimFft k l) . 
                                                   (unshuffle k) . toList
                                  in applyTransform (oneLineFft) k l (n, xs)

factorFft' k l xs = applyTransform R.fft k l xs
\end{code}
