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

End statements inside Perl blocks with semicolons, including the final
statement. Blocks for `grep`, `map`, `sort`, `sub`, `eval`, and `exec`
may omit the final semicolon if they contain exactly one statement.
Preserve existing semicolons in those blocks.

Use `eval { danger; 1; }` for operations that may fail and we do not
need the return value of, even if we are fairly confident that danger
returns a true value on success.

    eval { require $file; 1; }        # good
    eval { $mod->VERSION(0.01); 1; }  # likewise
    eval { $mod->VERSION(0.01); 1 }   # no!
    map { $_->name } @items           # good (single-statement exception)
    $pid = eval { open2(...) }        # likewise
