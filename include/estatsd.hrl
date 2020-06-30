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

%% defaults
-define(DEFAULT_HOSTNAME, {127, 0, 0, 1}).
-define(DEFAULT_PORT, 8125).
-define(DEFAULT_PREFIX, undefined).
-define(DEFAULT_TAGS, []).
-define(DEFAULT_BATCH_SIZE, 10).

%% types
-type options() :: [].
-type prefix() :: prefix_part() | [prefix_part()].
-type prefix_part() :: hostname | name | sname | undefined | iodata().
-type key() :: iodata().
-type sample_rate() :: number().
-type value() :: number().
-type tags() :: [{key(), any()}].
