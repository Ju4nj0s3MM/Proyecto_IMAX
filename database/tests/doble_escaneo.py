"""Prueba de concurrencia: N lecturas simultáneas del mismo QR en la puerta.

Resultado esperado: exactamente una lectura exitosa; el resto "Entrada ya utilizada".
Conexión por defecto: localhost:5432, usuario postgres, contraseña postgres y base imax.
Se puede cambiar con las variables PGHOST, PGPORT, PGUSER, PGPASSWORD y PGDATABASE.
Uso: python database/tests/doble_escaneo.py [hilos]
"""
import os
import sys
import threading
import time
from collections import Counter

import psycopg2

HILOS = int(sys.argv[1]) if len(sys.argv) > 1 else 30


def conectar():
    conn = psycopg2.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=os.environ.get("PGPORT", "5432"),
        user=os.environ.get("PGUSER", "postgres"),
        password=os.environ.get("PGPASSWORD", "postgres"),
        dbname=os.environ.get("PGDATABASE", "imax"))
    conn.autocommit = True
    return conn


def preparar(cur, qr):
    """Crea una sala con una puerta, una función en la ventana de ingreso y un boleto emitido."""
    sufijo = str(int(time.time() * 1000))
    cur.execute("select min(id) from cine")
    cine_id = cur.fetchone()[0]
    cur.execute("select min(id) from pelicula")
    pelicula_id = cur.fetchone()[0]
    cur.execute("select id from zona_asiento where nombre = 'General'")
    zona_id = cur.fetchone()[0]
    cur.execute("select id from usuario where email = 'cliente@imax.test'")
    usuario_id = cur.fetchone()[0]

    cur.execute("insert into sala (cine_id, nombre, capacidad) values (%s, %s, 1) returning id",
                (cine_id, "Sala prueba " + sufijo))
    sala_id = cur.fetchone()[0]
    cur.execute("insert into puerta (sala_id, nombre) values (%s, 'Tótem prueba') returning id", (sala_id,))
    puerta_id = cur.fetchone()[0]
    cur.execute("insert into asiento (sala_id, zona_asiento_id, fila, numero) values (%s, %s, 'A', 1) returning id",
                (sala_id, zona_id))
    asiento_id = cur.fetchone()[0]
    cur.execute("insert into funcion (pelicula_id, sala_id, inicio) values (%s, %s, now() + interval '10 minutes') returning id",
                (pelicula_id, sala_id))
    funcion_id = cur.fetchone()[0]
    cur.execute("""insert into orden (usuario_id, funcion_id, estado, subtotal, descuento, cargo_servicio, total, pagada_en)
                   values (%s, %s, 'PAGADA', 8.50, 0, 0.75, 9.25, now()) returning id""", (usuario_id, funcion_id))
    orden_id = cur.fetchone()[0]
    cur.execute("""insert into reserva_asiento (orden_id, funcion_id, asiento_id, estado, bloqueado_hasta, precio, cargo_servicio)
                   values (%s, %s, %s, 'VENDIDO', now(), 8.50, 0.75) returning id""", (orden_id, funcion_id, asiento_id))
    reserva_id = cur.fetchone()[0]
    cur.execute("""insert into boleto (orden_id, reserva_asiento_id, funcion_id, asiento_id, codigo_qr, estado)
                   values (%s, %s, %s, %s, %s, 'EMITIDO')""", (orden_id, reserva_id, funcion_id, asiento_id, qr))
    return puerta_id


def escanear(qr, puerta_id, barrera, resultados):
    conn = conectar()
    cur = conn.cursor()
    barrera.wait()  # todos disparan al mismo tiempo
    cur.execute("select ok, mensaje from fn_validar_entrada(%s, %s)", (qr, puerta_id))
    resultados.append(cur.fetchone())
    conn.close()


def main():
    qr = "QR-CONCURRENCIA-" + str(int(time.time() * 1000))
    conn = conectar()
    cur = conn.cursor()
    puerta_id = preparar(cur, qr)
    print(f"Boleto {qr} listo. Lanzando {HILOS} lecturas simultáneas en la puerta {puerta_id}...")

    resultados = []
    barrera = threading.Barrier(HILOS)
    hilos = [threading.Thread(target=escanear, args=(qr, puerta_id, barrera, resultados)) for _ in range(HILOS)]
    inicio = time.time()
    for h in hilos:
        h.start()
    for h in hilos:
        h.join()
    duracion = time.time() - inicio

    conteo = Counter((ok, mensaje) for ok, mensaje in resultados)
    print(f"\nResultados ({HILOS} lecturas en {duracion:.2f} s):")
    for (ok, mensaje), n in conteo.most_common():
        print(f"  {'ENTRÓ   ' if ok else 'RECHAZADO'} | {mensaje}: {n}")

    cur.execute("select count(*) from acceso_puerta_log where codigo_qr = %s and resultado = 'EXITOSO'", (qr,))
    exitosos_log = cur.fetchone()[0]
    cur.execute("select estado from boleto where codigo_qr = %s", (qr,))
    estado = cur.fetchone()[0]
    print(f"\nBitácora: {exitosos_log} ingreso(s) exitoso(s). Estado final del boleto: {estado}")

    exitosos = sum(1 for ok, _ in resultados if ok)
    if len(resultados) == HILOS and exitosos == 1 and exitosos_log == 1 and estado == "USADO":
        print("\nPRUEBA APROBADA: solo una lectura pudo ingresar.")
        sys.exit(0)
    print("\nPRUEBA FALLIDA: hubo más de un ingreso o faltaron resultados.")
    sys.exit(1)


if __name__ == "__main__":
    main()