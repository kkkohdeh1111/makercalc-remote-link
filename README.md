# MakerCalc Remote Link — Puente seguro

Conecta tu impresora a [MakerCalc](https://makercalc.app) cuando tu Moonraker es
una versión vieja que **no habla TLS** (cifrado).

Es un instalador chico y transparente. **Leelo antes de correrlo** — el puente
son ~40 líneas de Python (`mkc-bridge.py`), stdlib pura.

## ¿Qué hace?

Levanta un *puente* local en **Python puro** (`mkc-bridge.py`, sin instalar
ningún paquete — usa el `python3` que ya tenés):

1. Encuentra tu `moonraker.conf`
2. Instala el puente como servicio (`mkc-bridge`) con el python del sistema
3. El puente escucha local en `127.0.0.1:1883` y reenvía **cifrado (TLS)** a
   `mqtt.makercalc.app:8883`, verificando el certificado del broker
4. Apunta Moonraker al puente (cambia `address` y `port` **solo** dentro de
   `[mqtt]`), con backup en `moonraker.conf.mkc-bak`
5. Reinicia Moonraker

Moonraker manda los datos en claro **de un programa a otro dentro de tu placa**
(nunca salen a la red); recién al salir a internet van sellados.

## ¿Qué NO hace?

- **No toca tu token.** Vive en `moonraker.conf`; el puente solo mueve bytes.
- **No abre puertos** en tu router.
- **No toca Klipper** ni tu impresión.
- **No manda nada a ningún lado** salvo el broker de MakerCalc que ya tenías.

## Instalar

```bash
cd ~
git clone https://github.com/kkkohdeh1111/makercalc-remote-link
cd makercalc-remote-link
cat install.sh        # leelo primero
./install.sh
```

> Primero pegá el bloque `[mqtt]` de MakerCalc en tu `moonraker.conf` (desde la
> web → *Conectar impresora*). El instalador lo necesita para funcionar.

## Deshacer

```bash
./uninstall.sh
```

Restaura tu `moonraker.conf` desde el backup, borra el puente y reinicia. Tu
impresora queda **exactamente** como estaba.

## ¿Por qué confiar en esto?

- **Open source** — este mismo código es lo que corre. Sin binarios, sin humo.
- **Reversible** — backup automático + `uninstall.sh`.
- **Sin dependencias** — el puente es Python stdlib puro, no instala paquetes
  (anda hasta en placas viejas con `apt` roto/EOL).
- **Mínimo privilegio** — solo lo necesario para instalar un servicio y editar
  dos líneas de config.

## Licencia

MIT — ver [LICENSE](./LICENSE).
