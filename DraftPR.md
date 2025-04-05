# Add support for unbounded look-behind expressions

As an example consider the regex `(?<=Title:\s+)\w+` which would match the
following strings (matches underlined with `~`):

```
Title: hello world
       ~~~~~~~~~~~
```

```
Title: Title: foo
       ~~~~~
              ~~~
```

But **fails** to match:

- `No heading`
- `title: bad case`
- `Title:nospace`

## What

This PR implements the streaming algorithm from
[Linear Matching of JavaScript Regular Expressions (Section 4.4)](https://aurele-barriere.github.io/papers/linearjs.pdf#page=13)
for unbounded look-behinds. The same algorithm has been
[implemented and merged into V8](https://chromium-review.googlesource.com/c/v8/v8/+/5093860).
The addition of look-around expressions to this crate was mentioned previously
in [#1153](https://github.com/rust-lang/regex/discussions/1153).

This PR adds support for positive and negative look-behinds with arbitrary
nesting. With the following limitations

### Limitations

- Look-behind expressions cannot contain capture groups
- The algorithm is implemented only in the PikeVM and with prefiters off
- Only look-behinds and no look-aheads

With the current capture group semantics, no linear time algorithm which would
allow for capture groups in look-arounds is known. However, look-behinds could
be implemented in other engines and with prefilters on. Look-aheads could also
be implemented with additional memory.

## How

We implemented the streaming algorithm presented in Section 4.4 of the paper
mentioned above. The algorithm works by running the sub-automata for any
look-behind expressions in parallel to the main automaton. This is achieved by
compiling the look-behind expressions as usual but patching the resulting NFA
states into a union with the main automaton's states. The union is added per
pattern for multi-pattern searches.

Instead of a `match` state, the sub-automata for look-behinds have a
`WriteLookAround` state. This state causes the current position in the haystack
to be recorded in a global look-around table.

The main automaton (and the sub-automata in the case of nested look-behinds) can
then read from this table by means of a `CheckLookAround` instruction and
compare the stored index with the current position in the haystack. These states
work as conditional epsilon transitions, similar to the already supported "look"
assertions (e.g. `^`, `\b`, `$`).

## Testing

We have added unit tests for the new functionality in the individual test
modules to test the new parsing, translation, and compilation features. We have
further added integration tests in the form of a new toml file. All engines
apart from the PikeVM will reject look-behind expressions. Thus tests containing
look-around expressions are filtered out for engines other than the PikeVM and
Meta engine.

## Performance

TODO: redo with new benchmarks

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

We would love to get feedback on the implementation.

The next steps are to work on the current limitations. Namely, implement support
in more engines and enable prefilters. Additionally, support for look-aheads
would be implemented if the additional memory cost is acceptable.

We are open to the discussion about any of the above.
