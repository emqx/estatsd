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

-ifdef(TEST).
-compile(export_all).
-compile(nowarn_export_all).
-endif.

-compile(inline).
-compile({inline_size, 150}).

-behaviour(gen_server).

-export([ start_link/0
        , start_link/1
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
        , submit/1
        ]).

-export([ init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        , code_change/3
        ]).

-record(state, {
          socket     :: inet:socket(),
          host       :: inet:hostname() | inet:ip_address(),
          port       :: inet:port_number(),
          prefix     :: prefix(),
          tags       :: tags(),
          batch_size :: pos_integer()
         }).

%%--------------------------------------------------------------------
%% APIs
%%--------------------------------------------------------------------

-spec start_link() -> {ok, pid()}.
start_link() ->
    start_link([]).

-spec start_link(Options) -> {ok, pid()}
    when Options :: [Option],
         Option :: {host, inet:hostname() | inet:ip_address()} |
                   {port, inet:port_number()} |
                   {prefix, prefix()} |
                   {tags, tags()} |
                   {batch_size, pos_integer()}.        
start_link(Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Opts], []).

-spec(stop() -> ok).
stop() ->
    gen_server:stop(?MODULE).

-spec counter(name(), value()) -> ok.
counter(Name, Value) ->
    counter(Name, Value, 1, []).

-spec counter(name(), value(), sample_rate()) -> ok.
counter(Name, Value, Rate) ->
    counter(Name, Value, Rate, []).

-spec counter(name(), value(), sample_rate(), tags()) -> ok.
counter(Name, Value, Rate, Tags) when is_integer(Value) ->
    submit({counter, Name, Value, Rate, Tags}).

-spec increment(name(), value()) -> ok.
increment(Name, Value) ->
    increment(Name, Value, 1, []).

-spec increment(name(), value(), sample_rate()) -> ok.
increment(Name, Value, Rate) ->
    increment(Name, Value, Rate, []).

-spec increment(name(), value(), sample_rate(), tags()) -> ok.
increment(Name, Value, Rate, Tags) when is_integer(Value) ->
    submit({counter, Name, Value, Rate, Tags}).

-spec decrement(name(), value()) -> ok.
decrement(Name, Value) ->
    decrement(Name, Value, 1, []).

-spec decrement(name(), value(), sample_rate()) -> ok.
decrement(Name, Value, Rate) ->
    decrement(Name, Value, Rate, []).

-spec decrement(name(), value(), sample_rate(), tags()) -> ok.
decrement(Name, Value, Rate, Tags) when is_integer(Value) ->
    submit({counter, Name, -Value, Rate, Tags}).

-spec gauge(name(), value()) -> ok.
gauge(Name, Value) ->
    gauge(Name, Value, 1, []).

-spec gauge(name(), value(), sample_rate()) -> ok.
gauge(Name, Value, Rate) ->
    gauge(Name, Value, Rate, []).

-spec gauge(name(), value(), sample_rate(), tags()) -> ok.
gauge(Name, Value, Rate, Tags) when is_number(Value) andalso Value >= 0 ->
    submit({gauge, Name, Value, Rate, Tags}).

-spec gauge_delta(name(), value()) -> ok.
gauge_delta(Name, Value) ->
    gauge_delta(Name, Value, 1, []).

-spec gauge_delta(name(), value(), sample_rate()) -> ok.
gauge_delta(Name, Value, Rate) ->
    gauge_delta(Name, Value, Rate, []).

-spec gauge_delta(name(), value(), sample_rate(), tags()) -> ok.
gauge_delta(Name, Value, Rate, Tags) when is_number(Value) ->
    submit({gauge_delta, Name, Value, Rate, Tags}).

-spec set(name(), value()) -> ok.
set(Name, Value) ->
    set(Name, Value, 1, []).

-spec set(name(), value(), sample_rate()) -> ok.
set(Name, Value, Rate) ->
    set(Name, Value, Rate, []).

-spec set(name(), value(), sample_rate(), tags()) -> ok.
set(Name, Value, Rate, Tags) when is_number(Value) ->
    submit({set, Name, Value, Rate, Tags}).

-spec timing(name(), value() | function()) -> ok.
timing(Name, ValueOrFunc) ->
    timing(Name, ValueOrFunc, 1, []).

-spec timing(name(), value() | function(), sample_rate()) -> ok.
timing(Name, ValueOrFunc, Rate) ->
    timing(Name, ValueOrFunc, Rate, []).

-spec timing(name(), value() | function(), sample_rate(), tags()) -> ok.
timing(Name, Func, Rate, Tags) when is_function(Func) ->
    Start = erlang:system_time(millisecond),
    Func(),
    timing(Name, erlang:system_time(millisecond) - Start, Rate, Tags);

timing(Name, Value, Rate, Tags) when is_number(Value) ->
    submit({timing, Name, Value, Rate, Tags}).

-spec histogram(name(), value()) -> ok.
histogram(Name, Value) ->
    histogram(Name, Value, 1, []).

-spec histogram(name(), value(), sample_rate()) -> ok.
histogram(Name, Value, Rate) ->
    histogram(Name, Value, Rate, []).

-spec histogram(name(), value(), sample_rate(), tags()) -> ok.
histogram(Name, Value, Rate, Tags) when is_number(Value) ->
    submit({histogram, Name, Value, Rate, Tags}).


-spec submit(Metrics) -> ok
    when Metrics :: Metric | [Metric],
         Metric :: {counter | gauge | gauge_delta | timing | histogram | set, name(), value(), sample_rate(), tags()}.
submit(Metrics) when is_list(Metrics) ->
    ShouldSubmit = lists:filter(fun({_, _, _, SampleRate, _}) ->
                                    SampleRate >= 1 orelse rand:uniform(100) =< erlang:trunc(SampleRate * 100)
                                end, Metrics),
    gen_server:cast(?MODULE, {submit, ShouldSubmit});

submit({Type, Name, Value, SampleRate, Tags}) ->
    case SampleRate >= 1 orelse rand:uniform(100) =< erlang:trunc(SampleRate * 100) of
        true ->
            gen_server:cast(?MODULE, {submit, {Type, Name, Value, SampleRate, Tags}});
        false ->
            ok
    end.

%%--------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------

init([Opts]) ->
    Host = proplists:get_value(host, Opts, ?DEFAULT_HOST),
    Port = proplists:get_value(port, Opts, ?DEFAULT_PORT),
    Prefix = proplists:get_value(prefix, Opts, ?DEFAULT_PREFIX),
    Tags = proplists:get_value(tags, Opts, ?DEFAULT_TAGS),
    BatchSize = proplists:get_value(batch_size, Opts, ?DEFAULT_BATCH_SIZE),

    case gen_udp:open(0, [{active, false}]) of
        {ok, Socket} ->
            {ok, #state{socket = Socket,
                        host = Host,
                        port = Port,
                        prefix = prefix(Prefix),
                        tags = Tags,
                        batch_size = BatchSize}};
        {error, Reason} ->
            {stop, Reason}
    end.

handle_call(_Req, _From, State) ->
    {reply, ignored, State}.

handle_cast({submit, Metrics}, #state{socket     = Socket,
                                         host       = Host,
                                         port       = Port,
                                         prefix     = Prefix,
                                         tags       = ConstantTags,
                                         batch_size = BatchSize} = State) ->
    NMetrics = drain_metrics(BatchSize - 1, case Metrics of
                                                Metrics when is_list(Metrics) -> Metrics;
                                                _ -> [Metrics]
                                            end),
    Packets = lists:foldr(fun({Type, Name, Value, SampleRate, Tags}, Acc) ->
                              Packet = estatsd_protocol:encode(Type, Name, Value, SampleRate, Tags ++ ConstantTags),
                              case Acc of
                                  [] ->
                                      [Prefix, Packet];
                                  _ ->
                                      [Prefix, Packet, "\n" | Acc]
                              end
                          end, [], NMetrics),
    gen_udp:send(Socket, Host, Port, Packets),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{socket = Socket}) ->
    gen_udp:close(Socket).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

prefix(hostname) ->
    [hostname(), $.];
prefix(name) ->
    [name(), $.];
prefix(sname) ->
    [sname(), $.];
prefix(undefined) ->
    "";
prefix(Name) when is_binary(Name) ->
    [Name, $.];
prefix([]) ->
    [];
prefix([H | T] = Name) ->
    case io_lib:printable_unicode_list(Name) of
        true ->
            [Name, $.];
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

drain_metrics(0, Acc) ->
    lists:reverse(Acc);
drain_metrics(Cnt, Acc) ->
    receive
        {'$gen_cast', {submit, Submission}} ->
            drain_metrics(Cnt - 1, [Submission | Acc])
    after 0 ->
        lists:reverse(Acc)
    end.