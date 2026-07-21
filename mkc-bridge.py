#!/usr/bin/env python3
# ─────────────────────────────────────────────────────────────────────────
# MakerCalc Remote Link — puente TLS en Python puro (solo stdlib).
#
# Escucha local en 127.0.0.1:1883 y reenvía cada conexión CIFRADA (TLS) al
# broker de MakerCalc. Moonraker habla en claro con este proceso —dentro de
# la placa, nunca sale a la red— y el puente lo sella hacia afuera.
#
# No instala nada. Verifica el certificado del broker contra las CA del
# sistema (create_default_context: check_hostname + CERT_REQUIRED).
#
# Robustez:
#   · IP del broker CACHEADO en un thread de fondo (con reintento al boot).
#     Resolver DNS por-conexión es lento/frágil en placas viejas con DNS frío.
#     El TLS se sigue verificando contra el HOSTNAME (server_hostname).
#   · settimeout(None) en los sockets del relay: create_connection deja un
#     timeout de 20s pegado que cortaba la conexión en gaps de idle.
#   · HOLD + RETRY del upstream (clave, 2026-07-21): al boot la red tarda en
#     tener ruta. Si cerráramos el socket de Moonraker al primer fallo, el
#     Moonraker viejo ve una caída y NO reintenta (bug conocido) → el dato se
#     congela hasta un `restart moonraker` que BRICKEA la pantalla en placas
#     MKS/Elegoo. En vez: aguantamos el socket de Moonraker hasta ~45s
#     (dentro de su keepalive de 60s) reintentando el upstream. Cuando la red
#     sube, relayamos → Moonraker conecta a la PRIMERA, nunca ve una caída,
#     nunca se rinde. Cero restart de Moonraker, se autorepara en cada boot.
# ─────────────────────────────────────────────────────────────────────────
import socket
import ssl
import sys
import threading
import time

LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 1883
BROKER_HOST = "mqtt.makercalc.app"
BROKER_PORT = 8883
DNS_REFRESH_S = 300
# Cuánto aguantar el socket de Moonraker mientras la red sube. DEBE ser menor
# que el keepalive MQTT de Moonraker (paho default 60s) para que él no corte.
UPSTREAM_HOLD_S = 45
RETRY_EVERY_S = 1.5

_ctx = ssl.create_default_context()

_broker_ip = None
_broker_ip_lock = threading.Lock()


def _set_ip(ip):
    global _broker_ip
    with _broker_ip_lock:
        _broker_ip = ip


def _get_ip():
    with _broker_ip_lock:
        return _broker_ip


def _dns_worker():
    # Resuelve el IP del broker y lo refresca cada 5 min. Al boot, si la red
    # aún no está lista, reintenta cada 3s hasta lograrlo.
    while True:
        try:
            _set_ip(socket.gethostbyname(BROKER_HOST))
            time.sleep(DNS_REFRESH_S)
        except OSError as exc:
            sys.stderr.write("[mkc-bridge] DNS aun no disponible: %s\n" % exc)
            sys.stderr.flush()
            time.sleep(3)


def _connect_upstream():
    # Intenta armar el upstream TLS al broker, aguantando hasta UPSTREAM_HOLD_S.
    # Devuelve el socket TLS, o None si tras la espera la red sigue caída.
    deadline = time.monotonic() + UPSTREAM_HOLD_S
    while time.monotonic() < deadline:
        ip = _get_ip()
        if ip is not None:
            try:
                raw = socket.create_connection((ip, BROKER_PORT), timeout=10)
                raw.settimeout(None)  # relay persistente: sin timeout de idle
                return _ctx.wrap_socket(raw, server_hostname=BROKER_HOST)
            except Exception:
                pass  # red no lista / refused / TLS: reintentar sin cerrar al cliente
        time.sleep(RETRY_EVERY_S)
    return None


def _pipe(src, dst):
    try:
        while True:
            data = src.recv(4096)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def _handle(client):
    # NO cerramos el socket de Moonraker al primer fallo: lo aguantamos mientras
    # la red sube (hold+retry). El CONNECT que Moonraker ya mandó queda en el
    # buffer del socket y se relaya intacto cuando el upstream conecta.
    upstream = _connect_upstream()
    if upstream is None:
        sys.stderr.write("[mkc-bridge] upstream no disponible tras espera; cierro\n")
        sys.stderr.flush()
        try:
            client.close()
        except OSError:
            pass
        return
    upstream.settimeout(None)
    client.settimeout(None)
    t1 = threading.Thread(target=_pipe, args=(client, upstream), daemon=True)
    t2 = threading.Thread(target=_pipe, args=(upstream, client), daemon=True)
    t1.start()
    t2.start()
    t1.join()
    t2.join()
    for sock in (client, upstream):
        try:
            sock.close()
        except OSError:
            pass


def main():
    # El resolver corre en background; el listener arranca YA (bind local no
    # necesita DNS), así Moonraker siempre encuentra el puerto y reintenta.
    threading.Thread(target=_dns_worker, daemon=True).start()
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((LISTEN_HOST, LISTEN_PORT))
    srv.listen(16)
    sys.stdout.write(
        "[mkc-bridge] escuchando %s:%d  ->  %s:%d (TLS, IP cacheado, hold %ds)\n"
        % (LISTEN_HOST, LISTEN_PORT, BROKER_HOST, BROKER_PORT, UPSTREAM_HOLD_S)
    )
    sys.stdout.flush()
    while True:
        try:
            client, _ = srv.accept()
        except OSError:
            continue  # error transitorio de accept: no matar el loop
        threading.Thread(target=_handle, args=(client,), daemon=True).start()


if __name__ == "__main__":
    main()
