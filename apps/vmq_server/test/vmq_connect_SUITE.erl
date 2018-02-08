-module(vmq_connect_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

%% ===================================================================
%% common_test callbacks
%% ===================================================================
init_per_suite(_Config) ->
    cover:start(),
    vmq_test_utils:setup(),
    _Config.

end_per_suite(_Config) ->
    vmq_test_utils:teardown(),
    _Config.

init_per_group(mqtt, Config) ->
    Port = 1888,
    Address = "127.0.0.1",
    Opts = [],
    vmq_server_cmd:listener_start(Port, Address, Opts),
    [{address, Address},{port, Port},{opts, Opts}|Config].

end_per_group(mqtt, Config) ->
    Port = proplists:get_value(port, Config),
    Address = proplists:get_value(address, Config),
    vmq_server_cmd:listener_stop(Port, Address, false),
    ok.

init_per_testcase(_Case, Config) ->
    %% reset config before each test
    vmq_server_cmd:set_config(allow_anonymous, false),
    vmq_server_cmd:set_config(max_client_id_size, 23),
    vmq_config:configure_node(),
    Config.

end_per_testcase(_, Config) ->
    Config.

all() ->
    [
     {group, mqtt}
    ].

groups() ->
    Tests = 
        [anon_denied_test,
         anon_success_test,
         invalid_id_0_test,
         invalid_id_0_311_test,
         invalid_id_missing_test,
         invalid_id_24_test,
         invalid_protonum_test,
         uname_no_password_denied_test,
         uname_password_denied_test,
         uname_password_success_test,
         change_subscriber_id_test
        ],
    [
     {mqtt, [], Tests}
    ].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Actual Tests
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
anon_denied_test(_) ->
    Connect = packet:gen_connect("connect-anon-test", [{keepalive,10}]),
    Connack = packet:gen_connack(5),
    {ok, Socket} = packet:do_client_connect(Connect, Connack, []),
    ok = gen_tcp:close(Socket).

anon_success_test(_) ->
    vmq_server_cmd:set_config(allow_anonymous, true),
    vmq_config:configure_node(),
    %% allow_anonymous is proxied through vmq_config.erl
    Connect = packet:gen_connect("connect-success-test", [{keepalive,10}]),
    Connack = packet:gen_connack(0),
    {ok, Socket} = packet:do_client_connect(Connect, Connack, []),
    ok = gen_tcp:close(Socket).

invalid_id_0_test(_) ->
    Connect = packet:gen_connect(empty, [{keepalive,10}]),
    Connack = packet:gen_connack(2),
    {ok, Socket} = packet:do_client_connect(Connect, Connack, []),
    ok = gen_tcp:close(Socket).

invalid_id_0_311_test(_) ->
    Connect = packet:gen_connect(empty, [{keepalive,10},{proto_ver,4}]),
    Connack = packet:gen_connack(0),
    vmq_server_cmd:set_config(allow_anonymous, false),
    ok = vmq_plugin_mgr:enable_module_plugin(
      auth_on_register, ?MODULE, hook_empty_client_id_proto_4, 5),
    {ok, Socket} = packet:do_client_connect(Connect, Connack, []),
    ok = vmq_plugin_mgr:disable_module_plugin(
      auth_on_register, ?MODULE, hook_empty_client_id_proto_4, 5),
    ok = gen_tcp:close(Socket).

invalid_id_missing_test(_) ->
    Connect = packet:gen_connect(undefined, [{keepalive,10}]),
    {error, closed} = packet:do_client_connect(Connect, <<>>, []).

invalid_id_24_test(_) ->
    Connect = packet:gen_connect("connect-invalid-id-test-", [{keepalive,10}]),
    Connack = packet:gen_connack(2), %% client id longer than 23 Characters
    {ok, Socket} = packet:do_client_connect(Connect, Connack, []),
    ok = gen_tcp:close(Socket).

invalid_protonum_test(_) ->
    %% mosq_test.gen_connect("test", keepalive=10, proto_ver=0)
    Connect = <<16#10,16#12,16#00,16#06,16#4d,16#51,16#49,16#73,
                16#64,16#70,16#00,16#02,16#00,16#0a,16#00,16#04,
                16#74,16#65,16#73,16#74>>,
    Connack = packet:gen_connack(1),
    {ok, Socket} = packet:do_client_connect(Connect, Connack, []),
    ok = gen_tcp:close(Socket).

uname_no_password_denied_test(_) ->
    Connect = packet:gen_connect("connect-uname-test-", [{keepalive,10}, {username, "user"}]),
    Connack = packet:gen_connack(4),
    ok = vmq_plugin_mgr:enable_module_plugin(
      auth_on_register, ?MODULE, hook_uname_no_password_denied, 5),
    {ok, Socket} = packet:do_client_connect(Connect, Connack, []),
    ok = vmq_plugin_mgr:disable_module_plugin(
      auth_on_register, ?MODULE, hook_uname_no_password_denied, 5),
    ok = gen_tcp:close(Socket).

uname_password_denied_test(_) ->
    Connect = packet:gen_connect("connect-uname-pwd-test", [{keepalive,10}, {username, "user"},
                                                            {password, "password9"}]),
    Connack = packet:gen_connack(4),
    ok = vmq_plugin_mgr:enable_module_plugin(
      auth_on_register, ?MODULE, hook_uname_password_denied, 5),
    {ok, Socket} = packet:do_client_connect(Connect, Connack, []),
    ok = vmq_plugin_mgr:disable_module_plugin(
      auth_on_register, ?MODULE, hook_uname_password_denied, 5),
    ok = gen_tcp:close(Socket).

uname_password_success_test(_) ->
    Connect = packet:gen_connect("connect-uname-pwd-test", [{keepalive,10}, {username, "user"},
                                                            {password, "password9"}]),
    Connack = packet:gen_connack(0),
    ok = vmq_plugin_mgr:enable_module_plugin(
      auth_on_register, ?MODULE, hook_uname_password_success, 5),
    {ok, Socket} = packet:do_client_connect(Connect, Connack, []),
    ok = vmq_plugin_mgr:disable_module_plugin(
      auth_on_register, ?MODULE, hook_uname_password_success, 5),
    ok = gen_tcp:close(Socket).

change_subscriber_id_test(_) ->
    Connect = packet:gen_connect("change-sub-id-test",
                                 [{keepalive,10}, {username, "whatever"},
                                  {password, "whatever"}]),
    Connack = packet:gen_connack(0),
    ok = vmq_plugin_mgr:enable_module_plugin(
      auth_on_register, ?MODULE, hook_change_subscriber_id, 5),
    ok = vmq_plugin_mgr:enable_module_plugin(
      on_register, ?MODULE, hook_on_register_changed_subscriber_id, 3),
    {ok, Socket} = packet:do_client_connect(Connect, Connack, []),
    ok = vmq_plugin_mgr:disable_module_plugin(
      on_register, ?MODULE, hook_on_register_changed_subscriber_id, 3),
    ok = vmq_plugin_mgr:disable_module_plugin(
      auth_on_register, ?MODULE, hook_change_subscriber_id, 5),
    ok = gen_tcp:close(Socket).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Hooks
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
hook_empty_client_id_proto_4(_, _RandomId, _, _, _) -> ok.
hook_uname_no_password_denied(_, {"", <<"connect-uname-test-">>}, <<"user">>, undefined, _) -> {error, invalid_credentials}.
hook_uname_password_denied(_, {"", <<"connect-uname-pwd-test">>}, <<"user">>, <<"password9">>, _) -> {error, invalid_credentials}.
hook_uname_password_success(_, {"", <<"connect-uname-pwd-test">>}, <<"user">>, <<"password9">>, _) -> ok.
hook_change_subscriber_id(_, {"", <<"change-sub-id-test">>}, _, _, _) ->
    {ok, [{subscriber_id, {"newmp", <<"changed-client-id">>}}]}.
hook_on_register_changed_subscriber_id(_, {"newmp", <<"changed-client-id">>}, _) ->
    ok.
