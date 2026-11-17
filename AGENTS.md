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
`template-provider`, and `siteconf`. This rebuilds
`blib` and uses the workspace packages; direct `prove` runs can use
obsolete share directory (which holds the template files).

Before testing `siteconf-l10n`, run
`perl Makefile.PL LINGUAS='en zh'` in that directory so both language
catalogs are tested.
