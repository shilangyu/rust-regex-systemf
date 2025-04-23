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

# Week 4

- Implemented top-level unit tests for look-behinds
- Added build errors for engines that do not support lookarounds
- Turned off prefiltering for regexes with lookarounds

# Week 5

- Performed benchmarking via rebar
- Investigated what parts are fuzz-tested
- Wrote draft for the pull request

# Week 6
- Not much done due to sickness
- Wrote benchmarking script for Clément

# Week 7 + 8 (Aurèle away in week 7)
- Extracted regexes with lookbehinds from the Snort ruleset
  - Problem: due to licensing, most likely cannot redistribute,
    which means need very clear instructions on how the dataset
    was extracted so that benchmarks are hopefully reproducible
- Created benchmarks from Snort ruleset and some simple ones for linearity check
  - Performance was very bad, and linearity test showed quadratic behavior
  - Further investigation revealed that engine scanned to end of haystack
    for each match, due to look-behind threads having priority.
  - Changing the benchmark to only contain one match at end of string
    confirmed linear behavior
- Implemented a fix for the quadratic behavior by killing threads from lookbehinds
  once all main threads are gone. After this implementation, the engine was buggy
  - Investigating the cause of the bug revealed an unsoundness in the priorities of
    the lookbehind threads, which originates from an unsound compilation optimization:
    the unanchored prefix for each lookbehind was "factored out" up to this point,
    which causes threads of look-behinds with lower priority to still have higher
    priority than a later instantiation of a higher priority look-behind
  - Trying to prove this unsoundness was the cause for the buggy behavior lead to
    the detection of a more fundamental problem in how a multi match search is
    performed with regards to look-behinds: The entire search state is discarded
    upon a match being found except for the position in the haystack. This means
    that we are effectively starting a completely fresh search at the position
    where the last match ended without any memory of the NFA states, which causes
    the same problems as if prefilters were enabled.
- Finding this bug at the current stage is both good and terrible. Good because
  it saves us from explaining ourselves to the maintainer as we have not opened a PR
  yet, but terrible because it looks as if we now definitely need to rewrite the
  entire look-behind architecture and somehow allow multi-NFA compilation.

# Week 9

- Redesigned nfa setup to have list of starting states for each lb
- Rewrote search procedure to track lb threads seperately
- Added regression tests for the incorrect cases discovered in performance investigations

# Week 10 (easter break)
- Implemented faster matchall by means of storing lb thread states in cache