-module(vmq_mqtt5_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("vmq_commons/include/vmq_types_mqtt5.hrl").

init_per_suite(Config) ->
    vmq_test_utils:setup(),
    vmq_server_cmd:listener_start(1888, []),
    cover:start(),
    Config.

end_per_suite(_Config) ->
    vmq_test_utils:teardown(),
    ok.

init_per_testcase(_TestCase, Config) ->
    vmq_server_cmd:set_config(allow_anonymous, false),
    vmq_server_cmd:set_config(max_client_id_size, 50),
    vmq_config:configure_node(),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

all() ->
    [
     {group, mqtt}
    ].

groups() ->
    ConnectTests =
    [anon_success,
     empty_client_id,
     invalid_id,
     session_take_over,
     %% uname_no_password_success,
     %% password_no_uname_success,
     %% uname_password_denied,
     %% uname_password_success,
     %% change_subscriber_id,
     enhanced_authentication,
     enhanced_auth_no_other_packets,
     enhanced_auth_method_not_supported,
     enhanced_auth_server_rejects,
     enhanced_auth_new_auth_method_fails,
     reauthenticate,
     reauthenticate_server_rejects
    ],
    [
     {mqtt, [shuffle], ConnectTests}
    ].

anon_success(_Config) ->
    vmq_server_cmd:set_config(allow_anonymous, true),
    vmq_config:configure_node(),
    Connect = packetv5:gen_connect("connect-success-test", [{keepalive,10}]),
    {ok, Socket, Connack, <<>>} = packetv5:do_client_connect(Connect, []),
    #mqtt5_connack{session_present = 0,
                   reason_code = ?M5_CONNACK_ACCEPT,
                   properties = #{}}
        = Connack,
    ok = gen_tcp:close(Socket).

empty_client_id(_Config) ->
    %% A Server MAY allow a Client to supply a ClientID that has a
    %% length of zero bytes, however if it does so the Server MUST
    %% treat this as a special case and assign a unique ClientID to
    %% that Client [MQTT-3.1.3-6]. It MUST then process the CONNECT
    %% packet as if the Client had provided that unique ClientID, and
    %% MUST return the Assigned Client Identifier in the CONNACK
    %% packet [MQTT-3.1.3-7].
    vmq_server_cmd:set_config(allow_anonymous, true),
    vmq_config:configure_node(),
    CSTrue = packetv5:gen_connect(empty, [{keepalive,10}, {clean_start, true}]),
    {ok, Socket0, Connack0, <<>>} = packetv5:do_client_connect(CSTrue, []),
    #mqtt5_connack{session_present = 0,
                   reason_code = ?M5_CONNACK_ACCEPT,
                   properties = #{p_assigned_client_id := _}}
        = Connack0,
    ok = gen_tcp:close(Socket0),

    CSFalse = packetv5:gen_connect(empty, [{keepalive,10}, {clean_start, false}]),
    {ok, Socket1, Connack1, <<>>} = packetv5:do_client_connect(CSFalse, []),
    #mqtt5_connack{session_present = 0,
                   reason_code = ?M5_CONNACK_ACCEPT,
                   properties = #{p_assigned_client_id := _}}
        = Connack1,
    ok = gen_tcp:close(Socket1).

invalid_id(_Config) ->
    %% If the Server rejects the ClientID it MAY respond to the
    %% CONNECT packet with a CONNACK using Reason Code 0x85 (Client
    %% Identifier not valid) as described in section 4.13 Handling
    %% errors, and then itMUST close the Network Connection
    %% [MQTT-3.1.3-8].
    Id = <<"this client id is longer than the set limit of 23 bytes and thus invalid">>,
    Connect = packetv5:gen_connect(Id, [{keepalive,10}]),
    Connack = packetv5:gen_connack(0, ?M5_CLIENT_IDENTIFIER_NOT_VALID),
    {ok, Socket} = packetv5:do_client_connect(Connect, Connack, []),
    ok = gen_tcp:close(Socket).

session_take_over(_Config) ->
    %% If the ClientID represents a Client already connected to the
    %% Server, the Server send a DISCONNECT packet to the existing
    %% Client with Reason Code of 0x8E (Session taken over) as
    %% described in section 4.13 and MUST close the Network Connection
    %% of the existing Client [MQTT-3.1.4-3].
    vmq_server_cmd:set_config(allow_anonymous, true),
    vmq_server_cmd:set_config(max_client_id_size, 50),
    vmq_config:configure_node(),
    Connect = packetv5:gen_connect("connect-session-takeover", [{keepalive,10}]),
    Connack = packetv5:gen_connack(),
    {ok, Socket} = packetv5:do_client_connect(Connect, Connack, []),
    {ok, NewSocket} = packetv5:do_client_connect(Connect, Connack, []),
    Disconnect = packetv5:gen_disconnect(?M5_SESSION_TAKEN_OVER, #{}),
    ok = packetv5:expect_frame(Socket, Disconnect),
    ok = gen_tcp:close(Socket),
    ok = gen_tcp:close(NewSocket).

uname_no_password_success(_Config) ->
    %% Connect = packet:gen_connect("connect-uname-test-", [{keepalive,10}, {username, "user"}]),
    %% Connack = packet:gen_connack(4),
    %% ok = vmq_plugin_mgr:enable_module_plugin(
    %%   auth_on_register, ?MODULE, hook_uname_no_password_denied, 5),
    %% {ok, Socket} = packet:do_client_connect(Connect, Connack, []),
    %% ok = vmq_plugin_mgr:disable_module_plugin(
    %%   auth_on_register, ?MODULE, hook_uname_no_password_denied, 5),
    %% ok = gen_tcp:close(Socket).
    throw(not_implemented).

password_no_uname_success(_Config) ->
    throw(not_implemented).

uname_password_denied(_Config) ->
    throw(not_implemented).

uname_password_success(_Config) ->
    throw(not_implemented).

change_subscriber_id(_Config) ->
    %% TODO: should we be allowed to do this? If we should, should we
    %% then respond with the assigned_client_id property?
    throw(not_implemented).

-define(AUTH_METHOD, <<"AuthMethod">>).

enhanced_authentication(_Config) ->
    %% If the Server requires additional information to complete the
    %% authentication, it can send an AUTH packet to the Client. This
    %% packet MUST contain a Reason Code of 0x18 (Continue
    %% authentication) [MQTT-4.12.0- 2].

    %% The Client responds to an AUTH packet from the Server by
    %% sending a further AUTH packet. This packet MUST contain a
    %% Reason Code of 0x18 (Continue authentication) [MQTT-4.12.0-3].

    ok = vmq_plugin_mgr:enable_module_plugin(
           auth_on_register, ?MODULE, auth_on_register_ok_hook, 6),
    ok = vmq_plugin_mgr:enable_module_plugin(
           on_auth, ?MODULE, on_auth_hook, 1),

    ClientId = "client-enhanced-auth",
    Connect = packetv5:gen_connect(ClientId, [{keepalive, 10},
                                              {properties, auth_props(?AUTH_METHOD,<<"Client1">>)}]),
    AuthIn1 = packetv5:gen_auth(?M5_CONTINUE_AUTHENTICATION, auth_props(?AUTH_METHOD,<<"Server1">>)),
    {ok, Socket} = packetv5:do_client_connect(Connect, AuthIn1, []),
    AuthOut1 = packetv5:gen_auth(?M5_CONTINUE_AUTHENTICATION, auth_props(?AUTH_METHOD,<<"Client2">>)),
    ok = gen_tcp:send(Socket, AuthOut1),
    AuthIn2 = packetv5:gen_auth(?M5_CONTINUE_AUTHENTICATION, auth_props(?AUTH_METHOD,<<"Server2">>)),
    ok = packetv5:expect_frame(Socket, AuthIn2),
    AuthOut2 = packetv5:gen_auth(?M5_CONTINUE_AUTHENTICATION, auth_props(?AUTH_METHOD,<<"Client3">>)),
    ok = gen_tcp:send(Socket, AuthOut2),
    Connack = packetv5:gen_connack(0, ?M5_SUCCESS, auth_props(?AUTH_METHOD,<<"ServerFinal">>)),
    ok = packetv5:expect_frame(Socket, Connack),
    ok = gen_tcp:close(Socket),

    ok = vmq_plugin_mgr:disable_module_plugin(
           on_auth, ?MODULE, on_auth_hook, 1),
    ok = vmq_plugin_mgr:disable_module_plugin(
           auth_on_register, ?MODULE, auth_on_register_ok_hook, 6).

enhanced_auth_no_other_packets(_Config) ->
    %% If a Client sets an Authentication Method in the CONNECT, the
    %% Client MUST NOT send any packets other than AUTH or DISCONNECT
    %% packets until it has received a CONNACK packet [MQTT-3.1.2-30].

    ok = vmq_plugin_mgr:enable_module_plugin(
           auth_on_register, ?MODULE, auth_on_register_ok_hook, 6),
    ok = vmq_plugin_mgr:enable_module_plugin(
           on_auth, ?MODULE, on_auth_hook, 1),

    ClientId = "client-enh-auth-wrong-packet",
    Connect = packetv5:gen_connect(ClientId, [{keepalive, 10},
                                              {properties, auth_props(?AUTH_METHOD,<<"Client1">>)}]),
    AuthIn1 = packetv5:gen_auth(?M5_CONTINUE_AUTHENTICATION, auth_props(?AUTH_METHOD,<<"Server1">>)),
    {ok, Socket} = packetv5:do_client_connect(Connect, AuthIn1, []),
    Ping = packetv5:gen_pingreq(),
    ok = gen_tcp:send(Socket, Ping),
    Disconnect = packetv5:gen_disconnect(?M5_PROTOCOL_ERROR, #{}),
    ok = packetv5:expect_frame(Socket, Disconnect),
    {error, closed} = gen_tcp:recv(Socket, 0, 1000),

    ok = vmq_plugin_mgr:disable_module_plugin(
           on_auth, ?MODULE, on_auth_hook, 1),
    ok = vmq_plugin_mgr:disable_module_plugin(
           auth_on_register, ?MODULE, auth_on_register_ok_hook, 6).

enhanced_auth_method_not_supported(_Config) ->
    %% If the Server does not support the Authentication Method
    %% supplied by the Client, it MAY send a CONNACK with a Reason
    %% Code of 0x8C (Bad authentication method) or 0x87 (Not
    %% Authorized) as described in section 4.13 and MUST close the
    %% Network Connection [MQTT-4.12.0-1].

    ok = vmq_plugin_mgr:enable_module_plugin(
           auth_on_register, ?MODULE, auth_on_register_ok_hook, 6),
    ok = vmq_plugin_mgr:enable_module_plugin(
           on_auth, ?MODULE, on_auth_bad_method_hook, 1),

    ClientId = "client-enh-auth-bad-auth",
    Connect = packetv5:gen_connect(ClientId, [{keepalive, 10},
                                              {properties, auth_props(?AUTH_METHOD,<<"Client1">>)}]),
    Disconnect = packetv5:gen_disconnect(?M5_BAD_AUTHENTICATION_METHOD, #{}),
    {ok, Socket} = packetv5:do_client_connect(Connect, Disconnect, []),
    {error, closed} = gen_tcp:recv(Socket, 0,100),

    ok = vmq_plugin_mgr:disable_module_plugin(
           on_auth, ?MODULE, on_auth_bad_method_hook, 1),
    ok = vmq_plugin_mgr:disable_module_plugin(
           auth_on_register, ?MODULE, auth_on_register_ok_hook, 6).


enhanced_auth_server_rejects(_Config) ->
    %% The Server can reject the authentication at any point in this
    %% process. It MAY send a CONNACK with a Reason Code of 0x80 or
    %% above as described in section 4.13, and MUST close the Network
    %% Connection [MQTT-4.12.0-4].
    throw(not_implemented).

enhanced_auth_new_auth_method_fails(_Config) ->
    %% If the initial CONNECT packet included an Authentication Method
    %% property then all AUTH packets, and any successful CONNACK
    %% packet MUST include an Authentication Method Property with the
    %% same value as in the CONNECT packet [MQTT-4.12.0-5].

    ok = vmq_plugin_mgr:enable_module_plugin(
           auth_on_register, ?MODULE, auth_on_register_ok_hook, 6),
    ok = vmq_plugin_mgr:enable_module_plugin(
           on_auth, ?MODULE, on_auth_hook, 1),

    ClientId = "client-enhanced-auth-wrong-method",
    Connect = packetv5:gen_connect(ClientId, [{keepalive, 10},
                                              {properties, auth_props(?AUTH_METHOD,<<"Client1">>)}]),
    AuthIn1 = packetv5:gen_auth(?M5_CONTINUE_AUTHENTICATION, auth_props(?AUTH_METHOD,<<"Server1">>)),
    {ok, Socket} = packetv5:do_client_connect(Connect, AuthIn1, []),
    AuthOut1 = packetv5:gen_auth(?M5_CONTINUE_AUTHENTICATION, auth_props(<<"WRONG AUTH METHOD">>,<<"Client2">>)),
    ok = gen_tcp:send(Socket, AuthOut1),
    Disconnect = packetv5:gen_disconnect(?M5_PROTOCOL_ERROR, #{}),
    ok = packetv5:expect_frame(Socket, Disconnect),
    {error, closed} = gen_tcp:recv(Socket, 0, 100),

    ok = vmq_plugin_mgr:disable_module_plugin(
           on_auth, ?MODULE, on_auth_hook, 1),
    ok = vmq_plugin_mgr:disable_module_plugin(
           auth_on_register, ?MODULE, auth_on_register_ok_hook, 6).

reauthenticate(_Config) ->
    %% If the Client supplied an Authentication Method in the CONNECT
    %% packet it can initiate a re-authentication at any time after
    %% receiving a CONNACK. It does this by sending an AUTH packet
    %% with a Reason Code of 0x19 (Re-authentication). The Client MUST
    %% set the Authentication Method to the same value as the
    %% Authentication Method originally used to authenticate the
    %% Network Connection [MQTT-4.12.1-1]

    ok = vmq_plugin_mgr:enable_module_plugin(
           auth_on_register, ?MODULE, auth_on_register_ok_hook, 6),
    ok = vmq_plugin_mgr:enable_module_plugin(
           on_auth, ?MODULE, on_auth_hook, 1),
    ok = vmq_plugin_mgr:enable_module_plugin(
           auth_on_publish, ?MODULE, auth_on_publish_after_reauth, 6),

    ClientId = "client-enhanced-re-auth",
    Connect = packetv5:gen_connect(ClientId, [{keepalive, 10},
                                              {properties, auth_props(?AUTH_METHOD,<<"Client1">>)}]),
    AuthIn1 = packetv5:gen_auth(?M5_CONTINUE_AUTHENTICATION, auth_props(?AUTH_METHOD,<<"Server1">>)),
    {ok, Socket} = packetv5:do_client_connect(Connect, AuthIn1, []),
    AuthOut1 = packetv5:gen_auth(?M5_CONTINUE_AUTHENTICATION, auth_props(?AUTH_METHOD,<<"Client2">>)),
    ok = gen_tcp:send(Socket, AuthOut1),
    AuthIn2 = packetv5:gen_auth(?M5_CONTINUE_AUTHENTICATION, auth_props(?AUTH_METHOD,<<"Server2">>)),
    ok = packetv5:expect_frame(Socket, AuthIn2),
    AuthOut2 = packetv5:gen_auth(?M5_CONTINUE_AUTHENTICATION, auth_props(?AUTH_METHOD,<<"Client3">>)),
    ok = gen_tcp:send(Socket, AuthOut2),
    Connack = packetv5:gen_connack(0, ?M5_SUCCESS, auth_props(?AUTH_METHOD,<<"ServerFinal">>)),
    ok = packetv5:expect_frame(Socket, Connack),

    %% Now, let's try to reauthenticate (shorter flow)
    ReAuthOut1 = packetv5:gen_auth(?M5_REAUTHENTICATE, auth_props(?AUTH_METHOD,<<"Reauth">>)),
    ok = gen_tcp:send(Socket, ReAuthOut1),
    ReAuthIn1 = packetv5:gen_auth(?M5_SUCCESS, auth_props(?AUTH_METHOD,<<"ReauthOK">>)),
    ok = packetv5:expect_frame(Socket, ReAuthIn1),

    %% trigger publish hook to check the new username
    Publish = packetv5:gen_publish("some/topic", 1, <<"some payload">>, [{mid, 1}]),
    ok = gen_tcp:send(Socket, Publish),
    Puback = packetv5:gen_puback(1),
    ok = packetv5:expect_frame(Socket, Puback),
    ok = gen_tcp:close(Socket),

    ok = vmq_plugin_mgr:disable_module_plugin(
           auth_on_publish, ?MODULE, auth_on_publish_after_reauth, 6),
    ok = vmq_plugin_mgr:disable_module_plugin(
           on_auth, ?MODULE, on_auth_hook, 1),
    ok = vmq_plugin_mgr:disable_module_plugin(
           auth_on_register, ?MODULE, auth_on_register_ok_hook, 6).

reauthenticate_server_rejects(_Config) ->
    %% If the re-authentication fails, the Client or Server SHOULD
    %% send DISCONNECT with an appropriate Reason Code as described in
    %% section 4.13, and MUST close the Network Connection
    %% [MQTT-4.12.1-2].
    throw(not_implemented).

%%%%% Helpers %%%%%
auth_props(Method, Data) ->
    #{p_authentication_method => Method,
      p_authentication_data => Data}.

%%%%%% Hooks implementations %%%%%

auth_on_register_ok_hook(_,_,_,_,_,_) ->
    ok.

on_auth_bad_method_hook(#{p_authentication_method := _, p_authentication_data := _}) ->
    {error, bad_auth_method}.

on_auth_hook(#{p_authentication_method := ?AUTH_METHOD, p_authentication_data := <<"Client1">>}) ->
    {continue_auth, [{properties,
                      #{p_authentication_method => ?AUTH_METHOD, p_authentication_data => <<"Server1">>}}]};
on_auth_hook(#{p_authentication_method := ?AUTH_METHOD, p_authentication_data := <<"Client2">>}) ->
    {continue_auth, [{properties,
                      #{p_authentication_method => ?AUTH_METHOD, p_authentication_data => <<"Server2">>}}]};
on_auth_hook(#{p_authentication_method := ?AUTH_METHOD, p_authentication_data := <<"Client3">>}) ->
    %% return ok which will trigger the connack being sent to the
    %% client *or* an AUTH ok
    {ok, [{properties, #{p_authentication_method => ?AUTH_METHOD, p_authentication_data => <<"ServerFinal">>}}]};
on_auth_hook(#{p_authentication_method := ?AUTH_METHOD, p_authentication_data := <<"Reauth">>}) ->
    {ok, [{properties, #{p_authentication_method => ?AUTH_METHOD, p_authentication_data => <<"ReauthOK">>}},
          {username, <<"newusername">>}]}.


auth_on_publish_after_reauth(
  <<"newusername">>, _, 1, [<<"some">>, <<"topic">>], <<"some payload">>, false) ->
    ok.
