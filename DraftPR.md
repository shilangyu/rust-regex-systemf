# Implement look-behind assertions

## What

This PR implements a streaming algorithm for supporting look-behind assertions
in the regex crate. The algorithm supports arbitrarily nested look-behinds and
all features of regex expressions supported by the crate are usable within
look-behind expressions, with the exception of capture groups.

The algorithm is implemented in the PikeVM and the necessary changes in
`regex-syntax` and the other engines to use look-behind expressions from the
`regex` crate are included.

This PR is a MVP for adding support for general look-around assertions. The
implementation of look-_ahead_ assertions is not included, and doing so will
require the discussion of a space-time trade-off, as supporting look-ahead
expressions is not possible in the same streaming fashion as for look-behinds.
Furthermore, supporting capture groups within look-around expressions will
require different capture semantics than the ones currently used when matching
regexes and might hence not be desirable to implement. Finally, the backtracking
engine, in theory, supports look-arounds, but it is unclear how to best
integrate our current implementation, focused on the PikeVM, into the
bounded backtracker.

The addition of look-around expressions to this crate was mentioned previously
in the following discussion post: [#1153](https://github.com/rust-lang/regex/discussions/1153).

## Why

General look-around assertions are a powerful extension to the features of a
regex engine. The reason they were not supported up to this point is that it
was long thought that they could not be implemented in a way that respects the
runtime complexity guarantees of the regex crate (linear in the length of the
pattern and the haystack).

Theoretical work by Aurèle Barrière and Clément Pit-Claudel has shown that this
assumption is incorrect and that look-around assertions can in fact be
implemented in linear time. In their work [Linear Matching of JavaScript Regular Expressions](https://aurele-barriere.github.io/papers/linearjs.pdf)
they demonstrate how to do so for the semantics of JavaScript regexes.

As the regex crate is the de-facto standard for regex matching in Rust, it is
desirable to support look-around assertions in this crate as well, which is
why we propose this PR.

## How

We implemented the streaming algorithm presented in Section 4.4 of the paper
mentioned above. The algorithm works by running the sub-automata for any
look-behind assertions in parallel to the main automaton. This is achieved by
compiling the look-behind assertions regularly but patching the resulting NFA
states into a union with the main automaton's states. The union is added per
pattern for multi-pattern searches.

Instead of a `match` state, the sub-automata for look-behinds have a
`WriteLookAround` state. This state causes the current position in the haystack
to be recorded in a global look-around table.

The main automaton (and the sub-automata in the case of nested look-behinds) can
then read from this table by means of a `CheckLookAround` instruction and
compare the stored index with the current position in the haystack. These states
work as conditional epsilon transitions, similar to the already supported
simple lookaround assertions.

## Testing

We have added unit tests for the new functionality in the individual test
modules to test the new parsing, translation and compilation features. We have
further added integration tests in the form of a new toml file. All engines
apart from the PikeVM will fail to build when look-behind assertions are present
in the pattern. This fact was used to filter out the tests containing
look-behinds for engines other than the PikeVM and Meta engine.

## Performance

We forked the `rebar` repository and copied the engine definitions for the
`regex` crate and called the new definition `regex-lookbehind`. We added this
new engine definition to all benchmarks where `rust/regex` is already present.

The result of running the full benchmark suite is included in the latest commit
of the forked repository at `record/look-behind/all.csv`. The results show that
no significant performance regression is introduced by the new implementation.

The table below shows the output of `rebar cmp -t 1.1 all.csv`.

| benchmark                                              | rust/regex          | rust/regex-lookbehind |
| ------------------------------------------------------ | ------------------- | --------------------- |
| curated/01-literal/sherlock-ru                         | 36.7 GB/s (1.00x)   | 32.7 GB/s (1.12x)     |
| curated/08-words/long-russian                          | 23.6 MB/s (1.15x)   | 27.1 MB/s (1.00x)     |
| folly/literal-never-match-frequent                     | 52.6 GB/s (1.00x)   | 45.3 GB/s (1.16x)     |
| hyperscan/literal-english-nosom                        | 52.3 GB/s (1.00x)   | 45.9 GB/s (1.14x)     |
| hyperscan/literal-english-som                          | 51.0 GB/s (1.00x)   | 44.5 GB/s (1.14x)     |
| hyperscan/literal-russian-nosom                        | 52.0 GB/s (1.00x)   | 45.4 GB/s (1.14x)     |
| hyperscan/literal-russian-som                          | 53.1 GB/s (1.00x)   | 46.0 GB/s (1.15x)     |
| imported/leipzig/twain                                 | 51.0 GB/s (1.00x)   | 42.1 GB/s (1.21x)     |
| imported/rsc/one-pass-long-prefix-not                  | 354.2 MB/s (1.00x)  | 309.9 MB/s (1.14x)    |
| imported/rsc/easy0-32                                  | 1843.8 MB/s (1.00x) | 1382.8 MB/s (1.33x)   |
| imported/rsc/easy0-1mb                                 | 52.3 GB/s (1.12x)   | 58.5 GB/s (1.00x)     |
| imported/rsc/reallyhard0-1mb                           | 51.3 GB/s (1.12x)   | 57.5 GB/s (1.00x)     |
| imported/rsc/reallyreallyhard0-1mb                     | 52.6 GB/s (1.10x)   | 58.1 GB/s (1.00x)     |
| imported/sherlock/name-sherlock-holmes                 | 46.1 GB/s (1.00x)   | 41.0 GB/s (1.12x)     |
| imported/sherlock/name-whitespace                      | 29.6 GB/s (1.00x)   | 26.4 GB/s (1.12x)     |
| imported/sherlock/no-match-uncommon                    | 60.4 GB/s (1.14x)   | 69.1 GB/s (1.00x)     |
| imported/sherlock/no-match-really-common               | 34.9 GB/s (1.21x)   | 42.2 GB/s (1.00x)     |
| opt/prefilter/literal-english                          | 52.1 GB/s (1.00x)   | 45.8 GB/s (1.14x)     |
| opt/prefilter/literal-russian                          | 54.8 GB/s (1.00x)   | 46.2 GB/s (1.19x)     |
| reported/i13-subset-regex/big-ascii                    | 63.9 MB/s (1.12x)   | 71.3 MB/s (1.00x)     |
| reported/i13-subset-regex/huge-ascii-nosuffixlit       | 10.0 MB/s (1.10x)   | 11.0 MB/s (1.00x)     |
| test/func/non-greedy                                   | 40.9 MB/s (1.00x)   | 35.8 MB/s (1.14x)     |
| test/model/count                                       | 392.1 MB/s (1.00x)  | 352.9 MB/s (1.11x)    |
| test/unicode/invalid-utf8/dot-matches-codepoint-prefix | 40.9 MB/s (1.00x)   | 35.8 MB/s (1.14x)     |
| test/unicode/utf8/dot-matches-byte                     | 38.1 MB/s (1.11x)   | 42.4 MB/s (1.00x)     |
| unicode/overlapping-words/english                      | 4.8 MB/s (1.15x)    | 5.5 MB/s (1.00x)      |
| unicode/word/around-holmes-english                     | 51.7 GB/s (1.00x)   | 44.0 GB/s (1.18x)     |
| wild/rustsec-cargo-audit/original-windows              | 25.2 GB/s (1.00x)   | 22.2 GB/s (1.14x)     |
| wild/rustsec-cargo-audit/both-alternate                | 26.5 GB/s (1.00x)   | 24.0 GB/s (1.10x)     |

## Future Work

We would love to get feedback on the current state of the implementation and
discuss the mentioned space-time trade-off for supporting look-ahead assertions.
Furthermore, we would like to discuss the possibility of supporting capture
groups within look-around assertions and how to best integrate support for
look-around assertions into other engines where possible.
