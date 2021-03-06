module Parallel.Skel.EdenMWToken
 -- TODO export list
  where
import Parallel.Eden
import System.IO.Unsafe
import Control.Monad
import Data.List
import Control.Parallel.Strategies
import Control.Concurrent
import Maybe

--basic maste worker
mw :: (Trans t, Trans r) => Int -> Int -> (t -> r) -> [t] -> [r]
mw n prefetch wf tasks = ress
  where
   (reqs, ress) =  (unzip . merge) (spawn workers inputs)
   -- workers   :: [Process [t] [(Int,r)]]
   workers      =  [process (zip [i,i..] . map wf) | i <- [0..n-1]]
   inputs       =  distribute n tasks (initReqs ++ reqs)
   initReqs     =  concat (replicate prefetch [0..n-1])

--basic mw new, request and results in seperate streams
mwN :: (Trans t, Trans r) => Int -> Int -> (t -> r) -> [t] -> [r]
mwN n prefetch wf tasks = ress
  where
   (reqs, ress) =  mergelists $ spawn workers inputs
   -- workers   :: [Process [t] ([Int],[r])]
   workers      =  [process (\ts -> let 
                                           results = map wf ts 
                            -- Es gilt: reqs = [i,i..]
                            -- Requesterzeugung wird durch zip mit vollst�ndig ausgewerteter
                            -- Ergebnisliste k�nstlich verz�gert 
                                           reqs    = generateReqs i results
                                    in (reqs, results)) | i <- [0..n-1]]

   inputs       =  distribute n tasks (initReqs ++ reqs)
   initReqs     =  concat (replicate prefetch [0..n-1])

generateReqs :: NFData a => Int -> [a] -> [Int]
generateReqs i (r:rs) = rnf r `seq` (i:generateReqs i rs)
generateReqs i []     = []

mergelists :: [([a],[b])] -> ([a],[b])
mergelists tuples =    let (xss,yss) = unzip tuples
                       in (merge xss,  merge yss)
--mergelists :: [([a],[b])] -> ([a],[b])
--mergelists tuples = (merge(map fst tuples), merge (map snd tuples))


-- task distribution according to worker requests
distribute               :: Int -> [t] -> [Int] -> [[t]]
distribute np tasks reqs = [taskList reqs tasks n | n<-[0..np-1]]
    where taskList (r:rs) (t:ts) pe | (pe == r) = t:(taskList rs ts pe)
                                    | otherwise  =    taskList rs ts pe
          taskList _      _      _  = []

spawn :: (Trans a, Trans b) => [Process a b] -> [a] -> [b]
spawn ps is = unsafePerformIO (zipWithM (instantiateAt 0) ps is)


spawnAt :: (Trans a, Trans b) => [Int] -> [Process a b] -> [a] -> [b]
spawnAt strides ps is = unsafePerformIO
            (sequence
             [instantiateAt st p i |
              (st,p,i) <- zip3 (cycle strides) ps is]
            )

--without justLeafes -- diplom.tex Version
mwResTree :: (Trans t, Trans r) =>
              Bool -> [Int] -> Int -> Int -> (t -> r) -> [t] -> [r]
mwResTree _ nesting n prefetch wf tasks = ress
  where
   nestList = nesting ++ [n]                 -- use at least n CPUs
   inputs   =  distribute n tasks (initReqs ++ (merge reqss))
   initReqs =  concat (replicate prefetch [0..n-1])
   ress = (rnf [parfill tChan ts ()|(tChan,ts)<-zip tChans inputs]) `seq` ress'
   (tChans, ress') = concatmergelists workers
   (reqss, reqChans) = unzip [new (\reqChan reqs -> (reqs, (i,reqChan))) 
                               | i <- [0..n-1]] 
   workers = rnf reqChans `seq` genWorkers nestList reqChans
-- genWorkers :: (Trans t, Trans r) => [Int] -> [(Int,ChanName [Int])] -> 
--               [([ChanName [t]],[r])]
   genWorkers nestList' reqChans'' 
     = unsafePerformIO $
       zipWithM (\(pos,p)-> instantiateAt pos p)
       [(pos, (process (\() -> worker (tail nestList') (reqChans'))))
         |(pos,reqChans') <- (partNPlace (head nestList') reqChans'')] (repeat ())
-- worker :: (Trans t, Trans r) => [Int] -> [(Int,ChanName [Int])] -> 
--           ([ChanName [t]],[r])
   worker nestList' ((id,reqChan):reqChans') 
     = let 
         (tChans,ts) = new (\tChan ts' -> ((tChan:tChans'),ts'))
         (tChans',res) | null reqChans' = ([],[])           -- is leaf worker
                       | otherwise      = concatFirstList $ -- got childs
                                            genWorkers nestList' reqChans' 
         results = parfill reqChan reqs (mergeS (results':res) rnf) 
         results'= map wf ts
         reqs    = generateReqs id results'
       in (tChans, results)


--diplom.tex Version
mwResTreeDistrib :: (Trans t, Trans r) =>
       Bool -> [Int] -> Int -> Int -> (t -> r) -> [t] -> [r]
mwResTreeDistrib _ nesting n prefetch wf tasks = ress
  where
   nestList = nesting ++ [n-1]
   (tChans, ress) = concatmergelists workers
   (reqChans,done) = unsafePerformIO ((instantiateAt (n+1) distributor) tChans)
   workers = rnf reqChans `seq` genWorkers nestList reqChans
-- genWorkers :: (Trans t, Trans r) => [Int] -> [(Int,ChanName [Int])] -> 
--               [([ChanName [t]],[r])]
   genWorkers nestList' reqChans'' 
     = unsafePerformIO $
       zipWithM (\(pos,p)-> instantiateAt pos p)
       [(pos,(process (\() -> worker (tail nestList') (reqChans'))))
         |(pos,reqChans') <- (partNPlace (head nestList') reqChans'')] 
       (repeat ())

-- worker :: (Trans t, Trans r) => [Int] -> [(Int,ChanName [Int])] -> 
--           ([ChanName [t]],[r])
   worker nestList' ((id,reqChan):reqChans') 
     = let 
         (tChans,ts) = new (\tChan ts' -> ((tChan:tChans'),ts'))
         (tChans',res) | null reqChans' = ([],[])           -- is leaf worker
                       | otherwise      = concatFirstList $ -- got childs
                                            genWorkers nestList' reqChans' 
         results = parfill reqChan reqs (mergeS (results':res) rnf) 
         results'= map wf ts
         reqs    = generateReqs id results'
       in (tChans, results)
-- distributor :: ((Int,ChanName [Int]) , Bool)
   distributor 
     = process 
       (\tChans' -> let
          (reqss, reqChans') 
           = unzip [new (\reqChan reqs -> (reqs, (i,reqChan)))| i <- [0..n-2]]
          done'  = (rnf [parfill tChan ts () 
                           | (tChan,ts) <- zip tChans' inputs]) `seq` True
          inputs   = distribute (n-1) tasks (initReqs ++ (merge reqss))
          initReqs = concat (replicate prefetch [0..n-2])
        in (reqChans',done'))

--this skeleton is suffering from something - don't know what it might be
--ResTree for dynamic Task creation with distributor collector seperation
mwResTreeDistribDyn :: (Trans t, Trans r) =>
       Bool -> [Int] -> Int -> Int -> ([t] -> [(r,[t])]) -> [t] -> [r]
mwResTreeDistribDyn _ nesting n prefetch wf initTasks = ress
  where
   nestList = nesting ++ [n-1]
   (tChans, ress) = concatmergelists workers
   (reqChans,done) = unsafePerformIO ((instantiateAt (n+1) distributor) tChans)
   workers = rnf reqChans `seq` genWorkers nestList reqChans
-- genWorkers :: (Trans t, Trans r) => [Int] -> [(Int,ChanName ([Int],[[t]]))] -> 
--               [([ChanName [t]],[r])]
   genWorkers nestList' reqChans'' 
     = unsafePerformIO $
       zipWithM (\(pos,p)-> instantiateAt pos p)
       [(pos,(process (\() -> worker (tail nestList') (reqChans'))))
         |(pos,reqChans') <- (partNPlace (head nestList') reqChans'')] 
       (repeat ())

-- worker :: (Trans t, Trans r) => [Int] -> [(Int,ChanName ([Int],[[t]]]))] -> 
--           ([ChanName [t]],[r])
   worker nestList' ((id,reqChan):reqChans') 
     = let
         (tChans,ts) = new (\tChan ts' -> ((tChan:tChans'),ts'))
         (tChans',res) | null reqChans' = ([],[])           -- is leaf worker
                       | otherwise      = concatFirstList $ -- got childs
                                            genWorkers nestList' reqChans' 
         results = parfill reqChan (reqs,newTss) (mergeS (results'':res) rnf) 
         results'= wf ts
         (results'',newTss)= unzip results'
         reqs    = generateReqs id results'
       in (tChans, results)
-- distributor :: ([(Int,ChanName ([Int],[[t]]))], Bool)
   distributor 
     = process 
       (\tChans' -> let
          (reqss,nTsss, reqChans') 
           = unzip3 [new (\reqChan (reqs,nTss) -> (reqs,nTss,(i,reqChan)))| i <- [0..n-2]]
          done'  = (rnf [parfill tChan ts () 
                           | (tChan,ts) <- zip tChans' inputs]) `seq` True
          inputs   = distribute (n-1) tasks (initReqs ++(merge reqss))
          initReqs = concat (replicate prefetch [0..n-2])
          tasks = initTasks ++ newTs                       --complete task List
          (_,newTs) = tdetect (zip (repeat ()) (merge nTsss)) (length initTasks) --Term
        in (reqChans',done'))


partNPlace :: Int -> [el] ->[(Int,[el])] 
partNPlace parts ls = recPart (length ls) parts ls (selfPe+1) -- Liste in parts Teillisten aufteilen
  where
    recPart l p ls pos 
      | size >= l = [(pos,ls)]
      | otherwise = let (xs,ys) = (splitAt size ls)
                    in ((pos,xs) : recPart (l-size) (p-1) ys (pos+size))
      where size = ceiling((fromIntegral l) / (fromIntegral p))

concatFirstList :: [([a],[b])] -> ([a],[[b]])
concatFirstList tuples = (concat(map fst tuples), (map snd tuples))
concatmergelists :: NFData b => [([a],[b])] -> ([a],[b])
concatmergelists tuples =    let (xss,yss) = unzip tuples
                       in (concat xss,  merge yss)


--Version without DM
mwRingDynLF' :: (Trans t, Trans r) =>
       [Int] -> Int -> ([t] -> [(r,[t])]) -> [t] -> [r]
mwRingDynLF' nesting n wf tasks = ress
  where
   nestList = nesting ++ [n]
   inputs = unshuffleN (length tNReqChanChans) tasks  --partitions round robbin
   ress = 
     rnf tNReqChanChans `seq` 
     rnf [parfill tNReqChanChan (ts,reqChan,isFirst) () 
          | (tNReqChanChan,ts,reqChan,isFirst) 
          <- zip4 tNReqChanChans inputs reqChans (True:falselist)] `seq` ress'
     where falselist = False:falselist
   reqChans = tail reqChans' ++ [head reqChans']
   (tNReqChanChans,reqChans')= unzip tNReqChanChansNReqChans
   (tNReqChanChansNReqChans, ress') 
     = concatmergelists (genWorkers nestList n)
-- genWorkers :: (Trans t, Trans r) => 
--               [Int] -> Int -> [([(ChanName ([t],Req [t],Bool]),Req [t])],[r])]
   genWorkers nestList' restPEs 
     = unsafePerformIO $
       zipWithM (\(pos,p)-> instantiateAt pos p)
       [
       (pos, (process (\() -> worker (tail nestList') restPEs')))
        |(pos,restPEs') <- (nest (head nestList') restPEs)] (repeat ())
-- worker :: (Trans t, Trans r) => 
--           [Int] -> Int -> ([(ChanName ([t],Req [t],[Bool]),Req [t])],[r])
   worker nestList' restPEs 
     | (restPEs==1)                                           --Leafworker
       = (new (\tNReqChanChan (ts,reqCOut,isFirst) -> new(\reqCIn reqIn ->
               ([(tNReqChanChan,reqCIn)],
                workerAdminDyn wf ts reqCOut reqIn isFirst))))
     | otherwise                                              --Nodeworker
       = concatmergelists $ genWorkers nestList' (restPEs-1)  

--diplom.tex Version DM
mwRingDynLF :: (Trans t, Trans r) =>
       [Int] -> Int -> ([t] -> [(r,[t])]) -> [t] -> [r]
mwRingDynLF nesting n wf tasks = ress
  where
   nestList = nesting ++ [n]
   ress = 
     rnf [parfill reqChanChan reqChan () 
          | (reqChanChan,reqChan) <- zip reqChanChans reqChans] `seq` ress'
   reqChans = tail reqChans' ++ [head reqChans']
   (reqChanChans,reqChans')= unzip reqChanChansNReqChans
   (reqChanChansNReqChans, ress') 
     = concatmergelists (genWorkers nestList n tasks (True:(replicate n False))) 
-- genWorkers :: (Trans t, Trans r) => [Int] -> Int -> [t] -> [Bool] -> 
--                                     [([(ChanName Req [t],Req [t])],[r])]
   genWorkers nestList' restPEs tss isFirstL
     = unsafePerformIO $
       zipWithM (\(pos,p)-> instantiateAt pos p)
        [(pos, (process (\() -> 
          worker (tail nestList') restPEs' ts' isFirstL')))
          |((pos,restPEs'),ts',isFirstL') <- zip3 pNRpes (unshuffleN br tss) 
                                             (unshuffleN br isFirstL)]
                                             (repeat ())
       where pNRpes = (nest (head nestList') restPEs)
             br = length pNRpes                  -- real branching at this level
-- worker :: (Trans t, Trans r) => 
--           [Int] -> Int -> [t] -> [Bool] ->([(ChanName Req [t],Req [t])],[r])
   worker nestList' restPEs ts isFirstL
     | (restPEs==1)                                           --Leafworker
       = (new (\reqChanChan reqCOut -> new(\reqCIn reqIn ->
               ([(reqChanChan,reqCIn)],
                workerAdminDyn wf ts reqCOut reqIn (head isFirstL)))))
     | otherwise                                              --Nodeworker
       = concatmergelists $ genWorkers nestList' (restPEs-1) ts isFirstL

--Stateful Version without DM
mwRingSLF' :: (Trans t, Trans r, Trans s, NFData r') =>
       [Int] -> Int ->                         --Nesting, amount of Workers
       ([(t,s)] -> [(Maybe (r',s),[t])]) ->    --wf
       ([Maybe (r',s)] -> s -> [r]) ->         --result transformation
       ([[r]] -> [r]) ->                       --result merge
       ([t]->[t]->s->[t]) ->                   --Taskpool Transform Attach
-- !! Split and Detatch policy has to give tasks away, unless all tasks are cut
       ([t]->s->([t],[t])) ->                  --Split Policy (remote Req)
       ([t]->s->([t],Maybe (t,s))) ->          --tt Detach (local Req)
       (s->s->Bool) ->            --Checks if new State is better than old State
       s -> [t] -> ([r],Int)                   --initState, tasks, results
mwRingSLF' nesting n wf resT resMerge ttA ttSplit ttD sUpdate st tasks 
  = (ress,noOfTasks)
  where
   nestList = nesting ++ [n]
   inputs = unshuffleN (length tNReqChanChans) tasks  --partitions round robbin
   ress = 
     rnf tNReqChanChans `seq` 
     rnf [parfill tNReqChanChan (ts,reqChan,isFirst) () 
          | (tNReqChanChan,ts,reqChan,isFirst) 
          <- zip4 tNReqChanChans inputs reqChans (True:falselist)] `seq` ress'
     where falselist = False:falselist
   reqChans = tail reqChans' ++ [head reqChans']
   (tNReqChanChans,reqChans')= unzip tNReqChanChansNReqChans
   (tNReqChanChansNReqChans, ress',noOfTasks) 
     = (concat chs,resMerge resss, sum nosOfTasks) 
     where (chs,resss,nosOfTasks) = unzip3 $ genWorkers nestList n
-- genWorkers :: (Trans t, Trans r) => 
--        [Int] -> Int -> [([(ChanName ([t],ReqS [t] s,Bool]),ReqS [t] s)],[r],Int)]
   genWorkers nestList' restPEs 
     = unsafePerformIO $
       zipWithM (\(pos,p)-> instantiateAt pos p)
       [(pos, (process (\() -> worker (tail nestList') restPEs')))
        |(pos,restPEs') <- (nest (head nestList') restPEs)] (repeat())
-- worker :: (Trans t, Trans r) => 
--           [Int] -> Int -> ([(ChanName ([t],ReqS [t] s,[Bool]),ReqS [t] s)],[r],Int)
   worker nestList' restPEs 
     | (restPEs==1)                                           --Leafworker
       = (new (\tNReqChanChan (ts,reqCOut,isFirst) -> new(\reqCIn reqIn ->
                let (res,noOfTasks)= workerAdminS wf resT ttA ttSplit ttD sUpdate 
                                      st ts reqCOut reqIn isFirst
                in([(tNReqChanChan,reqCIn)],res,noOfTasks))))
     | otherwise = (concat chs, resMerge resss, sum nosOfTasks) 
        where (chs,resss,nosOfTasks) = unzip3 $ genWorkers nestList' (restPEs-1)

--Stateful Version DM
mwRingSLF :: (Trans t, Trans r, Trans s, NFData r') =>
       [Int] -> Int ->                         --Nesting, amount of Workers
       ([(t,s)] -> [(Maybe (r',s),[t])]) ->    --wf
       ([Maybe (r',s)] -> s -> [r]) ->         --result transformation
       ([[r]] -> [r]) ->                       --result merge
       ([t]->[t]->s->[t]) ->                   --Taskpool Transform Attach
-- !! Split and Detatch policy has to give tasks away, unless all tasks are cut
       ([t]->s->([t],[t])) ->                  --Split Policy (remote Req)
       ([t]->s->([t],Maybe (t,s))) ->          --tt Detach (local Req)
       (s->s->Bool) ->            --Checks if new State is better than old State
       s -> [t] -> ([r],Int)                   --initState, tasks, results
mwRingSLF nesting n wf resT resMerge ttA ttSplit ttD sUpdate st tasks 
  = (ress,noOfTasks)
  where
   nestList = nesting ++ [n]
   ress = 
     rnf [parfill reqChanChan reqChan () 
          | (reqChanChan,reqChan) <- zip reqChanChans reqChans] `seq` ress'
   reqChans = tail reqChans' ++ [head reqChans']
   (reqChanChans,reqChans')= unzip reqChanChansNReqChans
   (reqChanChansNReqChans, ress',noOfTasks) 
      = (concat chs,resMerge resss, sum nosOfTasks)
     where (chs,resss,nosOfTasks) = unzip3 $ genWorkers nestList n tasks (True:(replicate n False)) 
-- genWorkers :: (Trans t, Trans r) => [Int] -> Int -> [t] -> [Bool] -> 
--                                     [([(ChanName (ReqS [t] s),Req [t])],[r])]
   genWorkers nestList' restPEs tss isFirstL
     = unsafePerformIO $
       zipWithM (\(pos,p)-> instantiateAt pos p)
        [(pos, (process (\() -> 
          worker (tail nestList') restPEs' ts' isFirstL')))
          |((pos,restPEs'),ts',isFirstL') <- zip3 pNRpes (unshuffleN br tss) 
                                             (unshuffleN br isFirstL)]
                                             (repeat ())
       where pNRpes = (nest (head nestList') restPEs)
             br = length pNRpes                  -- real branching at this level
-- worker :: (Trans t, Trans r) => 
--           [Int] -> Int -> [t] -> [Bool] ->([(ChanName (ReqS [t] s),ReqS [t] s)],[r])
   worker nestList' restPEs ts isFirstL
     | (restPEs==1)                                           --Leafworker
       = (new (\reqChanChan reqCOut -> new(\reqCIn reqIn ->
                let (res,noOfTasks) = workerAdminS wf resT ttA ttSplit ttD sUpdate 
                                                    st ts reqCOut reqIn (head isFirstL)
                in([(reqChanChan,reqCIn)],res,noOfTasks))))
     | otherwise = (concat chs, resMerge resss, sum nosOfTasks) --Nodeworker
        where (chs,resss,nosOfTasks) = unzip3 $ genWorkers nestList' (restPEs-1) ts isFirstL

data Req t = Me |        --Work Request of local Worker - Fuction
             --Request of other Workers with Tag, and Chanel to Send Tasks and
             Others (Tag, ChanName (t,Maybe (ChanName(Req t))))| --Reply Chanel
             TasksNMe t  -- New Tasks and additional Me Request to add

instance NFData t => NFData (Req t)
      where rnf Me = ()       --Work Request of local Worker - Fuction
                --Request of other Workers with Tag, and Chanel to Send Tasks and
            rnf (Others (t, c)) = rnf t `seq` rnf c
            rnf (TasksNMe t) = rnf t   -- New Tasks and additional Me Request to add

instance Trans t => Trans (Req t)

data Tag = Black | --no Termination Situation / Term Mode: Last Request in Ring
           White (Int,Int,Int,Int) |  --check Termination Situation:(send&recv)
           None                       --Request of usual Worker

instance NFData Tag 
    where rnf Black = ()
          rnf None  = ()
          rnf (White (a,b,c,d)) = rnf (a,b,c,d)

instance Eq Tag where
    Black   == Black   = True
    None    == None    = True
    White a == White b = a==b
    a       == b       = False


workerAdminDyn :: (Trans t, Trans r) => ([t]->[(r,[t])]) -> [t] -> 
                  ChanName [Req [t]] -> [Req [t]] -> Bool -> [r]
workerAdminDyn wf ts reqCOut reqIn isFirst = parfill reqCOut reqOut ress
  where 
    ress' = wf ts'
    (ress,ntssNtoMe) --For every result, add TasksNMe request
      = unzip (map (\reS@(res,nts) -> rnf reS `seq`(res,TasksNMe nts)) ress')
    reqList = Me : mergeS [reqIn,            --merge external Requests
                           ntssNtoMe] rnf    --and nf reduced local Requests
    (ts',reqOut) = control reqList ts isFirst -- manage Taskpool & Requests

control:: Trans t => [Req [t]] -> [t] -> Bool -> ([t],[Req [t]])
control requests initTasks isFirst 
  = distribWork requests initTasks Nothing (0,0)
  where
    --until no tasks left: react on own and Others requests & add new Tasks
    --distribWork :: Trans t => [Req [t]] -> [t] -> Maybe (ChanName (Req [t])) 
    --                          -> (Int,Int)-> ([t],[Req [t]])
    distribWork (TasksNMe nts:rs) tS replyCh sNr --case selfmade Tasks arrive
      = distribWork (Me:rs) (nts++tS) replyCh sNr --then add Tasks and Me Req 
    distribWork (req@(Others(tag,tCh)):rs) [] replyCh sNr --Others Request & no
      | tag==None = (tS',req:wReqs')              --tasks left --> pass Request    
      | otherwise = (tS',Others(Black,tCh):wReqs') --I'm still working -> Black
       where(tS',wReqs') = distribWork rs [] replyCh sNr 
    distribWork (Me:rs) [] replyCh sNr = --last own Task solved and no new ones
      new (\reqChan (newTS,replyChan) -> --gen new reqChan to get newTS & replyC
       let (tS',wReqs)     = passWhileReceive (merge [rs, --wait for fst newTask
                              (rnf (case replyChan of Nothing -> newTS 
                                                      Just _ -> [head newTS]) 
                              `seq` [TasksNMe newTS])]) replyChan sNr --to merge
           tag | isFirst   = Black --First Worker starts Black (For Termination)
               | otherwise = None  --normal Workers with None Tag
         in(case replyCh of        --First own Request into Ring- others dynamic
                 Nothing       -> (tS',Others (tag,reqChan):wReqs)
                 Just replyCh' -> parfill replyCh' (Others (tag,reqChan)) 
                                          (tS',wReqs)))
    distribWork (Me:rs) tS replyCh sNr --local Request and Tasks present
      = let (tS',wReqs) = distribWork rs (tail tS) replyCh sNr 
        in ((head tS):tS',wReqs)       --add one Task to the Worker Input
    distribWork (Others (_,tCh):rs) tS replyCh (s,r) --foreign Req & have Tasks
      = let ((tS',wReqs'),replyReq) 
              = new (\replyChan replyReq' ->   --gen ReplyC and send Tasks & new
                 parfill tCh (tSEven,Just replyChan) --ReplyC in Chan of the Req
                 ((distribWork rs tSOdd replyCh (s+1,r)),replyReq')) 
        in (tS',merge [(rnf replyReq `seq` [replyReq]),wReqs']) --ReplyReqToOutp
      where [tSEven,tSOdd] = unshuffleN 2 tS   --split ts to send and ts to hold
--  Pass all until foreign Tasks arrive or Termination starts
--  passWhileRecive :: Trans t => [Req [t]] -> Maybe(ChanName (Req [t])) 
--                                -> (Int,Int) -> ([t],[Req [t]])
    passWhileReceive (req@(Others(None,tCh)):rs) replyCh sNr --Req of normal 
      = let (tS',wReqs) = passWhileReceive rs replyCh sNr    --Worker -> pass it
        in (tS',req:wReqs)
    passWhileReceive (req@(Others(Black,tCh)):rs) replyCh (s,r) --Black Request
      | (not isFirst) = (tS',req :wReqs)  --normal Workers: pass it
      | otherwise     = (tS',req':wReqs)  --First Worker: new Round starts White
      where (tS',wReqs) = passWhileReceive rs replyCh (s,r)
            req'= Others (White (s,r,0,0),tCh)         --Start with own Counters
    passWhileReceive (Others(White (s1,r1,s2,r2),tCh):rs) replyCh (s,r) 
      | (not isFirst) = (tS',req':wReqs)  --Normal Workers: add Counter and pass
      --4 counters equal -> pass Black as end of reqs Symbol, start Termination
      | otherwise     = if terminate then ([],Others(Black,tCh):termRing rs)
                                     else (tS',req'':wReqs) --no Termination
      where (tS',wReqs) = passWhileReceive rs replyCh (s,r)
            req'        = Others(White (s1+s,r1+r,s2,r2),tCh) --add Counters
            req''       = Others(White (s,r,s1,r1),tCh) --Move Counters->NewTurn 
            terminate   = (s1==r1)&&(r1==s2)&&(s2==r2)       --Check Termination
    passWhileReceive (TasksNMe newTS:rs) replyCh (s,r)       --Task List arrives
      | null newTS = ([],termRing  rs)    --got empty newTs -> begin Termination
      | otherwise  = (distribWork (Me:rs) newTS replyCh (s,r+1)) --have newTasks

termRing :: Trans t => [Req [t]] -> [Req [t]]
termRing []                       = []        -- Predecessors tells no more reqs
termRing ((Others (Black,tCh)):_) = parfill tCh ([],Nothing) [] --reply last req
termRing ((Others (None,tCh)):rs) = parfill tCh ([],Nothing) termRing rs --reply
termRing (_:rs)                   = termRing rs          --ignore isFirsts reply

data ReqS t s = 
       ME |                             --Work Request of local Worker - Fuction
               --Request of other Workers with Tag, and Chanel to Send Tasks and
       OtherS (Tag, ChanName (t,Maybe (ChanName(ReqS t s))))|     --Reply Chanel
       TasksNME t |                -- New Tasks and additional Me Request to add
       NewState s

instance (NFData t, NFData s) => NFData (ReqS t s)
  where 
   rnf ME = ()      
   rnf (OtherS (t, c)) = rnf t `seq` rnf c
   rnf (TasksNME t) = rnf t
   rnf (NewState s) = rnf s
            
instance (Trans t,Trans s) => Trans (ReqS t s)

workerAdminS :: (Trans t, Trans r, Trans s, NFData r') => 
                  ([(t,s)]->[(Maybe (r',s),[t])]) -> --Worker function
                  ([Maybe (r',s)]->s->[r]) ->        --Result Transformation
                  ([t]->[t]->s->[t]) ->              --Taskpool Transform Attach
                  ([t]->s->([t],[t])) ->             --Split Policy (remote Req)
                  ([t]->s->([t],Maybe (t,s))) ->     --tt Detach (local Req)
                  (s->s->Bool) -> --Checks if new State is better than old State
                  s ->                               --Initial State
                  [t] ->                             --Tasks
                  ChanName [ReqS [t] s] ->           --Outgoing request chanal 
                  [ReqS [t] s] ->                    --Received requests
                  Bool ->                            --First worker in Ring?
                  ([r],Int)                          --Results to parent
workerAdminS wf resT ttA ttSplit ttD sUpdate st ts reqCOut reqIn isFirst 
  = parfill reqCOut reqOut (ress,noOfTasks)
  where 
    ress' = wf ts'
    noOfTasks = length ress'
    (ress,ntssNtoMe) = let (rs,reqs) = unzip $ genResNReqS ress' --seperate
                       in ((resT rs sFinal), reqs)        --transform Res
    reqList = ME : mergeS [reqIn,            --merge external Requests
                           ntssNtoMe] rnf    --and nf reduced local Requests
    -- manage Taskpool & Requests
    (ts',reqOut) = controlS ttA ttSplit ttD sUpdate reqList ts st isFirst
    sFinal = let (NewState st')=last reqOut
             in st'

controlS:: (Trans t, Trans s) =>
           ([t]->[t]->s->[t]) ->                     --Taskpool Transform Attach
           ([t]->s->([t],[t])) ->                    --Split Policy (remote Req)
           ([t]->s->([t],Maybe (t,s))) ->            --tt Detach (local Req)
           (s->s->Bool)->           --Checks if newState is better than oldState
           [ReqS [t] s]->[t]->s->Bool->              --reqs,tasks,state,isFirst
           ([(t,s)],[ReqS [t] s])                    --localTasks,RequestsToRing
controlS ttA ttSplit ttD sUpdate requests initTasks st isFirst 
  = distribWork requests initTasks Nothing st (0,0)
  where
    --until no tasks left: react on own and Others requests & add new Tasks
    --distribWork :: Trans t => [ReqS [t] s] -> [t] -> 
    --           Maybe (ChanName (ReqS [t] s))->(Int,Int)-> ([t],[ReqS [t] s],s)
    distribWork (TasksNME nts:rs) tS replyCh st sNr      --selfmade Tasks arrive
      = distribWork (ME:rs) (ttA tS nts st) replyCh st sNr --add Tasks and MeReq 
    distribWork (NewState st':rs) tS replyCh st sNr      --Updated State arrives
      | sUpdate st' st = let (tS',wReqs') =distribWork rs tS replyCh st' sNr
                         in (tS',(NewState st':wReqs'))    --then check and send 
      | otherwise      = distribWork rs tS replyCh st sNr  --or discard
    distribWork (req@(OtherS(tag,tCh)):rs) [] replyCh st sNr  --Others Request &
      | tag==None = (tS',req:wReqs')            --no tasks left --> pass Request    
      | otherwise = (tS',OtherS(Black,tCh):wReqs') --I'm still working -> Black
      where(tS',wReqs') = distribWork rs [] replyCh st sNr 
    distribWork (ME:rs) [] replyCh st sNr = --last own Task solved and no new ones
      new (\reqChan (newTS,replyChan) -> --gen new reqChan to get newTS & replyC
       let (tS',wReqs)     = passWhileReceive (merge [rs, --wait for fst newTask
                              (rnf (case replyChan of Nothing -> newTS 
                                                      Just _ -> [head newTS]) 
                              `seq` [TasksNME newTS])]) replyChan st sNr --to merge
           tag | isFirst   = Black --First Worker starts Black (For Termination)
               | otherwise = None  --normal Workers with None Tag
       in(case replyCh of          --First own Request into Ring- others dynamic
               Nothing       -> (tS',OtherS (tag,reqChan):wReqs)
               Just replyCh' -> parfill replyCh' (OtherS (tag,reqChan)) 
                                          (tS',wReqs)))
    distribWork (ME:rs) tS replyCh st sNr      --local Request and Tasks present
      = let (tS',tDetatch) = ttD tS st         --TaskpoolTransform Detatch
            (tsDetatch,wReqs) = case tDetatch of 
                                 Nothing -> distribWork (ME:rs) [] replyCh st sNr 
                                 Just t  -> distribWork rs tS' replyCh st sNr
        in ((maybeToList tDetatch)++tsDetatch,wReqs) --add Maybe one Task to wf
    distribWork reqs@(OtherS (_,tCh):rs) tS replyCh st (s,r)  --foreign Req & have Ts
      = let (holdTs,sendTs) = ttSplit tS st    --split ts to send and ts to hold
            ((tS',wReqs'),replyReq) 
              = new (\replyChan replyReq' ->   --gen ReplyC and send Tasks & new
                 parfill tCh (sendTs,Just replyChan) --ReplyC in Chan of the Req
                 ((distribWork rs holdTs replyCh st (s+1,r)),replyReq')) 
        in case sendTs of                                       --ReplyReqToOutp
            []    -> distribWork reqs [] replyCh st (s,r)       --No tasks left
            (_:_) -> (tS',merge [(rnf replyReq `seq` [replyReq]),wReqs'])
--  Pass all until foreign Tasks arrive or Termination starts
--  passWhileRecive :: Trans t => [ReqS [t] s] -> Maybe(ChanName (ReqS [t] s)) 
--                                -> (Int,Int) -> ([t],[ReqS [t] s])
    passWhileReceive (NewState st':rs) replyCh st sNr --Updated State arrives
      | sUpdate st' st =let (tS',wReqs')=passWhileReceive rs replyCh st' sNr
                        in (tS',(NewState st':wReqs'))    --then check and send 
      | otherwise      = passWhileReceive rs replyCh st sNr     --or discard
    passWhileReceive (req@(OtherS(None,tCh)):rs) replyCh st sNr --Req of normal 
      = let (tS',wReqs) = passWhileReceive rs replyCh st sNr --Worker -> pass it
        in (tS',req:wReqs)
    passWhileReceive (req@(OtherS(Black,tCh)):rs) replyCh st (s,r) --Black Req
      | (not isFirst) = (tS',req :wReqs)  --normal Workers: pass it
      | otherwise     = (tS',req':wReqs)  --First Worker: new Round starts White
      where (tS',wReqs) = passWhileReceive rs replyCh st (s,r)
            req'= OtherS (White (s,r,0,0),tCh)         --Start with own Counters
    passWhileReceive (OtherS(White (s1,r1,s2,r2),tCh):rs) replyCh st (s,r) 
      | (not isFirst) = (tS',req':wReqs)  --Normal Workers: add Counter and pass
      --4 counters equal -> pass Black as end of reqs Symbol, start Termination
      | otherwise     = if terminate then ([],OtherS(Black,tCh):(termRingS rs ++ [NewState st]))
                                     else (tS',req'':wReqs) --no Termination
      where (tS',wReqs) = passWhileReceive rs replyCh st (s,r)
            req'        = OtherS(White (s1+s,r1+r,s2,r2),tCh) --add Counters
            req''       = OtherS(White (s,r,s1,r1),tCh) --Move Counters->NewTurn 
            terminate   = (s1==r1)&&(r1==s2)&&(s2==r2)       --Check Termination
    passWhileReceive (TasksNME newTS:rs) replyCh st (s,r)    --Task List arrives
      | null newTS = ([],(termRingS rs)    --got empty newTs -> begin Termination
                          ++ [NewState st]) --attach final State at the End
      | otherwise  = (distribWork (ME:rs) newTS replyCh st (s,r+1)) --have newTs

termRingS :: (Trans t,Trans s) => [ReqS [t] s] -> [ReqS [t] s]
termRingS []                       = []        -- Predecessors tells no more reqs
termRingS ((OtherS (Black,tCh)):_) = parfill tCh ([],Nothing) [] --reply last req
termRingS ((OtherS (None,tCh)):rs) = parfill tCh ([],Nothing) termRingS rs --reply
termRingS (_:rs)                   = termRingS rs          --ignore isFirsts reply

genResNReqS :: (NFData t,NFData r',NFData s)=>
               [(Maybe (r',s),[t])] -> [(Maybe (r',s),ReqS [t] s)]
genResNReqS [] = []                           --No more tasks
genResNReqS ((reS@(Nothing,nts)):ress'' )     --No new State -> Attach new Tasks 
  = rnf reS `seq` (Nothing,TasksNME nts):(genResNReqS ress'')
genResNReqS ((reS@(Just (r,st),nts)):ress'')   --New State found -> Attach
  = rnf reS `seq` (Just (r,st),NewState st):(genResNReqS ((Nothing,nts):ress''))


--calculates a list of (PeID to Instantiate Child, #restPEs to be Nested in Subtree) using the #restPEs rooted at this Node and the parts (childs) to divide them 
nest :: Int -> Int -> [(Int,Int)] 
nest parts restPEs 
  = tail (scanl (\a b -> ((fst a)+(snd a),b)) (selfPe+1, 0)      --pos des Kindes
     (replicate mot (dif+1) ++ replicate ((parts-mot) * min 1 dif) dif)) --prozessoren pro kind
 where dif = div restPEs parts
       mot = mod restPEs parts

mw2level ::  (Trans t, Trans r) =>
         Int -> Int -> ([t]->[r]) -> [t] -> [r]
mw2level np pf wf = mw' 2 (m*(pf+1)) (mw' m pf wf)
  where m = (np-3) `div` 2

--nestable mw ([t] -> [r])
mw' :: (Trans t, Trans r) =>
       Int -> Int -> ([t] -> [r]) -> [t] -> [r]
mw' n prefetch wf tasks = ress
  where
   (reqs, ress) =  (unzip . merge) (spawn workers inputs)
   -- workers   :: [Process [t] [(Int,r)]]
   workers      =  [process (zip [i,i..] . wf) | i <- [0..n-1]]
   inputs       =  distribute n tasks (initReqs ++ reqs)
   initReqs     =  concat (replicate prefetch [0..n-1])

-- and placement: 
mw'' :: (Trans t, Trans r) =>
        Int -> Int -> Int -> ([t] -> [r]) -> [t] -> [r]
mw'' stride n prefetch wf tasks = ress
  where
   (reqs, ress) =  (unzip . merge) (spawnAt (nextPes n stride) workers inputs)
   -- workers   :: [Process [t] [(Int,r)]]
   workers      =  [process (zip [i,i..] . wf) | i <- [0..n-1]]
   inputs       =  distribute n tasks (initReqs ++ reqs)
   initReqs     =  concat (replicate prefetch [0..n-1])

-- nestable mwN (new Version)
mwN' :: (Trans t, Trans r) =>
       Int -> Int -> ([t] -> [r]) -> [t] -> [r]
mwN' n prefetch wf tasks = ress
  where
   (reqs, ress) =  mergelists $ spawn workers inputs
   -- workers   :: [Process [t] [(Int,r)]]
   -- workers   :: [Process [t] ([Int],[r])]
   workers      =  [process (\ts -> let 
                                           results = wf ts 
                            -- Es gilt: reqs = [i,i..]
                            -- Requesterzeugung wird durch zip mit vollst�ndig ausgewerteter
                            -- Ergebnisliste k�nstlich verz�gert 
                                           reqs    = generateReqs i results
                                    in (reqs, results)) | i <- [0..n-1]]
   inputs       =  distribute n tasks (initReqs ++ reqs)
   initReqs     =  concat (replicate prefetch [0..n-1])



-- mwN with placement:
mwN'' :: (Trans t, Trans r) =>
        Int -> Int -> Int -> ([t] -> [r]) -> [t] -> [r]
mwN'' stride n prefetch wf tasks = ress
  where
   (reqs, ress) =  mergelists (spawnAt (nextPes n stride) workers inputs)
   -- workers   :: [Process [t] ([Int],[r])]
   workers      =  [process (\ts -> let 
                                           results = wf ts 
                            -- Es gilt: reqs = [i,i..]
                            -- Requesterzeugung wird durch zip mit vollst�ndig ausgewerteter
                            -- Ergebnisliste k�nstlich verz�gert 
                                           reqs    = generateReqs i results
                                    in (reqs, results)) | i <- [0..n-1]]
   inputs       =  distribute n tasks (initReqs ++ reqs)
   initReqs     =  concat (replicate prefetch [0..n-1])

nextPes :: Int -> Int -> [Int]
nextPes n stride | start > noPe = replicate n noPe
                 | otherwise    = concat (replicate n ps)
    where ps    = cycle (takeWhile (<= noPe) [start,start+stride..])
          start = selfPe + 1

mwNested :: (Trans t, Trans r) =>
            [Int] -> [Int] ->  -- branching degrees/prefetches
                               -- per level
            ([t] -> [r]) ->    -- worker function
            [t] -> [r]         -- tasks, results
mwNested ns pfs wf = foldr fld wf (zip ns pfs)
  where
    fld :: (Trans t, Trans r) =>
           (Int,Int) -> ([t] -> [r]) -> ([t] -> [r])
    fld (n,pf) wf = mw' n pf wf

-- and using placement
mwNested' :: (Trans t, Trans r) =>
             [Int] -> [Int] -> -- branching degrees/prefetches
                               -- per level
         ([t] -> [r]) ->   -- worker function
         [t] -> [r]        -- tasks, results
mwNested' ns pfs f initTasks = (foldr fld f (zip3 stds ns pfs)) initTasks
        where
    stds = scanr (\x y -> ((y*x)+1)) 1 (tail ns) -- liste der strides
    fld (stride,n,pf) wf = \ts -> (mw'' stride n pf wf ts)

mwNest :: (Trans t, Trans r) =>
          Int -> Int -> Int -> Int -> (t -> r) -> [t] -> [r]
mwNest depth level1 np pf f tasks
    = let nesting = mkNesting np depth level1
      in mwNested nesting (mkPFs pf nesting) (map f) tasks

-- and placement...
mwNest' :: (Trans t, Trans r) =>
           Int -> Int -> Int -> Int -> (t -> r) -> [t] -> [r]
mwNest' depth level1 np pf f tasks
    = let nesting = mkNesting np depth level1
      in mwNested' nesting (mkPFs pf nesting) (map f) tasks

mkNesting :: Int -> Int -> Int -> [Int]
mkNesting np 1 _ = [np]
mkNesting np depth level1 = level1:(replicate (depth - 2) 2) ++ [numWs]
  where -- leaves   = np - #submasters
        leaves      = np - level1 * ( 2^(depth-1) - 1 )
    -- # lowest submasters
        numSubMs    = level1 * 2^(depth - 2)
        -- workers per branch (rounded up)
        numWs       = (leaves + numSubMs - 1) `div` numSubMs

mkPFs :: Int ->    -- prefetch value for worker processes
         [Int] ->  -- branching per level top-down
         [Int]     -- list of prefetches
mkPFs pf nesting
    = [ factor * (pf+1) | factor <- scanr1 (*) (tail nesting) ] ++ [pf]

--mwDyn flat -with dynamic tasc creation
mwDyn :: (Trans t, Trans r) =>
         Int -> Int -> ([t] -> [(r,[t])]) -> [t] -> [r]
mwDyn n prefetch wf initTasks = finalResults
 where
   -- identical to static task pool except for the type of workers
   (reqs, ress) =  (unzip . merge) (spawn workers inputs)
-- worker    :: [Process [t] [(Int,(r,[t]))]]
   workers      =  [process (zip [i,i..] . wf) | i <- [0..n-1]]
   inputs       =  distribute n tasks (initReqs ++ reqs)
   initReqs     =  concat (replicate prefetch [0..n-1])
   -- additions for task queue management and
   -- termination detection
   tasks        =  initTasks ++ newTasks
   initNumTasks =  length initTasks
   (finalResults, newTasks) = tdetect ress initNumTasks


--mwDyn New with seperate chanals fpr Tasks and Requests
mwDynN :: (Trans t, Trans r) =>
         Int -> Int -> ([t] -> [(r,[t])]) -> [t] -> [r]
mwDynN n prefetch wf initTasks = finalResults
 where
   -- identical to static task pool except for the type of workers
   (reqs, ress) =  mergelists (spawn workers inputs)
--alt   -- worker    :: [Process [t] [(Int,(r,[t]))]]
--alt   workers      =  [process (zip [i,i..] . map wf) | i <- [0..n-1]]
   -- workers   :: [Process [t] ([Int],[(r,[t])])]
   workers      =  [process (\ts -> let 
                                           results = wf ts 
                            -- Es gilt: reqs = [i,i..]
                            -- Requesterzeugung wird durch zip mit vollst�ndig ausgewerteter
                            -- Ergebnisliste k�nstlich verz�gert 
                                           reqs    = generateReqs i results
                                    in (reqs, results)) | i <- [0..n-1]]


   inputs       =  distribute n tasks (initReqs ++ reqs)
   initReqs     =  concat (replicate prefetch [0..n-1])
   -- additions for task queue management and
   -- termination detection
   tasks        =  initTasks ++ newTasks
   initNumTasks =  length initTasks
   (finalResults, newTasks) = tdetect ress initNumTasks

-- task queue control for termination detection
tdetect :: [(r,[t])] -> Int -> ([r], [t])
tdetect ((r,ts):ress) numTs
  | numTs == 1 && null ts  = ([r], []) -- final result
  | otherwise              = (r:moreRes, ts ++ moreTs)
  where
    (moreRes, moreTs) = tdetect ress (numTs-1+length ts)

--Tiefensuche, alter wp
mwDyn' :: (Trans t, Trans r) =>
         Int -> Int -> ([t] -> [(r,[t])]) -> [t] -> [r]
mwDyn' n prefetch wf initTasks = finalResults
 where
   -- identical to static task pool except for the type of workers
   (reqNresS) =  merge (spawn workers inputs)
   -- worker    :: [Process [t] [(Int,(r,[t]))]]
   workers      =  [process (zip [i,i..] . wf) | i <- [0..n-1]]
   inputs       =  distribute n tasks (reqs)
   initReqs     =  concat (replicate prefetch [0..n-1])
   -- additions for task queue management and
   -- termination detection
   initNumTasks =  length initTasks
   (finalResults, tasks, reqs) = tdetect' reqNresS initReqs initTasks initNumTasks

-- task queue control for termination detection Dipl Version
tdetect' :: [(Int,(r,[t]))] -> [Int] -> [t] -> Int -> ([r], [t], [Int])
tdetect' rNrS initReqs initTs numTs
  = (rs',(ts++ts'),(reqs++reqs'))
  where
  (remReqs, remTs, reqs, ts) = tt initReqs initTs
  (rs',ts',reqs') = tdetect'' rNrS remReqs remTs numTs
  --taskpool transformation: serve matching amount of tasks and requests
  tt remReqs remTs = let l = min (length remReqs) (length remTs)
                         (rServe,rHold) = splitAt l remReqs
                         (tServe,tHold) = splitAt l remTs
                     in (rHold,tHold,rServe,tServe)
  tdetect'' ((req,(r,ts)):ress) remReqs remTs numTs
    | numTs == 1 && null ts  = ([r],[],[]) -- final result
    | otherwise = ((r:rs'),(ts'++ts''),(reqs'++reqs''))
      where 
       (remReqs', remTs', reqs', ts') = tt (req:remReqs) (ts++remTs)
       (rs',ts'',reqs'') = tdetect'' ress remReqs' remTs' (numTs+(length ts)-1)

mwDynSub :: (Trans t, Trans r) =>
            Int -> Int -> ([Maybe t] -> [(r,[t],Int)])
            -> [Maybe t] -> [(r,[t],Int)]
mwDynSub n prefetch wf initTasks = finalResults where
  fromWorkers  = map flatten (spawn workers inputs)
  -- worker    :: [Process [Maybe t] [(Int,Maybe (r,[t]))]]
  workers      =  [process (zip [i,i..] . wf) | i <- [0..n-1]]
  inputs       =  distribute n tasks (initReqs ++ reqs)
  initReqs     =  concat (replicate prefetch [0..n-1])
  -- task queue management
  controlInput =  merge (map Right initTasks: map (map Left) fromWorkers)
  (finalResults, tasks, reqs)
               = tcontrol controlInput 0 prefetch False

flatten :: [(Int,(r,[t],Int))] -> [(Int,r,[t],Int)] -- not shown

tcontrol :: [Either (Int,r,[t],Int) (Maybe t)] -> -- controlInput
         Int ->                          -- task counter
         Int -> Bool ->                  -- prefetch, split mode
         ([(r,[t],Int)],[Maybe t],[Int]) -- (results,tasks,requests)
tcontrol ((Right Nothing):_) 0 _ _
  = ([],repeat Nothing,[])               -- Final termination
tcontrol ((Right (Just t)):ress) numTs pf even  -- task from above
  = let (moreRes, moreTs, reqs) = tcontrol ress (numTs+1) pf even
    in (moreRes, (Just t):moreTs, reqs)
tcontrol ((Left (i,r,ts,subNumTs)):ress) numTs pf even
  | numTs == 1 && null ts && subNumTs == 0
    = let (moreRes, moreTasks, rs) = tcontrol ress 0 pf even
      in  ((r,[],0):moreRes, moreTasks, i:rs) -- last result
  | otherwise
    =  let (moreRes, moreTs, reqs)
             = tcontrol ress (numTs - 1 + length localTs + subNumTs)
               pf evenAct
           (localTs,fatherTs,evenAct)
             = split numTs pf ts even -- part of tasks to parent
           newreqs = if subNumTs == 0
              then i:reqs else reqs -- no tasks kept below?
       in ((r,fatherTs,subNumTs + length localTs):moreRes,
           (map Just localTs) ++ moreTs, newreqs)

-- error case, not shown in paper
tcontrol ((Right Nothing):_) n _ _
  = error "Received Stop signal, although not finished!"

-- ' Versions with experimental functions tcontrol' and tdetect'
mwDynSub' :: (Trans t, Trans r) =>
            Int -> Int -> ([Maybe t] -> [(r,[t],Int)])
            -> [Maybe t] -> [(r,[t],Int)]
mwDynSub' branch prefetch wf initTasks = finalResults where
  fromWorkers  = map flatten (spawn workers inputs)
  -- worker    :: [Process [Maybe t] [(Int,Maybe (r,[t]))]]
  workers      =  [process (zip [i,i..] . wf) | i <- [0..branch-1]]
  inputs       =  distribute branch tasks (initReqs ++ reqs)
  initReqs     =  concat (replicate prefetch [0..branch-1])
  -- task queue management
  controlInput =  merge (map Right initTasks: map (map Left) fromWorkers)
  (finalResults, tasks, reqs)
               = tcontrol' controlInput 0 0 (branch * (prefetch+1)) False


tcontrol' :: [Either (Int,r,[t],Int) (Maybe t)] -> -- controlInput
         Int -> Int ->                   -- task / hold counter
         Int -> Bool ->                  -- prefetch, split mode
         ([(r,[t],Int)],[Maybe t],[Int]) -- (results,tasks,requests)
tcontrol' ((Right Nothing):_) 0 _ _ _
  = ([],repeat Nothing,[])               -- Final termination
tcontrol' ((Right (Just t)):ress) numTs hldTs pf even  -- task from above
  = let (moreRes, moreTs, reqs) = tcontrol' ress (numTs+1) hldTs pf even
    in (moreRes, (Just t):moreTs, reqs)
tcontrol' ((Left (i,r,ts,subHoldsTs)):ress) numTs hldTs pf even
    =  let (moreRes, moreTs, reqs)
             = tcontrol' ress (numTs + differ) (hldTs') pf evenAct
           differ = length localTs + subHoldsTs - 1
           hldTs' = max (hldTs + differ) 0
           holdInf | (hldTs+differ+1 > 0) = 1
                   | otherwise            = 0
           (localTs,fatherTs,evenAct)
             = split numTs pf ts even -- part of tasks to parent
           newreqs | (subHoldsTs == 0) = i:reqs 
                   | otherwise         = reqs -- no tasks kept below?
       in ((r,fatherTs,holdInf):moreRes,
           (map Just localTs) ++ moreTs, newreqs)

-- error case, not shown in paper
tcontrol' ((Right Nothing):_) n _ _ _
  = error "Received Stop signal, although not finished!"

flatten [] = []
flatten ((i,(r,ts,n)):ps) = (i,r,ts,n) : flatten ps

split :: Int -> Int -> [t] -> Bool ->([t],[t],Bool)
split num pf ts even-- = splitAt (2*pf - num) ts
    | num >= 2*pf      = ([],ts,False)
    --keine Tasks vorhanden oder odd -> behalte ersten 
    | ((not even)||(num == 1)) = oddEven ts
    | otherwise                = evenOdd ts
    -- | num < pf `div` 2 = (ts,[])


oddEven :: [t] -> ([t],[t],Bool)
oddEven []     = ([],[],False)
oddEven (x:xs) = (x:localT ,fatherT, even)
    where (localT,fatherT,even) = evenOdd xs

evenOdd :: [t] -> ([t],[t],Bool)
evenOdd []   = ([],[],True)
evenOdd (x:xs) = (localT, x:fatherT, even)
    where (localT,fatherT,even) = oddEven xs
{-
odds,evens :: [t] -> [t]
odds [] = []
odds [x] = [x]
odds (x:xs) = x:evens xs
evens [] = []
evens [_] = []
evens (_:xs) = odds xs
-}


mwDynNested :: (Trans t, Trans r) =>
               [Int] -> [Int] -> (t -> (r,[t])) -> [t] -> [r]
mwDynNested ns pfs wf initTasks
     = topMaster (head ns) (head pfs) subWF initTasks
       where subWF = foldr fld wf' (zip (tail ns) (tail pfs))
             -- wf' :: [Maybe t] -> [(r,[t],Int)]
             wf' ((Just x):rest) = ((\ (r,ts) -> (r,ts,0))(wf x)):wf' rest
             wf' (Nothing:_) = [] -- STOP!!!
             fld :: (Trans t, Trans r) =>
                     (Int, Int) -> ([Maybe t] -> [(r,[t],Int)]) ->
                     [Maybe t] -> [(r,[t],Int)]
             fld (n,pf) wf = mwDynSub n pf wf

topMaster :: (Trans t, Trans r) =>
         Int -> Int -> ([Maybe t] -> [(r,[t],Int)]) -> [t] -> [r]
topMaster branch prefetch wf initTasks = finalResults
 where
   -- identical to static task pool except for the type of workers
   (reqs, ress) =  (unzip . merge) (spawn workers inputs)
   -- worker    :: [Process [t] [(Int,(r,[t]))]]
   workers      =  [process (zip [i,i..] . wf) | i <- [0..branch-1]]
   inputs       =  distribute branch  tasks (initReqs ++ reqs)
   initReqs     =  concat (replicate prefetch [0..branch-1])
   -- additions for task queue management and
   -- termination detection
   tasks        =  (map Just initTasks) ++ newTasks
   -----------------------------
   initNumTasks =  length initTasks
   -- => might lead to deadlock!
   -----------------------------
   (finalResults, newTasks) = tdetectTop ress initNumTasks

-- task queue control for termination detection
--tdetectTop :: [(r,[t],Int)] -> Int -> ([r], [Maybe t])
tdetectTop ((r,ts,localNumTs):ress) numTs
  | numTs == 1 && null ts && localNumTs == 0
    = ([r], repeat Nothing) -- final result
  | otherwise
    = (r:moreRes, (map Just ts) ++ moreTs)
  where
    (moreRes, moreTs) = tdetectTop ress (numTs-1+length ts+localNumTs)

-- ' Versions with experimental functions tcontrol' and tdetect'   
topMaster' :: (Trans t, Trans r) =>
         Int -> Int -> ([Maybe t] -> [(r,[t],Int)]) -> [t] -> [r]
topMaster' branch prefetch wf initTasks = finalResults
 where
   -- identical to static task pool except for the type of workers
   ress         =  merge (spawn workers inputs)
   -- worker    :: [Process [Maybe t] [(Int,(r,[t],Int))]]
   workers      =  [process (zip [i,i..] . wf) | i <- [0..branch-1]]
   inputs       =  distribute branch  tasks (initReqs ++ reqs)
   initReqs     =  concat (replicate prefetch [0..branch-1])
   -- additions for task queue management and
   -- termination detection
   tasks        =  (map Just initTasks) ++ newTasks
   -----------------------------
   initNumTasks =  length initTasks
   -- => might lead to deadlock!
   -----------------------------
   (finalResults, reqs, newTasks) 
                = tdetectTop' ress initNumTasks

-- task queue control for termination detection
--tdetectTop :: [(r,[t],Int)] -> Int -> ([r], [Int] [Maybe t])
tdetectTop' ((req,(r,ts,subHoldsTs)):ress) numTs
  | numTs == 1 && null ts && subHoldsTs == 0
    = ([r], [], repeat Nothing) -- final result
  | subHoldsTs == 1
    = (r:moreRes, moreReqs,  (map Just ts) ++ moreTs)
  | otherwise
    = (r:moreRes, req:moreReqs, (map Just ts) ++ moreTs)
  where --localNumTaks is 0 or 1, if it's 1 -> no Request 
        -- -> numTs will not be decreased
    (moreRes, moreReqs,  moreTs) 
      = tdetectTop' ress (numTs-1+length ts+subHoldsTs)


-- helper functions, not in paper

-- whnfspine :: Strategy [a]
whnfspine [] = ()
whnfspine (x:xs) = x `seq` whnfspine xs

mergeByTags :: [[(Int,r)]] -> [(Int,r)]
mergeByTags [] = []
mergeByTags [wOut] = wOut
-- mergeByTags (w1:rest) = merge2ByTag w1 (mergeByTags rest)
mergeByTags [w1,w2] = merge2ByTag w1 w2
mergeByTags wOuts = merge2ByTag
               (mergeHalf wOuts)
               (mergeHalf (tail wOuts))
    where mergeHalf = mergeByTags . (takeEach 2)
          takeEach n [] = []
          takeEach n xs@(x:_) = x:takeEach n (drop n xs)

merge2ByTag [] w2 = w2
merge2ByTag w1 [] = w1
merge2ByTag w1@(r1@(i,_):w1s) w2@(r2@(j,_):w2s)
                        | i < j = r1: merge2ByTag w1s w2
                        | i > j = r2: merge2ByTag w1 w2s
                        | otherwise = error "found tags i == j"
                        
mergeS:: [[a]] -> Strategy a -> [a]
mergeS l st = unsafePerformIO (nmergeIOS l st)

type Buffer a 
 = (MVar (MVar [a]), QSem)

max_buff_size :: Int
max_buff_size = 1

suckIOS :: MVar Int -> Buffer a -> [a] -> Strategy a -> IO ()
suckIOS branches_running buff@(tail_list,e) vs st
 = case vs of
    [] -> takeMVar branches_running >>= \ val ->
          if val == 1 then
         takeMVar tail_list     >>= \ node ->
         putMVar node []        >>
         putMVar tail_list node
          else  
         putMVar branches_running (val-1)
    (x:xs) ->
        (st x `seq` waitQSem e)           >>
        takeMVar tail_list       >>= \ node ->
            newEmptyMVar             >>= \ next_node ->
        unsafeInterleaveIO (
            takeMVar next_node  >>= \ y ->
            signalQSem e        >>
            return y)            >>= \ next_node_val ->
        putMVar node (x:next_node_val)   >>
        putMVar tail_list next_node      >>
        suckIOS branches_running buff xs st

nmergeIOS :: [[a]] -> Strategy a -> IO [a]
nmergeIOS lss st
 = let
    len = length lss
   in
    newEmptyMVar      >>= \ tail_node ->
    newMVar tail_node     >>= \ tail_list ->
    newQSem max_buff_size >>= \ e ->
    newMVar len       >>= \ branches_running ->
    let
     buff = (tail_list,e)
    in
    mapIO (\ x -> forkIO (suckIOS branches_running buff x st)) lss >>
    takeMVar tail_node  >>= \ val ->
    signalQSem e    >>
    return val
  where
    mapIO f xs = sequence (map f xs)
    
unshuffleN :: Int -> [a] -> [[a]]
unshuffleN n xs = unshuffle xs
        where  unshuffle xs = map (f xs) [0..n-1]
                where f xs i = g (drop i xs)
                      g [] = []
                      g xs = head xs : (g (drop n xs))

takeEveryN :: Int -> [a] -> ([a],[a])
takeEveryN n xs = ((f xs),(g xs))
          where f [] = []
                f (x:xs) = let (hold,rest)= splitAt (n-1) xs in hold++(f rest)
                g [] = []
                g xs = head xs : (g (drop n xs))
