@echo off
chcp 936 >nul
title 股票分析 - Web 工作台
cd /d "%~dp0"
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

if not exist ".venv\Scripts\python.exe" (
    echo [错误] 没有找到 .venv 虚拟环境。
    echo        请先在项目目录执行依赖安装。
    echo.
    pause
    exit /b 1
)

rem 如果 8000 端口已被占用，说明服务已在运行，直接打开浏览器，不再重复启动
powershell -NoProfile -Command "$c=New-Object Net.Sockets.TcpClient; try{$c.Connect('127.0.0.1',8000); $c.Close(); exit 0}catch{exit 1}" >nul 2>&1
if errorlevel 1 goto start_server

echo ============================================================
echo   检测到服务已在运行，直接打开浏览器
echo   访问地址: http://127.0.0.1:8000
echo ============================================================
start "" http://127.0.0.1:8000
ping -n 3 127.0.0.1 >nul
exit /b 0

:start_server
echo ============================================================
echo   股票智能分析系统 - Web 工作台
echo   访问地址: http://127.0.0.1:8000
echo   初始化约需 15 秒，随后浏览器会自动打开
echo   关闭本窗口或按 Ctrl+C 可停止服务
echo ============================================================
echo.

start "" /b powershell -NoProfile -WindowStyle Hidden -Command "Start-Sleep -Seconds 20; Start-Process 'http://127.0.0.1:8000'"

".venv\Scripts\python.exe" main.py --serve-only

echo.
echo 服务已停止，按任意键关闭窗口。
pause >nul