{-# language BangPatterns #-}
{-# language ScopedTypeVariables #-}

import Test.Tasty
import Test.Tasty.HUnit
import Foreign.C.Error (Errno,errnoToIOError)
import Data.Primitive (ByteArray)
import Control.Concurrent (forkIO)
import Control.Monad (when)
import Foreign.C.Types (CInt,CSize)
import Control.Concurrent (threadWaitRead)

import qualified GHC.Exts as E
import qualified Data.Primitive as PM
import qualified Data.Primitive.MVar as PM
import qualified Posix.Socket as S

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Tests"
  [ testGroup "sockets"
    [ testCase "A" testSocketsA
    , testCase "B" testSocketsB
    , testCase "C" testSocketsC
    , testCase "D" testSocketsD
    ]
  ]

testSocketsA :: Assertion
testSocketsA = do
  (a,b) <- demand =<< S.socketPair S.unix S.datagram S.defaultProtocol
  m <- PM.newEmptyMVar
  _ <- forkIO $ S.receiveByteArray b 5 mempty >>= PM.putMVar m
  bytesSent <- demand =<< S.sendByteArray a sample 0 5 mempty
  when (bytesSent /= 5) (fail "testSocketsA: bytesSent was wrong")
  actual <- demand =<< PM.takeMVar m
  sample @=? actual

testSocketsB :: Assertion
testSocketsB = do
  let limit = 10
      wordSz = PM.sizeOf (undefined :: Int)
      cwordSz = fromIntegral wordSz :: CSize
  (a,b) <- demand =<< S.socketPair S.unix S.datagram S.defaultProtocol
  lock <- PM.newEmptyMVar
  let go1 !(ix :: Int) !(n :: Int) = if (ix < limit)
        then do
          y <- PM.newByteArray wordSz
          PM.writeByteArray y 0 (1 + n)
          z <- PM.unsafeFreezeByteArray y
          oneWord =<< demand =<< S.sendByteArray b z 0 cwordSz mempty
          x <- demand =<< S.receiveByteArray b cwordSz mempty
          go1 (ix + 1) (PM.indexByteArray x 0)
        else pure n
      go2 !(ix :: Int) = if (ix < limit)
        then do
          x <- demand =<< S.receiveByteArray a cwordSz mempty
          y <- PM.newByteArray wordSz
          PM.writeByteArray y 0 (1 + PM.indexByteArray x 0 :: Int) 
          z <- PM.unsafeFreezeByteArray y
          oneWord =<< demand =<< S.sendByteArray a z 0 cwordSz mempty
          go2 (ix + 1)
        else PM.putMVar lock ()
  _ <- forkIO (go2 0)
  r <- go1 0 0
  PM.takeMVar lock
  20 @=? r

testSocketsC :: Assertion
testSocketsC = do
  (a,b) <- demand =<< S.socketPair S.unix S.datagram S.defaultProtocol
  m <- PM.newEmptyMVar
  _ <- forkIO $ S.receiveByteArray a 5 mempty >>= PM.putMVar m
  bytesSent <- demand =<< S.sendByteArray b sample 0 5 mempty
  when (bytesSent /= 5) (fail "testSocketsC: bytesSent was wrong")
  actual <- demand =<< PM.takeMVar m
  sample @=? actual

testSocketsD :: Assertion
testSocketsD = do
  (a,b) <- demand =<< S.socketPair S.unix S.datagram S.defaultProtocol
  _ <- forkIO $ do
    bytesSent <- demand =<< S.sendByteArray b sample 0 5 mempty
    when (bytesSent /= 5) (fail "testSocketsD: bytesSent was wrong")
  actual <- demand =<< S.receiveByteArray a 5 mempty
  sample @=? actual

sample :: ByteArray
sample = E.fromList [1,2,3,4,5]

demand :: Either Errno a -> IO a
demand = either (\e -> ioError (errnoToIOError "test" e Nothing Nothing)) pure
  
oneWord :: CSize -> IO ()
oneWord x = if x == fromIntegral (PM.sizeOf (undefined :: Int)) then pure () else fail "expected one machine word"

