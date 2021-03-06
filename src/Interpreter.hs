{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TupleSections #-}

module Interpreter where

import AST
import Control.Monad (foldM, (>=>))
import Data.Bifunctor (bimap, first)
import Util.Parsing (Result (..), successOr)

interpret :: Expression -> Result String Expression
interpret expr = reduce prelude (Appl [expr, Quote (ID "main")])

reduce :: Env -> Expression -> Result String Expression
reduce env (Appl items) = do
  reduced <- mapM (reduce env) items
  Trace (show items) $ foldM (apply env) (head reduced) (tail reduced)
reduce env (ID id) = case lookup id env of
  Just expr -> Success expr
  Nothing -> Error $ id ++ " not in scope. Env: " ++ show env
reduce env (Unquote (Quote expr)) = reduce env expr
reduce env (Unquote other) = Error $ "Cannot unquote " ++ show other
reduce _ other = Success other

apply :: Env -> Expression -> Expression -> Result String Expression
apply env (TypeVal _) x = Success x -- Ignore type annotations at runtime
apply env (Dict vals) id = do
  vals' <- mapM (\(k, v) -> (,v) <$> reduce env k) vals
  case lookup id vals' of
    Just x -> reduce (levelenv vals' ++ env) x
    Nothing -> Error $ "Value " ++ show id ++ " not present in dictionary."
apply _ (Internal Add) (Nbr x) = Success $ Internal $ Adding x
apply _ (Internal (Adding x)) (Nbr y) = Success $ Nbr $ x + y
apply _ (Internal Concat) (Quote (Appl chars)) = Internal . Concatenating <$> mapM getExprChar chars
apply _ (Internal (Concatenating a)) (Quote (Appl b)) = Appl . map Ch . (++ a) <$> mapM getExprChar b
apply _ (Internal Head) (Appl li) = Success $ head li
apply _ (Internal Tail) (Appl li) = Success $ Appl $ tail li
apply _ (Internal Len) (Appl li) = Success $ Nbr $ length li
apply _ (Internal Lambda0) (Quote (ID id)) = Success $ Internal $ Lambda1 id
apply env (Internal (Lambda1 id)) (Quote expr) = Success $ Internal $ Lambda2 id expr env
apply env (Internal (Lambda2 id expr eenv)) val = reduce ((id, val) : eenv) expr
apply _ (Internal ElemOf0) (Dict dict) = Success $ Internal $ ElemOf1 dict
apply env (Internal (ElemOf1 dict)) id = do
  vals' <- mapM (\(k, v) -> (,v) <$> reduce env k) dict
  case lookup id vals' of
    Just x -> Success $ Nbr 1
    Nothing -> Success $ Nbr 0
apply _ (Internal ITDict) (Dict ts) = Success $ TypeVal (TDict ts)
apply _ (Internal ITDictLen) (Nbr len) = Success $ TypeVal (TDictLen len)
apply _ (Internal ITAppl) (Appl ts) = Success $ TypeVal (TAppl ts)
apply _ (Internal ITApplLen) (Nbr len) = Success $ TypeVal (TApplLen len)
apply _ (Internal ITUnion) (Appl ts) = Success $ TypeVal (TUnion ts)
apply _ (Internal ITQuote) (TypeVal t) = Success $ TypeVal (TQuote (TypeVal t))
apply _ (Internal ITFn0) (TypeVal ta) = Success $ Internal (ITFn1 ta)
apply _ (Internal (ITFn1 a)) (TypeVal b) = Success $ TypeVal (TFn (TypeVal a) (TypeVal b))
apply _ (Internal ITID) (Quote (ID id)) = Success $ TypeVal (TID id)
apply env a@(Appl _) b = reduce env a >>= \a' -> apply env a' b
apply env a b@(Appl _) = reduce env b >>= \b' -> apply env a b'
apply _ a b = Error $ "Cannot apply " ++ show b ++ " to " ++ show a

getExprChar :: Expression -> Result String Char
getExprChar (Ch char) = Success char
getExprChar other = Error $ show other ++ " is not a char"
