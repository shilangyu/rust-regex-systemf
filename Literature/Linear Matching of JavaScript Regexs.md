[Paper](https://aurele-barriere.github.io/papers/linearjs.pdf)
Algorithmic complexity blowup is security relevant due to DoS attacks.

RQ:
-  which part of javascript regex can be matched in linear time
- is linearity achievable in both the regex and the string
- to what extent do the semantic choices have an impact on which features are matchable in linear time

Javascript peculiarities:
- when a quantifier is applied to something that contains capture groups, "entering" that quantifier will reset all contain capture groups to _undefined_.
- optional iterations of a quantifier are not allowed to match the empty string (so called non-nullable)

solutions for matching peculiarities in linear time
- add begin loop and end loop instructions and track a boolean value per thread that indicates whether or not the current thread has consumed characters. when encountering end loop instructions, check if character consumed and abort the thread if not
- add a global clock that is incremented upon each instruction executed. Each capture group register is extended by a clock value and each quantifier is also added as a clock value register. Once terminated, clear each capture group that has a smaller clock value than any of its enclosing quantifiers.

Additional solutions:
- Matching arbitrary lookarounds in linear time with oracles (uses additional space complexity of $\mathcal{O}(l(r)\times|s|)$)
- Matching lookbehinds without capture groups using NFA simulation that proceeds in lockstep with main expression