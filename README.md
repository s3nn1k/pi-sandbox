# pi-sandbox

Контейнерное окружение кодинг-агента pi: одна VM colima, dind-сайдкар, docker-UX агента
как на хосте (bind-маунты, localhost-порты стеков, тёплые кэши) при сохранении границы
«хост исполняет только свой код».

## Топология

```
VM1 (vz/virtiofs, mounts: projects, .pi/agent/{sessions,missions}, tmp,
     vaults/work/{researches,incidents}, go/pkg/mod ro, whisper ro)
+-- pi-agent        image: pi-agent-base; netns dind (network_mode service:dind)
|                   DOCKER_HOST=unix:///var/run/dind/docker.sock
+-- dind            docker:29-dind (digest), privileged, restart: unless-stopped,
|                   healthcheck docker info, /var/lib/docker -> volume dind-data,
|                   dockerd --group=<AGENT_GID>; same-path binds projects+researches+incidents;
|                   ports 8600-8799
+-- herdr-bridge    socat unix -> TCP 192.168.5.2:4761 (мак-мост, whitelist)
```

Запуск: `pi` из проекта (тонкая функция в dotfiles/zshrc -> `bin/pi-run`). `pi --unsafe` -
хостовый pi. guard корней - `pi-mounts` (vm-only = только маунт VM; ro = только сиды).

## Ключевые решения

- **Копии вместо маунтов**: brain/dotfiles/gitconfig/nvim/токен/pi-рантайм - rsync-копии
  (tmp/pi-cache) при каждом запуске; poisoning отбрасывается синком. pi-рантайм - синк
  хостовой установки (@earendil-works/pi-coding-agent), в контейнере ro через
  `~/.pi/runtime`; read-only хелпер токена - `bin/git-cred-read`. Токен: ro-секрет
  /run/secrets -> entrypoint-копия в $HOME (fail-loud).
- **dind в netns + агент рядом** (`service:dind`): пути демона = пути агента
  (bind-инвариант), порты стеков = localhost агента. Не host-net: два dockerd в одном
  netns конфликтуют в iptables.
- **Nesting наследует firewall**: эгресс inner-контейнеров NAT-ится через netns dind и
  проходит внешний DOCKER-USER: к 192.168.5.2 (мак-loopback) открыт только :4761;
  ESTABLISHED-ответы всегда проходят; VM не инициирует NEW к .2 (provision в colima.yaml,
  fail-loud + самопроверка порядка).
- **Сокет dind** - volume outer-dind, группа = gid агента.
- **Порты мака**: диапазон 8600-8799 публикуется на VM1 -> lima форвардит на mac
  localhost. Конвенция: тест-порты стеков - из диапазона; мак-контейнерам диапазон
  запрещён.

## Установка

`./install.sh` (его вызывает dotfiles/scripts/bootstrap.sh после клона): pf-якорь -> colima VM ->
маунты+firewall (sandbox-sync, verify) -> image+seeds -> herdr-bridge LaunchAgent.
Идемпотентен.

## Security-инварианты

- S1 хост исполняет только свой код (копии; bind rw = рабочие данные:
  projects/sessions/missions/researches/incidents; кэши - named volumes с односторонними
  сидами).
- S2 mac-loopback закрыт для контейнеров (включая вложенные), кроме herdr :4761 (whitelist
  по методам на маке).
- S3 хостовые креды вне VM (.ssh/.kube/Library/vault/dotfiles/мозг).
- S4 blast radius agent-root (через dind) = VM-маунты = принятые rw-поверхности.

Хостовой git: gitlab-хосты используют `bin/git-cred-read` (read-only store, approve =
no-op) - vault-файл единственный источник правды, URL-креды не перезаписывают человеческие
токены.

## Residuals (принятые)

- breakout из privileged dind = root VM1, включая внешний демон -> публикация портов на
  mac-localhost через lima-автофорвард (pf закрывает только 2375);
- правила S2 - v4: IPv6 host-forwarding в lima/colima не включать;
- inotify не проходит virtiofs: watch-стеки - polling-флаги;
- GOSUMDB=off (VPN): новые go-зависимости без проверки sum-db;
- ротация агентского токена действует со следующего запуска pi.

## Runbook

- dind пересоздан при живых pi-sess -> "сессия осиротела" -> перезапуск pi (pi-run сверяет
  container:<id> перед reattach и не поднимает dind при живых сессиях);
- флап port-forward (colima#1376) -> `colima restart`;
- resize VM: только `colima stop && colima start --memory N` (volumes живы);
  `colima delete` запрещён вне миграции;
- диск dind: pi-run делает ежедневный `docker system prune` (until=48h) и гасит контейнеры
  внутри dind, работающие дольше 24ч; при сбое prune - WARN с кодом и хвостом ошибки
  (полный лог - `~/tmp/pi-cache/.dind-prune-last.log`);
- запуск из вне-корневых путей -> guard откажет; pi-mounts - источник корней;
- обновление pi на хосте (brew) подхватывается контейнером при следующем запуске (rsync
  pi-runtime); pi в образе нет, пересборка для обновления не нужна;
- порт из 8600-8799, занятый на маке другим приложением: форвард этого порта молча не
  работает (проверь `lsof -iTCP:<port>` при пропавшем mac-паритете).

## LaunchAgent

`launchagents/com.pi-sandbox.herdr-bridge.plist` - шаблон (`__HOME__` подставляет
dotfiles/scripts/bootstrap.sh); в репозитории невалиден намеренно.
