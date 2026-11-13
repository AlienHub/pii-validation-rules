#!/usr/bin/env python3
"""One-shot importer for the banking deep-research handoff proposals.

Reads an unpacked handoff directory, independently adapts profiles into the
repo's pii-rules-1 shape, merges sources/coverage, and writes fixtures that the
test suite consumes. Does NOT copy UOB Appendix A or full OFCA allocation tables
(redistribution basis unclear / directory rights); those become a pluggable
directory interface plus synthetic fixtures only.

Usage:
  python3 tools/import_banking_deep_research.py /path/to/pii-banking-deep-research
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Research status -> repo status (retain meaning; extend vocabulary in lint).
STATUS_MAP = {
    "official_scoped_syntax": "official_scoped_syntax",
    "official_scoped_syntax_date_unknown": "official_scoped_syntax",
    "processor_scoped_profile": "processor_scoped_profile",
    "dated_bank_generation_profile": "dated_bank_generation_profile",
    "dated_channel_profile": "dated_channel_profile",
    "dated_numbering_series_profile": "dated_numbering_profile",
    "historical_compatibility": "historical_syntax",
    "historical_standard_only": "historical_syntax",
    "historical_interface_profile": "historical_syntax",
    "candidate_routing_syntax_directory_unverified": "candidate_profile",
    "standard_announcement_envelope": "standard_announcement_envelope",
    "syntax_plus_required_allocation_lookup": "syntax_plus_required_allocation_lookup",
}

PII_TYPE_MAP = {
    "domestic_bank_account": "domestic_bank_account",
    "virtual_bank_account": "virtual_bank_account",
    "loan_account": "loan_account",
    "account_channel_input": "account_channel_input",
    "payment_card_pan": "payment_card",
    "payment_card_number": "payment_card",
    "bank_card_number": "payment_card",
    "iban": "iban",
    "routing_bank_code": "routing_code",
    "routing_branch_code": "routing_code",
    "clearing_bank_code": "routing_code",
    "clearing_branch_code": "routing_code",
    "payment_system_routing_code": "routing_code",
    "payment_alias": "payment_alias",
    "payment_alias_suffix": "payment_alias_component",
    "foreign_resident_id": "foreign_resident_id",
    "mainland_residence_permit": "mainland_residence_permit",
    "mainland_travel_permit": "mainland_travel_permit",
    "exit_entry_permit": "exit_entry_permit",
    "resident_identity_card": "resident_id",
    "identity_identifier_without_check": "identity_component",
    "identity_check_character": "identity_component",
    "phone_number": "phone",
}

COMPONENT_TYPES = {
    "routing_code",
    "payment_alias_component",
    "identity_component",
    "account_channel_input",
}

# Profiles that stay as distinct rules (API-compatible IDs). TR.iban.2021 merges into TR.iban.
SKIP_NEW_IDS = {"TR.iban.2021"}  # folded into existing TR.iban

# Jurisdiction file for each profile id prefix / country field.
def target_jurisdiction(profile: dict) -> str:
    rid = profile["id"]
    country = profile.get("country") or ""
    if rid.startswith("GLOBAL."):
        return "GLOBAL"
    if country in ("CN/HK",):
        return "HK"
    if country in ("CN/MO",):
        return "MO"
    if rid.startswith("CN.") or country == "CN":
        return "CN"
    prefix = rid.split(".", 1)[0]
    if prefix in {
        "AE", "BD", "BH", "BN", "CN", "GLOBAL", "HK", "ID", "IL", "IN", "IQ", "IR", "JO", "JP",
        "KH", "KR", "KW", "KZ", "LA", "LB", "LK", "MM", "MN", "MO", "MY", "NP", "OM", "PH", "PK",
        "PS", "QA", "SA", "SG", "SY", "TH", "TR", "TW", "UZ", "VN", "YE",
    }:
        return prefix
    raise ValueError("cannot place %s (country=%r)" % (rid, country))


def standard_negatives(body: str, positive: str) -> list:
    """Build the standard negative suite used by existing rules."""
    base = positive or "X"
    return [
        {"input": "", "expected_syntax": False, "reason": "empty"},
        {"input": "!" + base, "expected_syntax": False, "reason": "invalid_character"},
        {"input": base + "\n", "expected_syntax": False, "reason": "trailing_newline"},
        {"input": "\n" + base, "expected_syntax": False, "reason": "leading_newline"},
        {"input": base + "!", "expected_syntax": False, "reason": "invalid_suffix"},
        {"input": base[:-1] if len(base) > 1 else "", "expected_syntax": False, "reason": "too_short_or_missing_field"},
        {"input": base + "0", "expected_syntax": False, "reason": "too_long"},
        {"input": ("１" + base[1:]) if base and base[0].isdigit() else "Ａ" + base[1:], "expected_syntax": False, "reason": "non_ascii_digit"},
    ]


def checksum_for(profile: dict) -> dict:
    rel = (profile.get("checksum_relationship") or "unknown").lower()
    status = profile.get("status", "")
    if "iban_mod97" in rel:
        return {"status": "algorithm_available", "algorithm": "iban_mod97", "evidence": "official", "policy": "enabled"}
    if "cn_mod11_2" in rel or "gb11643" in rel:
        return {
            "status": "algorithm_available",
            "algorithm": "cn_resident_id_mod11_2",
            "evidence": "official",
            "policy": "enabled",
        }
    if rel.strip() == "luhn" or rel.startswith("luhn"):
        # Worldpay / ISO processor profiles: opt-in so they never become global brand gates.
        if status == "processor_scoped_profile" or "worldpay" in profile["id"]:
            return {
                "status": "algorithm_available",
                "algorithm": "luhn",
                "evidence": "primary_payment_processor",
                "policy": "opt_in_processor_profile",
            }
        if "jrt0008" in profile["id"] or "legacy" in profile["id"]:
            return {
                "status": "algorithm_available",
                "algorithm": "luhn",
                "evidence": "official",
                "policy": "enabled",  # historical PAN rule already runs Luhn when selected
            }
        if "iso" in profile["id"]:
            # Envelope only announces length; Luhn is scheme/product policy, not automatic issuer proof.
            return {"status": "not_established"}
        return {
            "status": "algorithm_available",
            "algorithm": "luhn",
            "evidence": "standard_algorithm",
            "policy": "enabled",
        }
    if "present_but_algorithm_unknown" in rel or "algorithm_unknown" in rel:
        return {"status": "not_established"}
    if profile["type"] in {
        "phone_number", "routing_bank_code", "routing_branch_code", "clearing_bank_code",
        "clearing_branch_code", "payment_system_routing_code", "payment_alias", "payment_alias_suffix",
        "identity_identifier_without_check", "identity_check_character",
    }:
        return {"status": "not_applicable"}
    return {"status": "not_established"}


def notes_zh(profile: dict) -> str:
    bits = [
        "issuer_scope=%s" % profile.get("issuer_scope"),
        profile.get("semantic_constraints") or "",
        "validation_scope=%s" % profile.get("validation_scope"),
        "研究状态原文=%s" % profile.get("status"),
    ]
    if profile.get("effective_from"):
        bits.append("effective_from=%s" % profile["effective_from"])
    return "；".join(b for b in bits if b)


def build_rule(profile: dict, fixtures_by_rule: dict) -> dict:
    rid = profile["id"]
    body = profile["regex_body"]
    full = profile["pcre2_full"]
    # Lint requires \\A(?:body)\\z with body == python_fullmatch_body
    if not (full.startswith("\\A(?:") and full.endswith(")\\z")):
        raise ValueError("%s bad pcre2_full" % rid)
    extracted = full[5:-3]
    # Lint requires python_fullmatch_body == text inside \\A(?:...)\\z.
    if extracted == body or extracted == "(?:" + body + ")":
        body = extracted
        full = "\\A(?:" + body + ")\\z"
    else:
        # Prefer research regex_body; re-wrap canonically.
        full = "\\A(?:" + body + ")\\z"

    pii_type = PII_TYPE_MAP[profile["type"]]
    status = STATUS_MAP[profile["status"]]
    fx = fixtures_by_rule.get(rid, [])
    positives = [f for f in fx if f["expect_syntax"] and f["kind"] == "synthetic_format_only"]
    if not positives:
        positives = [f for f in fx if f["expect_syntax"]]
    examples = []
    for f in positives[:3]:
        examples.append({
            "input": f["input"],
            "expected_syntax": True,
            "provenance": "synthetic_format_fixture_not_checksum_claim",
        })
    if not examples:
        raise ValueError("no positive examples for %s" % rid)

    # Prefer curated official / algorithm vectors as additional examples where applicable.
    if rid == "CN.foreign_permanent_resident2023":
        examples = [
            {
                "input": "932682198501010017",
                "expected_syntax": True,
                "provenance": "official_NIA_illustrative_example_not_reserved",
                "expected_checksum_arithmetic": True,
            },
            {
                "input": "911156200002290013",
                "expected_syntax": True,
                "provenance": "synthetic_research_fixture",
                "expected_checksum_arithmetic": True,
            },
        ]
    if rid in ("CN.hk_mainland_residence",):
        examples = [{
            "input": "810000198501010010",
            "expected_syntax": True,
            "provenance": "synthetic_research_fixture",
            "expected_checksum_arithmetic": True,
        }]
    if rid in ("CN.mo_mainland_residence",):
        examples = [{
            "input": "820000198501010012",
            "expected_syntax": True,
            "provenance": "synthetic_research_fixture",
            "expected_checksum_arithmetic": True,
        }]

    neg_from_fx = [f for f in fx if not f["expect_syntax"]]
    negatives = []
    seen = set()
    for f in neg_from_fx:
        if f["input"] in seen:
            continue
        seen.add(f["input"])
        negatives.append({"input": f["input"], "expected_syntax": False, "reason": f["kind"]})
        if len(negatives) >= 12:
            break
    if len(negatives) < 4:
        negatives = standard_negatives(body, examples[0]["input"])

    cs = checksum_for(profile)
    rule = {
        "id": rid,
        "pii_type": pii_type,
        "status": status,
        "regex_pcre2": full,
        "python_fullmatch_body": body,
        "checksum": cs,
        "notes_zh": notes_zh(profile),
        "semantic_checks": [],
        "normalization": [],
        "source_ids": list(profile.get("evidence") or []),
        "source_urls": [],  # filled after sources merge
        "accessed_on": "2026-11-13",
        "examples": examples,
        "negative_syntax_examples": negatives,
        "sample_notice_zh": "样本为合成格式串或官方说明性号码，不代表已发卡/开户/发证；格式正例不承诺校验码通过。",
        "issuer_scope": profile.get("issuer_scope"),
        "rule_version_label": profile.get("version"),
        "validation_scope": profile.get("validation_scope"),
        "source_dates": profile.get("source_dates") or {},
    }
    if profile.get("effective_from"):
        rule["effective_from"] = profile["effective_from"]
    if pii_type in COMPONENT_TYPES:
        rule["rule_role"] = "component"
    elif pii_type in ("routing_code",):
        rule["rule_role"] = "routing"
    elif status == "processor_scoped_profile":
        rule["rule_role"] = "processor_profile"
    else:
        rule["rule_role"] = "full_identifier"

    # Semantic hooks
    if rid in (
        "CN.foreign_permanent_resident2023",
        "CN.hk_mainland_residence",
        "CN.mo_mainland_residence",
    ):
        rule["semantic_checks"] = [
            "gregorian_birth_date_yyyymmdd_pos7_14",
            "not_after_reference_date",
            "region_or_country_code_not_verified",
        ]
        rule["normalization"] = [{
            "transform": "ascii_uppercase_last_char",
            "requires_option": "ascii_uppercase",
        }]
    if rid == "MO.boc.selfservice15":
        rule["normalization"] = [{
            "transform": "mo_boc_selfservice_00_prefix_channel",
            "layout": "canonical_17_starting_00_to_15",
            "requires_option": "normalize",
        }]
        rule["notes_zh"] += "；仅渠道归一化：canonical17 必须以00开头时去掉恰好两位00；禁止全局去零。"
    if rid == "SG.uob.account":
        rule["semantic_checks"] = ["uob_prefix_branch_directory_lookup"]
    if rid == "HK.phone.mobile_candidate":
        rule["semantic_checks"] = ["hk_mobile_allocation_directory_lookup"]
    if rid == "MO.phone.mobile_series":
        rule["semantic_checks"] = ["mo_mobile_allocation_directory_lookup"]
    if rid == "TR.iban" or rid == "TR.iban.2021":
        rule["semantic_checks"] = ["tr_iban_reserved_zero", "tr_iban_psp_directory_not_bundled"]
    if "iban" in rid:
        rule["normalization"] = [
            {"transform": "strip_print_format_spaces", "layout": "groups of 4 separated by single spaces"},
            {"transform": "ascii_uppercase", "requires_option": "ascii_uppercase"},
        ]
    if pii_type == "payment_card" and "worldpay" in rid:
        rule["notes_zh"] += "；processor_scoped_profile：默认不启用；需 options.processor_profiles.worldpay=true 或 options.algorithms.luhn 在本规则策略下显式打开。"
    return rule


def merge_sources(existing: dict, handoff_sources: list) -> dict:
    by_id = {s["id"]: s for s in existing["sources"]}
    for hs in handoff_sources:
        sid = hs["id"]
        grade = hs.get("evidence_grade") or "A"
        quality = {
            "A": "primary_government",
            "B-primary-processor": "primary_payment_processor",
        }.get(grade, "secondary_technical")
        # Prefer more specific quality when publisher hints
        pub = (hs.get("publisher") or "").lower()
        if "iso" in pub:
            quality = "primary_standard_body"
        elif "worldpay" in pub or "processor" in grade.lower():
            quality = "primary_payment_processor"
        elif "bank" in pub or "hsbc" in pub or "uob" in pub or "dbs" in pub or "ocbc" in pub:
            quality = "primary_financial_institution"
        elif "tcmb" in pub or "central bank" in pub or "monetary" in pub:
            quality = "primary_financial_regulator"
        elif "ofca" in pub or "imda" in pub or "nbtc" in pub or "itu" in pub:
            quality = "primary_telecom_regulator"
        entry = {
            "id": sid,
            "url": hs.get("url") or "",
            "accessed_on": hs.get("accessed_on") or "2026-11-13",
            "access_timezone": hs.get("access_timezone") or "Asia/Shanghai",
            "quality": quality,
            "retrieval": hs.get("retrieval") or "opened_webfetch",
            "supports": [],
            "limitations": hs.get("limitations") or "",
            "quality_note": "%s | %s | quote=%s | locator=%s"
            % (hs.get("title") or "", hs.get("publisher") or "", (hs.get("quote") or "")[:180], hs.get("locator") or ""),
            "source_date": hs.get("source_date"),
        }
        if sid in by_id:
            # Keep existing; append research note rather than clobber.
            old = by_id[sid]
            note = old.get("quality_note") or ""
            add = "banking-deep-research-2026-11: " + (hs.get("limitations") or hs.get("title") or "")
            if add not in note:
                old["quality_note"] = (note + " | " + add).strip(" |")
        else:
            by_id[sid] = entry
    existing["sources"] = sorted(by_id.values(), key=lambda s: s["id"])
    return existing


def fill_source_urls(rule: dict, sources_by_id: dict) -> None:
    urls = []
    for sid in rule.get("source_ids") or []:
        if sid not in sources_by_id:
            continue
        urls.append(sources_by_id[sid]["url"])
    rule["source_urls"] = urls


def update_coverage(cov: dict, new_rules: list) -> None:
    by_jur = {j["jurisdiction"]: j for j in cov["jurisdictions"]}
    bank_ids = defaultdict(list)
    id_ids = defaultdict(list)
    phone_ids = defaultdict(list)
    passport_ids = defaultdict(list)
    for r in new_rules:
        jur = r["jurisdiction"]
        pt = r["pii_type"]
        rid = r["id"]
        if pt in (
            "domestic_bank_account", "virtual_bank_account", "loan_account", "account_channel_input",
            "iban", "routing_code", "payment_alias", "payment_alias_component", "payment_card",
        ):
            bank_ids[jur].append(rid)
        elif pt in (
            "foreign_resident_id", "mainland_residence_permit", "resident_id", "identity_component",
            "national_id",
        ):
            id_ids[jur].append(rid)
        elif pt == "phone":
            phone_ids[jur].append(rid)
        elif pt in ("mainland_travel_permit", "exit_entry_permit", "passport"):
            passport_ids[jur].append(rid)

    def bump(jur: str, cat: str, rids: list, limit: str):
        if jur not in by_jur or not rids:
            return
        cell = by_jur[jur]["coverage"][cat]
        merged = list(dict.fromkeys(cell.get("rule_ids", []) + rids))
        cell["rule_ids"] = merged
        cell["status"] = "researched_partial"
        cell["limit_zh"] = limit

    for jur, rids in bank_ids.items():
        bump(
            jur,
            "bank",
            rids,
            "银行规则均为产品/渠道/代际限定 profile，不是国家级通用账号长度；目录成员资格与开户归属均为 unknown。",
        )
    for jur, rids in id_ids.items():
        bump(jur, "national_resident_id", rids, "含永居证/居住证等；不做发证存在性/归属核验。")
    for jur, rids in phone_ids.items():
        bump(
            jur,
            "phone",
            rids,
            "带年代的编号/分配快照；携号转网后分配记录不等于当前运营商；表外返回 unknown，不证明无效。",
        )
    for jur, rids in passport_ids.items():
        bump(jur, "passport", rids, "通行证/回乡证本体规则；换证次数等后缀是独立组件；不做发证核验。")

    # GLOBAL payment cards stay outside coverage matrix (GLOBAL not in jurisdictions list).


def write_json(path: Path, obj) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("handoff_dir", type=Path)
    args = ap.parse_args()
    h = args.handoff_dir
    if not (h / "specs/new-rule-specs.json").exists():
        print("handoff dir missing specs/new-rule-specs.json", file=sys.stderr)
        return 2

    profiles = json.loads((h / "specs/new-rule-specs.json").read_text(encoding="utf-8"))["rules"]
    format_fx = json.loads((h / "specs/format-fixtures.json").read_text(encoding="utf-8"))["fixtures"]
    algo_fx = json.loads((h / "specs/algorithm-fixtures.json").read_text(encoding="utf-8"))
    handoff_sources = json.loads((h / "sources.json").read_text(encoding="utf-8"))["sources"]
    bank_csv = (h / "coverage-by-country-bank.csv").read_text(encoding="utf-8")

    fx_by_rule = defaultdict(list)
    for f in format_fx:
        fx_by_rule[f["rule_id"]].append(f)

    # Build rules (skip TR.iban.2021 as separate id)
    built = []
    for p in profiles:
        if p["id"] in SKIP_NEW_IDS:
            continue
        rule = build_rule(p, fx_by_rule)
        rule["jurisdiction"] = target_jurisdiction(p)
        # Ensure id prefix matches jurisdiction file
        if not rule["id"].startswith(rule["jurisdiction"] + "."):
            # e.g. should already match for HK.mainland_travel_permit
            raise ValueError("id/jurisdiction mismatch %s / %s" % (rule["id"], rule["jurisdiction"]))
        built.append(rule)

    # Merge sources first so URL fill works
    sources_doc = json.loads((ROOT / "research/sources.json").read_text(encoding="utf-8"))
    sources_doc = merge_sources(sources_doc, handoff_sources)
    # Ensure every referenced source id exists (create stubs if handoff evidence id missing)
    by_sid = {s["id"]: s for s in sources_doc["sources"]}
    for rule in built:
        for sid in rule["source_ids"]:
            if sid not in by_sid:
                by_sid[sid] = {
                    "id": sid,
                    "url": "https://example.invalid/missing-handoff-source/" + sid,
                    "accessed_on": "2026-11-13",
                    "access_timezone": "Asia/Shanghai",
                    "quality": "secondary_technical",
                    "retrieval": "handoff_referenced_missing_record",
                    "supports": [],
                    "limitations": "handoff evidence id referenced by a profile but absent from sources.json; stub recorded as gap",
                    "quality_note": "stub",
                }
        fill_source_urls(rule, by_sid)
        # Drop jurisdiction helper field before write
    sources_doc["sources"] = sorted(by_sid.values(), key=lambda s: s["id"])
    write_json(ROOT / "research/sources.json", sources_doc)

    # Group and merge into jurisdiction files
    by_file = defaultdict(list)
    for rule in built:
        jur = rule.pop("jurisdiction")
        by_file[jur].append(rule)

    # Special: tighten TR.iban in place
    tr_path = ROOT / "rules/TR.json"
    tr_doc = json.loads(tr_path.read_text(encoding="utf-8"))
    for r in tr_doc["rules"]:
        if r["id"] == "TR.iban":
            r["regex_pcre2"] = "\\A(?:TR[0-9]{2}[0-9]{5}0[A-Z0-9]{16})\\z"
            r["python_fullmatch_body"] = "TR[0-9]{2}[0-9]{5}0[A-Z0-9]{16}"
            r["iban_bban_notation"] = "5!n1!n16!c"
            r["notes_zh"] = (
                "TCMB 2021-08-05 修订公报：TR+2位校验(02..98)+5位PSP代码+保留位0+16位字母数字账户域；"
                "账户域无统一内部格式，由PSP右对齐左补零；非银行支付服务商亦可获分配。"
                "不得把末16位当各银行native account；MOD97只证明算术；PSP目录成员资格为registry层。"
                "旧 Information Booklet「16 digits」概述不得压过公报 alphanumeric 条文。"
            )
            r["semantic_checks"] = ["tr_iban_reserved_zero", "tr_iban_psp_directory_not_bundled"]
            r["source_ids"] = list(dict.fromkeys((r.get("source_ids") or []) + ["tr.iban", "tr.booklet"]))
            fill_source_urls(r, by_sid)
            r["examples"] = [
                {
                    "input": "TR470000100100000350930001",
                    "expected_syntax": True,
                    "provenance": "official_TCMB_appendix_illustrative_example",
                    "expected_checksum_arithmetic": True,
                },
                {
                    "input": "TR90000010000000000000000A",
                    "expected_syntax": True,
                    "provenance": "synthetic_alphanumeric_bban",
                    "expected_checksum_arithmetic": True,
                },
                {
                    "input": "TR14111110ZZZZZZZZZZZZZZZZ",
                    "expected_syntax": True,
                    "provenance": "synthetic_research_fixture",
                    "expected_checksum_arithmetic": True,
                },
            ]
            # Keep / refresh negatives including reserved nonzero
            r["negative_syntax_examples"] = [
                {"input": "", "expected_syntax": False, "reason": "empty"},
                {"input": "TR470000110100000350930001", "expected_syntax": False, "reason": "reserved_field_nonzero"},
                {"input": "TR470000100100000350930001\n", "expected_syntax": False, "reason": "trailing_newline"},
                {"input": "\nTR470000100100000350930001", "expected_syntax": False, "reason": "leading_newline"},
                {"input": "TR47000010010000035093000", "expected_syntax": False, "reason": "too_short_or_missing_field"},
                {"input": "TR4700001001000003509300010", "expected_syntax": False, "reason": "too_long"},
                {"input": "tr470000100100000350930001", "expected_syntax": False, "reason": "lowercase"},
                {"input": "TR47 0000 1001 0000 0350 9300 01", "expected_syntax": False, "reason": "print_format_requires_normalize"},
            ]
    tr_doc["version"] = "2026.11.13.banking"
    write_json(tr_path, tr_doc)

    for jur, rules in sorted(by_file.items()):
        path = ROOT / "rules" / (jur + ".json")
        doc = json.loads(path.read_text(encoding="utf-8"))
        existing_ids = {r["id"] for r in doc["rules"]}
        for rule in rules:
            if rule["id"] in existing_ids:
                # Replace in place (re-import)
                doc["rules"] = [rule if r["id"] == rule["id"] else r for r in doc["rules"]]
            else:
                doc["rules"].append(rule)
        doc["version"] = "2026.11.13.banking"
        write_json(path, doc)

    # Coverage
    cov = json.loads((ROOT / "research/coverage.json").read_text(encoding="utf-8"))
    # re-attach jurisdiction for coverage bump
    for jur, rules in by_file.items():
        for r in rules:
            r["jurisdiction"] = jur
    flat = []
    for rules in by_file.values():
        flat.extend(rules)
    update_coverage(cov, flat)
    # CN bank notes
    for j in cov["jurisdictions"]:
        if j["jurisdiction"] == "CN":
            j["notes_zh"] = (
                "已增加2023外国人永居证/旧永居兼容、港澳居民内地居住证、电子往来港澳通行证、"
                "中行存折12位限定profile、CNAPS路由、招行历史一卡通接口；"
                "不存在全国统一国内账号长度规则。"
            )
            j["domestic_bank_account_policy_zh"] = (
                "国内银行账号：仅产品/渠道/代际限定 profile；禁止全国16/19位一刀切；"
                "PAN≠存款账号；CNAPS≠个人账号。"
            )
        if j["jurisdiction"] == "TH":
            j["domestic_bank_account_policy_zh"] = (
                "泰国：BBL 10位存款 vs 16位ATM卡；KBank CDM 10位渠道；SCB公司管理员手册10或13位；"
                "Krungthai/Krungsri/ttb等仍 unsupported。"
            )
        if j["jurisdiction"] == "SG":
            j["domestic_bank_account_policy_zh"] = (
                "新加坡：DBS10/POSB9/OCBC10|12/UOB普通10/VAN变长/HSBC12/SBI14/渣打等产品限定；"
                "旧IBG与FAST分行处理不得混用；UOB前3位为查表键非直接分行码。"
            )
        if j["jurisdiction"] == "HK":
            j["domestic_bank_account_policy_zh"] = (
                "香港：HSBC 10或12（非10–12任意）；BOCHK工资自动转账14位限定；"
                "清算行/分行码为候选语法，目录正文未核验前不作权威拒绝。"
            )
        if j["jurisdiction"] == "MO":
            j["domestic_bank_account_policy_zh"] = (
                "澳门：BNU10；ICBC网银主账号19（日期未知）；中银标准17/贷款15/旧12/自助渠道15；"
                "禁止全局去前导零；FPS ID未取得可信规范。"
            )
        if j["jurisdiction"] == "TR":
            j["domestic_bank_account_policy_zh"] = (
                "土耳其：正式IBAN为26位且账户域字母数字；原生各银行账号长度仍未取得完整一手规范；"
                "KOLAS为别名不是通用账号格式。"
            )
    write_json(ROOT / "research/coverage.json", cov)

    # Research artifacts (no copyrighted full tables)
    research_bank = ROOT / "research/banking-2026-11"
    research_bank.mkdir(parents=True, exist_ok=True)
    write_json(research_bank / "new-rule-specs.adapted.json", {
        "schema_version": "1.0",
        "adapted_from": "pii-banking-deep-research handoff 2026-11-13",
        "note_zh": "实现阶段独立改编；52个研究profile中TR.iban.2021并入TR.iban；未盲从导入。",
        "rules": profiles,
    })
    (research_bank / "coverage-by-country-bank.csv").write_text(bank_csv, encoding="utf-8")
    # Self-authored implementation notes will be written separately as markdown.

    # Fixtures for repo tests
    write_json(ROOT / "fixtures/banking-format-fixtures.json", {
        "classification": "synthetic format strings only; positives are NOT checksum-valid unless separately asserted",
        "fixtures": format_fx,
    })
    write_json(ROOT / "fixtures/banking-algorithm-fixtures.json", algo_fx)

    # Synthetic directories only (do not ship full UOB/OFCA extracts)
    write_json(ROOT / "fixtures/directories/synthetic-uob-prefix-branch.json", {
        "schema_version": "directory-1",
        "directory": "sg_uob_prefix_branch",
        "notice_zh": (
            "合成/公开关系样例，供接口与回归测试。完整 UOB Appendix A（2026-10-08）因再分发权利未核清，"
            "不提交；调用方可通过 pii.directories.set_provider 注入自备表。"
        ),
        "source_id": "sg.uob",
        "source_date": "2026-10-08",
        "prefix_to_branch": {
            "910": "030",
            "101": "001",
            "001": "001",
        },
    })
    write_json(ROOT / "fixtures/directories/synthetic-hk-mobile-ranges.json", {
        "schema_version": "directory-1",
        "directory": "hk_mobile_allocation",
        "notice_zh": (
            "合成分配状态样例（含 handoff 关键回归号段）。完整 OFCA 当前表请由调用方自备并注入；"
            "分配记录≠当前运营商（携号转网）。"
        ),
        "source_id": "hk.phone",
        "source_date": "2026-10-31",
        "ranges": [
            {"start": "40400000", "end": "40409999", "status": "reserved", "service": "mobile"},
            {"start": "40600000", "end": "40609999", "status": "allocated_to_operator", "service": "mobile"},
            {"start": "51000000", "end": "51999999", "status": "allocated_to_operator", "service": "mobile"},
        ],
    })
    write_json(ROOT / "fixtures/directories/synthetic-mo-mobile-ranges.json", {
        "schema_version": "directory-1",
        "directory": "mo_mobile_allocation",
        "notice_zh": "合成澳门移动首阶样例，保留空洞与660 VAS；完整监管表由调用方注入。",
        "source_id": "mo.phone.mobile",
        "source_date": "2026-04-23",
        "ranges": [
            {"start": "62000000", "end": "62999999", "status": "allocated", "service": "mobile"},
            {"start": "66050000", "end": "66050008", "status": "allocated", "service": "VAS"},
            {"start": "68000000", "end": "68007999", "status": "allocated", "service": "mobile"},
            {"start": "68008001", "end": "68999999", "status": "allocated", "service": "mobile"},
        ],
    })

    # Persist research re-run report path hint
    report = {
        "imported_profiles": len(built),
        "skipped": sorted(SKIP_NEW_IDS),
        "format_fixtures": len(format_fx),
        "algorithm_fixtures": len(algo_fx.get("fixtures", [])),
        "uob_full_table_committed": False,
        "ofca_full_table_committed": False,
        "note_zh": "完整 UOB/OFCA 表未提交；仅合成目录夹具。",
    }
    write_json(research_bank / "import-report.json", report)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
