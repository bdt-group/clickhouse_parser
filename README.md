clickhouse_parser
=================

A parser of ClickHouse statements for Erlang

Description
-----------

The aim of the project is to provide a comprehensive parser
of ClickHouse statements for Erlang. However, currently only
`CREATE TABLE` statements are supported and the result is limited
to table name, columns with their types and presence of the `DEFAULT`
statement.

The key feature of the parser is that it's utilizing ANTLR4 grammar borrowed
directly from the ClickHouse project, so the result is fully compatible
with the one produced by ClickHouse itself.

Requirements
------------

* Erlang/OTP 22 or higher
* GCC with C++11 support
* ANTLR4 runtime

Usage
-----

In order to parse a query, `clickhouse_parser:parse/1` function is used.
Example:

```erl
> clickhouse_parser:parse("CREATE TABLE foo (ID UInt32, Tag LowCardinality(String) DEFAULT '')").
{ok,{foo,[{'ID',"uint32",false},
          {'Tag',{"lowcardinality",["string"]},true}]}}
```

In the presence of syntax errors, `clickhouse_parser:format_error/1` might be
called to generate descriptive text.
Example:

```erl
> {error, Reason} = clickhouse_parser:parse("CREATE TABLE foo (ID)").
{error,{syntax_error,1,20,
                     "no viable alternative at input 'ID)'"}}
> clickhouse_parser:format_error(Reason).
"syntax error at 1:20: no viable alternative at input 'ID)'"
```

If the statement is syntactically valid, but is unsupported, `none` is returned.
Example:

```erl
> clickhouse_parser:parse("ALTER TABLE foo ADD COLUMN bar Boolean").
none
```
