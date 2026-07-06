from fractions import Fraction
from math import isqrt

RMS = [0, 1, 2, 3, 4]

OP_FMADD = 0
OP_FMSUB = 1
OP_FNMSUB = 2
OP_FNMADD = 3

FORMATS = {
    "S": {
        "fmt_bit": 0,
        "p": 24,
        "exp_bits": 8,
        "frac_bits": 23,
        "bias": 127,
        "emin": -126,
        "emax": 127,
        "width": 32,
        "qnan": 0x7FC0_0000,
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
        "width": 64,
        "qnan": 0x7FF8_0000_0000_0000,
        "pack": lambda x: x,
    },
}


def shl_frac(value, shift):
    return value * (1 << shift) if shift >= 0 else value / (1 << -shift)


def raw_sign(fmt, bits):
    return (bits >> (fmt["width"] - 1)) & 1


def raw_exp(fmt, bits):
    return (bits >> fmt["frac_bits"]) & ((1 << fmt["exp_bits"]) - 1)


def raw_frac(fmt, bits):
    return bits & ((1 << fmt["frac_bits"]) - 1)


def is_nan(fmt, bits):
    return raw_exp(fmt, bits) == ((1 << fmt["exp_bits"]) - 1) and raw_frac(fmt, bits) != 0


def is_snan(fmt, bits):
    return is_nan(fmt, bits) and ((raw_frac(fmt, bits) >> (fmt["frac_bits"] - 1)) & 1) == 0


def is_inf(fmt, bits):
    return raw_exp(fmt, bits) == ((1 << fmt["exp_bits"]) - 1) and raw_frac(fmt, bits) == 0


def is_zero(fmt, bits):
    return (bits & ((1 << (fmt["width"] - 1)) - 1)) == 0


def is_finite(fmt, bits):
    return raw_exp(fmt, bits) != ((1 << fmt["exp_bits"]) - 1)


def canonical_nan(fmt):
    return fmt["pack"](fmt["qnan"])


def pack_raw(fmt, raw):
    return fmt["pack"](raw)


def pack_inf(fmt, sign):
    exp_mask = (1 << fmt["exp_bits"]) - 1
    return pack_raw(fmt, (sign << (fmt["width"] - 1)) | (exp_mask << fmt["frac_bits"]))


def pack_zero(fmt, sign):
    return pack_raw(fmt, sign << (fmt["width"] - 1))


def pack_max_finite(fmt, sign):
    exp_field = (1 << fmt["exp_bits"]) - 2
    frac = (1 << fmt["frac_bits"]) - 1
    return pack_raw(fmt, (sign << (fmt["width"] - 1)) | (exp_field << fmt["frac_bits"]) | frac)


def overflow_result(fmt, sign, rm):
    to_inf = rm in (0, 4) or (rm == 3 and not sign) or (rm == 2 and sign)
    return pack_inf(fmt, sign) if to_inf else pack_max_finite(fmt, sign)


def decode_finite(fmt, bits):
    sign = raw_sign(fmt, bits)
    exp_field = raw_exp(fmt, bits)
    frac = raw_frac(fmt, bits)
    if exp_field == 0:
        mant = frac
        exp = fmt["emin"]
    else:
        mant = (1 << fmt["frac_bits"]) | frac
        exp = exp_field - fmt["bias"]
    return sign, shl_frac(Fraction(mant, 1), exp - fmt["frac_bits"])


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
        inc = twice_r > value.denominator or (twice_r == value.denominator and (q & 1) != 0)
    elif rm == 2:
        inc = bool(sign)
    elif rm == 3:
        inc = not bool(sign)
    elif rm == 4:
        inc = twice_r >= value.denominator
    return q + (1 if inc else 0), True


def encode_finite(fmt, sign, value, rm):
    if value == 0:
        return pack_zero(fmt, sign), 0
    value = abs(value)
    p = fmt["p"]
    frac_bits = fmt["frac_bits"]
    frac_mask = (1 << frac_bits) - 1
    exp = floor_log2(value)
    if exp < fmt["emin"]:
        scaled = shl_frac(value, (p - 1) - fmt["emin"])
        sig, inexact = round_int(scaled, rm, sign)
        if sig == 0:
            return pack_zero(fmt, sign), 0x03 if inexact else 0
        if sig >= (1 << (p - 1)):
            raw = (1 << frac_bits)
        else:
            raw = sig & frac_mask
        flags = 0x01 if inexact else 0
        if inexact:
            flags |= 0x02
        return pack_raw(fmt, (sign << (fmt["width"] - 1)) | raw), flags
    scaled = shl_frac(value, (p - 1) - exp)
    sig, inexact = round_int(scaled, rm, sign)
    if sig >= (1 << p):
        sig >>= 1
        exp += 1
    if exp > fmt["emax"]:
        return overflow_result(fmt, sign, rm), 0x05
    exp_field = exp + fmt["bias"]
    if exp_field >= ((1 << fmt["exp_bits"]) - 1):
        return overflow_result(fmt, sign, rm), 0x05
    raw = (sign << (fmt["width"] - 1)) | (exp_field << frac_bits) | ((sig - (1 << (p - 1))) & frac_mask)
    return pack_raw(fmt, raw), 0x01 if inexact else 0


def expected_mul(fmt, rm, a, b):
    sign = raw_sign(fmt, a) ^ raw_sign(fmt, b)
    if is_nan(fmt, a) or is_nan(fmt, b):
        return canonical_nan(fmt), 0x10 if is_snan(fmt, a) or is_snan(fmt, b) else 0
    if (is_inf(fmt, a) and is_zero(fmt, b)) or (is_zero(fmt, a) and is_inf(fmt, b)):
        return canonical_nan(fmt), 0x10
    if is_inf(fmt, a) or is_inf(fmt, b):
        return pack_inf(fmt, sign), 0
    if is_zero(fmt, a) or is_zero(fmt, b):
        return pack_zero(fmt, sign), 0
    _sa, va = decode_finite(fmt, a)
    _sb, vb = decode_finite(fmt, b)
    return encode_finite(fmt, sign, va * vb, rm)


def expected_div(fmt, rm, a, b):
    sign = raw_sign(fmt, a) ^ raw_sign(fmt, b)
    if is_nan(fmt, a) or is_nan(fmt, b):
        return canonical_nan(fmt), 0x10 if is_snan(fmt, a) or is_snan(fmt, b) else 0
    if (is_zero(fmt, a) and is_zero(fmt, b)) or (is_inf(fmt, a) and is_inf(fmt, b)):
        return canonical_nan(fmt), 0x10
    if is_inf(fmt, a) or is_zero(fmt, b):
        return pack_inf(fmt, sign), 0x08 if is_zero(fmt, b) and not is_zero(fmt, a) else 0
    if is_zero(fmt, a) or is_inf(fmt, b):
        return pack_zero(fmt, sign), 0
    _sa, va = decode_finite(fmt, a)
    _sb, vb = decode_finite(fmt, b)
    return encode_finite(fmt, sign, va / vb, rm)


def pow2_frac(exp):
    return Fraction(1 << exp, 1) if exp >= 0 else Fraction(1, 1 << -exp)


def floor_log2_sqrt(value):
    exp = floor_log2(value) // 2
    while pow2_frac(2 * (exp + 1)) <= value:
        exp += 1
    while pow2_frac(2 * exp) > value:
        exp -= 1
    return exp


def floor_sqrt_scaled(value, scale_exp):
    if scale_exp >= 0:
        q, r = divmod(value.numerator << (2 * scale_exp), value.denominator)
    else:
        den = value.denominator << (-2 * scale_exp)
        q, r = divmod(value.numerator, den)
    root = isqrt(q)
    return root, (root * root == q) and (r == 0)


def round_sqrt_scaled(value, scale_exp, rm):
    floor_val, exact = floor_sqrt_scaled(value, scale_exp)
    if exact:
        return floor_val, False
    inc = False
    if rm in (0, 4):
        lhs = value * pow2_frac(2 * scale_exp)
        mid = Fraction((2 * floor_val + 1) * (2 * floor_val + 1), 4)
        inc = lhs > mid or (rm == 4 and lhs == mid) or (rm == 0 and lhs == mid and (floor_val & 1))
    elif rm == 3:
        inc = True
    return floor_val + (1 if inc else 0), True


def expected_sqrt(fmt, rm, a):
    if is_nan(fmt, a):
        return canonical_nan(fmt), 0x10 if is_snan(fmt, a) else 0
    sign = raw_sign(fmt, a)
    if sign and not is_zero(fmt, a):
        return canonical_nan(fmt), 0x10
    if is_inf(fmt, a) or is_zero(fmt, a):
        return pack_raw(fmt, a), 0
    _sign, value = decode_finite(fmt, a)
    exp = floor_log2_sqrt(value)
    if exp < fmt["emin"]:
        sig, inexact = round_sqrt_scaled(value, (fmt["p"] - 1) - fmt["emin"], rm)
        raw = 0 if sig == 0 else ((1 << fmt["frac_bits"]) if sig >= (1 << (fmt["p"] - 1)) else sig)
        flags = 0x01 if inexact else 0
        if inexact and raw < (1 << fmt["frac_bits"]):
            flags |= 0x02
        return pack_raw(fmt, raw), flags
    sig, inexact = round_sqrt_scaled(value, (fmt["p"] - 1) - exp, rm)
    if sig >= (1 << fmt["p"]):
        sig >>= 1
        exp += 1
    raw = ((exp + fmt["bias"]) << fmt["frac_bits"]) | ((sig - (1 << (fmt["p"] - 1))) & ((1 << fmt["frac_bits"]) - 1))
    return pack_raw(fmt, raw), 0x01 if inexact else 0


def fma_signs(op, a, b, c, fmt):
    neg_prod = op in (OP_FNMSUB, OP_FNMADD)
    neg_add = op in (OP_FMSUB, OP_FNMADD)
    prod_sign = raw_sign(fmt, a) ^ raw_sign(fmt, b) ^ int(neg_prod)
    add_sign = raw_sign(fmt, c) ^ int(neg_add)
    return prod_sign, add_sign


def expected_fma(fmt, rm, op, a, b, c):
    prod_sign, add_sign = fma_signs(op, a, b, c, fmt)
    invalid_mul = (is_inf(fmt, a) and is_zero(fmt, b)) or (is_zero(fmt, a) and is_inf(fmt, b))
    product_is_inf = is_inf(fmt, a) or is_inf(fmt, b)
    invalid_inf_add = product_is_inf and is_inf(fmt, c) and (prod_sign != add_sign)
    if is_nan(fmt, a) or is_nan(fmt, b) or is_nan(fmt, c) or invalid_mul or invalid_inf_add:
        nv = is_snan(fmt, a) or is_snan(fmt, b) or is_snan(fmt, c) or invalid_mul or invalid_inf_add
        return canonical_nan(fmt), 0x10 if nv else 0
    if product_is_inf:
        return pack_inf(fmt, prod_sign), 0
    if is_inf(fmt, c):
        return pack_inf(fmt, add_sign), 0
    sa, va = decode_finite(fmt, a)
    sb, vb = decode_finite(fmt, b)
    sc, vc = decode_finite(fmt, c)
    prod = va * vb
    add = vc
    if prod_sign:
        prod = -prod
    if add_sign:
        add = -add
    value = prod + add
    if value == 0:
        sign = prod_sign if prod_sign == add_sign else (1 if rm == 2 else 0)
    else:
        sign = 1 if value < 0 else 0
    return encode_finite(fmt, sign, abs(value), rm)


def make_qnan(fmt, rng):
    frac = (1 << (fmt["frac_bits"] - 1)) | (rng.getrandbits(fmt["frac_bits"] - 1) or 1)
    return (((1 << fmt["exp_bits"]) - 1) << fmt["frac_bits"]) | frac | (rng.getrandbits(1) << (fmt["width"] - 1))


def make_snan(fmt, rng):
    frac = rng.getrandbits(fmt["frac_bits"] - 1) or 1
    return (((1 << fmt["exp_bits"]) - 1) << fmt["frac_bits"]) | frac | (rng.getrandbits(1) << (fmt["width"] - 1))


def make_inf(fmt, sign):
    return (sign << (fmt["width"] - 1)) | (((1 << fmt["exp_bits"]) - 1) << fmt["frac_bits"])


def make_zero(fmt, sign):
    return sign << (fmt["width"] - 1)


def make_subnormal(fmt, rng, sign=None):
    if sign is None:
        sign = rng.getrandbits(1)
    return (sign << (fmt["width"] - 1)) | (rng.getrandbits(fmt["frac_bits"]) or 1)


def make_normal(fmt, rng, sign=None):
    if sign is None:
        sign = rng.getrandbits(1)
    exp = rng.randint(1, (1 << fmt["exp_bits"]) - 2)
    return (sign << (fmt["width"] - 1)) | (exp << fmt["frac_bits"]) | rng.getrandbits(fmt["frac_bits"])


def value_pool(fmt, rng):
    return [
        make_qnan(fmt, rng),
        make_snan(fmt, rng),
        make_inf(fmt, 0),
        make_inf(fmt, 1),
        make_zero(fmt, 0),
        make_zero(fmt, 1),
        make_subnormal(fmt, rng, 0),
        make_subnormal(fmt, rng, 1),
        make_normal(fmt, rng, 0),
        make_normal(fmt, rng, 1),
    ]


def mixed_operands(fmt, rng, nops):
    pool = value_pool(fmt, rng)
    return [pool[rng.randrange(len(pool))] for _ in range(nops)]
