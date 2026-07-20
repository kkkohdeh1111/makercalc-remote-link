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
# Robustez (2026-07-20):
#   · IP del broker CACHEADO en un thread de fondo (con reintento al boot).
#     Resolver DNS por-conexión es lento/frágil en placas viejas con DNS frío
#     al arranque: armar el upstream tardaba más que el timeout de CONNACK de
#     Moonraker → la conexión se caía a los ~6s sin completar. Con el IP
#     cacheado cada conexión arranca al instante. El TLS se sigue verificando
#     contra el HOSTNAME (server_hostname), así el cert se valida igual.
#   · settimeout(None) en los sockets del relay: create_connection deja un
#     timeout de 20s pegado que cortaba la conexión en gaps de idle (>20s sin
#     tráfico del broker). Un relay persistente no debe tener ese timeout.
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
    ip = _get_ip()
    if ip is None:
        # cache aún frío (primeros segundos post-boot): resolver on-demand
        try:
            ip = socket.gethostbyname(BROKER_HOST)
            _set_ip(ip)
        except OSError as exc:
            sys.stderr.write("[mkc-bridge] sin DNS: %s\n" % exc)
            sys.stderr.flush()
            client.close()
            return
    upstream = None
    try:
        raw = socket.create_connection((ip, BROKER_PORT), timeout=20)
        raw.settimeout(None)  # relay persistente: sin timeout de idle
        upstream = _ctx.wrap_socket(raw, server_hostname=BROKER_HOST)
        upstream.settimeout(None)
    except Exception as exc:
        sys.stderr.write("[mkc-bridge] upstream error: %s\n" % exc)
        sys.stderr.flush()
        client.close()
        return
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
        "[mkc-bridge] escuchando %s:%d  ->  %s:%d (TLS, IP cacheado)\n"
        % (LISTEN_HOST, LISTEN_PORT, BROKER_HOST, BROKER_PORT)
    )
    sys.stdout.flush()
    while True:
        client, _ = srv.accept()
        threading.Thread(target=_handle, args=(client,), daemon=True).start()


if __name__ == "__main__":
    main()
