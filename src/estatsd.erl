-module(estatsd).

-include("estatsd.hrl").

% -compile(inline).
% -compile({inline_size, 512}).

-behaviour(gen_server).

-export([ start_link/1
        , stop/0
        ]).

-export([ counter/3
        , counter/4
        , increment/3
        , increment/4
        , decrement/3
        , decrement/4
        , gauge/3
        , gauge/4
        , gauge_delta/3
        , gauge_delta/4
        , set/3
        , set/4
        , timing/3
        , timing/4
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

-spec counter(key(), value(), sample_rate()) -> ok.
counter(Key, Value, Rate) ->
    counter(Key, Value, Rate, []).

-spec counter(key(), value(), sample_rate(), tags()) -> ok.
counter(Key, Value, Rate, Tags) ->
    submit(counter, Key, Value, Rate, Tags).

-spec increment(key(), value(), sample_rate()) -> ok.
increment(Key, Value, Rate) ->
    increment(Key, Value, Rate, []).

increment(Key, Value, Rate, Tags) ->
    submit(counter, Key, Value, Rate, Tags).

-spec decrement(key(), value(), sample_rate()) -> ok.
decrement(Key, Value, Rate) ->
    decrement(Key, Value, Rate, []).

decrement(Key, Value, Rate, Tags) ->
    submit(counter, Key, -Value, Rate, Tags).

-spec gauge(key(), value(), sample_rate()) -> ok.
gauge(Key, Value, Rate) ->
    gauge(Key, Value, Rate, []).

gauge(Key, Value, Rate, Tags) when Value >= 0 ->
    submit(gauge, Key, Value, Rate, Tags).

-spec gauge_delta(key(), value(), sample_rate()) -> ok.
gauge_delta(Key, Value, Rate) ->
    gauge_delta(Key, Value, Rate, []).

gauge_delta(Key, Value, Rate, Tags) ->
    submit(gauge_delta, Key, Value, Rate, Tags).

set(Key, Value, Rate) ->
    set(Key, Value, Rate, []).

set(Key, Value, Rate, Tags) ->
    submit(set, Key, Value, Rate, Tags).

-spec timing(key(), value(), sample_rate()) -> ok.
timing(Key, Value, Rate) ->
    timing(Key, Value, Rate, []).

timing(Key, Value, Rate, Tags) ->
    submit(timing, Key, Value, Rate, Tags).

submit(Type, Key, Value, SampleRate, Tags) when SampleRate =< 1 ->
    case SampleRate =:= 1 orelse rand:uniform(100) > erlang:trunc(SampleRate * 100) of
        true ->
            Packet = estatsd_protocol:encode(Type, Key, Value, SampleRate, Tags),
            gen_server:cast(?MODULE, {submit, Packet});
        false ->
            ok
    end;
submit(_, _, _, SampleRate, _) ->
    error({bad_sample_rate, SampleRate}).

%%--------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------

% -spec init(term()) -> {ok, term()} | {stop, atom()}.
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
prefix(Key) when is_binary(Key) ->
    [Key, $.];
prefix([]) ->
    [];
prefix([H | T] = Key) ->
    case io_lib:printable_unicode_list(Key) of
        true ->
            [Key, $.];
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