@echo off

echo [ Building DATPACK.EXE ] >> BUILD.LOG
TPC /B /Q /EBUILD TOOLS\DATPACK.PAS >> BUILD.LOG
if errorlevel 1 goto error

echo [ Building ZZT.DAT ] >> BUILD.LOG
cd DOC
..\BUILD\DATPACK.EXE /C ..\BUILD\ZZT.DAT *.* >> BUILD.LOG
if errorlevel 1 goto error
cd ..

echo [ Building ZZT.EXE ] >> BUILD.LOG
TPC /B /Q /EBUILD /GD /ISRC /USRC %COMPARGS% SRC\ZZT.PAS >> BUILD.LOG
if errorlevel 1 goto error
goto done

:error
echo.
echo [ Error detected! Stopping. ]
:done
exit
