# MakerCalc Remote Link — Puente seguro

Conecta tu impresora a [MakerCalc](https://makercalc.app) cuando tu Moonraker es
una versión vieja que **no habla TLS** (cifrado).

Es un instalador chico y transparente. **Leelo antes de correrlo** — son ~60
líneas en castellano.

## ¿Qué hace?

Levanta un *puente* local con [`stunnel`](https://www.stunnel.org/) (herramienta
estándar, en los repos de Debian):

1. Encuentra tu `moonraker.conf`
2. Instala `stunnel`
3. Configura el puente: escucha local en `127.0.0.1:1883` y reenvía **cifrado
   (TLS)** a `mqtt.makercalc.app:8883`, verificando el certificado del broker
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
git clone https://github.com/makercalc/remote-link
cd remote-link
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
- **Herramienta estándar** — `stunnel`, usada en producción hace 20 años.
- **Mínimo privilegio** — solo lo necesario para instalar un paquete y editar
  dos líneas de config.

## Licencia

MIT — ver [LICENSE](./LICENSE).
