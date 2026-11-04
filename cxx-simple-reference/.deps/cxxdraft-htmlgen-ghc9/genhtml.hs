-- SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>
-- SPDX-FileContributor: Eelis <eelis@eelis.net>
--
-- SPDX-License-Identifier: LicenseRef-cxxdraft-htmlgen-PublicDomain AND MIT

{-# OPTIONS_GHC -fno-warn-tabs #-}
{-# LANGUAGE LambdaCase, ViewPatterns, RecordWildCards, OverloadedStrings #-}

import Document (Draft(..))
import Load14882 (load14882)
import Prelude hiding ((++), (.), writeFile, readFile)
import System.Directory (createDirectoryIfMissing, setCurrentDirectory, getCurrentDirectory, copyFile)
import System.Environment (getArgs)
import Control.Monad (forM, forM_)
import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (SomeException, try, throwIO)
import Data.Text.IO (readFile)
import Util hiding (readFile)
import Toc (writeTocFiles)
import Pages (outputDir, PageStyle(..))
import SectionPages

data CmdLineArgs = CmdLineArgs
	{ repo :: FilePath
	, sectionFileStyle :: PageStyle
	, sectionToWrite :: Maybe String }

readCmdLineArgs :: [String] -> CmdLineArgs
readCmdLineArgs = \case
	[repo, read -> sectionFileStyle, sec] -> CmdLineArgs{sectionToWrite=Just sec, ..}
	[repo, read -> sectionFileStyle] -> CmdLineArgs{sectionToWrite=Nothing,..}
	[repo] -> CmdLineArgs{sectionFileStyle=WithExtension,sectionToWrite=Nothing,..}
	_ -> error "param: path/to/repo"

copyFileToDir :: FilePath -> FilePath -> IO ()
copyFileToDir d f = copyFile f (d ++ "/" ++ f)

simpleFilesToCopy :: [FilePath]
simpleFilesToCopy = [
    "expanded.css",
    "colored.css",
    "normative-only.css",
    "icon-light.png",
    "icon-dark.png"]

-- | Runs the actions concurrently and waits for all of them. Rethrows the
-- exception of the first failed action in list order, if any.
concurrently_ :: [IO ()] -> IO ()
concurrently_ acts = do
	vars <- forM acts $ \act -> do
		v <- newEmptyMVar
		_ <- forkIO (try act >>= putMVar v)
		return v
	results <- mapM takeMVar vars
	mapM_ (either (throwIO :: SomeException -> IO ()) return) results

main :: IO ()
main = do
	cwd <- getCurrentDirectory
	CmdLineArgs{..} <- readCmdLineArgs . getArgs

	extraMacros <- readFile "macros.tex"

	setCurrentDirectory $ repo ++ "/source"
	draft@Draft{..} <- load14882 extraMacros

	setCurrentDirectory cwd
	createDirectoryIfMissing True outputDir
	forM_ simpleFilesToCopy $ copyFileToDir outputDir
	case sectionToWrite of
		Just abbr -> writeSingleSectionFile sectionFileStyle draft abbr
		Nothing -> do
			let acts =
				[ writeTocFiles sectionFileStyle draft
				, writeCssFile
				, writeFiguresFile sectionFileStyle draft
				, writeFigureFiles sectionFileStyle draft
				, writeFootnotesFile sectionFileStyle draft
				, writeTablesFile sectionFileStyle draft
				, writeTableFiles sectionFileStyle draft
				] ++
				writeXrefDeltaFiles sectionFileStyle draft ++
				writeIndexFiles sectionFileStyle draft index ++
				writeSectionFiles sectionFileStyle draft

			((), took) <- measure $ concurrently_ acts
			putStrLn $ "Wrote files to " ++ outputDir ++ " in " ++ show (took * 1000) ++ "ms."
