% This is our submission, modified from:
% the file JFP2egui.lhs
% release v1.02, 27th September 2001
%   (based on JFPguide.lhs v1.11 for LaLhs 2.09)
% Copyright (C) 2001 Cambridge University Press

\NeedsTeXFormat{LaTeX2e}

\documentclass{jfp1}

%% add a tweak to polycode, similar to literate in lstlistings, but uglier
%format |>>>|        = "\mathbin{|\!\!>\!\!>\!\!>\!\!|}"
%format parcomp        = "\mathbin{|\!\!>\!\!>\!\!>\!\!|}"
%format >>>        = "\mathbin{>\!\!>\!\!>}"
%% ^^^^ you want this. and similar for ***, +++, etc.
%% a hack for list comprehensions' <-, typeset it as <--
%%%%%format <--        = "\in "
%format DOLLAR = "\mathbin{\$}"
%%%% %format ` = "\`"
%%%% %% works fine without
%format ||| = "\mathbin{\mid\!\mid\!\mid}"
%format pipepipepipe = "\mathbin{\mid\!\mid\!\mid}"
%format |&&&| = "\mathbin{\mid\!\!\&\!\&\!\&\!\!\mid}"
%format parand = "\mathbin{\mid\!\!\&\!\&\!\&\!\!\mid}"
%format &&& = "\mathbin{\&\!\&\!\&}"
%format |***| = "\mathbin{\mid\!\!*\!*\!*\!\!\mid}"
%format parstar = "\mathbin{\mid\!\!*\!*\!*\!\!\mid}"
%format *** = "\mathbin{*\!*\!*}"
%format |+++| = "\mathbin{\mid\!\!+\!\!+\!\!+\!\!\mid}"
%format +++ = "\mathbin{+\!\!+\!\!+}"


%include polycode.fmt

%%% Macros for the guide only %%%
%\providecommand\AMSLaTeX{AMS\,\LaTeX}
%\newcommand\eg{\emph{e.g.}\ }
%\newcommand\etc{\emph{etc.}}
%\newcommand\bcmdtab{\noindent\bgroup\tabcolsep=0pt%
%  \begin{tabular}{@{}p{10pc}@{}p{20pc}@{}}}
%\newcommand\ecmdtab{\end{tabular}\egroup}
%\newcommand\rch[1]{$\longrightarrow\rlap{$#1$}$\hspace{1em}}
%\newcommand\lra{\ensuremath{\quad\longrightarrow\quad}}

\jdate{April 2017}
\pubyear{2017}
\pagerange{\pageref{firstpage}--\pageref{lastpage}}
\doi{...}

%\newtheorem{lemma}{Lemma}[section]

%include prelude.lhs


\title{Arrows for Parallel Computations}
\ifthenelse{\boolean{anonymous}}{%
\author{Submission ID xxxxxx}
}{%
%\author{Martin Braun, Phil Trinder, and Oleg Lobachev}
%\affiliation{University Bayreuth, Germany and Glasgow University, UK}
 \author[M. Braun, P. Trinder and O. Lobachev]%
        {MARTIN BRAUN\\
         University Bayreuth, 95440 Bayreuth, Germany\\
         PHIL TRINDER\\
		 Glasgow University, Glasgow, G12 8QQ, Scotland\\
		 \and\ OLEG LOBACHEV\\
		 University Bayreuth, 95440 Bayreuth, Germany}
}% end ifthenelse



\begin{document}

\label{firstpage}

\maketitle

%% environment inside
%include abstract.lhs

\tableofcontents

	%
	%%include abstract.lhs
	%
	%\newpage
	\tableofcontents
	%\pagebreak
	%include motivation.lhs
	%include parallelHaskells.lhs
	%include arrows.lhs
	%\pagebreak
	%include relwork.lhs
	%\pagebreak
	%\pagebreak
	%include parrows.lhs
	%\pagebreak
	%include basicSkeletons.lhs
	%\pagebreak
	%include syntacticSugar.lhs
	%\pagebreak
	%include futures.lhs
	%\pagebreak
	%include mapSkeletons.lhs
	%\pagebreak
	%include topologySkeletons.lhs
	%\pagebreak
	%include benchmarks.lhs
	%%\pagebreak
	%include conclusion.lhs
	%\pagebreak
        \bibliographystyle{jfp}
	\bibliography{references,main}
        \appendix
	%include utilityFunctions.lhs
\end{document}