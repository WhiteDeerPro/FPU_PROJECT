#!/usr/bin/env python3

import random
from fpu_random_case_utils import FORMATS, RMS, expected_mul, pack_raw, mixed_operands

CASES_PER_FMT_RM = 1000
SEED = 0x4D554C54


def main():
    rng = random.Random(SEED)
    count = 0
    with open("fpu_mult_random_cases.mem", "w", encoding="ascii") as mem:
        for fmt_name in ("S", "D"):
            fmt = FORMATS[fmt_name]
            for rm in RMS:
                for _idx in range(CASES_PER_FMT_RM):
                    a, b = mixed_operands(fmt, rng, 2)
                    result, flags = expected_mul(fmt, rm, a, b)
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
    print(f"wrote fpu_mult_random_cases.mem cases={count}")


if __name__ == "__main__":
    main()
