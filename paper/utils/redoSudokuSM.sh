#!/usr/bin/env bash

rm *.csv

./benchmarkCalculator ../raw_benches/sudoku_sm.csv bench_sudoku_sm True
cp bench-sudoku-sm.bench.* ../content/benchmarks/sudoku-sm

originalBenchmarks=(
    "bench-sudoku-sm.bench.eden-sudoku-sudoku17.1000.txt.csv"
    "bench-sudoku-sm.bench.eden-sudoku-sudoku17.16000.txt.csv"
    "bench-sudoku-sm.bench.multicore-sudoku-sudoku17.1000.txt.csv"
    "bench-sudoku-sm.bench.multicore-sudoku-sudoku17.16000.txt.csv"
    "bench-sudoku-sm.bench.parmonad-sudoku-sudoku17.1000.txt.csv"
    "bench-sudoku-sm.bench.parmonad-sudoku-sudoku17.16000.txt.csv"
)

parrowsBenchmarks=(
    "bench-sudoku-sm.bench.parrows-sudoku-parmap-eden-sudoku17.1000.txt.csv"
    "bench-sudoku-sm.bench.parrows-sudoku-parmap-eden-sudoku17.16000.txt.csv"
    "bench-sudoku-sm.bench.parrows-sudoku-parmap-mult-sudoku17.1000.txt.csv"
    "bench-sudoku-sm.bench.parrows-sudoku-parmap-mult-sudoku17.16000.txt.csv"
    "bench-sudoku-sm.bench.parrows-sudoku-parmap-par-sudoku17.1000.txt.csv"
    "bench-sudoku-sm.bench.parrows-sudoku-parmap-par-sudoku17.16000.txt.csv"
)

outFileNames=(
    "eden-cp-1000-diff.csv"
    "eden-cp-16000-diff.csv"
    "mult-1000-diff.csv"
    "mult-16000-diff.csv"
    "par-1000-diff.csv"
    "par-16000-diff.csv"
)

worstFileName="worstAndBestSudoku.csv"

count=${#originalBenchmarks[@]}

touch ${worstFileName}

for i in $(seq 0 $(expr ${count} - 1));
do
    ./calculateDifferences ${originalBenchmarks[i]} ${parrowsBenchmarks[i]} ${outFileNames[i]}
    cp ${outFileNames[i]} ../content/benchmarks/sudoku-sm

    ./calculateDifferences ${originalBenchmarks[i]} ${parrowsBenchmarks[i]} ${worstFileName} True True
    ./calculateDifferences ${originalBenchmarks[i]} ${parrowsBenchmarks[i]} ${worstFileName} True False
done

cp ${worstFileName} ../content/benchmarks/sudoku-sm

rm *.csv