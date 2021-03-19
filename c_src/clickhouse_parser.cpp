#include "ClickHouseLexer.h"
#include "ClickHouseParser.h"
#include "ClickHouseParserBaseVisitor.h"
#include <cstring>
#include <erl_nif.h>
#include <string>

using namespace antlr4;

ERL_NIF_TERM make_string(ErlNifEnv *env, std::string s) {
  /* This is lowercase, LOL */
  std::transform(s.begin(), s.end(), s.begin(),
                 [](unsigned char c) { return std::tolower(c); });
  return enif_make_string(env, s.c_str(), ERL_NIF_LATIN1);
}

std::string unquote(std::string s) { return s.substr(1, s.length() - 2); }

/*
 *  This is actually the most interesting class with
 *  the methods walking through the AST. The stuff below
 *  this class is just ANTLR4/NIF boilerplate
 */
class ParseTreeVisitor : public ClickHouseParserBaseVisitor {
  ErlNifEnv *env;
  ERL_NIF_TERM *table_name;
  ERL_NIF_TERM *db_name;
  ERL_NIF_TERM *cols_acc;
  ERL_NIF_TERM *types_acc;
  ERL_NIF_TERM *defaults_acc;
  unsigned index = 0;

public:
  ParseTreeVisitor(ErlNifEnv *init_env, ERL_NIF_TERM *init_table_name,
                   ERL_NIF_TERM *init_db_name, ERL_NIF_TERM *init_cols_acc,
                   ERL_NIF_TERM *init_types_acc,
                   ERL_NIF_TERM *init_defaults_acc) {
    env = init_env;
    table_name = init_table_name;
    db_name = init_db_name;
    cols_acc = init_cols_acc;
    types_acc = init_types_acc;
    defaults_acc = init_defaults_acc;
  }

  antlrcpp::Any visitQuery(ClickHouseParser::QueryContext *ctx) override {
    if (ctx->createStmt()) {
      /* Only proceed if the query is CREATE statement */
      return visitChildren(ctx);
    }
    return NULL;
  }

  antlrcpp::Any
  visitTableIdentifier(ClickHouseParser::TableIdentifierContext *ctx) override {
    auto tab = ctx->identifier();
    auto db = ctx->databaseIdentifier();
    *table_name = enif_make_string(env, tab->getText().c_str(), ERL_NIF_LATIN1);
    if (db)
      *db_name = enif_make_string(env, db->getText().c_str(), ERL_NIF_LATIN1);
    return NULL;
  }

  antlrcpp::Any
  visitTableColumnDfnt(ClickHouseParser::TableColumnDfntContext *ctx) override {
    auto nested_id = ctx->nestedIdentifier();
    auto prop_expr = ctx->tableColumnPropertyExpr();
    /* We currently detect only presence of DEFAULT keyword */
    const char *def = (prop_expr && prop_expr->DEFAULT()) ? "true" : "false";
    *defaults_acc =
        enif_make_list_cell(env, enif_make_atom(env, def), *defaults_acc);
    ERL_NIF_TERM el =
        enif_make_string(env, nested_id->getText().c_str(), ERL_NIF_LATIN1);
    *cols_acc = enif_make_list_cell(env, el, *cols_acc);
    return visitChildren(ctx);
  }

  antlrcpp::Any visitColumnTypeExprSimple(
      ClickHouseParser::ColumnTypeExprSimpleContext *ctx) override {
    auto id = ctx->identifier();
    ERL_NIF_TERM el = make_string(env, id->getText());
    *types_acc = enif_make_list_cell(env, el, *types_acc);
    return NULL;
  }

  antlrcpp::Any visitColumnTypeExprEnum(
      ClickHouseParser::ColumnTypeExprEnumContext *ctx) override {
    auto id = ctx->identifier();
    auto enum_vals = ctx->enumValue();
    ERL_NIF_TERM acc = enif_make_list(env, 0);
    ERL_NIF_TERM rev_acc;
    for (auto const &enum_val : enum_vals) {
      std::string text = enum_val->STRING_LITERAL()->getText();
      /* STRING_LITERAL is always quoted, so we unquote it */
      std::string text1 = text.substr(1, text.length() - 2);
      ERL_NIF_TERM en = enif_make_string(env, text1.c_str(), ERL_NIF_LATIN1);
      acc = enif_make_list_cell(env, en, acc);
    }
    enif_make_reverse_list(env, acc, &rev_acc);
    ERL_NIF_TERM el =
        enif_make_tuple2(env, make_string(env, id->getText()), rev_acc);
    *types_acc = enif_make_list_cell(env, el, *types_acc);
    return NULL;
  }

  antlrcpp::Any visitColumnTypeExprNested(
      ClickHouseParser::ColumnTypeExprNestedContext *ctx) override {
    auto ids = ctx->identifier();
    index++;
    ERL_NIF_TERM acc = enif_make_list(env, 0);
    ERL_NIF_TERM rev_acc;
    for (auto const &id : ids) {
      acc = enif_make_list_cell(env, make_string(env, id->getText()), acc);
    }
    enif_make_reverse_list(env, acc, &rev_acc);
    *types_acc = enif_make_list_cell(
        env,
        enif_make_tuple3(env, enif_make_atom(env, "begin"),
                         enif_make_uint(env, index), rev_acc),
        *types_acc);
    auto ret = visitChildren(ctx);
    *types_acc =
        enif_make_list_cell(env,
                            enif_make_tuple2(env, enif_make_atom(env, "end"),
                                             enif_make_uint(env, index)),
                            *types_acc);
    return ret;
  }

  antlrcpp::Any visitColumnTypeExprComplex(
      ClickHouseParser::ColumnTypeExprComplexContext *ctx) override {
    auto id = ctx->identifier();
    index++;
    ERL_NIF_TERM el = make_string(env, id->getText());
    ERL_NIF_TERM begin_tag = enif_make_tuple3(env, enif_make_atom(env, "begin"),
                                              enif_make_uint(env, index), el);
    ERL_NIF_TERM end_tag = enif_make_tuple2(env, enif_make_atom(env, "end"),
                                            enif_make_uint(env, index));
    *types_acc = enif_make_list_cell(env, begin_tag, *types_acc);
    auto ret = visitChildren(ctx);
    *types_acc = enif_make_list_cell(env, end_tag, *types_acc);
    return ret;
  }

  antlrcpp::Any visitColumnTypeExprParam(
      ClickHouseParser::ColumnTypeExprParamContext *ctx) override {
    auto id = ctx->identifier();
    ERL_NIF_TERM el = make_string(env, id->getText());
    /* TODO: parse nested expression list */
    ERL_NIF_TERM expr_list = enif_make_list(env, 0);
    ERL_NIF_TERM tag = enif_make_tuple2(env, el, expr_list);
    *types_acc = enif_make_list_cell(env, tag, *types_acc);
    return NULL;
  }
};

/*
 * Syntax exceptions boilerplate
 */
class SyntaxErrorException : public std::exception {
  size_t line;
  size_t pos;
  std::string message;

public:
  SyntaxErrorException(size_t line_, size_t pos_, const std::string &message_) {
    line = line_;
    pos = pos_;
    message = message_;
  }

  size_t get_line() { return line; }
  size_t get_pos() { return pos; }
  const char *what() const throw() { return message.c_str(); }
};

class LexerErrorListener : public antlr4::BaseErrorListener {
public:
  void syntaxError(antlr4::Recognizer *, antlr4::Token *, size_t line,
                   size_t pos, const std::string &message,
                   std::exception_ptr) override {
    throw SyntaxErrorException(line, pos, message);
  }
};

class ParserErrorListener : public antlr4::BaseErrorListener {
public:
  void syntaxError(antlr4::Recognizer *, antlr4::Token *, size_t line,
                   size_t pos, const std::string &message,
                   std::exception_ptr) override {
    throw SyntaxErrorException(line, pos, message);
  }
};

/*
 * Main parse utility
 */
void parse(ErlNifEnv *env, ErlNifBinary *bin, ERL_NIF_TERM *tab_name,
           ERL_NIF_TERM *db_name, ERL_NIF_TERM *cols, ERL_NIF_TERM *types,
           ERL_NIF_TERM *defaults) {
  ANTLRInputStream input((char *)bin->data, bin->size);
  ClickHouseLexer lexer(&input);
  CommonTokenStream tokens(&lexer);
  ClickHouseParser parser(&tokens);

  LexerErrorListener lexer_error_listener;
  ParserErrorListener parser_error_listener;

  lexer.removeErrorListeners();
  parser.removeErrorListeners();
  lexer.addErrorListener(&lexer_error_listener);
  parser.addErrorListener(&parser_error_listener);

  ParseTreeVisitor visitor(env, tab_name, db_name, cols, types, defaults);

  visitor.visitQueryStmt(parser.queryStmt());
}

/*
 * NIF boilerplate
 */
static int load(ErlNifEnv *env, void **priv, ERL_NIF_TERM load_info) {
  return 0;
}

static ERL_NIF_TERM parse_nif(ErlNifEnv *env, int argc,
                              const ERL_NIF_TERM argv[]) {
  ErlNifBinary bin;
  ERL_NIF_TERM tab_name, db_name;
  ERL_NIF_TERM cols, rev_cols, types, rev_types, defaults, rev_defaults;

  if (argc != 1)
    return enif_make_badarg(env);

  if (!(enif_inspect_iolist_as_binary(env, argv[0], &bin)))
    return enif_make_badarg(env);

  cols = enif_make_list(env, 0);
  types = enif_make_list(env, 0);
  defaults = enif_make_list(env, 0);
  tab_name = enif_make_list(env, 0);
  db_name = enif_make_list(env, 0);

  try {
    parse(env, &bin, &tab_name, &db_name, &cols, &types, &defaults);
  } catch (SyntaxErrorException &e) {
    return enif_make_tuple2(
        env, enif_make_atom(env, "error"),
        enif_make_tuple4(env, enif_make_atom(env, "syntax_error"),
                         enif_make_uint64(env, e.get_line()),
                         enif_make_uint64(env, e.get_pos()),
                         enif_make_string(env, e.what(), ERL_NIF_LATIN1)));
  }

  enif_make_reverse_list(env, cols, &rev_cols);
  enif_make_reverse_list(env, types, &rev_types);
  enif_make_reverse_list(env, defaults, &rev_defaults);

  return enif_make_tuple2(
      env, enif_make_atom(env, "ok"),
      enif_make_tuple4(env, enif_make_tuple2(env, db_name, tab_name), rev_cols,
                       rev_types, rev_defaults));
}

static ErlNifFunc nif_funcs[] = {{"parse_nif", 1, parse_nif}};

ERL_NIF_INIT(clickhouse_parser, nif_funcs, load, NULL, NULL, NULL)
