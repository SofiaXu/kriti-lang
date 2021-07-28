module GoBasic.Lexer where

import Data.Char (isSpace)
import Data.List (unfoldr)
import Data.Maybe (maybeToList)
import Data.Scientific (Scientific, scientificP)
import Data.Text (Text)
import GHC.Generics
import Text.Parsec.Pos (SourcePos, incSourceLine, incSourceColumn, initialPos, newPos, sourceColumn, sourceLine, setSourceColumn)
import Text.ParserCombinators.ReadP (ReadP, gather, readP_to_S)
import Text.Read (lexP, readPrec_to_P)

import qualified Data.Text as T
import qualified Text.Read.Lex as L

data Token =
    StringLit Text
    -- ^ String Literal
  | Identifier Text
    -- ^ Identifier
  | NumLit Scientific
    -- ^ Number literal
  | BoolLit Bool
  | Bling
  | Colon
  | Dot
  | Comma
  | Eq'
  | GT'
  | LT'
  | And
  | Or
  -- | Member
  | CurlyOpen
  | CurlyClose
  | TemplateOpen
  | TemplateClose
  | SquareOpen
  | SquareClose
  | ParenOpen
  | ParenClose
  | Underscore
  | Assignment
  deriving (Show, Eq, Generic)

serialize :: Token -> Text
serialize = \case
    StringLit str   -> "\"" <> str <> "\""
    Identifier iden -> iden
    NumLit i        -> T.pack $ show i
    BoolLit True    -> "true"
    BoolLit False   -> "false"
    Bling           -> "$"
    Colon           -> ":"
    Dot             -> "."
    Comma           -> ","
    Eq'             -> "=="
    GT'             -> ">"
    LT'             -> "<"
    And             -> "&&"
    Or              -> "||"
    CurlyOpen       -> "{"
    CurlyClose      -> "}"
    TemplateOpen    -> "{{"
    TemplateClose   -> "}}"
    SquareOpen      -> "["
    SquareClose     -> "]"
    ParenOpen       -> "("
    ParenClose      -> ")"
    Underscore      -> "_"
    Assignment      -> ":="

data TokenExt = TokenExt { teType :: Token, tePos :: SourcePos }
  deriving (Show, Eq)

lexer :: Text -> [TokenExt]
lexer = unfoldr go . (, initialPos "sourceName") -- (b -> Maybe (a, b)) -> b -> [a]
  where
    go :: (Text, SourcePos) -> Maybe (TokenExt, (Text, SourcePos))
    go (t, pos)
      | T.null t = Nothing
      | Just s <- T.stripPrefix "true"  t = Just ((TokenExt (BoolLit True) pos), advance s pos "true")
      | Just s <- T.stripPrefix "false" t = Just ((TokenExt (BoolLit False) pos), advance s pos "false")
      | Just s <- T.stripPrefix "_"     t = Just ((TokenExt (Underscore) pos), advance s pos "_")
      | Just s <- T.stripPrefix "."     t = Just ((TokenExt (Dot) pos), advance s pos ".")
      | Just s <- T.stripPrefix ","     t = Just ((TokenExt (Comma) pos), advance s pos ",")
      | Just s <- T.stripPrefix "$"     t = Just ((TokenExt (Bling) pos), advance s pos "$")
      | Just s <- T.stripPrefix ":="    t = Just ((TokenExt (Assignment) pos), advance s pos ":=")
      | Just s <- T.stripPrefix ":"     t = Just ((TokenExt (Colon) pos), advance s pos ":")
      | Just s <- T.stripPrefix "=="    t = Just ((TokenExt (Eq') pos), advance s pos "==")
      | Just s <- T.stripPrefix ">"     t = Just ((TokenExt (GT') pos), advance s pos ">")
      | Just s <- T.stripPrefix "<"     t = Just ((TokenExt (LT') pos), advance s pos "<")
      | Just s <- T.stripPrefix "&&"    t = Just ((TokenExt (And) pos), advance s pos "&&")
      | Just s <- T.stripPrefix "||"    t = Just ((TokenExt (Or) pos), advance s pos "||")
      | Just s <- T.stripPrefix "{{"    t = Just ((TokenExt (TemplateOpen) pos), advance s pos "{{")
      | Just s <- T.stripPrefix "}}"    t = Just ((TokenExt (TemplateClose) pos), advance s pos "}}")
      | Just s <- T.stripPrefix "{"     t = Just ((TokenExt (CurlyOpen) pos), advance s pos "{")
      | Just s <- T.stripPrefix "}"     t = Just ((TokenExt (CurlyClose) pos), advance s pos "}")
      | Just s <- T.stripPrefix "["     t = Just ((TokenExt (SquareOpen) pos), advance s pos "[")
      | Just s <- T.stripPrefix "]"     t = Just ((TokenExt (SquareClose) pos), advance s pos "]")
      | Just s <- T.stripPrefix ")"     t = Just ((TokenExt (ParenClose) pos), advance s pos ")")
      | Just s <- T.stripPrefix "("     t = Just ((TokenExt (ParenOpen) pos), advance s pos "(")
      | Just (str, matched, s) <- stringLit t  = Just ((TokenExt (StringLit str) pos), advance s pos matched)
      | Just (str, matched, s) <- identifier t = Just ((TokenExt (Identifier str) pos), advance s pos matched)
      | Just (n, matched, s) <- numberLit t    = Just ((TokenExt (NumLit (realToFrac n)) pos), advance s pos matched)
      | otherwise = Nothing

    identifier :: Text -> Maybe (Text, Text, Text) -- (value, lit, remainder)
    identifier = fromRead (readPrec_to_P identLexeme 0) where
        identLexeme = do
          L.Ident s <- lexP
          pure (T.pack s)

    stringLit :: Text -> Maybe (Text, Text, Text) -- (value, lit, remainder)
    stringLit = fromRead (readPrec_to_P stringLexeme 0)
      where
        stringLexeme = do
          L.String s <- lexP
          pure (T.pack s)

    numberLit :: Text -> Maybe (Scientific, Text, Text) -- (value, lit, remainder)
    numberLit = fromRead scientificP

    fromRead :: ReadP a -> Text -> Maybe (a, Text, Text) -- (value, lit, remainder)
    fromRead rp t =
      let matchS = maxParsed <$> readP_to_S (gather rp)
       in case matchS (T.unpack t) of
            (((lit, value), rest):_) -> do
              pure (value, T.pack lit, T.pack rest)
            _ -> Nothing

    -- | Choose the parse result which consumed the maximum number of bytes.
    maxParsed :: [(a, String)] -> [(a, String)]
    maxParsed xs =
      let f (a, str) = \case
            Just (a', str') -> if length str < length str' then pure (a, str) else pure (a', str')
            Nothing -> pure (a, str)
      in maybeToList $ foldr f Nothing xs

    advance :: Text -> SourcePos -> Text -> (Text, SourcePos)
    advance t pos eaten =
      let (ws, rest) = T.span isSpace t
          col = sourceColumn pos + T.length eaten
          newSourcePos = T.foldl' f (newPos "sourceName" (sourceLine pos) col) ws
          f pos' '\n' = setSourceColumn (incSourceLine pos' 1) 0
          f pos' '\r' = pos'
          f pos' _ = incSourceColumn pos' 1
       in (rest, newSourcePos)
