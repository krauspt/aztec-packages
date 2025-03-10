
// TODO: Once we fully move to the new SSA pass this module can be removed and replaced
// by the methods in the `slice` module
impl<T, N> [T; N] {
    #[builtin(array_len)]
    pub fn len(self) -> Field {}

    #[builtin(arraysort)]
    pub fn sort(self) -> Self {}

    // Sort with a custom sorting function.
    pub fn sort_via<Env>(mut a: Self, ordering: fn[Env](T, T) -> bool) -> Self { 
        for i in 1 .. a.len() {
            for j in 0..i {
                if ordering(a[i], a[j]) {
                    let old_a_j = a[j];
                    a[j] = a[i];
                    a[i] = old_a_j;
                }
            }
        }
        a
    }

    // Converts an array into a slice.
    pub fn as_slice(self) -> [T] {
        let mut slice = [];
        for elem in self {
            slice = slice.push_back(elem);
        }
        slice
    }

    // Apply a function to each element of an array, returning a new array
    // containing the mapped elements.
    pub fn map<U, Env>(self, f: fn[Env](T) -> U) -> [U; N] {
        let first_elem = f(self[0]);
        let mut ret = [first_elem; N];

        for i in 1 .. self.len() {
            ret[i] = f(self[i]);
        }

        ret
    }

    // Apply a function to each element of the array and an accumulator value,
    // returning the final accumulated value. This function is also sometimes
    // called `foldl`, `fold_left`, `reduce`, or `inject`.
    pub fn fold<U, Env>(self, mut accumulator: U, f: fn[Env](U, T) -> U) -> U {
        for elem in self {
            accumulator = f(accumulator, elem);
        }
        accumulator
    }

    // Apply a function to each element of the array and an accumulator value,
    // returning the final accumulated value. Unlike fold, reduce uses the first
    // element of the given array as its starting accumulator value.
    pub fn reduce<Env>(self, f: fn[Env](T, T) -> T) -> T {
        let mut accumulator = self[0];
        for i in 1 .. self.len() {
            accumulator = f(accumulator, self[i]);
        }
        accumulator
    }

    // Returns true if all elements in the array satisfy the predicate
    pub fn all<Env>(self, predicate: fn[Env](T) -> bool) -> bool {
        let mut ret = true;
        for elem in self {
            ret &= predicate(elem);
        }
        ret
    }

    // Returns true if any element in the array satisfies the predicate
    pub fn any<Env>(self, predicate: fn[Env](T) -> bool) -> bool {
        let mut ret = false;
        for elem in self {
            ret |= predicate(elem);
        }
        ret
    }
}
