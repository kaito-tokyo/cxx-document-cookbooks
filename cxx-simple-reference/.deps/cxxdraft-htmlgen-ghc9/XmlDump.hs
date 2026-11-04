-- SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>
--
-- SPDX-License-Identifier: MIT

{-# LANGUAGE OverloadedStrings, RankNTypes, RecordWildCards, ScopedTypeVariables #-}

-- | Writes the loaded draft as XML, following the Haskell data structure.
--
-- Every value becomes one element:
--
-- * a constructor becomes an element named after it; a record constructor
--   wraps each field in an element named after the field, other
--   constructors list their arguments in order;
-- * 'Text', 'String', 'Int' and 'Char' become a 'Text', 'String', 'Int' or
--   'Char' element holding the value as text; a character that XML 1.0
--   does not allow (such as the control characters htmlgen uses as markers
--   in index entries) is written as an empty 'Char' element whose 'code'
--   attribute is its code point;
-- * lists become a 'List' element, tuples a 'Tuple' element, 'Map' and
--   'IntMap' a 'Map' or 'IntMap' element holding a 'List' of key/value
--   'Tuple's.
--
-- Fields that point back to an enclosing section ('sectionRefFields'), and
-- 'labels' of the draft, hold each 'Section' as a 'SectionRef' element with
-- the section's abbreviation, because writing them in full would never end.
-- 'abbrMap' is a function and is not written.
module XmlDump (draftToXml) where

import Data.Data
import Data.Text (Text)
import qualified Data.Map as Map
import qualified Data.Text as Text
import qualified Text.XML as X
import Document (Draft(..), Section(..))

data Mode = Full | SectionRef

sectionRefFields :: [String]
sectionRefFields = ["parents", "paraSection", "tableSection", "figureSection", "formulaSection"]

draftToXml :: Draft -> X.Document
draftToXml Draft{..} = X.Document (X.Prologue [] Nothing []) root []
  where
    root = X.Element (X.Name "Draft" Nothing Nothing) Map.empty
        [ field "commitUrl" (value Full commitUrl)
        , field "chapters" (value Full chapters)
        , field "index" (value Full index)
        , field "indexEntryMap" (value Full indexEntryMap)
        , field "indexEntriesByPath" (value Full indexEntriesByPath)
        , field "xrefDelta" (value Full xrefDelta)
        , field "labels" (value SectionRef labels)
        ]

value :: forall a. Data a => Mode -> a -> X.Node
value mode x
    | Just (t :: Text) <- cast x = leaf "Text" t
    | Just (s :: String) <- cast x = leaf "String" (Text.pack s)
    | SectionRef <- mode, Just (s :: Section) <- cast x = leaf "SectionRef" (abbreviation s)
    | otherwise = case constrRep c of
        CharConstr ch -> leaf "Char" (Text.singleton ch)
        IntConstr _ -> leaf typeName (Text.pack (showConstr c))
        FloatConstr _ -> leaf typeName (Text.pack (showConstr c))
        AlgConstr _
            | name `elem` ["(:)", "[]"] -> element "List" (listItems mode x)
            | isTuple name -> element "Tuple" (gmapQ (value mode) x)
            | name == "fromList" -> element typeName (gmapQ (value mode) x)
            | null fields -> element name (gmapQ (value mode) x)
            | otherwise -> element name (zipWith fieldValue fields (gmapQ (\y m -> value m y) x))
  where
    c = toConstr x
    name = Text.pack (showConstr c)
    fields = constrFields c
    typeName = Text.pack (reverse (takeWhile (/= '.') (reverse (dataTypeName (dataTypeOf x)))))
    isTuple n = Text.length n > 2 && Text.head n == '(' && Text.all (`elem` ("(,)" :: String)) n
    fieldValue f v = field (Text.pack f) (v (if f `elem` sectionRefFields then SectionRef else mode))

listItems :: Data a => Mode -> a -> [X.Node]
listItems mode x
    | showConstr (toConstr x) == "(:)" = gmapQi 0 (value mode) x : gmapQi 1 (listItems mode) x
    | otherwise = []

element :: Text -> [X.Node] -> X.Node
element n children = X.NodeElement (X.Element (X.Name n Nothing Nothing) Map.empty children)

field :: Text -> X.Node -> X.Node
field n v = element n [v]

leaf :: Text -> Text -> X.Node
leaf n t = element n (content t)

content :: Text -> [X.Node]
content t = case Text.break (not . xmlChar) t of
    (a, rest) -> case Text.uncons rest of
        Nothing -> [X.NodeContent a | not (Text.null a)]
        Just (ch, more) ->
            [X.NodeContent a | not (Text.null a)] ++ codePoint ch : content more
  where
    codePoint ch = X.NodeElement (X.Element (X.Name "Char" Nothing Nothing)
        (Map.singleton (X.Name "code" Nothing Nothing) (Text.pack (show (fromEnum ch)))) [])

-- | Whether XML 1.0 allows the character in text.
xmlChar :: Char -> Bool
xmlChar ch = ch `elem` ("\t\n\r" :: String)
    || (ch >= '\x20' && ch <= '\xD7FF')
    || (ch >= '\xE000' && ch <= '\xFFFD')
    || ch >= '\x10000'
