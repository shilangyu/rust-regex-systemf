[Github](https://github.com/rust-lang/regex)

[Author's blog post](https://burntsushi.net/regex-internals/)

The regex crate is now split into regex-automata and regex-syntax, both of which will need contributions for lookaround implementations.

The main Meta-Engine in the regex crate combines all different engines and chooses the fastest one based on used features in the regex and heuristics when running the engine.
It uses the following priority:

- none if substring search is sufficient
- extract prefix literal sequence and use this to minimize the search locations
- try to do a "reverse optimization":
  - anchored search from end (when $ used)
  - suffix literal sequence
  - literal sequence that partitions regex -> use to find match candidates and perform forward and backward searches
- use full-DFA if available and possible to find bounds of match
- use lazy-DFA if possible to find bounds of match
- use one-pass DFA, bounded backtracker, pikeVM in this order as fallback or to get capture groups after one of the other succeeded to find bounds of match

PikeVM should be fully compatible with the lookaround implementation from [[Linear Matching of JavaScript Regexs]]. It is to be determined if it can also be implemented for the bounded backtracker and one-pass DFA. Furthermore, the lazy and full DFA will also need to be checked, at least for capture-less lookarounds, since they provide the initial match candidates.

The semantics of the regexes try to follow Perl semantics.

Some regex engines allow for manual state transition control. This means we can start and pause them. This can be beneficial for running the captureless lookbehind automaton using the lazyDFA engine in lockstep.
