# Week 1

- Read background literature and summarized it in the `Literature` folder
- Setup project tooling and did some investigation in the `regex` crate

# Week 2

- Created a fork for the rust-lang/regex crate
- Decided on a first variant of extending the HIR to support lookarounds
- Implemented said variant
- Inspected relevant code for determining the implementation plan and started
  writing the plan

# Week 3

- Refactored the HIR extension to be more straightforward
- Extended NFA with instructions to read and write the lookaround oracle
- Implemented compilation from HIR to NFA
- Implemented execution of new instructions
- Made compilation of lookaround machinery conditional on whether or not the
  expression contains lookarounds
