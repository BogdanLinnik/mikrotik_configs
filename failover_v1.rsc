# =========================
# DHCP (вимикаємо default route)
# =========================
/ip dhcp-client
set [find interface=ether1] add-default-route=no use-peer-dns=yes
add interface=ether2 add-default-route=no use-peer-dns=yes

# =========================
# Recursive маршрути
# =========================
/ip route
add dst-address=8.8.8.8 gateway=ether1 scope=10 comment="check-wan1"
add dst-address=1.1.1.1 gateway=ether2 scope=10 comment="check-wan2"

add dst-address=0.0.0.0/0 gateway=8.8.8.8 distance=1 comment="WAN1"
add dst-address=0.0.0.0/0 gateway=1.1.1.1 distance=2 comment="WAN2"

# =========================
# Netwatch (простий варіант)
# =========================
/tool netwatch
add host=8.8.8.8 interval=10s timeout=2s \
down-script=":log warning \"WAN1 down\"; /ip route disable [find comment=\"WAN1\"]" \
up-script=":delay 15s; :log warning \"WAN1 up\"; /ip route enable [find comment=\"WAN1\"]"