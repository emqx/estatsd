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

-spec counter(metric(), value()) -> ok.
counter(Metric, Value) ->
    counter(Metric, Value, 1, []).

-spec counter(metric(), value(), sample_rate()) -> ok.
counter(Metric, Value, Rate) ->
    counter(Metric, Value, Rate, []).

-spec counter(metric(), value(), sample_rate(), tags()) -> ok.
counter(Metric, Value, Rate, Tags) when is_integer(Value) ->
    submit(counter, Metric, Value, Rate, Tags).

-spec increment(metric(), value()) -> ok.
increment(Metric, Value) ->
    increment(Metric, Value, 1, []).

-spec increment(metric(), value(), sample_rate()) -> ok.
increment(Metric, Value, Rate) ->
    increment(Metric, Value, Rate, []).

-spec increment(metric(), value(), sample_rate(), tags()) -> ok.
increment(Metric, Value, Rate, Tags) when is_integer(Value) ->
    submit(counter, Metric, Value, Rate, Tags).

-spec decrement(metric(), value()) -> ok.
decrement(Metric, Value) ->
    decrement(Metric, Value, 1, []).

-spec decrement(metric(), value(), sample_rate()) -> ok.
decrement(Metric, Value, Rate) ->
    decrement(Metric, Value, Rate, []).

-spec decrement(metric(), value(), sample_rate(), tags()) -> ok.
decrement(Metric, Value, Rate, Tags) when is_integer(Value) ->
    submit(counter, Metric, -Value, Rate, Tags).

-spec gauge(metric(), value()) -> ok.
gauge(Metric, Value) ->
    gauge(Metric, Value, 1, []).

-spec gauge(metric(), value(), sample_rate()) -> ok.
gauge(Metric, Value, Rate) ->
    gauge(Metric, Value, Rate, []).

-spec gauge(metric(), value(), sample_rate(), tags()) -> ok.
gauge(Metric, Value, Rate, Tags) when is_number(Value) andalso Value >= 0 ->
    submit(gauge, Metric, Value, Rate, Tags).

-spec gauge_delta(metric(), value()) -> ok.
gauge_delta(Metric, Value) ->
    gauge_delta(Metric, Value, 1, []).

-spec gauge_delta(metric(), value(), sample_rate()) -> ok.
gauge_delta(Metric, Value, Rate) ->
    gauge_delta(Metric, Value, Rate, []).

-spec gauge_delta(metric(), value(), sample_rate(), tags()) -> ok.
gauge_delta(Metric, Value, Rate, Tags) when is_number(Value) ->
    submit(gauge_delta, Metric, Value, Rate, Tags).

-spec set(metric(), value()) -> ok.
set(Metric, Value) ->
    set(Metric, Value, 1, []).

-spec set(metric(), value(), sample_rate()) -> ok.
set(Metric, Value, Rate) ->
    set(Metric, Value, Rate, []).

-spec set(metric(), value(), sample_rate(), tags()) -> ok.
set(Metric, Value, Rate, Tags) when is_number(Value) ->
    submit(set, Metric, Value, Rate, Tags).

-spec timing(metric(), value() | function()) -> ok.
timing(Metric, ValueOrFunc) ->
    timing(Metric, ValueOrFunc, 1, []).

-spec timing(metric(), value() | function(), sample_rate()) -> ok.
timing(Metric, ValueOrFunc, Rate) ->
    timing(Metric, ValueOrFunc, Rate, []).

-spec timing(metric(), value() | function(), sample_rate(), tags()) -> ok.
timing(Metric, Func, Rate, Tags) when is_function(Func) ->
    Start = erlang:system_time(millisecond),
    Func(),
    timing(Metric, erlang:system_time(millisecond) - Start, Rate, Tags);

timing(Metric, Value, Rate, Tags) when is_number(Value) ->
    submit(timing, Metric, Value, Rate, Tags).

-spec histogram(metric(), value()) -> ok.
histogram(Metric, Value) ->
    histogram(Metric, Value, 1, []).

-spec histogram(metric(), value(), sample_rate()) -> ok.
histogram(Metric, Value, Rate) ->
    histogram(Metric, Value, Rate, []).

-spec histogram(metric(), value(), sample_rate(), tags()) -> ok.
histogram(Metric, Value, Rate, Tags) when is_number(Value) ->
    submit(histogram, Metric, Value, Rate, Tags).

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

handle_cast({submit, Submission}, #state{socket     = Socket,
                                         host       = Host,
                                         port       = Port,
                                         prefix     = Prefix,
                                         tags       = ConstantTags,
                                         batch_size = BatchSize} = State) ->
    Submissions = drain_submissions(BatchSize - 1, [Submission]),
    Packets = lists:foldr(fun({Type, Metric, Value, SampleRate, Tags}, Acc) ->
                              Packet = estatsd_protocol:encode(Type, Metric, Value, SampleRate, Tags ++ ConstantTags),
                              case Acc of
                                  [] ->
                                      [Prefix, Packet];
                                  _ ->
                                      [Prefix, Packet, "\n" | Acc]
                              end
                          end, [], Submissions),
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

submit(Type, Metric, Value, SampleRate, Tags) when SampleRate =< 1 ->
    case SampleRate =:= 1 orelse rand:uniform(100) =< erlang:trunc(SampleRate * 100) of
        true ->
            gen_server:cast(?MODULE, {submit, {Type, Metric, Value, SampleRate, Tags}});
        false ->
            ok
    end;
submit(_, _, _, SampleRate, _) ->
    error({bad_sample_rate, SampleRate}).

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

drain_submissions(0, Acc) ->
    lists:reverse(Acc);
drain_submissions(Cnt, Acc) ->
    receive
        {'$gen_cast', {submit, Submission}} ->
            drain_submissions(Cnt - 1, [Submission | Acc])
    after 0 ->
        lists:reverse(Acc)
    end.