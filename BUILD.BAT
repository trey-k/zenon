@echo off
if not exist BIN mkdir BIN
del /Q BIN\*.*
if not exist DIST mkdir DIST
del /Q DIST\*.*
echo.
echo 	[ Building DATPACK.EXE ]
call :logger TPC /B /EBIN TOOLS\DATPACK.PAS
echo 	[ Building ZZT.DAT ]
cd DOC
call :logger ..\BIN\DATPACK.EXE /C ..\BIN\ZZT.DAT *.*
cd ..
echo 	[ Building ZZT.EXE ]
call :logger TPC /B /EBIN /GD /ISRC /USRC SRC\ZZT.PAS
echo 	[ Compressing ZZT.EXE ]
cd BIN
call :logger ..\TOOLS\LZEXE.EXE ZZT.EXE
cd ..
echo 	[ Creating DIST/ ]
echo.
copy BIN\ZZT.EXE DIST\ZZT.EXE
copy BIN\ZZT.DAT DIST\ZZT.DAT
copy RES\ZZT.CFG DIST\ZZT.CFG
copy RES\DEMO.ZZT DIST\DEMO.ZZT
copy LICENSE.TXT DIST\LICENSE.TXT
del LOG.TXT
goto done
exit
:logger
echo.
start /wait /MIN %~dp0\LOGGER.BAT %*
type %~dp0\LOG.TXT
echo.
:done