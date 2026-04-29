# =============================================================================
# MikroTik RB4011iGS+5HacQ2HnD  |  RouterOS 7.2.7
# Перевірка швидкості інтернет з'єднання
# =============================================================================
# Вимірює download-швидкість через /tool fetch і ping-латентність через
# /tool ping. Жодних зовнішніх серверів або додаткової інфраструктури
# не потрібно.
#
# Чому не /tool speed-test і не /tool bandwidth-test:
#   Обидва інструменти тестують канал між двома MikroTik-пристроями і
#   вимагають MikroTik-сервер на іншому кінці. Для виміру швидкості
#   інтернет-з'єднання до довільного хосту вони не підходять.
#
# Як запустити:
#   Спосіб А — разовий імпорт:
#       /import file-name=speed_test.rsc verbose=yes
#
#   Спосіб Б — зберегти як скрипт і запускати за потребою:
#       /system script add name=speed-test \
#           source=[/file get [find name=speed_test.rsc] contents]
#       /system script run speed-test
#
# Обмеження:
#   - Upload не вимірюється (/tool fetch підтримує лише GET).
#   - Для точного виміру файл повинен завантажуватись щонайменше 3–5 секунд.
#     На швидких лініях (>100 Mbit/s) замініть розмір файлів у dlUrls на 1GB.
# =============================================================================

# ---- Параметри ---------------------------------------------------------------
# Список URL у порядку пріоритету; скрипт спробує кожен по черзі.
# Перший URL перевірений. Решту перевірте вручну і замініть якщо не працюють:
#   /tool fetch url="<url>" dst-path=test.bin mode=http
:local dlUrls {
    "http://cachefly.cachefly.net/100mb.test";
    "http://speedtest-nl.belhost.com/100mb.bin";
    "http://speedtest.tele2.net/100MB.zip";
}
:local tmpFile "sptest.tmp"
:local pingHosts {"1.1.1.1";"8.8.8.8";"google.com"}
# ------------------------------------------------------------------------------

:put "============================================================"
:put (" Speed Test  |  " . [/system clock get date] . "  " . [/system clock get time])
:put "============================================================"

# ---- 1. Активний WAN ---------------------------------------------------------
:put ""
:put "[1/3] Active route:"
:foreach rid in=[/ip route find dst-address=0.0.0.0/0 active=yes] do={
    :put ("    gateway=" . [/ip route get $rid gateway] . \
          "  distance=" . [/ip route get $rid distance])
}

# ---- 2. Ping-латентність -----------------------------------------------------
# as-value у RouterOS 7 не виводить RTT у консоль і ненадійно повертає поля
# через ->; ping без as-value друкує таблицю результатів сам по собі.
# Програмна перевірка зв'язку тут не потрібна: якщо інтернету нема,
# кроки 1 (немає активного route) або 3 (fetch fail) це покажуть.
:put ""
:put "[2/3] Ping-latency (3 packets):"
:foreach h in=$pingHosts do={
    :put ("    -- " . $h . " --")
    /tool ping address=$h count=3
}

# ---- 3. Download -------------------------------------------------------------
:put ""
:put "[3/3] Download test:"

:local fetchOk  false
:local usedUrl  ""
:do { /file remove [find name=$tmpFile] } on-error={}

:foreach url in=$dlUrls do={
    :if (!$fetchOk) do={
        :put ("    Attempt: " . $url)
        :local t1 [/system resource get uptime]
        :do {
            /tool fetch url=$url dst-path=$tmpFile mode=http
            :local t2 [/system resource get uptime]

            :local elapsed    ($t2 - $t1)
            :local elapsedStr [:tostr $elapsed]
            :local actual     0
            :do { :set actual [/file get [find name=$tmpFile] size] } on-error={}
            :do { /file remove [find name=$tmpFile] } on-error={}

            # Парсимо elapsed у секунди.
            # RouterOS повертає різницю uptime у форматі "HH:MM:SS"
            # (або "[D]d HH:MM:SS" при > 24 год, що для нас нереально).
            :local totalSec 0
            :local c1 [:find $elapsedStr ":"]
            :local c2 [:find $elapsedStr ":" ($c1 + 1)]
            :if ($c1 >= 0 && $c2 > $c1) do={
                :local hh [:tonum [:pick $elapsedStr 0 $c1]]
                :local mm [:tonum [:pick $elapsedStr ($c1 + 1) $c2]]
                :local ss [:tonum [:pick $elapsedStr ($c2 + 1) [:len $elapsedStr]]]
                :set totalSec ($hh * 3600 + $mm * 60 + $ss)
            }

            :put ("    Size: " . ($actual / 1048576) . " MB  |  Time: " . $elapsedStr)
            :if ($totalSec >= 1) do={
                :local bps ($actual * 8 / $totalSec)
                :put ("    >> Download: " . ($bps / 1000000) . " Mbit/s  (" . ($bps / 1000) . " Kbit/s)")
                :log info ("SpeedTest: download=" . ($bps / 1000000) . " Mbit/s  server=" . $url . "  elapsed=" . $elapsedStr)
            } else={
                :put "    Час < 1 с — test file is too small."
                :log warning "SpeedTest: elapsed < 1s — result unreliable"
            }
            :set fetchOk true
        } on-error={
            :put "    Server is unreachable, try the next one..."
            :do { /file remove [find name=$tmpFile] } on-error={}
        }
    }
}

:if (!$fetchOk) do={
    :put "Error: no response from test servers."
    :log error "SpeedTest: all download servers failed"
}

:put ""
:put "============================================================"
:put " Test completed."
:put "============================================================"
