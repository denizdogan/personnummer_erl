-module(personnummer).

-moduledoc """
Validate, parse and format Swedish personal identity numbers (personnummer).

Implements the [personnummer specification
v3.1](https://github.com/personnummer/meta). Supports regular
personnummer, coordination numbers (samordningsnummer) and interim
numbers (T-numbers).

```erlang
{ok, Pnr} = personnummer:parse(<<"198608134667">>),
true = personnummer:valid(<<"198608134667">>),
<<"860813-4667">> = personnummer:format(Pnr),
<<"198608134667">> = personnummer:format(Pnr, true),
{1986, 8, 13} = personnummer:get_date(Pnr),
true = personnummer:is_female(Pnr).
```

Coordination numbers are accepted by default; interim numbers are
opt-in via the `t:options/0` map passed to `parse/2` or `valid/2`.
""".

-export([
    parse/1, parse/2,
    valid/1, valid/2,
    format/1, format/2,
    get_date/1,
    get_age/1, get_age/2,
    get_century/1,
    get_serial/1,
    get_check/1,
    get_separator/1,
    is_male/1,
    is_female/1,
    is_coordination_number/1,
    is_interim_number/1
]).

-export_type([personnummer/0, options/0, parse_error/0]).

-record(personnummer, {
    date :: calendar:date(),
    serial :: <<_:24>>,
    check :: 0..9,
    coordination :: boolean(),
    interim :: boolean()
}).

-doc "An opaque, validated personnummer. Construct with `parse/1,2`.".
-opaque personnummer() :: #personnummer{}.

-doc """
Options accepted by `parse/2` and `valid/2`.

- `allow_coordination_number` — default `true`. When `false`,
  coordination numbers (samordningsnummer) are rejected.
- `allow_interim_number` — default `false`. When `true`, interim
  numbers (T-numbers) are accepted.
""".
-type options() :: #{
    allow_coordination_number => boolean(),
    allow_interim_number => boolean()
}.

-doc "Reasons returned by `parse/1,2` on failure.".
-type parse_error() ::
    invalid_format
    | invalid_date
    | invalid_check
    | coordination_number_not_allowed
    | interim_number_not_allowed.

-define(DEFAULT_OPTIONS, #{
    allow_coordination_number => true,
    allow_interim_number => false
}).

-define(REGEX,
    "^(\\d{2})?(\\d{2})(\\d{2})(\\d{2})([-+]?)((?:[TRSUWXJKLMN]|\\d)\\d{2})(\\d)$"
).

%%%=============================================================================
%%% Public API
%%%=============================================================================

-doc #{equiv => parse / 2}.
-spec parse(iodata()) -> {ok, personnummer()} | {error, parse_error()}.
parse(Input) ->
    parse(Input, #{}).

-doc """
Parse a personnummer from `Input` using `Options`.

Accepts any of the canonical input formats: `YYMMDDXXXX`,
`YYMMDD-XXXX`, `YYMMDD+XXXX`, `YYYYMMDDXXXX`, `YYYYMMDD-XXXX`,
`YYYYMMDD+XXXX`. The `+` separator on a short input shifts the implied
century back by 100 years (used for people aged 100+).

Returns `{ok, Pnr}` on success or `{error, Reason}` where `Reason` is
a `t:parse_error/0`.
""".
-spec parse(iodata(), options()) ->
    {ok, personnummer()} | {error, parse_error()}.
parse(Input, Options) ->
    Bin = iolist_to_binary(Input),
    Opts = maps:merge(?DEFAULT_OPTIONS, Options),
    do_parse(Bin, Opts).

-doc #{equiv => valid / 2}.
-spec valid(iodata()) -> boolean().
valid(Input) ->
    valid(Input, #{}).

-doc "Return `true` if `Input` is a valid personnummer under `Options`.".
-spec valid(iodata(), options()) -> boolean().
valid(Input, Options) ->
    case parse(Input, Options) of
        {ok, _} -> true;
        {error, _} -> false
    end.

-doc #{equiv => format / 2}.
-spec format(personnummer()) -> binary().
format(Pnr) ->
    format(Pnr, false).

-doc """
Render `Pnr` in short or long form.

- `format(Pnr, false)` -> `<<"YYMMDD-XXXX">>`. The separator is `+`
  if the person is 100+ years old, otherwise `-`.
- `format(Pnr, true)`  -> `<<"YYYYMMDDXXXX">>` (no separator).

For coordination numbers the day is rendered as the stored day plus
60. For interim numbers the letter is preserved at the first of the
four-digit suffix.
""".
-spec format(personnummer(), boolean()) -> binary().
format(#personnummer{} = Pnr, false) ->
    short_format(Pnr);
format(#personnummer{} = Pnr, true) ->
    long_format(Pnr).

-doc """
Return the underlying birth date as a `t:calendar:date/0`.

For coordination numbers the returned day is the real day (input day
minus 60).
""".
-spec get_date(personnummer()) -> calendar:date().
get_date(#personnummer{date = Date}) ->
    Date.

-doc #{equiv => get_age / 2}.
-spec get_age(personnummer()) -> non_neg_integer().
get_age(Pnr) ->
    get_age(Pnr, erlang:date()).

-doc "Age in completed years on `OnDate`.".
-spec get_age(personnummer(), calendar:date()) -> non_neg_integer().
get_age(#personnummer{date = BirthDate}, OnDate) ->
    diff_years(BirthDate, OnDate).

-doc "Return the century portion of the birth year (e.g. `19` or `20`).".
-spec get_century(personnummer()) -> non_neg_integer().
get_century(#personnummer{date = {Y, _, _}}) ->
    Y div 100.

-doc """
Return the three-byte serial portion of the personnummer suffix.

For interim numbers the first byte is the interim letter; remaining
bytes are always digits.
""".
-spec get_serial(personnummer()) -> binary().
get_serial(#personnummer{serial = Serial}) ->
    Serial.

-doc "Return the Luhn check digit (`0..9`).".
-spec get_check(personnummer()) -> 0..9.
get_check(#personnummer{check = Check}) ->
    Check.

-doc """
Return the separator that the short form would use today: `<<"+">>` if
the person is at least 100 years old, `<<"-">>` otherwise.
""".
-spec get_separator(personnummer()) -> binary().
get_separator(Pnr) ->
    render_separator(Pnr).

-doc "Return `true` if the personnummer denotes a male person.".
-spec is_male(personnummer()) -> boolean().
is_male(Pnr) ->
    not is_female(Pnr).

-doc """
Return `true` if the personnummer denotes a female person.

Determined by the parity of the third digit of the four-digit suffix
(equivalently: the last digit of the three-digit serial). Even is
female, odd is male.
""".
-spec is_female(personnummer()) -> boolean().
is_female(#personnummer{serial = Serial}) ->
    binary:last(Serial) rem 2 =:= 0.

-doc "Return `true` if the personnummer is a coordination number.".
-spec is_coordination_number(personnummer()) -> boolean().
is_coordination_number(#personnummer{coordination = C}) -> C.

-doc "Return `true` if the personnummer is an interim (T-) number.".
-spec is_interim_number(personnummer()) -> boolean().
is_interim_number(#personnummer{interim = I}) -> I.

%%%=============================================================================
%%% Internal: parsing
%%%=============================================================================

do_parse(Bin, Opts) ->
    maybe
        {ok, {Century, YY, Month, RawDay, Sep, Serial, Check}} ?= match(Bin),
        ok ?= check_serial(Serial),
        {ok, Year} ?= resolve_year(Century, YY, Sep),
        {Day, Coordination} = decode_day(RawDay),
        Interim = is_interim_letter(binary:first(Serial)),
        ok ?= check_options(Coordination, Interim, Opts),
        Date = {Year, Month, Day},
        ok ?= check_date(Date),
        ok ?= check_luhn(YY, Month, RawDay, Serial, Check),
        {ok, #personnummer{
            date = Date,
            serial = Serial,
            check = Check,
            coordination = Coordination,
            interim = Interim
        }}
    end.

%% Serial 000 is reserved and not a valid personnummer.
check_serial(<<"000">>) -> {error, invalid_format};
check_serial(_) -> ok.

match(Bin) ->
    case re:run(Bin, ?REGEX, [{capture, all_but_first, binary}, caseless]) of
        {match, [Century, YY, Month, RawDay, Sep, Serial0, Check]} ->
            Serial = upper(Serial0),
            {ok, {
                Century,
                binary_to_integer(YY),
                binary_to_integer(Month),
                binary_to_integer(RawDay),
                Sep,
                Serial,
                binary_to_integer(Check)
            }};
        nomatch ->
            {error, invalid_format}
    end.

resolve_year(<<>>, YY, Sep) ->
    {Y, _, _} = erlang:date(),
    ThisCentury = Y div 100,
    Year0 = ThisCentury * 100 + YY,
    Year1 =
        if
            Year0 > Y -> Year0 - 100;
            true -> Year0
        end,
    Year =
        case Sep of
            <<"+">> -> Year1 - 100;
            _ -> Year1
        end,
    {ok, Year};
resolve_year(Century, YY, _Sep) ->
    {ok, binary_to_integer(Century) * 100 + YY}.

decode_day(DD) when DD >= 61, DD =< 91 -> {DD - 60, true};
decode_day(DD) -> {DD, false}.

is_interim_letter($T) -> true;
is_interim_letter($R) -> true;
is_interim_letter($S) -> true;
is_interim_letter($U) -> true;
is_interim_letter($W) -> true;
is_interim_letter($X) -> true;
is_interim_letter($J) -> true;
is_interim_letter($K) -> true;
is_interim_letter($L) -> true;
is_interim_letter($M) -> true;
is_interim_letter($N) -> true;
is_interim_letter(_) -> false.

check_options(true, _, #{allow_coordination_number := false}) ->
    {error, coordination_number_not_allowed};
check_options(_, true, #{allow_interim_number := false}) ->
    {error, interim_number_not_allowed};
check_options(_, _, _) ->
    ok.

check_date({Y, M, D}) ->
    case calendar:valid_date(Y, M, D) of
        true -> ok;
        false -> {error, invalid_date}
    end.

check_luhn(YY, Month, RawDay, Serial, Check) ->
    Digits = digits_for_luhn(YY, Month, RawDay, Serial),
    case luhn_check_digit(Digits) =:= Check of
        true -> ok;
        false -> {error, invalid_check}
    end.

%% First 9 digits used for Luhn check (yymmdd + 3-digit serial; interim letter
%% is replaced with 1).
digits_for_luhn(YY, Month, RawDay, <<A, B, C>>) ->
    [
        YY div 10,
        YY rem 10,
        Month div 10,
        Month rem 10,
        RawDay div 10,
        RawDay rem 10,
        interim_digit(A),
        interim_digit(B),
        interim_digit(C)
    ].

interim_digit(C) when C >= $0, C =< $9 -> C - $0;
interim_digit(_) -> 1.

luhn_check_digit(Digits) ->
    {Sum, _} = lists:foldl(
        fun(D, {Acc, Mult}) ->
            X = D * Mult,
            X1 =
                if
                    X >= 10 -> X - 9;
                    true -> X
                end,
            {Acc + X1, 3 - Mult}
        end,
        {0, 2},
        Digits
    ),
    (10 - Sum rem 10) rem 10.

%%%=============================================================================
%%% Internal: formatting
%%%=============================================================================

short_format(#personnummer{date = {Y, M, D}, serial = Serial, check = Check} = Pnr) ->
    YearBin = pad2(Y rem 100),
    MonthBin = pad2(M),
    DayBin = pad2(render_day(D, Pnr)),
    Sep = render_separator(Pnr),
    CheckBin = integer_to_binary(Check),
    <<YearBin/binary, MonthBin/binary, DayBin/binary, Sep/binary, Serial/binary, CheckBin/binary>>.

long_format(#personnummer{date = {Y, M, D}, serial = Serial, check = Check} = Pnr) ->
    YearBin = integer_to_binary(Y),
    MonthBin = pad2(M),
    DayBin = pad2(render_day(D, Pnr)),
    CheckBin = integer_to_binary(Check),
    <<YearBin/binary, MonthBin/binary, DayBin/binary, Serial/binary, CheckBin/binary>>.

render_day(D, #personnummer{coordination = true}) -> D + 60;
render_day(D, _) -> D.

%% '+' if person is at least 100 years old, otherwise '-'.
render_separator(Pnr) ->
    case get_age(Pnr) >= 100 of
        true -> <<"+">>;
        false -> <<"-">>
    end.

%%%=============================================================================
%%% Internal: misc
%%%=============================================================================

%% Only the first byte of a serial can be a letter (interim numbers); the
%% remaining two are always digits. Uppercase only that byte.
upper(<<C, Rest/binary>>) when C >= $a, C =< $z ->
    <<(C - 32), Rest/binary>>;
upper(B) ->
    B.

%% Render a 0..99 integer as a two-byte zero-padded binary.
pad2(N) when N < 10 -> <<$0, (integer_to_binary(N))/binary>>;
pad2(N) -> integer_to_binary(N).

diff_years({BY, BM, BD}, {Y, M, D}) ->
    Diff = Y - BY,
    case {M, D} < {BM, BD} of
        true -> Diff - 1;
        false -> Diff
    end.
