@echo off
setlocal
set "MOVIENOOK_ROOT=%~dp0"
where docker >nul 2>&1
if errorlevel 1 (
  echo MovieNook needs Docker Desktop. Install it from https://www.docker.com/products/docker-desktop/
  pause
  exit /b 1
)
docker info >nul 2>&1
if errorlevel 1 (
  if exist "%ProgramFiles%\Docker\Docker\Docker Desktop.exe" start "" "%ProgramFiles%\Docker\Docker\Docker Desktop.exe"
  echo Waiting for Docker Desktop...
  for /L %%I in (1,1,60) do (
    docker info >nul 2>&1 && goto docker_ready
    timeout /t 2 /nobreak >nul
  )
  echo Docker Desktop did not become ready.
  pause
  exit /b 1
)
:docker_ready
set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%BASH_EXE%" set "BASH_EXE=%LocalAppData%\Programs\Git\bin\bash.exe"
if not exist "%BASH_EXE%" (
  echo MovieNook needs Git for Windows and Docker Desktop.
  echo Install Git from https://git-scm.com/download/win and then double-click MovieNook.cmd again.
  pause
  exit /b 1
)
"%BASH_EXE%" -lc "cd \"$(cygpath -u '%MOVIENOOK_ROOT%')\" && ./MovieNook.sh"
if errorlevel 1 pause
