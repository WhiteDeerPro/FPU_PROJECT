#!/usr/bin/env python3

from fractions import Fraction
import random

CASES_PER_RM = 1000
SUBNORMAL_CASES_PER_RM = 1000
SEED = 0x46505544

RMS = [
    ("RNE", 0),
    ("RTZ", 1),
    ("RDN", 2),
    ("RUP", 3),
    ("RMM", 4),
]

FORMATS = {
    "S": {
        "fmt_bit": 0,
        "p": 24,
        "exp_bits": 8,
        "frac_bits": 23,
        "bias": 127,
        "emin": -126,
        "emax": 127,
        "pack": lambda x: 0xFFFF_FFFF_0000_0000 | x,
    },
    "D": {
        "fmt_bit": 1,
        "p": 53,
        "exp_bits": 11,
        "frac_bits": 52,
        "bias": 1023,
        "emin": -1022,
        "emax": 1023,
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
    num = value.numerator
    den = value.denominator
    q, r = divmod(num, den)
    inexact = r != 0

    if not inexact:
        return q, False

    twice_r = 2 * r
    inc = False
    if rm == 0:
        inc = twice_r > den or (twice_r == den and (q & 1) != 0)
    elif rm == 1:
        inc = False
    elif rm == 2:
        inc = sign
    elif rm == 3:
        inc = not sign
    elif rm == 4:
        inc = twice_r >= den

    return q + (1 if inc else 0), True


def overflow_result(fmt, sign, rm):
    exp_mask = (1 << fmt["exp_bits"]) - 1
    frac_mask = (1 << fmt["frac_bits"]) - 1
    to_inf = (
        rm == 0 or
        rm == 4 or
        (rm == 3 and not sign) or
        (rm == 2 and sign)
    )
    exp_field = exp_mask if to_inf else exp_mask - 1
    frac_field = 0 if to_inf else frac_mask
    width = 32 if fmt["frac_bits"] == 23 else 64
    return (int(sign) << (width - 1)) | (exp_field << fmt["frac_bits"]) | frac_field


def encode_result(fmt, sign, value, rm):
    if value == 0:
        return int(sign) << (31 if fmt["frac_bits"] == 23 else 63), False

    p = fmt["p"]
    emin = fmt["emin"]
    emax = fmt["emax"]
    frac_bits = fmt["frac_bits"]
    exp_bits = fmt["exp_bits"]
    bias = fmt["bias"]
    exp_mask = (1 << exp_bits) - 1
    frac_mask = (1 << frac_bits) - 1
    width = 32 if frac_bits == 23 else 64
    sign_bit = int(sign) << (width - 1)

    exp = floor_log2(value)
    if exp < emin:
      scaled = shl_frac(value, (p - 1) - emin)
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

    if exp > emax:
        return overflow_result(fmt, sign, rm), True

    exp_field = exp + bias
    if exp_field >= exp_mask:
        return overflow_result(fmt, sign, rm), True

    return sign_bit | (exp_field << frac_bits) | ((sig - (1 << (p - 1))) & frac_mask), inexact


def decode_finite(fmt, bits):
    frac_bits = fmt["frac_bits"]
    exp_bits = fmt["exp_bits"]
    bias = fmt["bias"]
    emin = fmt["emin"]
    width = 32 if frac_bits == 23 else 64
    sign = bool((bits >> (width - 1)) & 1)
    exp_field = (bits >> frac_bits) & ((1 << exp_bits) - 1)
    frac = bits & ((1 << frac_bits) - 1)

    if exp_field == 0:
        mant = frac
        exp = emin
    else:
        mant = (1 << frac_bits) | frac
        exp = exp_field - bias

    value = shl_frac(Fraction(mant, 1), exp - frac_bits)
    return sign, value


def make_normal_bits(fmt, rng):
    frac_bits = fmt["frac_bits"]
    exp_bits = fmt["exp_bits"]
    width = 32 if frac_bits == 23 else 64
    sign = rng.getrandbits(1)
    exp_field = rng.randint(1, (1 << exp_bits) - 2)
    frac = rng.getrandbits(frac_bits)
    return (sign << (width - 1)) | (exp_field << frac_bits) | frac


def raw_exp_field(fmt, bits):
    return (bits >> fmt["frac_bits"]) & ((1 << fmt["exp_bits"]) - 1)


def raw_frac_field(fmt, bits):
    return bits & ((1 << fmt["frac_bits"]) - 1)


def pack_case(fmt, rm, a_raw, b_raw):
    a_sign, a_val = decode_finite(fmt, a_raw)
    b_sign, b_val = decode_finite(fmt, b_raw)
    q_sign = a_sign ^ b_sign
    q_val = a_val / b_val
    result_raw, nx = encode_result(fmt, q_sign, q_val, rm)
    return (
        fmt["fmt_bit"],
        rm,
        fmt["pack"](a_raw),
        fmt["pack"](b_raw),
        fmt["pack"](result_raw),
        int(nx),
        result_raw,
    )


def make_case(fmt_name, rm, rng, idx):
    fmt = FORMATS[fmt_name]
    if idx % 20 == 0:
        numer = rng.randint(1, 1 << 20)
        denom = rng.randint(1, 1 << 20)
        a_raw = encode_result(fmt, bool(rng.getrandbits(1)), Fraction(numer, 1), 0)[0]
        b_raw = encode_result(fmt, bool(rng.getrandbits(1)), Fraction(denom, 1), 0)[0]
    elif idx % 20 == 1:
        exp_a = rng.randint(fmt["bias"] - 8, fmt["bias"] + 8)
        exp_b = rng.randint(fmt["bias"] - 8, fmt["bias"] + 8)
        a_raw = (rng.getrandbits(1) << (31 if fmt_name == "S" else 63)) | (exp_a << fmt["frac_bits"])
        b_raw = (rng.getrandbits(1) << (31 if fmt_name == "S" else 63)) | (exp_b << fmt["frac_bits"])
    else:
        a_raw = make_normal_bits(fmt, rng)
        b_raw = make_normal_bits(fmt, rng)

    return pack_case(fmt, rm, a_raw, b_raw)[:6]


def make_subnormal_result_case(fmt_name, rm, rng):
    fmt = FORMATS[fmt_name]
    width = 32 if fmt_name == "S" else 64
    min_norm_exp = 1
    max_exp = (1 << fmt["exp_bits"]) - 2

    while True:
        sign_a = rng.getrandbits(1)
        sign_b = rng.getrandbits(1)
        frac_a = rng.getrandbits(fmt["frac_bits"])
        frac_b = rng.getrandbits(fmt["frac_bits"])

        exp_b = rng.randint(max(fmt["bias"] - 16, min_norm_exp),
                            min(fmt["bias"] + 16, max_exp))
        exp_a = rng.randint(min_norm_exp, min(24, max_exp))

        a_raw = (sign_a << (width - 1)) | (exp_a << fmt["frac_bits"]) | frac_a
        b_raw = (sign_b << (width - 1)) | (exp_b << fmt["frac_bits"]) | frac_b
        packed = pack_case(fmt, rm, a_raw, b_raw)
        result_raw = packed[6]

        if raw_exp_field(fmt, result_raw) == 0 and raw_frac_field(fmt, result_raw) != 0:
            return packed[:6]


def main():
    rng = random.Random(SEED)
    with open("fpu_div_random_cases.mem", "w", encoding="ascii") as mem:
        for fmt_name in ("S", "D"):
            for _rm_name, rm in RMS:
                for idx in range(CASES_PER_RM):
                    fmt_bit, rm_bits, a, b, result, nx = make_case(fmt_name, rm, rng, idx)
                    word = (
                        (fmt_bit << 196) |
                        (rm_bits << 193) |
                        (a << 129) |
                        (b << 65) |
                        (result << 1) |
                        nx
                    )
                    mem.write(f"{word:050x}\n")

    with open("fpu_div_subnormal_cases.mem", "w", encoding="ascii") as mem:
        for fmt_name in ("S", "D"):
            for _rm_name, rm in RMS:
                for _idx in range(SUBNORMAL_CASES_PER_RM):
                    fmt_bit, rm_bits, a, b, result, nx = make_subnormal_result_case(fmt_name, rm, rng)
                    word = (
                        (fmt_bit << 196) |
                        (rm_bits << 193) |
                        (a << 129) |
                        (b << 65) |
                        (result << 1) |
                        nx
                    )
                    mem.write(f"{word:050x}\n")


if __name__ == "__main__":
    main()
