# Add support for unbounded look-behind expressions

As an example consider the regex `(?<=Title:\s+)\w+` which would match the
following strings (matches underlined with `~`):

```
Title: HelloWorld
       ~~~~~~~~~~
```

```
Title: Title: foo
       ~~~~~
              ~~~
```

But **does not** match:

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

Capture groups outside of look-arounds are supported. With the current capture
group semantics, no linear time algorithm which would allow for capture groups
inside of look-arounds is known. However, look-behinds could be implemented in
other engines and with prefilters on. Look-aheads could also be implemented with
additional memory.

## How

We implemented the streaming algorithm presented in Section 4.4 of the paper
mentioned above. The algorithm works by running the sub-automata for any
look-behind expressions in parallel to the main automaton. This is achieved by
compiling the look-behind expressions as usual but storing their start states
separately, not reachable from the main automaton.

Instead of a `match` state, the sub-automata for look-behinds have a
`WriteLookAround` state. This state causes the current position in the haystack
to be recorded in a global look-around table.

The main automaton (and the sub-automata in the case of nested look-behinds) can
then read from this table by means of a `CheckLookAround` instruction and
compare the stored index with the current position in the haystack. These states
work as conditional epsilon transitions, similar to the already supported "look"
assertions (e.g. `^`, `\b`, `$`).

`PikeVM`'s cache has been expanded to preserve good performance of single-match
searches (stop the look-around threads once the main automaton finishes) and of
all-matches searches (remember the look-around states when resuming a search to
prevent having to rescan the haystack from the beginning).

## Testing

We have added unit tests for the new functionality in the individual test
modules to test the new parsing, translation, and compilation features. We have
further added integration tests in the form of a new toml file. All engines
apart from the PikeVM will reject look-behind expressions. Thus tests containing
look-around expressions are filtered out for engines other than the PikeVM and
Meta engine.

## Future Work

We would love to get feedback on the implementation.

The next steps are to work on the current limitations. Namely, implement support
in more engines and enable prefilters. Additionally, support for look-aheads
would be implemented if the additional memory cost is acceptable.

We are open to the discussion about any of the above.

## Performance

We forked [`rebar`](https://github.com/epfl-systemf/rebar) and added a new engine
definition (`rust/regex-lookbehind`) for our fork of `regex`. We added this new
engine definition to all benchmarks where `rust/regex` was already present.
Furthermore, we added some benchmark definitions to measure the performance
of the look-behind algorithm.

We ran the full suite of benchmarks twice and merged the results. They are available
in our rebar fork ([`results_full_combined.csv`](https://github.com/epfl-systemf/rebar/blob/master/results_full_combined.csv))

### Results without look-behinds

The results from all benchmarks without look-behinds show that our changes do not
introduce a significant slowdown for regexes that were already supported:

```
$ rebar rank results_full_combined.csv -e 'rust[^2]*$' -F 'lookbehind'
Engine                 Version  Geometric mean of speed ratios  Benchmark count
------                 -------  ------------------------------  ---------------
rust/regex             1.11.0   1.01                            341
rust/regex-lookbehind  1.12.0   1.03                            341
```

Note: We noticed a discrepancy across multiple runs of up to 1.51 when comparing the
current version of `rust/regex`:

```
$ rebar cmp results_full_combined.csv -e 'rust/regex(|-run2)$' -F 'lookbehind' -t 1.5
benchmark                      rust/regex         rust/regex-run2
---------                      ----------         ---------------
hyperscan/literal-russian-som  36.3 GB/s (1.51x)  54.9 GB/s (1.00x)
```

Due to this result, we conclude that, despite the highest speedup ratio being 1.57 when
comparing both engines across both runs, the results of all individual benchmarks
further strengthen the claim that our changes do not significantly impact performance.

<details>
   <summary>Full benchmark comparison (without look-behinds)</summary>

```
$ rebar cmp results_full_combined.csv -e 'rust' -F 'lookbehind'
benchmark                                                  rust/regex            rust/regex-lookbehind  rust/regex-lookbehind-run2  rust/regex-run2
---------                                                  ----------            ---------------------  --------------------------  ---------------
captures/contiguous-letters                                9.0 MB/s (1.34x)      12.0 MB/s (1.00x)      12.0 MB/s (1.00x)           12.0 MB/s (1.00x)
curated/01-literal/sherlock-en                             43.5 GB/s (1.01x)     43.8 GB/s (1.00x)      43.6 GB/s (1.01x)           43.8 GB/s (1.00x)
curated/01-literal/sherlock-casei-en                       12.0 GB/s (1.00x)     11.1 GB/s (1.08x)      11.9 GB/s (1.01x)           12.0 GB/s (1.00x)
curated/01-literal/sherlock-ru                             42.3 GB/s (1.01x)     30.6 GB/s (1.40x)      42.1 GB/s (1.02x)           42.8 GB/s (1.00x)
curated/01-literal/sherlock-casei-ru                       9.5 GB/s (1.01x)      9.6 GB/s (1.00x)       9.6 GB/s (1.00x)            9.5 GB/s (1.01x)
curated/01-literal/sherlock-zh                             50.0 GB/s (1.00x)     50.1 GB/s (1.00x)      50.0 GB/s (1.00x)           49.9 GB/s (1.00x)
curated/02-literal-alternate/sherlock-en                   13.4 GB/s (1.00x)     13.3 GB/s (1.01x)      13.3 GB/s (1.01x)           13.4 GB/s (1.00x)
curated/02-literal-alternate/sherlock-casei-en             3.3 GB/s (1.00x)      3.2 GB/s (1.01x)       3.2 GB/s (1.02x)            3.3 GB/s (1.00x)
curated/02-literal-alternate/sherlock-ru                   7.4 GB/s (1.00x)      7.3 GB/s (1.01x)       7.2 GB/s (1.02x)            7.3 GB/s (1.00x)
curated/02-literal-alternate/sherlock-casei-ru             1774.2 MB/s (1.00x)   1772.0 MB/s (1.00x)    1780.0 MB/s (1.00x)         1769.2 MB/s (1.01x)
curated/02-literal-alternate/sherlock-zh                   15.2 GB/s (1.00x)     15.2 GB/s (1.00x)      15.2 GB/s (1.00x)           15.1 GB/s (1.01x)
curated/03-date/ascii                                      159.2 MB/s (1.01x)    160.2 MB/s (1.00x)     160.2 MB/s (1.00x)          159.2 MB/s (1.01x)
curated/03-date/unicode                                    159.2 MB/s (1.00x)    159.2 MB/s (1.00x)     159.2 MB/s (1.00x)          159.2 MB/s (1.00x)
curated/03-date/compile-ascii                              1.25ms (1.00x)        1.26ms (1.01x)         1.29ms (1.03x)              1.26ms (1.01x)
curated/03-date/compile-unicode                            4.69ms (1.04x)        4.51ms (1.00x)         4.65ms (1.03x)              4.80ms (1.06x)
curated/04-ruff-noqa/real                                  1695.4 MB/s (1.02x)   1728.4 MB/s (1.00x)    1711.3 MB/s (1.01x)         1677.0 MB/s (1.03x)
curated/04-ruff-noqa/tweaked                               1519.3 MB/s (1.06x)   1614.2 MB/s (1.00x)    1598.4 MB/s (1.01x)         1498.0 MB/s (1.08x)
curated/04-ruff-noqa/compile-real                          51.83us (1.00x)       52.13us (1.01x)        53.41us (1.03x)             52.03us (1.00x)
curated/05-lexer-veryl/single                              10.0 MB/s (1.03x)     10.2 MB/s (1.00x)      10.2 MB/s (1.00x)           10.0 MB/s (1.03x)
curated/05-lexer-veryl/compile-single                      241.25us (1.00x)      244.29us (1.01x)       244.16us (1.01x)            242.08us (1.00x)
curated/05-lexer-veryl/multi                               74.8 MB/s (1.02x)     76.4 MB/s (1.00x)      76.0 MB/s (1.01x)           74.4 MB/s (1.03x)
curated/06-cloud-flare-redos/original                      629.9 MB/s (1.00x)    629.9 MB/s (1.00x)     629.9 MB/s (1.00x)          629.9 MB/s (1.00x)
curated/06-cloud-flare-redos/simplified-short              1737.0 MB/s (1.00x)   1737.0 MB/s (1.00x)    1706.6 MB/s (1.02x)         1706.6 MB/s (1.02x)
curated/06-cloud-flare-redos/simplified-long               78.3 GB/s (1.00x)     77.6 GB/s (1.01x)      77.0 GB/s (1.02x)           77.6 GB/s (1.01x)
curated/07-unicode-character-data/parse-line               400.2 MB/s (1.00x)    378.6 MB/s (1.06x)     374.0 MB/s (1.07x)          398.5 MB/s (1.00x)
curated/07-unicode-character-data/compile                  24.39us (1.00x)       25.19us (1.03x)        24.90us (1.02x)             24.49us (1.00x)
curated/08-words/all-english                               123.9 MB/s (1.00x)    123.1 MB/s (1.01x)     122.3 MB/s (1.01x)          123.9 MB/s (1.00x)
curated/08-words/all-russian                               23.8 MB/s (1.00x)     16.3 MB/s (1.46x)      16.3 MB/s (1.46x)           23.8 MB/s (1.00x)
curated/08-words/long-english                              891.9 MB/s (1.00x)    889.0 MB/s (1.00x)     888.6 MB/s (1.00x)          892.4 MB/s (1.00x)
curated/08-words/long-russian                              42.8 MB/s (1.00x)     34.1 MB/s (1.26x)      33.9 MB/s (1.27x)           43.0 MB/s (1.00x)
curated/09-aws-keys/full                                   1992.8 MB/s (1.01x)   2016.1 MB/s (1.00x)    1991.5 MB/s (1.01x)         1970.0 MB/s (1.02x)
curated/09-aws-keys/quick                                  1941.7 MB/s (1.02x)   1975.1 MB/s (1.00x)    1947.8 MB/s (1.01x)         1921.2 MB/s (1.03x)
curated/09-aws-keys/compile-full                           80.69us (1.00x)       83.01us (1.03x)        82.92us (1.03x)             83.60us (1.04x)
curated/09-aws-keys/compile-quick                          13.69us (1.02x)       13.96us (1.04x)        13.44us (1.00x)             13.58us (1.01x)
curated/10-bounded-repeat/letters-en                       773.2 MB/s (1.05x)    796.2 MB/s (1.02x)     811.4 MB/s (1.00x)          768.7 MB/s (1.06x)
curated/10-bounded-repeat/letters-ru                       710.2 MB/s (1.00x)    709.2 MB/s (1.00x)     706.0 MB/s (1.01x)          709.8 MB/s (1.00x)
curated/10-bounded-repeat/context                          115.6 MB/s (1.00x)    113.1 MB/s (1.02x)     112.6 MB/s (1.03x)          115.3 MB/s (1.00x)
curated/10-bounded-repeat/capitals                         917.0 MB/s (1.00x)    917.0 MB/s (1.00x)     913.4 MB/s (1.00x)          913.4 MB/s (1.00x)
curated/10-bounded-repeat/compile-context                  51.87us (1.00x)       53.62us (1.03x)        53.10us (1.02x)             52.62us (1.01x)
curated/10-bounded-repeat/compile-capitals                 52.49us (1.00x)       54.09us (1.03x)        53.82us (1.03x)             53.31us (1.02x)
curated/11-unstructured-to-json/extract                    123.0 MB/s (1.00x)    123.4 MB/s (1.00x)     123.3 MB/s (1.00x)          123.2 MB/s (1.00x)
curated/11-unstructured-to-json/compile                    17.32us (1.02x)       17.57us (1.04x)        17.70us (1.04x)             16.96us (1.00x)
curated/12-dictionary/single                               784.7 MB/s (1.01x)    789.6 MB/s (1.00x)     786.7 MB/s (1.00x)          783.7 MB/s (1.01x)
curated/12-dictionary/multi                                206.6 MB/s (1.00x)    199.3 MB/s (1.04x)     200.0 MB/s (1.03x)          206.4 MB/s (1.00x)
curated/12-dictionary/compile-single                       6.79ms (1.00x)        6.80ms (1.00x)         6.79ms (1.00x)              6.79ms (1.00x)
curated/12-dictionary/compile-multi                        13.34ms (1.09x)       12.29ms (1.01x)        12.22ms (1.00x)             13.46ms (1.10x)
curated/13-noseyparker/single                              138.8 MB/s (1.00x)    136.5 MB/s (1.02x)     135.7 MB/s (1.02x)          137.0 MB/s (1.01x)
curated/13-noseyparker/multi                               111.9 MB/s (1.00x)    111.3 MB/s (1.01x)     112.1 MB/s (1.00x)          111.4 MB/s (1.01x)
curated/13-noseyparker/compile-single                      2.02ms (1.00x)        2.04ms (1.01x)         2.09ms (1.03x)              2.03ms (1.00x)
curated/13-noseyparker/compile-multi                       2.36ms (1.00x)        2.39ms (1.01x)         2.45ms (1.04x)              2.45ms (1.04x)
curated/14-quadratic/1x                                    20.0 MB/s (1.00x)     19.8 MB/s (1.01x)      19.8 MB/s (1.01x)           20.0 MB/s (1.00x)
curated/14-quadratic/2x                                    9.6 MB/s (1.00x)      9.5 MB/s (1.01x)       9.5 MB/s (1.01x)            9.6 MB/s (1.00x)
curated/14-quadratic/10x                                   1902.8 KB/s (1.00x)   1892.6 KB/s (1.01x)    1884.7 KB/s (1.01x)         1902.2 KB/s (1.00x)
dictionary/compile/english                                 192.78ms (1.01x)      190.18ms (1.00x)       195.72ms (1.03x)            199.17ms (1.05x)
dictionary/compile/english-10                              66.95ms (1.00x)       72.86ms (1.09x)        66.67ms (1.00x)             69.49ms (1.04x)
dictionary/compile/english-15                              6.77ms (1.00x)        6.78ms (1.00x)         6.80ms (1.00x)              6.78ms (1.00x)
dictionary/search/english                                  113.0 MB/s (1.00x)    108.7 MB/s (1.04x)     109.2 MB/s (1.03x)          111.7 MB/s (1.01x)
dictionary/search/english-tiny                             196.6 MB/s (1.02x)    195.4 MB/s (1.02x)     200.0 MB/s (1.00x)          198.8 MB/s (1.01x)
dictionary/search/english-10                               180.5 MB/s (1.00x)    175.9 MB/s (1.03x)     175.0 MB/s (1.03x)          180.0 MB/s (1.00x)
dictionary/search/english-15                               783.1 MB/s (1.00x)    785.4 MB/s (1.00x)     785.3 MB/s (1.00x)          783.2 MB/s (1.00x)
folly/awyer-inn-busted                                     179.0 MB/s (1.00x)    177.6 MB/s (1.01x)     177.3 MB/s (1.01x)          178.6 MB/s (1.00x)
folly/literal-never-match-rare                             54.2 GB/s (1.01x)     54.7 GB/s (1.00x)      52.9 GB/s (1.03x)           52.4 GB/s (1.04x)
folly/literal-never-match-frequent                         54.4 GB/s (1.00x)     52.3 GB/s (1.04x)      53.9 GB/s (1.01x)           51.8 GB/s (1.05x)
folly/literal-never-match-tricksy                          7.6 GB/s (1.01x)      7.5 GB/s (1.02x)       7.7 GB/s (1.00x)            7.7 GB/s (1.00x)
grep/every-line                                            2.2 GB/s (1.00x)      2.2 GB/s (1.02x)       2.2 GB/s (1.02x)            2.2 GB/s (1.00x)
grep/long-words-ascii                                      930.3 MB/s (1.00x)    931.5 MB/s (1.00x)     931.5 MB/s (1.00x)          926.6 MB/s (1.01x)
grep/long-words-unicode                                    899.4 MB/s (1.00x)    898.3 MB/s (1.00x)     896.0 MB/s (1.00x)          897.1 MB/s (1.00x)
hyperscan/literal-english-nosom                            54.9 GB/s (1.00x)     54.9 GB/s (1.00x)      54.9 GB/s (1.00x)           54.9 GB/s (1.00x)
hyperscan/literal-english-som                              55.0 GB/s (1.00x)     54.8 GB/s (1.00x)      54.9 GB/s (1.00x)           54.9 GB/s (1.00x)
hyperscan/literal-casei-english-nosom                      16.4 GB/s (1.02x)     16.4 GB/s (1.02x)      16.4 GB/s (1.02x)           16.8 GB/s (1.00x)
hyperscan/literal-casei-english-som                        16.8 GB/s (1.00x)     16.4 GB/s (1.02x)      16.4 GB/s (1.02x)           16.7 GB/s (1.00x)
hyperscan/literal-russian-nosom                            54.9 GB/s (1.00x)     54.9 GB/s (1.00x)      54.9 GB/s (1.00x)           54.9 GB/s (1.00x)
hyperscan/literal-russian-som                              36.3 GB/s (1.51x)     54.8 GB/s (1.00x)      54.9 GB/s (1.00x)           54.9 GB/s (1.00x)
hyperscan/literal-casei-russian-nosom                      13.1 GB/s (1.01x)     13.3 GB/s (1.00x)      13.2 GB/s (1.00x)           13.2 GB/s (1.00x)
hyperscan/literal-casei-russian-som                        13.1 GB/s (1.01x)     13.3 GB/s (1.00x)      13.3 GB/s (1.00x)           13.2 GB/s (1.01x)
hyperscan/literal-suffix-nosom                             20.5 GB/s (1.00x)     17.4 GB/s (1.18x)      20.4 GB/s (1.01x)           20.5 GB/s (1.00x)
hyperscan/literal-suffix-som                               17.8 GB/s (1.01x)     17.7 GB/s (1.01x)      17.9 GB/s (1.00x)           17.9 GB/s (1.00x)
hyperscan/literal-inner-nosom                              21.9 GB/s (1.01x)     22.0 GB/s (1.00x)      22.0 GB/s (1.00x)           22.0 GB/s (1.00x)
hyperscan/literal-inner-som                                17.6 GB/s (1.18x)     20.8 GB/s (1.00x)      20.7 GB/s (1.00x)           20.5 GB/s (1.01x)
hyperscan/fixed-length-words-nosom                         917.8 MB/s (1.00x)    914.6 MB/s (1.00x)     914.1 MB/s (1.00x)          917.6 MB/s (1.00x)
hyperscan/fixed-length-words-som                           912.0 MB/s (1.00x)    908.9 MB/s (1.00x)     908.6 MB/s (1.00x)          912.0 MB/s (1.00x)
hyperscan/fixed-length-words-unicode-nosom                 917.7 MB/s (1.00x)    917.5 MB/s (1.00x)     917.4 MB/s (1.00x)          917.5 MB/s (1.00x)
imported/leipzig/twain                                     45.4 GB/s (1.04x)     46.3 GB/s (1.01x)      46.9 GB/s (1.00x)           46.4 GB/s (1.01x)
imported/leipzig/twain-insensitive                         16.1 GB/s (1.00x)     16.0 GB/s (1.01x)      15.8 GB/s (1.02x)           15.8 GB/s (1.02x)
imported/leipzig/shing                                     27.8 GB/s (1.00x)     22.1 GB/s (1.26x)      27.5 GB/s (1.01x)           27.8 GB/s (1.00x)
imported/leipzig/huck-saw                                  24.8 GB/s (1.00x)     24.8 GB/s (1.00x)      24.4 GB/s (1.02x)           24.5 GB/s (1.01x)
imported/leipzig/word-ending-nn                            30.3 GB/s (1.01x)     30.5 GB/s (1.00x)      30.5 GB/s (1.00x)           30.5 GB/s (1.00x)
imported/leipzig/certain-long-strings-ending-x             6.3 GB/s (1.02x)      6.4 GB/s (1.00x)       6.3 GB/s (1.01x)            6.3 GB/s (1.02x)
imported/leipzig/tom-sawyer-huckle-finn                    22.9 GB/s (1.00x)     22.8 GB/s (1.00x)      22.5 GB/s (1.01x)           22.7 GB/s (1.01x)
imported/leipzig/tom-sawyer-huckle-fin-insensitive         1399.8 MB/s (1.01x)   1414.1 MB/s (1.00x)    1407.6 MB/s (1.00x)         1394.7 MB/s (1.01x)
imported/leipzig/tom-sawyer-huckle-fin-prefix-short        21.3 GB/s (1.00x)     18.0 GB/s (1.18x)      21.1 GB/s (1.01x)           21.0 GB/s (1.01x)
imported/leipzig/tom-sawyer-huckle-fin-prefix-long         20.5 GB/s (1.00x)     20.4 GB/s (1.00x)      20.3 GB/s (1.01x)           20.3 GB/s (1.01x)
imported/leipzig/tom-river                                 18.7 GB/s (1.00x)     18.7 GB/s (1.00x)      18.6 GB/s (1.01x)           18.6 GB/s (1.00x)
imported/leipzig/ing                                       3.3 GB/s (1.00x)      3.3 GB/s (1.00x)       3.3 GB/s (1.01x)            3.3 GB/s (1.01x)
imported/leipzig/ing-whitespace                            3.3 GB/s (1.00x)      3.2 GB/s (1.00x)       3.2 GB/s (1.01x)            3.2 GB/s (1.01x)
imported/leipzig/awyer-inn                                 16.3 GB/s (1.00x)     16.3 GB/s (1.00x)      16.2 GB/s (1.01x)           16.2 GB/s (1.01x)
imported/leipzig/quotes-bounded                            4.8 GB/s (1.00x)      4.8 GB/s (1.00x)       4.8 GB/s (1.01x)            4.8 GB/s (1.01x)
imported/leipzig/non-ascii-alternate                       25.8 GB/s (1.00x)     25.9 GB/s (1.00x)      25.8 GB/s (1.01x)           25.5 GB/s (1.02x)
imported/leipzig/math-symbols                              914.5 MB/s (1.00x)    915.0 MB/s (1.00x)     909.1 MB/s (1.01x)          908.5 MB/s (1.01x)
imported/leipzig/bounded-strings-ending-z                  44.8 GB/s (1.00x)     44.9 GB/s (1.00x)      44.4 GB/s (1.01x)           44.3 GB/s (1.01x)
imported/lh3lh3-reb/uri                                    2.5 GB/s (1.00x)      2.5 GB/s (1.00x)       2.5 GB/s (1.02x)            2.5 GB/s (1.01x)
imported/lh3lh3-reb/email                                  2.6 GB/s (1.01x)      2.6 GB/s (1.00x)       2.6 GB/s (1.01x)            2.5 GB/s (1.02x)
imported/lh3lh3-reb/date                                   2.0 GB/s (1.01x)      2.1 GB/s (1.00x)       2.0 GB/s (1.01x)            2.0 GB/s (1.03x)
imported/lh3lh3-reb/uri-or-email                           867.7 MB/s (1.00x)    865.9 MB/s (1.00x)     858.1 MB/s (1.01x)          856.4 MB/s (1.01x)
imported/mariomka/email                                    49.6 GB/s (1.00x)     49.7 GB/s (1.00x)      49.2 GB/s (1.01x)           49.4 GB/s (1.01x)
imported/mariomka/uri                                      9.6 GB/s (1.00x)      9.4 GB/s (1.02x)       9.6 GB/s (1.00x)            9.5 GB/s (1.00x)
imported/mariomka/ip                                       3.5 GB/s (1.00x)      3.5 GB/s (1.00x)       3.5 GB/s (1.01x)            3.5 GB/s (1.01x)
imported/regex-redux/regex-redux                           11.14ms (1.01x)       11.02ms (1.00x)        11.07ms (1.00x)             11.21ms (1.02x)
imported/rsc/no-exponential                                567.7 MB/s (1.00x)    554.5 MB/s (1.02x)     554.5 MB/s (1.02x)          567.7 MB/s (1.00x)
imported/rsc/literal                                       2.3 GB/s (1.00x)      2.1 GB/s (1.10x)       2.1 GB/s (1.10x)            2.3 GB/s (1.00x)
imported/rsc/not-literal                                   1158.0 MB/s (1.02x)   1158.0 MB/s (1.02x)    1158.0 MB/s (1.02x)         1186.3 MB/s (1.00x)
imported/rsc/match-class                                   2.4 GB/s (1.00x)      2.4 GB/s (1.00x)       2.4 GB/s (1.00x)            2.4 GB/s (1.00x)
imported/rsc/match-class-in-range                          3.4 GB/s (1.00x)      3.3 GB/s (1.05x)       3.3 GB/s (1.05x)            3.4 GB/s (1.00x)
imported/rsc/match-class-unicode                           791.5 MB/s (1.01x)    779.4 MB/s (1.02x)     779.4 MB/s (1.02x)          795.6 MB/s (1.00x)
imported/rsc/anchored-literal-short-non-match              1239.8 MB/s (1.05x)   1239.8 MB/s (1.05x)    1180.7 MB/s (1.11x)         1305.0 MB/s (1.00x)
imported/rsc/anchored-literal-long-non-match               20.2 GB/s (1.00x)     18.2 GB/s (1.11x)      17.3 GB/s (1.17x)           19.1 GB/s (1.06x)
imported/rsc/anchored-literal-short-match                  885.6 MB/s (1.00x)    855.0 MB/s (1.04x)     855.0 MB/s (1.04x)          855.0 MB/s (1.04x)
imported/rsc/anchored-literal-long-match                   13.0 GB/s (1.00x)     13.0 GB/s (1.00x)      12.5 GB/s (1.04x)           13.0 GB/s (1.00x)
imported/rsc/one-pass-short                                405.3 MB/s (1.03x)    415.7 MB/s (1.00x)     405.3 MB/s (1.03x)          415.7 MB/s (1.00x)
imported/rsc/one-pass-short-not                            344.9 MB/s (1.00x)    330.9 MB/s (1.04x)     324.2 MB/s (1.06x)          344.9 MB/s (1.00x)
imported/rsc/one-pass-long-prefix                          506.0 MB/s (1.00x)    467.8 MB/s (1.08x)     467.8 MB/s (1.08x)          495.9 MB/s (1.02x)
imported/rsc/one-pass-long-prefix-not                      506.0 MB/s (1.00x)    467.8 MB/s (1.08x)     467.8 MB/s (1.08x)          506.0 MB/s (1.00x)
imported/rsc/long-needle1                                  56.1 GB/s (1.00x)     53.8 GB/s (1.04x)      53.8 GB/s (1.04x)           56.1 GB/s (1.00x)
imported/rsc/long-needle2                                  372.9 MB/s (1.02x)    377.5 MB/s (1.01x)     378.0 MB/s (1.01x)          380.7 MB/s (1.00x)
imported/rsc/easy0-32                                      2.3 GB/s (1.00x)      2.2 GB/s (1.09x)       2.2 GB/s (1.09x)            2.3 GB/s (1.04x)
imported/rsc/easy0-1k                                      23.9 GB/s (1.00x)     23.3 GB/s (1.02x)      21.7 GB/s (1.10x)           23.3 GB/s (1.02x)
imported/rsc/easy0-32k                                     54.5 GB/s (1.00x)     53.7 GB/s (1.02x)      53.7 GB/s (1.02x)           54.5 GB/s (1.00x)
imported/rsc/easy0-1mb                                     55.0 GB/s (1.00x)     55.0 GB/s (1.00x)      55.0 GB/s (1.00x)           55.0 GB/s (1.00x)
imported/rsc/easy1-32                                      1034.8 MB/s (1.02x)   992.6 MB/s (1.07x)     992.6 MB/s (1.07x)          1057.3 MB/s (1.00x)
imported/rsc/easy1-1k                                      20.7 GB/s (1.00x)     19.4 GB/s (1.06x)      19.4 GB/s (1.06x)           20.7 GB/s (1.00x)
imported/rsc/easy1-32k                                     649.7 GB/s (1.00x)    623.2 GB/s (1.04x)     623.2 GB/s (1.04x)          623.2 GB/s (1.04x)
imported/rsc/easy1-1mb                                     21230.0 GB/s (1.00x)  19930.2 GB/s (1.07x)   19531.6 GB/s (1.09x)        21230.0 GB/s (1.00x)
imported/rsc/medium-32                                     1042.0 MB/s (1.00x)   987.1 MB/s (1.06x)     987.1 MB/s (1.06x)          1023.0 MB/s (1.02x)
imported/rsc/medium-1k                                     17.8 GB/s (1.02x)     17.2 GB/s (1.06x)      17.2 GB/s (1.06x)           18.1 GB/s (1.00x)
imported/rsc/medium-32k                                    565.6 GB/s (1.00x)    535.8 GB/s (1.06x)     535.8 GB/s (1.06x)          555.3 GB/s (1.02x)
imported/rsc/medium-1mb                                    18085.0 GB/s (1.00x)  17133.1 GB/s (1.06x)   17133.1 GB/s (1.06x)        17756.1 GB/s (1.02x)
imported/rsc/hard-32                                       582.2 MB/s (1.00x)    564.4 MB/s (1.03x)     564.4 MB/s (1.03x)          582.2 MB/s (1.00x)
imported/rsc/hard-1k                                       17.8 GB/s (1.00x)     16.9 GB/s (1.05x)      16.9 GB/s (1.05x)           17.5 GB/s (1.02x)
imported/rsc/hard-32k                                      555.3 GB/s (1.00x)    526.6 GB/s (1.05x)     526.6 GB/s (1.05x)          555.3 GB/s (1.00x)
imported/rsc/hard-1mb                                      10279.9 GB/s (1.01x)  10067.9 GB/s (1.03x)   10067.9 GB/s (1.03x)        10389.2 GB/s (1.00x)
imported/rsc/reallyhard0-32                                397.9 MB/s (1.00x)    386.8 MB/s (1.03x)     386.8 MB/s (1.03x)          392.3 MB/s (1.01x)
imported/rsc/reallyhard0-1k                                11.5 GB/s (1.00x)     11.2 GB/s (1.02x)      10.7 GB/s (1.07x)           11.1 GB/s (1.04x)
imported/rsc/reallyhard0-32k                               49.9 GB/s (1.00x)     47.2 GB/s (1.06x)      47.2 GB/s (1.06x)           49.9 GB/s (1.00x)
imported/rsc/reallyhard0-1mb                               52.5 GB/s (1.04x)     36.0 GB/s (1.51x)      54.5 GB/s (1.00x)           53.4 GB/s (1.02x)
imported/rsc/reallyreallyhard0-32                          317.9 MB/s (1.00x)    313.4 MB/s (1.01x)     315.7 MB/s (1.01x)          317.9 MB/s (1.00x)
imported/rsc/reallyreallyhard0-1k                          10.6 GB/s (1.01x)     10.8 GB/s (1.00x)      10.8 GB/s (1.00x)           10.6 GB/s (1.01x)
imported/rsc/reallyreallyhard0-32k                         48.7 GB/s (1.00x)     48.7 GB/s (1.00x)      48.8 GB/s (1.00x)           48.8 GB/s (1.00x)
imported/rsc/reallyreallyhard0-1mb                         56.8 GB/s (1.00x)     56.8 GB/s (1.00x)      56.8 GB/s (1.00x)           56.8 GB/s (1.00x)
imported/rsc/reallyreallyreallyhard0-32                    330.9 MB/s (1.01x)    330.9 MB/s (1.01x)     330.9 MB/s (1.01x)          333.1 MB/s (1.00x)
imported/rsc/reallyreallyreallyhard0-1k                    10.2 GB/s (1.08x)     11.0 GB/s (1.00x)      10.9 GB/s (1.01x)           10.9 GB/s (1.01x)
imported/rsc/reallyreallyreallyhard0-32k                   47.1 GB/s (1.07x)     50.3 GB/s (1.00x)      50.1 GB/s (1.00x)           47.1 GB/s (1.07x)
imported/rsc/reallyreallyreallyhard0-1mb                   56.8 GB/s (1.00x)     56.8 GB/s (1.00x)      56.4 GB/s (1.01x)           56.8 GB/s (1.00x)
imported/sherlock/name-sherlock                            48.3 GB/s (1.00x)     48.3 GB/s (1.00x)      48.2 GB/s (1.00x)           48.3 GB/s (1.00x)
imported/sherlock/name-holmes                              36.7 GB/s (1.00x)     27.5 GB/s (1.34x)      36.8 GB/s (1.00x)           36.5 GB/s (1.01x)
imported/sherlock/name-sherlock-holmes                     48.5 GB/s (1.00x)     48.5 GB/s (1.00x)      48.5 GB/s (1.00x)           48.6 GB/s (1.00x)
imported/sherlock/name-sherlock-casei                      14.2 GB/s (1.01x)     14.1 GB/s (1.02x)      14.3 GB/s (1.00x)           14.2 GB/s (1.01x)
imported/sherlock/name-holmes-casei                        9.7 GB/s (1.00x)      9.7 GB/s (1.00x)       9.8 GB/s (1.00x)            9.8 GB/s (1.00x)
imported/sherlock/name-sherlock-holmes-casei               13.9 GB/s (1.01x)     14.0 GB/s (1.00x)      14.0 GB/s (1.00x)           13.8 GB/s (1.01x)
imported/sherlock/name-whitespace                          28.0 GB/s (1.33x)     37.1 GB/s (1.00x)      37.3 GB/s (1.00x)           37.2 GB/s (1.00x)
imported/sherlock/name-alt1                                43.4 GB/s (1.00x)     43.3 GB/s (1.00x)      43.3 GB/s (1.00x)           43.3 GB/s (1.00x)
imported/sherlock/name-alt2                                12.0 GB/s (1.02x)     12.0 GB/s (1.02x)      12.2 GB/s (1.00x)           12.1 GB/s (1.01x)
imported/sherlock/name-alt3                                10.9 GB/s (1.01x)     10.9 GB/s (1.00x)      10.9 GB/s (1.00x)           10.8 GB/s (1.01x)
imported/sherlock/name-alt3-casei                          1986.0 MB/s (1.00x)   1977.5 MB/s (1.00x)    1966.6 MB/s (1.01x)         1980.1 MB/s (1.00x)
imported/sherlock/name-alt4                                10.9 GB/s (1.01x)     11.0 GB/s (1.00x)      11.0 GB/s (1.00x)           11.0 GB/s (1.00x)
imported/sherlock/name-alt4-casei                          5.9 GB/s (1.00x)      5.8 GB/s (1.02x)       5.8 GB/s (1.02x)            5.9 GB/s (1.00x)
imported/sherlock/name-alt5                                11.5 GB/s (1.02x)     11.7 GB/s (1.00x)      11.7 GB/s (1.00x)           11.6 GB/s (1.01x)
imported/sherlock/name-alt5-casei                          4.1 GB/s (1.02x)      4.2 GB/s (1.00x)       4.2 GB/s (1.00x)            4.1 GB/s (1.01x)
imported/sherlock/no-match-uncommon                        38.0 GB/s (1.00x)     38.0 GB/s (1.00x)      38.0 GB/s (1.00x)           37.9 GB/s (1.00x)
imported/sherlock/no-match-common                          37.9 GB/s (1.00x)     38.0 GB/s (1.00x)      37.9 GB/s (1.00x)           38.0 GB/s (1.00x)
imported/sherlock/no-match-really-common                   44.8 GB/s (1.00x)     44.7 GB/s (1.00x)      44.6 GB/s (1.00x)           44.6 GB/s (1.00x)
imported/sherlock/the-lower                                3.7 GB/s (1.03x)      3.7 GB/s (1.02x)       3.8 GB/s (1.01x)            3.8 GB/s (1.00x)
imported/sherlock/the-upper                                25.7 GB/s (1.02x)     26.2 GB/s (1.00x)      26.1 GB/s (1.00x)           25.3 GB/s (1.04x)
imported/sherlock/the-casei                                1941.9 MB/s (1.00x)   1937.0 MB/s (1.00x)    1938.7 MB/s (1.00x)         1940.0 MB/s (1.00x)
imported/sherlock/everything-greedy                        294.0 MB/s (1.00x)    279.5 MB/s (1.05x)     279.5 MB/s (1.05x)          294.0 MB/s (1.00x)
imported/sherlock/everything-greedy-nl                     394.0 MB/s (1.00x)    380.8 MB/s (1.03x)     380.8 MB/s (1.03x)          391.3 MB/s (1.01x)
imported/sherlock/letters                                  59.8 MB/s (1.00x)     59.7 MB/s (1.01x)      60.1 MB/s (1.00x)           59.5 MB/s (1.01x)
imported/sherlock/letters-upper                            579.0 MB/s (1.00x)    579.0 MB/s (1.00x)     579.0 MB/s (1.00x)          579.0 MB/s (1.00x)
imported/sherlock/letters-lower                            61.2 MB/s (1.00x)     60.9 MB/s (1.01x)      61.3 MB/s (1.00x)           60.7 MB/s (1.01x)
imported/sherlock/words                                    115.6 MB/s (1.04x)    120.5 MB/s (1.00x)     120.2 MB/s (1.00x)          119.2 MB/s (1.01x)
imported/sherlock/before-holmes                            17.9 GB/s (1.00x)     17.9 GB/s (1.00x)      17.8 GB/s (1.01x)           17.9 GB/s (1.00x)
imported/sherlock/before-after-holmes                      21.0 GB/s (1.00x)     20.8 GB/s (1.01x)      20.8 GB/s (1.01x)           17.6 GB/s (1.19x)
imported/sherlock/holmes-cochar-watson                     10.5 GB/s (1.01x)     10.5 GB/s (1.00x)      10.6 GB/s (1.00x)           10.5 GB/s (1.01x)
imported/sherlock/holmes-coword-watson                     1866.2 MB/s (1.00x)   1870.7 MB/s (1.00x)    1866.0 MB/s (1.00x)         1869.2 MB/s (1.00x)
imported/sherlock/quotes                                   2.9 GB/s (1.00x)      2.9 GB/s (1.00x)       2.9 GB/s (1.00x)            2.9 GB/s (1.01x)
imported/sherlock/line-boundary-sherlock-holmes            41.7 GB/s (1.00x)     41.6 GB/s (1.00x)      41.8 GB/s (1.00x)           41.7 GB/s (1.00x)
imported/sherlock/word-ending-n                            899.8 MB/s (1.00x)    886.7 MB/s (1.01x)     890.2 MB/s (1.01x)          897.1 MB/s (1.00x)
imported/sherlock/repeated-class-negation                  23.0 GB/s (1.03x)     23.5 GB/s (1.01x)      23.7 GB/s (1.00x)           23.7 GB/s (1.00x)
imported/sherlock/ing-suffix                               3.3 GB/s (1.00x)      3.2 GB/s (1.01x)       3.2 GB/s (1.02x)            3.3 GB/s (1.00x)
imported/sherlock/ing-suffix-limited-space                 3.5 GB/s (1.01x)      3.6 GB/s (1.00x)       3.6 GB/s (1.00x)            3.5 GB/s (1.00x)
opt/accelerate/whole-line                                  1422.7 MB/s (1.00x)   1414.1 MB/s (1.01x)    1411.3 MB/s (1.01x)         1425.6 MB/s (1.00x)
opt/accelerate/non-dna                                     1990.3 MB/s (1.01x)   2004.2 MB/s (1.00x)    1998.8 MB/s (1.00x)         1996.0 MB/s (1.00x)
opt/backtrack/words-english                                232.1 MB/s (1.00x)    225.0 MB/s (1.03x)     225.0 MB/s (1.03x)          232.1 MB/s (1.00x)
opt/backtrack/words-russian                                55.6 MB/s (1.02x)     56.5 MB/s (1.00x)      56.3 MB/s (1.00x)           55.9 MB/s (1.01x)
opt/fixed-length/too-small-ascii                           357.6 MB/s (1.00x)    301.2 MB/s (1.19x)     301.2 MB/s (1.19x)          336.6 MB/s (1.06x)
opt/fixed-length/too-small-unicode                         2.1 GB/s (1.00x)      1807.0 MB/s (1.19x)    1807.0 MB/s (1.19x)         2.1 GB/s (1.00x)
opt/fixed-length/too-big-ascii                             3.0 GB/s (1.00x)      2.5 GB/s (1.19x)       2.4 GB/s (1.25x)            3.0 GB/s (1.00x)
opt/fixed-length/too-big-unicode                           2.6 GB/s (1.00x)      2.2 GB/s (1.19x)       2.0 GB/s (1.25x)            2.4 GB/s (1.06x)
opt/fixed-length/go33484-1                                 582.1 GB/s (1.00x)    490.2 GB/s (1.19x)     465.7 GB/s (1.25x)          547.8 GB/s (1.06x)
opt/fixed-length/go33484-2                                 582.1 GB/s (1.00x)    490.2 GB/s (1.19x)     490.2 GB/s (1.19x)          582.1 GB/s (1.00x)
opt/fixed-length/go33484-3                                 58.2 GB/s (1.00x)     49.0 GB/s (1.19x)      49.0 GB/s (1.19x)           54.8 GB/s (1.06x)
opt/literal-alt/one-pattern                                787.3 MB/s (1.00x)    776.8 MB/s (1.01x)     776.8 MB/s (1.01x)          787.3 MB/s (1.00x)
opt/literal-alt/pattern-per-word                           454.7 MB/s (1.00x)    451.2 MB/s (1.01x)     456.4 MB/s (1.00x)          436.1 MB/s (1.05x)
opt/nfa-sparse/small-repeated-class-bytes                  1496.2 KB/s (1.00x)   1402.5 KB/s (1.07x)    1392.0 KB/s (1.07x)         1341.1 KB/s (1.12x)
opt/nfa-sparse/small-repeated-class-unicode                1491.5 KB/s (1.00x)   1399.9 KB/s (1.07x)    1394.3 KB/s (1.07x)         1481.1 KB/s (1.01x)
opt/onepass/fn-predicate                                   1078.5 MB/s (1.05x)   1135.9 MB/s (1.00x)    1134.0 MB/s (1.00x)         1073.5 MB/s (1.06x)
opt/onepass/first-three-words-english                      557.1 MB/s (1.02x)    567.9 MB/s (1.00x)     567.9 MB/s (1.00x)          557.1 MB/s (1.02x)
opt/onepass/first-three-words-russian                      726.0 MB/s (1.01x)    736.8 MB/s (1.00x)     735.8 MB/s (1.00x)          723.7 MB/s (1.02x)
opt/onepass/word-boundary-english                          901.1 MB/s (1.04x)    934.4 MB/s (1.00x)     936.3 MB/s (1.00x)          895.1 MB/s (1.05x)
opt/onepass/word-boundary-russian                          1160.4 MB/s (1.04x)   1207.8 MB/s (1.00x)    1205.7 MB/s (1.00x)         1157.6 MB/s (1.04x)
opt/prefilter/literal-english                              54.9 GB/s (1.00x)     54.9 GB/s (1.00x)      54.9 GB/s (1.00x)           54.9 GB/s (1.00x)
opt/prefilter/literal-casei-english                        16.8 GB/s (1.00x)     16.4 GB/s (1.02x)      16.4 GB/s (1.02x)           16.8 GB/s (1.00x)
opt/prefilter/literal-russian                              54.9 GB/s (1.00x)     54.9 GB/s (1.00x)      54.9 GB/s (1.00x)           54.9 GB/s (1.00x)
opt/prefilter/literal-casei-russian                        13.2 GB/s (1.01x)     13.3 GB/s (1.00x)      13.3 GB/s (1.00x)           13.3 GB/s (1.00x)
opt/prefilter/rust-functions                               15.7 GB/s (1.00x)     15.7 GB/s (1.00x)      15.7 GB/s (1.00x)           15.7 GB/s (1.00x)
opt/reverse-anchored/word-end                              33261.6 GB/s (1.00x)  31044.1 GB/s (1.07x)   30042.7 GB/s (1.11x)        32114.6 GB/s (1.04x)
opt/reverse-inner/holmes                                   20.9 GB/s (1.01x)     21.0 GB/s (1.00x)      20.9 GB/s (1.01x)           21.0 GB/s (1.00x)
opt/reverse-inner/email                                    81.9 GB/s (1.01x)     82.8 GB/s (1.00x)      83.0 GB/s (1.00x)           82.4 GB/s (1.01x)
opt/reverse-inner/factored-prefix                          9.7 GB/s (1.01x)      9.7 GB/s (1.01x)       9.7 GB/s (1.01x)            9.9 GB/s (1.00x)
opt/reverse-inner/no-quadratic-backward                    918.1 MB/s (1.00x)    913.7 MB/s (1.00x)     914.8 MB/s (1.00x)          918.1 MB/s (1.00x)
opt/reverse-inner/no-quadratic-forward                     459.9 MB/s (1.00x)    459.0 MB/s (1.00x)     459.0 MB/s (1.00x)          459.9 MB/s (1.00x)
opt/reverse-suffix/holmes                                  17.8 GB/s (1.01x)     17.9 GB/s (1.00x)      17.9 GB/s (1.01x)           17.9 GB/s (1.00x)
opt/reverse-suffix/no-quadratic                            915.9 MB/s (1.00x)    912.6 MB/s (1.00x)     912.6 MB/s (1.00x)          915.9 MB/s (1.00x)
reported/i1095-word-repetition/unicode-compile             28.57ms (1.06x)       27.00ms (1.00x)        27.53ms (1.02x)             29.18ms (1.08x)
reported/i1095-word-repetition/unicode-search              868.3 KB/s (1.13x)    779.1 KB/s (1.26x)     882.5 KB/s (1.11x)          981.5 KB/s (1.00x)
reported/i1095-word-repetition/ascii-compile               34.88us (1.00x)       35.19us (1.01x)        35.33us (1.02x)             34.71us (1.00x)
reported/i1095-word-repetition/ascii-search                448.0 MB/s (1.00x)    446.3 MB/s (1.01x)     445.5 MB/s (1.01x)          448.8 MB/s (1.00x)
reported/i13-subset-regex/original-ascii                   6.3 GB/s (1.02x)      6.4 GB/s (1.00x)       6.4 GB/s (1.00x)            6.3 GB/s (1.01x)
reported/i13-subset-regex/original-unicode                 377.4 MB/s (1.00x)    365.0 MB/s (1.03x)     365.1 MB/s (1.03x)          376.1 MB/s (1.00x)
reported/i13-subset-regex/big-ascii                        99.3 MB/s (1.00x)     94.5 MB/s (1.05x)      92.9 MB/s (1.07x)           98.7 MB/s (1.01x)
reported/i13-subset-regex/big-unicode                      35.3 MB/s (1.04x)     33.3 MB/s (1.10x)      36.7 MB/s (1.00x)           35.3 MB/s (1.04x)
reported/i13-subset-regex/huge-ascii                       15.1 MB/s (1.10x)     15.9 MB/s (1.04x)      15.7 MB/s (1.06x)           16.6 MB/s (1.00x)
reported/i13-subset-regex/huge-unicode                     16.8 MB/s (1.00x)     15.7 MB/s (1.07x)      15.7 MB/s (1.07x)           16.7 MB/s (1.01x)
reported/i13-subset-regex/huge-ascii-nosuffixlit           16.8 MB/s (1.00x)     15.9 MB/s (1.06x)      15.7 MB/s (1.07x)           15.9 MB/s (1.06x)
reported/i13-subset-regex/huge-unicode-nosuffixlit         16.9 MB/s (1.00x)     15.9 MB/s (1.06x)      15.9 MB/s (1.06x)           16.7 MB/s (1.01x)
reported/i787-keywords/compile                             348.12us (1.00x)      350.08us (1.01x)       353.12us (1.01x)            348.11us (1.00x)
reported/i787-keywords/ascii                               209.5 MB/s (1.00x)    208.0 MB/s (1.01x)     207.5 MB/s (1.01x)          209.4 MB/s (1.00x)
reported/i787-keywords/unicode                             209.4 MB/s (1.00x)    207.4 MB/s (1.01x)     207.1 MB/s (1.01x)          208.4 MB/s (1.00x)
reported/i787-keywords/opt-ascii                           417.4 MB/s (1.00x)    415.6 MB/s (1.00x)     415.4 MB/s (1.00x)          416.0 MB/s (1.00x)
reported/i787-keywords/opt-unicode                         415.5 MB/s (1.00x)    413.9 MB/s (1.01x)     413.7 MB/s (1.01x)          416.6 MB/s (1.00x)
reported/i988-cloudflare-compile/javascript-obfuscation    14.38us (1.00x)       14.92us (1.04x)        14.87us (1.03x)             14.45us (1.00x)
reported/i988-cloudflare-compile/sql-injection             142.19us (1.00x)      144.06us (1.01x)       145.88us (1.03x)            142.43us (1.00x)
slow/quadratic-regex-1x                                    9.9 MB/s (1.00x)      9.9 MB/s (1.00x)       9.9 MB/s (1.00x)            9.9 MB/s (1.00x)
slow/quadratic-regex-2x                                    4.8 MB/s (1.00x)      4.8 MB/s (1.00x)       4.8 MB/s (1.00x)            4.8 MB/s (1.00x)
slow/quadratic-haystack-1x                                 20.0 MB/s (1.00x)     19.8 MB/s (1.01x)      19.8 MB/s (1.01x)           20.0 MB/s (1.00x)
slow/quadratic-haystack-2x                                 9.6 MB/s (1.00x)      9.5 MB/s (1.01x)       9.5 MB/s (1.01x)            9.6 MB/s (1.00x)
test/dot/default-new-line                                  45.4 MB/s (1.00x)     41.5 MB/s (1.10x)      39.7 MB/s (1.14x)           45.4 MB/s (1.00x)
test/dot/default-carriage-return                           41.5 MB/s (1.00x)     39.7 MB/s (1.04x)      38.1 MB/s (1.09x)           39.7 MB/s (1.04x)
test/dot/dotall-new-line                                   43.3 MB/s (1.00x)     38.1 MB/s (1.14x)      38.1 MB/s (1.14x)           41.5 MB/s (1.05x)
test/dot/dotall-carriage-return                            41.5 MB/s (1.00x)     39.7 MB/s (1.04x)      39.7 MB/s (1.04x)           41.5 MB/s (1.00x)
test/dot/multiline-new-line                                45.4 MB/s (1.00x)     39.7 MB/s (1.14x)      39.7 MB/s (1.14x)           43.3 MB/s (1.05x)
test/dot/multiline-carriage-return                         43.3 MB/s (1.00x)     39.7 MB/s (1.09x)      38.1 MB/s (1.14x)           41.5 MB/s (1.05x)
test/dot/dotall-multiline-new-line                         41.5 MB/s (1.00x)     38.1 MB/s (1.09x)      36.7 MB/s (1.13x)           41.5 MB/s (1.00x)
test/dot/dotall-multiline-carriage-return                  39.7 MB/s (1.04x)     38.1 MB/s (1.09x)      38.1 MB/s (1.09x)           41.5 MB/s (1.00x)
test/func/leftmost-first                                   303.4 MB/s (1.00x)    256.8 MB/s (1.18x)     256.8 MB/s (1.18x)          303.4 MB/s (1.00x)
test/func/dollar-only-matches-end                          56.1 MB/s (1.00x)     53.0 MB/s (1.06x)      51.5 MB/s (1.09x)           56.1 MB/s (1.00x)
test/func/non-greedy                                       77.3 MB/s (1.00x)     75.3 MB/s (1.03x)      71.5 MB/s (1.08x)           73.4 MB/s (1.05x)
test/model/count                                           630.1 MB/s (1.00x)    598.1 MB/s (1.05x)     598.1 MB/s (1.05x)          630.1 MB/s (1.00x)
test/model/count-spans                                     476.8 MB/s (1.00x)    470.5 MB/s (1.01x)     470.5 MB/s (1.01x)          476.8 MB/s (1.00x)
test/model/count-captures                                  420.1 MB/s (1.00x)    415.1 MB/s (1.01x)     415.1 MB/s (1.01x)          420.1 MB/s (1.00x)
test/model/grep                                            375.7 MB/s (1.00x)    375.7 MB/s (1.00x)     364.6 MB/s (1.03x)          375.7 MB/s (1.00x)
test/model/grep-captures                                   106.0 MB/s (1.00x)    105.4 MB/s (1.01x)     105.4 MB/s (1.01x)          106.0 MB/s (1.00x)
test/model/compile                                         11.06us (1.01x)       10.97us (1.01x)        10.91us (1.00x)             11.13us (1.02x)
test/unicode/case/ascii-only                               100.4 MB/s (1.00x)    90.8 MB/s (1.11x)      86.7 MB/s (1.16x)           100.4 MB/s (1.00x)
test/unicode/case/ascii-with-unicode                       65.8 MB/s (1.00x)     61.5 MB/s (1.07x)      61.5 MB/s (1.07x)           65.8 MB/s (1.00x)
test/unicode/case/unicode                                  65.8 MB/s (1.00x)     61.5 MB/s (1.07x)      59.6 MB/s (1.10x)           65.8 MB/s (1.00x)
test/unicode/decimal/ascii-only                            136.2 MB/s (1.00x)    124.4 MB/s (1.10x)     124.4 MB/s (1.10x)          130.0 MB/s (1.05x)
test/unicode/decimal/unicode                               114.4 MB/s (1.00x)    102.2 MB/s (1.12x)     102.2 MB/s (1.12x)          114.4 MB/s (1.00x)
test/unicode/invalid-utf8/dot-matches-xFF                  41.5 MB/s (1.00x)     39.7 MB/s (1.04x)      38.1 MB/s (1.09x)           41.5 MB/s (1.00x)
test/unicode/invalid-utf8/dot-no-matches-xFF               45.4 MB/s (1.00x)     39.7 MB/s (1.14x)      39.7 MB/s (1.14x)           45.4 MB/s (1.00x)
test/unicode/invalid-utf8/dot-matches-codepoint-prefix     77.3 MB/s (1.00x)     73.4 MB/s (1.05x)      71.5 MB/s (1.08x)           77.3 MB/s (1.00x)
test/unicode/invalid-utf8/dot-no-matches-codepoint-prefix  124.4 MB/s (1.00x)    110.0 MB/s (1.13x)     106.0 MB/s (1.17x)          114.4 MB/s (1.09x)
test/unicode/invalid-utf8/xFF-matches-xFF                  50.2 MB/s (1.00x)     43.3 MB/s (1.16x)      43.3 MB/s (1.16x)           50.2 MB/s (1.00x)
test/unicode/letter/pL-matches-bmp-delta                   76.3 MB/s (1.00x)     70.6 MB/s (1.08x)      70.6 MB/s (1.08x)           76.3 MB/s (1.00x)
test/unicode/letter/pLbraced-matches-bmp-delta             76.3 MB/s (1.00x)     70.6 MB/s (1.08x)      68.1 MB/s (1.12x)           76.3 MB/s (1.00x)
test/unicode/letter/pLbraced-matches-nonbmp-delta          146.7 MB/s (1.00x)    136.2 MB/s (1.08x)     127.2 MB/s (1.15x)          141.3 MB/s (1.04x)
test/unicode/letter/pLetter-matches-bmp-delta              76.3 MB/s (1.00x)     70.6 MB/s (1.08x)      68.1 MB/s (1.12x)           76.3 MB/s (1.00x)
test/unicode/letter/pLetter-casei-matches-bmp-delta        76.3 MB/s (1.00x)     70.6 MB/s (1.08x)      68.1 MB/s (1.12x)           73.4 MB/s (1.04x)
test/unicode/letter/pLetter-gc-equals-matches-bmp-delta    76.3 MB/s (1.00x)     70.6 MB/s (1.08x)      70.6 MB/s (1.08x)           76.3 MB/s (1.00x)
test/unicode/letter/pLetter-gc-colon-matches-bmp-delta     79.5 MB/s (1.00x)     70.6 MB/s (1.12x)      68.1 MB/s (1.17x)           76.3 MB/s (1.04x)
test/unicode/utf8/dot-matches-byte                         84.8 MB/s (1.00x)     81.2 MB/s (1.04x)      82.9 MB/s (1.02x)           82.9 MB/s (1.02x)
test/unicode/utf8/dot-matches-codepoint                    146.7 MB/s (1.00x)    136.2 MB/s (1.08x)     131.5 MB/s (1.12x)          146.7 MB/s (1.00x)
test/unicode/whitespace/ascii-only                         136.2 MB/s (1.00x)    124.4 MB/s (1.10x)     119.2 MB/s (1.14x)          136.2 MB/s (1.00x)
test/unicode/whitespace/unicode                            114.4 MB/s (1.00x)    106.0 MB/s (1.08x)     106.0 MB/s (1.08x)          114.4 MB/s (1.00x)
test/unicode/word-boundary/ascii-only                      86.7 MB/s (1.00x)     79.5 MB/s (1.09x)      76.3 MB/s (1.14x)           86.7 MB/s (1.00x)
test/unicode/word-boundary/unicode-alphabetic              11.2 MB/s (1.00x)     11.2 MB/s (1.01x)      11.2 MB/s (1.00x)           11.1 MB/s (1.01x)
test/unicode/word-boundary/unicode-join-control            15.9 MB/s (1.01x)     15.9 MB/s (1.01x)      16.0 MB/s (1.00x)           15.8 MB/s (1.01x)
test/unicode/word-boundary/unicode-mark                    11.2 MB/s (1.00x)     11.2 MB/s (1.01x)      11.2 MB/s (1.00x)           11.2 MB/s (1.00x)
test/unicode/word-boundary/unicode-decimal-number          15.9 MB/s (1.01x)     16.0 MB/s (1.00x)      16.0 MB/s (1.00x)           15.6 MB/s (1.02x)
test/unicode/word-boundary/unicode-connector-punctuation   15.9 MB/s (1.01x)     16.0 MB/s (1.00x)      15.9 MB/s (1.01x)           15.9 MB/s (1.01x)
test/unicode/word/ascii-only                               86.7 MB/s (1.00x)     79.5 MB/s (1.09x)      73.4 MB/s (1.18x)           86.7 MB/s (1.00x)
test/unicode/word/unicode-alphabetic                       76.3 MB/s (1.00x)     70.6 MB/s (1.08x)      70.6 MB/s (1.08x)           76.3 MB/s (1.00x)
test/unicode/word/unicode-join-control                     114.4 MB/s (1.00x)    102.2 MB/s (1.12x)     102.2 MB/s (1.12x)          114.4 MB/s (1.00x)
test/unicode/word/unicode-mark                             76.3 MB/s (1.00x)     70.6 MB/s (1.08x)      70.6 MB/s (1.08x)           76.3 MB/s (1.00x)
test/unicode/word/unicode-decimal-number                   114.4 MB/s (1.00x)    102.2 MB/s (1.12x)     102.2 MB/s (1.12x)          110.0 MB/s (1.04x)
test/unicode/word/unicode-connector-punctuation            114.4 MB/s (1.00x)    102.2 MB/s (1.12x)     102.2 MB/s (1.12x)          114.4 MB/s (1.00x)
unicode/codepoints/any-one                                 458.3 MB/s (1.00x)    401.1 MB/s (1.14x)     409.8 MB/s (1.12x)          448.9 MB/s (1.02x)
unicode/codepoints/any-all                                 445.1 MB/s (1.00x)    436.7 MB/s (1.02x)     435.4 MB/s (1.02x)          443.7 MB/s (1.00x)
unicode/codepoints/letters-one                             14.4 MB/s (1.00x)     12.3 MB/s (1.18x)      12.3 MB/s (1.18x)           14.5 MB/s (1.00x)
unicode/codepoints/letters-alt                             14.7 MB/s (1.00x)     12.3 MB/s (1.19x)      12.5 MB/s (1.18x)           14.6 MB/s (1.00x)
unicode/codepoints/letters-lower-or-upper                  910.6 MB/s (1.00x)    910.6 MB/s (1.00x)     908.6 MB/s (1.00x)          908.6 MB/s (1.00x)
unicode/codepoints/contiguous-greek                        914.6 MB/s (1.00x)    914.6 MB/s (1.00x)     912.6 MB/s (1.00x)          912.6 MB/s (1.00x)
unicode/compile/one-letter                                 118.19us (1.07x)      110.24us (1.00x)       110.04us (1.00x)            118.28us (1.07x)
unicode/compile/fifty-letters                              5.57ms (1.08x)        5.16ms (1.00x)         5.23ms (1.01x)              5.66ms (1.10x)
unicode/compile/fifty-letters-ascii                        9.32us (1.00x)        9.36us (1.00x)         9.32us (1.00x)              9.34us (1.00x)
unicode/compile/match-every-line                           42.54us (1.00x)       43.15us (1.01x)        43.09us (1.01x)             42.72us (1.00x)
unicode/compile/match-every-line-ascii                     10.23us (1.01x)       10.20us (1.00x)        10.17us (1.00x)             10.31us (1.01x)
unicode/compile/negated-class-matches-codepoint            32.76us (1.00x)       33.20us (1.01x)        33.01us (1.01x)             32.72us (1.00x)
unicode/overlapping-words/ascii                            79.7 MB/s (1.00x)     73.3 MB/s (1.09x)      77.1 MB/s (1.04x)           80.0 MB/s (1.00x)
unicode/overlapping-words/english                          7.1 MB/s (1.00x)      7.1 MB/s (1.00x)       7.1 MB/s (1.01x)            7.1 MB/s (1.00x)
unicode/overlapping-words/russian                          6.4 MB/s (1.01x)      6.5 MB/s (1.00x)       6.5 MB/s (1.01x)            6.5 MB/s (1.01x)
unicode/word/boundary-any-english                          123.4 MB/s (1.00x)    122.9 MB/s (1.01x)     122.4 MB/s (1.01x)          123.9 MB/s (1.00x)
unicode/word/boundary-any-russian                          26.6 MB/s (1.00x)     17.0 MB/s (1.56x)      16.9 MB/s (1.57x)           26.5 MB/s (1.00x)
unicode/word/boundary-long-english                         905.3 MB/s (1.00x)    901.5 MB/s (1.00x)     901.2 MB/s (1.00x)          905.1 MB/s (1.00x)
unicode/word/boundary-long-russian                         43.3 MB/s (1.00x)     35.1 MB/s (1.23x)      34.9 MB/s (1.24x)           43.1 MB/s (1.00x)
unicode/word/around-holmes-english                         55.8 GB/s (1.00x)     55.7 GB/s (1.00x)      55.7 GB/s (1.00x)           55.7 GB/s (1.00x)
unicode/word/around-holmes-russian                         36.4 MB/s (1.01x)     34.8 MB/s (1.06x)      34.7 MB/s (1.06x)           36.7 MB/s (1.00x)
wild/bibleref/compile                                      289.02us (1.04x)      279.52us (1.01x)       277.77us (1.00x)            289.70us (1.04x)
wild/bibleref/long                                         883.4 MB/s (1.00x)    883.2 MB/s (1.00x)     882.8 MB/s (1.00x)          883.0 MB/s (1.00x)
wild/bibleref/short                                        62.5 MB/s (1.00x)     62.8 MB/s (1.00x)      61.9 MB/s (1.02x)           62.6 MB/s (1.00x)
wild/bibleref/line                                         732.4 MB/s (1.01x)    739.2 MB/s (1.00x)     737.9 MB/s (1.00x)          732.5 MB/s (1.01x)
wild/caddy/caddy                                           449.5 MB/s (1.00x)    441.7 MB/s (1.02x)     441.7 MB/s (1.02x)          451.5 MB/s (1.00x)
wild/dot-star-capture/rust-src-tools                       536.8 MB/s (1.00x)    524.0 MB/s (1.02x)     522.0 MB/s (1.03x)          527.1 MB/s (1.02x)
wild/grapheme/compile                                      304.73us (1.07x)      285.59us (1.00x)       285.06us (1.00x)            305.07us (1.07x)
wild/grapheme/source-code                                  122.9 MB/s (1.00x)    120.4 MB/s (1.02x)     117.4 MB/s (1.05x)          122.5 MB/s (1.00x)
wild/grapheme/codepoints                                   451.4 MB/s (1.00x)    437.2 MB/s (1.03x)     420.5 MB/s (1.07x)          444.2 MB/s (1.02x)
wild/parol-veryl/ascii                                     10.0 MB/s (1.02x)     10.2 MB/s (1.00x)      10.2 MB/s (1.00x)           10.0 MB/s (1.02x)
wild/parol-veryl/unicode                                   8.5 MB/s (1.04x)      8.9 MB/s (1.00x)       8.9 MB/s (1.00x)            8.5 MB/s (1.04x)
wild/parol-veryl/multi-patternid-ascii                     74.4 MB/s (1.03x)     76.4 MB/s (1.00x)      76.0 MB/s (1.01x)           74.4 MB/s (1.03x)
wild/parol-veryl/multi-captures-ascii                      33.9 MB/s (1.05x)     35.6 MB/s (1.00x)      35.5 MB/s (1.00x)           33.9 MB/s (1.05x)
wild/ruff/whitespace-around-keywords                       376.6 MB/s (1.01x)    381.9 MB/s (1.00x)     379.7 MB/s (1.01x)          373.6 MB/s (1.02x)
wild/ruff/noqa                                             1699.1 MB/s (1.02x)   1728.4 MB/s (1.00x)    1714.1 MB/s (1.01x)         1683.4 MB/s (1.03x)
wild/ruff/unnecessary-coding-comment                       1520.8 MB/s (1.00x)   1508.9 MB/s (1.01x)    1497.3 MB/s (1.02x)         1500.2 MB/s (1.01x)
wild/ruff/string-quote-prefix                              2.1 GB/s (1.03x)      2.2 GB/s (1.00x)       2.2 GB/s (1.01x)            2.1 GB/s (1.03x)
wild/ruff/space-around-operator                            497.7 MB/s (1.01x)    503.6 MB/s (1.00x)     497.2 MB/s (1.01x)          493.4 MB/s (1.02x)
wild/ruff/shebang                                          956.2 MB/s (1.12x)    1070.7 MB/s (1.00x)    1061.2 MB/s (1.01x)         950.6 MB/s (1.13x)
wild/rustsec-cargo-audit/original-unix                     29.5 GB/s (1.03x)     30.1 GB/s (1.01x)      29.8 GB/s (1.02x)           30.3 GB/s (1.00x)
wild/rustsec-cargo-audit/original-windows                  28.5 GB/s (1.01x)     28.9 GB/s (1.00x)      28.1 GB/s (1.03x)           27.8 GB/s (1.04x)
wild/rustsec-cargo-audit/both-slashes                      26.3 GB/s (1.19x)     30.9 GB/s (1.01x)      30.6 GB/s (1.02x)           31.3 GB/s (1.00x)
wild/rustsec-cargo-audit/both-alternate                    30.6 GB/s (1.01x)     30.6 GB/s (1.01x)      30.3 GB/s (1.02x)           30.9 GB/s (1.00x)
wild/url/compile                                           2.80ms (1.00x)        2.83ms (1.01x)         2.85ms (1.02x)              2.80ms (1.00x)
wild/url/search                                            110.8 MB/s (1.00x)    109.3 MB/s (1.01x)     109.0 MB/s (1.02x)          110.6 MB/s (1.00x)
```

</details>

### Results with look-behinds

To get an estimate for performance of "real-world regexes" using look-behinds,
we extracted all regexes that contain look-behind expressions from the `snort`
ruleset. We chose this as a source of regexes because it has been used as a
benchmark for look-arounds before in [Efficient Matching of Regular Expressions with Lookaround Assertions.](https://dl.acm.org/doi/10.1145/3632934)

Unfortunately, this ruleset is licensed in a way that prohibits us from
distributing it. See the reproduction section below to learn where to get the
ruleset from and how to extract the regexes.

Furthermore, we wrote a couple of very simple benchmarks to demonstrate that
our implementation respects linearity.

We chose to compare our implementation to `python/re`, as this engine is readily
available, hence easy to benchmark, and used ubiquitously. Note, however, that
`python/re` only supports bounded length look-behinds, while our implementation
supports unbounded ones as well.

<details>
   <summary>Look-behind benchmark comparison</summary>

```
$ rebar cmp results_full_combined.csv -f 'lookbehind' -e '[^2]$'
benchmark                                     python/re           rust/regex-lookbehind
---------                                     ---------           ---------------------
lookbehind/snort/snort-0                      4.1 GB/s (1.00x)    62.2 MB/s (67.07x)
lookbehind/snort/snort-1                      356.9 MB/s (1.00x)  43.8 MB/s (8.16x)
lookbehind/snort/snort-2                      170.4 MB/s (1.00x)  74.3 MB/s (2.29x)
lookbehind/snort/snort-3                      130.3 MB/s (1.02x)  132.6 MB/s (1.00x)
lookbehind/snort/snort-4                      3.8 GB/s (1.00x)    64.4 MB/s (60.92x)
lookbehind/snort/linear-haystack-1000         234.8 MB/s (1.00x)  40.4 MB/s (5.82x)
lookbehind/snort/linear-haystack-10000        253.8 MB/s (1.00x)  40.4 MB/s (6.28x)
lookbehind/snort/linear-haystack-100000       257.2 MB/s (1.00x)  40.8 MB/s (6.31x)
lookbehind/snort/linear-haystack-many-1000    33.9 MB/s (1.00x)   15.4 MB/s (2.20x)
lookbehind/snort/linear-haystack-many-10000   32.5 MB/s (1.00x)   15.4 MB/s (2.11x)
lookbehind/snort/linear-haystack-many-100000  32.7 MB/s (1.00x)   15.4 MB/s (2.12x)
```
</details>

A few things to note:

1. The regexes in `snort-0` and `snort-4` are the only ones where there is an
   opportunity for prefiltering based on a prefix literal, which we haven't implemented currently.
   This explains the huge difference in speedup compared to all other regexes.
2. For regexes containing no look-behinds, there are a few benchmarks where the
   speedup ratio between `pyhton/re` and `rust/*` is similar to the values seen
   here (e.g. `imported/sherlock/everything-greedy-nl`, `curated/08-words/long-russian`).
   We therefore conclude that the baseline performance for regexes with
   look-behinds is reasonable.
3. The constant throughput in the `linear-haystack` benchmarks shows that our
   algorithm indeed runs in linear time.

### How to reproduce

Please follow these instructions to reproduce our results:

1. Visit [snort.org](https://snort.org) and create a free account.
1. Go to [Downloads > Rules](https://www.snort.org/downloads#rules) and download
   snapshot `3200` of the rules in the "Registered" column.
1. Clone our [`rebar` fork](https://github.com/epfl-systemf/rebar)
1. Extract the contents of the downloaded archive to a new directory called
   `snortrules-snapshot-3200` in the root of the cloned repo.
1. Check the script `benchmark_lookbehind.sh` for the prerequisites. If you are
   on a debian/ubuntu system, you can install them easily by running
   `./benchmark_lookbehind.sh --install` (requires root privileges).
1. Execute `./benchmark_lookbehind.sh` to run the benchmark.
1. Find the results in the files `results_full.csv` and
   `results_lookbehind.csv`, which are placed in the directory containing the
   rebar fork.

## Acknowledgements

This was a joint effort by @multimodcrafter and @shilangyu, supervised by [Aurèle Barrière](https://aurele-barriere.github.io) and [Clément Pit-Claudel](https://pit-claudel.fr/clement/) at EPFL's [SYSTEMF](https://systemf.epfl.ch/).
