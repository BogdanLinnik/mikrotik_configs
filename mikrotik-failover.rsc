# =============================================================================
# MikroTik RB4011iGS+5HacQ2HnD  |  RouterOS 7.2.7
# Базове налаштування 2xWAN (DHCP) з failover ПОВЕРХ заводських defaults.
# -----------------------------------------------------------------------------
# Робочий цикл для тестування:
#   1) Скинь на завод (роутер перезавантажиться):
#        /system reset-configuration no-defaults=no skip-backup=yes
#   2) Після ребуту підключись до 192.168.88.1 з LAN-порту (ether2..ether10).
#      Логін: admin, пароль порожній.
#      Якщо WinBox питає "Remove configuration" — натисни "X" (НЕ "OK").
#   3) Залий цей файл на роутер:
#        scp mikrotik-failover.rsc admin@192.168.88.1:mikrotik-failover.rsc
#   4) У терміналі роутера:
#        /import file-name=mikrotik-failover.rsc verbose=yes
#
# ЧОМУ НЕ run-after-reset: цей скрипт — overlay поверх заводських defaults.
# run-after-reset ЗАМІНЮЄ дефолтну конфігурацію (не доповнює), тому bridge,
# LAN IP, DHCP-сервер, NAT — нічого з цього не буде.
#
# Що робить скрипт поверх defaults:
#   - Виносить ether2 з bridge і додає його у список WAN
#   - Підключає DHCP-клієнт на ether2
#   - Переналаштовує DHCP-клієнт ether1: БЕЗ add-default-route
#   - Probe-маршрути та дефолти прописуються ДИНАМІЧНО через DHCP-скрипти
#     (шлюз читається з /ip dhcp-client, тому працює при будь-яких IP від ISP)
#   - Фіксує DNS-сервери роутера (щоб не залежали від провайдера при failover)
#   - Ім'я пристрою, таймзона, NTP
#
# Default-и НЕ чіпаємо: bridge, IP на LAN, DHCP-сервер, фаєрвол, NAT
# (masquerade на out-interface-list=WAN) — все це вже є й автоматично
# підхоплює ether2, щойно він опиниться у списку WAN.
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Виносимо ether2 із дефолтного bridge, бо він буде WAN2
# -----------------------------------------------------------------------------
/interface bridge port
remove [find interface=ether2]

# -----------------------------------------------------------------------------
# 2. Додаємо ether2 у список WAN
#    (ether1 уже в WAN за дефолтом; bridge уже в LAN)
# -----------------------------------------------------------------------------
/interface list member
add interface=ether2 list=WAN comment="WAN2 backup"

# -----------------------------------------------------------------------------
# 3. Статичні DNS-сервери для роутера
# -----------------------------------------------------------------------------
/ip dns set servers=1.1.1.1,8.8.8.8

# -----------------------------------------------------------------------------
# 4. Failover routing — скрипти з динамічним шлюзом
#
# Як працює:
#   - Default route прямо на gateway ISP з прив'язкою до інтерфейсу (%ether1/2).
#     Прив'язка необхідна, бо обидва TP-Link можуть мати однаковий IP (192.168.0.1):
#     без неї RouterOS балансує між ether1/ether2 (ECMP).
#   - check-gateway=ping моніторить доступність gateway. Якщо TP-Link недоступний —
#     маршрут деактивується і трафік переходить на резервний WAN.
#   - distance=1 (WAN1) пріоритетний, distance=2 (WAN2) — резерв.
#   - ОБМЕЖЕННЯ: check-gateway=ping пінгує TP-Link (не ISP). Якщо TP-Link живий,
#     але ISP впав — автоперемикання НЕ відбудеться. Для виробничого середовища
#     потрібен окремий скрипт моніторингу інтернету.
#
# ЧОМУ НЕ recursive routing (через 1.1.1.1): RouterOS 7 не підтримує
# check-gateway=ping з non-connected gateway — immediate-gw залишається порожнім
# і маршрут завжди Is (Inactive).
#
# Скрипти визначаємо ДО налаштування DHCP-клієнтів, щоб при першому ж
# bind-евенті вони вже існували в системі.
# -----------------------------------------------------------------------------
/system script
add name=wan1-route-update source=":local gw [/ip dhcp-client get [find interface=ether1] gateway]\r\n:if (\$gw != \"\") do={\r\n    :local gwIface (\$gw . \"%ether1\")\r\n    /ip route remove [find comment=\"default via WAN1 (primary)\"]\r\n    /ip route add dst-address=0.0.0.0/0 gateway=\$gwIface distance=1 check-gateway=ping comment=\"default via WAN1 (primary)\"\r\n}"
add name=wan2-route-update source=":local gw [/ip dhcp-client get [find interface=ether2] gateway]\r\n:if (\$gw != \"\") do={\r\n    :local gwIface (\$gw . \"%ether2\")\r\n    /ip route remove [find comment=\"default via WAN2 (backup)\"]\r\n    /ip route add dst-address=0.0.0.0/0 gateway=\$gwIface distance=2 check-gateway=ping comment=\"default via WAN2 (backup)\"\r\n}"

# -----------------------------------------------------------------------------
# 5. DHCP-клієнти на обох WAN
#    - add-default-route=no — маршрути управляємо через скрипти вище
#    - use-peer-dns=no — не пускаємо провайдерські DNS у /ip dns
#    - script= — викликається при кожній зміні стану (bound / renew / unbound)
# -----------------------------------------------------------------------------
/ip dhcp-client
set [find interface=ether1] add-default-route=no use-peer-dns=no use-peer-ntp=no comment="WAN1" script="/system script run wan1-route-update"
add interface=ether2 add-default-route=no use-peer-dns=no use-peer-ntp=no disabled=no comment="WAN2" script="/system script run wan2-route-update"

# Запускаємо одразу — для випадку, коли DHCP-клієнти вже були bound до імпорту
/system script run wan1-route-update
/system script run wan2-route-update

# -----------------------------------------------------------------------------
# 6. Час
# -----------------------------------------------------------------------------
/system clock set time-zone-name=Europe/Kiev
/system ntp client set enabled=yes
/system ntp client servers
add address=pool.ntp.org

# =============================================================================
# Перевірка після /import:
#   /ip dhcp-client print
#       -> обидва клієнти у стані "bound", мають IP + gateway
#   /ip route print where dst-address=0.0.0.0/0
#       -> два дефолти; активний має прапор "A S", резервний просто "S"
#   /tool traceroute 8.8.8.8
#       -> видно, через який аплінк іде трафік
#
# Тест failover:
#   - висмикни кабель з ether1 -> за ~10 сек трафік переїде на ether2;
#   - встроми назад -> через ~10 сек повернеться на ether1.
#
# Якщо в процесі експериментів пароль admin десь "злетів", його завжди
# можна виставити наново:  /user set [find name=admin] password="12345678"
# =============================================================================
