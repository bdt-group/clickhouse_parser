%%%-------------------------------------------------------------------
%%% @author Evgeny Khramtsov <ekhramtsov@bdt.group>
%%% @copyright (C) 2021, Big Data Technology
%%% @doc
%%%
%%% @end
%%% Created : 19 Mar 2021 by Evgeny Khramtsov <ekhramtsov@bdt.group>
%%%-------------------------------------------------------------------
-module(clickhouse_parser_eunit).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Tests
%%%===================================================================
create_table_test() ->
    Stmt = "CREATE TABLE db . test (foo String, bar . baz Int32 DEFAULT 0)\n \n",
    Expected = {{"db", "test"}, [{"foo", 'String', false},
                                 {"bar.baz", 'Int32', true}]},
    ?assertEqual({ok, Expected}, clickhouse_parser:parse(Stmt)).

no_create_table_test() ->
    Stmt = "ALTER TABLE test ADD COLUMN foo UInt64 DEFAULT 0",
    ?assertEqual(none, clickhouse_parser:parse(Stmt)).

parse_syntax_error_test() ->
    Stmt = "CREATE TABLE (foo String, bar.baz Int32)",
    Ret = clickhouse_parser:parse(Stmt),
    ?assertMatch(
       {error, {syntax_error, 1, 13, "extraneous input" ++ _}},
       Ret),
    {error, Reason} = Ret,
    ?assertMatch("syntax error at " ++ _, clickhouse_parser:format_error(Reason)).

int_test() ->
    lists:foreach(
      fun(Type) ->
              Stmt = create_table_stmt("column " ++ atom_to_list(Type)),
              ?assertEqual(
                 {ok, {{"", "table"}, [{"column", Type, false}]}},
                 clickhouse_parser:parse(Stmt))
      end, int_types()).

nested_test() ->
    Stmt = create_table_stmt("column Nested (id UUID, str String)"),
    ?assertEqual(
       {ok, {{"", "table"},
             [{"column", {'Nested', [{"id", 'UUID'},
                                     {"str", 'String'}]},
               false}]}},
       clickhouse_parser:parse(Stmt)).

%%%===================================================================
%%% Internal functions
%%%===================================================================
create_table_stmt(S) ->
    "CREATE TABLE table (" ++ S ++ ")".

int_types() ->
    ['Int128', 'Int16', 'Int256', 'Int32', 'Int64', 'Int8',
     'UInt16', 'UInt256', 'UInt32', 'UInt64', 'UInt8'].
