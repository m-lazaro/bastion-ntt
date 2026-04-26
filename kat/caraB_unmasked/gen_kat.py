#!/usr/bin/env python3
"""Generate KAT hex files for Kyber-512 NTT testbench."""
import struct

Q = 3329
QINV = -3327  # q^-1 mod 2^16 (signed)

ZETAS = [
    -1044, -758, -359, -1517, 1493, 1422, 287, 202,
    -171, 622, 1577, 182, 962, -1202, -1474, 1468,
    573, -1325, 264, 383, -829, 1458, -1602, -130,
    -681, 1017, 732, 608, -1542, 411, -205, -1571,
    1223, 652, -552, 1015, -1293, 1491, -282, -1544,
    516, -8, -320, -666, -1618, -1162, 126, 1469,
    -853, -90, -271, 830, 107, -1421, -247, -951,
    -398, 961, -1508, -725, 448, -1065, 677, -1275,
    -1103, 430, 555, 843, -1251, 871, 1550, 105,
    422, 587, 177, -235, -291, -460, 1574, 1653,
    -246, 778, 1159, -147, -777, 1483, -602, 1119,
    -1590, 644, -872, 349, 418, 329, -156, -75,
    817, 1097, 603, 610, 1322, -1285, -1465, 384,
    -1215, -136, 1218, -1335, -874, 220, -1187, -1659,
    -1185, -1530, -1278, 794, -1510, -854, -870, 478,
    -108, -308, 996, 991, 958, -1460, 1522, 1628,
]

def to_int16(x):
    return ((x + 0x8000) & 0xFFFF) - 0x8000

def montgomery_reduce(x):
    m = to_int16(to_int16(x & 0xFFFF) * QINV)
    u = (x - m * Q) >> 16
    return to_int16(u)

def fqmul(a, b):
    return montgomery_reduce(to_int16(a) * to_int16(b))

def ntt(r):
    r = list(r)
    k = 1
    l = 128
    while l >= 2:
        s = 0
        while s < 256:
            z = ZETAS[k]; k += 1
            for j in range(s, s + l):
                t = fqmul(z, r[j + l])
                r[j + l] = to_int16(r[j] - t)
                r[j]     = to_int16(r[j] + t)
            s = j + l + 1
        l >>= 1
    return r

def to_hex16(v):
    return format(v & 0xFFFF, '04x')

# Generate a deterministic test vector
import random
random.seed(42)
inp = [random.randint(-1664, 1664) for _ in range(256)]
out = ntt(inp)

with open("kat_input.hex", "w") as f:
    for v in inp:
        f.write(to_hex16(v) + "\n")

with open("kat_expected.hex", "w") as f:
    for v in out:
        f.write(to_hex16(v) + "\n")

print("Generated kat_input.hex and kat_expected.hex")
