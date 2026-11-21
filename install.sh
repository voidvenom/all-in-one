#!/usr/bin/env bash
# all-in-one kurulum betiği
#
# Ne yapar?
#   - Depoyu yerel bir dizine klonlar (veya mevcut checkout'u kullanır)
#   - Bir Python sanal ortamı oluşturup paketi kurar
#   - `aio` komutunu ~/.local/bin'e bağlar
#   - Başlat menüsüne (uygulama başlatıcı) all-in-one kısayolunu ve logoyu ekler
#
# Hızlı kullanım:
#   curl -fsSL https://raw.githubusercontent.com/voidvenom/all-in-one/main/install.sh | bash
#
# Kaynaktan:
#   git clone https://github.com/voidvenom/all-in-one.git && cd all-in-one && ./install.sh
set -euo pipefail

REPO_URL="${AIO_REPO:-https://github.com/voidvenom/all-in-one.git}"
REF="${AIO_REF:-main}"
SRC_DIR="${AIO_SRC_DIR:-$HOME/.local/share/all-in-one}"
VENV_DIR="${AIO_VENV:-$SRC_DIR/.venv}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APPS_DIR="$DATA_HOME/applications"
ICON_DIR="$DATA_HOME/icons/hicolor/scalable/apps"
BIN_DIR="$HOME/.local/bin"
APP_NAME="all-in-one"

DESKTOP=1
DEPS=0
UNINSTALL=0
SOURCE_DIR=""

BLUE=$'\033[1;34m'; GREEN=$'\033[1;32m'; YEL=$'\033[1;33m'; RED=$'\033[1;31m'; DIM=$'\033[2m'; OFF=$'\033[0m'

info()  { printf '%s==>%s %s\n' "$BLUE" "$OFF" "$*"; }
ok()    { printf '%s✓%s %s\n' "$GREEN" "$OFF" "$*"; }
warn()  { printf '%s!%s %s\n' "$YEL" "$OFF" "$*"; }
die()   { printf '%sHata:%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
all-in-one kurulum betiği

Kullanım: install.sh [seçenekler]

Seçenekler:
  --dir <yol>        Kaynak dizini (varsayılan: $SRC_DIR)
  --repo <url>       Git deposu adresi (varsayılan: $REPO_URL)
  --ref <dal>        Klonlanacak dal/etiket (varsayılan: $REF)
  --deps             Eksik sistem paketlerini kurmayı dene (sudo gerekir)
  --no-desktop       Başlat menüsü kısayolunu ekleme
  --uninstall        Kısayolu, ikonu ve komut bağlantısını kaldır
  -h, --help         Bu yardımı göster

Ortam değişkenleri:
  AIO_REPO, AIO_REF, AIO_SRC_DIR, AIO_VENV
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)        SRC_DIR="$2"; shift 2 ;;
    --repo)       REPO_URL="$2"; shift 2 ;;
    --ref)        REF="$2"; shift 2 ;;
    --venv)       VENV_DIR="$2"; shift 2 ;;
    --deps)       DEPS=1; shift ;;
    --no-desktop) DESKTOP=0; shift ;;
    --uninstall)  UNINSTALL=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "bilinmeyen seçenek: $1 (--help)" ;;
  esac
done

# Bu betik bir checkout içindeyse onu kullan (klonlamaya gerek yok).
SCRIPT_PATH="${BASH_SOURCE[0]:-}"
if [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ]; then
  CANDIDATE="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
  if [ -f "$CANDIDATE/pyproject.toml" ] && grep -q 'name = "all-in-one"' "$CANDIDATE/pyproject.toml" 2>/dev/null; then
    SOURCE_DIR="$CANDIDATE"
  fi
fi

uninstall() {
  info "Kısayol, ikon ve komut bağlantısı kaldırılıyor"
  rm -f "$APPS_DIR/$APP_NAME.desktop"
  rm -f "$ICON_DIR/$APP_NAME.svg"
  rm -f "$BIN_DIR/aio"
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f -t "$DATA_HOME/icons/hicolor" 2>/dev/null || true
  ok "Kaldırıldı. Kaynak dizini ve sanal ortam korundu: $SRC_DIR"
  echo "  Tamamen silmek için: rm -rf \"$SRC_DIR\""
  exit 0
}

[ "$UNINSTALL" -eq 1 ] && uninstall

[ "$(uname -s)" = "Linux" ] || die "Bu betik yalnızca Linux içindir."

# Python 3.10+ kontrolü
PYTHON_BIN=""
for cand in python3 python; do
  if command -v "$cand" >/dev/null 2>&1; then
    if "$cand" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
      PYTHON_BIN="$(command -v "$cand")"; break
    fi
  fi
done
[ -n "$PYTHON_BIN" ] || die "Python 3.10+ bulunamadı. Kurun ve tekrar deneyin."
ok "Python: $("$PYTHON_BIN" --version 2>&1)"

# Kaynak: mevcut checkout ya da klon
if [ -z "$SOURCE_DIR" ]; then
  if [ -d "$SRC_DIR/.git" ]; then
    info "Mevcut kaynak güncelleniyor: $SRC_DIR"
    git -C "$SRC_DIR" fetch --depth 1 origin "$REF" >/dev/null 2>&1 || true
    git -C "$SRC_DIR" checkout -q FETCH_HEAD 2>/dev/null || git -C "$SRC_DIR" pull --ff-only || true
  else
    command -v git >/dev/null 2>&1 || die "git bulunamadı. Kurun ya da depoyu elle klonlayıp ./install.sh çalıştırın."
    info "Depo klonlanıyor: $REPO_URL ($REF)"
    mkdir -p "$(dirname "$SRC_DIR")"
    git clone --depth 1 --branch "$REF" "$REPO_URL" "$SRC_DIR"
  fi
  SOURCE_DIR="$SRC_DIR"
else
  info "Mevcut checkout kullanılıyor: $SOURCE_DIR"
fi

# Sanal ortam + kurulum
if [ ! -x "$VENV_DIR/bin/python" ]; then
  info "Sanal ortam oluşturuluyor: $VENV_DIR"
  "$PYTHON_BIN" -m venv "$VENV_DIR" || die "venv oluşturulamadı. Dağıtımınızda 'python3-venv' paketi gerekebilir."
fi
info "Paket kuruluyor (bağımlılıklar indirilebilir)"
"$VENV_DIR/bin/python" -m pip install --quiet --upgrade pip
"$VENV_DIR/bin/python" -m pip install --quiet -e "$SOURCE_DIR"
ok "Kuruldu: $("$VENV_DIR/bin/aio" --version 2>/dev/null || echo aio)"

# Sistem bağımlılıkları (opsiyonel)
missing=()
command -v secret-tool >/dev/null 2>&1 || missing+=("secret-tool (libsecret)")
command -v notify-send >/dev/null 2>&1 || missing+=("notify-send (libnotify)")
if [ "${#missing[@]}" -gt 0 ]; then
  warn "Eksik sistem araçları: ${missing[*]}"
  if [ "$DEPS" -eq 1 ]; then
    if command -v pacman >/dev/null 2>&1; then
      sudo pacman -S --needed --noconfirm libsecret libnotify
    elif command -v apt >/dev/null 2>&1; then
      sudo apt update && sudo apt install -y libsecret-tools libnotify-bin
    else
      warn "Paket yöneticisi tanınmadı; elle kurun."
    fi
  else
    info "Kurmak için: sudo pacman -S libsecret libnotify  (veya apt) · ya da: ./install.sh --deps"
  fi
fi

# `aio` komutunu PATH'e bağla
mkdir -p "$BIN_DIR"
ln -sf "$VENV_DIR/bin/aio" "$BIN_DIR/aio"
ok "Komut bağlandı: $BIN_DIR/aio"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR PATH'te değil. Kabuk profilinize ekleyin: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# Başlat menüsü kısayolu + logo
if [ "$DESKTOP" -eq 1 ]; then
  mkdir -p "$APPS_DIR" "$ICON_DIR"
  if [ -f "$SOURCE_DIR/assets/logo.svg" ]; then
    cp -f "$SOURCE_DIR/assets/logo.svg" "$ICON_DIR/$APP_NAME.svg"
  else
    warn "Logo bulunamadı: $SOURCE_DIR/assets/logo.svg (ikon atlandı)"
  fi
  if [ -f "$SOURCE_DIR/packaging/all-in-one.desktop" ]; then
    sed -e "s|@EXEC@|$VENV_DIR/bin/aio|g" \
        -e "s|@ICON@|$APP_NAME|g" \
        "$SOURCE_DIR/packaging/all-in-one.desktop" > "$APPS_DIR/$APP_NAME.desktop"
    chmod 0644 "$APPS_DIR/$APP_NAME.desktop"
  else
    warn ".desktop şablonu bulunamadı; kısayol atlandı"
  fi
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f -t "$DATA_HOME/icons/hicolor" 2>/dev/null || true
  ok "Başlat menüsüne eklendi: $APPS_DIR/$APP_NAME.desktop"
fi

echo
ok "all-in-one hazır."
echo "  Veri dizini : $HOME/.all-in-one"
echo "  Kaynak      : $SOURCE_DIR"
echo
echo "  Sonraki adımlar:"
echo "    aio doctor     # kurulum/kimlik kontrolü"
echo "    aio init       # mevcut Antigravity hesabını ana hesap yap"
echo "    aio ui         # web arayüzünü aç  (başlat menüsünden de açılabilir)"
echo
echo "  Kaldırmak için: $SOURCE_DIR/install.sh --uninstall"
