%%%-------------------------------------------------------------------
%%% @author Evgeny Khramtsov <ekhramtsov@bdt.group>
%%% @copyright (C) 2021, Big Data Technology. All Rights Reserved.
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%% @doc
%%% @end
%%% Created :  4 Dec 2020 by Evgeny Khramtsov <ekhramtsov@bdt.group>
%%%-------------------------------------------------------------------
-module(clickhouse_parser).

-on_load(load_nif/0).

%% API
-export([parse/1]).
-export([format_error/1]).
%% Shut up xref
-export([load_nif/0]).
%% Exported types
-export_type([table/0]).
-export_type([column/0]).
-export_type([definition/0]).
-export_type([type/0]).
-export_type([error_reason/0]).

-include_lib("kernel/include/logger.hrl").

-type column() :: string().
-type token() :: string() | {string(), list()} |
                 {'begin', pos_integer(), [string()] | string()} |
                 {'end', pos_integer()}.
-type table() :: {Db :: string(), Name :: string()}.
-type definition() :: {column(), type(), HaveDefault :: boolean()}.
-type error_reason() :: {syntax_error, Line :: pos_integer(),
                         Position :: non_neg_integer(),
                         Message :: string()}.
-type type() ::  {'AggregateFunction', string(), type()} |
                 {'Array', type()} |
                 'Boolean' |
                 'Date' |
                 {'DateTime64', list()} |
                 {'DateTime', list()} |
                 {'Decimal128', list()} |
                 {'Decimal256', list()} |
                 {'Decimal32', list()} |
                 {'Decimal64', list()} |
                 {'Decimal', list()} |
                 {'Enum16', [string()]} |
                 {'Enum8', [string()]} |
                 {'Enum', [string()]} |
                 {'FixedString', list()} |
                 'Float32' |
                 'Float64' |
                 'Int128' |
                 'Int16' |
                 'Int256' |
                 'Int32' |
                 'Int64' |
                 'Int8' |
                 {'LowCardinality', type()} |
                 {'Map', type(), type()} |
                 'MultiPolygon' |
                 {'Nested', [{column(), type()}]} |
                 {'Nullable', type()} |
                 'Point' |
                 'Polygon' |
                 'Ring' |
                 {'SimpleAggregateFunction', string(), type()} |
                 'String' |
                 {'Tuple', [type()]} |
                 'UInt16' |
                 'UInt256' |
                 'UInt32' |
                 'UInt64' |
                 'UInt8' |
                 'UUID' |
                 string() |
                 {string(), list()}.

%%%===================================================================
%%% API
%%%===================================================================
%% Currently only CREATE TABLE statement is supported
-spec parse(iodata()) -> {ok, {table(), [definition()]}} |
                         none |
                         {error, error_reason()}.
parse(Data) ->
    case parse_nif(Data) of
        {ok, {TabName, [_|_] = Cols, Types, Defaults}} ->
            TabDef = make_table_definition(Cols, Types, Defaults, []),
            {ok, {TabName, TabDef}};
        {ok, _} ->
            none;
        {error, {syntax_error, Line, Pos, Msg}} ->
            {error, {syntax_error, Line, Pos, Msg}}
    end.

-spec format_error(error_reason()) -> string().
format_error({syntax_error, Line, Pos, Message}) ->
    lists:flatten(io_lib:format("syntax error at ~B:~B: ~s", [Line, Pos, Message])).

%%%===================================================================
%%% Internal functions
%%%===================================================================
-spec make_table_definition([column()], [token()], [boolean()],
                            [definition()]) -> [definition()].
make_table_definition([Col|Cols], Types, [HaveDefault|Defaults], Acc) ->
    {Type, Types1} = make_type(Types),
    make_table_definition(Cols, Types1, Defaults,
                               [{Col, Type, HaveDefault}|Acc]);
make_table_definition([], [], [], Acc) ->
    lists:reverse(Acc).

-spec make_types([token()]) -> [type()].
make_types(T) ->
    make_types(T, []).

-spec make_types([token()], [type()]) -> [type()].
make_types([], Acc) ->
    Acc;
make_types(T, Acc) ->
    {Type, T1} = make_type(T),
    make_types(T1, [Type|Acc]).

-spec make_type([token()]) -> {type(), token()}.
make_type([{'begin', Index, [Type|Cols]}|T]) when is_list(Type) ->
    {Types, T1} = read_until({'end', Index}, T),
    Types1 = make_types(Types),
    {t({Type, lists:zip(Cols, Types1)}), T1};
make_type([{'begin', Index, Type}|T]) ->
    {Types, T1} = read_until({'end', Index}, T),
    {t({Type, make_types(Types)}), T1};
make_type([Type|T]) ->
    {t(Type), T}.

-spec read_until(T, [T]) -> {T, [T]}.
read_until(X, L) ->
    read_until(X, L, []).

-spec read_until(T, [T], [T]) -> {T, [T]}.
read_until(X, [X|T], Acc) ->
    {Acc, T};
read_until(X, [Y|T], Acc) ->
    read_until(X, T, [Y|Acc]).

-spec t(token()) -> type().
t("int8") -> 'Int8';
t("int16") -> 'Int16';
t("int32") -> 'Int32';
t("int64") -> 'Int64';
t("int128") -> 'Int128';
t("int256") -> 'Int256';
t("uint8") -> 'UInt8';
t("uint16") -> 'UInt16';
t("uint32") -> 'UInt32';
t("uint64") -> 'UInt64';
t("uint256") -> 'UInt256';
t("tinyint") -> 'Int8';
t("int1") -> 'Int8';
t("smallint") -> 'Int16';
t("int2") -> 'Int16';
t("int") -> 'Int32';
t("int4") -> 'Int32';
t("integer") -> 'Int32';
t("bigint") -> 'Int64';
t("float32") -> 'Float32';
t("float64") -> 'Float64';
t("float") -> 'Float32';
t("double") -> 'Float64';
t({"decimal", L}) -> {'Decimal', L};
t({"decimal32", L}) -> {'Decimal32', L};
t({"decimal64", L}) -> {'Decimal64', L};
t({"decimal128", L}) -> {'Decimal128', L};
t({"decimal256", L}) -> {'Decimal256', L};
t("bool") -> 'Boolean';
t("boolean") -> 'Boolean';
t("string") -> 'String';
t({"fixedstring", L}) -> {'FixedString', L};
t("uuid") -> 'UUID';
t("date") -> 'Date';
t({"datetime", L}) -> {'DateTime', L};
t({"datetime64", L}) -> {'DateTime64', L};
t({"enum", L}) -> {'Enum', L};
t({"enum8", L}) -> {'Enum8', L};
t({"enum16", L}) -> {'Enum16', L};
t({"lowcardinality", [T]}) -> {'LowCardinality', t(T)};
t({"array", [T]}) -> {'Array', t(T)};
t({"aggregatefunction", [N, T]}) -> {'AggregateFunction', N, t(T)};
t({"tuple", L}) -> {'Tuple', [t(T) || T <- L]};
t({"nullable", [T]}) -> {'Nullable', t(T)};
t("point") -> 'Point';
t("ring") -> 'Ring';
t("polygon") -> 'Polygon';
t("multipolygon") -> 'MultiPolygon';
t({"simpleaggregatefunction", [N, T]}) -> {'SimpleAggregateFunction', N, t(T)};
t({"map", [T1, T2]}) -> {'Map', t(T1), t(T2)};
t({"nested", KT}) -> {'Nested', [{K, t(T)} || {K, T} <- KT]};
t(Unknown) ->
    Unknown.

%%%===================================================================
%%% NIF stuff
%%%===================================================================
-spec parse_nif(iodata()) -> {ok, {table(), [column()], [token()], [boolean()]}} |
                             {error, error_reason()}.
parse_nif(_Data) ->
    erlang:nif_error({nif_not_loaded, ?MODULE}).

-spec load_nif() -> ok | {error, term()}.
load_nif() ->
    SOPath = get_so_path(?MODULE),
    case erlang:load_nif(SOPath, 0) of
        ok ->
            ok;
        Err ->
            ?LOG_ERROR("Failed to load NIF '~s': ~p", [?MODULE, Err]),
            Err
    end.

-spec get_so_path(module()) -> file:filename().
get_so_path(Module) ->
    EbinDir = filename:dirname(code:which(Module)),
    AppDir = filename:dirname(EbinDir),
    PrivDir = filename:join([AppDir, "priv"]),
    filename:join(PrivDir, Module).
