The AI initiative Marin at Stanford University has
nice [writing guidelines][marin].  Please refer to
them in the file here:

@ai/writing-style.md

Marin is licensed under Apache-2.0 License, in case
that is any relevant.

[marin]: https://github.com/marin-community/marin/blob/main/docs/dev-guide/writing-style/ai-writing-donts.md

## Testing

Run `../env.pl make test` from each package directory: `codesets`,
`textdomain`, `gengenlib`, `genlib`, `siteconf-l10n`,
`template-provider`, `siteconf`, `siteconf-ninja`, `siteconf-redo`, and `siteconf-task`. This rebuilds
`blib` and uses the workspace packages; direct `prove` runs can use
obsolete share directory (which holds the template files).

Before testing `siteconf-l10n`, run
`perl Makefile.PL LINGUAS='en zh'` in that directory so both language
catalogs are tested.

## Style

Ban parenthetical fragments unless they fit grammatically into the surrounding
sentence. A parenthetical that stands on its own must be a complete sentence;
its final period is optional. For example, `# (The catalog is optional)` is
allowed; `# (which is optional)` on its own is not. Avoid incoherent, indirect,
or unclear relative clauses. Do not inherit these parenthetical fragments or
relative clauses from surrounding code.

Prefer high-level comments that explain intent or constraints. Omit comments
that only restate the code.

Do not assume `version.pm` is already loaded. Load it explicitly before
using its API.

End statements inside Perl blocks with semicolons, including the final
statement. The following blocks may omit the final semicolon only when
they contain exactly one statement:

* `do` and `eval` whose value is used. Void-context blocks, including
  `A or do { ... }`, require the semicolon. The exception includes
  `do { ... } or A` and `do` used in a do-while loop.
* Blocks passed to higher-order functions that transform, search, or act
  on their operands, including `map`, `grep`, `sort`, `exec`, and functions
  with `&` prototypes. Examples include `any`/`all` from `List::Util` and
  `lower_bound`/`upper_bound`/`equal_range` binary searches. This exception
  does not apply to `try`/`catch` or ordinary subroutine definitions.

Preserve existing semicolons in exempt blocks. Count empty statements too:
`map {; { %$_ }; }` contains two statements and requires the final semicolon.

Use `eval { danger; 1; }` for operations that may fail and we do not
need the return value of, even if we are fairly confident that danger
returns a true value on success.

    eval { require $file; 1; }        # good
    eval { $mod->VERSION(0.01); 1; }  # likewise
    eval { $mod->VERSION(0.01); 1 }   # no!
    map { $_->name } @items           # good (single-statement exception)
    $pid = eval { open2(...) }        # likewise
