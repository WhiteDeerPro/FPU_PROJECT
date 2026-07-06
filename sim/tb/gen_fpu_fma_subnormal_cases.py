#!/usr/bin/env python3

from fractions import Fraction
import random

CASES_PER_RM = 1000
SEED = 0x464d4153
RMS = [0, 1, 2, 3, 4]

FORMATS = {
    "S": {
        "fmt_bit": 0,
        "p": 24,
        "exp_bits": 8,
        "frac_bits": 23,
        "bias": 127,
        "emin": -126,
        "pack": lambda x: 0xffff_ffff_0000_0000 | x,
    },
    "D": {
        "fmt_bit": 1,
        "p": 53,
        "exp_bits": 11,
        "frac_bits": 52,
        "bias": 1023,
        "emin": -1022,
        "pack": lambda x: x,
    },
}


def shl_frac(value, shift):
    return value * (1 << shift) if shift >= 0 else value / (1 << -shift)


def floor_log2(value):
    n = value.numerator
    d = value.denominator
    exp = n.bit_length() - d.bit_length()
    if exp >= 0:
        if n < (d << exp):
            exp -= 1
    else:
        if (n << -exp) < d:
            exp -= 1
    return exp


def round_int(value, rm, sign):
    q, r = divmod(value.numerator, value.denominator)
    if r == 0:
        return q, False

    twice_r = 2 * r
    inc = False
    if rm == 0:
        inc = twice_r > value.denominator or (
            twice_r == value.denominator and (q & 1) != 0
        )
    elif rm == 2:
        inc = sign
    elif rm == 3:
        inc = not sign
    elif rm == 4:
        inc = twice_r >= value.denominator

    return q + (1 if inc else 0), True


def encode_result(fmt, sign, value, rm):
    if value == 0:
        return int(sign) << (31 if fmt["frac_bits"] == 23 else 63), False

    p = fmt["p"]
    frac_bits = fmt["frac_bits"]
    width = 32 if frac_bits == 23 else 64
    sign_bit = int(sign) << (width - 1)
    frac_mask = (1 << frac_bits) - 1

    exp = floor_log2(value)
    if exp < fmt["emin"]:
        scaled = shl_frac(value, (p - 1) - fmt["emin"])
        sig, inexact = round_int(scaled, rm, sign)
        if sig == 0:
            return sign_bit, inexact
        if sig >= (1 << (p - 1)):
            return sign_bit | (1 << frac_bits), inexact
        return sign_bit | (sig & frac_mask), inexact

    scaled = shl_frac(value, (p - 1) - exp)
    sig, inexact = round_int(scaled, rm, sign)
    if sig >= (1 << p):
        sig >>= 1
        exp += 1

    exp_field = exp + fmt["bias"]
    return sign_bit | (exp_field << frac_bits) | (
        (sig - (1 << (p - 1))) & frac_mask
    ), inexact


def decode_finite(fmt, bits):
    frac_bits = fmt["frac_bits"]
    exp_bits = fmt["exp_bits"]
    width = 32 if frac_bits == 23 else 64
    sign = bool((bits >> (width - 1)) & 1)
    exp_field = (bits >> frac_bits) & ((1 << exp_bits) - 1)
    frac = bits & ((1 << frac_bits) - 1)

    if exp_field == 0:
        mant = frac
        exp = fmt["emin"]
    else:
        mant = (1 << frac_bits) | frac
        exp = exp_field - fmt["bias"]

    return sign, shl_frac(Fraction(mant, 1), exp - frac_bits)


def raw_exp_field(fmt, bits):
    return (bits >> fmt["frac_bits"]) & ((1 << fmt["exp_bits"]) - 1)


def raw_frac_field(fmt, bits):
    return bits & ((1 << fmt["frac_bits"]) - 1)


def make_case(fmt_name, rm, rng):
    fmt = FORMATS[fmt_name]
    width = 32 if fmt_name == "S" else 64
    max_exp = (1 << fmt["exp_bits"]) - 2

    while True:
        sign_a = rng.getrandbits(1)
        sign_b = rng.getrandbits(1)
        frac_a = rng.getrandbits(fmt["frac_bits"])
        frac_b = rng.getrandbits(fmt["frac_bits"])
        exp_a = rng.randint(1, min(24, max_exp))
        exp_b = rng.randint(max(fmt["bias"] - 8, 1), min(fmt["bias"] + 8, max_exp))

        a_raw = (sign_a << (width - 1)) | (exp_a << fmt["frac_bits"]) | frac_a
        b_raw = (sign_b << (width - 1)) | (exp_b << fmt["frac_bits"]) | frac_b
        c_raw = 1 << (width - 1) if (sign_a ^ sign_b) else 0

        a_sign, a_val = decode_finite(fmt, a_raw)
        b_sign, b_val = decode_finite(fmt, b_raw)
        result_raw, nx = encode_result(fmt, a_sign ^ b_sign, a_val * b_val, rm)

        if raw_exp_field(fmt, result_raw) == 0 and raw_frac_field(fmt, result_raw) != 0:
            return (
                fmt["fmt_bit"],
                rm,
                fmt["pack"](a_raw),
                fmt["pack"](b_raw),
                fmt["pack"](c_raw),
                fmt["pack"](result_raw),
                int(nx),
            )


def main():
    rng = random.Random(SEED)
    with open("fpu_fma_subnormal_cases.mem", "w", encoding="ascii") as mem:
        for fmt_name in ("S", "D"):
            for rm in RMS:
                for _idx in range(CASES_PER_RM):
                    fmt_bit, rm_bits, a, b, c, result, nx = make_case(fmt_name, rm, rng)
                    word = (
                        (fmt_bit << 260) |
                        (rm_bits << 257) |
                        (a << 193) |
                        (b << 129) |
                        (c << 65) |
                        (result << 1) |
                        nx
                    )
                    mem.write(f"{word:066x}\n")


if __name__ == "__main__":
    main()
