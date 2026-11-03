# Data layer. Everything here is deterministic given inputs.lock.
#
#   make -C data fetch    check out the pinned draft and htmlgen sources
#   make -C data draft    render the draft to build/draft-html/
#   make -C data tables   extract tables into build/db.sqlite and build/data/*.json
#   make -C data cppref   download + unpack the pinned cppreference archive
#   make -C data check    verify build/ against CONTRACT.md
#   make -C data repro    check + re-render the draft and require identical output
#   make -C data all      fetch + draft + tables + check (+ cppref if pinned)
#   make -C data bump     repin draft/htmlgen to upstream heads (edits inputs.lock)

LOCK  ?= ../inputs.lock
BUILD ?= ../build
PY    ?= python3

.PHONY: all fetch bump draft tables cppref check repro clean

all: tables
	@if grep -Eq '^cppref_url[[:space:]]*=[[:space:]]*[^[:space:]#]' $(LOCK); then $(MAKE) cppref; fi
	$(MAKE) check

fetch:
	$(PY) fetch_inputs.py $(LOCK) $(BUILD)

bump:
	$(PY) fetch_inputs.py $(LOCK) $(BUILD) --bump

draft: fetch
	bash build_draft.sh $(LOCK) $(BUILD)

tables: draft
	$(PY) extract_tables.py $(LOCK) $(BUILD)

cppref:
	$(PY) fetch_cppref.py $(LOCK) $(BUILD)

check:
	$(PY) check_data.py $(LOCK) $(BUILD)

repro:
	$(PY) check_data.py $(LOCK) $(BUILD) --repro

clean:
	rm -rf $(BUILD)
