# MikroTik RouterOS — WAN Failover Scripts

Набір скриптів для MikroTik RB4011iGS+5HacQ2HnD (RouterOS 7.x) для налаштування мульти-WAN з автоматичним failover поверх заводської конфігурації.

---

## Структура проекту

```
cofigurations/
    change_default_net.rsc          — зміна LAN-підмережі
    pppoe_wan_connection_setup.rsc  — налаштування PPPoE WAN1
    pppoe_wan_failover_extention.rsc — додавання DHCP WAN2/WAN3
    dhcp_failover_v1.rsc            — failover для схеми 2×DHCP
    dhcp_pppoe_failover_v0.rsc      — стара версія (референс)

speed_tests/
    general.rsc  — повний тест: маршрут, ping, download
    basic.rsc    — мінімальний тест: лише Mbit/s

notifications/
    low_speed.rsc  — Discord-сповіщення при падінні швидкості нижче порогу
```

---

## Файли

### `cofigurations/change_default_net.rsc`
Змінює підмережу LAN з заводської `192.168.88.0/24` на `192.168.0.0/24`.

Що робить:
- Переписує IP-адресу bridge-інтерфейсу: `192.168.88.1` → `192.168.0.1`
- Оновлює DHCP-пул: `192.168.0.10–192.168.0.254`
- Оновлює налаштування DHCP-сервера (шлюз, мережа, DNS)

Після виконання роутер доступний на `192.168.0.1`.

> **Увага:** не підключай до WAN-портів роутери, що роздають адреси з мережі `192.168.0.0/24`. LAN цього MikroTik використовує ту саму підмережу — виникне конфлікт маршрутизації, і RouterOS не зможе відрізнити трафік до локальних пристроїв від трафіку до шлюзу ISP.

---

### `cofigurations/pppoe_wan_connection_setup.rsc`
Налаштовує PPPoE-з'єднання на `ether1` як основний WAN (distance=1).

Що робить:
- Вимикає DHCP-клієнт на `ether1` (конфліктує з PPPoE)
- Додає PPPoE-клієнт `pppoe-out1` (потрібно вказати логін/пароль провайдера)
- Додає NAT masquerade для вихідного трафіку через PPPoE
- Додає базові firewall-правила: allow established/related, drop invalid, allow ICMP з WAN, drop решти

**Перед використанням:** замінити `PPPOE_USER` та `PPPOE_PASSWORD` на дані провайдера.

---

### `cofigurations/pppoe_wan_failover_extention.rsc`
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

### `cofigurations/dhcp_failover_v1.rsc`
Актуальна версія failover-конфігурації для схеми **2×WAN через DHCP** (без PPPoE) поверх заводських налаштувань.

Що робить:
- Виносить `ether2` з bridge і додає до списку `WAN`
- Налаштовує динамічні маршрути через скрипти: при кожному DHCP-bind автоматично прописується default route з `check-gateway=ping` та прив'язкою до інтерфейсу
- Перемикає обидва DHCP-клієнти в режим `add-default-route=no` (маршрути керуються скриптами)
- Встановлює DNS `1.1.1.1`, `8.8.8.8`, таймзону `Europe/Kiev` та NTP

Особливість: прив'язка маршруту до інтерфейсу (`gateway%ether1`) вирішує проблему ECMP, коли обидва провайдери видають однаковий шлюз (наприклад, `192.168.0.1`).

---

### `cofigurations/dhcp_pppoe_failover_v0.rsc`
Стара (v0) версія конфігурації зі змішаним підходом: DHCP на `ether1` і `ether3`, PPPoE на `ether2`. Містить відомі проблеми з надійністю перемикання та логуванням Netwatch. Збережено як референс.

---

### `speed_tests/general.rsc`
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
/import file-name=speed_tests/general.rsc
```

Або як повторно викликаний скрипт:
```
/system script add name=speed-test source=[/file get [find name=speed_tests/general.rsc] contents]
/system script run speed-test
```

Налаштування — змінна `dlUrls` на початку файлу. Скрипт пробує URL по черзі і використовує перший доступний. Перевірити URL вручну:
```
/tool fetch url="<url>" dst-path=test.bin mode=http
```

Обмеження:
- Upload не вимірюється (`/tool fetch` підтримує лише GET)

---

### `speed_tests/basic.rsc`
Мінімальна версія тесту швидкості — виводить лише одне число: поточна download-швидкість у Mbit/s.

Призначений для автоматизації: виклику з інших скриптів, планувальника або моніторингу, де повний вивід `general.rsc` зайвий.

Запуск:
```
/import file-name=speed_tests/basic.rsc
```

Вивід — одне число:
```
17
```

Результат також записується в `/log` з тегом `SpeedTest/basic`. При запуску через `/system scheduler` `:put` нікуди не виводиться — результат залишається тільки в лозі:
```
/log print where message~"SpeedTest/basic"
```

> **Примітка:** `/tool fetch` завжди друкує прогрес завантаження (status/downloaded/duration) — це поведінка RouterOS яку не можна вимкнути параметрами. При запуску через планувальник цей вивід не з'являється в терміналі.

---

### `notifications/low_speed.rsc`
Вимірює download-швидкість і надсилає повідомлення у Discord якщо результат нижче порогу.

Параметри на початку файлу:
- `speedThreshold` — мінімально допустима швидкість у Mbit/s (за замовчуванням `50`)
- `discordWebhook` — URL Discord Webhook (отримати: Server Settings → Integrations → Webhooks → New Webhook → Copy Webhook URL)

Що робить:
1. Завантажує тестовий файл ~100 МБ через `/tool fetch`, обчислює швидкість у Mbit/s
2. Якщо результат нижче `speedThreshold` — надсилає повідомлення у Discord і пише `warning` у `/log`
3. Завжди пише поточну швидкість у `/log` з тегом `SpeedMonitor` (незалежно від порогу)

**Передумова:** `/tool fetch` має бути дозволений у device-mode (так само як для speed_tests).

Запуск вручну:
```
/import file-name=notifications/low_speed.rsc
```

Автоматичний запуск через планувальник (наприклад, кожні 30 хвилин):
```
/system script add name=speed-monitor \
    source=[/file get [find name=notifications/low_speed.rsc] contents]
/system scheduler add name=speed-monitor interval=30m \
    on-event="/system script run speed-monitor"
```

Переглянути лог:
```
/log print where message~"SpeedMonitor"
```

> **Примітка:** Discord Webhook URL є секретом — не комітьте файл з реальним URL у відкритий репозиторій.

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
scp cofigurations/change_default_net.rsc admin@192.168.88.1:change_default_net.rsc
```

У терміналі роутера:
```
/import file-name=change_default_net.rsc verbose=yes
```

Після виконання — перепідключитись до `192.168.0.1`.

> **Увага:** не підключай до WAN-портів роутери, що роздають адреси з мережі `192.168.0.0/24` — це спричинить конфлікт маршрутизації з LAN.

---

### Крок 2 — Налаштування PPPoE (WAN1)

Відкрити файл `cofigurations/pppoe_wan_connection_setup.rsc` і замінити:
- `PPPOE_USER` → логін провайдера
- `PPPOE_PASSWORD` → пароль провайдера

```bash
scp cofigurations/pppoe_wan_connection_setup.rsc admin@192.168.0.1:pppoe_wan_connection_setup.rsc
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
scp cofigurations/pppoe_wan_failover_extention.rsc admin@192.168.0.1:pppoe_wan_failover_extention.rsc
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
