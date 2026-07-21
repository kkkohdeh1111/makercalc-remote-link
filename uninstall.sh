#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# MakerCalc Remote Link — desinstalador
# Deshace todo lo que hizo install.sh: restaura tu moonraker.conf desde el
# backup, para y borra el puente, y reinicia. Deja tu impresora como estaba.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

BRIDGE_DST="/usr/local/bin/mkc-bridge.py"
UNIT="/etc/systemd/system/mkc-bridge.service"

log() { printf '\033[1;36m[MakerCalc]\033[0m %s\n' "$*"; }

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

# 1 ── Restaurar moonraker.conf desde el backup ─────────────────────────────
CONF=""
for p in /home/*/printer_data/config/moonraker.conf \
         /home/*/klipper_config/moonraker.conf \
         /root/printer_data/config/moonraker.conf; do
  [ -f "$p" ] && CONF="$p" && break
done
[ -z "$CONF" ] && CONF="$(find /home /root -maxdepth 5 -name moonraker.conf 2>/dev/null | grep -vi backup | head -1 || true)"

if [ -n "$CONF" ] && [ -f "${CONF}.mkc-bak" ]; then
  log "Restaurando tu config original…"
  $SUDO cp "${CONF}.mkc-bak" "$CONF"
  $SUDO rm -f "${CONF}.mkc-bak"
else
  log "No hay backup .mkc-bak — dejo moonraker.conf sin tocar."
fi

# 2 ── Parar y borrar el puente ─────────────────────────────────────────────
log "Borrando el puente…"
$SUDO systemctl disable --now mkc-bridge >/dev/null 2>&1 || true
$SUDO rm -f "$UNIT" "$BRIDGE_DST"
$SUDO systemctl daemon-reload 2>/dev/null || true

# 3 ── NO reiniciamos Moonraker ─────────────────────────────────────────────
# Reiniciar Moonraker brickea la pantalla en placas MKS/Elegoo. El cambio se
# aplica con un reinicio normal de la impresora (screen-safe).
log "Listo. Reiniciá la impresora una vez para aplicar (screen-safe)."
log "Tu config quedó como antes del puente."
