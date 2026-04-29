# =============================================================================
# MikroTik RB4011iGS+5HacQ2HnD  |  RouterOS 7.2.7
# Мінімальний тест швидкості — виводить лише Mbit/s
# =============================================================================
# Призначений для використання в інших скриптах або автоматизації,
# де потрібне лише числове значення поточної download-швидкості.
#
# Запуск:
#   /import file-name=basic_speed_test.rsc
# =============================================================================

:local dlUrls {
    "http://cachefly.cachefly.net/100mb.test";
    "http://speedtest-nl.belhost.com/100mb.bin";
    "http://speedtest.tele2.net/100MB.zip";
}
:local tmpFile "sptest.tmp"

:do { /file remove [find name=$tmpFile] } on-error={}

:local fetchOk false
:foreach url in=$dlUrls do={
    :if (!$fetchOk) do={
        :local t1 [/system resource get uptime]
        :do {
            /tool fetch url=$url dst-path=$tmpFile mode=http
            :local t2 [/system resource get uptime]

            :local elapsedStr [:tostr ($t2 - $t1)]
            :local actual     0
            :do { :set actual [/file get [find name=$tmpFile] size] } on-error={}
            :do { /file remove [find name=$tmpFile] } on-error={}

            :local c1 [:find $elapsedStr ":"]
            :local c2 [:find $elapsedStr ":" ($c1 + 1)]
            :local totalSec 0
            :if ($c1 >= 0 && $c2 > $c1) do={
                :local hh [:tonum [:pick $elapsedStr 0 $c1]]
                :local mm [:tonum [:pick $elapsedStr ($c1 + 1) $c2]]
                :local ss [:tonum [:pick $elapsedStr ($c2 + 1) [:len $elapsedStr]]]
                :set totalSec ($hh * 3600 + $mm * 60 + $ss)
            }

            :local dlSpeed 0
            :if ($totalSec >= 1) do={ :set dlSpeed ($actual * 8 / $totalSec / 1000000) }
            :put $dlSpeed
            :log info ("SpeedTest/basic: " . $dlSpeed . " Mbit/s")
            :set fetchOk true
        } on-error={
            :do { /file remove [find name=$tmpFile] } on-error={}
        }
    }
}
