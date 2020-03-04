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

%% @doc
-module(nkrest_protocol).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([transports/1, default_port/1]).
-export([send/2, send_async/2, stop/1]).
-export([conn_init/1, conn_encode/2, conn_parse/3, conn_handle_call/4,
         conn_handle_cast/3, conn_handle_info/3, conn_stop/3]).
-export([http_init/4]).
-import(nkserver_trace, [trace/1, trace/2, log/2, log/3]).

-include_lib("nkserver/include/nkserver.hrl").


%% ===================================================================
%% Types
%% ===================================================================

-type msg() :: {text, iolist()} | {binary, iolist()} | {json, iolist()}.


%% ===================================================================
%% Public
%% ===================================================================

%% @doc Callbacks for protocol
transports(_) ->
    [http, https, ws, wss].


%% @doc Callbacks for protocol
default_port(http) -> 80;
default_port(https) -> 443;
default_port(ws) -> 80;
default_port(wss) -> 443.


%% @doc Send a command to the client and wait a response
-spec send(pid(), msg()) ->
    ok | {error, term()}.

send(Pid, Data) ->
    gen_server:call(Pid, {nkrest_send, Data}).


%% @doc Send a command and don't wait for a response
-spec send_async(pid(), msg()) ->
    ok | {error, term()}.

send_async(Pid, Data) ->
    gen_server:cast(Pid, {nkrest_send, Data}).


%% @doc
stop(Pid) ->
    gen_server:cast(Pid, nkrest_stop).


%% ===================================================================
%% WS Protocol callbacks
%% ===================================================================

-record(state, {
    srv :: nkserver:id(),
    local :: binary(),
    local_port :: integer(),
    remote :: binary(),
    remote_port :: integer(),
    transport :: atom(),
    user_state = #{} :: map()
}).


-spec conn_init(nkpacket:nkport()) ->
    {ok, #state{}}.

conn_init(NkPort) ->
    {ok, _Class, {nkrest, SrvId}} = nkpacket:get_id(NkPort),
    {ok, {_, _, LocalIp, LocalPort}} = nkpacket:get_local(NkPort),
    {ok, {_Proto, Transp, RemIp, RemPort}} = nkpacket:get_remote(NkPort),
    Local = nklib_util:to_host(LocalIp),
    Remote = nklib_util:to_host(RemIp),
    State = #state{
        srv = SrvId,
        local = Local,
        local_port = LocalPort,
        transport = Transp,
        remote = Remote,
        remote_port = RemPort
    },
    SpanOpts = #{
        local => Local,
        local_port => LocalPort,
        remote => Remote,
        remote_port => RemPort,
        transport => Transp
    },
    nkserver_trace:new_span(SrvId, {nkrest, connection}, infinity, SpanOpts),
    log(info, "new connection (~s, ~p)", [Remote, self()]),
    {ok, State2} = handle(ws_init, [SrvId, NkPort], State),
    log(debug, "connection initialized"),
    {ok, State2}.


%% @private
-spec conn_parse(term()|close, nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, term(), #state{}}.

conn_parse(close, _NkPort, State) ->
    log(debug, "connection closed"),
    {ok, State};

conn_parse({text, Text}, NkPort, State) ->
    log(debug, "received text: ~p", [Text]),
    call_rest_frame({text, Text}, NkPort, State);

conn_parse({binary, Bin}, NkPort, State) ->
    log(debug, "received bin: ~p", [Bin]),
    call_rest_frame({binary, Bin}, NkPort, State).


-spec conn_encode(term(), nkpacket:nkport()) ->
    {ok, nkpacket:outcoming()} | continue | {error, term()}.

conn_encode({text, Text}, _NkPort) ->
    {ok, {text, Text}};

conn_encode({binary, Bin}, _NkPort) ->
    {ok, {binary, Bin}};

conn_encode({json, Term}, _NkPort) ->
    case nklib_json:encode(Term) of
        error ->
            lager:warning("invalid json in ~p: ~p", [?MODULE, Term]),
            {error, invalid_json};
        Json ->
            {ok, {text, Json}}
    end.


-spec conn_handle_call(term(), {pid(), term()}, nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, Reason::term(), #state{}}.

conn_handle_call({nkrest_send, Data}, From, NkPort, State) ->
    case do_send(Data, NkPort, State) of
        {ok, State2} ->
            gen_server:reply(From, ok),
            {ok, State2};
        {stop, Error, State2} ->
            {error, Error, State2}
    end;

conn_handle_call(Msg, From, _NkPort, State) ->
    handle(ws_handle_call, [Msg, From], State).


-spec conn_handle_cast(term(), nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, Reason::term(), #state{}}.

conn_handle_cast({nkrest_send, Data}, NkPort, State) ->
    do_send(Data, NkPort, State);

conn_handle_cast(nkrest_stop, _NkPort, State) ->
    {stop, normal, State};

conn_handle_cast(Msg, _NkPort, State) ->
    handle(ws_handle_cast, [Msg], State).


-spec conn_handle_info(term(), nkpacket:nkport(), #state{}) ->
    {ok, #state{}} | {stop, Reason::term(), #state{}}.

conn_handle_info(Info, _NkPort, State) ->
    handle(ws_handle_info, [Info], State).


%% @doc Called when the connection stops
-spec conn_stop(Reason::term(), nkpacket:nkport(), #state{}) ->
    ok.

conn_stop(Reason, _NkPort, State) ->
    catch handle(ws_terminate, [Reason], State).


%% ===================================================================
%% HTTP Protocol callbacks
%% ===================================================================

%% For HTTP based connections, http_init is called
%% See nkpacket_protocol

http_init(Paths, Req, Env, NkPort) ->
    nkrest_http:init(Paths, Req, Env, NkPort).



%% ===================================================================
%% Requests
%% ===================================================================

%% @private
call_rest_frame(Frame, NkPort, #state{srv=SrvId, user_state=UserState}=State) ->
    trace("calling ws_frame"),
    case ?CALL_SRV(SrvId, ws_frame, [Frame, UserState]) of
        {reply, {text, Text}, UserState2} ->
            do_send({text, Text}, NkPort, State#state{user_state=UserState2});
        {reply, {binary, Bin}, UserState2} ->
            do_send({binary, Bin}, NkPort, State#state{user_state=UserState2});
        {reply, {json, Term}, UserState2} ->
            Text = nklib_json:encode(Term),
            do_send({text, Text}, NkPort, State#state{user_state=UserState2});
        {ok, UserState2} ->
            {ok, State#state{user_state=UserState2}}
    end.


%%%% @private
%%set_debug(NkPort, State) ->
%%    Debug = nkpacket:get_debug(NkPort) == true,
%%    put(nkrest_debug, Debug),
%%    ?DEBUG("debug system activated", [], State).


%% @private
do_send(Msg, NkPort, State) ->
    trace("sending reply"),
    log(debug, "reply data: ~p", [Msg]),
    case nkpacket_connection:send(NkPort, Msg) of
        ok ->
            {ok, State};
        Other ->
            log(notice, "connection send error: ~p", [Other]),
            {stop, normal, State}
    end.


%% @private
handle(Fun, Args, State) ->
    handle_user_call(Fun, Args, State, #state.srv, #state.user_state).


%% @private
%% Will call the service's functions
handle_user_call(Fun, Args, State, PosSrvId, PosUserState) ->
    SrvId = element(PosSrvId, State),
    UserState = element(PosUserState, State),
    Args2 = Args ++ [UserState],
    case ?CALL_SRV(SrvId, Fun, Args2) of
        {reply, Reply, UserState2} ->
            State2 = setelement(PosUserState, State, UserState2),
            {reply, Reply, State2};
        {reply, Reply, UserState2, Time} ->
            State2 = setelement(PosUserState, State, UserState2),
            {reply, Reply, State2, Time};
        {noreply, UserState2} ->
            State2 = setelement(PosUserState, State, UserState2),
            {noreply, State2};
        {noreply, UserState2, Time} ->
            State2 = setelement(PosUserState, State, UserState2),
            {noreply, State2, Time};
        {stop, Reason, Reply, UserState2} ->
            State2 = setelement(PosUserState, State, UserState2),
            {stop, Reason, Reply, State2};
        {stop, Reason, UserState2} ->
            State2 = setelement(PosUserState, State, UserState2),
            {stop, Reason, State2};
        {ok, UserState2} ->
            State2 = setelement(PosUserState, State, UserState2),
            {ok, State2};
        continue ->
            continue;
        Other ->
            lager:warning("invalid response for ~p:~p(~p): ~p", [SrvId, Fun, Args, Other]),
            error(invalid_handle_response)
    end.

