format binary as 'bin'      ; Вказуємо компілятору FASM, що нам потрібен чистий бінарник (без заголовків Windows/Linux)
use64                       ; Використовуємо 64-бітний режим процесора (який нам включив UEFI)
org 0x100000                ; Базова адреса в пам'яті, куди завантажувач (main.asm) кладе наше ядро

; ==========================================================
; 1. ІНІЦІАЛІЗАЦІЯ ЯДРА
; ==========================================================
start:
    cld                     ; Очищаємо прапор напрямку (щоб команди типу rep movsb копіювали вперед, а не назад)
    mov     rsp, 0x200000   ; Встановлюємо вказівник стека далеко за межами нашого коду (щоб не затерти ядро)

    ; UEFI завантажувач передав нам параметри екрану через регістри RCX, RDX та R8. Зберігаємо їх:
    mov     [ScreenBase], rcx   ; Базова адреса відеопам'яті (куди малювати пікселі)
    mov     [ScreenWidth], edx  ; Ширина екрану в пікселях
    mov     [ScreenHeight], r8d ; Висота екрану в пікселях

    ; Малюємо інтерфейс
    call    ClearScreen         ; <--- ДОДАНО: Очищаємо екран від меню завантажувача
    call    DrawTaskbar         ; Заливаємо верхню панель синім кольором
    
    ; Виводимо назву ОС (Білим кольором - 0x00FFFFFF)
    mov     rcx, 20             ; X координата
    mov     rdx, 20             ; Y координата
    lea     r8,  [MsgName]      ; Вказівник на рядок
    mov     r9d, 0x00FFFFFF     ; Колір (AARRGGBB)
    call    DrawString

    ; Виводимо список команд (Жовтим кольором)
    mov     rcx, 20
    mov     rdx, 100
    lea     r8,  [MsgHelpList]
    mov     r9d, 0x00FFFF00
    call    DrawString

    ; Встановлюємо початкові координати для курсора вводу
    mov     [CursorX], 20
    mov     [CursorY], 140
    call    PrintPrompt         ; Виводимо значок "> "

; ==========================================================
; 2. ГОЛОВНИЙ ЦИКЛ (СЕРЦЕ ОС)
; ==========================================================
kernel_loop:
    call    CheckKeyboard       ; Перевіряємо, чи натиснута клавіша
    
    mov     rcx, 10000          ; Штучна затримка, щоб не спалити процесор на 100%
.delay:
    dec     rcx
    jnz     .delay

    jmp     kernel_loop         ; Нескінченний цикл

hang:                           ; Сюди ОС стрибає, коли треба зависнути (наприклад, перед ребутом)
    cli                         ; Вимикаємо переривання
    hlt                         ; Зупиняємо процесор до наступного апаратного сигналу
    jmp     hang

; ==========================================================
; 3. КОМАНДНА ОБОЛОНКА (SHELL)
; ==========================================================
ExecuteCommand:
    mov     rbx, [BufferLen]
    mov     byte [CmdBuffer + rbx], 0 ; Ставимо нуль-термінатор в кінці введеної команди

    call    NewLine             ; Переходимо на новий рядок після натискання Enter

    ; --- Перевірка команди LS ---
    lea     rsi, [CmdBuffer]
    lea     rdi, [CmdLS]
    call    StrCmp              ; Порівнюємо введене слово з "LS"
    test    rax, rax
    jz      .run_ls             ; Якщо збігається (rax=0) - стрибаємо на обробник
    
    ; --- Перевірка команди CREATE ---
    lea     rsi, [CmdBuffer]
    lea     rdi, [CmdCreate]
    call    StrPrefix           ; Перевіряємо, чи ПОЧИНАЄТЬСЯ рядок з "CREATE "
    test    rax, rax
    jz      .run_create

    ; --- Перевірка команди READ ---
    lea     rsi, [CmdBuffer]
    lea     rdi, [CmdRead]
    call    StrPrefix
    test    rax, rax
    jz      .run_read

    ; --- Перевірка команди HELP ---
    lea     rsi, [CmdBuffer]
    lea     rdi, [CmdHelp]
    call    StrCmp
    test    rax, rax
    jz      .run_help

    ; --- Перевірка команди INFO ---
    lea     rsi, [CmdBuffer]
    lea     rdi, [CmdInfo]
    call    StrCmp
    test    rax, rax
    jz      .run_info

    ; --- Перевірка команди REBOOT ---
    lea     rsi, [CmdBuffer]
    lea     rdi, [CmdReboot]
    call    StrCmp
    test    rax, rax
    jz      .run_reboot

    ; --- Якщо натиснули просто Enter (порожній буфер) ---
    cmp     [BufferLen], 0
    je      .finish

    ; --- Якщо команду не знайдено ---
    mov     rcx, 20
    mov     rdx, [CursorY]
    lea     r8,  [MsgUnknown]
    mov     r9d, 0x000000FF     ; Червоний текст помилки
    call    DrawString
    call    NewLine
    jmp     .finish

; --- Обробники конкретних команд ---
.run_help:
    mov     rcx, 20
    mov     rdx, [CursorY]
    lea     r8,  [MsgHelpList]
    mov     r9d, 0x00FFFFFF
    call    DrawString
    call    NewLine
    jmp     .finish

.run_info:                      ; Отримання назви процесора (CPUID)
    xor     eax, eax
    cpuid                       ; Апаратна команда процесора, повертає Vendor ID у ebx, edx, ecx
    mov     dword [VendorID], ebx
    mov     dword [VendorID + 4], edx
    mov     dword [VendorID + 8], ecx

    ; Робимо літери процесора ВЕЛИКИМИ
    lea     rsi, [VendorID]
    mov     rcx, 12
.to_upper:
    cmp     byte [rsi], 'a'
    jb      .skip_char
    cmp     byte [rsi], 'z'
    ja      .skip_char
    sub     byte [rsi], 32
.skip_char:
    inc     rsi
    dec     rcx
    jnz     .to_upper

    mov     rcx, 20
    mov     rdx, [CursorY]
    lea     r8,  [MsgCPU]
    mov     r9d, 0x0000FF00     ; Зелений текст "CPU DETECTED:"
    call    DrawString
    
    add     rcx, 110
    lea     r8,  [VendorID]
    mov     r9d, 0x00FFFFFF     ; Білий текст самої назви (Intel/AMD)
    call    DrawString
    
    call    NewLine
    jmp     .finish

.run_reboot:
    ; Спілкуємося з контролером клавіатури (порт 0x64), щоб апаратно перезавантажити ПК
    in      al, 0x64
    test    al, 2
    jnz     .run_reboot
    mov     al, 0xFE            ; Команда "Reset"
    out     0x64, al
    jmp     hang

.run_ls:
    mov     rcx, 20
    mov     rdx, [CursorY]
    lea     r8,  [MsgLS]
    mov     r9d, 0x0000FF00
    call    DrawString
    call    NewLine
    call    ListFilesFAT32      ; Викликаємо драйвер ФС
    jmp     .finish

.run_create:
    lea     rsi, [CmdBuffer + 7]        ; Пропускаємо слово "CREATE " (7 символів)
    lea     rdi, [ParsedFileName]       ; Буфер, куди збережемо форматоване ім'я
    call    FormatFAT32Name             ; Робимо з "OS.TXT" -> "OS      TXT"

    lea     r8, [ParsedFileName]
    call    CreateFileFAT32             ; Викликаємо драйвер запису
    jc      .disk_err                   ; Якщо Carry Flag = 1 (помилка) -> червоний текст

    mov     rcx, 20
    mov     rdx, [CursorY]
    lea     r8,  [MsgCreated]
    mov     r9d, 0x0000FF00
    call    DrawString
    add     rcx, 120
    lea     r8,  [ParsedFileName]
    call    DrawString                  ; Виводимо створене ім'я
    call    NewLine
    jmp     .finish

.run_read:
    lea     rsi, [CmdBuffer + 5]        ; Пропускаємо слово "READ "
    lea     rdi, [ParsedFileName]
    call    FormatFAT32Name

    lea     r8, [ParsedFileName]
    call    ReadFileFAT32               ; Читаємо кластери файлу в FileBuffer
    jc      .read_failed

    ; --- Конвертуємо прочитаний текст у ВЕЛИКІ літери ---
    lea     rsi, [FileBuffer]
.up_loop:
    mov     al, [rsi]
    test    al, al
    jz      .print_buf                  ; Якщо нуль - кінець тексту
    cmp     al, 'a'
    jb      .skip_up
    cmp     al, 'z'
    ja      .skip_up
    sub     byte [rsi], 32              ; Перетворюємо 'a'-'z' на 'A'-'Z'
.skip_up:
    inc     rsi
    jmp     .up_loop

.print_buf:
    mov     rcx, 20
    mov     rdx, [CursorY]
    lea     r8,  [FileBuffer]
    mov     r9d, 0x00FFFFFF             ; Виводимо текст білим кольором
    call    DrawString
    
    mov     [CursorY], rdx              ; Зберігаємо Y, який міг змінитися через Enter в тексті
    call    NewLine
    jmp     .finish

.disk_err:                              ; Якщо диск відхилив команду WRITE
    mov     rcx, 20
    mov     rdx, [CursorY]
    lea     r8,  [MsgWriteErr]
    mov     r9d, 0x000000FF             ; Червоний текст
    call    DrawString
    call    NewLine
    jmp     .finish

.read_failed:                           ; Якщо файл порожній або не існує
    mov     rcx, 20
    mov     rdx, [CursorY]
    lea     r8,  [MsgReadErr]
    mov     r9d, 0x000000FF
    call    DrawString
    call    NewLine
    jmp     .finish

.finish:
    mov     qword [BufferLen], 0        ; Очищаємо буфер для нової команди
    call    PrintPrompt                 ; Малюємо "> "
    ret

; ==========================================================
; 4. СИСТЕМНІ УТИЛІТИ (Рядки, клавіатура)
; ==========================================================
PrintPrompt:
    mov     rcx, [CursorX]
    mov     rdx, [CursorY]
    lea     r8,  [PromptStr]
    mov     r9d, 0x0000FF00             ; Малюємо зелений "> "
    call    DrawString
    add     qword [CursorX], 18         ; Відступаємо місце для вводу
    ret

NewLine:
    mov     qword [CursorX], 20         ; Повертаємо X на старт
    add     qword [CursorY], 20         ; Опускаємо Y вниз на 20 пікселів (висота рядка)
    ret

; Повне порівняння двох рядків (повертає RAX=0 якщо рівні)
StrCmp:
    push    rsi
    push    rdi
    push    rbx
.loop:
    mov     al, [rsi]
    mov     bl, [rdi]
    cmp     al, bl
    jne     .ne
    test    al, al
    jz      .eq
    inc     rsi
    inc     rdi
    jmp     .loop
.ne:
    pop     rbx
    pop     rdi
    pop     rsi
    mov     rax, 1
    ret
.eq:
    pop     rbx
    pop     rdi
    pop     rsi
    xor     rax, rax
    ret

; Часткове порівняння: перевіряє чи починається рядок RSI з RDI ("CREATE MY.TXT" -> "CREATE ")
StrPrefix:
    push    rsi
    push    rdi
    push    rbx
.loop:
    mov     bl, [rdi]
    test    bl, bl
    jz      .match
    mov     al, [rsi]
    cmp     al, bl
    jne     .ne
    inc     rsi
    inc     rdi
    jmp     .loop
.match:
    pop     rbx
    pop     rdi
    pop     rsi
    xor     rax, rax
    ret
.ne:
    pop     rbx
    pop     rdi
    pop     rsi
    mov     rax, 1
    ret

; Перетворює "FILE.TXT" у формат "FILE    TXT" (рівно 11 байт для запису в директорію диска)
FormatFAT32Name:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    mov     rdx, rdi
    mov     rcx, 11
    mov     al, ' '
    cld
    rep stosb                   ; Заповнюємо весь буфер 11 пробілами

    mov     rdi, rdx
    mov     rcx, 8              ; Обробляємо максимум 8 символів імені
.copy_name:
    mov     al, [rsi]
    test    al, al
    jz      .done               ; Кінець рядка
    cmp     al, '.'
    je      .do_ext             ; Дійшли до крапки
    cmp     al, 'a'
    jb      .store_n
    cmp     al, 'z'
    ja      .store_n
    sub     al, 32              ; Робимо літеру великою
.store_n:
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rcx
    jnz     .copy_name

.skip_to_ext:                   ; Якщо ім'я було більше 8 символів - відкидаємо зайве до крапки
    mov     al, [rsi]
    test    al, al
    jz      .done
    cmp     al, '.'
    je      .do_ext
    inc     rsi
    jmp     .skip_to_ext

.do_ext:
    inc     rsi                 ; Пропускаємо саму крапку
    mov     rdi, rdx
    add     rdi, 8              ; Зсуваємо вказівник запису на 8-му позицію (розширення)
    mov     rcx, 3              ; Обробляємо максимум 3 символи розширення
.copy_ext:
    mov     al, [rsi]
    test    al, al
    jz      .done
    cmp     al, 'a'
    jb      .store_e
    cmp     al, 'z'
    ja      .store_e
    sub     al, 32
.store_e:
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rcx
    jnz     .copy_ext

.done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; Читання PS/2 клавіатури через порти
CheckKeyboard:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    r8
    push    r9

    in      al, 0x64            ; Порт стану контролера
    test    al, 1               ; Перевіряємо біт "Чи є дані?"
    jz      .exit

    in      al, 0x60            ; Читаємо сам скан-код натиснутої клавіші з порту 0x60
    test    al, 0x80            ; Якщо встановлено старший біт - це ВІДПУСКАННЯ клавіші (ігноруємо)
    jnz     .exit

    cmp     al, 0x1C            ; Скан-код Enter
    je      .enter
    cmp     al, 0x0E            ; Скан-код Backspace
    je      .bs

    lea     rbx, [ScanCodes]    ; Перекладаємо апаратний скан-код в ASCII символ (через нашу таблицю)
    xlatb                       ; AL = ScanCodes[AL]
    test    al, al
    jz      .exit               ; Якщо символ нульовий (Shift, Ctrl) - ігноруємо

    mov     rbx, [BufferLen]
    cmp     rbx, 60             ; Захист від переповнення буфера
    jge     .exit
    
    mov     [CmdBuffer + rbx], al
    inc     qword [BufferLen]

    ; Малюємо введену літеру на екрані
    movzx   r8, al
    mov     rcx, [CursorX]
    mov     rdx, [CursorY]
    mov     r9d, 0x00FFFFFF
    call    DrawChar_Safe

    add     qword [CursorX], 9  ; Зсуваємо курсор вправо
    jmp     .exit

.bs:                            ; Обробка Backspace (видалення)
    cmp     qword [BufferLen], 0
    je      .exit               ; Якщо буфер порожній - нічого видаляти
    dec     qword [BufferLen]
    sub     qword [CursorX], 9  ; Повертаємо курсор вліво
    mov     rcx, [CursorX]
    mov     rdx, [CursorY]
    call    EraseChar           ; Замальовуємо літеру чорним квадратом
    jmp     .exit

.enter:
    call    ExecuteCommand      ; Якщо Enter - запускаємо парсер команди
    jmp     .exit

.exit:
    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; ==========================================================
; 5. ФАЙЛОВА СИСТЕМА (FAT32)
; ==========================================================
ListFilesFAT32:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    ; --- Читаємо MBR (Sector 0) ---
    xor     eax, eax                    ; EAX = 0 (LBA 0)
    lea     rdi, [SectorBuffer]         ; Куди читати
    call    ReadSectorATA

    ; Шукаємо зсув розділу (Volume Boot Record)
    mov     eax, dword [SectorBuffer + 0x1BE + 8] 
    test    eax, eax
    jnz     .read_vbr
    xor     eax, eax                    ; Якщо MBR немає (суперфлоппі), починаємо з 0
.read_vbr:
    mov     [VolumeStartLBA], eax
    lea     rdi, [SectorBuffer]
    call    ReadSectorATA

    ; --- Читаємо параметри FAT32 з VBR ---
    movzx   ebx, word [SectorBuffer + 0x0E]  ; Reserved sectors
    movzx   ecx, byte [SectorBuffer + 0x10]  ; Кількість таблиць FAT
    mov     edx, dword [SectorBuffer + 0x24] ; Розмір однієї FAT

    ; Рахуємо де лежить Коренева Директорія: VolumeStart + Reserved + (NumFATs * FATSize)
    imul    edx, ecx
    add     ebx, edx
    add     ebx, [VolumeStartLBA]

    ; Читаємо сектор кореневої директорії
    mov     eax, ebx
    lea     rdi, [SectorBuffer]
    call    ReadSectorATA

    ; --- Парсимо записи (32 байти кожен) ---
    lea     rsi, [SectorBuffer]
    mov     rcx, 16                     ; 512 байт / 32 = 16 записів у секторі

.parse_entry:
    mov     al, [rsi]
    test    al, al
    jz      .done                       ; 0x00 = кінець директорії
    cmp     al, 0xE5
    je      .next_entry                 ; 0xE5 = видалений файл (ігноруємо)

    mov     al, [rsi + 0x0B]            ; Байт атрибутів
    cmp     al, 0x0F
    je      .next_entry                 ; 0x0F = LFN (Довге ім'я, ігноруємо)
    test    al, 0x08
    jnz     .next_entry                 ; 0x08 = Мітка тому (ігноруємо)

    ; Копіюємо 11 байт імені
    push    rcx
    push    rsi
    lea     rdi, [FileNameBuf]
    mov     rcx, 11
    rep movsb
    mov     byte [rdi], 0               ; Додаємо нуль-термінатор для друку
    pop     rsi
    pop     rcx

    ; Друкуємо знайдене ім'я
    push    rcx
    mov     rcx, 20
    mov     rdx, [CursorY]
    lea     r8,  [FileNameBuf]
    mov     r9d, 0x00FFFFFF
    call    DrawString
    call    NewLine
    pop     rcx

.next_entry:
    add     rsi, 32                     ; Наступний запис (32 байти)
    dec     rcx
    jnz     .parse_entry

.done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

CreateFileFAT32:
    ; (Пропуск обчислення Root LBA, воно ідентичне ListFiles)
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    xor     eax, eax
    lea     rdi, [SectorBuffer]
    call    ReadSectorATA
    mov     eax, dword [SectorBuffer + 0x1BE + 8]
    test    eax, eax
    jnz     .read_vbr_c
    xor     eax, eax
.read_vbr_c:
    mov     [VolumeStartLBA], eax
    lea     rdi, [SectorBuffer]
    call    ReadSectorATA

    movzx   ebx, word [SectorBuffer + 0x0E]
    movzx   ecx, byte [SectorBuffer + 0x10]
    mov     edx, dword [SectorBuffer + 0x24]
    imul    edx, ecx
    add     ebx, edx
    add     ebx, [VolumeStartLBA]
    
    mov     [RootDirLBA], ebx 
    mov     eax, ebx
    lea     rdi, [SectorBuffer]
    call    ReadSectorATA

    ; --- Шукаємо порожній слот ---
    lea     rsi, [SectorBuffer]
    mov     rcx, 16

.find_empty:
    mov     al, [rsi]
    test    al, al
    jz      .found_empty                ; 0x00 = вільний
    cmp     al, 0xE5
    je      .found_empty                ; 0xE5 = видалений (можна перезаписати)
    add     rsi, 32
    dec     rcx
    jnz     .find_empty
    jmp     .done_c                     ; Якщо немає місця - виходимо

.found_empty:
    ; Вписуємо 11 байт імені з буфера в директорію
    push    rcx
    push    rsi
    push    rdi
    mov     rdi, rsi
    mov     rsi, r8         
    mov     rcx, 11
    rep movsb
    pop     rdi
    pop     rsi
    pop     rcx
    
    mov     byte [rsi+11], 0x20         ; Атрибут 0x20 = Archive (звичайний файл)
    
    ; Зануляємо решту 20 байтів запису (час, кластер, розмір = 0)
    push    rdi
    lea     rdi, [rsi+12]
    mov     rcx, 20
    xor     al, al
    rep stosb
    pop     rdi

    ; --- ЗБЕРІГАЄМО ОНОВЛЕНИЙ СЕКТОР НА ДИСК ---
    mov     eax, [RootDirLBA]
    lea     rdi, [SectorBuffer]
    call    WriteSectorATA
    clc                                 ; Очищаємо Carry Flag (все успішно)
    jmp     .done_c

.done_c:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

ReadFileFAT32:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    
    ; (Пропуск обчислення DataRegionLBA)
    xor     eax, eax
    lea     rdi, [SectorBuffer]
    call    ReadSectorATA
    mov     eax, dword [SectorBuffer + 0x1BE + 8]
    test    eax, eax
    jnz     .vbr
    xor     eax, eax
.vbr:
    mov     [VolumeStartLBA], eax
    lea     rdi, [SectorBuffer]
    call    ReadSectorATA

    movzx   ebx, word [SectorBuffer + 0x0E]
    movzx   ecx, byte [SectorBuffer + 0x10]
    mov     edx, dword [SectorBuffer + 0x24]
    mov     al, byte [SectorBuffer + 0x0D]      ; Отримуємо SectorsPerCluster (зазвичай 1 або 8)
    mov     [SectorsPerCluster], al

    imul    edx, ecx
    add     ebx, edx
    add     ebx, [VolumeStartLBA]
    mov     [DataRegionLBA], ebx                ; Це перший сектор, де лежать кластери даних
    
    ; Читаємо директорію
    mov     eax, ebx
    lea     rdi, [SectorBuffer]
    call    ReadSectorATA

    ; --- Шукаємо файл ---
    lea     rsi, [SectorBuffer]
    mov     rcx, 16
.find:
    mov     al, [rsi]
    test    al, al
    jz      .not_found
    cmp     al, 0xE5
    je      .next
    
    ; Порівнюємо ім'я
    push    rcx
    push    rsi
    mov     rdi, r8
    mov     rcx, 11
    cld
    repe cmpsb
    pop     rsi
    pop     rcx
    je      .found

.next:
    add     rsi, 32
    dec     rcx
    jnz     .find

.not_found:
    stc                     ; Ставимо помилку CF=1
    jmp     .exit

.found:
    ; --- Отримуємо номер кластера (High + Low) ---
    movzx   eax, word [rsi + 0x14]
    shl     eax, 16
    mov     ax, word [rsi + 0x1A] 
    
    test    eax, eax
    jz      .not_found      ; Якщо кластер 0 - файл порожній!

    ; --- Магія перетворення Кластера у Фізичний LBA сектор ---
    ; Формула: Sector = DataRegionLBA + (Cluster - 2) * SectorsPerCluster
    sub     eax, 2
    movzx   ecx, byte [SectorsPerCluster]
    imul    eax, ecx
    add     eax, [DataRegionLBA]

    ; Читаємо самі дані файлу!
    lea     rdi, [FileBuffer]
    call    ReadSectorATA
    
    mov     byte [FileBuffer + 511], 0 ; Захист від сміття при друку (термінатор)
    clc                     ; CF=0 (Успіх)

.exit:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; ==========================================================
; 6. АПАРАТНИЙ РІВЕНЬ ДИСКА (ATA PIO MODE)
; ==========================================================
; Звернення до контролера диска напряму через порти вводу/виводу процесора

ReadSectorATA:
    push    rdx
    push    rcx
    push    rbx
    push    rax

    mov     ebx, eax
    ; Відправляємо LBA адресу порціями по різних портах (0x1F3 - 0x1F6)
    mov     edx, 0x1F6
    shr     eax, 24
    or      al, 0xE0            ; Вибираємо Master диск і режим LBA
    out     dx, al
    mov     edx, 0x1F2
    mov     al, 1               ; Читаємо 1 сектор
    out     dx, al
    mov     edx, 0x1F3
    mov     eax, ebx            ; LBA Low
    out     dx, al
    mov     edx, 0x1F4
    mov     eax, ebx            ; LBA Mid
    shr     eax, 8
    out     dx, al
    mov     edx, 0x1F5
    mov     eax, ebx            ; LBA High
    shr     eax, 16
    out     dx, al
    
    ; Надсилаємо команду READ (0x20)
    mov     edx, 0x1F7
    mov     al, 0x20
    out     dx, al
.wait_ready:
    in      al, dx
    test    al, 8               ; Чекаємо поки диск підніме біт DRQ (готовність даних)
    jz      .wait_ready
    
    ; Вичитуємо 256 слів (512 байт) з порту даних 0x1F0
    mov     edx, 0x1F0
    mov     rcx, 256
    cld
    rep insw                    ; Читаємо в пам'ять за адресою RDI

    pop     rax
    pop     rbx
    pop     rcx
    pop     rdx
    ret

WriteSectorATA:
    push    rdx
    push    rcx
    push    rbx
    push    rax

    mov     ebx, eax
    mov     edx, 0x1F6
    shr     eax, 24
    or      al, 0xE0
    out     dx, al
    mov     edx, 0x1F2
    mov     al, 1
    out     dx, al
    mov     edx, 0x1F3
    mov     eax, ebx
    out     dx, al
    mov     edx, 0x1F4
    mov     eax, ebx
    shr     eax, 8
    out     dx, al
    mov     edx, 0x1F5
    mov     eax, ebx
    shr     eax, 16
    out     dx, al
    
    ; Надсилаємо команду WRITE (0x30)
    mov     edx, 0x1F7
    mov     al, 0x30
    out     dx, al

.wait_bsy:
    in      al, dx
    test    al, 0x80            ; Перевіряємо біт BSY (диск думає)
    jnz     .wait_bsy

.wait_drq:
    in      al, dx
    test    al, 0x01            ; Перевіряємо біт ERR (помилка - Read Only?)
    jnz     .disk_error
    test    al, 0x08            ; Перевіряємо біт DRQ (диск готовий приймати дані)
    jz      .wait_drq

    ; Записуємо 256 слів на диск
    mov     edx, 0x1F0
    mov     rcx, 256
    mov     rsi, rdi            ; Беремо дані з RDI
    cld
    rep outsw

    ; Примусове скидання кешу диска (щоб дані точно записались магнітами)
    mov     edx, 0x1F7
    mov     al, 0xE7            ; CACHE FLUSH
    out     dx, al
    
.wait_flush:
    in      al, dx
    test    al, 0x80
    jnz     .wait_flush

    clc                         ; Успіх
    jmp     .exit_w

.disk_error:
    stc                         ; Ставимо помилку
.exit_w:
    pop     rax
    pop     rbx
    pop     rcx
    pop     rdx
    ret

; ==========================================================
; 7. ГРАФІКА ТА ВІДЕОПАМ'ЯТЬ
; ==========================================================
DrawTaskbar:
    mov     rdi, [ScreenBase]           ; Початок відеопам'яті
    movsxd  rax, dword [ScreenWidth]    ; Ширина
    imul    rax, 80                     ; Висота панелі 80 px
    mov     rcx, rax                    ; Кількість пікселів для замальовки
    mov     eax, 0x000000FF             ; Синій колір
    cld
    rep     stosd                       ; Заповнюємо пам'ять пікселями (по 4 байти на піксель)
    ret

DrawString:
    push    rsi
    push    rax
    push    rbx
    push    rcx
    mov     rsi, r8
.next:
    mov     al, [rsi]
    inc     rsi
    test    al, al
    jz      .done

    cmp     al, 13          ; Ігноруємо \r (повернення каретки)
    je      .next
    cmp     al, 10          ; Перехід на новий рядок \n
    jne     .draw
    
    mov     rcx, 20         ; X повертаємо на старт
    add     rdx, 20         ; Y опускаємо на 20 px
    jmp     .next

.draw:
    movzx   r8, al
    push    rcx
    push    rdx
    push    r9
    call    DrawChar_Safe   ; Малюємо 1 символ
    pop     r9
    pop     rdx
    pop     rcx
    add     rcx, 9          ; Зсув вправо для наступної літери (шрифт 8px + 1px інтервал)
    jmp     .next
.done:
    pop     rcx
    pop     rbx
    pop     rax
    pop     rsi
    ret
ClearScreen:
    mov     rdi, [ScreenBase]           ; Початок відеопам'яті
    mov     eax, [ScreenWidth]
    imul    eax, [ScreenHeight]         ; Загальна кількість пікселів на екрані
    mov     rcx, rax
    xor     eax, eax                    ; 0x00000000 = Чорний колір
    cld
    rep     stosd                       ; Заливаємо весь екран чорним
    ret

DrawChar_Safe:
    push    rdi
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rax

    mov     rax, r8                     ; ASCII код символу
    movzx   rbx, al
    sub     rbx, 32                     ; Віднімаємо 32 (офсет, бо шрифт починається з пробілу)
    imul    rbx, 8                      ; Кожен символ займає 8 байт
    lea     rsi, [FontData + rbx + 7]   ; Читаємо шрифт знизу-вверх

    ; Формула відеопам'яті: Base + (Y * Width + X) * 4
    mov     rax, rdx
    movsxd  r10, dword [ScreenWidth]
    imul    rax, r10
    add     rax, rcx
    shl     rax, 2
    add     rax, [ScreenBase]
    mov     rdi, rax
    
    mov     rcx, 8                      ; 8 рядків у висоту
.ln:
    mov     al, [rsi]
    dec     rsi
    push    rcx
    mov     rcx, 8                      ; 8 пікселів у ширину
.px:
    shl     al, 1                       ; Дістаємо 1 біт з шрифту (1 - малювати, 0 - пусто)
    jnc     .sk
    mov     [rdi], r9d                  ; Малюємо кольоровий піксель
.sk:
    add     rdi, 4                      ; Наступний піксель (4 байти)
    dec     rcx
    jnz     .px
    pop     rcx
    
    movsxd  r10, dword [ScreenWidth]    ; Переходимо на наступний рядок екрана
    shl     r10, 2
    sub     r10, 32
    add     rdi, r10
    dec     rcx
    jnz     .ln

    pop     rax
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rdi
    ret

EraseChar:  ; Малює чорний квадрат розміром 8x8 (використовується для Backspace)
    push    rdi
    push    rcx
    push    rdx
    push    rax
    
    mov     rax, rdx
    movsxd  r10, dword [ScreenWidth]
    imul    rax, r10
    add     rax, rcx
    shl     rax, 2
    add     rax, [ScreenBase]
    mov     rdi, rax
    
    xor     eax, eax        ; 0x00000000 = Чорний колір
    mov     rcx, 8
.el:
    push    rcx
    mov     rcx, 8
.ep:
    mov     [rdi], eax
    add     rdi, 4
    dec     rcx
    jnz     .ep
    pop     rcx
    movsxd  r10, dword [ScreenWidth]
    shl     r10, 2
    sub     r10, 32
    add     rdi, r10
    dec     rcx
    jnz     .el
    
    pop     rax
    pop     rdx
    pop     rcx
    pop     rdi
    ret

; ==========================================================
; 8. ДАНІ ТА ЗМІННІ ЯДРА
; ==========================================================
; Глобальні змінні екрану
ScreenBase      dq 0
ScreenWidth     dd 0
ScreenHeight    dd 0
CursorX         dq 0
CursorY         dq 0

; Буфери оболонки
CmdBuffer       rb 64           ; Сюди складаються натиснуті кнопки
BufferLen       dq 0

; Команди
CmdHelp         db 'HELP', 0
CmdInfo         db 'INFO', 0
CmdReboot       db 'REBOOT', 0
CmdLS           db 'LS', 0
CmdCreate       db 'CREATE ', 0
CmdRead         db 'READ ', 0

; Текстові повідомлення
MsgName         db 'EUGENE OS V1.3', 0
MsgCPU          db 'CPU DETECTED:', 0
PromptStr       db '> ', 0
MsgUnknown      db 'UNKNOWN COMMAND', 0
MsgLS           db 'FILES ON DISK:', 0
MsgCreated      db 'FILE CREATED: ', 0
MsgHelpList     db 'COMMANDS: HELP, INFO, REBOOT, LS, CREATE, READ', 0
MsgWriteErr     db 'DISK WRITE ERROR (READ-ONLY?)', 0
MsgReadErr      db 'FILE NOT FOUND OR EMPTY', 0

; Буфери для FAT32
SectorBuffer    rb 512          ; Тимчасовий буфер для одного сектора диска
FileNameBuf     rb 12           ; Для друку знайдених файлів
ParsedFileName  rb 12           ; Відформатоване ім'я для створення/читання
VolumeStartLBA  dd 0
RootDirLBA      dd 0
DataRegionLBA   dd 0
SectorsPerCluster db 0

VendorID        db '            ', 0  ; Назва CPU

FileBuffer      rb 512          ; Буфер для тексту з прочитаного файлу

; Таблиця перекладу апаратних кодів клавіатури у звичайні букви (US QWERTY)
ScanCodes:
    db 0, 27, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 8, 9
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '[', ']', 13, 0
    db 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ';', 39, '`', 0, '\'
    db 'Z', 'X', 'C', 'V', 'B', 'N', 'M', ',', '.', '/', 0, '*', 0, ' '
    times 100 db 0 

; Системний шрифт 8x8 (тільки ВЕЛИКІ літери та символи, для економії місця)
align 8
FontData:
    dq 0
    dq 0x1818181818001800, 0x2424240000000000, 0x24247E247E242400, 0x183C603C063C1800
    dq 0x66C6181830660000, 0x386C3876DC000000, 0x1818300000000000, 0x0C183030180C0000
    dq 0x30180C0C18300000, 0x00663CFF3C660000, 0x0018187E18180000, 0x0000000000181830
    dq 0x0000007E00000000, 0x0000000000181800, 0x006030180C060000
    dq 0x3C666666663C0000, 0x18381818183C0000, 0x3C660C18307E0000, 0x3C660C0C663C0000
    dq 0x0C1C3C6C7E0C0000, 0x7E603E06063C0000, 0x1C30603C663C0000, 0x7E060C1830300000
    dq 0x3C663C663C000000, 0x3C663C060C380000
    dq 0x0018180018180000, 0x0018180018183000, 0x060C1830180C0600, 0x00007E007E000000
    dq 0x6030180C18306000, 0x3C660C1800180000, 0x3C666E6E603E0000
    dq 0x183C66667E666600, 0x7E66667E66667E00, 0x3C66606060663C00, 0x7C66666666667C00
    dq 0x7E60607860607E00, 0x7E60607860606000, 0x3C66606E663C0000, 0x6666667E66666600
    dq 0x3C18181818183C00, 0x1E060606663C0000, 0x666C78786C660000, 0x6060606060607E00
    dq 0x63777F6B63630000, 0x66767F6E66660000, 0x3C666666663C0000
    dq 0x7E66667E60600000, 0x3C6666666C360000, 0x7E66667E6C660000, 0x3C603C06663C0000
    dq 0x7E18181818180000, 0x66666666663C0000, 0x666666663C180000, 0x63636B7F77630000
    dq 0x66663C183C660000, 0x66663C1818180000, 0x7E060C18307E0000
    dq 0x3C303030303C0000, 0x00060C1830600000, 0x3C0C0C0C0C3C0000