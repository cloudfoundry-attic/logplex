# Table of Contents

1. [Build](#build)
2. [Test](#test)
3. [Develop](#develop)
4. [Supervision Tree](#supervision-tree)
5. [Processes](#processes)

# Build

    $ ./rebar --config public.rebar.config get-deps compile

# Test

Given an empty local redis (v2.6ish):

    $ INSTANCE_NAME=`hostname` \
      LOGPLEX_CONFIG_REDIS_URL="redis://localhost:6379" \
      LOCAL_IP="127.0.0.1" \
      LOGPLEX_COOKIE=123 \
      rebar skip_deps=true ct

Runs the common test suite for logplex.

# Develop

run

    $ INSTANCE_NAME=`hostname` \
      LOGPLEX_CONFIG_REDIS_URL="redis://localhost:6379" \
      LOCAL_IP="127.0.0.1" \
      LOGPLEX_COOKIE=123 \
      LOGPLEX_AUTH_KEY=123 \
      erl -name logplex@`hostname` -pa ebin -env ERL_LIBS deps -s logplex_app -setcookie ${LOGPLEX_COOKIE}

create creds    

    1> logplex_cred:store(logplex_cred:grant('full_api', logplex_cred:grant('any_channel', logplex_cred:rename(<<"Local-Test">>, logplex_cred:new(<<"local">>, <<"password">>))))).
    ok

hit healthcheck

    $ curl http://local:password@localhost:8001/healthcheck
    OK

create a channel

    $ curl -d '{"tokens": ["app"]}' http://local:password@localhost:8001/channels
    {"channel_id":1,"tokens":{"app":"t.feff49f1-4d55-4c9e-aee1-2d2b10e69b42"}}

post a log msg

    $ curl -v \
    -H "Content-Type: application/logplex-1" \
    -H "Content-Length: 119" \
    -d "115 <134>1 2012-12-10T03:00:48Z+00:00 erlang t.feff49f1-4d55-4c9e-aee1-2d2b10e69b42 console.1 - Logsplat test message 1" \
    http://local:password@localhost:8601/logs

create a log session

    $ curl -d '{"channel_id": "1"}' http://local:password@localhost:8001/v2/sessions
    {"url":"/sessions/9d53bf70-7964-4429-a589-aaa4df86fead"}

fetch logs for session

    $ curl http://local:password@localhost:8001/sessions/9d53bf70-7964-4429-a589-aaa4df86fead?srv=1
    2012-12-10T03:00:48Z+00:00 app[console.1]: test message 1

# Supervision Tree

<table>
<tr><td>logplex_app</td><td> logplex_sup</td><td> <a href="#logplex_db">logplex_db</a></td><td></td><td></td></tr>
                          <tr><td></td><td></td><td> <a href="#config_redis">config_redis</a> (redo)</td><td></td><td></td></tr>
                          <tr><td></td><td></td><td> <a href="#logplex_drain_sup">logplex_drain_sup</a></td><td> logplex_http_drain</td><td></td></tr>
                                                                                <tr><td></td><td></td><td></td><td> logplex_tcpsyslog_drain</td><td></td></tr>
                          <tr><td></td><td></td><td> <a href="#nsync">nsync</a></td><td></td><td></td></tr>
                          <tr><td></td><td></td><td> <a href="#redgrid">redgrid</a></td><td></td><td></td></tr>
                          <tr><td></td><td></td><td> <a href="#logplex_realtime">logplex_realtime</a></td><td> redo</td><td></td></tr>
                          <tr><td></td><td></td><td> <a href="#logplex_stats">logplex_stats</a></td><td></td><td></td></tr>
                          <tr><td></td><td></td><td> <a href="#logplex_tail">logplex_tail</a></td><td></td><td></td></tr>
                          <tr><td></td><td></td><td> <a href="#logplex_redis_writer_sup">logplex_redis_writer_sup</a> (logplex_worker_sup)</td><td> logplex_redis_writer</td><td></td></tr>
                          <tr><td></td><td></td><td> <a href="#logplex_read_queue_sup">logplex_read_queue_sup</a> (logplex_queue_sup)</td><td> logplex_queue</td><td></td></tr>
                          <tr><td></td><td></td><td> <a href="#logplex_reader_sup">logplex_reader_sup</a> (logplex_worker_sup)</td><td> logplex_reader</td><td></td></tr>
                          <tr><td></td><td></td><td> <a href="#logplex_shard">logplex_shard</a></td><td> redo</td><td></td></tr>
                          <tr><td></td><td></td><td> <a href="#logplex_api">logplex_api</a></td><td></td><td></td></tr>
                          <tr><td></td><td></td><td> <a href="#logplex_syslog_sup">logplex_syslog_sup</a></td><td> tcp_proxy_sup</td><td> tcp_proxy</td></tr>
                          <tr><td></td><td></td><td> <a href="#logplex_logs_rest">logplex_logs_rest</a></td><td></td><td></td></tr>
</table>

# Processes

### logplex_db

Starts and supervises a number of ETS tables:

```
channels
tokens
drains
creds
sessions
```

### config_redis

A [redo](https://github.com/JacobVorreuter/redo) redis client process connected to the logplex config redis.

### logplex_drain_sup

An empty one_for_one supervisor. Supervises [HTTP](https://github.com/heroku/logplex/blob/jake-docs/src/logplex_http_drain.erl) and [TCP](https://github.com/heroku/logplex/blob/jake-docs/src/logplex_tcpsyslog_drain.erl) drain processes.

### nsync

An [nsync](https://github.com/JacobVorreuter/nsync) process connected to the logplex config redis. Callback module is [nsync_callback](https://github.com/heroku/logplex/blob/jake-docs/src/nsync_callback.erl).

Nsync is an Erlang redis replication client. It allows the logplex node to act as a redis slave and sync the logplex config redis data into memory.

### redgrid

A [redgrid](https://github.com/JacobVorreuter/redgrid) process that registers the node in a central redis server to facilitate discovery by other nodes.

### logplex_realtime

Establishes a connection to the logplex stats redis. Owns the `logplex_realtime` ETS table and flushes the contents to [tempo](https://github.com/JacobVorreuter/tempo) via redis pub/sub every second.

Metrics published to tempo:

```
message_received
message_processed
drain_delivered
drain_dropped
git_branch
availability_zone
```

### logplex_stats

Owns the `logplex_stats` ETS table.  Prints channel, drain and system stats every 60 seconds.

### logplex_tail

Maintains the `logplex_tail` ETS table that is used to register tail sessions.

### logplex_redis_writer_sup

Starts a [logplex_worker_sup](https://github.com/heroku/logplex/blob/master/src/logplex_worker_sup.erl) process, registered as `logplex_redis_writer_sup`, that supervises [logplex_redis_writer](https://github.com/heroku/logplex/blob/master/src/logplex_redis_writer.erl) processes.

### logplex_read_queue_sup

Starts a [logplex_queue_sup](https://github.com/heroku/logplex/blob/master/src/logplex_queue_sup.erl) process, registered as `logplex_read_queue_sup`, that supervises [logplex_queue](https://github.com/heroku/logplex/blob/master/src/logplex_queue.erl) processes.

### logplex_reader_sup

Appears to start a `logplex_worker_sup` that supervises `logplex_reader` processes. That model doesn't seem to exist?!?

### logplex_shard

Owns the `logplex_shard_info` ETS table.  Starts a separate read and write redo client for each redis shard found in the `logplex_shard_urls` var.

### logplex_api

Blocks waiting for nsync to finish replicating data into memory before starting a mochiweb acceptor that handles API requests for managing channels/tokens/drains/sessions.

### logplex_syslog_sup

Supervises a [tcp_proxy_sup](https://github.com/heroku/logplex/blob/master/src/tcp_proxy_sup.erl) process that supervises a [tcp_proxy](https://github.com/heroku/logplex/blob/master/src/tcp_proxy.erl) process that accepts syslog messages over TCP.

### logplex_logs_rest

Starts a `cowboy_tcp_transport` process and serves as the callback for processing HTTP log input.
