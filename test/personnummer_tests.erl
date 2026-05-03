-module(personnummer_tests).

-include_lib("eunit/include/eunit.hrl").

-define(INTERIM_LETTERS, "TRSUWXJKLMN").
-define(ALPHABET, "ABCDEFGHIJKLMNOPQRSTUVWXYZ").

%%%=============================================================================
%%% Parsing
%%%=============================================================================

parse_long_format_test() ->
    {ok, P} = personnummer:parse(<<"198608134667">>),
    ?assertEqual({1986, 8, 13}, personnummer:get_date(P)).

parse_short_format_test() ->
    {ok, P} = personnummer:parse(<<"8608134667">>),
    ?assertEqual({1986, 8, 13}, personnummer:get_date(P)).

parse_short_with_dash_test() ->
    {ok, P} = personnummer:parse(<<"860813-4667">>),
    ?assertEqual({1986, 8, 13}, personnummer:get_date(P)).

parse_long_with_dash_test() ->
    {ok, P} = personnummer:parse(<<"19860813-4667">>),
    ?assertEqual({1986, 8, 13}, personnummer:get_date(P)).

parse_iolist_input_test() ->
    {ok, P} = personnummer:parse(["198608", <<"134667">>]),
    ?assertEqual({1986, 8, 13}, personnummer:get_date(P)).

parse_plus_separator_test() ->
    %% Person is over 100 years old -> '+' shifts back a century.
    {ok, P} = personnummer:parse(<<"090527+1474">>),
    ?assertEqual({1909, 5, 27}, personnummer:get_date(P)).

parse_invalid_format_test_() ->
    [
        ?_assertEqual({error, invalid_format}, personnummer:parse(<<"">>)),
        ?_assertEqual({error, invalid_format}, personnummer:parse(<<"abc">>)),
        ?_assertEqual({error, invalid_format}, personnummer:parse(<<"86081346670">>)),
        ?_assertEqual({error, invalid_format}, personnummer:parse(<<"19090527 1474">>))
    ].

parse_invalid_date_test_() ->
    [
        ?_assertEqual({error, invalid_date}, personnummer:parse(<<"198613134667">>)),
        ?_assertEqual({error, invalid_date}, personnummer:parse(<<"198602304667">>))
    ].

parse_invalid_check_test_() ->
    [
        ?_assertEqual({error, invalid_check}, personnummer:parse(<<"8608134668">>)),
        ?_assertEqual({error, invalid_check}, personnummer:parse(<<"198608134000">>))
    ].

%%%=============================================================================
%%% Accessors
%%%=============================================================================

accessors_test() ->
    {ok, P} = personnummer:parse(<<"198608134667">>),
    ?assertEqual({1986, 8, 13}, personnummer:get_date(P)),
    ?assertEqual(19, personnummer:get_century(P)),
    ?assertEqual(<<"466">>, personnummer:get_serial(P)),
    ?assertEqual(7, personnummer:get_check(P)),
    ?assertEqual(<<"-">>, personnummer:get_separator(P)).

accessors_centenarian_test() ->
    {ok, P} = personnummer:parse(<<"19090527+1474">>),
    ?assertEqual(19, personnummer:get_century(P)),
    ?assertEqual(<<"+">>, personnummer:get_separator(P)).

accessors_interim_test() ->
    {ok, P} = personnummer:parse(<<"20000101T220">>, #{allow_interim_number => true}),
    ?assertEqual(20, personnummer:get_century(P)),
    ?assertEqual(<<"T22">>, personnummer:get_serial(P)),
    ?assertEqual(0, personnummer:get_check(P)).

%%%=============================================================================
%%% Coordination numbers
%%%=============================================================================

coordination_number_default_allowed_test() ->
    {ok, P} = personnummer:parse(<<"197302889931">>),
    ?assertEqual({1973, 2, 28}, personnummer:get_date(P)),
    ?assert(personnummer:is_coordination_number(P)).

coordination_number_disallowed_test() ->
    Opts = #{allow_coordination_number => false},
    ?assertEqual(
        {error, coordination_number_not_allowed},
        personnummer:parse(<<"197302889931">>, Opts)
    ).

coordination_day_boundaries_test_() ->
    %% Day 60 is reserved (between regular max 31 and coordination min 61) so
    %% the date check rejects it before Luhn runs.
    %% Day 61 is the first coordination day -> real day 1.
    %% Day 91 is the last coordination day -> real day 31.
    [
        ?_assertEqual(
            {error, invalid_date}, personnummer:parse(<<"197302601111">>)
        ),
        fun() ->
            {ok, P} = personnummer:parse(<<"197301615550">>),
            ?assert(personnummer:is_coordination_number(P)),
            ?assertEqual({1973, 1, 1}, personnummer:get_date(P))
        end,
        fun() ->
            {ok, P} = personnummer:parse(<<"197301913336">>),
            ?assert(personnummer:is_coordination_number(P)),
            ?assertEqual({1973, 1, 31}, personnummer:get_date(P))
        end,
        %% Day 91 with February yields real day 31 -> calendar rejects.
        ?_assertEqual(
            {error, invalid_date}, personnummer:parse(<<"197302915555">>)
        )
    ].

coordination_gender_test() ->
    %% Coordination numbers use the same gender rule as regular pnrs:
    %% parity of the third digit of the four-digit suffix. 197302889931 has
    %% suffix 9931 -> third digit 3 -> male.
    {ok, P} = personnummer:parse(<<"197302889931">>),
    ?assert(personnummer:is_male(P)),
    ?assertNot(personnummer:is_female(P)).

%%%=============================================================================
%%% Interim numbers
%%%=============================================================================

interim_number_default_disallowed_test() ->
    ?assertEqual(
        {error, interim_number_not_allowed},
        personnummer:parse(<<"20000101T220">>)
    ).

interim_number_opt_in_test() ->
    Opts = #{allow_interim_number => true},
    {ok, P} = personnummer:parse(<<"20000101T220">>, Opts),
    ?assert(personnummer:is_interim_number(P)),
    ?assertEqual({2000, 1, 1}, personnummer:get_date(P)).

interim_number_invalid_letter_test_() ->
    %% Letters outside the documented set must be rejected by the regex,
    %% not silently accepted and replaced with 1 in the Luhn calculation.
    Opts = #{allow_interim_number => true},
    [
        {
            "reject letter " ++ [L],
            ?_assertEqual(
                {error, invalid_format},
                personnummer:parse(<<"20000101", L, "220">>, Opts)
            )
        }
     || L <- ?ALPHABET, not lists:member(L, ?INTERIM_LETTERS)
    ].

interim_number_lowercase_letter_test() ->
    %% Lowercase letters are accepted and normalized to uppercase.
    Opts = #{allow_interim_number => true},
    {ok, P} = personnummer:parse(<<"20000101t220">>, Opts),
    ?assert(personnummer:is_interim_number(P)),
    ?assertEqual(<<"000101-T220">>, personnummer:format(P)).

interim_all_letters_test_() ->
    %% Every documented interim letter must validate via the interim.json
    %% fixture, but exercise each individually here for a clear failure mode
    %% if a letter is dropped from the regex or Luhn substitution table.
    Opts = #{allow_interim_number => true},
    [
        {"interim letter " ++ [L], ?_assert(personnummer:valid(<<"20000101", L, "220">>, Opts))}
     || L <- ?INTERIM_LETTERS
    ].

%%%=============================================================================
%%% Validity
%%%=============================================================================

valid_test_() ->
    [
        ?_assert(personnummer:valid(<<"198608134667">>)),
        ?_assert(personnummer:valid(<<"860813-4667">>)),
        ?_assertNot(personnummer:valid(<<"8608134668">>)),
        ?_assertNot(personnummer:valid(<<"bogus">>))
    ].

%%%=============================================================================
%%% Formatting
%%%=============================================================================

format_default_short_test() ->
    {ok, P} = personnummer:parse(<<"198608134667">>),
    ?assertEqual(<<"860813-4667">>, personnummer:format(P)).

format_long_test() ->
    {ok, P} = personnummer:parse(<<"198608134667">>),
    ?assertEqual(<<"198608134667">>, personnummer:format(P, true)).

format_separator_for_centenarian_test() ->
    %% Person born in 1909 is older than 100, separator is '+'.
    {ok, P} = personnummer:parse(<<"19090527+1474">>),
    ?assertEqual(<<"090527+1474">>, personnummer:format(P)).

format_coordination_number_test() ->
    {ok, P} = personnummer:parse(<<"197302889931">>),
    ?assertEqual(<<"730288-9931">>, personnummer:format(P)),
    ?assertEqual(<<"197302889931">>, personnummer:format(P, true)).

format_interim_number_test() ->
    Opts = #{allow_interim_number => true},
    {ok, P} = personnummer:parse(<<"20000101T220">>, Opts),
    ?assertEqual(<<"000101-T220">>, personnummer:format(P)),
    ?assertEqual(<<"20000101T220">>, personnummer:format(P, true)).

roundtrip_test_() ->
    %% Format -> parse -> format should be a fixed point for any valid input.
    Inputs = [
        <<"198608134667">>,
        <<"19090527+1474">>,
        <<"197302889931">>
    ],
    [
        fun() ->
            {ok, P1} = personnummer:parse(In),
            Long = personnummer:format(P1, true),
            {ok, P2} = personnummer:parse(Long),
            ?assertEqual(personnummer:get_date(P1), personnummer:get_date(P2)),
            ?assertEqual(personnummer:format(P1), personnummer:format(P2)),
            ?assertEqual(Long, personnummer:format(P2, true))
        end
     || In <- Inputs
    ].

%%%=============================================================================
%%% Gender
%%%=============================================================================

gender_test_() ->
    [
        fun() ->
            {ok, P} = personnummer:parse(<<"198608134667">>),
            %% Last digit of serial is 6 -> female.
            ?assert(personnummer:is_female(P)),
            ?assertNot(personnummer:is_male(P))
        end,
        fun() ->
            {ok, P} = personnummer:parse(<<"19900101-0017">>),
            ?assert(personnummer:is_male(P)),
            ?assertNot(personnummer:is_female(P))
        end
    ].

%%%=============================================================================
%%% Age
%%%=============================================================================

get_age_test() ->
    {ok, P} = personnummer:parse(<<"198608134667">>),
    ?assertEqual(40, personnummer:get_age(P, {2026, 8, 13})),
    ?assertEqual(39, personnummer:get_age(P, {2026, 8, 12})),
    ?assertEqual(40, personnummer:get_age(P, {2027, 8, 12})).

%%%=============================================================================
%%% Compliance: drive structured.json from personnummer/meta
%%%=============================================================================

structured_json_test_() ->
    #{
        <<"ssn">> := #{<<"string">> := #{<<"valid">> := SsnValid, <<"invalid">> := SsnInvalid}},
        <<"con">> := #{<<"string">> := #{<<"valid">> := ConValid, <<"invalid">> := ConInvalid}}
    } = read_testdata("structured.json"),
    [
        {"ssn valid:" ++ binary_to_list(S), ?_assert(personnummer:valid(S))}
     || S <- SsnValid
    ] ++
        [
            {"ssn invalid:" ++ binary_to_list(S), ?_assertNot(personnummer:valid(S))}
         || S <- SsnInvalid
        ] ++
        [
            {"con valid:" ++ binary_to_list(S), ?_assert(personnummer:valid(S))}
         || S <- ConValid
        ] ++
        [
            {"con invalid:" ++ binary_to_list(S), ?_assertNot(personnummer:valid(S))}
         || S <- ConInvalid
        ].

list_json_test_() ->
    Entries = read_testdata("list.json"),
    lists:flatmap(fun list_json_entry_assertions/1, Entries).

list_json_entry_assertions(#{
    <<"valid">> := Valid,
    <<"long_format">> := Long,
    <<"short_format">> := Short,
    <<"separated_format">> := SepShort,
    <<"separated_long">> := SepLong,
    <<"isFemale">> := IsFemale,
    <<"isMale">> := IsMale
}) ->
    Inputs = [Long, Short, SepShort, SepLong],
    BasicCases = [
        {"valid " ++ binary_to_list(In), ?_assertEqual(Valid, personnummer:valid(In))}
     || In <- Inputs
    ],
    case Valid of
        true ->
            {ok, P} = personnummer:parse(SepLong),
            BasicCases ++
                [
                    {
                        "isFemale " ++ binary_to_list(SepLong),
                        ?_assertEqual(IsFemale, personnummer:is_female(P))
                    },
                    {
                        "isMale " ++ binary_to_list(SepLong),
                        ?_assertEqual(IsMale, personnummer:is_male(P))
                    },
                    {
                        "format short " ++ binary_to_list(SepLong),
                        ?_assertEqual(SepShort, personnummer:format(P))
                    },
                    {
                        "format long " ++ binary_to_list(SepLong),
                        ?_assertEqual(Long, personnummer:format(P, true))
                    }
                ];
        false ->
            BasicCases
    end.

interim_json_test_() ->
    Entries = read_testdata("interim.json"),
    lists:map(
        fun(#{<<"valid">> := Valid, <<"separated_long">> := In}) ->
            {
                "interim " ++ binary_to_list(In),
                ?_assertEqual(Valid, personnummer:valid(In, #{allow_interim_number => true}))
            }
        end,
        Entries
    ).

read_testdata(Name) ->
    Path = filename:join([filename:dirname(?FILE), "testdata", Name]),
    {ok, Bin} = file:read_file(Path),
    json:decode(Bin).
