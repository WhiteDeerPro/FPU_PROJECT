#!/usr/bin/env python3

import random
from fpu_random_case_utils import (
    FORMATS,
    RMS,
    OP_FMADD,
    OP_FMSUB,
    OP_FNMSUB,
    OP_FNMADD,
    expected_fma,
    pack_raw,
    mixed_operands,
    make_subnormal,
    make_normal,
)

CASES_PER_FMT_RM_OP = 250
SEED = 0x464D4152
OPS = [OP_FMADD, OP_FMSUB, OP_FNMSUB, OP_FNMADD]


def make_operands(fmt, rng, idx):
    if idx % 5 == 0:
        return make_subnormal(fmt, rng, 0), make_normal(fmt, rng, 0), make_subnormal(fmt, rng, 1)
    if idx % 5 == 1:
        return make_normal(fmt, rng, 1), make_subnormal(fmt, rng, 0), make_normal(fmt, rng, 0)
    return mixed_operands(fmt, rng, 3)


def main():
    rng = random.Random(SEED)
    count = 0
    with open("fpu_fma_random_cases.mem", "w", encoding="ascii") as mem:
        for fmt_name in ("S", "D"):
            fmt = FORMATS[fmt_name]
            for rm in RMS:
                for op in OPS:
                    for idx in range(CASES_PER_FMT_RM_OP):
                        a, b, c = make_operands(fmt, rng, idx)
                        result, flags = expected_fma(fmt, rm, op, a, b, c)
                        word = (
                            (fmt["fmt_bit"] << 267) |
                            (op << 265) |
                            (rm << 262) |
                            (pack_raw(fmt, a) << 198) |
                            (pack_raw(fmt, b) << 134) |
                            (pack_raw(fmt, c) << 70) |
                            (result << 6) |
                            (flags << 1) |
                            1
                        )
                        mem.write(f"{word:067x}\n")
                        count += 1
    print(f"wrote fpu_fma_random_cases.mem cases={count}")


if __name__ == "__main__":
    main()
