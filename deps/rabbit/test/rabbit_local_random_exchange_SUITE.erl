%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%
%% Copyright (c) 2007-2023 VMware, Inc. or its affiliates.  All rights reserved.
%%
-module(rabbit_local_random_exchange_SUITE).

-compile(nowarn_export_all).
-compile(export_all).

-include_lib("amqp_client/include/amqp_client.hrl").
-include_lib("eunit/include/eunit.hrl").

all() ->
    [
     {group, non_parallel_tests}
    ].

groups() ->
    [
     {non_parallel_tests, [], [
                               routed_to_one_local_queue_test,
                               no_route
                              ]}
    ].

%% -------------------------------------------------------------------
%% Test suite setup/teardown
%% -------------------------------------------------------------------

init_per_suite(Config) ->
    rabbit_ct_helpers:log_environment(),
    Config1 = rabbit_ct_helpers:set_config(Config,
                                           [
                                            {rmq_nodename_suffix, ?MODULE},
                                            {rmq_nodes_count, 3},
                                            {tcp_ports_base, {skip_n_nodes, 3}}
                                           ]),
    rabbit_ct_helpers:run_setup_steps(Config1,
                                      rabbit_ct_broker_helpers:setup_steps() ++
                                      rabbit_ct_client_helpers:setup_steps()).

end_per_suite(Config) ->
    rabbit_ct_helpers:run_teardown_steps(
      Config,
      rabbit_ct_client_helpers:teardown_steps() ++
      rabbit_ct_broker_helpers:teardown_steps()).

init_per_group(_, Config) ->
    Config.

end_per_group(_, Config) ->
    Config.

init_per_testcase(Testcase, Config) ->
    case rabbit_ct_broker_helpers:enable_feature_flag(
           Config, rabbit_exchange_type_local_random) of
        ok ->
            TestCaseName = rabbit_ct_helpers:config_to_testcase_name(Config, Testcase),
            Config1 = rabbit_ct_helpers:set_config(Config, {test_resource_name,
                                                            re:replace(TestCaseName, "/", "-",
                                                                       [global, {return, list}])}),
            rabbit_ct_helpers:testcase_started(Config1, Testcase);
        Res ->
            {skip, Res}
    end.

end_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_finished(Config, Testcase).

%% -------------------------------------------------------------------
%% Test cases
%% -------------------------------------------------------------------

routed_to_one_local_queue_test(Config) ->
    E = make_exchange_name(Config, "0"),
    declare_exchange(Config, E),
    %% declare queue on the first two nodes: 0, 1
    QueueNames = declare_and_bind_queues(Config, 2, E),
    %% publish message on node 1
    publish(Config, E, 0),
    publish(Config, E, 1),
    %% message should arrive to queue on node 1
    run_on_node(Config, 0,
                fun(Chan) ->
                        assert_queue_size(Config, Chan, 1, lists:nth(1, QueueNames))
                end),
    run_on_node(Config, 0,
                fun(Chan) ->
                        assert_queue_size(Config, Chan, 1, lists:nth(2, QueueNames))
                end),
    delete_exchange_and_queues(Config, E, QueueNames),
    ok.

no_route(Config) ->

    E = make_exchange_name(Config, "0"),
    declare_exchange(Config, E),
    %% declare queue on nodes 0, 1
    QueueNames = declare_and_bind_queues(Config, 2, E),
    %% publish message on node 2
    publish_expect_return(Config, E, 2),
    %% message should arrive to any of the other nodes. Total size among all queues is 1
    delete_exchange_and_queues(Config, E, QueueNames),
    ok.

delete_exchange_and_queues(Config, E, QueueNames) ->
    run_on_node(Config, 0,
              fun(Chan) ->
                      amqp_channel:call(Chan, #'exchange.delete'{exchange = E }),
                      [amqp_channel:call(Chan, #'queue.delete'{queue = Q })
                       || Q <- QueueNames]
              end).
publish(Config, E, Node) ->
    run_on_node(Config, Node,
                fun(Chan) ->
                        amqp_channel:call(Chan, #'confirm.select'{}),
                        amqp_channel:call(Chan,
                                          #'basic.publish'{exchange = E, routing_key = rnd()},
                                          #amqp_msg{props = #'P_basic'{}, payload = <<>>}),
                        amqp_channel:wait_for_confirms_or_die(Chan)
                end).

publish_expect_return(Config, E, Node) ->
    run_on_node(Config, Node,
              fun(Chan) ->
                      amqp_channel:register_return_handler(Chan, self()),
                      amqp_channel:call(Chan,
                                        #'basic.publish'{exchange = E,
                                                         mandatory = true,
                                                         routing_key = rnd()},
                                        #amqp_msg{props = #'P_basic'{},
                                                  payload = <<>>}),
                      receive
                          {#'basic.return'{}, _} ->
                              ok
                      after 5000 ->
                                flush(100),
                                ct:fail("no return received")
                      end
              end).

run_on_node(Config, Node, RunMethod) ->
    {Conn, Chan} = rabbit_ct_client_helpers:open_connection_and_channel(Config, Node),
    Return = RunMethod(Chan),
    rabbit_ct_client_helpers:close_connection_and_channel(Conn, Chan),
    Return.

declare_exchange(Config, ExchangeName) ->
    run_on_node(Config, 0,
                fun(Chan) ->
                        #'exchange.declare_ok'{} =
                        amqp_channel:call(Chan,
                                          #'exchange.declare'{exchange = ExchangeName,
                                                              type = <<"x-local-random">>,
                                                              auto_delete = false})
                end).

declare_and_bind_queues(Config, NodeCount, E) ->
  QueueNames = [make_queue_name(Config, Node) || Node <- lists:seq(0, NodeCount -1)],
  [run_on_node(Config, Node,
               fun(Chan) ->
                       declare_and_bind_queue(Chan, E, make_queue_name(Config, Node))
               end) || Node <- lists:seq(0, NodeCount -1)],
  QueueNames.

declare_and_bind_queue(Ch, E, Q) ->
    #'queue.declare_ok'{} = amqp_channel:call(Ch, #'queue.declare'{queue = Q}),
    #'queue.bind_ok'{} = amqp_channel:call(Ch, #'queue.bind'{queue = Q,
                                                             exchange = E,
                                                             routing_key = <<"">>}),
    ok.

assert_total_queue_size(_Config, Chan, ExpectedSize, ExpectedQueues) ->
    Counts = [begin
                  #'queue.declare_ok'{message_count = M} =
                  amqp_channel:call(Chan, #'queue.declare'{queue = Q}),
                  M
              end || Q <- ExpectedQueues],
    ?assertEqual(ExpectedSize, lists:sum(Counts)).

assert_queue_size(_Config, Chan, ExpectedSize, ExpectedQueue) ->
    ct:log("assert_queue_size ~p ~p", [ExpectedSize, ExpectedQueue]),
    #'queue.declare_ok'{message_count = M} =
    amqp_channel:call(Chan, #'queue.declare'{queue = ExpectedQueue}),
    ?assertEqual(ExpectedSize, M).

rnd() ->
    list_to_binary(integer_to_list(rand:uniform(1000000))).

make_exchange_name(Config, Suffix) ->
    B = rabbit_ct_helpers:get_config(Config, test_resource_name),
    erlang:list_to_binary("x-" ++ B ++ "-" ++ Suffix).
make_queue_name(Config, Node) ->
    B = rabbit_ct_helpers:get_config(Config, test_resource_name),
    erlang:list_to_binary("q-" ++ B ++ "-" ++ integer_to_list(Node)).

flush(T) ->
    receive X ->
                ct:pal("flushed ~p", [X]),
                flush(T)
    after T ->
              ok
    end.
