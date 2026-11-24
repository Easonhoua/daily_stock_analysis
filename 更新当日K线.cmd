@echo off
chcp 936 >nul
title 股票分析 - 更新当日K线数据
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

echo ============================================================
echo   更新当日 K 线数据
echo   只抓取行情数据并写入数据库，不调用 AI、不发送推送
echo   股票列表来自 .env 里的 STOCK_LIST
echo.
echo   提示: A 股收盘(15:00)后运行才会写入当天这根 K 线;
echo         盘中运行时，项目会跳过尚未收盘的当日 K 线。
echo ============================================================
echo.

".venv\Scripts\python.exe" main.py --dry-run --no-market-review --no-notify

echo.
echo ============================================================
echo   执行结束，按任意键关闭窗口。
echo ============================================================
pause >nul