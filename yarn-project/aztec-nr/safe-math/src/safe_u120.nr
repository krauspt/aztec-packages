use dep::std::cmp::Eq;
use dep::aztec::protocol_types::traits::{Deserialize, Serialize};

struct SafeU120 {
    value: u120,
}

impl Eq for SafeU120 {
    fn eq(
        self: Self,
        other: Self
    ) -> bool {
        self.value == other.value
    }
}

global SAFE_U120_SERIALIZED_LEN: Field = 1;

impl Serialize<SAFE_U120_SERIALIZED_LEN> for SafeU120 {
    fn serialize(value: SafeU120) -> [Field; SAFE_U120_SERIALIZED_LEN] {
        [value.value as Field]
    }
}

impl Deserialize<SAFE_U120_SERIALIZED_LEN> for SafeU120 {
    // This is safe when reading from storage IF only correct safeu120 was written to storage
    fn deserialize(fields: [Field; SAFE_U120_SERIALIZED_LEN]) -> SafeU120 {
        SafeU120 { value: fields[0] as u120 }
    }
}

impl SafeU120 {
    pub fn min() -> Self {
        Self {
            value: 0
        }
    }

    pub fn max() -> Self {
        Self {
            value: 0xffffffffffffffffffffffffffffff
        }
    }

    pub fn new(
        value: Field,
    ) -> Self {
        // Check that it actually will fit. Spending a lot of constraints here :grimacing:
        let bytes = value.to_be_bytes(32);
        for i in 0..17 {
            assert(bytes[i] == 0, "Value too large for SafeU120");
        }
        Self {
            value: value as u120
        }
    }

    pub fn is_zero(
        self: Self,
    ) -> bool {
        self.value == 0
    }

    pub fn lt(self: Self, other: Self) -> bool {
        self.value < other.value
    }

    pub fn le(self: Self, other: Self) -> bool {
        self.value <= other.value
    }

    pub fn gt(self: Self, other: Self) -> bool {
        self.value > other.value
    }

    pub fn ge(self: Self, other: Self) -> bool {
        self.value >= other.value
    }

    pub fn sub(
      self: Self,
      b: Self,
    ) -> Self {
        assert(self.value >= b.value, "Underflow");
        Self {
            value: self.value - b.value
        }
    }

    pub fn add(
        self: Self,
        b: Self,
    ) -> Self {
        let c: u120 = self.value + b.value;
        assert(c >= self.value, "Overflow");
        Self {
            value: c
        }
    }

    pub fn mul(
        self: Self,
        b: Self,
    ) -> Self {
        let c: u120 = self.value * b.value;
        if !b.is_zero() {
            assert(c / b.value == self.value, "Overflow");
        }
        Self {
            value: c
        }
    }

    pub fn div(
        self: Self,
        b: Self,
    ) -> Self {
        assert(!b.is_zero(), "Divide by zero");
        Self {
            value: self.value / b.value
        }
    }

    pub fn mul_div(
        self: Self,
        b: Self,
        divisor: Self
    ) -> Self {
        self.mul(b).div(divisor)
    }

    pub fn mul_div_up(
        self: Self,
        b: Self,
        divisor: Self
    ) -> Self {
        let c = self.mul(b);
        assert(!divisor.is_zero(), "Divide by zero");
        let adder = ((self.value * b.value % divisor.value) as u120 > 0) as u120;
        c.div(divisor).add(Self {value: adder})
    }

    // todo: implement mul_div with 240 bit intermediate values.
}

#[test]
fn test_init() {
    let a = SafeU120::new(1);
    assert(a.value == 1);
}

#[test]
fn test_init_max() {
    let a = SafeU120::max();
    assert(a.value == 0xffffffffffffffffffffffffffffff);
}

#[test]
fn test_init_min() {
    let a = SafeU120::min();
    assert(a.value == 0);
}

#[test]
fn test_is_zero() {
    let a = SafeU120::min();
    assert(a.value == 0);
    assert(a.is_zero() == true);
}

#[test]
fn test_eq() {
    let a = SafeU120::new(1);
    let b = SafeU120::new(1);
    assert(a.eq(b));
}

#[test]
fn test_lt() {
    let a = SafeU120::new(1);
    let b = SafeU120::new(2);
    assert(a.lt(b));
    assert(b.lt(a) == false);
}

#[test]
fn test_le() {
    let a = SafeU120::new(2);
    let b = SafeU120::new(2);
    let c = SafeU120::new(5);
    assert(a.le(b));
    assert(a.le(c));
    assert(c.le(a) == false);
}

#[test]
fn test_gt() {
    let a = SafeU120::new(1);
    let b = SafeU120::new(2);
    assert(b.gt(a));
    assert(a.gt(b) == false);
}

#[test]
fn test_ge() {
    let a = SafeU120::new(2);
    let b = SafeU120::new(2);
    let c = SafeU120::new(5);
    assert(a.ge(b));
    assert(a.ge(c) == false);
    assert(c.ge(a));
}

#[test(should_fail)]
fn test_init_too_large() {
    let b = SafeU120::max().value as Field + 1; // max + 1
    let _a = SafeU120::new(b);
}

#[test]
fn test_add() {
    let a = SafeU120::new(1);
    let b = SafeU120::new(2);
    let c = SafeU120::add(a, b);
    assert(c.value == 3);
}

#[test(should_fail)]
fn test_add_overflow() {
    let a = SafeU120::max();
    let b = SafeU120::new(1);
    let _c = SafeU120::add(a, b);
}

#[test]
fn test_sub() {
    let a = SafeU120::new(2);
    let b = SafeU120::new(1);
    let c = SafeU120::sub(a, b);
    assert(c.value == 1);
}

#[test(should_fail)]
fn test_sub_underflow() {
    let a = SafeU120::new(1);
    let b = SafeU120::new(2);
    let _c = SafeU120::sub(a, b);
}

#[test]
fn test_mul() {
    let a = SafeU120::new(2);
    let b = SafeU120::new(3);
    let c = SafeU120::mul(a, b);
    assert(c.value == 6);
}

#[test(should_fail)]
fn test_mul_overflow() {
    let a = SafeU120::max();
    let b = SafeU120::new(2);
    let _c = SafeU120::mul(a, b);
}

#[test]
fn test_div() {
    let a = SafeU120::new(6);
    let b = SafeU120::new(3);
    let c = SafeU120::div(a, b);
    assert(c.value == 2);
}

#[test(should_fail)]
fn test_div_by_zero() {
    let a = SafeU120::new(6);
    let b = SafeU120::new(0);
    let _c = SafeU120::div(a, b);
}

#[test]
fn test_mul_div() {
    let a = SafeU120::new(6);
    let b = SafeU120::new(3);
    let c = SafeU120::new(2);
    let d = SafeU120::mul_div(a, b, c);
    assert(d.value == 9);
}

#[test(should_fail)]
fn test_mul_div_zero_divisor() {
    let a = SafeU120::new(6);
    let b = SafeU120::new(3);
    let c = SafeU120::new(0);
    let _d = SafeU120::mul_div(a, b, c);
}

#[test(should_fail)]
fn test_mul_div_ghost_overflow() {
    let a = SafeU120::max();
    let b = SafeU120::new(2);
    let c = SafeU120::new(4);
    let _d = SafeU120::mul_div(a, b, c);
}

#[test]
fn test_mul_div_up_rounding() {
    let a = SafeU120::new(6);
    let b = SafeU120::new(3);
    let c = SafeU120::new(5);
    let d = SafeU120::mul_div_up(a, b, c);
    assert(d.value == 4);
}

#[test]
fn test_mul_div_up_non_rounding() {
    let a = SafeU120::new(6);
    let b = SafeU120::new(3);
    let c = SafeU120::new(2);
    let d = SafeU120::mul_div_up(a, b, c);
    assert(d.value == 9);
}

#[test(should_fail)]
fn test_mul_div_up_ghost_overflow() {
    let a = SafeU120::max();
    let b = SafeU120::new(2);
    let c = SafeU120::new(9);
    let _d = SafeU120::mul_div_up(a, b, c);
}

// It should not be possible for us to overflow `mul_div_up` through the adder, since that require the divisor to be 1
// since we otherwise would not be at the max value. If divisor is 1, adder is 0.
#[test(should_fail)]
fn test_mul_div_up_zero_divisor() {
    let a = SafeU120::new(6);
    let b = SafeU120::new(3);
    let c = SafeU120::new(0);
    let _d = SafeU120::mul_div_up(a, b, c);
}
