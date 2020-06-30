%%--------------------------------------------------------------------
%% Copyright (c) 2020 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(estatsd).

-include("estatsd.hrl").

-compile(inline).
-compile({inline_size, 150}).

-behaviour(gen_server).

-export([ start_link/1
        , stop/0
        ]).

-export([ counter/2
        , counter/3
        , counter/4
        , increment/2
        , increment/3
        , increment/4
        , decrement/2
        , decrement/3
        , decrement/4
        , gauge/2
        , gauge/3
        , gauge/4
        , gauge_delta/2
        , gauge_delta/3
        , gauge_delta/4
        , set/2
        , set/3
        , set/4
        , timing/2
        , timing/3
        , timing/4
        , histogram/2
        , histogram/3
        , histogram/4
        ]).

-export([ init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        , code_change/3
        ]).

-record(state, {
          prefix     :: iodata(),
          socket     :: inet:socket(),
          batch_size :: pos_integer()
         }).

%%--------------------------------------------------------------------
%% APIs
%%--------------------------------------------------------------------

% -spec start_link(atom(), options()) -> {ok, pid()}.
start_link(Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Opts], []).

-spec(stop() -> ok).
stop() ->
    gen_server:stop(?MODULE).

counter(Metric, Value) ->
    counter(Metric, Value, 1, []).

-spec counter(key(), value(), sample_rate()) -> ok.
counter(Metric, Value, Rate) ->
    counter(Metric, Value, Rate, []).

-spec counter(key(), value(), sample_rate(), tags()) -> ok.
counter(Metric, Value, Rate, Tags) when is_integer(Value) ->
    submit(counter, Metric, Value, Rate, Tags).

increment(Metric, Value) ->
    increment(Metric, Value, 1, []).

-spec increment(key(), value(), sample_rate()) -> ok.
increment(Metric, Value, Rate) ->
    increment(Metric, Value, Rate, []).

increment(Metric, Value, Rate, Tags) when is_integer(Value) ->
    submit(counter, Metric, Value, Rate, Tags).

decrement(Metric, Value) ->
    decrement(Metric, Value, 1, []).

-spec decrement(key(), value(), sample_rate()) -> ok.
decrement(Metric, Value, Rate) ->
    decrement(Metric, Value, Rate, []).

decrement(Metric, Value, Rate, Tags) when is_integer(Value) ->
    submit(counter, Metric, -Value, Rate, Tags).

gauge(Metric, Value) ->
    gauge(Metric, Value, 1, []).

-spec gauge(key(), value(), sample_rate()) -> ok.
gauge(Metric, Value, Rate) ->
    gauge(Metric, Value, Rate, []).

gauge(Metric, Value, Rate, Tags) when is_number(Value) andalso Value >= 0 ->
    submit(gauge, Metric, Value, Rate, Tags).

gauge_delta(Metric, Value) ->
    gauge_delta(Metric, Value, 1, []).

-spec gauge_delta(key(), value(), sample_rate()) -> ok.
gauge_delta(Metric, Value, Rate) ->
    gauge_delta(Metric, Value, Rate, []).

gauge_delta(Metric, Value, Rate, Tags) when is_number(Value) ->
    submit(gauge_delta, Metric, Value, Rate, Tags).

set(Metric, Value) ->
    set(Metric, Value, 1, []).

set(Metric, Value, Rate) ->
    set(Metric, Value, Rate, []).

set(Metric, Value, Rate, Tags) when is_number(Value) ->
    submit(set, Metric, Value, Rate, Tags).

timing(Metric, ValueOrFunc) ->
    timing(Metric, ValueOrFunc, 1, []).

timing(Metric, ValueOrFunc, Rate) ->
    timing(Metric, ValueOrFunc, Rate, []).

timing(Metric, Func, Rate, Tags) when is_function(Func) ->
    Start = erlang:system_time(millisecond),
    Func(),
    timing(Metric, erlang:system_time(millisecond) - Start, Rate, Tags);

timing(Metric, Value, Rate, Tags) when is_number(Value) ->
    submit(timing, Metric, Value, Rate, Tags).

histogram(Metric, Value) ->
    histogram(Metric, Value, 1, []).

histogram(Metric, Value, Rate) ->
    histogram(Metric, Value, Rate, []).

histogram(Metric, Value, Rate, Tags) when is_number(Value) ->
    submit(histogram, Metric, Value, Rate, Tags).

submit(Type, Metric, Value, SampleRate, Tags) when SampleRate =< 1 ->
    case SampleRate =:= 1 orelse rand:uniform(100) > erlang:trunc(SampleRate * 100) of
        true ->
            Packet = estatsd_protocol:encode(Type, Metric, Value, SampleRate, Tags),
            gen_server:cast(?MODULE, {submit, Packet});
        false ->
            ok
    end;
submit(_, _, _, SampleRate, _) ->
    error({bad_sample_rate, SampleRate}).

%%--------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------

init(Opts) ->
    Prefix = proplists:get_value(prefix, Opts, ?DEFAULT_PREFIX),
    Hostname = proplists:get_value(hostname, Opts, ?DEFAULT_HOSTNAME),
    Port = proplists:get_value(port, Opts, ?DEFAULT_PORT),
    BatchSize = proplists:get_value(batch_size, Opts, ?DEFAULT_BATCH_SIZE),

    case gen_udp:open(0, [{active, false}]) of
        {ok, Socket} ->
            gen_udp:connect(Socket, Hostname, Port),
            {ok, #state{prefix = prefix(Prefix),
                        socket = Socket,
                        batch_size = BatchSize}};
        {error, Reason} ->
            {stop, Reason}
    end.

handle_call(_Req, _From, State) ->
    {reply, ignored, State}.

handle_cast({submit, Packet}, #state{prefix     = Prefix,
                                     socket     = Socket,
                                     batch_size = BatchSize} = State) ->
    Packets = drain_submits(BatchSize, Prefix),
    gen_udp:send(Socket, [Prefix, Packet, "\n" | Packets]),
    {ok, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

-spec prefix(prefix()) -> iodata().
prefix(hostname) ->
    [hostname(), $.];
prefix(name) ->
    [name(), $.];
prefix(sname) ->
    [sname(), $.];
prefix(undefined) ->
    "";
prefix(Metric) when is_binary(Metric) ->
    [Metric, $.];
prefix([]) ->
    [];
prefix([H | T] = Metric) ->
    case io_lib:printable_unicode_list(Metric) of
        true ->
            [Metric, $.];
        false ->
            [prefix(H) | prefix(T)]
    end.

hostname() ->
    {ok, Hostname} = inet:gethostname(),
    Hostname.

name() ->
    atom_to_list(node()).

sname() ->
    string:sub_word(atom_to_list(node()), 1, $@).

drain_submits(Cnt, Prefix) ->
    drain_submits(Cnt, Prefix, []).

drain_submits(0, _, Acc) ->
    Acc;
drain_submits(Cnt, Prefix, Acc) ->
    receive
        {'$gen_cast', {submit, Packet}} ->
            drain_submits(Cnt - 1, Prefix, [Prefix, Packet, "\n" | Acc])
    after 0 ->
        Acc
    end.