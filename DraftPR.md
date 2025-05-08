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

`PikeVM`s cache has been expanded to preserve good performance of single-match
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

## Performance

We forked [`rebar`](https://github.com/epfl-systemf/rebar) and added a new engine
definition for our fork of `regex`. We added this new engine definition to all
benchmarks where `rust/regex` was already present. Furthermore, we added our own
set of benchmarks to measure the performance of the look-behind algorithm.

To get an estimate for performance of 'real-world regexes' using look-behinds,
we extracted all regexes that contain look-behind expressions from the `snort`
ruleset. Unfortunately, this ruleset is licensed in a way that prohibits us from
distributing it. Please follow these instructions to reproduce our results:

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
1. Find the results in the files `results_full.csv` and `results_lookbehind.csv`,
   which are placed in the directory containing the rebar fork.

## Future Work

We would love to get feedback on the implementation.

The next steps are to work on the current limitations. Namely, implement support
in more engines and enable prefilters. Additionally, support for look-aheads
would be implemented if the additional memory cost is acceptable.

We are open to the discussion about any of the above.
