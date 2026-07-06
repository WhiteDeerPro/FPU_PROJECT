#!/usr/bin/env python3

import random
from fpu_random_case_utils import (
    FORMATS,
    RMS,
    expected_div,
    pack_raw,
    mixed_operands,
    make_subnormal,
    make_normal,
)

CASES_PER_FMT_RM = 1000
SEED = 0x46505544


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
    print(f"wrote fpu_div_random_cases.mem cases={count}")


if __name__ == "__main__":
    main()
