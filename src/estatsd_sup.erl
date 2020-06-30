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

-module(estatsd_sup).

-include("estatsd.hrl").

%% public
-export([start_link/0]).

-behaviour(supervisor).

-export([init/1]).

%% public
-spec start_link() -> {ok, pid()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% supervisor callbacks
-spec init([]) -> {ok, {{one_for_one, 5, 10}, [supervisor:child_spec()]}}.
init(_Args) ->
    {ok, {{one_for_one, 5, 10}, child_specs()}}.

%% private
child_specs() ->
    [#{id       => estatsd,
       start    => {estatsd, start_link, []},
       restart  => permanent,
       shutdown => 5000,
       type     => worker,
       modules  => [estatsd]}].