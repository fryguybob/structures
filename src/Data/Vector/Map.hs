{-# LANGUAGE CPP #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE UndecidableInstances #-}
module Data.Vector.Map
  ( Map(..)
  , empty
  , null
  , singleton
  , lookup
  ) where

import Control.Lens as L
import Control.Monad
import Data.Bits
import qualified Data.Vector.Generic as G
import qualified Data.Vector.Generic.Mutable as GM
import qualified Data.Vector.Unboxed as U
import qualified Data.Vector.Unboxed.Mutable as UM
import Data.Vector.Internal.Check as Ck
import Data.Word
import Data.Vector.Array
import qualified Data.Vector.Bit as BV

#define BOUNDS_CHECK(f) (Ck.f __FILE__ __LINE__ Ck.Bounds)

-- | This Map is implemented as an insert-only Cache Oblivious Lookahead Array (COLA) with amortized complexity bounds
-- that are equal to those of a B-Tree when it is used ephemerally.
data Map k v = Map {-# UNPACK #-} !Int !(Array k) {-# UNPACK #-} !BitVector !(Array v) !(Map k v) | Nil

deriving instance (Show (Arr v v), Show (Arr k k)) => Show (Map k v)
deriving instance (Read (Arr v v), Read (Arr k k)) => Read (Map k v)

null :: Map k v -> Int
null Nil = True
null _   = False

empty :: Map k v
empty = Nil
{-# INLINE empty #-}

singleton :: (Arrayed k, Arrayed v) => k -> v -> Map k v
singleton k v = Map 1 (G.singleton k) (BV.singleton False) (G.singleton v) Nil
{-# INLINE singleton #-}

lookup :: (Ord k, Arrayed k, Arrayed v) => k -> Map k v -> Maybe v
lookup k m0 = start m0 where
  start Nil = Nothing
  start (Map n ks fwd vs m)
    | ks G.! j == k, not (bv^.contains j) = Just (vs G.! l)
    | otherwise = continue (dilate l)  m
    where j = search (\i -> ks G.! i >= k) 0 (n-1)
          l = rank fwd j

  continue lo Nil = Nothing
  continue lo (Map n ks bv vs m)
    | ks G.! j == k, not (bv^.contains j) = Just (vs G.! l)
    | otherwise = continue (dilate l) m
    where j = search (\i -> ks G.! i >= k) lo (min (lo+7) (n-1))
          l = rank fwd j
{-# INLINE lookup #-}

insert :: (Ord k, Arrayed k, Arrayed v) => k -> v -> Map k v -> Map k v
insert k v Nil = singleton k v
insert k v (Map n ks bv vs m) = undefined

-- * Utilities

dilate, contract :: Int -> Int
dilate x = unsafeShiftL x 3
contract x = unsafeShiftR x 3

-- | assuming @l <= h@. Returns @h@ if the predicate is never @True@ over @[l..h)@
search :: (Int -> Bool) -> Int -> Int -> Int
search p = go where
  go l h
    | l == h    = l
    | p m       = go l m
    | otherwise = go (m+1) h
    where m = l + div (h-l) 2
{-# INLINE search #-}