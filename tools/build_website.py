#!/usr/bin/env python3
"""Build static PII Atlas site into website-dist/ from canonical rules/*.json.

Does not invent counts: metadata is computed from loaded rule files.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import time
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "website"
OUT = ROOT / "website-dist"

STATUS_ZH = {
    "syntax_supported": "现行官方结构",
    "official_scoped_syntax": "官方·产品/渠道限定",
    "processor_scoped_profile": "处理商剖面（默认关）",
    "dated_bank_generation_profile": "银行代际剖面",
    "dated_channel_profile": "渠道输入剖面",
    "standard_announcement_envelope": "标准公告外壳",
    "syntax_plus_required_allocation_lookup": "语法+分配表",
    "candidate_profile": "候选剖面",
    "historical_syntax": "历史格式",
    "dated_numbering_profile": "带年代编号剖面",
    "country_code_envelope_only": "国家区号外壳",
}

PII_TYPE_ZH = {
    "national_id": "国民身份号",
    "resident_id": "居民身份号",
    "tax_id": "税号",
    "tax_id_entity": "实体税号",
    "passport": "护照",
    "phone": "电话",
    "iban": "IBAN",
    "payment_card": "支付卡 PAN",
    "passport_mrz_field": "护照 MRZ 字段",
    "domestic_bank_account": "国内银行账户",
    "virtual_bank_account": "虚拟账户",
    "loan_account": "贷款账户",
    "account_channel_input": "渠道账户输入",
    "routing_code": "路由/清算代码",
    "payment_alias": "收款别名",
    "payment_alias_component": "别名组件",
    "foreign_resident_id": "外国人永居证",
    "mainland_residence_permit": "内地居住证",
    "mainland_travel_permit": "回乡证本体",
    "exit_entry_permit": "往来港澳通行证",
    "identity_component": "身份组件",
}

SIX = ["CN", "TH", "TR", "SG", "HK", "MO"]


def load_rules():
    rules = []
    for path in sorted((ROOT / "rules").glob("*.json")):
        if path.name == "algorithms.json":
            continue
        doc = json.loads(path.read_text(encoding="utf-8"))
        for r in doc["rules"]:
            role = r.get("rule_role") or "full_identifier"
            rules.append({
                "id": r["id"],
                "jurisdiction": doc["jurisdiction"],
                "jurisdiction_name_zh": doc.get("name_zh") or doc["jurisdiction"],
                "pii_type": r["pii_type"],
                "pii_type_zh": PII_TYPE_ZH.get(r["pii_type"], r["pii_type"]),
                "status": r["status"],
                "status_zh": STATUS_ZH.get(r["status"], r["status"]),
                "rule_role": role,
                "is_component": role in ("component", "routing"),
                "issuer_scope": r.get("issuer_scope") or "",
                "validation_scope": r.get("validation_scope") or "",
                "checksum_status": (r.get("checksum") or {}).get("status"),
                "checksum_algorithm": (r.get("checksum") or {}).get("algorithm"),
                "checksum_policy": (r.get("checksum") or {}).get("policy"),
                "checksum_evidence": (r.get("checksum") or {}).get("evidence"),
                "regex_pcre2": r["regex_pcre2"],
                "python_fullmatch_body": r["python_fullmatch_body"],
                "notes_zh": r.get("notes_zh") or "",
                "semantic_checks": r.get("semantic_checks") or [],
                "normalization": r.get("normalization") or [],
                "source_ids": r.get("source_ids") or [],
                "source_urls": r.get("source_urls") or [],
                "accessed_on": r.get("accessed_on"),
                "effective_from": r.get("effective_from"),
                "examples": [
                    {
                        "input": e["input"],
                        "expected_syntax": e.get("expected_syntax"),
                        "provenance": e.get("provenance"),
                        # never expose expected_checksum as "valid identity"
                    }
                    for e in (r.get("examples") or [])[:3]
                ],
                "sample_notice_zh": r.get("sample_notice_zh") or "",
                "file_version": doc.get("version"),
                "six_region": doc["jurisdiction"] in SIX or r["id"].startswith(tuple(s + "." for s in SIX)),
            })
    return rules


def main():
    rules = load_rules()
    algos = json.loads((ROOT / "rules/algorithms.json").read_text(encoding="utf-8"))
    cov_path = ROOT / "reports/coverage-summary.json"
    cov = json.loads(cov_path.read_text(encoding="utf-8")) if cov_path.exists() else {}

    full = [r for r in rules if not r["is_component"]]
    components = [r for r in rules if r["is_component"]]
    by_status = Counter(r["status"] for r in rules)
    by_type = Counter(r["pii_type"] for r in rules)
    by_jur = Counter(r["jurisdiction"] for r in rules)

    payload = {
        "schema_version": "pii-atlas-catalog-1",
        "brand": "PII Atlas",
        "generated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source_of_truth": "rules/*.json + rules/algorithms.json",
        "disclaimer_zh": (
            "本站只展示格式/校验码研究规则，不做发证、开户、归属或在线号码核验。"
            "样本为合成或官方说明性字符串；请勿提交真实证件/卡号/账号到任何在线接口。"
            "组件与路由规则单独标注，不计入完整 PII 类型宣传口径。"
        ),
        "attribution_zh": (
            "界面视觉风格参考同一所有者的 Agent Atlas（AlienHub/agent-catalog · "
            "https://agent-atlas.pindo.page/）；非第三方公司品牌仿冒。"
        ),
        "metadata": {
            "rule_count_total": len(rules),
            "full_identifier_count": len(full),
            "component_or_routing_count": len(components),
            "algorithm_count": len(algos.get("algorithms", [])),
            "jurisdiction_files": len(by_jur),
            "six_region_rule_count": sum(1 for r in rules if r["six_region"]),
            "by_status": dict(sorted(by_status.items())),
            "by_pii_type": dict(sorted(by_type.items())),
            "by_jurisdiction": dict(sorted(by_jur.items())),
            "coverage_summary": {
                "regex_rules_total": cov.get("regex_rules_total"),
                "checksum_algorithms_total": cov.get("checksum_algorithms_total"),
            },
            "rules_version_sample": rules[0]["file_version"] if rules else None,
        },
        "status_labels_zh": STATUS_ZH,
        "pii_type_labels_zh": PII_TYPE_ZH,
        "six_regions": SIX,
        "rules": rules,
        "algorithms": [
            {
                "id": a["id"],
                "evidence": a.get("evidence"),
                "default_policy": a.get("default_policy"),
                "lua_module": a.get("lua_module"),
                "notes_zh": a.get("notes_zh"),
            }
            for a in algos.get("algorithms", [])
        ],
    }

    raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    brand_hash = hashlib.sha256(raw[:4096] + b"pii-atlas").hexdigest()[:12]

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    # copy static assets
    for name in ("style.css", "favicon.svg", "app.js", "index.html", "notices.txt"):
        src = SRC / name
        if src.exists():
            shutil.copy2(src, OUT / name)

    (OUT / "catalog.json").write_bytes(raw + b"\n")
    # pretty copy for humans
    (OUT / "catalog.pretty.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    # stamp index.html placeholders
    index = (OUT / "index.html").read_text(encoding="utf-8")
    index = (
        index.replace("__RULE_COUNT__", str(len(rules)))
        .replace("__FULL_COUNT__", str(len(full)))
        .replace("__COMPONENT_COUNT__", str(len(components)))
        .replace("__BRAND_HASH__", brand_hash)
        .replace("__GENERATED__", payload["generated_at_utc"])
    )
    (OUT / "index.html").write_text(index, encoding="utf-8")

    # machine-readable download pointers (relative links into repo on GitHub after public)
    downloads = {
        "catalog_json": "catalog.json",
        "github_rules": "https://github.com/AlienHub/pii-validation-rules/tree/cursor/pii-validation-rules-impl-9e79/rules",
        "github_lua": "https://github.com/AlienHub/pii-validation-rules/tree/cursor/pii-validation-rules-impl-9e79/lua/pii",
        "branch": "cursor/pii-validation-rules-impl-9e79",
    }
    (OUT / "downloads.json").write_text(json.dumps(downloads, indent=2) + "\n", encoding="utf-8")

    print(json.dumps({
        "out": str(OUT),
        "rules": len(rules),
        "full_identifiers": len(full),
        "components": len(components),
        "brand_hash": brand_hash,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
