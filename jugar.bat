@echo off
rem Lanza el juego sin abrir el editor. Doble click y listo.
rem
rem La ruta se puede pisar desde afuera con la variable de entorno GODOT,
rem asi que quien clone el repo no necesita editar este archivo:
rem   set GODOT=C:\lo\que\sea\Godot.exe  &&  jugar.bat
if not defined GODOT set "GODOT=F:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"

if not exist "%GODOT%" (
    echo No se encontro Godot en:
    echo    %GODOT%
    echo.
    echo Editar la variable GODOT arriba en este archivo, o definirla en el entorno.
    echo Descarga: https://godotengine.org/download  ^(build estandar, NO la .NET^)
    pause
    exit /b 1
)

rem "%~dp0." = la carpeta de este .bat. El punto final es a proposito: %~dp0 ya
rem termina en barra, y una barra pegada a la comilla se come la comilla.
rem Los argumentos extra se pasan tal cual, para poder correr escenas de tools/.
start "" "%GODOT%" --path "%~dp0." %*
