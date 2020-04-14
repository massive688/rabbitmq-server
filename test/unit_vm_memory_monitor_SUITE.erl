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

-module(unit_vm_memory_monitor_SUITE).

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
          parse_line_linux,
          set_vm_memory_high_watermark_command
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


%% -------------------------------------------------------------------
%% Test cases
%% -------------------------------------------------------------------


parse_line_linux(_Config) ->
    lists:foreach(fun ({S, {K, V}}) ->
                          {K, V} = vm_memory_monitor:parse_line_linux(S)
                  end,
                  [{"MemTotal:      0 kB",        {'MemTotal', 0}},
                   {"MemTotal:      502968 kB  ", {'MemTotal', 515039232}},
                   {"MemFree:         178232 kB", {'MemFree',  182509568}},
                   {"MemTotal:         50296888", {'MemTotal', 50296888}},
                   {"MemTotal         502968 kB", {'MemTotal', 515039232}},
                   {"MemTotal     50296866   ",   {'MemTotal', 50296866}}]),
    ok.

set_vm_memory_high_watermark_command(Config) ->
    rabbit_ct_broker_helpers:rpc(Config, 0,
      ?MODULE, set_vm_memory_high_watermark_command1, [Config]).

set_vm_memory_high_watermark_command1(_Config) ->
    MemLimitRatio = 1.0,
    MemTotal = vm_memory_monitor:get_total_memory(),

    vm_memory_monitor:set_vm_memory_high_watermark(MemLimitRatio),
    MemLimit = vm_memory_monitor:get_memory_limit(),
    case MemLimit of
        MemTotal -> ok;
        _        -> MemTotalToMemLimitRatio = MemLimit * 100.0 / MemTotal / 100,
                    ct:fail(
                        "Expected memory high watermark to be ~p (~s), but it was ~p (~.1f)",
                        [MemTotal, MemLimitRatio, MemLimit, MemTotalToMemLimitRatio]
                    )
    end.
