#!/usr/bin/env python3

import random
from fpu_random_case_utils import FORMATS, RMS, expected_sqrt, pack_raw, value_pool, make_subnormal, make_normal

CASES_PER_CLASS = 200
SEED = 0x53515254


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
    print(f"wrote fpu_sqrt_random_cases.mem cases={count}")


if __name__ == "__main__":
    main()
