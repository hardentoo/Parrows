module Main where

import Util

import Text.ParserCombinators.Parsec
import Text.ParserCombinators.Parsec.Number

import Graphics.Rendering.Chart
import Graphics.Rendering.Chart.Drawing

import Data.Colour
import Data.Colour.Names
import Data.Default.Class
import Graphics.Rendering.Chart.Backend.Cairo
import Control.Lens

import Text.Regex.PCRE

import Data.String.Utils

import Data.String
import Data.CSV
import Data.List

import Data.Maybe
import Data.Either
import qualified Data.Map.Strict as M

import Debug.Trace

import System.Environment

import Data.Ord

type SpeedupsPerProgram = (String, [Speedup])
type NCores = Int
type SpeedupVal = Double

data BenchResult = BenchResult {
    name :: String,
    nCores :: NCores,
    mean :: Double,
    meanLB :: Double,
    meanUB :: Double,
    stdDev :: Double,
    stdDevLB :: Double,
    stdDevUB :: Double
} deriving (Show)

convToBenchResults :: [[String]] -> [BenchResult]
convToBenchResults lines = catMaybes $ map convToBenchResult lines
    where
        convToBenchResult :: [String] -> Maybe BenchResult
        convToBenchResult (nameStr:rest) = go nameStr $ convDoubles rest
            where go nameStr (Just ([mean,meanLB,meanUB,stdDev,stdDevLB,stdDevUB])) =
                    let (name, nCores) = parseName nameStr
                    in
                        Just $ BenchResult {
                            name = name,
                            nCores = nCores,
                            mean = mean,
                            meanLB = meanLB,
                            meanUB = meanUB,
                            stdDev = stdDev,
                            stdDevLB = stdDevLB,
                            stdDevUB = stdDevUB
                        }
                  go _ _ = Nothing

                  parseName :: String -> (String, Int)
                  -- little hacky with the two Regexes, but who cares?
                  parseName str = let (_, _, _, nameWithRTS) = str =~ "(.*) \\+RTS -N[0-9]*.*" :: (String,String,String,[String])
                                      (_, _, _, nCores) = str =~ ".* \\+RTS -N([0-9]*).*" :: (String,String,String,[String])
                                  in
                                    (if length nameWithRTS > 0 then head nameWithRTS else str,
                                        if length nCores > 0 then read (head nCores) else 1)

toMap :: [BenchResult] -> M.Map String [BenchResult]
toMap benchRes =
    foldl (\m bRes -> let name_ = name bRes in M.insert name_ (bRes:(lookup' name_ m)) m) M.empty benchRes
        where
            lookup' :: String -> M.Map String [BenchResult] -> [BenchResult]
            lookup' key map = go $ M.lookup key map
                where
                    go (Just a) = a
                    go Nothing = []

findSeqRun :: [BenchResult] -> Maybe BenchResult
findSeqRun results = go $ filter (\res -> nCores res == 1) results
    where
        go (res:rest) = Just res
        go _ = Nothing

data Speedup = Speedup (Maybe SpeedupVal) BenchResult deriving (Show)

benchResult :: Speedup -> BenchResult
benchResult (Speedup _ x) = x

calculateSpeedUps :: [BenchResult] -> Maybe [Double]
calculateSpeedUps benchResults = let maybeSeqRun = findSeqRun benchResults
    in
        fmap (\seqRun -> speedUps seqRun benchResults) maybeSeqRun
        where
            speedUps :: BenchResult -> [BenchResult] -> [Double]
            speedUps seqRun benchResults = map (speedUp seqRun) benchResults

            speedUp :: BenchResult -> BenchResult -> Double
            speedUp seqRun benchResult = (mean seqRun) / (mean benchResult)

calculateSpeedUpsForMap :: M.Map String [BenchResult] -> [SpeedupsPerProgram]
calculateSpeedUpsForMap = foldr (:) [] . (M.mapWithKey (\key benchResults ->
                                                let
                                                    maybeSpeedUps = calculateSpeedUps (benchResults)

                                                    zipToSpeedUp (Just speedUps) = zipWith (Speedup) (map Just speedUps) benchResults
                                                    zipToSpeedUp Nothing = zipWith Speedup (repeat Nothing) benchResults
                                                in
                                                    (key, sortBy (comparing (nCores . benchResult)) $ zipToSpeedUp maybeSpeedUps)))

toPlottableValues :: [SpeedupsPerProgram] -> [(String, [(NCores, SpeedupVal)])]
toPlottableValues speedUpsPerPrograms =
    map (\(name, speedupList) -> (name, catMaybes $ map speedupVal speedupList)) speedUpsPerPrograms

speedupVal :: Speedup -> Maybe (NCores, SpeedupVal)
speedupVal (Speedup (Just speedup) benchRes) = Just $ (nCores benchRes, speedup)
speedupVal _ = Nothing

countTo :: (Num a, Ord a) => a -> [a]
countTo num = go 0 num
                where
                    go cur num
                        | cur <= num = cur:(go (cur + 1) num)
                        | cur > num = []

setLinesBlue :: PlotLines a b -> PlotLines a b
setLinesBlue = plot_lines_style  . line_color .~ opaque blue

chart :: NCores -> String -> [LineStyle] -> [PointStyle] -> [(String, [(NCores, SpeedupVal)])] -> Renderable ()
chart maxCores plotName lineStyles pointStyles plotValues = toRenderable $ layout maxCores plotName lineStyles pointStyles plotValues
  where
    idLine :: NCores -> PlotLines Int Double
    idLine maxCores = plot_lines_values .~ [(zipWith (,) (countTo maxCores) (countTo (fromIntegral maxCores)))]
                          $ plot_lines_style .~ (dashedLine 2 [2, 3] $ opaque black)
                          $ def

    allDifferentNCores :: [NCores] -> [NCores]
    allDifferentNCores = map head . group . sort

    plotOneLines :: LineStyle -> (String, [(NCores, SpeedupVal)]) -> PlotLines Int Double
    plotOneLines lineStyle (name, renderValues) =
        plot_lines_values .~ [renderValues]
             $ plot_lines_style .~ lineStyle
             $ plot_lines_title .~ name
             $ def

    plotOnePoints :: PointStyle -> (String, [(NCores, SpeedupVal)]) -> PlotPoints Int Double
    plotOnePoints pointStyle (name, renderValues) =
       plot_points_style .~ pointStyle
             $ plot_points_values .~ renderValues
             $ plot_points_title .~ name
             $ def

    layout :: NCores -> String -> [LineStyle] -> [PointStyle] -> [(String, [(NCores, SpeedupVal)])] -> Layout Int Double
    layout maxCores plotName lineStyles pointStyles plotValues =
           let
               differentNCores = allDifferentNCores $ map fst $ concat $ map snd plotValues
               differentNCoresDouble = map fromIntegral differentNCores
           in
               layout_title .~ plotName
               $ layout_plots .~    ((toPlot $ idLine maxCores) :
                                    (map toPlot (zipWith ($) (zipWith ($) (repeat plotOneLines) lineStyles) plotValues)
                                    ++ map toPlot (zipWith ($) (zipWith ($) (repeat plotOnePoints) pointStyles) plotValues)))

               -- make sure we don't plot too much whitespace
               -- also add gridlines and labels for each relevant numcore/speedup step
               $ layout_x_axis . laxis_generate .~ const AxisData {
                                                              _axis_visibility = def,
                                                              _axis_viewport = vmap (0,maxCores+1),
                                                              _axis_tropweiv = invmap (0,maxCores+1),
                                                              _axis_ticks    = [],
                                                              _axis_grid     = differentNCores,
                                                              _axis_labels   = [[(l, show l) | l <- differentNCores]]
                                                         }
               $ layout_y_axis . laxis_generate .~ const AxisData {
                                                             _axis_visibility = def,
                                                             _axis_viewport = vmap (0,fromIntegral (maxCores +1)),
                                                             _axis_tropweiv = invmap (0,fromIntegral (maxCores +1)),
                                                             _axis_ticks    = [],
                                                             _axis_grid     = differentNCoresDouble,
                                                             _axis_labels   = [[(l, show l) | l <- differentNCoresDouble]]
                                                        }
               -- give the axis proper names
               $ layout_x_axis . laxis_title .~ "# of cores"
               $ layout_y_axis . laxis_title .~ "speedup"

               -- using the _Just prism, display only one legend element per line
               $ layout_legend . _Just . legend_orientation .~ LORows 1

               $ def


main :: IO ()
main = do
    args <- getArgs
    if(length args < 2)
    then
        do  putStrLn "usage: <program> file output maxCores plotName dimX dimY (for pdf output)"
            putStrLn "    or <program> file output ignoreSeq (for tex output)"
    else if (length args < 6)
    then
        -- output to TeX compatible csv file
        do
           let (file:output:ignoreSeqStr:rest) = args
               handleParse :: Either ParseError [[String]] -> IO ()
               handleParse (Right lines) = do
                   let
                       ignoreSeq :: Bool
                       ignoreSeq = read ignoreSeqStr

                       benchResultsPerProgram = toMap $ convToBenchResults lines
                       speedUpsPerPrograms = calculateSpeedUpsForMap benchResultsPerProgram
                       plottableValues = toPlottableValues speedUpsPerPrograms

                       -- "","name","time","nCores","speedup"
                       legend :: String
                       legend = "\"\",\"name\",\"time\",\"nCores\",\"speedup\",\"stddev\"" ++ "\n"

                       str :: String -> String
                       str st = "\"" ++ st ++ "\""

                       writeToFile :: String -> [Speedup] -> IO ()
                       writeToFile output speedups =
                            writeFile output $
                                legend ++
                                (concat $ zipWith ($) (zipWith ($) (repeat speedUpToString) ([1..]::([Int]))) speedups)

                       speedUpToString :: Int -> Speedup -> String
                       speedUpToString num (Speedup (Just speedupVal) benchRes) =
                            if (nCores benchRes) == 1 && ignoreSeq
                            then ""
                            else (str (show num)) ++ "," ++ (str $ name benchRes) ++ "," ++  (show $ mean benchRes) ++ "," ++
                                (show $ nCores benchRes) ++ "," ++ (show speedupVal) ++ "," ++ (show $ stdDev benchRes) ++ "\n"

                       sanitizeFileName :: String -> String
                       sanitizeFileName str = replace "_" "-" $ replace " " "_" $ replace "/" "" str

                   putStrLn $ "parsed " ++ show (M.size $ benchResultsPerProgram) ++ " different programs (with different number of cores)"
                   putStrLn $ "speedUps: " ++ show (speedUpsPerPrograms)
                   mapM_ (\(name, speedups) -> writeToFile (sanitizeFileName $ output ++ "." ++ name ++ ".csv") speedups) speedUpsPerPrograms
                   putStrLn $ "finished."
               handleParse _ = putStrLn "parse Error!"

           putStrLn $ "parsing from file: " ++ file
           linesOrError <- parseFromFile csvFile file
           handleParse linesOrError
    else
        -- directly plot to PDF file
        do
            let (file:output:maxCoresStr:plotName:dimX:dimY:rest) = args

                maxCores = read maxCoresStr

                outProps = fo_size .~ (read dimX,read dimY)
                        $ fo_format .~ PDF
                        $ def

                handleParse :: Either ParseError [[String]] -> IO ()
                handleParse (Right lines) = do
                    let benchResultsPerProgram = toMap $ convToBenchResults lines
                        speedUpsPerPrograms = calculateSpeedUpsForMap benchResultsPerProgram
                        plottableValues = toPlottableValues speedUpsPerPrograms
                        pointSize = 5
                        thickness = 2
                        pointStyles = cycle [filledCircles pointSize $ opaque black,
                                                filledPolygon pointSize 3 True $ opaque black,
                                                plusses pointSize thickness $ opaque black,
                                                exes pointSize thickness $ opaque black,
                                                stars pointSize thickness $ opaque black,
                                                filledPolygon pointSize 3 False $ opaque black,
                                                hollowPolygon pointSize thickness 3 True $ opaque black,
                                                hollowCircles pointSize thickness $ opaque black,
                                                hollowPolygon pointSize thickness 3 False $ opaque black
                                                ]
                    putStrLn $ "parsed " ++ show (M.size $ benchResultsPerProgram) ++ " different programs (with different number of cores)"
                    putStrLn $ "speedUps: " ++ show (speedUpsPerPrograms)
                    renderableToFile outProps output $ chart maxCores plotName (repeat $ (def :: LineStyle)) pointStyles plottableValues
                    putStrLn $ "finished."
                handleParse _ = putStrLn "parse Error!"

            putStrLn $ "parsing from file: " ++ file
            linesOrError <- parseFromFile csvFile file
            handleParse linesOrError