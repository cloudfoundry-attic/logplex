-module(logplex_app).
-behaviour(application).

%% Application callbacks
-export([start/2, stop/1, init/1]).

-include_lib("logplex.hrl").

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    set_cookie(),
    boot_redis(),
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

stop(_State) ->
    ok.

init([]) ->
    {ok, {{one_for_one, 5, 10}, [
        {logplex_grid, {logplex_grid, start_link, []}, permanent, 2000, worker, [logplex_grid]},
        {logplex_channel, {logplex_channel, start_link, []}, permanent, 2000, worker, [logplex_channel]},
        {logplex_token, {logplex_token, start_link, []}, permanent, 2000, worker, [logplex_token]},
        {logplex_drain, {logplex_drain, start_link, []}, permanent, 2000, worker, [logplex_drain]},
        {syslog_server, {syslog_server, start_link, []}, permanent, 2000, worker, [syslog_server]},
        {logplex_api, {logplex_api, start_link, []}, permanent, 2000, worker, [logplex_api]},
        {logplex_stats, {logplex_stats, start_link, []}, permanent, 2000, worker, [logplex_stats]},
        {logplex_tail, {logplex_tail, start_link, []}, permanent, 2000, worker, [logplex_tail]}
    ] ++ [
        {erlang:make_ref(), {logplex_drain_pool, start_link, []}, permanent, 2000, worker, [logplex_drain_pool]}
    || _ <- lists:seq(1, 100)]}}.

set_cookie() ->
    case os:getenv("ERLANG_COOKIE") of
        false -> ok;
        Cookie -> erlang:set_cookie(node(), list_to_atom(Cookie))
    end.

boot_redis() ->
    case application:start(redis, temporary) of
        ok ->
            Opts = 
                case os:getenv("LOGPLEX_REDIS_URL") of
                    false -> [];
                    Url ->
                        case redis_uri:parse(Url) of
                            {redis, UserInfo, Host, Port, _Path, _Query} ->
                                Pass = 
                                    case UserInfo of
                                        "" -> undefined;
                                        Val -> list_to_binary(Val)
                                    end,
                                [{ip, Host}, {port, Port}, {pass, Pass}];
                            _ ->
                                []
                        end
                end,
            redis_sup:add_pool(redis_pool, Opts, 100),
            [redis_sup:add_pool(list_to_atom("spool_" ++ integer_to_list(N)), Opts, 50) || N <- lists:seq(1, ?NUM_REDIS_POOLS)],
            ok;
        Err ->
            exit(Err)
    end.
