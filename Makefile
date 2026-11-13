# Reproducible test entry points. All commands are plain shell; see README.md.
#
#   make test            lint + PCRE2 + pcre2test + Lua (every installed runtime) + differential + coverage check
#   make reports         same as test, but also refreshes reports/SUMMARY.md
#   make lua LUA=lua5.1  run the Lua suite on one runtime
#   make fixtures        regenerate generated fixtures (reference vectors, regex corpus)

PY      ?= python3
# every installed versioned interpreter; the generic `lua` binary is only used when no versioned one exists
LUAS    ?= $(shell found=""; for l in lua5.4 lua5.3 lua5.1 luajit; do command -v $$l >/dev/null 2>&1 && found="$$found $$l"; done; \
             if [ -z "$$found" ]; then command -v lua >/dev/null 2>&1 && found="lua"; fi; echo $$found)
REPORTS  = reports

.PHONY: test lint pcre2 banking lua differential coverage fixtures reports clean-reports website

test: lint pcre2 banking lua differential coverage
	@echo "all checks passed"

lint:
	$(PY) tools/check_rules.py

pcre2:
	$(PY) tests/pcre2/run_pcre2_tests.py --report $(REPORTS)/pcre2-regex-report.json
	$(PY) tests/pcre2/run_pcre2test_cli.py --report $(REPORTS)/pcre2test-cli-report.json

banking:
	$(PY) tests/pcre2/run_banking_format_tests.py --report $(REPORTS)/banking-format-report.json
	$(PY) tests/pcre2/run_banking_algorithm_tests.py --report $(REPORTS)/banking-algorithm-report.json

lua:
	@test -n "$(LUAS)" || (echo "no Lua interpreter found (install lua5.4, lua5.1 or luajit)"; exit 1)
	@for l in $(LUAS); do \
	  name=$$(basename $$l); \
	  echo "== $$l"; \
	  $$l tests/lua/run.lua --report $(REPORTS)/lua-test-report-$$name.json --syntax-verdicts $(REPORTS)/lua-syntax-verdicts-$$name.json || exit 1; \
	done

differential: 
	@for l in $(LUAS); do \
	  name=$$(basename $$l); \
	  $(PY) tools/compare_syntax_verdicts.py --pcre2 $(REPORTS)/pcre2-corpus-verdicts.json \
	    --lua $(REPORTS)/lua-syntax-verdicts-$$name.json --out $(REPORTS)/lua-vs-pcre2-differential-$$name.json || exit 1; \
	done

coverage:
	$(PY) tools/gen_coverage_docs.py --check

fixtures:
	$(PY) tools/gen_reference_vectors.py
	$(PY) tools/gen_regex_corpus.py
	$(PY) tools/gen_coverage_docs.py

reports: test
	$(PY) tools/write_summary.py

website:
	$(PY) tools/build_website.py
	$(PY) tools/check_website.py

clean-reports:
	rm -f $(REPORTS)/lua-syntax-verdicts-*.json $(REPORTS)/pcre2-corpus-verdicts.json
