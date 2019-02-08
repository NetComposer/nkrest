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

%% @doc Default plugin callbacks
-module(nkrest_callbacks).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([msg/1]).
-export([request/4]).
-export([ws_init/3, ws_frame/2, ws_handle_call/3, ws_handle_cast/2, ws_handle_info/2,
         ws_terminate/2]).

-include("nkrest.hrl").


-define(DEBUG(Txt, Args),
    case erlang:get(nkrest_debug) of
        true -> ?LLOG(debug, Txt, Args);
        _ -> ok
    end).


-define(LLOG(Type, Txt, Args),lager:Type("NkSERVER REST "++Txt, Args)).


%% ===================================================================
%% Types
%% ===================================================================


%% ===================================================================
%% Msg Callbacks
%% ===================================================================

msg(_)   		                    -> continue.


%% ===================================================================
%% REST Callbacks
%% ===================================================================

-type user_state() :: nkrest:user_state().
-type continue() :: nkserver_callbacks:continue().
-type id() :: nkserver:module_id().
-type http_method() :: nkrest_http:method().
-type http_path() :: nkrest_http:path().
-type http_req() :: nkrest_http:req().
-type http_reply() :: nkrest_http:http_reply().
-type nkport() :: nkpacket:nkport().


%% @doc called when a new http request has been received
-spec request(http_method(), http_path(), http_req(), user_state()) ->
    http_reply() |
    {redirect, Path::binary(), http_req()} |
    {cowboy_static, cowboy_static:opts()} |
    {cowboy_rest, Callback::module(), State::term()}.

request(Method, Path, #{srv:=SrvId}=Req, _State) ->
    #{peer:=Peer} = Req,
    ?LLOG(debug, "path not found (~p, ~s): ~p from ~s", [SrvId, Method, Path, Peer]),
    {http, 404, [], <<"NkSERVER REST: Path Not Found">>, Req}.

%%request(SrvId, Method, Path, #{srv:=SrvId}=Req) ->
%%    case nkserver:get_plugin_config(SrvId, nkrest, requestCallBack) of
%%        #{class:=luerl, luerl_fun:=_}=CB ->
%%            case nkserver_luerl_instance:spawn_callback_spec(SrvId, CB) of
%%                {ok, Pid} ->
%%                    process_luerl_req(SrvId, CB, Pid, Req);
%%                {error, too_many_instances} ->
%%                    {http, 429, [], <<"NkSERVER REST: Too many requests">>, Req}
%%            end;
%%        _ ->
%%            % There is no callback defined
%%            #{peer:=Peer} = Req,
%%            ?LLOG(debug, "path not found (~p, ~s): ~p from ~s", [SrvId, Method, Path, Peer]),
%%            {http, 404, [], <<"NkSERVER REST: Path Not Found">>, Req}
%%    end.



%% ===================================================================
%% WS Callbacks
%% ===================================================================


%% @doc Called when a new connection starts
-spec ws_init(id(), nkport(), user_state()) ->
    {ok, user_state()} | {stop, term()}.

ws_init(_Id, _NkPort, State) ->
    {ok, State}.


%% @doc Called when a new connection starts
-spec ws_frame({text, binary()}|{binary, binary()}, user_state()) ->
    {ok, user_state()} | {reply, Msg, user_state()}
    when Msg :: {text, iolist()} | {binary, iolist()} | {json, term()}.

ws_frame(_Frame, State) ->
    ?LLOG(notice, "unhandled data ~p", [_Frame]),
    {ok, State}.


%% @doc Called when the process receives a handle_call/3.
-spec ws_handle_call(term(), {pid(), reference()}, user_state()) ->
    {ok, user_state()} | continue().

ws_handle_call(Msg, _From, State) ->
    ?LLOG(error, "unexpected call ~p", [Msg]),
    {ok, State}.


%% @doc Called when the process receives a handle_cast/3.
-spec ws_handle_cast(term(), user_state()) ->
    {ok, user_state()} | continue().

ws_handle_cast(Msg, State) ->
    ?LLOG(error, "unexpected cast ~p", [Msg]),
    {ok, State}.


%% @doc Called when the process receives a handle_info/3.
-spec ws_handle_info(term(), user_state()) ->
    {ok, user_state()} | continue().

ws_handle_info(Msg, State) ->
    ?LLOG(error, "unexpected info ~p", [Msg]),
    {ok, State}.


%% @doc Called when a service is stopped
-spec ws_terminate(term(), user_state()) ->
    {ok, user_state()}.

ws_terminate(_Reason, State) ->
    {ok, State}.




%% ===================================================================
%% Internal
%% ===================================================================

%%process_luerl_req(PackageId, CBSpec, Pid, Req) ->
%%    Start = nklib_util:l_timestamp(),
%%    case nkrest_http:make_req_ext(PackageId, Req) of
%%        {ok, ReqInfo, Req2} ->
%%            ?DEBUG("script spawn time: ~pusecs", [nklib_util:l_timestamp() - Start]),
%%            ?DEBUG("calling info: ~p", [ReqInfo]),
%%            case
%%                nkserver_luerl_instance:call_callback(Pid, CBSpec, [ReqInfo])
%%            of
%%                {ok, [Reply]} ->
%%                    nkrest_http:reply_req_ext(Reply, Req2);
%%                {ok, Other} ->
%%                    ?LLOG(notice, "invalid reply from script ~s: ~p", [PackageId, Other]),
%%                    {http, 500, [], "NkSERVER REST: Reply response error", Req2};
%%                {error, Error} ->
%%                    ?LLOG(notice, "invalid reply from script ~s: ~p", [PackageId, Error]),
%%                    {http, 500, [], "NkSERVER REST: Reply response error", Req2}
%%            end;
%%        {error, Error} ->
%%            ?LLOG(notice, "invalid reply from script ~s: ~p", [PackageId, Error]),
%%            {http, 500, [], "NkSERVER REST: Reply response error", Req}
%%    end.
