#!/usr/bin/env python3

import random
from fractions import Fraction
from fpu_random_case_utils import (
    FORMATS,
    RMS,
    decode_finite,
    encode_finite,
    expected_div,
    pack_raw,
    mixed_operands,
    make_subnormal,
    make_normal,
)

CASES_PER_FMT_RM = 1000
EXACT_CASES_PER_FMT_RM = 256
SEED = 0x46505544


def raw_mask(fmt):
    return (1 << fmt["width"]) - 1


def sign_mask(fmt):
    return 1 << (fmt["width"] - 1)


def shl_frac(value, shift):
    return value * (1 << shift) if shift >= 0 else value / (1 << -shift)


def raw_from_exact(fmt, value):
    packed, flags = encode_finite(fmt, 0, value, 0)
    if flags != 0:
        return None
    raw = packed & raw_mask(fmt)
    if decode_finite(fmt, raw)[1] != value:
        return None
    return raw


def set_raw_sign(fmt, raw, sign):
    return (raw & ~sign_mask(fmt)) | (sign << (fmt["width"] - 1))


def candidate_exact_values(fmt, rng):
    values = []
    exp_limit = 40 if fmt["width"] == 32 else 320
    directed_mants = [
        Fraction(1, 1),
        Fraction(5, 4),
        Fraction(3, 2),
        Fraction(7, 4),
        Fraction(2, 1),
        Fraction(3, 1),
        Fraction(5, 1),
        Fraction(7, 1),
        Fraction(9, 1),
        Fraction(17, 1),
        Fraction(31, 1),
    ]

    for exp in range(-exp_limit, exp_limit + 1, max(1, exp_limit // 16)):
        for mant in directed_mants:
            values.append(shl_frac(mant, exp))

    for _ in range(4 * EXACT_CASES_PER_FMT_RM):
        exp = rng.randint(-exp_limit, exp_limit)
        denom_shift = rng.randint(0, min(10, fmt["p"] - 1))
        numer = rng.randint(1, 1 << min(12, fmt["p"] - 1))
        values.append(shl_frac(Fraction(numer, 1 << denom_shift), exp))

    exact_values = []
    seen = set()
    for value in values:
        raw = raw_from_exact(fmt, value)
        if raw is None or raw in seen:
            continue
        seen.add(raw)
        exact_values.append((raw, value))
    return exact_values


def exact_div_operands(fmt, rng, count):
    values = candidate_exact_values(fmt, rng)
    cases = []
    seen = set()

    directed_q = [value for _raw, value in values if value in (
        Fraction(1, 1), Fraction(2, 1), Fraction(3, 1),
        Fraction(5, 1), Fraction(7, 1), Fraction(17, 1),
    )]
    q_values = directed_q + [value for _raw, value in values]

    for q_value in q_values:
        for b_raw, b_value in values:
            product = q_value * b_value
            a_raw = raw_from_exact(fmt, product)
            q_raw = raw_from_exact(fmt, q_value)
            if a_raw is None or q_raw is None:
                continue
            sign_a = rng.getrandbits(1)
            sign_b = rng.getrandbits(1)
            a_signed = set_raw_sign(fmt, a_raw, sign_a)
            b_signed = set_raw_sign(fmt, b_raw, sign_b)
            key = (a_signed, b_signed)
            if key in seen:
                continue
            seen.add(key)
            cases.append((a_signed, b_signed))
            if len(cases) >= count:
                return cases

    raise RuntimeError(f"only generated {len(cases)} exact div cases")


def make_operands(fmt, rng, idx):
    if idx % 5 == 0:
        return make_subnormal(fmt, rng, 0), make_normal(fmt, rng, 0)
    if idx % 5 == 1:
        return make_normal(fmt, rng, 0), make_subnormal(fmt, rng, 0)
    while True:
        a, b = mixed_operands(fmt, rng, 2)
        if a != b:
            return a, b


def main():
    rng = random.Random(SEED)
    count = 0
    with open("fpu_div_random_cases.mem", "w", encoding="ascii") as mem:
        for fmt_name in ("S", "D"):
            fmt = FORMATS[fmt_name]
            for rm in RMS:
                for idx in range(CASES_PER_FMT_RM):
                    a, b = make_operands(fmt, rng, idx)
                    result, flags = expected_div(fmt, rm, a, b)
                    word = (
                        (fmt["fmt_bit"] << 201) |
                        (rm << 198) |
                        (pack_raw(fmt, a) << 134) |
                        (pack_raw(fmt, b) << 70) |
                        (result << 6) |
                        (flags << 1) |
                        1
                    )
                    mem.write(f"{word:051x}\n")
                    count += 1
                for a, b in exact_div_operands(fmt, rng, EXACT_CASES_PER_FMT_RM):
                    result, flags = expected_div(fmt, rm, a, b)
                    word = (
                        (fmt["fmt_bit"] << 201) |
                        (rm << 198) |
                        (pack_raw(fmt, a) << 134) |
                        (pack_raw(fmt, b) << 70) |
                        (result << 6) |
                        (flags << 1) |
                        1
                    )
                    mem.write(f"{word:051x}\n")
                    count += 1
    print(f"wrote fpu_div_random_cases.mem cases={count}")


if __name__ == "__main__":
    main()
