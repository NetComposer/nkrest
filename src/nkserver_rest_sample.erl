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
-module(nkserver_rest_sample).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

%%-define(WS, "wss://127.0.0.1:9010/ws").
%%-define(HTTP, "https://127.0.0.1:9010/rpc/api").

-include_lib("nkserver/include/nkserver_module.hrl").

-export([start/0, stop/0, test1/0, test2/0, test3/0]).
-export([request/4, ws_frame/2]).


-compile(export_all).
-compile(nowarn_export_all).


-dialyzer({nowarn_function, start/0}).

%% ===================================================================
%% Public
%% ===================================================================


%% @doc Starts the service
start() ->
    {ok, _} = nkserver_rest:start_link(?MODULE, #{
        url => "https://node:9010/test1, wss:node:9010/test1/ws;idle_timeout=5000",
        opts => #{
            cowboy_opts => #{max_headers=>100}  % To test in nkpacket
        },
        debug => [nkpacket, http, ws]
    }).


%% @doc Stops the service
stop() ->
    nkserver_rest:stop(?MODULE).


test1() ->
    Url = "https://127.0.0.1:9010/test1/test-a?b=1&c=2",
    {ok, {{_, 200, _}, Hs, B}} = httpc:request(post, {Url, [], "test/test", "body1"}, [], []),
    [1] = nklib_util:get_value("header1", Hs),
    #{
        <<"ct">> := <<"test/test">>,
        <<"qs">> := #{<<"b">>:=<<"1">>, <<"c">>:=<<"2">>},
        <<"body">> := <<"body1">>
    } =
        nklib_json:decode(B),
    ok.


test2() ->
    Url1 = "https://127.0.0.1:9010/test1/index.html",
    {ok, {{_, 200, _}, _, "<!DOC"++_}} = httpc:request(Url1),
    Url2 = "https://127.0.0.1:9010/test1/",
    {ok, {{_, 200, _}, _, "<!DOC"++_}} = httpc:request(Url2),
    Url3 = "https://127.0.0.1:9010/test1",
    {ok, {{_, 200, _}, _, "<!DOC"++_}} = httpc:request(Url3),
    Url4 = "https://127.0.0.1:9010/test1/dir/hi.txt",
    {ok, {{_, 200, _}, _, "nkserver"}} = httpc:request(Url4),
    ok.


test3() ->
    {ok, ConnPid} = gun:open("127.0.0.1", 9010, #{transport=>ssl}),
    receive {gun_up, _Pid, http} -> ok after 100 -> error(?LINE) end,
    gun:ws_upgrade(ConnPid, "/test1/ws"),
    receive {gun_upgrade, _, _, _, _} -> ok after 100 -> error(?LINE) end,
    gun:ws_send(ConnPid, {text, "text1"}),
    receive {gun_ws, _, _, {text, <<"Reply: text1">>}} -> ok after 100 -> error(?LINE) end,
    gun:ws_send(ConnPid, {binary, <<"text2">>}),
    receive {gun_ws, _, _, {binary, <<"Reply2: text2">>}} -> ok after 100 -> error(?LINE) end,
    gun:ws_send(ConnPid, {text, nklib_json:encode(#{a=>1})}),
    Json = receive {gun_ws, _, _, {text, J}} -> J after 100 -> error(?LINE) end,
    #{<<"a">>:=1, <<"b">>:=2} = nklib_json:decode(Json),
    gun:close(ConnPid),
    gun:flush(ConnPid),
    ok.


%%test4() ->
%%    Url = "https://127.0.0.1:9010/test2/test-a?b=1&c=2",
%%    {ok, {{_, 200, _}, Hs, B}} = httpc:request(post, {Url, [], "test/test", "body1"}, [], []),
%%    "1.0" = nklib_util:get_value("header1", Hs),
%%    #{
%%        <<"ct">> := <<"test/test">>,
%%        <<"qs">> := #{<<"b">>:=<<"1">>, <<"c">>:=<<"2">>},
%%        <<"body">> := <<"body1">>
%%    } =
%%        nklib_json:decode(B),
%%    {ok, {{_, 501, _}, _, _}} = httpc:request(Url),
%%    ok.





%% ===================================================================
%% API callbacks
%% ===================================================================

% Redirect .../test1/
request(<<"GET">>, [<<>>], _Req, _State) ->
    {redirect, "/index.html"};

% Redirect .../test1
request(<<"GET">>, [], _Req, _State) ->
    {redirect, "/index.html"};

request(<<"GET">>, _Paths, _Req, _State) ->
    lager:error("NKLOG STATIC ~p", [_Paths]),
    {cowboy_static, {priv_dir, nkserver_rest, "/www"}};

request(<<"POST">>, [<<"test-a">>], #{content_type:=CT}=Req, _State) ->
    {ok, Body, Req2} = nkserver_rest_http:get_body(Req, #{parse=>true}),
    Qs = nkserver_rest_http:get_qs(Req),
    Reply = nklib_json:encode(#{qs=>maps:from_list(Qs), ct=>CT, body=>Body}),
    {http, 200, #{<<"header1">> => 1}, Reply, Req2};

request(_Method, _Path, _Req, _State) ->
    lager:error("NKLOG OTHER"),
    continue.


ws_frame({text, <<"{", _/binary>>=Json}, State) ->
    Decode1 = nklib_json:decode(Json),
    Decode2 = Decode1#{b=>2},
    {reply, {json, Decode2}, State};

ws_frame({text, Text}, State) ->
    {reply, {text, <<"Reply: ", Text/binary>>}, State};

ws_frame({binary, Bin}, State) ->
    {reply, {binary, <<"Reply2: ", Bin/binary>>}, State}.
