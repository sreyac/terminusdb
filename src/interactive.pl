#!/usr/bin/env swipl

/*
 *
 */

:- [load_paths].
:- initialization(main).

initialise_hup :-
    (   current_prolog_flag(unix, true)
    ->  on_signal(hup, _, hup)
    ;   true).

:- initialise_hup.


initialise_log_settings :-
    (   getenv('TERMINUSDB_LOG_PATH', Log_Path)
    ->  set_setting(http:logfile, Log_Path)
    ;   get_time(Time),
        asserta(http_log:log_stream(user_error, Time))).

:-multifile prolog:message//1.

prolog:message(server_missing_config(BasePath)) -->
    [
    'CRITICAL ERROR: Server can\'t be started because the configuration is missing',
    nl,
    nl,
    'Run: ~s/utils/db_init first'-[BasePath],
    nl
    ].


:- reexport(core(util/syntax)).

:- use_module(server(routes)).
:- use_module(server(main)).

% Plugins
%:- use_module(plugins(registry)).

:- use_module(core(query/json_woql),[initialise_woql_contexts/0]).
:- use_module(core(api), [bootstrap_files/0]).

:- use_module(library(http/http_log)).

:- set_test_options([run(manual),concurrent(true)]).

:- use_module(cli(main)).

hup(_Signal) :-
  thread_send_message(main, stop).

main(_Argv) :-
    initialise_log_settings,
    initialise_woql_contexts,
    bootstrap_config_files,
    bootstrap_files,
    debug(terminus(main), 'initialise_woql_contexts completed', []),
    debug(terminus(main), 'initialise_log_settings completed', []).
