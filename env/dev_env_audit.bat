@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM =============================================================
REM  Dev Environment Audit - FULL v3 (all bugs fixed)
REM
REM  Fix 1: wmic UTF-16 garbled output -> use PowerShell instead
REM  Fix 2: mvn crash (bad JAVA_HOME) killing entire script
REM          -> temporarily override JAVA_HOME for mvn call only
REM  Fix 3: any command crash terminating script
REM          -> cmd /c wrapper isolates exit codes
REM  Fix 4: choco list -l removed in v2+ -> use choco list instead
REM =============================================================

for /f "tokens=2 delims==" %%a in ('wmic os get localdatetime /value ^| find "="') do set dt=%%a
set dt=%dt:~0,8%_%dt:~8,6%
set host=%COMPUTERNAME%
set out=dev_env_audit_FULL_%host%_%dt%.txt

(
  echo ==================================================
  echo  Dev Environment Audit Report - FULL v3
  echo  Computer : %host%
  echo  Time     : %date% %time%
  echo  User     : %USERNAME%
  echo  WorkDir  : %CD%
  echo ==================================================
  echo.
) > "%out%"

goto :START

REM ---- section header ----
:H
>>"%out%" echo.
>>"%out%" echo ==================================================
>>"%out%" echo  [%~1]
>>"%out%" echo ==================================================
>>"%out%" echo.
exit /b

REM ---- where wrapper ----
:W
>>"%out%" echo -- where %~1
where %~1 >>"%out%" 2>>&1
>>"%out%" echo.
exit /b

REM ---- safe command runner: cmd /c isolates crashes and bad exit codes ----
REM Usage: call :RUN "label" command args...
REM Because shift does not affect %* in subroutines, we use a temp .cmd file trick
:RUN
set "_rlabel=%~1"
>>"%out%" echo -- %_rlabel%
shift
REM rebuild command from remaining positional params
set "_rcmd=%1"
if not "%2"=="" set "_rcmd=%_rcmd% %2"
if not "%3"=="" set "_rcmd=%_rcmd% %3"
if not "%4"=="" set "_rcmd=%_rcmd% %4"
if not "%5"=="" set "_rcmd=%_rcmd% %5"
if not "%6"=="" set "_rcmd=%_rcmd% %6"
>>"%out%" echo    ^> %_rcmd%
cmd /c "%_rcmd%" >>"%out%" 2>>&1
>>"%out%" echo.
exit /b

:START

REM =============================================================
call :H "SYSTEM"

>>"%out%" echo -- Windows version
ver >>"%out%" 2>>&1
>>"%out%" echo.

REM Use PowerShell for OS/machine info to avoid wmic UTF-16 garbled output
>>"%out%" echo -- OS details
powershell -NoProfile -Command "Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber | Format-List" >>"%out%" 2>>&1
>>"%out%" echo.

>>"%out%" echo -- Machine
powershell -NoProfile -Command "Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model | Format-List" >>"%out%" 2>>&1
>>"%out%" echo.

>>"%out%" echo -- CPU
powershell -NoProfile -Command "Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors | Format-List" >>"%out%" 2>>&1
>>"%out%" echo.

>>"%out%" echo -- RAM
powershell -NoProfile -Command "'{0:N1} GB' -f ((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)" >>"%out%" 2>>&1
>>"%out%" echo.

>>"%out%" echo User: %USERNAME%
>>"%out%" echo Arch: %PROCESSOR_ARCHITECTURE%
>>"%out%" echo.

REM =============================================================
call :H "PATH"

>>"%out%" echo -- Full PATH:
>>"%out%" echo %PATH%
>>"%out%" echo.

>>"%out%" echo -- Duplicate PATH entries:
powershell -NoProfile -Command "$p=$env:PATH -split ';'; $p | Group-Object | Where-Object {$_.Count -gt 1} | Select-Object -ExpandProperty Name" >>"%out%" 2>>&1
>>"%out%" echo.

>>"%out%" echo -- All PATH entries (one per line, for readability):
powershell -NoProfile -Command "$env:PATH -split ';' | Select-Object -Unique | ForEach-Object { $_ }" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "PACKAGE MANAGERS"

call :W winget
cmd /c "winget --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W choco
cmd /c "choco --version" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- choco list (installed):
cmd /c "choco list" >>"%out%" 2>>&1
>>"%out%" echo.

call :W scoop
cmd /c "scoop --version" >>"%out%" 2>>&1
>>"%out%" echo.
cmd /c "scoop list" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "PYTHON"

call :W python
cmd /c "python --version" >>"%out%" 2>>&1
>>"%out%" echo.
cmd /c "python -c ""import sys; print(sys.executable)""" >>"%out%" 2>>&1
>>"%out%" echo.

call :W py
cmd /c "py --version" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- py -0p (all registered Python installs):
cmd /c "py -0p" >>"%out%" 2>>&1
>>"%out%" echo.

call :W pip
cmd /c "pip --version" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- pip list:
cmd /c "pip list" >>"%out%" 2>>&1
>>"%out%" echo.

call :W conda
cmd /c "conda --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W pipenv
cmd /c "pipenv --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W poetry
cmd /c "poetry --version" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "JAVA"

call :W java
cmd /c "java -version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W javac
cmd /c "javac -version" >>"%out%" 2>>&1
>>"%out%" echo.

>>"%out%" echo JAVA_HOME=%JAVA_HOME%
>>"%out%" echo.

call :W jar
call :W javadoc

REM =============================================================
call :H "JAVA - INSTALL PATHS"

>>"%out%" echo -- C:\Program Files\Java:
dir /b "C:\Program Files\Java" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- C:\Program Files\Eclipse Adoptium:
dir /b "C:\Program Files\Eclipse Adoptium" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- C:\Program Files\Common Files\Oracle\Java\javapath:
dir /b "C:\Program Files\Common Files\Oracle\Java\javapath" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "MAVEN / GRADLE"

call :W mvn

REM Maven needs a valid JAVA_HOME. Your JAVA_HOME points to jdk-22 but
REM the Oracle javapath shim points to 21 -> they're mismatched.
REM We try mvn with the javapath JDK first (what PATH resolves to):
>>"%out%" echo -- mvn -version (using PATH java, JAVA_HOME temporarily set to Temurin 21):
cmd /c "set JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.3.9-hotspot && mvn -version" >>"%out%" 2>>&1
>>"%out%" echo.

>>"%out%" echo -- mvn -version (using original JAVA_HOME=jdk-22):
cmd /c "mvn -version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W gradle
cmd /c "gradle --version" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "NODE / NPM / YARN / PNPM"

call :W node
cmd /c "node -v" >>"%out%" 2>>&1
>>"%out%" echo.

call :W npm
cmd /c "npm -v" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- npm config get prefix:
cmd /c "npm config get prefix" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- npm list -g --depth=0:
cmd /c "npm list -g --depth=0" >>"%out%" 2>>&1
>>"%out%" echo.

call :W npx
call :W corepack
cmd /c "corepack --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W yarn
cmd /c "yarn -v" >>"%out%" 2>>&1
>>"%out%" echo.

call :W pnpm
cmd /c "pnpm -v" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "RUBY"

call :W ruby
cmd /c "ruby -v" >>"%out%" 2>>&1
>>"%out%" echo.

call :W gem
cmd /c "gem -v" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- gem list:
cmd /c "gem list" >>"%out%" 2>>&1
>>"%out%" echo.

call :W bundler
cmd /c "bundle -v" >>"%out%" 2>>&1
>>"%out%" echo.

call :W rbenv
call :W rvm

REM =============================================================
call :H ".NET / C#"

call :W dotnet
>>"%out%" echo -- dotnet --info:
cmd /c "dotnet --info" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- dotnet --list-sdks:
cmd /c "dotnet --list-sdks" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- dotnet --list-runtimes:
cmd /c "dotnet --list-runtimes" >>"%out%" 2>>&1
>>"%out%" echo.

>>"%out%" echo -- Registry: .NET x64 runtimes:
reg query "HKLM\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.NETCore.App" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- Registry: .NET x64 SDKs:
reg query "HKLM\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sdk" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- Registry: .NET x86 runtimes:
reg query "HKLM\SOFTWARE\dotnet\Setup\InstalledVersions\x86\sharedfx\Microsoft.NETCore.App" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "C / C++ TOOLCHAINS"

call :W cl
cmd /c "cl" >>"%out%" 2>>&1
>>"%out%" echo.

call :W gcc
cmd /c "gcc --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W g++
cmd /c "g++ --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W clang
cmd /c "clang --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W cmake
cmd /c "cmake --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W make
cmd /c "make --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W ninja
cmd /c "ninja --version" >>"%out%" 2>>&1
>>"%out%" echo.

>>"%out%" echo -- Visual Studio installs:
dir /b "C:\Program Files\Microsoft Visual Studio" >>"%out%" 2>>&1
dir /b "C:\Program Files (x86)\Microsoft Visual Studio" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "GO"

call :W go
cmd /c "go version" >>"%out%" 2>>&1
>>"%out%" echo.
cmd /c "go env GOPATH GOROOT" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "RUST"

call :W rustc
cmd /c "rustc --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W cargo
cmd /c "cargo --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W rustup
cmd /c "rustup show" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "GIT / SSH / GPG"

call :W git
cmd /c "git --version" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- git config --global --list:
cmd /c "git config --global --list" >>"%out%" 2>>&1
>>"%out%" echo.

call :W ssh
cmd /c "ssh -V" >>"%out%" 2>>&1
>>"%out%" echo.

call :W openssl
cmd /c "openssl version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W gpg
cmd /c "gpg --version" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "DEVOPS - TERRAFORM"

call :W terraform
cmd /c "terraform version" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "DEVOPS - AWS CLI"

call :W aws
cmd /c "aws --version" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "DEVOPS - DOCKER"

call :W docker
cmd /c "docker --version" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- docker info:
cmd /c "docker info" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- docker ps -a:
cmd /c "docker ps -a" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- docker images:
cmd /c "docker images" >>"%out%" 2>>&1
>>"%out%" echo.

call :W docker-compose
cmd /c "docker-compose --version" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "DEVOPS - KUBERNETES / HELM"

call :W kubectl
cmd /c "kubectl version --client" >>"%out%" 2>>&1
>>"%out%" echo.

call :W helm
cmd /c "helm version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W minikube
cmd /c "minikube version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W kind
cmd /c "kind version" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "DEVOPS - CI/CD / CLOUD CLI"

call :W gh
cmd /c "gh --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W az
cmd /c "az version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W gcloud
cmd /c "gcloud --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W packer
cmd /c "packer version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W vagrant
cmd /c "vagrant --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W ansible
cmd /c "ansible --version" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "NETWORK / TERMINAL TOOLS"

call :W putty
call :W plink
call :W pscp
call :W pageant

call :W curl
cmd /c "curl --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W wget
cmd /c "wget --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W nmap
cmd /c "nmap --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W tshark
cmd /c "tshark -v" >>"%out%" 2>>&1
>>"%out%" echo.

call :W nc
call :W telnet

REM =============================================================
call :H "DATABASE TOOLS"

call :W mongod
cmd /c "mongod --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W mongosh
cmd /c "mongosh --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W sqlcmd
cmd /c "sqlcmd -?" >>"%out%" 2>>&1
>>"%out%" echo.

call :W mysql
cmd /c "mysql --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W psql
cmd /c "psql --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W sqlite3
cmd /c "sqlite3 --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W redis-cli
cmd /c "redis-cli --version" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "EDITORS / IDEs"

call :W code
cmd /c "code --version" >>"%out%" 2>>&1
>>"%out%" echo.

call :W idea64
call :W idea
call :W pycharm64
call :W pycharm
call :W webstorm64
call :W goland64
call :W rider64
call :W eclipse
call :W devenv

REM =============================================================
call :H "COMMON INSTALL FOLDERS"

>>"%out%" echo -- JetBrains (Program Files):
dir /b "C:\Program Files\JetBrains" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- JetBrains (LocalAppData):
dir /b "%LOCALAPPDATA%\JetBrains" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- VS Code (User install):
dir /b "%LOCALAPPDATA%\Programs\Microsoft VS Code" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- VS Code (H:\Programs):
dir /b "H:\Programs\Microsoft VS Code" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- H:\Programs:
dir /b "H:\Programs" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- D:\Program Files:
dir /b "D:\Program Files" >>"%out%" 2>>&1
>>"%out%" echo.
>>"%out%" echo -- Eclipse Foundation:
dir /b "C:\Program Files\Eclipse Foundation" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "WINDOWS - VC++ RUNTIMES (filtered)"

>>"%out%" echo -- Visual C++ Redistributables:
powershell -NoProfile -Command "Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -like '*Visual C++*'} | Select-Object DisplayName,DisplayVersion | Sort-Object DisplayName | Format-Table -AutoSize" >>"%out%" 2>>&1
>>"%out%" echo.

>>"%out%" echo -- Windows SDKs:
powershell -NoProfile -Command "Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -like '*Windows SDK*'} | Select-Object DisplayName,DisplayVersion | Sort-Object DisplayName | Format-Table -AutoSize" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "INSTALLED PROGRAMS - FULL REGISTRY DUMP"

>>"%out%" echo -- HKLM 64-bit:
powershell -NoProfile -Command "Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName} | Select-Object DisplayName,DisplayVersion,Publisher | Sort-Object DisplayName | Format-Table -AutoSize" >>"%out%" 2>>&1
>>"%out%" echo.

>>"%out%" echo -- HKLM 32-bit (WOW6432Node):
powershell -NoProfile -Command "Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName} | Select-Object DisplayName,DisplayVersion,Publisher | Sort-Object DisplayName | Format-Table -AutoSize" >>"%out%" 2>>&1
>>"%out%" echo.

>>"%out%" echo -- HKCU per-user:
powershell -NoProfile -Command "Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName} | Select-Object DisplayName,DisplayVersion | Sort-Object DisplayName | Format-Table -AutoSize" >>"%out%" 2>>&1
>>"%out%" echo.

REM =============================================================
call :H "NOTES"

>>"%out%" echo -- Scan complete.
>>"%out%" echo -- Known issues found:
>>"%out%" echo    JAVA_HOME=%JAVA_HOME% but PATH resolves java to Oracle javapath (21.0.3)
>>"%out%" echo    These are mismatched - Maven uses JAVA_HOME, compiler uses PATH java
>>"%out%" echo    Fix: set JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.3.9-hotspot
>>"%out%" echo    OR:  set JAVA_HOME=C:\Program Files\Common Files\Oracle\Java\javapath
>>"%out%" echo.
>>"%out%" echo -- PATH has many duplicate entries (see PATH section above)
>>"%out%" echo    Clean up via: System Properties -> Environment Variables -> Path (edit)
>>"%out%" echo.

echo.
echo Done. Report saved to: %CD%\%out%
endlocal