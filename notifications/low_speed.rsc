# =============================================================================
# MikroTik RB4011iGS+5HacQ2HnD  |  RouterOS 7.2.7
# Моніторинг швидкості — Slack-сповіщення при падінні нижче порогу
# =============================================================================
# Вимірює download-швидкість і надсилає повідомлення у Slack якщо
# результат нижче speedThreshold Mbit/s.
#
# Передумови:
#   - /tool fetch дозволений у device-mode (/system device-mode update fetch=yes)
#   - Slack Incoming Webhook URL вставлений у змінну slackWebhook
#     (створити на: https://api.slack.com/messaging/webhooks)
#
# Запуск вручну:
#   /import file-name=notifications/low_speed.rsc
#
# Автоматичний запуск (наприклад, кожні 30 хв):
#   /system script add name=speed-monitor \
#       source=[/file get [find name=notifications/low_speed.rsc] contents]
#   /system scheduler add name=speed-monitor interval=30m \
#       on-event="/system script run speed-monitor"
# =============================================================================

# ---- Параметри ---------------------------------------------------------------
:local speedThreshold 50
:local slackWebhook   "SLACK_WEBHOOK_URL"
:local dlUrls {
    "http://cachefly.cachefly.net/100mb.test";
    "http://speedtest-nl.belhost.com/100mb.bin";
    "http://speedtest.tele2.net/100MB.zip";
}
:local tmpFile "sptest_notify.tmp"
# ------------------------------------------------------------------------------

# ---- Вимірювання швидкості ---------------------------------------------------
:do { /file remove [find name=$tmpFile] } on-error={}

:local dlSpeed    0
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

            :if ($totalSec >= 1) do={ :set dlSpeed ($actual * 8 / $totalSec / 1000000) }
            :set fetchOk true
        } on-error={
            :do { /file remove [find name=$tmpFile] } on-error={}
        }
    }
}

:log info ("SpeedMonitor: " . $dlSpeed . " Mbit/s  threshold=" . $speedThreshold)

# ---- Slack-сповіщення --------------------------------------------------------
:if ($dlSpeed < $speedThreshold) do={
    :local msg ("{\"text\":\"[MikroTik] Low speed: " . $dlSpeed . " Mbit/s (threshold: " . $speedThreshold . " Mbit/s) | " . [/system clock get date] . " " . [/system clock get time] . "\"}")
    :do {
        /tool fetch url=$slackWebhook mode=https \
            http-method=post \
            http-header-field="Content-Type: application/json" \
            http-data=$msg \
            dst-path=slack_resp.tmp
        :do { /file remove [find name=slack_resp.tmp] } on-error={}
        :log warning ("SpeedMonitor: Slack notification sent (" . $dlSpeed . " Mbit/s)")
    } on-error={
        :log error "SpeedMonitor: failed to send Slack notification"
    }
}
