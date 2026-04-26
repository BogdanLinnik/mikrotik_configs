# =============================================================================
# MikroTik RB4011iGS+5HacQ2HnD  |  RouterOS 7.2.7
# WAN2 (ether2) і WAN3 (ether3) через DHCP + автоматичний failover
# =============================================================================
# Передумови:
#   - change_default_net.rsc та pppoe_wan_connection_setup.rsc вже виконані
#   - ether1 = PPPoE WAN1 (pppoe-out1, distance=1) — вже налаштовано
#   - ether2 = DHCP WAN2 (distance=2) — підключений до провайдера
#   - ether3 = DHCP WAN3 (distance=3) — підключений до провайдера
#
# Порядок застосування:
#   scp pppoe_wan_failover_extention.rsc admin@192.168.0.1:pppoe_wan_failover_extention.rsc
#   /import file-name=pppoe_wan_failover_extention.rsc verbose=yes
#
# Логіка failover:
#   RouterOS вибирає маршрут з найменшою дистанцією серед активних.
#   check-gateway=ping перевіряє досяжність ISP-шлюзу (не тільки стан інтерфейсу).
#
#   WAN1 (PPPoE) пропав       → трафік іде через WAN2 (distance=2)
#   WAN1 і WAN2 пропали       → трафік іде через WAN3 (distance=3)
#   WAN1 відновився           → RouterOS повертає трафік на нього автоматично
#
# Примітка:
#   check-gateway=ping виявляє недоступність ISP-шлюзу (обрив NAT, аварія шлюзу).
#   Якщо потрібен контроль інтернет-доступності (шлюз живий, але BGP впав) —
#   додатково налаштуйте /tool netwatch з пінгом зовнішнього IP (напр. 1.1.1.1)
#   і скриптами, що керують маршрутами вручну.
# =============================================================================

# ---------- 1. Видаляємо ether2 і ether3 з LAN-bridge ----------
# У заводській конфігурації ether2..ether10 входять до LAN-bridge.
# Щоб використовувати їх як WAN — прибираємо з bridge.
/interface bridge port
remove [find interface=ether2]
remove [find interface=ether3]

# ---------- 2. DHCP-клієнти на WAN2 і WAN3 ----------
# add-default-route=yes   — DHCP-клієнт сам додає default route через отриманий шлюз
# default-route-distance  — пріоритет маршруту (менше = вищий пріоритет)
# use-peer-dns=no         — не перезаписуємо DNS від кількох провайдерів
# script                  — після отримання IP встановлює check-gateway=ping
#                           на щойно доданий маршрут (:delay 2s — очікуємо
#                           поки DHCP-клієнт встигне додати маршрут)
/ip dhcp-client
add interface=ether2 \
    add-default-route=yes \
    default-route-distance=2 \
    use-peer-dns=no \
    disabled=no \
    comment="WAN2 DHCP" \
    script=":if (\$bound = 1) do={ :delay 2s; /ip route set [find dst-address=0.0.0.0/0 distance=2] check-gateway=ping }"

add interface=ether3 \
    add-default-route=yes \
    default-route-distance=3 \
    use-peer-dns=no \
    disabled=no \
    comment="WAN3 DHCP" \
    script=":if (\$bound = 1) do={ :delay 2s; /ip route set [find dst-address=0.0.0.0/0 distance=3] check-gateway=ping }"

# ---------- 3. NAT — masquerade для WAN2 і WAN3 ----------
/ip firewall nat
add chain=srcnat out-interface=ether2 action=masquerade comment="WAN2 masquerade"
add chain=srcnat out-interface=ether3 action=masquerade comment="WAN3 masquerade"

# ---------- 4. Firewall — захист вхідного трафіку з WAN2 і WAN3 ----------
# Правила "established/related accept" і "invalid drop" вже додані
# скриптом pppoe_wan_connection_setup.rsc і стосуються ВСІХ інтерфейсів.
# Тут додаємо тільки правила, специфічні для нових WAN-портів.
/ip firewall filter
add chain=input in-interface=ether2 protocol=icmp action=accept \
    comment="WAN2 allow ICMP"
add chain=input in-interface=ether2 action=drop \
    comment="WAN2 drop all other input"
add chain=input in-interface=ether3 protocol=icmp action=accept \
    comment="WAN3 allow ICMP"
add chain=input in-interface=ether3 action=drop \
    comment="WAN3 drop all other input"

# ---------- 5. Перевірка ----------
# /ip dhcp-client print
# /ip route print
# /ip firewall nat print
# /ip firewall filter print
# /ip address print
