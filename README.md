# pi-sandbox-macos

Контейнерное окружение кодинг-агента pi на macOS: VM colima (vz/virtiofs), агент в netns
dind, граница "хост исполняет только свой код". Инварианты и residuals - в коде
(compose.yaml, bin/pi-run, install.sh) и истории коммитов.

## Установка

Вызывается dotfiles-mac/scripts/bootstrap.sh после клона, или руками:

```sh
./install.sh
```

Разворачивает pf-якорь, colima VM с маунтами и firewall (bin/sandbox-sync), образ и сиды,
LaunchAgent herdr-bridge. Идемпотентен.

## Использование

Из проекта (корни запуска - pi-mounts):

```sh
pi
```

- pi --unsafe - хостовый pi; конфиг-подкоманды (update/mcp/auth/...) - тоже хостовые.
- Порты тест-стеков: 8600-8799 (lima форвардит на mac-localhost).
- Проверка окружения: sandbox-sync; смена списка корней - sandbox-sync + colima restart.
- Живые сессии: docker ps --format '{{.Names}}' | grep pi-sess; при обрыве связи pi-run
  перецепляется сам; флап port-forward - colima restart.
