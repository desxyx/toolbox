@echo off
setlocal
set SRC=%~dp0main.cpp
set OUT=%~dp0read_gui.exe
set GPP=C:\msys64\mingw64\bin\g++.exe
set CC1DIR=C:\msys64\mingw64\lib\gcc\x86_64-w64-mingw32\15.2.0
set ASDIR=C:\msys64\mingw64\x86_64-w64-mingw32\bin

rem Put cc1plus/as dirs first so they find the right zlib1.dll (not the system one)
set PATH=%CC1DIR%;%ASDIR%;C:\msys64\mingw64\bin;C:\msys64\usr\bin;%PATH%

echo Compiling %SRC%
"%GPP%" -O2 -mwindows -municode -static-libgcc -static-libstdc++ "%SRC%" -lole32 -loleaut32 -luuid -lcomdlg32 -lshell32 -Wl,-Bstatic,--whole-archive -lwinpthread -Wl,--no-whole-archive,-Bdynamic -o "%OUT%"
if %ERRORLEVEL% == 0 (
    echo [OK] Built: %OUT%
) else (
    echo [FAIL] Compilation error
)
endlocal
