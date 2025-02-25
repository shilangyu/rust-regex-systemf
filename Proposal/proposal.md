# New matching algorithms for Rust regexes

## Abstract

Modern regexes have features that allow one to express more than what actually
constitutes regular languages. This leads to matching engines supporting the
full set of regexes to have exponential worst case running time. As this fact
has been abused for DoS attacks, engines with worst case linear running time
were developed, which do not support the full set of modern regexes. However,
as previous research has shown, the supported set of regexes is more restrictive
than necessary. The goal of our project is to implement these findings in the
regex (and potentially fancy-regex) crates for the rust language.

## Introduction

Regexes have become a ubiquitous feature, whether that is for manual searching
in text editors or to validate user input in a program. The latter specifically,
however, is potentially susceptible to DoS attacks when the regex engine has
exponential worst case runtime complexity. This has been dubbed ReDoS[^owasp]
and lead to applications seeking to use regex engines that promise worst case
linear runtime complexity.

Modern regexes have certain features that cannot possibly be supported by a
linear runtime regex engine. One example are backreferences. However, as
previous research has shown[^lire], certain
features that are currently not offered by many linear time engines, can in
fact be implemented in a way that preserves linear time complexity. One such
feature are look-arounds without capture groups.

Some other features, like look-arounds _with_ capture groups, are only linear
time compatible under particular assumptions about the semantics of the regex.

Due to the increased flexibility with additional regex features, it is desirable
that popular regex engines support as many of them as possible, and in
particular that linear engines do not limit the set of allowed regexes further
than necessary.
[^owasp]: [OWASP ReDoS](https://owasp.org/www-community/attacks/Regular_expression_Denial_of_Service_-_ReDoS)

[^lire]: [Linear regex matching](https://aurele-barriere.github.io/papers/linearjs.pdf)

## Proposal

The primary target of this project is to extend the regex engine of the
rust language by means of the crate [regex](https://github.com/rust-lang/regex).
An additional target could be the
[fancy-regex](https://github.com/fancy-regex/fancy-regex) crate, though this
crate currently supports a large set of regex features already, but uses
algorithms with exponential time complexity. Thus, for this crate the
contribution would merely be an improvement in complexity but not an addition
of an unsupported feature.

Our main goal is to implement capture-less look-behinds for the regex crate.
This will include:

- understanding the current architecture of the crate
- implementing the necessary changes to support the algorithm and the algorithm
  itself
- extending the parser to support the syntax for look-behinds
- polishing and documenting the implementation to the current standard of the
  crate to maximize chances of a merge

Depending on how quickly the changes can be implemented, the following list
serves as a reference for potential stretch goals of the project:

- Implementing capture-less look-aheads and potentially even general
  look-arounds including capture groups
- Analyzing the different algorithms in the regex crate for compatibility with
  look-arounds apart from the PikeVM for which compatibility is known
- Implementing an API to allow choice of data-structure for capture group
  tracking, enabling the user to choose from a time-space-complexity trade-off
  as presented in section 4.6 of
  [Linear regex matching](https://aurele-barriere.github.io/papers/linearjs.pdf)
- Exploring algorithms that allow for matching regex intersections as presented
  in [RE#](https://www.microsoft.com/en-us/research/uploads/prod/2025/01/popl25-p2-final.pdf)

## Timeline

| Week    | Task                                                                                                |
| ------- | --------------------------------------------------------------------------------------------------- |
| 1       | Background reading, proposal and presentation preparation                                           |
| 2 - 3   | Familiarizing with codebase of regex and fancy-regex crates, coming up with implementation strategy |
| 4 - 7   | Implementing capture-less look-behinds                                                              |
| 8 - 9   | Polishing and documenting implementation                                                            |
| 10 - 13 | Exploring stretch goals                                                                             |
| 14      | Finishing up, writing report                                                                        |

## Related work

The theoretical results and implementation in the V8 Javascript engine are the
works of Clément Pit-Claudel, Aurèle Barrière, and Ludovic Mermod as presented in
[Linear regex matching](https://aurele-barriere.github.io/papers/linearjs.pdf).
Our main goal will be porting these results to rust.

Furthermore, Erik Giorgis has implemented the same algorithms in a fork of RE2.
This work is presented in [this blogpost](https://systemf.epfl.ch/blog/re2-lookbehinds/)
of the SystemF group.

In case we decide to pursue the regex intersection matching, we would orient
ourselves on the results presented by Varatalu et al. in [RE#](https://www.microsoft.com/en-us/research/uploads/prod/2025/01/popl25-p2-final.pdf)
