-module(estatsd_protocol).

-include("estatsd.hrl").

-compile(inline).
-compile({inline_size, 150}).

-export([encode/5]).

%%--------------------------------------------------------------------
%% APIs
%%--------------------------------------------------------------------

encode(Type, Key, Value, SampleRate, Tags) ->
    [Key, <<":">>, encode_value(Type, Value), <<"|">>, encode_type(Type), encode_sample_rate(SampleRate), encode_tags(Tags)].

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

encode_value(Type, Value) when Type =:= gauge_delta andalso Value >= 0 ->
    [<<"+">>, encode_value(Value)];
encode_value(Type, Value) when (Type =:= gauge orelse Type =:= timing orelse Type =:= set) andalso Value < 0 ->
    error({bad_value, Value});
encode_value(_, Value) ->
    encode_value(Value).

encode_value(Value) when is_integer(Value) ->
    integer_to_list(Value);
encode_value(Value) when is_float(Value) ->
    float_to_list(Value, [{decimals, 2}]).

encode_type(counter) ->
    <<"c">>;
encode_type(gauge) ->
    <<"g">>;
encode_type(gauge_delta) ->
    <<"g">>;
encode_type(timing) ->
    <<"t">>;
encode_type(set) ->
    <<"s">>;
encode_type(Type) ->
    error({bad_type, Type}).

encode_sample_rate(SampleRate) when SampleRate >= 1 ->
    <<>>;
encode_sample_rate(SampleRate) ->
    [<<"|@">>, float_to_list(SampleRate, [compact, {decimals, 6}])].

encode_tags(Tags) ->
    encode_tags(Tags, []).

encode_tags([], Acc) ->
    Acc;
encode_tags([{Key, Value} | More], Acc) ->
    encode_tags(More, [[to_string(Key), to_string(Value)] | Acc]).

to_string(Atom) when is_atom(Atom) ->
    atom_to_binary(Atom, utf8);
to_string(Integer) when is_integer(Integer) ->
    integer_to_binary(Integer);
to_string(List) when is_list(List) ->
    List;
to_string(Binary) when is_binary(Binary) ->
    Binary;
to_string(Item) ->
    error({bad_data_type, Item}).
