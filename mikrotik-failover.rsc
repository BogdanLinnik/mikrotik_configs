# =============================================================================
# MikroTik RB4011iGS+5HacQ2HnD  |  RouterOS 7.2.7
# Базове налаштування 2xWAN (DHCP) з failover ПОВЕРХ заводських defaults.
# -----------------------------------------------------------------------------
# Робочий цикл для тестування:
#   1) /system reset-configuration no-defaults=no skip-backup=no
#      (роутер перезавантажиться й застосує стандартну заводську конфігурацію)
#   2) Після ребуту зайди у WinBox/SSH за адресою 192.168.88.1 з LAN-порту
#      (ether2..ether10). Логін: admin, пароль порожній (спершу спитає задати).
#      Якщо WinBox питає "Remove configuration" — НАТИСНИ "OK" лише якщо хочеш
#      прибрати defaults. Нам defaults потрібні, тому натискай вгорі "X"
#      (або просто пропусти це вікно).
#   3) Залий цей файл на роутер (Files -> drag&drop, або scp):
#        scp mikrotik-failover.rsc admin@192.168.88.1:mikrotik-failover.rsc
#   4) У терміналі роутера:
#        /import file-name=mikrotik-failover.rsc verbose=yes
#
# Що робить скрипт поверх defaults:
#   - Встановлює пароль admin = 12345678
#   - Виносить ether2 з bridge і додає його у список WAN
#   - Підключає DHCP-клієнт на ether2
#   - Переналаштовує DHCP-клієнт ether1: БЕЗ add-default-route (бо дефолти
#     додамо руками з check-gateway=ping для реального failover)
#   - Додає recursive-маршрути: WAN1 -> distance=1, WAN2 -> distance=2
#   - Фіксує DNS-сервери роутера (щоб не залежали від провайдера при failover)
#   - Ім'я пристрою, таймзона, NTP
#
# Default-и НЕ чіпаємо: bridge, IP на LAN, DHCP-сервер, фаєрвол, NAT
# (masquerade на out-interface-list=WAN) — все це вже є й автоматично
# підхоплює ether2, щойно він опиниться у списку WAN.
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Пароль admin та ім'я пристрою
# -----------------------------------------------------------------------------
/user set [find name=admin] password="12345678"
/system identity set name=RB4011-lab

# -----------------------------------------------------------------------------
# 2. Виносимо ether2 із дефолтного bridge, бо він буде WAN2
# -----------------------------------------------------------------------------
/interface bridge port
remove [find interface=ether2]

# -----------------------------------------------------------------------------
# 3. Додаємо ether2 у список WAN
#    (ether1 уже в WAN за дефолтом; bridge уже в LAN)
# -----------------------------------------------------------------------------
/interface list member
add interface=ether2 list=WAN comment="WAN2 backup"

# -----------------------------------------------------------------------------
# 4. DHCP-клієнти на обох WAN
#    - На ether1 дефолтний DHCP-клієнт вже існує: правимо його (не додаємо!).
#    - add-default-route=no — дефолтні маршрути додамо руками нижче, щоб
#      мати check-gateway=ping для failover (на DHCP-маршрутах його немає).
#    - use-peer-dns=no — не пускаємо провайдерські DNS у /ip dns, щоб при
#      перемиканні WAN DNS не "плавали".
# -----------------------------------------------------------------------------
/ip dhcp-client
set [find interface=ether1] add-default-route=no use-peer-dns=no use-peer-ntp=no comment="WAN1"
add interface=ether2 add-default-route=no use-peer-dns=no use-peer-ntp=no disabled=no comment="WAN2"

# -----------------------------------------------------------------------------
# 5. Статичні DNS-сервери для роутера (LAN-клієнти звертаються на 192.168.88.1)
# -----------------------------------------------------------------------------
/ip dns set servers=1.1.1.1,8.8.8.8

# -----------------------------------------------------------------------------
# 6. Failover через recursive routing + check-gateway=ping
#
# Як працює:
#   - Для кожного WAN жорстко прив'язуємо "probe"-адресу (1.1.1.1 через ether1,
#     8.8.8.8 через ether2) з вузьким scope=10. Ці маршрути резолвляться
#     через gateway, що приходить по DHCP (динамічний connected route).
#   - Дефолтні маршрути дивляться на ці probe-адреси (target-scope=10) з
#     check-gateway=ping. Поки probe пінгується — дефолт активний.
#   - distance=1 (WAN1) пріоритетний, distance=2 (WAN2) — резерв.
#   - Падіння provider-side (коли лінк є, а інтернету немає) теж ловиться,
#     бо check-gateway=ping пінгує реальну адресу в інтернеті.
# -----------------------------------------------------------------------------
/ip route
add dst-address=1.1.1.1/32 gateway=ether1 scope=10 comment="probe via WAN1"
add dst-address=8.8.8.8/32 gateway=ether2 scope=10 comment="probe via WAN2"
add dst-address=0.0.0.0/0 gateway=1.1.1.1 distance=1 check-gateway=ping \
    target-scope=10 comment="default via WAN1 (primary)"
add dst-address=0.0.0.0/0 gateway=8.8.8.8 distance=2 check-gateway=ping \
    target-scope=10 comment="default via WAN2 (backup)"

# -----------------------------------------------------------------------------
# 7. Час
# -----------------------------------------------------------------------------
/system clock set time-zone-name=Europe/Kiev
/system ntp client set enabled=yes
/system ntp client servers
add address=pool.ntp.org

# =============================================================================
# Перевірка після /import:
#   /ip dhcp-client print
#       -> обидва клієнти у стані "bound", мають IP
#   /ip route print where dst-address=0.0.0.0/0
#       -> два дефолти; активний має прапор "A S", резервний просто "S"
#   /ip route print where dst-address~"1.1.1.1|8.8.8.8"
#       -> два probe-маршрути, обидва "A S"
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
