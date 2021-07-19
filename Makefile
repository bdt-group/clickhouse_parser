REBAR ?= rebar3
PROJECT := clickhouse_parser

.PHONY: compile clean distclean xref dialyze lint test

all: compile

compile:
	@$(REBAR) compile

clean:
	@$(REBAR) clean

distclean:
	@$(MAKE) -C c_src clean
	rm -rf *.log
	rm -rf _build
	rm -rf ${PROJECT}
	rm -rf artefact

test:
	@$(REBAR) eunit --cover
	@$(REBAR) ct --cover
	@$(REBAR) cover --verbose

xref:
	@$(REBAR) xref

dialyze:
	@$(REBAR) dialyzer

lint:
	@$(REBAR) as lint lint

release:
	@$(REBAR) as prod release
