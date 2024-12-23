# Docker dynamic Access Control List

## Для чего
Дополнительный фактор защиты. С развитием docker стало возможным внутри контейнера создать правила iptables, которые будут запрещать доступ к порту. При этом можно создать правила, которые с одной стороны не изменят для пользователей привычного механизма доступа к защищаемому сервису. С другой стороны усложнят (**но, не исключат полностью**) определение наличия открытого порта защищаемого сервиса (злоумышленниками или специализированными поисковыми сервисами вроде [Censys](https://search.censys.io/)). **Полезно для сервисов, которые не должны быть общедоступны.** Обычно правила межсетевых экранов создавали администраторы (или иные специалисты, но не DevOps). И на них была обязанность по корректной настройке правил (и содержания их верными). Теперь создатель контейнера может "перестраховаться" (если правила межсетевых экранов окажутся неактивными по каким-то причинам) и создать свои правила прямо в контейнере. Динамические правила ACL (Access Control List) полезны в случаях, когда заранее неизвестно какие IP-адреса клиентов нужно внести в список (например, если у клиента меняется адрес из-за смены его локации или использования мобильного оператора).
Внедрение данной защиты также потенциально увеличит доступное время для устранения уязвимости ([пока её не начнут пытаться эксплуатировать на защищаемом сервисе](https://rezbez.ru/reviews/chto-delat-kogda-vse-uyazvimosti-odinakovo-opasny)). Т.к. для эксплуатации нужно ещё обнаружить уязвимый сервис. Также это уменьшит размер логов защищаемых сервисов (т.к. в них реже будут попадать попытки подключений, связанные со сканированием). Что упрощает анализ логов (для расследования инцидентов или дебага). Решение может использоваться не только в докере, а на любой Linux-системе.
**В отличие от fail2ban, задача - снизить обнаружение сервиса, а не пытаться бороться с последствиями (брутфорс, эксплуатация), когда сервис уже обнаружен.**

## Как это работает

В iptables создаётся правило, запрещающее доступ к определённому TCP-порту (порту защищаемого сервиса).
knockd согласно своему конфигурационному файлу ожидает *определённое количество попыток обращения пользователя за определённый промежуток времени* на порт защищаемого сервиса (TCP пакетов с флагом SYN). В случае выполнения этого условия IP-адрес пользователя **временно** заносится в список разрешённых ACL.

При запуске *creator.sh* спрашивает пользователя данные, необходимые для генерации конфигурации:

• название правила для knockd;

• номер порта защищаемой службы;

• количество повторов, которые должны произойти, чтоб пользователь попал в ACL;

• за какое время должны эти повторы произойти;

• на какое время включить IP-адрес в ACL ([не более 2147483 секунд](https://ipset.netfilter.org/ipset.man.html#lbAJ)).

Можно создать несколько правил (для разных портов). После чего *creator.sh* создаст конфигурационный файл *knockd.conf* и *DACL.sh* (с правилами для iptables и ipset). При повторном запуске *creator.sh* файлы перезаписываются. Нужно будет перенести эти файлы в контейнер. `knockd.conf` поместить в `/etc/`. *DACL.sh* запустить в любом месте.

## Зависимости

На контейнере должны быть установлены: [iptables](https://ipset.netfilter.org/iptables.man.html), [ipset](https://ipset.netfilter.org/ipset.man.html), [knockd](https://linux.die.net/man/1/knockd)


## Особенности эксплуатации

Для работы iptables контейнер docker должен быть запущен с параметром `--cap-add=NET_ADMIN` (см. [вопросы безопасности](https://habr.com/ru/articles/855536/#netadmin), связанные с использованием capability NET_ADMIN).

Количество необходимых повторов напрямую влияет на время, через которое пользователь сможет получить доступ к защищаемому сервису (пока IP-адрес пользователя не попадёт в список ACL). Для OpenSSH сервера (Ubuntu 22.04) подключение стандартным клиентом с Ubuntu 22.04 показало: 3 повтора - 3 секунды ожидания. 6 повторов - 6 сек.

Повторов должно быть не менее 2-х: 1 повтор означает его отсутствие, такой сервис будет обнаружен при сканировании. После добавления IP-адреса пользователя в список ACL задержки исчезнут (*пока не истечёт время нахождения адреса в списке*). Перед использованием проверьте, сколько запросов обычно отправляет клиент прежде, чем выдаст ошибку (**некоторые клиенты делают всего 1 запрос**). **Могут быть несовместимости с уже существующими правилами iptables на docker контейнере.**

Проверить, что порт сервиса не виден при сканировании можно через [nmap](https://nmap.org/):

`nmap -vv -sS IP-адрес -p номер_порта`

## Ответы на частые вопросы
### Почему решение снижает обнаружение, а не исключает его?
Злонамеренный сотрудник может где-то рассказать о такой защите. Если атакующему [удалось получить доступ к роутеру](https://habr.com/ru/articles/855536/#3), через который идёт трафик - он `теоретически` может заметить аномалию в виде нескольких SYN пакетов перед тем, как пойдёт полноценный трафик на сервис.
