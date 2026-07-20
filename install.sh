#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# MakerCalc Remote Link — instalador del puente seguro
#
#   git clone https://github.com/makercalc/remote-link
#   cd remote-link && ./install.sh
#
# Para impresoras con un Moonraker viejo que no habla TLS. Levanta un puente
# local (stunnel): Moonraker conecta en claro a 127.0.0.1 —dentro de la placa,
# nunca sale a la red— y stunnel lo envuelve en TLS hacia el broker.
#
# NO toca tu token (vive en moonraker.conf y viaja siempre sellado).
# NO abre puertos en tu router. NO toca Klipper. Deja backup y es reversible
# (./uninstall.sh). Idempotente: podés correrlo varias veces.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

BROKER_HOST="mqtt.makercalc.app"
BROKER_PORT="8883"
LOCAL_PORT="1883"
STUNNEL_CONF="/etc/stunnel/makercalc.conf"

log() { printf '\033[1;36m[MakerCalc]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[MakerCalc]\033[0m %s\n' "$*" >&2; }

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || { err "Necesito root o sudo para instalar stunnel."; exit 1; }
  SUDO="sudo"
  log "Voy a pedir tu contraseña (sudo) para instalar stunnel y editar la config."
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

# 2 ── Instalar stunnel ─────────────────────────────────────────────────────
if ! command -v stunnel >/dev/null 2>&1 && ! command -v stunnel4 >/dev/null 2>&1; then
  log "Instalando el puente (stunnel)…"
  export DEBIAN_FRONTEND=noninteractive
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq stunnel4 >/dev/null
else
  log "stunnel ya está instalado."
fi

# 3 ── Bundle de certificados CA (para verificar que el broker es el real) ───
CAFILE=""
for c in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt; do
  [ -f "$c" ] && CAFILE="$c" && break
done
[ -n "$CAFILE" ] || { err "No encontré el bundle de certificados CA del sistema."; exit 1; }

# 4 ── Escribir la config del puente ────────────────────────────────────────
log "Configurando el puente TLS…"
$SUDO tee "$STUNNEL_CONF" >/dev/null <<EOF
# MakerCalc Remote Link — puente TLS. Generado por install.sh.
[mqtt-makercalc]
client = yes
accept = 127.0.0.1:${LOCAL_PORT}
connect = ${BROKER_HOST}:${BROKER_PORT}
verifyChain = yes
CAfile = ${CAFILE}
checkHost = ${BROKER_HOST}
sni = ${BROKER_HOST}
EOF

[ -f /etc/default/stunnel4 ] && $SUDO sed -i 's/^ENABLED=0/ENABLED=1/' /etc/default/stunnel4 || true
$SUDO systemctl enable stunnel4 >/dev/null 2>&1 || true
$SUDO systemctl restart stunnel4

for _ in $(seq 1 10); do
  ss -ltn 2>/dev/null | grep -q "127.0.0.1:${LOCAL_PORT}" && break
  sleep 1
done
ss -ltn 2>/dev/null | grep -q "127.0.0.1:${LOCAL_PORT}" || {
  err "El puente no quedó escuchando en ${LOCAL_PORT}. Revisá:  systemctl status stunnel4"
  exit 1
}
log "Puente activo: 127.0.0.1:${LOCAL_PORT}  →  ${BROKER_HOST}:${BROKER_PORT} (TLS)"

# 5 ── Apuntar Moonraker al puente (solo dentro de [mqtt]) ───────────────────
log "Apuntando Moonraker al puente (backup en ${CONF}.mkc-bak)…"
$SUDO cp "$CONF" "${CONF}.mkc-bak"
$SUDO awk -v lp="$LOCAL_PORT" '
  /^\[/ { sec = $0 }
  sec == "[mqtt]" && /^address:/    { print "address: 127.0.0.1"; next }
  sec == "[mqtt]" && /^port:/       { print "port: " lp;          next }
  sec == "[mqtt]" && /^enable_tls:/ { print "enable_tls: False";  next }
  { print }
' "$CONF" > /tmp/mkc-moonraker.tmp && $SUDO cp /tmp/mkc-moonraker.tmp "$CONF" && rm -f /tmp/mkc-moonraker.tmp

# 6 ── Reiniciar Moonraker ──────────────────────────────────────────────────
log "Reiniciando Moonraker…"
$SUDO systemctl restart moonraker 2>/dev/null || $SUDO systemctl restart moonraker.service 2>/dev/null || true

echo
log "¡Listo! Tu impresora aparecerá conectada en MakerCalc en unos segundos."
log "Para deshacer todo:  ./uninstall.sh"
