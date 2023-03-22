%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%
%% Copyright (c) 2007-2023 VMware, Inc. or its affiliates.  All rights reserved.
%%

-module(rabbit_mqtt_retained_msg_store).

%% TODO Support retained messages in RabbitMQ cluster, for
%% 1. support PUBLISH with retain on a different node than SUBSCRIBE
%% 2. replicate retained message for data safety
%%
%% Possible solution for 1.
%% * retained message store backend does RPCs to peer nodes to lookup and delete
%%
%% Possible solutions for 2.
%% * rabbitmq_mqtt_retained_msg_store_khepri
%% * rabbitmq_mqtt_retained_msg_store_ra (implementing our own ra machine)

-include("rabbit_mqtt.hrl").
-include("rabbit_mqtt_packet.hrl").
-include_lib("kernel/include/logger.hrl").
-export([start/1, insert/3, lookup/2, delete/2, terminate/1]).
-export_type([state/0]).

-define(STATE, ?MODULE).
-record(?STATE, {store_mod :: module(),
                 store_state :: term()}).
-opaque state() :: #?STATE{}.

-callback new(Directory :: file:name_all(), rabbit_types:vhost()) ->
    State :: any().

-callback recover(Directory :: file:name_all(), rabbit_types:vhost()) ->
    {ok, State :: any()} | {error, uninitialized}.

-callback insert(Topic :: binary(), mqtt_msg(), State :: any()) ->
    ok.

-callback lookup(Topic :: binary(), State :: any()) ->
    mqtt_msg() | undefined.

-callback delete(Topic :: binary(), State :: any()) ->
    ok.

-callback terminate(State :: any()) ->
    ok.

-spec start(rabbit_types:vhost()) -> state().
start(VHost) ->
    {ok, Mod} = application:get_env(?APP_NAME, retained_message_store),
    Dir = rabbit:data_dir(),
    ?LOG_INFO("Starting MQTT retained message store ~s for vhost '~ts'",
              [Mod, VHost]),
    S = case Mod:recover(Dir, VHost) of
            {ok, StoreState} ->
                ?LOG_INFO("Recovered MQTT retained message store ~s for vhost '~ts'",
                          [Mod, VHost]),
                StoreState;
            {error, uninitialized} ->
                StoreState = Mod:new(Dir, VHost),
                ?LOG_INFO("Initialized MQTT retained message store ~s for vhost '~ts'",
                          [Mod, VHost]),
                StoreState
        end,
    #?STATE{store_mod = Mod,
            store_state = S}.

-spec insert(Topic :: binary(), mqtt_msg(), state()) -> ok.
insert(Topic, Msg, #?STATE{store_mod = Mod,
                           store_state = StoreState}) ->
    ok = Mod:insert(Topic, Msg, StoreState).

-spec lookup(Topic :: binary(), state()) ->
    mqtt_msg() | undefined.
lookup(Topic, #?STATE{store_mod = Mod,
                      store_state = StoreState}) ->
    Mod:lookup(Topic, StoreState).

-spec delete(Topic :: binary(), state()) -> ok.
delete(Topic, #?STATE{store_mod = Mod,
                      store_state = StoreState}) ->
    ok = Mod:delete(Topic, StoreState).

-spec terminate(state()) -> ok.
terminate(#?STATE{store_mod = Mod,
                  store_state = StoreState}) ->
    ok = Mod:terminate(StoreState).
