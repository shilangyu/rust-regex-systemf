[Github](https://github.com/fancy-regex/fancy-regex/blob/main/Cargo.toml)

This crate implements a hybrid approach that supports "fancy" regex features using an unbounded backtracking engine but internally delegates as much as possible to the NFA engines from the [[regex crate]].

This means we would get the linear time lookaround benefits for both crates if we implement it in `regex` and then only contribute a change to the delegation decision in `fancy-regex`
