@echo off

echo [ Building ZZT.DAT ] >> BUILD.LOG
cd DOC
..\BUILD\DATPACK.EXE /C ..\BUILD\ZZT.DAT *.* >> BUILD.LOG
if errorlevel 1 goto error
cd ..
goto done

:error
echo.
echo [ Error detected! Stopping. ]
:done
exit
