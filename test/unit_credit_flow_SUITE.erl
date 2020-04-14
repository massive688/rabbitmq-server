%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License at
%% https://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%% License for the specific language governing rights and limitations
%% under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2011-2020 VMware, Inc. or its affiliates.  All rights reserved.
%%

-module(unit_credit_flow_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-compile(export_all).

all() ->
    [
      {group, sequential_tests}
    ].

groups() ->
    [
      {sequential_tests, [], [
          credit_flow_settings
        ]}
    ].

%% -------------------------------------------------------------------
%% Testsuite setup/teardown
%% -------------------------------------------------------------------

init_per_suite(Config) ->
    rabbit_ct_helpers:log_environment(),
    rabbit_ct_helpers:run_setup_steps(Config).

end_per_suite(Config) ->
    rabbit_ct_helpers:run_teardown_steps(Config).

init_per_group(Group, Config) ->
    Config1 = rabbit_ct_helpers:set_config(Config, [
        {rmq_nodename_suffix, Group},
        {rmq_nodes_count, 1}
      ]),
    rabbit_ct_helpers:run_steps(Config1,
      rabbit_ct_broker_helpers:setup_steps() ++
      rabbit_ct_client_helpers:setup_steps()).

end_per_group(_Group, Config) ->
    rabbit_ct_helpers:run_steps(Config,
      rabbit_ct_client_helpers:teardown_steps() ++
      rabbit_ct_broker_helpers:teardown_steps()).

init_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_started(Config, Testcase).

end_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_finished(Config, Testcase).


%% ---------------------------------------------------------------------------
%% Test Cases
%% ---------------------------------------------------------------------------

credit_flow_settings(Config) ->
    rabbit_ct_broker_helpers:rpc(Config, 0,
      ?MODULE, credit_flow_settings1, [Config]).

credit_flow_settings1(_Config) ->
    passed = test_proc(400, 200, {400, 200}),
    passed = test_proc(600, 300),
    passed.

test_proc(InitialCredit, MoreCreditAfter) ->
    test_proc(InitialCredit, MoreCreditAfter, {InitialCredit, MoreCreditAfter}).
test_proc(InitialCredit, MoreCreditAfter, Settings) ->
    Pid = spawn(?MODULE, dummy, [Settings]),
    Pid ! {credit, self()},
    {InitialCredit, MoreCreditAfter} =
        receive
            {credit, Val} -> Val
        end,
    passed.

dummy(Settings) ->
    credit_flow:send(self()),
    receive
        {credit, From} ->
            From ! {credit, Settings};
        _      ->
            dummy(Settings)
    end.
