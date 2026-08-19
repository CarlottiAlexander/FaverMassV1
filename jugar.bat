@echo off
setlocal
rem Lanza el juego sin abrir el editor. Doble click y listo.
rem
rem Busca el ejecutable de Godot en este orden, y se queda con el primero:
rem   1. La variable de entorno GODOT, si esta definida.
rem   2. godot.exe / godot4.exe en el PATH.
rem   3. Ubicaciones habituales (ver el bloque de abajo).
rem
rem Para clavar una version concreta, una sola vez y sin editar este archivo:
rem   setx GODOT "C:\lo\que\sea\Godot.exe"

if defined GODOT goto :verificar

rem --- 2. PATH. El modificador ~$PATH: resuelve el nombre contra el PATH.
for %%e in (godot.exe godot4.exe) do (
    if not defined GODOT if not "%%~$PATH:e"=="" set "GODOT=%%~$PATH:e"
)
if defined GODOT goto :verificar

rem --- 3. Ubicaciones habituales. Gana el primer Godot_v*win64.exe que aparezca.
rem     Se descartan los _console.exe: abren una consola de mas al lado del juego.
for %%d in (
    "%~dp0..\Tools\Godot"
    "%~dp0"
    "%LOCALAPPDATA%\Programs\Godot"
    "%ProgramFiles%\Godot"
) do (
    if not defined GODOT (
        for /f "delims=" %%f in ('dir /b /a-d "%%~d\Godot_v*win64.exe" 2^>nul ^| findstr /v /i "_console"') do (
            if not defined GODOT set "GODOT=%%~d\%%f"
        )
    )
)

:verificar
if not defined GODOT goto :nohay
if not exist "%GODOT%" goto :nohay

echo Motor: %GODOT%
rem "%~dp0." = la carpeta de este .bat. El punto final es a proposito: %~dp0 ya
rem termina en barra, y una barra pegada a la comilla se come la comilla.
rem Los argumentos extra se pasan tal cual, para poder correr escenas de tools/.
start "" "%GODOT%" --path "%~dp0." %*
exit /b 0

:nohay
echo No se encontro Godot.
if defined GODOT echo    La variable GODOT apunta a: "%GODOT%", que no existe.
echo.
echo Definir la ruta una sola vez con:
echo    setx GODOT "C:\ruta\a\Godot.exe"
echo o dejar el ejecutable en Tools\Godot\ al lado de la carpeta del proyecto.
echo.
echo El proyecto declara Godot 4.6 ^(config/features en project.godot^).
echo Descarga: https://godotengine.org/download  ^(build estandar, NO la .NET^)
pause
exit /b 1
