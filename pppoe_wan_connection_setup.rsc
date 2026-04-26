# =============================================================================
# MikroTik RB4011iGS+5HacQ2HnD  |  RouterOS 7.2.7
# Базове налаштування 2xWAN (DHCP) з failover ПОВЕРХ заводських defaults.
# -----------------------------------------------------------------------------
# Робочий цикл для тестування:
#   1) Скинь на завод (роутер перезавантажиться):
#        /system reset-configuration no-defaults=no skip-backup=no
#   2) Після ребуту підключись до 192.168.88.1 з LAN-порту (ether3..ether10).
#      Логін: admin, пароль стандартний.
#      Налаштуй новий пароль для admin.
#   3) Залий цей файл на роутер:
#        scp pppoe_wan_connection_setup.rsc admin@192.168.88.1:pppoe_wan_connection_setup.rsc
#        (або будь-яким іншим зручним способом; можна навіть створити скрипт в Winbox і вставити код вручну)
#   4) У терміналі роутера:
#        /import file-name=pppoe_wan_connection_setup.rsc verbose=yes
#
# Передумови:
#   - ether1 — порт, підключений до лінії провайдера
#   - замінити YOUR_LOGIN та YOUR_PASSWORD на дані провайдера

# Для налаштування потібно заван

# ---------- 1. PPPoE-клієнт ----------
/interface pppoe-client add \
    name=pppoe-out1 \
    interface=ether1 \
    user="PPPOE_USER" \
    password="PPPOE_PASSWORD" \
    add-default-route=yes \
    default-route-distance=1\ 
    use-peer-dns=yes \
    disabled=no

# ---------- 2. Firewall — базовий NAT (masquerade) ----------
# Весь трафік з локальної мережі виходить через PPPoE-інтерфейс
/ip firewall nat add \
    chain=srcnat \
    out-interface=pppoe-out1 \
    action=masquerade \
    comment="PPPoE WAN masquerade"

# ---------- 3. Firewall — захист вхідного трафіку ----------
# Дозволяємо вже встановлені/пов'язані з'єднання та ICMP, решту дропаємо
/ip firewall filter
add chain=input connection-state=established,related action=accept comment="allow established/related"
add chain=input connection-state=invalid action=drop     comment="drop invalid"
add chain=input in-interface=pppoe-out1 protocol=icmp action=accept comment="allow ICMP from WAN"
add chain=input in-interface=pppoe-out1 action=drop     comment="drop all other WAN input"

# ---------- 4. DNS ----------
# Якщо провайдер не надає DNS автоматично — задати вручну
# /ip dns set servers=8.8.8.8,1.1.1.1 allow-remote-requests=yes

# ---------- 5. Перевірка ----------
# /interface pppoe-client monitor pppoe-out1 once
# /ip address print
# /ip route print
# /ping 8.8.8.8
