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

-module(estatsd_protocol_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

all() -> emqx_ct:all(?MODULE).

t_encode(_) ->
    try estatsd_protocol:encode(aaa, example, 10, 1, []) of
        _ -> ct:fail(should_throw_error)
    catch error:Reason ->
        ?assertEqual(Reason, {bad_type, aaa})
    end,
    try estatsd_protocol:encode(counter, example, 10, 2, []) of
        _ -> ct:fail(should_throw_error)
    catch error:Reason1 ->
        ?assertEqual(Reason1, {bad_sample_rate, 2})
    end,
    ?assertEqual(<<"example:10|c">>, iolist_to_binary(estatsd_protocol:encode(counter, example, 10, 1, []))),
    ?assertEqual(<<"example:-10|c">>, iolist_to_binary(estatsd_protocol:encode(counter, example, -10, 1, []))),
    ?assertEqual(<<"example:-10|c|@0.2">>, iolist_to_binary(estatsd_protocol:encode(counter, example, -10, 0.2, []))),
    ?assertEqual(<<"example:-10|c|@0.2|#first:a,second:b">>, iolist_to_binary(estatsd_protocol:encode(counter, example, -10, 0.2, [{"first", "a"}, {<<"second">>, "b"}]))),
    ?assertEqual(<<"example:10|g">>, iolist_to_binary(estatsd_protocol:encode(gauge, example, 10, 1, []))),
    ?assertEqual(<<"example:+10|g">>, iolist_to_binary(estatsd_protocol:encode(gauge_delta, example, 10, 1, []))),
    ?assertEqual(<<"example:-10|g">>, iolist_to_binary(estatsd_protocol:encode(gauge_delta, example, -10, 1, []))),
    ?assertEqual(<<"example:10|ms">>, iolist_to_binary(estatsd_protocol:encode(timing, example, 10, 1, []))),
    ?assertEqual(<<"example:10|h">>, iolist_to_binary(estatsd_protocol:encode(histogram, example, 10, 1, []))),
    ?assertEqual(<<"example:10|s">>, iolist_to_binary(estatsd_protocol:encode(set, example, 10, 1, []))),
    try estatsd_protocol:encode(gauge, example, -10, 1, []) of
        _ -> ct:fail(should_throw_error)
    catch error:Reason2 ->
        ?assertEqual(Reason2, {bad_value, -10})
    end,
    try estatsd_protocol:encode(timing, example, -10, 1, []) of
        _ -> ct:fail(should_throw_error)
    catch error:Reason3 ->
        ?assertEqual(Reason3, {bad_value, -10})
    end,
    try estatsd_protocol:encode(set, example, -10, 1, []) of
        _ -> ct:fail(should_throw_error)
    catch error:Reason4 ->
        ?assertEqual(Reason4, {bad_value, -10})
    end.



