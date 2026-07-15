@echo off
chcp 65001 >nul
echo ============================================
echo   kgka_Music_hl - APK 构建工具
echo ============================================
echo.

setlocal
set JAVA_HOME=E:\jdk17\jdk-17.0.12+7
set ANDROID_HOME=E:\AIwork\android-sdk
set JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF-8
set PATH=%JAVA_HOME%\bin;%ANDROID_HOME%\platform-tools;%PATH%

cd /d E:\AIwork\kgka_Music_hl

set BUILD_TYPE=%1
if "%BUILD_TYPE%"=="" set BUILD_TYPE=release

echo [构建类型] %BUILD_TYPE%
echo.

echo [1/3] 安装依赖...
call E:\flutter\flutter\bin\flutter.bat pub get
if %ERRORLEVEL% neq 0 (
    echo [失败] pub get 出错
    pause
    exit /b 1
)

echo.
echo [2/3] 代码分析...
call E:\flutter\flutter\bin\flutter.bat analyze
if %ERRORLEVEL% neq 0 (
    echo [失败] 分析出错，请检查代码
    pause
    exit /b 1
)

echo.
echo [3/3] 构建 APK...
call E:\flutter\flutter\bin\flutter.bat build apk --%BUILD_TYPE%
if %ERRORLEVEL% neq 0 (
    echo [失败] 构建出错
    pause
    exit /b 1
)

echo.
echo ============================================
echo   ^[成功^] 构建成功！
echo   APK：build\app\outputs\flutter-apk\app-%BUILD_TYPE%.apk
echo ============================================
echo.
echo 用法: build_apk.bat [release^|debug]
echo   默认: release（22MB）
echo   debug: 调试版（89MB）
pause
