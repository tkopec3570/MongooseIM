%%==============================================================================
%% Copyright 2014 Erlang Solutions Ltd.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%==============================================================================

-module(ejabberd_node_utils).

-export([init/1, init/2,
         restart_application/1, restart_application/2,
         call_fun/3, call_fun/4,
         call_ctl/2, call_ctl/3,
         call_ctl_with_args/3,
         file_exists/1, file_exists/2,
         backup_config_file/1, backup_config_file/2,
         restore_config_file/1, restore_config_file/2,
         modify_config_file/2, modify_config_file/4,
         get_cwd/2]).

-include_lib("common_test/include/ct.hrl").

-define(CWD(Node, Config), ?config({ejabberd_cwd, Node}, Config)).

-define(CURRENT_CFG_PATH(Node, Config),
        filename:join([?CWD(Node, Config), "etc", "ejabberd.cfg"])).

-define(BACKUP_CFG_PATH(Node, Config),
        filename:join([?CWD(Node, Config), "etc","ejabberd.cfg.bak"])).

-define(CFG_TEMPLATE_PATH(Node, Config),
        filename:join([?CWD(Node, Config), "..", "..", "rel", "files",
                       "ejabberd.cfg"])).

-define(CFG_VARS_PATH(Node, Config, File),
        filename:join([?CWD(Node, Config), "..", "..", "rel",
                       File])).

-define(CTL_PATH(Node, Config),
        filename:join([?CWD(Node, Config), "bin", "mongooseimctl"])).

-type ct_config() :: list({Key :: term(), Value :: term()}).

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------

-spec init(ct_config()) -> ct_config().
init(Config) ->
    Node = ct:get_config(ejabberd_node),
    init(Node, Config).

init(Node, Config) ->
    set_ejabberd_node_cwd(Node, Config).

-spec restart_application(atom()) -> ok.
restart_application(ApplicationName) ->
    Node = ct:get_config(ejabberd_node),
    restart_application(Node, ApplicationName).

-spec restart_application(node(), atom()) -> ok.
restart_application(Node, ApplicationName) ->
    ok = ejabberd_node_utils:call_fun(Node, application, stop, [ApplicationName]),
    ok = ejabberd_node_utils:call_fun(Node, application, start, [ApplicationName]).


-spec backup_config_file(ct_config()) -> ct_config().
backup_config_file(Config) ->
    Node = ct:get_config(ejabberd_node),
    backup_config_file(Node, Config).

-spec backup_config_file(node(), ct_config()) -> ct_config().
backup_config_file(Node, Config) ->
    {ok, _} = call_fun(Node, file, copy, [?CURRENT_CFG_PATH(Node, Config),
                                          ?BACKUP_CFG_PATH(Node, Config)]).

-spec restore_config_file(ct_config()) -> ct_config().
restore_config_file(Config) ->
    Node = ct:get_config(ejabberd_node),
    restore_config_file(Node, Config).

-spec restore_config_file(node(), ct_config()) -> ct_config().
restore_config_file(Node, Config) ->
    ok = call_fun(Node, file, rename, [?BACKUP_CFG_PATH(Node, Config),
                                       ?CURRENT_CFG_PATH(Node, Config)]).

-spec call_fun(module(), atom(), []) -> term() | {badrpc, term()}.
call_fun(M, F, A) ->
    Node = ct:get_config(ejabberd_node),
    call_fun(Node, M, F, A).

-spec call_fun(node(), module(), atom(), []) -> term() | {badrpc, term()}.
call_fun(Node, M, F, A) ->
    rpc:call(Node, M, F, A).

%% @doc Calls the mongooseimctl script with given command `Cmd'.
%%
%% For example to restart mongooseim call `call_ctl(restart, Config).'.
-spec call_ctl(atom(), ct_config()) -> term() | term().
call_ctl(Cmd, Config) ->
    Node = ct:get_config(ejabberd_node),
    call_ctl(Node, Cmd, Config).

-spec call_ctl(node(), atom(), ct_config()) -> term() | term().
call_ctl(Node, Cmd, Config) ->
    call_ctl_with_args(Node, [atom_to_list(Cmd)], Config).

-spec call_ctl_with_args(node(), [string()], ct_config()) -> term() | term().
call_ctl_with_args(Node, CmdAndArgs, Config) ->
    OsCmd = string:join([?CTL_PATH(Node, Config) | CmdAndArgs], " "),
    os:cmd(OsCmd).

-spec file_exists(file:name_all()) -> term() | {badrpc, term()}.
file_exists(Filename) ->
    call_fun(filelib, is_file, [Filename]).

-spec file_exists(node(), file:name_all()) -> term() | {badrpc, term()}.
file_exists(Node, Filename) ->
    call_fun(Node, filelib, is_file, [Filename]).

%% @doc Modifies default ejabberd config file: `etc/ejabberd.cfg'.
%%
%% This function assumes that the config file was generated from template
%% file in `rel/files/ejabberd.cfg' using variables from `rel/vars.config'.
%% The modification procedure overrides given variables provided in
%% `rel/vars.config'.
%%
%% For example to change `hosts' value in the configuration file one
%% has to call the function as follows:
%% ```NewHosts = {hosts, "[\"" ++ binary_to_list(Domain) ++ "\"]"},
%%    modify_config_file([NewHosts], Config).'''
-spec modify_config_file([{ConfigVariable, Value}], ct_config()) -> ok when
      ConfigVariable :: atom(),
      Value :: string().
modify_config_file(CfgVarsToChange, Config) ->
    Node = ct:get_config(ejabberd_node),
    modify_config_file(Node, "vars.config", CfgVarsToChange, Config).

-spec modify_config_file(node(), string(), [{ConfigVariable, Value}], ct_config()) -> ok when
      ConfigVariable :: atom(),
      Value :: string().
modify_config_file(Node, VarsFile, CfgVarsToChange, Config) ->
    CurrentCfgPath = ?CURRENT_CFG_PATH(Node, Config),
    {ok, CfgTemplate} = ejabberd_node_utils:call_fun(Node,
                          file, read_file, [?CFG_TEMPLATE_PATH(Node, Config)]),
    {ok, DefaultVars} = ejabberd_node_utils:call_fun(Node, file, consult,
                                                 [?CFG_VARS_PATH(Node, Config, "vars.config")]),
    {ok, NodeVars} = ejabberd_node_utils:call_fun(Node, file, consult,
                                                  [?CFG_VARS_PATH(Node, Config, VarsFile)]),

    PresetVars = case proplists:get_value(preset, Config) of
                     undefined ->
                         [];
                     Name ->
                         Presets = ct:get_config(ejabberd_presets),
                         proplists:get_value(list_to_existing_atom(Name), Presets)
                 end,

    CfgVars1 = dict:to_list(dict:merge(fun(_, V, _) -> V end,
                                      dict:from_list(NodeVars),
                                      dict:from_list(DefaultVars))),

    CfgVars = dict:to_list(dict:merge(fun(_, V, _) -> V end,
                                      dict:from_list(PresetVars),
                                      dict:from_list(CfgVars1))),

    UpdatedCfgVars = update_config_variables(CfgVarsToChange, CfgVars),
    CfgTemplateList = binary_to_list(CfgTemplate),
    UpdatedCfgFile = mustache:render(CfgTemplateList,
                                     dict:from_list(UpdatedCfgVars)),
    ok = ejabberd_node_utils:call_fun(Node, file, write_file, [CurrentCfgPath,
                                                               UpdatedCfgFile]).

-spec get_cwd(node(), ct_config()) -> string().
get_cwd(Node, Config) ->
    ?CWD(Node, Config).

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

set_ejabberd_node_cwd(Node, Config) ->
    {ok, Cwd} = call_fun(Node, file, get_cwd, []),
    [{{ejabberd_cwd, Node}, Cwd} | Config].

update_config_variables(CfgVarsToChange, CfgVars) ->
    lists:foldl(fun({Var, Val}, Acc) ->
                        lists:keystore(Var, 1, Acc,{Var, Val})
                end, CfgVars, CfgVarsToChange).
