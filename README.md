# personnummer

[![CI](https://github.com/denizdogan/personnummer_erl/actions/workflows/erlang.yml/badge.svg)](https://github.com/denizdogan/personnummer_erl/actions/workflows/erlang.yml)
[![codecov](https://codecov.io/gh/denizdogan/personnummer_erl/branch/main/graph/badge.svg)](https://codecov.io/gh/denizdogan/personnummer_erl)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Validate, parse and format Swedish personal identity numbers
(personnummer) in Erlang/OTP. Implements the
[personnummer specification v3.1](https://github.com/personnummer/meta).

Supports:

- Regular personnummer (`YYMMDD-XXXX`, `YYYYMMDD-XXXX`, `+` separator
  for ages 100+)
- Coordination numbers (samordningsnummer, day = real day + 60)
- Interim numbers (T-numbers, opt-in via options map)

## Installation

Once published to Hex, add to `rebar.config`:

```erlang
{deps, [{personnummer_erl, "3.1.0"}]}.
```

Until then, depend on the GitHub source:

```erlang
{deps, [
    {personnummer_erl,
        {git, "https://github.com/denizdogan/personnummer_erl.git",
            {branch, "main"}}}
]}.
```

Requires Erlang/OTP 27 or newer.

## Quick start

```erlang
{ok, Pnr} = personnummer:parse(<<"198608134667">>),

true = personnummer:valid(<<"198608134667">>),
<<"860813-4667">> = personnummer:format(Pnr),
<<"198608134667">> = personnummer:format(Pnr, true),
{1986, 8, 13} = personnummer:get_date(Pnr),
19 = personnummer:get_century(Pnr),
<<"466">> = personnummer:get_serial(Pnr),
7 = personnummer:get_check(Pnr),
<<"-">> = personnummer:get_separator(Pnr),
true = personnummer:is_female(Pnr),
false = personnummer:is_coordination_number(Pnr),
false = personnummer:is_interim_number(Pnr).
```

## Options

```erlang
%% Reject coordination numbers (samordningsnummer).
personnummer:parse(Input, #{allow_coordination_number => false}).

%% Accept interim numbers (T-numbers). Disabled by default.
personnummer:parse(<<"20000101T220">>, #{allow_interim_number => true}).
```

Defaults: `allow_coordination_number => true`,
`allow_interim_number => false`.

## Compliance

The test suite is driven by JSON fixtures vendored from
[personnummer/meta](https://github.com/personnummer/meta/tree/master/testdata).
See [test/testdata/README.md](test/testdata/README.md) for refresh
instructions.

## Development

This project uses [Mise](https://mise.jdx.dev/) for tool versions and
task running.

```console
$ mise compile
$ mise test
$ mise format     # apply erlfmt
$ mise check      # fmt-check, eunit, dialyzer
$ mise eq-all     # eqwalizer (requires `elp` on PATH)
$ mise cover      # test coverage report
$ mise docs       # ex_doc
```

CI runs `mise check` plus codecov upload on OTP 27 and 28.

### Conventions

- Formatting: [`erlfmt`](https://github.com/whatsapp/erlfmt) — CI
  enforces with `rebar3 fmt --check`.
- Type checking: dialyzer must report 0 warnings; eqwalizer must
  report `NO ERRORS` (run via [`elp`](https://github.com/WhatsApp/erlang-language-platform)).
- Tests: prefer one focused EUnit function per behavior. The
  compliance suite is driven by JSON fixtures vendored from
  [personnummer/meta](https://github.com/personnummer/meta); refresh
  with `mise refresh-testdata`.
- Changelog: describe user-facing changes under `[Unreleased]` in
  [CHANGELOG.md](CHANGELOG.md).

### Releasing

1. Bump `vsn` in `src/personnummer.app.src` and convert the
   `[Unreleased]` heading in `CHANGELOG.md` to the new version. Commit
   and push.
2. Run `mise check` to confirm everything is green.
3. Run `mise publish`. This publishes to Hex (requires
   `rebar3 hex user auth` once), tags `vX.Y.Z`, and pushes the tag.

## License

[MIT](LICENSE)
