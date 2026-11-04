-- SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>
--
-- SPDX-License-Identifier: MIT

-- | cxxdraft-xml path/to/draft output.xml
--
-- Loads the draft like cxxdraft-htmlgen and writes its document structure
-- as XML (see XmlDump). Run it from this directory, which holds macros.tex.

import Data.Text.IO (readFile)
import Prelude hiding (readFile)
import System.Directory (getCurrentDirectory, setCurrentDirectory)
import System.Environment (getArgs)
import Conduit (runConduitRes, yieldMany, sinkFile, (.|))
import Data.Default.Class (def)
import Text.XML.Stream.Render (renderBytes)
import Load14882 (load14882)
import XmlDump (draftToEvents)

main :: IO ()
main = do
    args <- getArgs
    (repo, out) <- case args of
        [r, o] -> return (r, o)
        _ -> ioError (userError "usage: cxxdraft-xml path/to/draft output.xml")
    extraMacros <- readFile "macros.tex"
    cwd <- getCurrentDirectory
    setCurrentDirectory (repo ++ "/source")
    draft <- load14882 extraMacros
    setCurrentDirectory cwd
    runConduitRes $ yieldMany (draftToEvents draft) .| renderBytes def .| sinkFile out
