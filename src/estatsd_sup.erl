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