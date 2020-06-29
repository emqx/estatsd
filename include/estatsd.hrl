%% defaults
-define(DEFAULT_POOL_SIZE, 4).
-define(DEFAULT_PREFIX, undefined).
-define(DEFAULT_HOSTNAME, {127, 0, 0, 1}).
-define(DEFAULT_PORT, 8125).
-define(DEFAULT_BATCH_SIZE, 10).

%% types
-type options() :: [].
-type prefix() :: prefix_part() | [prefix_part()].
-type prefix_part() :: hostname | name | sname | undefined | iodata().
-type key() :: iodata().
-type sample_rate() :: number().
-type value() :: number().
-type tags() :: [{key(), any()}].
