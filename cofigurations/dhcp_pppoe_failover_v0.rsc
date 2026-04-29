# НАЛАШТУВАННЯ ROUTER OS 7 З АВТОМАТИЧНИМ ПЕРЕМИКАННЯМ АКТИВНОГО WAN ІНТЕРФЕЙСУ ПРИ ВТРАТІ З'ЄДНАННЯ

# Відомі проблеми - 
# 1. При зміні стану активного підключення (підключення перервалось або навпаки відновилось) з невідомих наразі причин перемикання не завжди відбувається на порт з найвищим пріоритетом. 
# 2. Netwatch не веде актуальних логів перемикань та невірно відображає стан підключень. Можливо це є коренем проблеми 1.
# 3. Канал пише про помилку підключення при спробі підключення

# Процес налаштування - 

# 1. Видалення 2 та 3го інтерфейсів з бріджа
/interface bridge port

remove [find interface=ether2]
remove [find interface=ether3]

# 2. Видалення стандартного dhcp клієнта для 1го інтерфейсу
/ip dhcp-client

remove [find interface=ether1]

# 3. Налаштування dhcp клієнтів для першого і третього інтерфейсу
/ip dhcp-client
add interface=ether1 disabled=no add-default-route=yes default-route-distance=1  use-peer-dns=no comment="WAN1-primary"


add interface=ether3 disabled=no add-default-route=yes default-route-distance=20 use-peer-dns=no comment="WAN3-emergency"

# 4. Налаштування PPPoE клієнта для другого інтерфейсу
/interface pppoe-client
add name=pppoe-wan2 interface=ether2 user="your_login" password="your_password"  disabled=no add-default-route=yes default-route-distance=10 use-peer-dns=no comment="WAN2-backup"


# 5. Налаштування NAT для dhcp підключення на прикладі 3го інтерфейсу. NAT для 1го інтерфейсу залишається стандартним якщо перший інтерфейс використовує dhcp клієнт.
/ip firewall nat add chain=srcnat out-interface=ether3 action=masquerade comment="NAT WAN3"

# 6. Налаштування NAT для PPPoE підключення на прикладі 2го інтерфейсу.
/ip firewall nat add chain=srcnat out-interface=pppoe-wan2 action=masquerade comment="NAT WAN2 PPPoE" 

# 7. Налаштування DNS
/ip dns set servers=8.8.8.8,1.1.1.1 allow-remote-requests=yes

# 8. Логування переходу між інтерфейсами за допомогою Netwatch
/tool netwatch
add host=8.8.8.8 interval=10s timeout=3s comment="Check-WAN1" up-script=":log info \"WAN1 UP - active route restored (priority 1)\"" down-script=":log warning \"WAN1 DOWN - failover to lower priority\""

add host=8.8.8.9 interval=10s timeout=3s comment="Check-WAN2" up-script=":log info \"WAN2 UP - route available (priority 2)\"" down-script=":log warning \"WAN2 DOWN - WAN2 unavailable\""

add host=8.8.4.4 interval=10s timeout=3s comment="Check-WAN3" up-script=":log info \"WAN3 UP - route available (priority 3)\"" down-script=":log warning \"WAN3 DOWN - WAN3 unavailable\""

# 9. Тестування dhcp клієнта - всі клієнти мають бути bound (якщо є фізичне підключення) і без флагу I
/ip dhcp-client print

# 10. Тестування PPPoE клієнта - всі клієнти мають бути bound (якщо є фізичне підключення) і без флагу I
/interface pppoe-client print

# 11. Перевірка вірного вибору активного маршруту distance=1
/ip route print where dst-address=0.0.0.0/0


