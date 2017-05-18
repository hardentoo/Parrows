%\section{Motivation}
%Arrows were introduced in John Hughes paper as a general interface for computation and therefore as an alternative to monads for API design \citHughes. In the paper Hughes describes how arrows are a generalization of monads and how they are not as restrictive. In this paper we will use this concept to express parallelism.

\section{Introduction}
\label{sec:introduction}
\olcomment{todo, reuse 5.5, "Impact" at the end and more}

blablabla arrows, parallel, haskell.

\paragraph{Contribution}

HIT HERE REALLY STRONG

\paragraph{Structure}
The remaining text is structures as follows. Section~\ref{sec:background} briefly introduces known parallel Haskell flavours and gives an overview of Arrows to the reader (Sec.~\ref{sec:arrows}). Section~\ref{sec:related-work} discusses related work. Section~\ref{sec:parallel-arrows} defines Parallel Arrows and presents a basic interface. Section~\ref{futures} defines Futures for Parallel Arrows, this concept enables better communication. Section~\ref{sec:map-skeletons} presents some basic algorithmic skeletons (parallel |map| with and without load balancing, |map-reduce|) in our newly defined dialect. More advanced ones are showcased in Section~\ref{sec:topology-skeletons} (|pipe|, |ring|, |torus|). Section~\ref{sec:benchmarks} shows the benchmark results. Section~\ref{sec:conclusion} discusses future work and concludes.

%%% Local Variables:
%%% mode: latex
%%% TeX-master: "main"
%%% End: