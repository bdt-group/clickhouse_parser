# Based on c_src.mk from erlang.mk by Loic Hoguin <essen@ninenines.eu>

CURDIR := $(shell pwd)
BASEDIR := $(abspath $(CURDIR)/..)

PROJECT ?= $(notdir $(BASEDIR))
PROJECT := $(strip $(PROJECT))

ERTS_INCLUDE_DIR ?= $(shell erl -noshell -s init stop -eval "io:format(\"~s/erts-~s/include/\", [code:root_dir(), erlang:system_info(version)]).")

C_SRC_DIR = $(CURDIR)
C_SRC_OUTPUT ?= $(CURDIR)/../priv/clickhouse_parser.so

LEXER_SOURCES = ClickHouseLexer.cpp
LEXER_HEADERS = ClickHouseLexer.h
LEXER_OUTPUT = $(LEXER_SOURCES) $(LEXER_HEADERS) ClickHouseLexer.interp  ClickHouseLexer.tokens

PARSER_SOURCES = ClickHouseParserBaseVisitor.cpp  ClickHouseParser.cpp ClickHouseParserVisitor.cpp
PARSER_HEADERS = ClickHouseParser.h ClickHouseParserVisitor.h ClickHouseParserBaseVisitor.h
PARSER_OUTPUT = $(PARSER_SOURCES) $(PARSER_HEADERS) ClickHouseParser.tokens ClickHouseParser.interp

# System type and C compiler/flags.

UNAME_SYS := $(shell uname -s)
CC ?= cc
LDFLAGS ?= -Wl,-Bsymbolic-functions -Wl,-z,relro,-z,now -Wl,-z,noexecstack -shared
CFLAGS ?= -D_FORTIFY_SOURCE=2 -O2 -fstack-protector-strong -std=gnu++11 \
					-I /usr/include/antlr4-runtime \
					-I /usr/local/include/antlr4-runtime \
					-I $(ERTS_INCLUDE_DIR) \
					-Wno-attributes \
				 	-Wformat -Werror=format-security \
					-Wunused-variable \
				 	-fno-strict-aliasing \
					-pie -fPIE -fPIC \
					-Wtype-limits -Wstrict-overflow=5 \
					-fstrict-overflow -Wsign-compare

LDLIBS += -lpthread -ldl -lantlr4-runtime

# Verbosity.

c_verbose_0 = @echo " C     " $(?F);
c_verbose = $(c_verbose_$(V))

link_verbose_0 = @echo " LD    " $(@F);
link_verbose = $(link_verbose_$(V))

SOURCES := $(LEXER_SOURCES) $(PARSER_SOURCES) clickhouse_parser.cpp
HEADERS := $(LEXER_HEADERS) $(PARSER_HEADERS)
OBJECTS = $(addsuffix .o, $(basename $(SOURCES)))

COMPILE_C = $(c_verbose) $(CC) $(CFLAGS)

all: $(PARSER_OUTPUT) $(C_SRC_OUTPUT)

$(LEXER_OUTPUT): ClickHouseLexer.g4
	antlr4 -Dlanguage=Cpp -no-listener -visitor ClickHouseLexer.g4

$(PARSER_OUTPUT): $(LEXER_OUTPUT) ClickHouseParser.g4
	antlr4 -Dlanguage=Cpp -no-listener -visitor ClickHouseParser.g4

$(C_SRC_OUTPUT): $(SOURCES) $(HEADERS)
	mkdir -p $(dir $@)
	$(COMPILE_C) -o $(C_SRC_OUTPUT) $(SOURCES) $(LDFLAGS) $(LDLIBS)

clean:
	@rm -f $(C_SRC_OUTPUT) $(LEXER_OUTPUT) $(PARSER_OUTPUT) $(OBJECTS)

.PHONY: all clean
