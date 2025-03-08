# rust-lang/regex

## required steps

- Extend HIR with lookarounds
- Implement parsing support for lookarounds in regex-syntax
- Implement translation of AST to HIR for lookarounds
- Implement translation of HIR to NFA for lookarounds
- Implement lookaround algorithm for NFA
- Implement decision making in meta-engine for lookarounds
- Investigate prefilter impact on lookarounds

### HIR extension

`hir` values have a `HirKind` and some `Properties`.

`HirKind` already features a tuple variant `HirKind::Look` for simple
lookarounds. The `Look` enum is one of the few enums that makes use of explicit
`u32` representation and uses this for certain optimizations in a bit-flag style
manner. There are two options that come to mind on how to extend the HIR:

- Add a new variant to `HirKind` for complex lookarounds (what to call this?)
  ==> We decided to go this route and call it `LookAround` for now.
- ~~Wrap the simple lookaround variant in a new enum (do we reuse the name
  `Look`?)~~

We also need to deal with the `Properties` of the new HIR values. It features
fields like whether the value is a literal, it's minimum match length, etc.
These properties are computed when constructing the HIR values and are used
for optimization purposes. We need to make sure that we get these right so that
no semantically incorrect optimizations are performed.

### Parsing support

The in the `ast` module, `ErrorKind::UnsupportedLookAround` would need to be
replaced with `ErrorKind::UnsupportedLookAhead`. Additionally a new error
`ErrorKind::UnsupportedCaptureInLookBehind` would need to be added.

The `Ast`, similar to the `HirKind`, has an `Assertion` variant with a boxed
`Assertion` struct. Analogously to the change to the `hir`, a new variant is
added to the `Ast` enum, `LookAhead`. It contains the `span`, the `kind`
(positive/negative look-ahead/look-behind), and the inner expression `ast`. All
code matching on `Ast` has to be inspected to see how the new variant should be
handled.

The `ParserI::parse_group` function currently returns an `Either<,>` enum value,
being one of `SetFlags` or `Group`. We need to extend this to allow returning
Assertions values as well. Depending on whether the AST extension tracks if a
lookaround assertion contains capture groups or not, we must track this in the
parser too.

### Translation of AST to HIR

The `ast` module defines a `Visitor` trait that is used to traverse the AST.
The `hir` module has a `Translator` which implements the `Visitor` trait and
is used to perform the translation. Here, we need to extend at least the
`visit_pre` and `visit_post` methods to handle the new AST nodes.

### Translation of HIR to NFA

If we go the route of one large NFA combining all sub-NFAs for each lookaround,
We can use the `add_union` method of the NFA builder as this will prefer earlier
transitions.

To add the instructions for setting the lookaround state, we need to extend the
`State` enum in the builder. Furhtermore, we need to extend the `State` enum
in the NFA.

Somewhere, there will also be the code for reversing the NFA. We need to make
sure lookarounds are reversed properly.

### Lookaround algorithm

It might be possible to use the capture group slots for storing the lookaround
evaluation bit. This has the advantage that we would not need to keep track
of more state. The downside is that the semantics of the slots would be bloated.
After reading the documentation of `PikeVM::search_slots`, it seems that the
idea is probably quite bad, since the user of this api must provide the memory
corresponding to the "slots".

Writing to the datastructure that keeps track of the lookaround evaluation
will have to be done in the `PikeVM::epsilon_closure_explore` function.

### Decision making in meta-engine

The decision procedure is implemented in the `strategy::Core`. It looks as if
there is no need in updating this since all but the `PikeVM` engines should
either fail to build or fail to find matches as soon as they encounter
unsupported instructions. Of course it would probably be better for performance
to skip directly to the `PikeVM` whenever there are lookarounds in the regex.

### Prefilter adjustments

Prefilters for the default creation path of the meta-engine are selected
in the `strategy::new` function.

Some code for extracting prefilters is also located in
`meta::reverse_inner::extract` and the functions it calls. However, it might not
be necessary to change things there, as this seems to be a very low level api.
