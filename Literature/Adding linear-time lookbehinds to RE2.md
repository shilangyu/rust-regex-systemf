[Article](https://systemf.epfl.ch/blog/re2-lookbehinds/)

RE2 has the following engines: DFA, OnePass, BitState, NFA.
These should match the Lazy-DFA, onepass-DFA, bounded backtracker, pikeVM from [[regex crate]]

The article mentions the following required changes:
- parser must support lookbehind syntax
- compiler must generate automatons for lookbehinds
- NFA must keep table for lookbehind state and run the separate automatons with correct precedence
- choice of engine must fall back to NFA for regexes including lookbehinds (only for this engine, the necessary changes were implemented. The future work section at the end mentions that implementation for other engines must be explored.)
- add tests with lookbehinds