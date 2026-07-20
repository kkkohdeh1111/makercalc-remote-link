#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# MakerCalc Remote Link — desinstalador
# Deshace todo lo que hizo install.sh: restaura tu moonraker.conf desde el
# backup, borra el puente stunnel y reinicia. Deja tu impresora como estaba.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

STUNNEL_CONF="/etc/stunnel/makercalc.conf"

log() { printf '\033[1;36m[MakerCalc]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[MakerCalc]\033[0m %s\n' "$*" >&2; }

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

# 2 ── Borrar el puente stunnel ─────────────────────────────────────────────
if [ -f "$STUNNEL_CONF" ]; then
  log "Borrando el puente TLS…"
  $SUDO rm -f "$STUNNEL_CONF"
  $SUDO systemctl restart stunnel4 2>/dev/null || true
fi

# 3 ── Reiniciar Moonraker ──────────────────────────────────────────────────
log "Reiniciando Moonraker…"
$SUDO systemctl restart moonraker 2>/dev/null || $SUDO systemctl restart moonraker.service 2>/dev/null || true

log "Listo. Tu impresora quedó como antes del puente."
