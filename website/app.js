/* PII Atlas — static catalog UI. Visual language aligned with Agent Atlas
 * (AlienHub/agent-catalog). Data loaded from build-time catalog.json only.
 * No input analytics, no live number validation endpoints.
 */
(function () {
  "use strict";

  const SIX = ["CN", "TH", "TR", "SG", "HK", "MO"];
  const emptyFilters = {
    search: "",
    jurisdiction: "",
    pii_type: "",
    status: "",
    checksum: "",
    sixOnly: true,
    hideComponents: true,
  };

  const I18N = {
    zh: {
      brandTag: "目录",
      note: "格式 / 校验码规则目录 · 非发证核验",
      introTitle: "PII Atlas",
      introBody: "浏览按辖区组织的标识符规则：语法状态、校验策略、产品/渠道范围与来源。不做开户、发证或归属核验。",
      searchPh: "搜索规则 ID、辖区、类型、issuer_scope…",
      allJur: "全部辖区",
      allType: "全部类型",
      allStatus: "全部状态",
      allChecksum: "全部校验状态",
      sixOnly: "仅六地 CN/TH/TR/SG/HK/MO",
      hideComponents: "隐藏组件/路由（不计入完整 PII）",
      reset: "清除筛选",
      rules: "规则（含组件）",
      fullIds: "完整标识符",
      components: "组件/路由",
      algos: "校验算法",
      empty: "没有匹配的规则",
      detailEyebrow: "RULE RECORD",
      close: "关闭详情",
      copyRegex: "复制正则",
      copyId: "复制 ID",
      copied: "已复制",
      downloads: "下载",
      catalogJson: "catalog.json",
      githubRules: "GitHub rules/",
      githubLua: "GitHub lua/pii/",
      notices: "声明",
      lang: "EN",
      pan: "支付卡 PAN",
      bank: "银行账户",
      routing: "路由/清算",
      alias: "收款别名",
    },
    en: {
      brandTag: "catalog",
      note: "Format / checksum rules · not issuer verification",
      introTitle: "PII Atlas",
      introBody: "Browse jurisdiction rules: syntax status, checksum policy, product/channel scope and sources. No account, issuance or ownership checks.",
      searchPh: "Search rule id, jurisdiction, type, issuer_scope…",
      allJur: "All jurisdictions",
      allType: "All types",
      allStatus: "All statuses",
      allChecksum: "All checksum statuses",
      sixOnly: "Six regions only CN/TH/TR/SG/HK/MO",
      hideComponents: "Hide components/routing (not full PII types)",
      reset: "Clear filters",
      rules: "Rules (incl. components)",
      fullIds: "Full identifiers",
      components: "Components/routing",
      algos: "Checksum algorithms",
      empty: "No matching rules",
      detailEyebrow: "RULE RECORD",
      close: "Close",
      copyRegex: "Copy regex",
      copyId: "Copy ID",
      copied: "Copied",
      downloads: "Downloads",
      catalogJson: "catalog.json",
      githubRules: "GitHub rules/",
      githubLua: "GitHub lua/pii/",
      notices: "Notices",
      lang: "中文",
      pan: "Payment PAN",
      bank: "Bank account",
      routing: "Routing/clearing",
      alias: "Payment alias",
    },
  };

  let lang = "zh";
  let data = null;
  let filters = { ...emptyFilters };
  let selected = null;
  let downloads = null;

  const el = (tag, cls, text) => {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  };

  const t = (k) => I18N[lang][k] || k;

  function typeBucket(piiType) {
    if (piiType === "payment_card") return "pan";
    if (["domestic_bank_account", "virtual_bank_account", "loan_account", "account_channel_input", "iban"].includes(piiType)) return "bank";
    if (piiType === "routing_code") return "routing";
    if (piiType === "payment_alias" || piiType === "payment_alias_component") return "alias";
    return "other";
  }

  function matches(rule) {
    const q = filters.search.trim().toLowerCase();
    if (filters.sixOnly && !rule.six_region && rule.jurisdiction !== "GLOBAL") return false;
    if (filters.hideComponents && rule.is_component) return false;
    if (filters.jurisdiction && rule.jurisdiction !== filters.jurisdiction) return false;
    if (filters.pii_type && rule.pii_type !== filters.pii_type) return false;
    if (filters.status && rule.status !== filters.status) return false;
    if (filters.checksum && rule.checksum_status !== filters.checksum) return false;
    if (!q) return true;
    const hay = [
      rule.id,
      rule.jurisdiction,
      rule.jurisdiction_name_zh,
      rule.pii_type,
      rule.pii_type_zh,
      rule.status,
      rule.status_zh,
      rule.issuer_scope,
      rule.notes_zh,
      rule.checksum_algorithm || "",
    ].join("\n").toLowerCase();
    return hay.includes(q);
  }

  async function copyText(text, btn) {
    try {
      await navigator.clipboard.writeText(text);
      const old = btn.textContent;
      btn.textContent = t("copied");
      setTimeout(() => { btn.textContent = old; }, 1200);
    } catch (_) {
      /* ignore */
    }
  }

  function openDetail(rule) {
    selected = rule;
    const dlg = document.getElementById("details");
    const content = document.getElementById("detailContent");
    content.replaceChildren();

    const head = el("div", "detailhead");
    head.append(el("h2", null, rule.id));
    head.append(el("p", "muted", rule.issuer_scope || rule.pii_type_zh));
    content.append(head);

    const pills = el("div", "card-tags");
    pills.append(el("span", "pill status-pill " + rule.status, rule.status_zh));
    pills.append(el("span", "pill", rule.pii_type_zh));
    pills.append(el("span", "pill", rule.jurisdiction));
    if (rule.is_component) pills.append(el("span", "pill", "component/routing"));
    content.append(pills);

    content.append(el("div", "scope-banner", data.disclaimer_zh));

    const defs = [
      ["状态", rule.status + " · " + rule.status_zh],
      ["类型", rule.pii_type + " · " + rule.pii_type_zh],
      ["角色", rule.rule_role],
      ["校验状态", rule.checksum_status || "—"],
      ["校验算法", rule.checksum_algorithm || "—"],
      ["校验策略", rule.checksum_policy || "—"],
      ["证据", rule.checksum_evidence || "—"],
      ["issuer_scope", rule.issuer_scope || "—"],
      ["validation_scope", rule.validation_scope || "—"],
      ["规则版本", rule.file_version || "—"],
      ["查阅日", rule.accessed_on || "—"],
      ["生效", rule.effective_from || "—"],
    ];
    const dl = el("dl");
    defs.forEach(([dt, dd]) => {
      const row = el("div");
      row.append(el("dt", null, dt));
      row.append(el("dd", null, dd));
      dl.append(row);
    });
    content.append(dl);

    content.append(el("h3", null, "PCRE2"));
    const code = el("pre", "codeblock", rule.regex_pcre2);
    content.append(code);
    const copies = el("div", "copyrow");
    const b1 = el("button", null, t("copyRegex"));
    b1.addEventListener("click", () => copyText(rule.regex_pcre2, b1));
    const b2 = el("button", null, t("copyId"));
    b2.addEventListener("click", () => copyText(rule.id, b2));
    copies.append(b1, b2);
    content.append(copies);

    content.append(el("h3", null, "说明 / 限制"));
    content.append(el("p", null, rule.notes_zh || "—"));

    if (rule.normalization && rule.normalization.length) {
      content.append(el("h3", null, "归一化（仅显式 opt-in）"));
      content.append(el("pre", "codeblock", JSON.stringify(rule.normalization, null, 2)));
    }
    if (rule.semantic_checks && rule.semantic_checks.length) {
      content.append(el("h3", null, "语义检查项"));
      content.append(el("p", null, rule.semantic_checks.join("、")));
    }

    const ev = el("div", "evidence");
    ev.append(el("h3", null, "来源 URL"));
    (rule.source_urls || []).forEach((u) => {
      const a = el("a", null, u);
      a.href = u;
      a.target = "_blank";
      a.rel = "noopener noreferrer";
      ev.append(a);
    });
    if (!(rule.source_urls || []).length) ev.append(el("p", "muted", "无 URL"));
    content.append(ev);

    content.append(el("h3", null, "合成/说明性样本（非真实核验）"));
    (rule.examples || []).forEach((ex) => {
      const row = el("p", "muted");
      row.textContent = (ex.provenance || "sample") + " · syntax=" + String(ex.expected_syntax);
      content.append(row);
      content.append(el("pre", "codeblock", ex.input === "" ? "(empty string)" : ex.input));
    });
    if (rule.sample_notice_zh) content.append(el("p", "muted", rule.sample_notice_zh));

    dlg.showModal();
  }

  function renderCards(list) {
    const grid = document.getElementById("rows");
    grid.replaceChildren();
    if (!list.length) {
      grid.append(el("p", "muted", t("empty")));
      return;
    }
    list.forEach((rule) => {
      const card = el("article", "app-card" + (rule.is_component ? " role-component" : ""));
      const head = el("div", "card-head");
      const name = el("div", "appname", rule.id);
      head.append(name);
      card.append(head);
      const tags = el("div", "card-tags");
      tags.append(el("span", "pill status-pill " + rule.status, rule.status_zh));
      tags.append(el("span", "pill interface-pill", rule.jurisdiction));
      const bucket = typeBucket(rule.pii_type);
      if (bucket !== "other") tags.append(el("span", "pill source-pill", t(bucket)));
      else tags.append(el("span", "pill", rule.pii_type_zh));
      card.append(tags);
      const bottom = el("div", "card-bottom");
      bottom.append(el("div", "listmeta", (rule.issuer_scope || rule.pii_type_zh).slice(0, 80)));
      const open = el("button", "textbutton", "详情");
      open.addEventListener("click", (e) => { e.stopPropagation(); openDetail(rule); });
      bottom.append(open);
      card.append(bottom);
      card.addEventListener("click", () => openDetail(rule));
      grid.append(card);
    });
  }

  function render() {
    const list = data.rules.filter(matches);
    document.getElementById("visibleCount").textContent = String(list.length);
    renderCards(list);
  }

  function buildShell() {
    const root = document.getElementById("app");
    root.replaceChildren();

    const header = el("header");
    const start = el("div", "header-start");
    const brand = el("a", "brand");
    brand.href = "./";
    const mark = document.createElement("img");
    mark.className = "brandmark";
    mark.src = "favicon.svg?v=" + (document.documentElement.dataset.brandHash || "");
    mark.width = 34;
    mark.height = 34;
    mark.alt = "";
    mark.setAttribute("aria-hidden", "true");
    brand.append(mark, document.createTextNode(" PII Atlas "), el("span", "tag", t("brandTag")));
    start.append(brand);
    header.append(start);
    header.append(el("span", "headernote", t("note")));
    const langBtn = el("button", null, t("lang"));
    langBtn.addEventListener("click", () => {
      lang = lang === "zh" ? "en" : "zh";
      buildShell();
      render();
    });
    const langWrap = el("div", "lang-switch");
    langWrap.append(langBtn);
    header.append(langWrap);
    root.append(header);

    const main = el("main");
    const intro = el("div", "intro");
    const left = el("div");
    left.append(el("h1", null, t("introTitle")));
    left.append(el("p", null, t("introBody")));
    const six = el("div", "six-focus");
    SIX.forEach((j) => {
      const b = el("button", "collection" + (filters.jurisdiction === j ? " active" : ""), j);
      b.addEventListener("click", () => {
        filters.jurisdiction = filters.jurisdiction === j ? "" : j;
        filters.sixOnly = true;
        buildShell();
        render();
      });
      six.append(b);
    });
    left.append(six);
    intro.append(left);

    const exports = el("div", "exports");
    const dlCat = el("a", "assetlink", t("catalogJson"));
    dlCat.href = "catalog.json";
    dlCat.download = "catalog.json";
    exports.append(dlCat);
    if (downloads) {
      const a1 = el("a", "assetlink", t("githubRules"));
      a1.href = downloads.github_rules;
      a1.target = "_blank";
      a1.rel = "noopener noreferrer";
      const a2 = el("a", "assetlink", t("githubLua"));
      a2.href = downloads.github_lua;
      a2.target = "_blank";
      a2.rel = "noopener noreferrer";
      exports.append(a1, a2);
    }
    const notice = el("a", "assetlink", t("notices"));
    notice.href = "notices.txt";
    exports.append(notice);
    intro.append(exports);
    main.append(intro);

    const disc = el("div", "disclaimer");
    const strong = el("strong", null, lang === "zh" ? "声明：" : "Notice: ");
    disc.append(strong);
    disc.append(document.createTextNode(data.disclaimer_zh + " " + data.attribution_zh));
    main.append(disc);

    const meta = data.metadata;
    const summary = el("div", "summary");
    summary.setAttribute("aria-label", "目录概况");
    [
      [t("rules"), meta.rule_count_total],
      [t("fullIds"), meta.full_identifier_count],
      [t("components"), meta.component_or_routing_count],
      [t("algos"), meta.algorithm_count],
    ].forEach(([label, value]) => {
      const s = el("span");
      s.append(el("strong", null, String(value)));
      s.append(document.createTextNode(" " + label));
      summary.append(s);
    });
    const vis = el("span", "version");
    vis.innerHTML = "可见 <strong id=\"visibleCount\">0</strong>";
    summary.append(vis);
    main.append(summary);

    const workspace = el("section", "workspace");
    const tools = el("div", "tools");
    const searchLabel = el("label", "search");
    searchLabel.append(el("span", null, "⌕"));
    const input = document.createElement("input");
    input.type = "search";
    input.id = "search";
    input.placeholder = t("searchPh");
    input.setAttribute("aria-label", t("searchPh"));
    input.value = filters.search;
    input.addEventListener("input", () => { filters.search = input.value; render(); });
    searchLabel.append(input);
    tools.append(searchLabel);

    function select(key, label, values, allLabel) {
      const s = document.createElement("select");
      s.setAttribute("aria-label", label);
      s.append(new Option(allLabel, ""));
      values.forEach(([v, text]) => s.append(new Option(text, v)));
      s.value = filters[key];
      s.addEventListener("change", () => { filters[key] = s.value; render(); });
      tools.append(s);
    }

    const jurOpts = [...new Set(data.rules.map((r) => r.jurisdiction))].sort().map((j) => [j, j]);
    const typeOpts = Object.keys(data.pii_type_labels_zh).sort().map((k) => [k, data.pii_type_labels_zh[k]]);
    const statusOpts = Object.keys(data.status_labels_zh).sort().map((k) => [k, data.status_labels_zh[k]]);
    const checksumOpts = [...new Set(data.rules.map((r) => r.checksum_status).filter(Boolean))].sort().map((k) => [k, k]);
    select("jurisdiction", t("allJur"), jurOpts, t("allJur"));
    select("pii_type", t("allType"), typeOpts, t("allType"));
    select("status", t("allStatus"), statusOpts, t("allStatus"));
    select("checksum", t("allChecksum"), checksumOpts, t("allChecksum"));

    const toggles = el("div", "filter-toggles");
    function check(key, label) {
      const lab = el("label", "svgfilter");
      const c = document.createElement("input");
      c.type = "checkbox";
      c.checked = !!filters[key];
      c.addEventListener("change", () => { filters[key] = c.checked; render(); });
      lab.append(c, document.createTextNode(label));
      toggles.append(lab);
    }
    check("sixOnly", t("sixOnly"));
    check("hideComponents", t("hideComponents"));
    const reset = el("button", null, t("reset"));
    reset.addEventListener("click", () => { filters = { ...emptyFilters }; buildShell(); render(); });
    toggles.append(reset);
    tools.append(toggles);
    workspace.append(tools);

    workspace.append(el("div", "catalog-grid", null));
    workspace.lastChild.id = "rows";
    main.append(workspace);

    const footer = el("footer");
    footer.append(el("span", "muted", "PII Atlas · source of truth: rules/*.json"));
    footer.append(el("a", null, "notices.txt"));
    footer.lastChild.href = "notices.txt";
    main.append(footer);
    root.append(main);

    const dlg = document.createElement("dialog");
    dlg.id = "details";
    const top = el("div", "dialogtop");
    top.append(el("span", "eyebrow", t("detailEyebrow")));
    const close = el("button", null, "✕");
    close.setAttribute("aria-label", t("close"));
    close.addEventListener("click", () => dlg.close());
    top.append(close);
    dlg.append(top);
    const detail = el("div");
    detail.id = "detailContent";
    dlg.append(detail);
    dlg.addEventListener("click", (e) => { if (e.target === dlg) dlg.close(); });
    root.append(dlg);
  }

  async function boot() {
    try {
      const [cat, dl] = await Promise.all([
        fetch("catalog.json", { cache: "no-cache" }).then((r) => r.json()),
        fetch("downloads.json", { cache: "no-cache" }).then((r) => r.json()).catch(() => null),
      ]);
      data = cat;
      downloads = dl;
      buildShell();
      render();
    } catch (err) {
      document.getElementById("app").textContent = "无法加载 catalog.json：" + String(err);
    }
  }

  boot();
})();
