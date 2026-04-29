# MikroTik RouterOS — WAN Failover Scripts

Набір скриптів для MikroTik RB4011iGS+5HacQ2HnD (RouterOS 7.x) для налаштування мульти-WAN з автоматичним failover поверх заводської конфігурації.

---

## Файли

### `change_default_net.rsc`
Змінює підмережу LAN з заводської `192.168.88.0/24` на `192.168.0.0/24`.

Що робить:
- Переписує IP-адресу bridge-інтерфейсу: `192.168.88.1` → `192.168.0.1`
- Оновлює DHCP-пул: `192.168.0.10–192.168.0.254`
- Оновлює налаштування DHCP-сервера (шлюз, мережа, DNS)

Після виконання роутер доступний на `192.168.0.1`.

> **Увага:** не підключай до WAN-портів роутери, що роздають адреси з мережі `192.168.0.0/24`. LAN цього MikroTik використовує ту саму підмережу — виникне конфлікт маршрутизації, і RouterOS не зможе відрізнити трафік до локальних пристроїв від трафіку до шлюзу ISP.

---

### `pppoe_wan_connection_setup.rsc`
Налаштовує PPPoE-з'єднання на `ether1` як основний WAN (distance=1).

Що робить:
- Вимикає DHCP-клієнт на `ether1` (конфліктує з PPPoE)
- Додає PPPoE-клієнт `pppoe-out1` (потрібно вказати логін/пароль провайдера)
- Додає NAT masquerade для вихідного трафіку через PPPoE
- Додає базові firewall-правила: allow established/related, drop invalid, allow ICMP з WAN, drop решти

**Перед використанням:** замінити `PPPOE_USER` та `PPPOE_PASSWORD` на дані провайдера.

---

### `pppoe_wan_failover_extention.rsc`
Розширення до попереднього скрипта — додає `ether2` (WAN2, distance=2) та `ether3` (WAN3, distance=3) через DHCP як резервні канали.

Що робить:
- Виносить `ether2` і `ether3` з LAN-bridge
- Додає DHCP-клієнти на обидва порти з автоматичним встановленням `check-gateway=ping` на маршрут після отримання IP
- Додає NAT masquerade для `ether2` і `ether3`
- Додає firewall-правила для захисту вхідного трафіку з нових WAN-портів

Логіка failover:
```
WAN1 (PPPoE, distance=1) → WAN2 (DHCP, distance=2) → WAN3 (DHCP, distance=3)
```
RouterOS автоматично перемикається на наступний маршрут при недоступності шлюзу.

---

### `dhcp_failover_v1.rsc`
Актуальна версія failover-конфігурації для схеми **2×WAN через DHCP** (без PPPoE) поверх заводських налаштувань.

Що робить:
- Виносить `ether2` з bridge і додає до списку `WAN`
- Налаштовує динамічні маршрути через скрипти: при кожному DHCP-bind автоматично прописується default route з `check-gateway=ping` та прив'язкою до інтерфейсу
- Перемикає обидва DHCP-клієнти в режим `add-default-route=no` (маршрути керуються скриптами)
- Встановлює DNS `1.1.1.1`, `8.8.8.8`, таймзону `Europe/Kiev` та NTP

Особливість: прив'язка маршруту до інтерфейсу (`gateway%ether1`) вирішує проблему ECMP, коли обидва провайдери видають однаковий шлюз (наприклад, `192.168.0.1`).

---

### `general_speed_test.rsc`
Перевіряє швидкість і якість інтернет-з'єднання засобами самого роутера.

Що робить (три кроки):
1. **Активний маршрут** — показує поточний default gateway і distance (корисно при failover, щоб одразу бачити який WAN активний)
2. **Ping-латентність** — пінгує `1.1.1.1`, `8.8.8.8`, `google.com`; виводить середній RTT і packet loss по кожному хосту
3. **Download** — завантажує тестовий файл ~100 МБ через `/tool fetch`, вимірює час і обчислює швидкість у Mbit/s

Результати виводяться в консоль і записуються в `/log` (тег `SpeedTest`).

**Передумова:** `/tool fetch` має бути дозволений у device-mode:
```
/system device-mode print
/system device-mode update fetch=yes
```
Після другої команди натиснути кнопку Reset на пристрої протягом 5 хвилин для підтвердження.

Запуск:
```
/import file-name=general_speed_test.rsc
```

Або як повторно викликаний скрипт:
```
/system script add name=speed-test source=[/file get [find name=general_speed_test.rsc] contents]
/system script run speed-test
```

Налаштування — змінна `dlUrls` на початку файлу. Скрипт пробує URL по черзі і використовує перший доступний. Перевірити URL вручну:
```
/tool fetch url="<url>" dst-path=test.bin mode=http
```

Обмеження:
- Upload не вимірюється (`/tool fetch` підтримує лише GET)

---

### `dhcp_pppoe_failover_v0.rsc`
Стара (v0) версія конфігурації зі змішаним підходом: DHCP на `ether1` і `ether3`, PPPoE на `ether2`. Містить відомі проблеми з надійністю перемикання та логуванням Netwatch. Збережено як референс.

---

## Повний цикл налаштування failover з нуля

### Крок 0 — Скидання на завод та підключення

```
/system reset-configuration no-defaults=no skip-backup=no
```

Після перезавантаження підключитись до `192.168.88.1` через LAN-порт (`ether3`–`ether10`), встановити пароль адміністратора.

---

### Крок 1 — Зміна підмережі

```bash
scp change_default_net.rsc admin@192.168.88.1:change_default_net.rsc
```

У терміналі роутера:
```
/import file-name=change_default_net.rsc verbose=yes
```

Після виконання — перепідключитись до `192.168.0.1`.

> **Увага:** не підключай до WAN-портів роутери, що роздають адреси з мережі `192.168.0.0/24` — це спричинить конфлікт маршрутизації з LAN.

---

### Крок 2 — Налаштування PPPoE (WAN1)

Відкрити файл `pppoe_wan_connection_setup.rsc` і замінити:
- `PPPOE_USER` → логін провайдера
- `PPPOE_PASSWORD` → пароль провайдера

```bash
scp pppoe_wan_connection_setup.rsc admin@192.168.0.1:pppoe_wan_connection_setup.rsc
```

```
/import file-name=pppoe_wan_connection_setup.rsc verbose=yes
```

Перевірка:
```
/interface pppoe-client monitor pppoe-out1 once
/ping 8.8.8.8
```

---

### Крок 3 — Додаткові DHCP-з'єднання та failover

Підключити кабелі резервних провайдерів до `ether2` та `ether3`.

```bash
scp pppoe_wan_failover_extention.rsc admin@192.168.0.1:pppoe_wan_failover_extention.rsc
```

```
/import file-name=pppoe_wan_failover_extention.rsc verbose=yes
```

Перевірка:
```
/ip dhcp-client print
/ip route print where dst-address=0.0.0.0/0
/ip firewall nat print
```

Тест failover: від'єднати кабель з `ether1` — за ~10 секунд трафік перейде на `ether2`. Повернути кабель — трафік повернеться на PPPoE автоматично.

---

## Схема портів

| Порт    | Роль              | З'єднання     | Distance |
|---------|-------------------|---------------|----------|
| ether1  | WAN1 (основний)   | PPPoE         | 1        |
| ether2  | WAN2 (резерв 1)   | DHCP          | 2        |
| ether3  | WAN3 (резерв 2)   | DHCP          | 3        |
| ether4–10 | LAN             | bridge        | —        |

## Обмеження

`check-gateway=ping` пінгує шлюз провайдера (перший хоп), а не зовнішній інтернет. Якщо шлюз ISP живий, але BGP/інтернет недоступний — автоматичного перемикання не відбудеться. Для продакшн-середовища рекомендується додатково налаштувати `/tool netwatch` з пінгом зовнішніх IP (наприклад, `1.1.1.1`) та скриптами ручного керування маршрутами.
