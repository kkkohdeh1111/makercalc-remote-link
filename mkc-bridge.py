#!/usr/bin/env python3
# ─────────────────────────────────────────────────────────────────────────
# MakerCalc Remote Link — puente TLS en Python puro (solo stdlib).
#
# Escucha local en 127.0.0.1:1883 y reenvía cada conexión CIFRADA (TLS) al
# broker de MakerCalc. Moonraker habla en claro con este proceso —dentro de
# la placa, nunca sale a la red— y el puente lo sella hacia afuera.
#
# No instala nada. No necesita root para correr. Verifica el certificado del
# broker contra las CA del sistema (create_default_context: check_hostname +
# CERT_REQUIRED por defecto).
# ─────────────────────────────────────────────────────────────────────────
import socket
import ssl
import sys
import threading

LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 1883
BROKER_HOST = "mqtt.makercalc.app"
BROKER_PORT = 8883

_ctx = ssl.create_default_context()  # verifica cadena + hostname del broker


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
    upstream = None
    try:
        raw = socket.create_connection((BROKER_HOST, BROKER_PORT), timeout=20)
        upstream = _ctx.wrap_socket(raw, server_hostname=BROKER_HOST)
    except Exception as exc:  # DNS caído al boot, red no lista, etc.
        sys.stderr.write("[mkc-bridge] upstream error: %s\n" % exc)
        sys.stderr.flush()
        client.close()
        return
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
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((LISTEN_HOST, LISTEN_PORT))
    srv.listen(16)
    sys.stdout.write(
        "[mkc-bridge] escuchando %s:%d  ->  %s:%d (TLS)\n"
        % (LISTEN_HOST, LISTEN_PORT, BROKER_HOST, BROKER_PORT)
    )
    sys.stdout.flush()
    while True:
        client, _ = srv.accept()
        threading.Thread(target=_handle, args=(client,), daemon=True).start()


if __name__ == "__main__":
    main()
