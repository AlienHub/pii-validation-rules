# pii-validation-rules (English summary)

Format and check-digit **consistency** rules for personal and entity identifiers in Asia and the Middle East: per-jurisdiction JSON rules (strict full-string PCRE2 regexes with evidence grades and sources), pure-Lua checksum modules, synthetic fixtures, reproducible PCRE2 and Lua tests, research notes and a coverage matrix. The primary documentation is in Chinese ([README.md](../README.md)); identifiers and API names are English.

**This library never verifies identity.** Every result carries `issuer_verification = "unknown"`. A pass means only that the string's shape/arithmetic agrees with a recorded rule.

## Honest coverage numbers

- 129 regex rules: 72 `syntax_supported` (current official structure, syntax only), 9 `candidate_profile`, 5 `historical_syntax`, 4 `dated_numbering_profile` (phone numbering snapshots), 39 `country_code_envelope_only` (`+CC` + ≤15 digits; **not** phone validators). Do not describe this as "129 official validators".
- 17 checksum algorithms: 9 official/standard and enabled by default (`cn_resident_id_mod11_2`, `cn_uscc_mod31`, `jp_mynumber`, `jp_corporate_number`, `kz_iin`, `iban_mod97`, `luhn` for payment PANs, `verhoeff`, `icao9303_check_digit`); 6 secondary/reconstructed and **off by default** (`th_mod11`, `tr_tckn`, `tr_vkn`, `tw_citizen_new_ui`, `hkid_mod11`, `ir_national_mod11`); Singapore NRIC/FIN reconstruction opt-in with the disputed M-series table behind a separate experimental flag; Korean RRN legacy formula gated on an explicitly declared pre-2020-10 regime.
- Jurisdictions: 39 named (6 core, 14 Middle East, 19 additional Asia) + 13 inventory-only backlog (AF AM AZ BT CY GE KG MV TL TJ TM KP RU) + EG edge entry = 53. Passports have a rule only for Chinese ordinary passports; domestic bank accounts are unsupported everywhere (IBAN for 16 countries is separate); many Middle-Eastern ID/TIN cells are explicitly `unsupported_insufficient_primary_spec`.

## Layout

`rules/<CC>.json` + `rules/algorithms.json` · `lua/pii/` (init, syntax, checksums/*, policies, normalize, semantic, json) · `fixtures/` · `tests/pcre2/` (ctypes native PCRE2 + `pcre2test` + Python `re`) · `tests/lua/` · `tools/` · `research/` (notes, change notes, coverage, sources) · `reports/` (committed machine-readable results) · `.github/workflows/ci.yml`.

## Usage

```lua
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local pii = require("pii")
local r = pii.validate("CN.resident_id", "11010519491231002X")
-- r.syntax / r.checksum / r.semantic ∈ pass|fail|unknown|not_applicable|not_evaluated
-- r.issuer_verification == "unknown"; r.summary ∈ pass|pass_with_unknowns|fail (never "valid")
pii.validate("TH.citizen_id", "1234567890121")                                 -- checksum "unknown" (secondary formula off)
pii.validate("TH.citizen_id", "1234567890121", { secondary_checksums = true }) -- checksum "pass" + evidence warning
pii.validate("SG.fin", "M1234567B")                                            -- checksum "unknown" (M table disputed)
pii.validate("KR.rrn", "9001011234560", { kr_rrn_regime = "current_post_2020_10" }) -- checksum "not_applicable"
pii.validate("MY.nric", "900101-01-0001", { normalize = true })                -- explicit, reported normalization
```

Options: `secondary_checksums`, `algorithms = { id = true/false }`, `sg_m_series_experimental`, `kr_rrn_regime`, `historical_import`, `ir_reject_repeated_digits`, `normalize`, `ascii_uppercase`, `semantic`, `reference_date`, `max_input_length`. Details: [docs/API.zh.md](API.zh.md).

## Tests (real commands)

```bash
sudo apt-get install -y lua5.4 lua5.1 luajit libpcre2-8-0 pcre2-utils
make test      # lint → native PCRE2 (+pcre2test, Python re) → Lua on every runtime → Lua-vs-PCRE2 differential → coverage drift
make reports   # same, then rewrite reports/SUMMARY.md
```

Committed results for this revision ([reports/SUMMARY.md](../reports/SUMMARY.md)): PCRE2 10.42 compiled 129 rules, 1176 expected cases passed, 7363 differential inputs with zero disagreement between PCRE2 (plain and UTF), Python `re`; `pcre2test` 1176 subjects 0 mismatches; Lua 5.4 / 5.1 / LuaJIT each 299 cases, 89 032 assertions, 0 failures; Lua subset matcher vs PCRE2: 7363 × 3 runtimes, 0 disagreements.

## Regex contract and the Lua matcher

Patterns are `\A(?:body)\z` with explicit `[0-9]` classes and bounded repetition; PCRE2 is authoritative, Python `re.fullmatch` is a compatibility check. Lua patterns are not regexes: `lua/pii/syntax.lua` is a documented restricted-subset byte matcher (classes, bounded quantifiers, non-capturing groups, alternation) that raises on anything else and is differential-tested against PCRE2 in CI. Bind `lrexlib-pcre2` yourself if you need full PCRE2 in Lua.

## Safety

Only synthetic values or officially published illustrative examples (GB 11643 appendix, ICAO Doc 9303 sample MRZ, NTA corporate-number example, Stripe test PANs) are used. No raw source documents, PDFs, card images or contact details are committed. No license file was added (none requested); all checksum implementations are original, written from the published mathematics.
