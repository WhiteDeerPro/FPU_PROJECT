#!/usr/bin/env python3

import random
from fractions import Fraction
from fpu_random_case_utils import (
    FORMATS,
    RMS,
    decode_finite,
    encode_finite,
    expected_sqrt,
    pack_raw,
    value_pool,
    make_subnormal,
    make_normal,
)

CASES_PER_CLASS = 200
PERFECT_SQUARE_CASES_PER_FMT_RM = 256
SEED = 0x53515254


def raw_mask(fmt):
    return (1 << fmt["width"]) - 1


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


def root_candidates(fmt, rng):
    exp_limit = 60 if fmt["width"] == 32 else 500
    bases = [
        Fraction(1, 1),
        Fraction(9, 8),
        Fraction(5, 4),
        Fraction(11, 8),
        Fraction(3, 2),
        Fraction(13, 8),
        Fraction(7, 4),
        Fraction(15, 8),
    ]
    values = []

    for exp in range(-exp_limit, exp_limit + 1, max(1, exp_limit // 20)):
        for base in bases:
            values.append(shl_frac(base, exp))

    for _ in range(8 * PERFECT_SQUARE_CASES_PER_FMT_RM):
        exp = rng.randint(-exp_limit, exp_limit)
        denom_shift = rng.randint(0, 8)
        numer = rng.randint(1 << denom_shift, (2 << denom_shift) - 1)
        values.append(shl_frac(Fraction(numer, 1 << denom_shift), exp))

    exact_roots = []
    seen = set()
    for value in values:
        raw = raw_from_exact(fmt, value)
        if raw is None or raw in seen:
            continue
        seen.add(raw)
        exact_roots.append((raw, value))
    return exact_roots


def perfect_square_cases(fmt, rng, count):
    cases = []
    seen = set()
    for root_raw, root_value in root_candidates(fmt, rng):
        square_raw = raw_from_exact(fmt, root_value * root_value)
        if square_raw is None or square_raw in seen:
            continue
        result, flags = expected_sqrt(fmt, 0, square_raw)
        if result != pack_raw(fmt, root_raw) or flags != 0:
            continue
        seen.add(square_raw)
        cases.append(square_raw)
        if len(cases) >= count:
            return cases

    raise RuntimeError(f"only generated {len(cases)} perfect-square sqrt cases")


def raw_cases(fmt, rng):
    cases = value_pool(fmt, rng)
    directed_subs = [1, 2, 3, (1 << (fmt["frac_bits"] - 1)), (1 << fmt["frac_bits"]) - 1]
    sign_shift = fmt["width"] - 1
    for frac in directed_subs:
        cases.append(frac)
        cases.append((1 << sign_shift) | frac)
    for _ in range(CASES_PER_CLASS):
        cases.extend([
            make_subnormal(fmt, rng, 0),
            make_subnormal(fmt, rng, 1),
            make_normal(fmt, rng, 0),
            make_normal(fmt, rng, 1),
        ])
    return cases


def main():
    rng = random.Random(SEED)
    count = 0
    with open("fpu_sqrt_random_cases.mem", "w", encoding="ascii") as mem:
        for fmt_name in ("S", "D"):
            fmt = FORMATS[fmt_name]
            cases = raw_cases(fmt, rng)
            for rm in RMS:
                for raw in cases:
                    result, flags = expected_sqrt(fmt, rm, raw)
                    word = (
                        (fmt["fmt_bit"] << 137) |
                        (rm << 134) |
                        (pack_raw(fmt, raw) << 70) |
                        (result << 6) |
                        (flags << 1) |
                        1
                    )
                    mem.write(f"{word:035x}\n")
                    count += 1
                for raw in perfect_square_cases(fmt, rng, PERFECT_SQUARE_CASES_PER_FMT_RM):
                    result, flags = expected_sqrt(fmt, rm, raw)
                    word = (
                        (fmt["fmt_bit"] << 137) |
                        (rm << 134) |
                        (pack_raw(fmt, raw) << 70) |
                        (result << 6) |
                        (flags << 1) |
                        1
                    )
                    mem.write(f"{word:035x}\n")
                    count += 1
    print(f"wrote fpu_sqrt_random_cases.mem cases={count}")


if __name__ == "__main__":
    main()
