#!/usr/bin/env bash
# =============================================================================
#  AdGuard VPN для рабочего стола — установка одной командой
#  Bazzite, SteamOS (режим рабочего стола) и другой Linux (x86_64).
#
#  Запуск (от обычного пользователя, БЕЗ sudo):
#      bash ~/Downloads/install-adguard-vpn-desktop.sh [путь/к/adguard-vpn-desktop-X.Y.Z.zip] [флаги]
#
#  Флаги:
#      --system=bazzite|steamos|other   не показывать меню выбора системы
#      --sudoers / --no-sudoers         правило sudo без пароля: создать без вопроса / не создавать
#      --autostart / --no-autostart     запуск вместе с рабочим столом: да / нет (без вопроса)
#      --yes                            на все вопросы — ответ по умолчанию
#      --uninstall                      удалить приложение (AdGuard VPN CLI и правило sudo — по вопросу)
#      --dry-run                        только показать, что будет сделано
#      -h, --help                       эта справка
#
#  Журнал: ~/adguard-vpn-desktop-install.log. Можно запускать повторно — готовые шаги пропускаются.
# =============================================================================
set -euo pipefail

APP_VERSION="1.1.0"
APP_ZIP_URL="${APP_ZIP_URL:-}"      # можно задать прямую ссылку на ZIP приложения
ADGUARD_INSTALLER_URL="https://raw.githubusercontent.com/AdguardTeam/AdGuardVPNCLI/HEAD/scripts/release/install.sh"
ADGUARD_RELEASES="https://github.com/AdguardTeam/AdGuardVPNCLI/releases"
GET_PIP_URL="https://bootstrap.pypa.io/get-pip.py"
QT_PIP_PACKAGE="${QT_PIP_PACKAGE:-PySide6-Essentials}"

# Переопределения только для тестов
ETC="${AGV_ETC:-/etc}"
OS_RELEASE="${AGV_OS_RELEASE:-/etc/os-release}"
OPT_CLI="${AGV_OPT_CLI:-/opt/adguardvpn_cli/adguardvpn-cli}"

BASE="$HOME/.local/share/adguard-vpn-desktop"
BIN_DIR="$HOME/.local/bin"
LAUNCHER="$BIN_DIR/adguard-vpn-desktop"
DESKTOP_FILE="$HOME/.local/share/applications/adguard-vpn-desktop.desktop"
ICONS="$HOME/.local/share/icons/hicolor"
AUTOSTART_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/adguard-vpn-desktop.desktop"
LOG="$HOME/adguard-vpn-desktop-install.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SYSTEM=""; DO_SUDOERS="ask"; DO_AUTOSTART="ask"; YES=0; UNINSTALL=0; DRY=0; ZIP_ARG=""
for a in "$@"; do
  case "$a" in
    --system=*)     SYSTEM="${a#--system=}" ;;
    --sudoers)      DO_SUDOERS=1 ;;
    --no-sudoers)   DO_SUDOERS=0 ;;
    --autostart)    DO_AUTOSTART=1 ;;
    --no-autostart) DO_AUTOSTART=0 ;;
    --yes|-y)       YES=1 ;;
    --uninstall)    UNINSTALL=1 ;;
    --dry-run)      DRY=1 ;;
    -h|--help)      sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)             echo "Неизвестный флаг: $a (см. --help)" >&2; exit 2 ;;
    *)              ZIP_ARG="$a" ;;
  esac
done
case "$SYSTEM" in ""|bazzite|steamos|other) ;; *) echo "--system: нужно bazzite, steamos или other" >&2; exit 2 ;; esac

# ---------- оформление ----------
if [ -t 1 ]; then B=$'\e[1m'; R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; N=$'\e[0m'
else B=""; R=""; G=""; Y=""; C=""; N=""; fi
STEP=0; STEP_NAME=""
step() { STEP=$((STEP + 1)); STEP_NAME="$1"; printf '\n%s%s[%d] %s%s\n' "$B" "$C" "$STEP" "$1" "$N"; }
ok()   { printf '  %s✔ %s%s\n' "$G" "$*" "$N"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '  %s⚠ %s%s\n' "$Y" "$*" "$N"; }
die()  { printf '\n%s✖ Ошибка на шаге «%s»: %s%s\n' "$R" "$STEP_NAME" "$*" "$N" >&2
         printf '  Подробности: %s\n' "$LOG" >&2; exit 1; }
run()  { if [ "$DRY" = 1 ]; then printf '  %s[dry-run]%s %s\n' "$Y" "$N" "$*"; else "$@"; fi; }
ask() {   # ask "вопрос" y|n
  local q="$1" def="$2" hint ans=""
  if [ "$def" = y ]; then hint="[Y/n]"; else hint="[y/N]"; fi
  if [ "$YES" = 1 ]; then printf '  %s %s %s\n' "$q" "$hint" "$def"; ans="$def"
  else printf '  %s %s ' "$q" "$hint"; read -r ans || ans=""; ans="${ans:-$def}"; fi
  case "$ans" in [yYдД]*) return 0 ;; *) return 1 ;; esac
}
CURL_SMALL=(-fsSL --connect-timeout 15 --max-time 300 --retry 3 --retry-delay 5 --retry-connrefused)
CURL_BIG=(-fSL --connect-timeout 15 --max-time 900 --retry 3 --retry-delay 5 --retry-connrefused)
reachable() {
  local code i
  for i in 1 2 3; do
    code="$(curl -sS -o /dev/null -I -w '%{http_code}' --connect-timeout 10 --max-time 30 "$1" 2>/dev/null || true)"
    if [ -n "$code" ] && [ "$code" != 000 ]; then return 0; fi
    [ "$i" = 3 ] || sleep 2
  done
  return 1
}
unset SUDO_ASKPASS      # пароль sudo — в этом терминале, а не окном

touch "$LOG" 2>/dev/null || LOG="/tmp/adguard-vpn-desktop-install-$USER.log"
exec > >(tee -a "$LOG") 2>&1
printf '\n===== %s  %s %s =====\n' "$(date '+%F %T')" "$0" "$*" >>"$LOG"
TMP="$(mktemp -d)"
KEEPALIVE=""
cleanup() {
  if [ -n "$KEEPALIVE" ]; then pkill -P "$KEEPALIVE" 2>/dev/null || true; kill "$KEEPALIVE" 2>/dev/null || true; fi
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'die "прервано"' INT TERM
tty_run() { if { : >/dev/tty; } 2>/dev/null; then "$@" </dev/tty >/dev/tty 2>&1; else "$@"; fi; }
find_cli() {
  if command -v adguardvpn-cli >/dev/null 2>&1; then command -v adguardvpn-cli
  elif [ -x "$OPT_CLI" ]; then echo "$OPT_CLI"
  elif [ -x "$HOME/.local/bin/adguardvpn-cli" ]; then echo "$HOME/.local/bin/adguardvpn-cli"
  else return 1; fi
}
cli_q() { timeout 150 "$CLI" "$@" </dev/null 2>&1; }
sudoers_name() { if [ "$SYSTEM" = steamos ]; then echo "zz-adguardvpn"; else echo "90-adguardvpn"; fi; }
sudoers_present() { local f; for f in "$ETC/sudoers.d/90-adguardvpn" "$ETC/sudoers.d/zz-adguardvpn"; do
  if [ -e "$f" ] || sudo -n test -e "$f" 2>/dev/null; then echo "$f"; return 0; fi; done; return 1; }
plugin_installed() {   # плагин AdGuard VPN для игрового режима (тогда общие CLI и правило sudo не трогаем)
  local d
  for d in "$HOME"/homebrew/plugins/*/; do
    [ -f "${d}plugin.json" ] || continue
    grep -qE '"name"[[:space:]]*:[[:space:]]*"(AdGuard VPN|adguard-vpn)"' "${d}plugin.json" && return 0
  done
  return 1
}
has_qt() { "$1" -c 'import importlib.util as u, sys
sys.exit(0 if any(u.find_spec(m) for m in ("PySide6", "PyQt6", "PyQt5")) else 1)' 2>/dev/null; }
qt_works() { QT_QPA_PLATFORM=offscreen "$1" -c 'import sys; sys.path.insert(0, sys.argv[1])
from adguard_vpn_desktop.qt_compat import API, QtWidgets
app = QtWidgets.QApplication([]); print(API)' "$2" 2>&1; }
SUDO_READY=0
need_sudo() {
  [ "$SUDO_READY" = 1 ] && return 0
  if [ "$SYSTEM" = steamos ]; then
    local st; st="$(passwd -S "$USER" 2>/dev/null | awk '{print $2}' || true)"
    if [ "$st" = NP ] || [ "$st" = L ]; then
      warn "у пользователя $USER нет пароля — на SteamOS так по умолчанию."
      info "Придумайте пароль (его попросят дважды; символы не видны — это нормально)."
      if [ "$DRY" = 1 ]; then run passwd; else tty_run passwd || die "пароль не задан (passwd)"; fi
    fi
  fi
  info "Введите пароль вашего пользователя (символы не видны — это нормально)."
  if [ "$DRY" = 1 ]; then run sudo -v
  else
    sudo -v || die "неверный пароль или sudo недоступен"
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 30; done ) >/dev/null 2>&1 </dev/null &
    KEEPALIVE=$!
  fi
  SUDO_READY=1
}
fetch_adguard_installer() {
  if curl "${CURL_SMALL[@]}" "$ADGUARD_INSTALLER_URL" -o "$1" 2>/dev/null; then info "установщик AdGuard скачан"
  elif curl "${CURL_SMALL[@]}" "$ADGUARD_RELEASES/latest/download/install.sh" -o "$1"; then
    warn "raw.githubusercontent.com недоступен — установщик взят со страницы релизов GitHub"
  else return 1; fi
  head -n1 "$1" | grep -q '^#!' || return 1
}

printf '%s%sAdGuard VPN для рабочего стола %s — установка%s\n' "$B" "$G" "$APP_VERSION" "$N"
[ "$DRY" = 1 ] && warn "РЕЖИМ ПРОВЕРКИ (--dry-run): ничего не меняется"

# ---------- 1. система ----------
step "Проверка системы"
[ "$(id -u)" -ne 0 ] || die "не запускайте через sudo и не от root. Просто: bash $0"
[ "$(uname -m)" = x86_64 ] || die "нужен процессор x86_64, а у вас $(uname -m)"
OS_ID=""; OS_NAME="неизвестно"
if [ -r "$OS_RELEASE" ]; then
  # shellcheck source=/dev/null
  OS_ID="$(. "$OS_RELEASE"; echo "${ID:-}")"
  # shellcheck source=/dev/null
  OS_NAME="$(. "$OS_RELEASE"; echo "${PRETTY_NAME:-${NAME:-?}}")"
fi
case "$OS_ID" in bazzite) DEF=1 ;; steamos) DEF=2 ;; *) DEF=3 ;; esac
info "Обнаружено: $OS_NAME"
if [ -z "$SYSTEM" ]; then
  printf '\n  Выберите систему:\n    1) Bazzite\n    2) SteamOS (Steam Deck)\n    3) Другой Linux\n'
  if [ "$YES" = 1 ]; then choice="$DEF"; printf '  Номер: %s\n' "$DEF"
  else printf '  Номер [%s, Enter — согласиться]: ' "$DEF"; read -r choice || choice=""; fi
  case "${choice:-$DEF}" in 1) SYSTEM=bazzite ;; 2) SYSTEM=steamos ;; 3) SYSTEM=other ;; *) die "нужно ввести 1, 2 или 3" ;; esac
fi
ok "Система: $SYSTEM"
for t in curl python3 tar sha256sum; do command -v "$t" >/dev/null 2>&1 || die "нет программы «$t»"; done
ok "Пользователь: $USER, домашняя папка: $HOME"

# =============================================================================
#  УДАЛЕНИЕ
# =============================================================================
if [ "$UNINSTALL" = 1 ]; then
  step "Удаление приложения"
  [ -x "$LAUNCHER" ] && { run "$LAUNCHER" --quit >/dev/null 2>&1 || true; }
  [ -f "$BASE/desktop-shortcut.path" ] && rm -f "$(cat "$BASE/desktop-shortcut.path")" 2>/dev/null
  for f in "$LAUNCHER" "$DESKTOP_FILE" "$AUTOSTART_FILE" "$ICONS/scalable/apps/adguard-vpn-desktop.svg"; do
    [ -e "$f" ] && { run rm -f "$f"; ok "удалено: $f"; }
  done
  for s in 16 22 24 32 48 64 128 256; do run rm -f "$ICONS/${s}x${s}/apps/adguard-vpn-desktop.png"; done
  [ -d "$BASE" ] && { run rm -rf "$BASE"; ok "удалено: $BASE"; }
  CFG="${XDG_CONFIG_HOME:-$HOME/.config}/adguard-vpn-desktop"; STATE="${XDG_STATE_HOME:-$HOME/.local/state}/adguard-vpn-desktop"
  if [ -d "$CFG" ] || [ -d "$STATE" ]; then
    if ask "Удалить и настройки/журнал приложения ($CFG, $STATE)?" y; then run rm -rf "$CFG" "$STATE"; ok "настройки удалены"; fi
  fi
  if plugin_installed; then
    info "Плагин AdGuard VPN для игрового режима установлен — AdGuard VPN CLI и правило sudo оставляю (они общие)."
  else
    if SF="$(sudoers_present)"; then
      if ask "Удалить правило sudo без пароля ($SF)?" y; then
        need_sudo; run sudo rm -f "$SF" "$ETC/atomic-update.conf.d/adguard-vpn.conf"; ok "правило удалено"
      fi
    fi
    if CLI="$(find_cli)" && ask "Удалить и саму программу AdGuard VPN CLI ($CLI)?" n; then
      need_sudo
      run "$CLI" disconnect >/dev/null 2>&1 || true
      fetch_adguard_installer "$TMP/install.sh" || die "не удалось скачать установщик AdGuard для удаления"
      ( cd "$TMP" && run sh "$TMP/install.sh" -v -u -a y ) || die "install.sh -u завершился с ошибкой"
      ok "AdGuard VPN CLI удалён"
    fi
  fi
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$HOME/.local/share/applications" 2>/dev/null || true
  printf '\n%s%sГотово: приложение удалено.%s\n' "$B" "$G" "$N"
  exit 0
fi

# ---------- 2. файлы приложения ----------
step "Файлы приложения"
SRC=""
if [ -d "$SCRIPT_DIR/adguard_vpn_desktop" ]; then SRC="$SCRIPT_DIR"
else
  ZIP="$ZIP_ARG"
  if [ -z "$ZIP" ]; then
    ZIP="$(ls -t "$SCRIPT_DIR"/adguard-vpn-desktop-*.zip "$HOME"/Downloads/adguard-vpn-desktop-*.zip \
           "$HOME"/Загрузки/adguard-vpn-desktop-*.zip 2>/dev/null | head -n1 || true)"
  fi
  if [ -z "$ZIP" ] && [ -n "$APP_ZIP_URL" ]; then
    info "Скачиваю приложение: $APP_ZIP_URL"
    curl "${CURL_BIG[@]}" "$APP_ZIP_URL" -o "$TMP/app.zip" || die "не удалось скачать ZIP приложения"
    ZIP="$TMP/app.zip"
  fi
  [ -n "$ZIP" ] && [ -f "$ZIP" ] || die "не найден ZIP приложения (adguard-vpn-desktop-$APP_VERSION.zip). Положите его в «Загрузки» рядом со скриптом."
  python3 - "$ZIP" "$TMP/unz" <<'PY' || die "не удалось распаковать ZIP"
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PY
  SRC="$(dirname "$(find "$TMP/unz" -type d -name adguard_vpn_desktop | head -n1)")"
  [ -d "$SRC/adguard_vpn_desktop" ] || die "в ZIP нет папки adguard_vpn_desktop — это точно ZIP приложения?"
  info "из архива: $ZIP"
fi
ok "Источник: $SRC"

# ---------- 3. AdGuard VPN CLI ----------
step "AdGuard VPN CLI"
if CLI="$(find_cli)"; then
  ok "уже установлен: $(cli_q --version | head -n1) ($CLI) — пропускаю"
else
  info "Проверяю интернет (github.com)… на медленной сети до 1–2 минут"
  reachable https://github.com || reachable https://raw.githubusercontent.com || \
    { warn "github.com не отвечает."; ask "Продолжить всё равно (скачивание ждёт дольше и повторяется)?" y || die "отменено"; }
  need_sudo
  cd "$TMP"
  fetch_adguard_installer "$TMP/install.sh" || die "не удалось скачать официальный установщик AdGuard"
  info "Устанавливаю (ответы на вопросы установщика — автоматически «y»)…"
  if ! run sh "$TMP/install.sh" -v -a y; then
    warn "официальный установщик не смог скачать программу — пробую архив со страницы релизов"
    TAG="$(curl "${CURL_SMALL[@]}" -I -o /dev/null -w '%{url_effective}' "$ADGUARD_RELEASES/latest" | sed 's#.*/tag/##' || true)"
    case "$TAG" in v[0-9]*) ;; *) die "не удалось узнать последнюю версию на GitHub" ;; esac
    PKG="adguardvpn-cli-${TAG#v}-linux-x86_64.tar.gz"
    curl "${CURL_BIG[@]}" "$ADGUARD_RELEASES/download/$TAG/$PKG" -o "$TMP/$PKG" || die "не удалось скачать $PKG"
    WANT="$(curl "${CURL_SMALL[@]}" "https://api.github.com/repos/AdguardTeam/AdGuardVPNCLI/releases/tags/$TAG" 2>/dev/null \
      | python3 -c 'import json,sys
d=json.load(sys.stdin); n=sys.argv[1]
print(next((a.get("digest","") for a in d.get("assets",[]) if a["name"]==n),"").replace("sha256:",""))' "$PKG" 2>/dev/null || true)"
    HAVE="$(sha256sum "$TMP/$PKG" | cut -d' ' -f1)"
    if [ -n "$WANT" ]; then [ "$WANT" = "$HAVE" ] || die "контрольная сумма архива не совпала с GitHub"; ok "SHA256 совпадает с GitHub"
    else warn "не удалось получить SHA256 с GitHub; SHA256 архива: $HAVE"; fi
    run sh "$TMP/install.sh" -v -a y -p "$TMP/$PKG" || die "установка из архива не удалась"
  fi
  cd "$HOME"; hash -r
  if [ "$DRY" = 1 ]; then CLI="adguardvpn-cli"
  else CLI="$(find_cli)" || die "после установки команда adguardvpn-cli не найдена"; ok "установлен: $(cli_q --version | head -n1)"; fi
fi
if [ "$DRY" = 0 ]; then
  info "Настраиваю adguardvpn-cli (первый запуск; на медленной сети до минуты)…"
  cli_q config set-crash-reporting off >/dev/null && info "отправка отчётов о сбоях выключена" || warn "config set-crash-reporting off не выполнен (не страшно)"
fi

# ---------- 4. права администратора ----------
step "Права администратора для включения VPN"
if SF="$(sudoers_present)"; then
  ok "правило sudo без пароля уже есть ($SF) — пропускаю"
elif [ "$DRY" = 0 ] && sudo -n -l 2>/dev/null | grep -q 'NOPASSWD: ALL'; then
  ok "sudo уже работает без пароля — правило не нужно"
else
  if [ "$DO_SUDOERS" = ask ]; then
    info "AdGuard VPN нужны права администратора при каждом подключении."
    info "Без правила приложение будет спрашивать пароль окном. С правилом — не спрашивает."
    if ask "Создать правило «sudo без пароля»?" y; then DO_SUDOERS=1; else DO_SUDOERS=0; fi
  fi
  if [ "$DO_SUDOERS" = 1 ]; then
    need_sudo
    SF="$ETC/sudoers.d/$(sudoers_name)"
    RULE="$USER ALL=(ALL) NOPASSWD: ALL"
    printf '%s\n' "# AdGuard VPN: adguardvpn-cli вызывает sudo сам (приложение и плагин для игрового режима)" "$RULE" >"$TMP/rule"
    command -v visudo >/dev/null 2>&1 || [ "$DRY" = 1 ] || die "нет visudo"
    # проверяем ТОЛЬКО наш файл: чужие системные файлы sudoers (например, с кривыми правами) нас не касаются
    if [ "$DRY" = 0 ]; then sudo visudo -cf "$TMP/rule" >/dev/null || die "проверка правила (visudo -cf) не прошла — ничего не изменено"; fi
    run sudo install -m 0440 -o root -g root "$TMP/rule" "$SF"
    if [ "$DRY" = 0 ]; then sudo visudo -cf "$SF" >/dev/null || { sudo rm -f "$SF"; die "visudo нашёл ошибку в нашем правиле — правило удалено"; }; fi
    ok "создано: $SF"
    if [ "$SYSTEM" = steamos ]; then
      KEEP="$ETC/atomic-update.conf.d/adguard-vpn.conf"
      if ! sudo test -f "$KEEP"; then
        run sudo mkdir -p "$ETC/atomic-update.conf.d"
        printf '%s\n' "$SF" >"$TMP/keep"
        run sudo install -m 0644 "$TMP/keep" "$KEEP"
        ok "SteamOS: правило сохранится после обновления системы"
      fi
    fi
    warn "Теперь программы от имени $USER могут выполнять команды администратора без пароля. Убрать: bash $0 --uninstall"
  else
    info "Правило не создаю — пароль будет спрашиваться окном при подключении."
  fi
fi

# ---------- 5. Qt для Python ----------
step "Библиотека окна (Qt для Python)"
PY=""
SYS_PY="$(command -v python3)"
if has_qt "$SYS_PY" && QTAPI="$(qt_works "$SYS_PY" "$SRC")"; then
  PY="$SYS_PY"; ok "уже есть в системе: $(echo "$QTAPI" | tail -n1) — ничего не скачиваю"
elif [ -x "$BASE/venv/bin/python3" ] && QTAPI="$(qt_works "$BASE/venv/bin/python3" "$SRC")"; then
  PY="$BASE/venv/bin/python3"; ok "уже установлено ранее: $(echo "$QTAPI" | tail -n1) ($BASE/venv)"
else
  info "В системе нет Qt для Python. Ставлю $QT_PIP_PACKAGE в отдельную папку $BASE/venv"
  info "(систему не трогает — работает и на Bazzite/SteamOS, где система только для чтения; ~100 МБ)."
  if [ "$DRY" = 1 ]; then run python3 -m venv "$BASE/venv"; run "$BASE/venv/bin/python3" -m pip install "$QT_PIP_PACKAGE"
  else
    mkdir -p "$BASE"
    rm -rf "$BASE/venv"
    if ! python3 -m venv "$BASE/venv" >/dev/null 2>&1; then
      warn "python3 -m venv без pip — ставлю pip отдельно (get-pip.py)"
      rm -rf "$BASE/venv"
      python3 -m venv --without-pip "$BASE/venv" || die "не удалось создать окружение Python (python3 -m venv)"
      curl "${CURL_SMALL[@]}" "$GET_PIP_URL" -o "$TMP/get-pip.py" || die "не удалось скачать get-pip.py"
      "$BASE/venv/bin/python3" "$TMP/get-pip.py" -q || die "не удалось установить pip"
    fi
    "$BASE/venv/bin/python3" -m pip --version >/dev/null 2>&1 || {
      curl "${CURL_SMALL[@]}" "$GET_PIP_URL" -o "$TMP/get-pip.py" || die "не удалось скачать get-pip.py"
      "$BASE/venv/bin/python3" "$TMP/get-pip.py" -q || die "не удалось установить pip"; }
    info "Скачиваю $QT_PIP_PACKAGE… на медленной сети это несколько минут"
    "$BASE/venv/bin/python3" -m pip install --disable-pip-version-check --timeout 120 --retries 5 "$QT_PIP_PACKAGE" \
      || die "pip не смог установить $QT_PIP_PACKAGE (проверьте интернет и запустите скрипт снова)"
    QTAPI="$(qt_works "$BASE/venv/bin/python3" "$SRC")" || die "Qt установлен, но не запускается: $QTAPI"
    PY="$BASE/venv/bin/python3"
    ok "установлено: $(echo "$QTAPI" | tail -n1)"
  fi
fi

# ---------- 6. приложение ----------
step "Установка приложения"
if [ "$DRY" = 1 ]; then
  run cp -r "$SRC/adguard_vpn_desktop" "$BASE/app/"; run install "$SRC/adguard-vpn-desktop" "$LAUNCHER"
else
  [ -x "$LAUNCHER" ] && "$LAUNCHER" --quit >/dev/null 2>&1 || true      # старая копия, если запущена
  mkdir -p "$BASE" "$BIN_DIR" "$(dirname "$DESKTOP_FILE")" "$ICONS/scalable/apps"
  rm -rf "$BASE/app.new"; mkdir -p "$BASE/app.new"
  cp -r "$SRC/adguard_vpn_desktop" "$BASE/app.new/"
  find "$BASE/app.new" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
  rm -rf "$BASE/app"; mv "$BASE/app.new" "$BASE/app"
  printf '%s\n' "$PY" >"$BASE/python"
  install -m 0755 "$SRC/adguard-vpn-desktop" "$LAUNCHER"
  install -m 0644 "$SRC/adguard_vpn_desktop/data/icons/adguard-vpn-desktop.svg" "$ICONS/scalable/apps/adguard-vpn-desktop.svg"
  for s in 16 22 24 32 48 64 128 256; do
    mkdir -p "$ICONS/${s}x${s}/apps"
    install -m 0644 "$SRC/adguard_vpn_desktop/data/icons/adguard-vpn-desktop-$s.png" "$ICONS/${s}x${s}/apps/adguard-vpn-desktop.png"
  done
  sed "s#^Exec=.*#Exec=$LAUNCHER#" "$SRC/adguard-vpn-desktop.desktop" >"$DESKTOP_FILE"
  chmod 0644 "$DESKTOP_FILE"
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$(dirname "$DESKTOP_FILE")" 2>/dev/null || true
  # ярлык на рабочем столе
  DESK_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
  [ -n "$DESK_DIR" ] && [ "$DESK_DIR" != "$HOME" ] || DESK_DIR="$HOME/Desktop"
  [ -d "$DESK_DIR" ] || { [ -d "$HOME/Рабочий стол" ] && DESK_DIR="$HOME/Рабочий стол"; }
  mkdir -p "$DESK_DIR"
  DESK_LINK="$DESK_DIR/adguard-vpn-desktop.desktop"
  cp "$DESKTOP_FILE" "$DESK_LINK" && chmod 0755 "$DESK_LINK"
  command -v gio >/dev/null 2>&1 && gio set "$DESK_LINK" metadata::trusted true 2>/dev/null || true
  echo "$DESK_LINK" >"$BASE/desktop-shortcut.path" 2>/dev/null || true
  ok "ярлык на рабочем столе: $DESK_LINK"
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$ICONS" 2>/dev/null || true
  for k in kbuildsycoca6 kbuildsycoca5; do command -v "$k" >/dev/null 2>&1 && { "$k" >/dev/null 2>&1 || true; break; }; done
  VER="$("$LAUNCHER" --version 2>&1)" || die "приложение не запускается: $VER"
  ok "$VER"
  ok "в меню: «AdGuard VPN» (Сеть / Интернет); команда: $LAUNCHER"
fi

# ---------- 7. автозапуск ----------
step "Запуск вместе с рабочим столом"
if [ "$DO_AUTOSTART" = ask ]; then
  if ask "Запускать AdGuard VPN при входе в рабочий стол (свёрнуто в трей)?" y; then DO_AUTOSTART=1; else DO_AUTOSTART=0; fi
fi
if [ "$DO_AUTOSTART" = 1 ]; then
  if [ "$DRY" = 0 ]; then
    mkdir -p "$(dirname "$AUTOSTART_FILE")"
    printf '%s\n' "[Desktop Entry]" "Type=Application" "Name=AdGuard VPN" \
      "Comment=AdGuard VPN — запуск вместе с рабочим столом (свёрнуто в трей)" "Exec=$LAUNCHER --minimized" \
      "Icon=adguard-vpn-desktop" "Terminal=false" "X-GNOME-Autostart-enabled=true" "X-KDE-autostart-after=panel" >"$AUTOSTART_FILE"
  fi
  ok "включено ($AUTOSTART_FILE). Выключить можно в приложении: «Настройки»."
else
  [ -f "$AUTOSTART_FILE" ] && run rm -f "$AUTOSTART_FILE"
  info "выключено"
fi

# ---------- 8. вход и проверка ----------
step "Аккаунт AdGuard"
if [ "$DRY" = 0 ]; then
  LIC="$(cli_q license || true)"
  if printf '%s' "$LIC" | grep -qiE 'not logged in|please log in|log in first|login required'; then
    info "Вход ещё не выполнен — войдите в приложении: «🔑 Войти в AdGuard» (QR-код или ссылка)."
  elif printf '%s' "$LIC" | grep -qi 'logged in as'; then
    ok "$(printf '%s' "$LIC" | grep -i 'logged in as' | head -n1)"
  else
    warn "AdGuard не ответил (медленная сеть?) — проверьте вход в приложении"
  fi
  mkdir -p "$BASE"
  printf 'version=%s\ndate=%s\nsystem=%s\nuser=%s\npython=%s\n' "$APP_VERSION" "$(date '+%F %T')" "$SYSTEM" "$USER" "$PY" >"$BASE/install-complete"
fi

printf '\n%s%sГотово!%s AdGuard VPN %s установлен.\n' "$B" "$G" "$N" "$APP_VERSION"
info "Запуск: меню приложений → «AdGuard VPN» (или команда adguard-vpn-desktop)."
info "Удалить: bash $0 --uninstall"
if [ "$DRY" = 0 ] && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
  if ask "Открыть приложение сейчас?" y; then
    ( setsid "$LAUNCHER" >/dev/null 2>&1 < /dev/null & ) ; ok "запущено"
  fi
fi
