@echo off
REM Включаємо підтримку UTF-8 у консолі, щоб не було кракозябр
chcp 65001 > nul
cls
echo [INIT] LAUNCHING EUGENE OS BUILDER...

set WORK_DIR=%CD%
set FASM="D:\fasm\fasm.exe"
set BIOS="OVMF.fd"
set QEMU="%WORK_DIR%\qemu\qemu-system-x86_64.exe"

REM === ПОВНИЙ ШЛЯХ ДО ФАЙЛУ ДИСКА (Заміни на свій!) ===
set DISK_FILE="D:\store\1.vhd"

REM === ЗМІНИ E: НА БУКВУ ТВОГО ЗМОНТОВАНОГО ДИСКА ===
set VHD_DRIVE=E:

REM Перевірка, чи змонтовано VHD
if not exist %VHD_DRIVE%\ (
    echo [ERROR] Диск %VHD_DRIVE% не знайдено!
    echo Змонтуй файл %DISK_FILE% подвійним кліком і спробуй ще раз.
    pause
    exit /b
)

REM Створюємо структуру папок на VHD, якщо їх ще немає
if not exist %VHD_DRIVE%\EFI\BOOT mkdir %VHD_DRIVE%\EFI\BOOT

REM --- КОМПІЛЯЦІЯ BOOTLOADER ---
%FASM% main.asm %VHD_DRIVE%\EFI\BOOT\BOOTX64.EFI
if %errorlevel% neq 0 (
    echo [ERROR] FASM Main Failed!
    pause
    exit /b
)

REM --- КОМПІЛЯЦІЯ KERNEL ---
%FASM% kernel.asm %VHD_DRIVE%\kernel.bin
if %errorlevel% neq 0 (
    echo [ERROR] FASM Kernel Failed!
    pause
    exit /b
)

echo.
echo ========================================================
echo [УСПІХ] Файли завантажено на диск %VHD_DRIVE%
echo ========================================================
echo [МАГІЯ ВІДКЛЮЧЕННЯ] 
echo 1. Відкрий "Цей ПК".
echo 2. Натисни правою кнопкою на диск %VHD_DRIVE% і вибери "Витягти" (Eject).
echo 3. Тільки ПІСЛЯ ЦЬОГО натискай будь-яку клавішу в цьому вікні!
echo ========================================================
pause

REM --- ЗАПУСК QEMU З ПОВНИМ ШЛЯХОМ ДО ДИСКА ---
echo [INFO] Starting QEMU...
%QEMU% -bios %BIOS% -net none -vga std -drive file=%DISK_FILE%,format=vpc -boot menu=on