:- module(test_utils,[
              try/1,
              status_200/1,
              admin_pass/1,
              setup_temp_store/1,
              setup_unattached_store/1,
              teardown_temp_store/1,
              teardown_unattached_store/1,
              with_temp_store/1,
              ensure_label/1,
              layer_schema_context_from_label_descriptor/2,
              layer_schema_context_from_label_descriptor/3,
              ref_schema_context_from_label_descriptor/2,
              ref_schema_context_from_label_descriptor/3,
              repo_schema_context_from_label_descriptor/2,
              repo_schema_context_from_label_descriptor/3,
              create_db_with_test_schema/2,
              create_db_without_schema/2,
              create_db_with_empty_schema/2,
              create_db_with_ttl_schema/3,
              create_public_db_without_schema/2,
              print_all_triples/1,
              print_all_triples/2,
              delete_user_and_organization/1,
              cleanup_user_database/2,

              simulates/3,

              spawn_server/4,
              kill_server/1,
              setup_temp_server/2,
              teardown_temp_server/1,
              setup_temp_unattached_server/3,
              teardown_temp_unattached_server/1,
              setup_cloned_situation/4,
              setup_cloned_nonempty_situation/4
          ]).

/** <module> Test Utilities
 *
 * Utils to assist in testing.
 *
 * Printing during tests goes through two pipelines.
 *
 * Actual test output is sent to print_message with a **Kind** of
 * `testing`. Use test_format/3 for most things.
 *
 * progress of testing is reported to `debug/3` with a topic of
 * `terminus(testing_progress(Msg))`, where `Msg` in
 * `[run, error, fail]`
 *
 * Debug output should go through `debug/3`
 *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 */


:- use_module(utils).
:- use_module(file_utils).

:- use_module(core(triple)).
:- use_module(core(transaction)).
:- use_module(core(query)).
:- use_module(core(api)).
:- use_module(core(account)).

:- use_module(library(terminus_store)).

:- use_module(library(http/http_client)).
:- use_module(library(http/http_open)).
:- use_module(library(http/json)).

:- use_module(library(apply)).
:- use_module(library(apply_macros)).

:- use_module(library(process)).

:- meta_predicate test_format(:, +, +).

%!  test_format(+Goal:callable, +Format:text, +Args:list) is det
%
%   print the message formed as in [[format/2]] for message from
%   test Goal.
%
%   @arg Goal a callable term, the argument to [[try/1]], name of our
%   test
%   @arg Format string (an atom) as in [[format/2]]
%   @arg Args list of arguments for the format string
%
test_format(Goal, Format, Args) :-
    print_message(testing, test_format(Goal, Format, Args)).

:- multifile prolog:message//1.

prolog:message(test_format(Goal, Format, Args)) -->
    [
           '~Ntest ~q:'-[Goal],
           Format-Args
       ].

:- meta_predicate try(0).

%!  try(+Goal:callable) is semidet
%
%   calls `Goal` as once, writing debug information,
%
try(Goal) :-
    test_format(Goal, '~N* Running test ~q', [Goal]),
    debug(terminus(testing_progress(run)), 'running ~q', [Goal]),
    (   catch(Goal, Error, true)
    ->  (   var(Error)
        ->  true
        ;   test_format(Goal, '~N+ ERROR! Could not successfully run ~q: ~q',[Goal,Error]),
            debug(terminus(testing_progress(error)), 'ERROR! Could not successfully run ~q: ~q',[Goal,Error]),
            fail
        )
    ;
        test_format(Goal, '~N+ FAIL! Could not successfully run ~q',[Goal]),
        debug(terminus(testing_progress(fail)), 'FAIL! Could not successfully run ~q',[Goal]),
        fail
    ).

write_arg(Arg) :-
    string(Arg),
    !,
    writeq(Arg).
write_arg(Arg) :-
    re_match('.*:.*', Arg),
    !,
    writeq(Arg).
write_arg(Arg) :-
    re_match('[^ ]+ ', Arg),
    !,
    format('"~s"',Arg).
write_arg(Arg) :-
    atom(Arg),
    !,
    write(Arg).

write_args(Args) :-
    intersperse(' ', Args,Spaced),
    !,
    maplist(write_arg,Spaced),
    format('~n',[]).

status_200(URL) :-
    http_open(URL, _, [status_code(200)]).


/*
 * admin_pass(+Pass) is det.
 *
 * Get the administrator password for testing from the environment,
 * or try the default ('root')
 */
admin_pass(Pass) :-
    (   getenv('TERMINUSDB_ADMIN_PASSWD', Pass)
    ->  true
    ;   Pass='root').

setup_unattached_store(Store-Dir) :-
    tmp_file(temporary_terminus_store, TmpName),
    random_string(RandomString),
    atomic_list_concat([TmpName, RandomString], Dir),
    make_directory(Dir),
    open_directory_store(Dir, Store),
    initialize_database_with_store('root', Store).

setup_temp_store(Store-Dir) :-
    setup_unattached_store(Store-Dir),
    local_triple_store(Store).

teardown_unattached_store(_Store-Dir) :-
    delete_directory_and_contents(Dir).

teardown_temp_store(Store-Dir) :-
    retract_local_triple_store(Store),
    teardown_unattached_store(Store-Dir).

:- meta_predicate with_temp_store(:).
with_temp_store(Goal) :-
    setup_call_cleanup(setup_temp_store(State),
                       Goal,
                       teardown_temp_store(State)).

ensure_label(Label) :-
    triple_store(Store),
    ignore(create_named_graph(Store, Label, _Graph)).

layer_schema_context_from_label_descriptor(Label_Descriptor, Context) :-
    Commit_Info = commit_info{author:"test",message:"test"},
    ref_schema_context_from_label_descriptor(Label_Descriptor, Commit_Info, Context).
layer_schema_context_from_label_descriptor(Label_Descriptor, Commit_Info, Context) :-
    layer_ontology(Layer_Label),
    Layer_Descriptor = labelled_graph{label:Layer_Label,type:schema,name:"layer"},
    open_read_write_obj(Layer_Descriptor, Layer_Read_Write_Object),

    open_descriptor(Label_Descriptor, Commit_Info, Incomplete_Transaction_Object),
    Transaction_Object = Incomplete_Transaction_Object.put(schema_objects,
                                                           [Layer_Read_Write_Object]),

    create_context(Transaction_Object, Commit_Info, Context).

ref_schema_context_from_label_descriptor(Label_Descriptor, Context) :-
    Commit_Info = commit_info{author:"test",message:"test"},
    ref_schema_context_from_label_descriptor(Label_Descriptor, Commit_Info, Context).
ref_schema_context_from_label_descriptor(Label_Descriptor, Commit_Info, Context) :-
    layer_ontology(Layer_Label),
    ref_ontology(Ref_Label),
    Layer_Descriptor = labelled_graph{label:Layer_Label,type:schema,name:"layer"},
    Ref_Descriptor = labelled_graph{label:Ref_Label,type:schema,name:"ref"},
    open_read_write_obj(Layer_Descriptor, Layer_Read_Write_Object),
    open_read_write_obj(Ref_Descriptor, Ref_Read_Write_Object),

    open_descriptor(Label_Descriptor, Commit_Info, Incomplete_Transaction_Object),
    Transaction_Object = Incomplete_Transaction_Object.put(schema_objects,
                                                           [Layer_Read_Write_Object,
                                                            Ref_Read_Write_Object]),

    create_context(Transaction_Object, Commit_Info, Context).

repo_schema_context_from_label_descriptor(Label_Descriptor, Context) :-
    Commit_Info = commit_info{author:"test",message:"test"},
    repo_schema_context_from_label_descriptor(Label_Descriptor, Commit_Info, Context).
repo_schema_context_from_label_descriptor(Label_Descriptor, Commit_Info, Context) :-
    layer_ontology(Layer_Label),
    repository_ontology(Repo_Label),
    Layer_Descriptor = labelled_graph{label:Layer_Label,type:schema,name:"layer"},
    Repo_Descriptor = labelled_graph{label:Repo_Label,type:schema,name:"ref"},
    open_read_write_obj(Layer_Descriptor, Layer_Read_Write_Object),
    open_read_write_obj(Repo_Descriptor, Repo_Read_Write_Object),

    open_descriptor(Label_Descriptor, Commit_Info, Incomplete_Transaction_Object),
    Transaction_Object = Incomplete_Transaction_Object.put(schema_objects,
                                                           [Layer_Read_Write_Object,
                                                            Repo_Read_Write_Object]),

    create_context(Transaction_Object, Commit_Info, Context).

create_db_with_test_schema(Organization, Db_Name) :-
    Prefixes = _{ doc  : 'system://worldOnt/document/',
                  scm : 'http://example.com/data/worldOntology#'},

    open_descriptor(system_descriptor{}, System),
    super_user_authority(Admin),
    create_db(System, Admin, Organization, Db_Name, "test", "a test db", false, true, Prefixes),

    terminus_path(Path),
    interpolate([Path, '/test/worldOnt.ttl'], TTL_File),
    read_file_to_string(TTL_File, TTL, []),

    atomic_list_concat([Organization, '/', Db_Name,
                        '/local/branch/main/schema/main'],
                       Graph),
    super_user_authority(Auth),
    Commit_Info = commit_info{author: "test", message: "add test schema"},
    graph_update(system_descriptor{}, Auth, Graph, Commit_Info, "turtle", TTL).

create_db_with_ttl_schema(Organization, Db_Name, TTL_Schema) :-
    Prefixes = _{ doc  : 'system://worldOnt/document/',
                  scm : 'http://example.com/data/worldOntology#'},

    open_descriptor(system_descriptor{}, System),
    super_user_authority(Admin),
    create_db(System, Admin, Organization, Db_Name, "test", "a test db", false, true, Prefixes),

    terminus_path(Path),
    interpolate([Path, TTL_Schema], TTL_File),
    read_file_to_string(TTL_File, TTL, []),

    atomic_list_concat([Organization, '/', Db_Name,
                        '/local/branch/main/schema/main'],
                       Graph),
    super_user_authority(Auth),
    Commit_Info = commit_info{author: "test", message: "add test schema"},
    graph_update(system_descriptor{}, Auth, Graph, Commit_Info, "turtle", TTL).

create_db_without_schema(Organization, Db_Name) :-
    Prefixes = _{ doc : 'http://somewhere.for.now/document/',
                  scm : 'http://somewhere.for.now/schema#' },
    open_descriptor(system_descriptor{}, System),
    super_user_authority(Admin),
    create_db(System, Admin, Organization, Db_Name, "test", "a test db", false, false, Prefixes).

create_db_with_empty_schema(Organization, Db_Name) :-
    Prefixes = _{ doc : 'http://somewhere.for.now/document/',
                  scm : 'http://somewhere.for.now/schema#' },
    open_descriptor(system_descriptor{}, System),
    super_user_authority(Admin),
    create_db(System, Admin, Organization, Db_Name, "test", "a test db", false, true, Prefixes).

create_public_db_without_schema(Organization, Db_Name) :-
    Prefixes = _{ doc : 'http://somewhere.for.now/document/',
                  scm : 'http://somewhere.for.now/schema#' },
    open_descriptor(system_descriptor{}, System),
    super_user_authority(Admin),
    create_db(System, Admin, Organization, Db_Name, "test", "a test db", true, false, Prefixes).

delete_user_and_organization(User_Name) :-
    do_or_die(delete_user(User_Name),
             error(user_doesnt_exist(User_Name))),
    do_or_die(delete_organization(User_Name),
             error(organization_doesnt_exist(User_Name))).

:- begin_tests(db_test_schema_util).
test(create_db_and_insert_invalid_data,
     [setup((setup_temp_store(State),
             create_db_with_test_schema("admin", "test"))),
      cleanup(teardown_temp_store(State)),
      throws(error(schema_check_failure(_),_))])
:-
    resolve_absolute_string_descriptor("admin/test", Descriptor),
    create_context(Descriptor, commit_info{author:"test",message:"this should never commit"}, Context),

    with_transaction(Context,
                     ask(Context,
                         insert(a,b,c)),
                     _).

:- end_tests(db_test_schema_util).

print_all_triples(Askable) :-
    findall(t(S,P,O),
            ask(Askable, t(S,P,O)),
            Triples),
    forall(member(Triple,Triples),
           (   writeq(Triple), nl)).

print_all_triples(Askable, Selector) :-
    findall(t(S,P,O),
            ask(Askable, t(S,P,O, Selector)),
            Triples),
    forall(member(Triple,Triples),
           (   writeq(Triple), nl)).

cleanup_user_database(User, Database) :-
   (   database_exists(User, Database)
   ->  force_delete_db(User, Database)
   ;   true),
   (   agent_name_exists(system_descriptor{}, User)
   ->  delete_user(User)
   ;   true),
   (   organization_name_exists(system_descriptor{}, User)
   ->  delete_organization(User)
   ;   true).

select_mode([],[],[],true).
select_mode([(?)|Rest],[Arg1|Args1],[Arg2|Args2],Equations) :-
    Arg1 = Arg2,
    select_mode(Rest,Args1,Args2,Equations).
select_mode([(?)|Rest],[Arg1|Args1],[Arg2|Args2],Equations) :-
    select_mode(Rest,Args1,Args2,Other_Equations),
    Equations = (Arg1=Arg2,Other_Equations).
select_mode([(-)|Rest],[Arg1|Args1],[Arg2|Args2],Equations) :-
    select_mode(Rest,Args1,Args2,Other_Equations),
    Equations = (Arg1=Arg2,Other_Equations).
select_mode([domain(L)|Rest],[X|Args1],[X|Args2],Equations) :-
    member(X,L),
    select_mode(Rest,Args1,Args2,Equations).

/*
 * simulates(+P,+Q,+Modes) is det.
 *
 * Predicate P simulates Q, (P < Q)
 *
 * Modes is a a list with len = arity(P) = arity(Q)
 * containing elements either (?), (-) or domain([X,Y,Z,...])
 * where X,Y,Z are ground values in the domain.
 *
 */
simulates(M:P,N:Q,Modes) :-
    forall((   member(Mode,Modes),
               select_mode(Mode,Args1,Args2,Equations),
               P_Goal =.. [P|Args1],
               Q_Goal =.. [Q|Args2],
               call(N:Q_Goal)),
           (   (   call(M:P_Goal),
                   call(Equations)
               ->  true
               ;   format("Goal ~q did not simulate ~q~nunder equations (~q) for mode ~q",
                          [P_Goal,Q_Goal,Equations,Mode]),
                   fail)
           )).

inherit_env_var(Env_List_In, Var, Env_List_Out) :-
    (   getenv(Var, Val)
    ->  Env_List_Out = [Var=Val|Env_List_In]
    ;   Env_List_Out = Env_List_In).

inherit_env_vars(Env_List, [], Env_List) :-
    !.
inherit_env_vars(Env_List_In, [Var|Vars], Env_List) :-
    inherit_env_var(Env_List_In, Var, Env_List_Out),
    inherit_env_vars(Env_List_Out, Vars, Env_List).

% spawn_server(+Path, -URL, -PID, +Options) is det.
spawn_server_1(Path, URL, PID, Options) :-
    (   memberchk(port(Port), Options)
    ->  true
    ;   between(0,5,_),
        random_between(49152, 65535, Port)),

    current_prolog_flag(executable, Swipl_Path),

    directory_file_path(_, Exe, Swipl_Path),
    (   Exe = swipl
    ->  expand_file_search_path(terminus_home('start.pl'), Argument),
        Args = [Argument, serve]
    ;   Args = [serve]
    ),

    format(string(URL), "http://127.0.0.1:~d", [Port]),

    Env_List_1 = [
        'LANG'='en_US.UTF-8',
        'LC_TIME'='en_US.UTF-8',
        'LC_MONETARY'='en_US.UTF-8',
        'LC_MEASUREMENT'='en_US.UTF-8',
        'LC_NUMERIC'='en_US.UTF-8',
        'LC_PAPER'='en_US.UTF-8',

        'TERMINUSDB_SERVER_PORT'=Port,
        'TERMINUSDB_SERVER_DB_PATH'=Path,
        'TERMINUSDB_HTTPS_ENABLED'='false'
    ],

    inherit_env_vars(Env_List_1,
                     [
                         'HOME',
                         'SystemRoot', % Windows specific stuff...
                         'TMP', % Windows sadness
                         'TEMP', % Again...
                         'TERMINUSDB_ADMIN_PASSWD',
                         'TERMINUSDB_SERVER_PACK_DIR',
                         'TERMINUSDB_SERVER_JWT_PUBLIC_KEY_PATH',
                         'TERMINUSDB_SERVER_JWT_PUBLIC_KEY_ID',
                         'TERMINUSDB_JWT_ENABLED',
                         'TERMINUSDB_SERVER_TMP_PATH'
                     ],
                     Env_List),

    process_create(Swipl_Path, Args,
                   [
                       process(PID),
                       env(Env_List),
                       stdin(pipe(Input)),
                       stdout(pipe(_)),
                       stderr(pipe(Error))
                   ]),

    % this very much depends on something being written on startup
    % we read 2 lines, because the first line will report start. the second line will be printed after load is done.
    % This is very fragile though.
    read_line_to_string(Error, _First_Line),
    read_line_to_string(Error, _Second_Line),
    %read_line_to_string(Error, _Third_Line),

    ignore(memberchk(error(Error), Options)),
    ignore(memberchk(input(Input), Options)),

    (   current_prolog_flag(windows, true)
    ->  sleep(0.1)
    ;   true),
    process_wait(PID, Status, [timeout(0)]),
    (   Status = exit(98)
    ->  fail
    ;   Status \= timeout
    ->  throw(error(server_spawn_failed(Status), _))
    ;   true).

spawn_server(Path, URL, PID, Options) :-
    (   memberchk(port(_), Options)
    ->  Error = server_spawn_port_in_use
    ;   Error = server_spawn_retry_exceeded),

    do_or_die(spawn_server_1(Path, URL, PID, Options),
              error(Error, _)).

kill_server(PID) :-
    process_kill(PID),
    process_wait(PID, _).

setup_temp_server(Store-Dir-PID, URL) :-
    setup_temp_store(Store-Dir),
    spawn_server(Dir, URL, PID, []).

teardown_temp_server(Store-Dir-PID) :-
    kill_server(PID),
    teardown_temp_store(Store-Dir).

setup_temp_unattached_server(Store-Dir-PID, Store, URL) :-
    setup_unattached_store(Store-Dir),
    spawn_server(Dir, URL, PID, []).

teardown_temp_unattached_server(Store-Dir-PID) :-
    kill_server(PID),
    teardown_unattached_store(Store-Dir).

setup_cloned_situation(Store_Origin, Server_Origin, Store_Destination, Server_Destination) :-
    %% Setup: create a database on the remote server, clone it on the local server
    with_triple_store(
        Store_Destination,
        (   add_user("KarlKautsky", 'karl@kautsky.org', 'a comment', some('password_destination'), _),
            create_db_without_schema("KarlKautsky", "foo"))
    ),

    with_triple_store(
        Store_Origin,
        add_user("RosaLuxemburg", 'rosa@luxemburg.org', 'a comment', some('password_origin'), _)),

    atomic_list_concat([Server_Origin, '/api/clone/RosaLuxemburg/bar'], Clone_URL),
    atomic_list_concat([Server_Destination, '/KarlKautsky/foo'], Remote_URL),
    base64("KarlKautsky:password_destination", Base64_Destination_Auth),
    format(string(Authorization_Remote), "Basic ~s", [Base64_Destination_Auth]),
    http_post(Clone_URL,
              json(_{comment: "hai hello",
                     label: "bar",
                     remote_url: Remote_URL}),

              _,
              [json_object(dict),authorization(basic('RosaLuxemburg','password_origin')),
               request_header('Authorization-Remote'=Authorization_Remote)]).

setup_cloned_nonempty_situation(Store_Origin, Server_Origin, Store_Destination, Server_Destination) :-
    %% Setup: create a database with content on the remote server, clone it on the local server
    with_triple_store(
        Store_Destination,
        (   add_user("KarlKautsky", 'karl@kautsky.org', 'a comment', some('password_destination'), _),
            create_db_without_schema("KarlKautsky", "foo"),

            resolve_absolute_string_descriptor("KarlKautsky/foo", Descriptor),
            create_context(Descriptor, commit_info{author:"kautsky", message: "hi hello"}, Context1),
            with_transaction(Context1,
                             ask(Context1,
                                 insert(a,b,c)),
                             _),
            create_context(Descriptor, commit_info{author:"kautsky", message: "hi hello"}, Context2),
            with_transaction(Context2,
                             ask(Context2,
                                 insert(d,e,f)),
                             _)
        )
    ),

    with_triple_store(
        Store_Origin,
        add_user("RosaLuxemburg", 'rosa@luxemburg.org', 'a comment', some('password_origin'), _)),


    atomic_list_concat([Server_Origin, '/api/clone/RosaLuxemburg/bar'], Clone_URL),
    atomic_list_concat([Server_Destination, '/KarlKautsky/foo'], Remote_URL),
    base64("KarlKautsky:password_destination", Base64_Destination_Auth),
    format(string(Authorization_Remote), "Basic ~s", [Base64_Destination_Auth]),
    http_post(Clone_URL,
              json(_{comment: "hai hello",
                     label: "bar",
                     remote_url: Remote_URL}),

              _,
              [json_object(dict),authorization(basic('RosaLuxemburg','password_origin')),
               request_header('Authorization-Remote'=Authorization_Remote)]).
