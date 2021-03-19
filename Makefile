REBAR ?= rebar3
PROJECT := clickhouse_parser
BUILD_IMAGE ?= gitlab.bdt.tools:5000/build-ubuntu1804:1.4.6

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

# Build in docker environment
.PHONY: d_sh d_% dc_sh dc_% compose decompose

d_sh:
	./build-with-env --image $(BUILD_IMAGE) bash

d_%:
	./build-with-env --image $(BUILD_IMAGE) make $*
