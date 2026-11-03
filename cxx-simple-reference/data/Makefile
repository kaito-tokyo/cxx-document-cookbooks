# Data layer.
#
#   make -C data fetch    check out the upstream heads of the draft and htmlgen
#   make -C data draft    render the draft to build/draft-html/
#   make -C data tables   extract tables into build/db.sqlite and build/data/*.json
#   make -C data cppref   download + unpack the cppreference archive at CPPREF_URL
#   make -C data check    verify build/ against CONTRACT.md
#   make -C data all      fetch + draft + tables + check (+ cppref if CPPREF_URL is set)

BUILD      ?= ../build
PY         ?= python3
CPPREF_URL ?=

.PHONY: all fetch draft tables cppref check clean

all: tables
	@if [ -n "$(CPPREF_URL)" ]; then $(MAKE) cppref; fi
	$(MAKE) check

fetch:
	$(PY) fetch_inputs.py $(BUILD)

draft: fetch
	bash build_draft.sh $(BUILD)

tables: draft
	$(PY) extract_tables.py $(BUILD)

cppref:
	@[ -n "$(CPPREF_URL)" ] || { echo "cppref: set CPPREF_URL" >&2; exit 1; }
	$(PY) fetch_cppref.py $(BUILD) "$(CPPREF_URL)"

check:
	$(PY) check_data.py $(BUILD)

clean:
	rm -rf $(BUILD)
