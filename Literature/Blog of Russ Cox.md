[Part 1](https://swtch.com/~rsc/regexp/regexp1.html)
"standard" regular expression matching can have pathological cases in which runtime is exponential. Thompson NFA implementation does not have these cases.

Regular expressions can be matched in linear time with constant amount of memory. However, when adding backreferences, the expression is not regular anymore; it is more powerful and the best known implementation has worstcase exponential runtime (it is NP-complete). However, when the input regex does _not_ have backreferences, then linear matching should be employed.

Regexes and NFAs are equivalent and there is a simple NFA construction process that uses a simple pattern for each regex concept (character, concatenation, alternation, ?, \*, +)

Simulating NFAs naively involves backtracking and thus exponential runtime. To get linear time, one must track all possible states the NFA could be in at any moment and advance each of them for every character read.

A further optimization is to cache the list of current NFA states and thereby effectively computing the equivalent DFA but only the states that are actually needed.

[Part 2](https://swtch.com/~rsc/regexp/regexp2.html)
Regex matching can be modelled as a virtual machine with a very limited instruction set: char x, split x y, jmp x, match.

One way to implement such a VM is using backtracking; leading to worst case exponential runtime.

Thompson's implementation runs different threads in lockstep, leading to linear runtime.

When subexpressions should be matched "separately" in the sense that start and end of each subexpression match should be known, the VM can be extended with the save i instruction, which saves a position in the thread context.

To implement greedy and non-greedy behaviour of \*, + and ?, one simply has to make sure the order of the threads in split x y is correct and that the thread x has priority over thread y.

POSIX submatching rules are different from the Perl greedy vs non greedy. They are 'easier to state but harder to implement', though it is possible to implement them in linear time with bounded state.