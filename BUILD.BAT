@echo off
if not exist BIN mkdir BIN
del BIN\*.*
if not exist DIST mkdir DIST
del DIST\*.*
echo.
echo [ Building DATPACK.EXE ]
echo.
start /wait /MIN logger.bat C:\TP\TPC /B /EBIN TOOLS\DATPACK.PAS
type log.txt
echo.
echo [ Building ZZT.DAT ]
echo.
cd DOC
start /wait /MIN ..\logger.bat ..\BIN\DATPACK.EXE /C ..\BIN\ZZT.DAT *.*
cd ..
type log.txt
echo.
echo [ Building ZZT.EXE ]
echo.
start /wait /MIN logger.bat C:\TP\TPC /B /EBIN /GD /ISRC /USRC SRC\ZZT.PAS
type log.txt
echo.
echo [ Compressing ZZT.EXE ]
echo.
cd BIN
start /wait /MIN ..\logger.bat ..\TOOLS\LZEXE.EXE ZZT.EXE
cd ..
type log.txt

echo.
echo [ Creating DIST/ ]
echo.

copy BIN\ZZT.EXE DIST\ZZT.EXE
copy BIN\ZZT.DAT DIST\ZZT.DAT
copy RES\ZZT.CFG DIST\ZZT.CFG
copy RES\DEMO.ZZT DIST\DEMO.ZZT
copy LICENSE.TXT DIST\LICENSE.TXT

