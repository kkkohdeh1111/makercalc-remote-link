#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# MakerCalc Remote Link — instalador del puente seguro
#
#   git clone https://github.com/kkkohdeh1111/makercalc-remote-link
#   cd makercalc-remote-link && ./install.sh
#
# Para impresoras con un Moonraker viejo que no habla TLS. Levanta un puente
# local en Python puro (mkc-bridge.py): Moonraker conecta en claro a
# 127.0.0.1 —dentro de la placa, nunca sale a la red— y el puente lo envuelve
# en TLS hacia el broker.
#
# NO instala paquetes. NO toca tu token (vive en moonraker.conf y viaja
# siempre sellado). NO abre puertos en tu router. NO toca Klipper. Deja backup
# y es reversible (./uninstall.sh). Idempotente: podés correrlo varias veces.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

LOCAL_PORT="1883"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE_DST="/usr/local/bin/mkc-bridge.py"
UNIT="/etc/systemd/system/mkc-bridge.service"

log() { printf '\033[1;36m[MakerCalc]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[MakerCalc]\033[0m %s\n' "$*" >&2; }

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || { err "Necesito root o sudo."; exit 1; }
  SUDO="sudo"
  log "Voy a pedir tu contraseña (sudo) para instalar el servicio del puente."
fi

# 1 ── Ubicar moonraker.conf ────────────────────────────────────────────────
log "Buscando la config de tu impresora…"
CONF=""
for p in /home/*/printer_data/config/moonraker.conf \
         /home/*/klipper_config/moonraker.conf \
         /root/printer_data/config/moonraker.conf; do
  [ -f "$p" ] && CONF="$p" && break
done
if [ -z "$CONF" ]; then
  CONF="$(find /home /root -maxdepth 5 -name moonraker.conf 2>/dev/null | grep -vi backup | head -1 || true)"
fi
[ -n "$CONF" ] || { err "No encontré moonraker.conf. ¿Está instalado Moonraker?"; exit 1; }
grep -q '^\[mqtt\]' "$CONF" || {
  err "Tu config no tiene el bloque [mqtt] de MakerCalc todavía."
  err "Pegalo primero desde la web (Conectar impresora) y volvé a correr esto."
  exit 1
}
log "Config encontrada: $CONF"

# 2 ── Detectar un python3 (sin instalar nada) ──────────────────────────────
PY=""
for p in /usr/bin/python3 /usr/local/bin/python3 /home/*/moonraker-env/bin/python; do
  [ -x "$p" ] && PY="$p" && break
done
[ -n "$PY" ] || { err "No encontré python3 en el sistema."; exit 1; }
log "Usando python: $PY"

# 3 ── Instalar el puente + servicio ────────────────────────────────────────
log "Instalando el puente (Python puro, sin paquetes)…"
$SUDO cp "$SCRIPT_DIR/mkc-bridge.py" "$BRIDGE_DST"
$SUDO chmod +x "$BRIDGE_DST"

$SUDO tee "$UNIT" >/dev/null <<EOF
[Unit]
Description=MakerCalc Remote Link TLS bridge
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$PY $BRIDGE_DST
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

$SUDO systemctl daemon-reload
$SUDO systemctl enable mkc-bridge >/dev/null 2>&1 || true
$SUDO systemctl restart mkc-bridge

for _ in $(seq 1 10); do
  ss -ltn 2>/dev/null | grep -q "127.0.0.1:${LOCAL_PORT}" && break
  sleep 1
done
ss -ltn 2>/dev/null | grep -q "127.0.0.1:${LOCAL_PORT}" || {
  err "El puente no quedó escuchando en ${LOCAL_PORT}. Revisá:  systemctl status mkc-bridge"
  exit 1
}
log "Puente activo: 127.0.0.1:${LOCAL_PORT}  →  mqtt.makercalc.app:8883 (TLS)"

# 4 ── Apuntar Moonraker al puente (solo dentro de [mqtt]) ───────────────────
log "Apuntando Moonraker al puente (backup en ${CONF}.mkc-bak)…"
$SUDO cp "$CONF" "${CONF}.mkc-bak"
$SUDO awk -v lp="$LOCAL_PORT" '
  /^\[/ { sec = $0 }
  sec == "[mqtt]" && /^address:/    { print "address: 127.0.0.1"; next }
  sec == "[mqtt]" && /^port:/       { print "port: " lp;          next }
  sec == "[mqtt]" && /^enable_tls:/ { print "enable_tls: False";  next }
  { print }
' "$CONF" > /tmp/mkc-moonraker.tmp && $SUDO cp /tmp/mkc-moonraker.tmp "$CONF" && rm -f /tmp/mkc-moonraker.tmp

# 5 ── Reiniciar Moonraker ──────────────────────────────────────────────────
log "Reiniciando Moonraker…"
$SUDO systemctl restart moonraker 2>/dev/null || $SUDO systemctl restart moonraker.service 2>/dev/null || true

echo
log "¡Listo! Tu impresora aparecerá conectada en MakerCalc en unos segundos."
log "Para deshacer todo:  ./uninstall.sh"
