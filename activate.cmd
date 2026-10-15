@echo off
rem ai工作医生（ai-work-doctor）一键激活 —— 双击运行即可
rem 默认走交互式菜单：自己挑要装哪几个 agent（可多选 / all / detected）
chcp 65001 >nul
setlocal
echo.
echo ============================================
echo   ai工作医生 / ai-work-doctor  一键激活
echo ============================================
echo.
echo 接下来会让你挑宿主：
echo   输入编号（如 1,3,5 或 2-4）   all=全部   detected=只装检测到的   q=退出
echo   直接回车 = 只装本机检测到的宿主
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Select %*
echo.
echo 其它用法：
echo   install.ps1 -DryRun             只预览不改文件
echo   install.ps1 -Only trae,codex    指定宿主，不进菜单
echo   install.ps1 -Uninstall          卸载（只删本技能写入的内容）
echo   install.ps1 -Project D:\my-app  往项目里写项目级规则
echo.
pause
