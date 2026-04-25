@echo on
setlocal EnableDelayedExpansion

rem ----------------------------------------------------------
rem  Silent installer – all output is redirected to a log file
rem ----------------------------------------------------------
rem  Log file will be created next to the batch file for seperate processes and subprocesses
set "INSTALL_LOG=%~dp0install.log"
set "FASTAPI_LOG=%~dp0fastapi.log"
set "MCP_CONTEXT_LOG=%~dp0mcp_context_engineer.log"
set "DOCLING_MCP_LOG=%~dp0docling_mcp.log"
rem  Start a fresh log
type nul > "%INSTALL_LOG%"
type nul > "%FASTAPI_LOG%"
type nul > "%MCP_CONTEXT_LOG%"
type nul > "%DOCLING_MCP_LOG%"

rem Helper to write a line both to the log and (optionally) to the console
rem   Use   call :log "Your message"
goto :main
:log
    echo %*>>"%INSTALL_LOG%"
    goto :eof

:main
rem ----------------------------------------------------------
rem 1️⃣ Determine repo root (where this .bat lives)
rem ----------------------------------------------------------
set "REPO_ROOT=%~dp0"
if "%REPO_ROOT:~-1%"=="\" set "REPO_ROOT=%REPO_ROOT:~0,-1%"

call :log "=== Installing / Starting MCP for Docs ==="
call :log "Repo root: %REPO_ROOT%"

rem ----------------------------------------------------------
rem 2️⃣ Ensure `uv` is available
rem ----------------------------------------------------------
where uv >nul 2>nul
if errorlevel 1 (
    call :log "uv not found - installing uv..."
    powershell -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex" >nul 2>&1
) else (
    call :log "uv already installed."
)


rem ----------------------------------------------------------
rem **NEW SECTION – Ensure Git is installed**
rem ----------------------------------------------------------
where git >nul 2>nul
if errorlevel 1 (
    call :log "Git not found - downloading and installing Git for Windows..."

    rem ---- download the latest 64‑bit installer (you can pin a version if you wish) ----
    set "GIT_URL=https://github.com/git-for-windows/git/releases/download/v2.45.0.windows.1/Git-2.45.0-64-bit.exe"
    set "GIT_INSTALLER=%TEMP%\git-installer.exe"

    setlocal EnableDelayedExpansion
    powershell -Command "Invoke-WebRequest -Uri !GIT_URL! -OutFile !GIT_INSTALLER!" >nul 2>&1
    if errorlevel 1 (
        call :log "*** ERROR: Failed to download Git installer."
        goto :end
    )

    rem ---- silent install (no UI, default options) ----
    !GIT_INSTALLER! /VERYSILENT /NORESTART
    if errorlevel 1 (
        call :log "*** ERROR: Git installer returned a non‑zero exit code."
        goto :end
    )

    rem ---- clean up the installer file ----
    del /f /q "!GIT_INSTALLER!" >nul 2>&1
    call :log "Git installed successfully."
) else (
    call :log "Git already installed."
)


rem ----------------------------------------------------------
rem 3️⃣ Create *global* virtual environment (once)
rem ----------------------------------------------------------
set "VENV_DIR=%REPO_ROOT%\venv"
if not exist "%VENV_DIR%" (
    call :log "Creating virtual environment at %VENV_DIR% ..."
    uv venv "%VENV_DIR%" >nul 2>&1
) else (
    call :log "Virtual environment already exists - skipping creation."
)

rem ----------------------------------------------------------
rem 4️⃣ Activate the venv for the rest of the script
rem ----------------------------------------------------------
call "%VENV_DIR%\Scripts\activate.bat" >nul 2>&1

rem ----------------------------------------------------------
rem Copy .env into the venv so the MCP process can always find it
rem regardless of working directory at runtime
rem ----------------------------------------------------------
if exist "%REPO_ROOT%\.env" (
    copy /y "%REPO_ROOT%\.env" "%VENV_DIR%\Scripts\.env" >nul 2>&1
    call :log "Copied .env to venv Scripts directory."
) else (
    call :log "WARNING: No .env file found at %REPO_ROOT%\.env - API keys will not be available."
)

rem ----------------------------------------------------------
rem Install wheels & extra deps – only once
rem ----------------------------------------------------------
set "DEPS_SENTINEL=%VENV_DIR%\.deps_installed"
if not exist "%DEPS_SENTINEL%" (
    call :log "Installing required wheels and extra packages..."
    uv pip install ragdapi-0.1.0-py3-none-any.whl --no-deps >nul 2>&1
    uv pip install local_codebase_indexing-1.0.0-py3-none-any.whl >nul 2>&1
    uv pip install mcp_context_engineer-1.0.0-py3-none-any.whl >nul 2>&1
    uv pip install docling_mcp-1.0.0-py3-none-any.whl >nul 2>&1    
    uv pip install orbax-checkpoint --no-deps >nul 2>&1
    uv pip install tree-sitter-language-pack >nul 2>&1
    rem Touch sentinel so we know deps are installed
    type nul > "%DEPS_SENTINEL%"
) else (
    call :log "Dependencies already installed - skipping pip install."
)

rem ----------------------------------------------------------
rem 6️⃣ Launch the FastAPI server (runs __main__.py)
rem ----------------------------------------------------------
call :log "Starting FastAPI server..."
rem  `start ""` launches it in a new window; we hide that window by
rem  launching it via `cmd /c` and redirecting its own output to the log.
@REM "%VENV_DIR%\Scripts\python.exe" -m codebase_context_provider >> "%LOG%" 2>&1
@REM start "FASTAPI Server" cmd /c ""%VENV_DIR%\Scripts\python.exe" -m codebase_context_provider >> "%LOG%" 2>&1"
start "" /b cmd /c ""%VENV_DIR%\Scripts\python.exe" -m codebase_context_provider >> "%FASTAPI_LOG%" 2>&1"

rem ----------------------------------------------------------
rem 6️⃣‑B  Launch the MCP server (FastMCP) – also fire‑and‑forget
rem ----------------------------------------------------------
call :log "Starting MCP (FastMCP) server..."
rem  The MCP server talks over stdio, so we just run it in the background.
rem  Its stdout is also redirected to the same log file.
@REM "%VENV_DIR%\Scripts\python.exe" -m mcp_context_engineer.main >> "%LOG%" 2>&1
@REM start "MCP Server" cmd /c ""%VENV_DIR%\Scripts\python.exe" -m mcp_context_engineer.main >> "%LOG%" 2>&1"
start "" /b cmd /c ""%VENV_DIR%\Scripts\python.exe" -m mcp_context_engineer.main >> "%MCP_CONTEXT_LOG%" 2>&1"


rem ----------------------------------------------------------
rem  Launch the DOCLING MCP server
rem ----------------------------------------------------------
call :log "Starting Docling MCP server..."
start "" /b cmd /c ""%VENV_DIR%\Scripts\python.exe" -m docling_mcp.main >> "%DOCLING_MCP_LOG%" 2>&1"


rem ----------------------------------------------------------
rem  Create Continue MCP config
rem ----------------------------------------------------------
rem The continue will make the server up  else how will it know if the server is running or not.
set "CONTINUE_DIR=%USERPROFILE%\.continue"
set "MCP_DIR=%CONTINUE_DIR%\mcpServers"

if not exist "%CONTINUE_DIR%" mkdir "%CONTINUE_DIR%"
if not exist "%MCP_DIR%" mkdir "%MCP_DIR%"

set "CONFIG_FILE=%MCP_DIR%\LocalXploreMCP.yaml"
set "PYTHON_EXE=%VENV_DIR%\Scripts\python.exe"

(
echo name: LocalXploreMCP
echo version: 0.1.0
echo schema: v1
echo mcpServers:
echo   - name: LocalXploreMCP
echo     type: streamable-http
echo     url: http://127.0.0.1:8080/mcp
echo     connectionTimeout: 240000
echo   - name: DoclingMCP
echo     type: streamable-http
echo     url: http://127.0.0.1:9090/mcp
echo     connectionTimeout: 240000
) > "%CONFIG_FILE%"

call :log "Continue MCP config created at %CONFIG_FILE%"

rem ----------------------------------------------------------
rem 7️⃣ Register a Windows Scheduled Task (run at logon)
rem ----------------------------------------------------------
set "TASK_NAME=MCP-Docs-Server"
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
if not errorlevel 1 (
    call :log "Scheduled task \"%TASK_NAME%\" already exists - nothing to do."
) else (
    call :log "Creating scheduled task \"%TASK_NAME%\" to run this installer at logon..."
    schtasks /Create ^
        /TN "%TASK_NAME%" ^
        /TR "\"%~dp0install.bat\"" ^
        /SC ONLOGON ^
        /RL HIGHEST ^
        /F >nul 2>&1
    if not errorlevel 1 (
        call :log "Task created successfully."
    ) else (
        call :log "*** ERROR creating scheduled task. You may need admin rights."
    )
)

rem ----------------------------------------------------------
rem 8️⃣ Final message (still written only to the log)
rem ----------------------------------------------------------
call :log ""
call :log "=== Installation / startup complete! ==="
call :log "The FastAPI server should be reachable at http://localhost:8000"
call :log "The FastMCP server should be reachable at http://127.0.0.1:8080/mcp"
call :log "The Docling MCP server should be reachable at http://127.0.0.1:9090/mcp"
call :log "All details are in %INSTALL_LOG%"
call :log "FastAPI logs are in %FASTAPI_LOG%"
call :log "MCP Context Engineer logs are in %MCP_CONTEXT_LOG%"
call :log "Docling MCP logs are in %DOCLING_MCP_LOG%"

endlocal
exit /b 0