<img width="1280" height="640" alt="Без имени" src="https://github.com/user-attachments/assets/524e9405-44e4-40ac-89e2-dde3d6d9f110" />

## English

You need an AdGuard VPN account and an internet connection.

## Install

1. Download `install-adguard-vpn-desktop.sh` and `adguard-vpn-desktop-1.1.0.zip` from Releases to your **Downloads** folder.
2. Open **Konsole** (terminal) and run:
   ```
   bash ~/Downloads/install-adguard-vpn-desktop.sh
   ```
3. Choose your system (Bazzite, SteamOS or other), enter your password (it stays invisible while you type), and answer **y** to every question.
4. Open **AdGuard VPN** from the desktop shortcut or the app menu. Log in with the QR code or the link in the window.

That's it. Click a country to connect, or «⛔ Отключить» to disconnect. The tray icon shows the VPN state, and the app keeps running in the tray when you close the window.

## If something is wrong

- The app warns you if setup isn't finished or you aren't logged in. Details are in «📜 Журнал» at the bottom of the window.
- Running the installer again (step 2) fixes almost everything.
- On SteamOS the `deck` user may have no password. Set one with `passwd`.
- To remove everything: `bash ~/Downloads/install-adguard-vpn-desktop.sh --uninstall`

There is also a separate plugin for Gaming Mode. The two work together: they share favourites and the manual "disconnected" state, and they don't get in each other's way.

> The app interface is in Russian.


## Русский

Нужно: аккаунт AdGuard VPN и интернет.

## Установка

1. Скачайте `install-adguard-vpn-desktop.sh` и `adguard-vpn-desktop-1.1.0.zip` из Releases в папку **Загрузки**.
2. Откройте **Konsole** (терминал) и выполните:
   ```
   bash ~/Downloads/install-adguard-vpn-desktop.sh
   ```
   Если папка называется по-русски, введите `~/Загрузки/` вместо `~/Downloads/`.
3. Выберите систему (Bazzite, SteamOS или другая), введите пароль (символы не видны, так и должно быть) и на все вопросы отвечайте **y**.
4. Откройте **AdGuard VPN** ярлыком на рабочем столе или в меню приложений. Войдите в аккаунт по QR-коду или ссылке в окне.

Готово. Нажмите на страну, чтобы подключиться, или на «⛔ Отключить», чтобы отключиться. Значок в трее показывает состояние VPN, а закрытое окно продолжает работать в трее.

## Если что-то не так

- Приложение само покажет, если установка не завершена или вы не вошли в аккаунт. Подробности смотрите в «📜 Журнал» внизу окна.
- Почти всё лечится повторным запуском установщика (шаг 2).
- На SteamOS у пользователя `deck` может не быть пароля. Задайте его командой `passwd`.
- Удалить всё: `bash ~/Downloads/install-adguard-vpn-desktop.sh --uninstall`

Есть также отдельный плагин для игрового режима. С ним приложение работает вместе: общие избранные, общее «отключено вручную», и они не мешают друг другу.

---
<sub>by MaxFoley · сделано с помощью Grok Bot</sub>
