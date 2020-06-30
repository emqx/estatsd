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

-module(estatsd_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

all() -> emqx_ct:all(?MODULE).

init_per_suite(Config) ->
    application:ensure_all_started(estatsd),
    Config.

end_per_suite(_Config) ->
    application:stop(estatsd).

t_apis(_) ->
    {ok, Socket} = gen_udp:open(8125),
    {ok, _} = estatsd:start_link(),

    estatsd:counter(example, 1),
    should_receive(<<"example:1|c">>),

    estatsd:increment(example, 1),
    should_receive(<<"example:1|c">>),

    estatsd:increment(example, -1),
    should_receive(<<"example:-1|c">>),

    estatsd:decrement(example, 1),
    should_receive(<<"example:-1|c">>),

    estatsd:decrement(example, -1),
    should_receive(<<"example:1|c">>),

    estatsd:gauge(example, 10),
    should_receive(<<"example:10|g">>),

    estatsd:gauge_delta(example, 1),
    should_receive(<<"example:+1|g">>),

    estatsd:gauge_delta(example, -1),
    should_receive(<<"example:-1|g">>),

    estatsd:set(example, 10),
    should_receive(<<"example:10|s">>),

    estatsd:timing(example, 10),
    should_receive(<<"example:10|ms">>),

    DelayFunc = fun() ->
                    ct:sleep(100)
                end,
    estatsd:timing(example, DelayFunc),
    receive
        {udp, _, _, _, Packet} ->
            Milliseconds = list_to_integer(lists:nth(2, re:split(Packet,"[:|]",[{return,list}]))),
            ?assert(Milliseconds > 50 andalso Milliseconds < 150)
    after 10 ->
        ct:fail(should_recv_packet)
    end,

    estatsd:histogram(example, 10),
    should_receive(<<"example:10|h">>),

    gen_udp:close(Socket),
    ok = estatsd:stop().
    
t_sample_rate(_) ->
    {ok, Socket} = gen_udp:open(8125),
    {ok, _} = estatsd:start_link([{batch_size, 1}]),

    [estatsd:counter(example, 1, 0.1) || _N <- lists:seq(1, 500)],
    Rate = receive_count(0) / 500,
    ?assert(Rate > 0.06 andalso Rate < 0.14),

    gen_udp:close(Socket),
    ok = estatsd:stop().

t_opts(_) ->
    {ok, Socket} = gen_udp:open(8125),

    {ok, _} = estatsd:start_link([{prefix, hostname}, {tags, [{"constant", "abc"}]}]),
    estatsd:counter(example, 1, 1, [{"env", "dev"}]),
    should_receive(iolist_to_binary([estatsd:hostname(), $., "example:1|c|#env:dev,constant:abc"])),
    ok = estatsd:stop(),

    {ok, _} = estatsd:start_link([{prefix, name}]),
    estatsd:counter(example, 1),
    should_receive(iolist_to_binary([estatsd:name(), $., "example:1|c"])),
    ok = estatsd:stop(),

    {ok, _} = estatsd:start_link([{prefix, sname}]),
    estatsd:counter(example, 1),
    should_receive(iolist_to_binary([estatsd:sname(), $., "example:1|c"])),
    ok = estatsd:stop(),

    gen_udp:close(Socket).

receive_count(Cnt) ->
    receive
        {udp, _, _, _, _} ->
            receive_count(Cnt + 1)
    after 100 ->
        Cnt
    end.

should_receive(Expected) ->
    receive
        {udp, _, _, _, Packet} ->
            ?assertEqual(Expected, list_to_binary(Packet))
    after 10 ->
        ct:fail(should_recv_packet)
    end.

