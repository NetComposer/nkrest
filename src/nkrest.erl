%% -------------------------------------------------------------------
%%
%% Copyright (c) 2019 Carlos Gonzalez Florido.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(nkrest).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([start_link/2, get_sup_spec/2]).
-export([stop/1, update/2]).
-export_type([id/0, config/0, user_state/0]).

-include("nkrest.hrl").


%% ===================================================================
%% Types
%% ===================================================================

-type id() :: nkserver:id().

-type config() :: map().

-type user_state() :: term().

%% ===================================================================
%% Public
%% ===================================================================

%% @doc Starts a new nkrest_http service
-spec start_link(id(), config()) ->
    {ok, pid()} | {error, term()}.

start_link(Id, Config) ->
    nkserver:start_link(nkrest, Id, Config).


%% @doc Retrieves a service as a supervisor child specification
-spec get_sup_spec(id(), config()) ->
    {ok, supervisor:child_spec()} | {error, term()}.

get_sup_spec(Id, Config) ->
    nkserver:get_sup_spec(nkrest, Id, Config).


stop(Id) ->
    nkserver_srv_sup:stop(Id).


-spec update(id(), config()) ->
    ok | {error, term()}.

update(Id, Config) ->
    Config2 = nklib_util:to_map(Config),
    Config3 = case Config2 of
        #{plugins:=Plugins} ->
            Config2#{plugins:=[nkrest|Plugins]};
        _ ->
            Config2
    end,
    nkserver:update(Id, Config3).

