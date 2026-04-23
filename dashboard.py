"""
dashboard.py  —  Egypt BA Sales Dashboard
Reads your supervisor's Excel (sales_data.xlsx) and generates report.html.

Usage:
    python3 dashboard.py
"""

import sys
import json
import pandas as pd
import plotly.graph_objects as go

from targets import TEAM_MONTHLY_TARGETS, DEFAULT_TARGET


# ─────────────────────────────────────────────────────────────────
# 1.  File & sheet config
# ─────────────────────────────────────────────────────────────────

EXCEL_FILE = "sales_data.xlsx"

# Non-selling markers — treated as 0 sales
NO_SALE_MARKERS = {
    "cong", "nil", "sick", "anual", "annual", "eid", "eid ", "cong ",
    "nil ", "sick ", "anual ", "xxxxxxx", "xxxxxxxxx", "nan", "", "éid",
}

# Per-sheet config
SHEET_CONFIG = {
    "Jan26":  {"month": "Jan 2026", "ba_row": 15, "total_row": 49},
    "Feb26":  {"month": "Feb 2026", "ba_row": 16, "total_row": 46},
    "march ": {"month": "Mar 2026", "ba_row": 16, "total_row": 49},
    "APRIL":  {"month": "Apr 2026", "ba_row": 20, "daily_start": 22, "daily_end": 55},
}

# Team membership (lower-case name → team)
TEAM_LOOKUP = {
    "nada": "Cairo",   "mary": "Cairo",    "nourhan": "Cairo",
    "marwa": "Cairo",  "esraa": "Cairo",   "eman1": "Cairo",
    "eman2": "Cairo",  "nouran": "Cairo",  "yasmin": "Cairo",
    "ahmed": "Cairo",  "atef": "Cairo",    "nadine": "Cairo",
    "samah": "Sharm",  "mamdouh": "Sharm", "mohamed": "Sharm",
    "rehab": "Hurgadah", "besher": "Hurgadah", "basher": "Hurgadah",
    "veronia": "Hurgadah",
}

# Canonical display name (handles spelling variants)
CANONICAL = {
    "basher": "Besher",
    "eman1 ": "Eman1",
    "eman2 ": "Eman2",
    "veronia ": "Veronia",
}


# ─────────────────────────────────────────────────────────────────
# 2.  Helpers
# ─────────────────────────────────────────────────────────────────

def clean_sales(raw) -> float:
    if raw is None or (isinstance(raw, float) and pd.isna(raw)):
        return 0.0
    s = str(raw).strip().lower().replace("$", "").replace(",", "")
    if s in NO_SALE_MARKERS:
        return 0.0
    try:
        return float(s)
    except ValueError:
        return 0.0


def normalize(name: str) -> str:
    s = str(name).strip().title()          # unify case: AHMED → Ahmed, basher → Basher
    return CANONICAL.get(s.lower(), s)


def get_ba_col_map(df, ba_row_idx):
    """Returns {display_name: sales_col}. Sales col = ba_name_col + 1."""
    row = df.iloc[ba_row_idx]
    skip = {"date", "item", "sales", "total", "nan", ""}
    result = {}
    for col_idx, val in enumerate(row):
        if pd.isna(val):
            continue
        s = str(val).strip()
        if s.lower() in skip:
            continue
        result[normalize(s)] = col_idx + 1
    return result


def extract_from_total_row(df, ba_col_map, total_row_idx):
    row = df.iloc[total_row_idx]
    return {name: clean_sales(row[col]) for name, col in ba_col_map.items()}


def extract_from_daily_rows(df, ba_col_map, start_row, end_row):
    totals = {name: 0.0 for name in ba_col_map}
    skip_labels = {"total", "percanet", "percent", "percentage", "nan", "target"}
    for row_idx in range(start_row, min(end_row + 1, len(df))):
        date_cell = str(df.iloc[row_idx, 2]).strip().lower()
        if date_cell in skip_labels or date_cell == "nan":
            continue
        for name, sales_col in ba_col_map.items():
            totals[name] += clean_sales(df.iloc[row_idx, sales_col])
    return totals


# ─────────────────────────────────────────────────────────────────
# 3.  Load all sheets
# ─────────────────────────────────────────────────────────────────

def load_all_data():
    try:
        xl = pd.ExcelFile(EXCEL_FILE)
    except FileNotFoundError:
        sys.exit(f"ERROR: '{EXCEL_FILE}' not found.")

    records = []
    for sheet_name, cfg in SHEET_CONFIG.items():
        if sheet_name not in xl.sheet_names:
            print(f"  Warning: sheet '{sheet_name}' not found, skipping.")
            continue
        df = pd.read_excel(xl, sheet_name=sheet_name, header=None)
        ba_col_map = get_ba_col_map(df, cfg["ba_row"])

        if "total_row" in cfg:
            sales_map = extract_from_total_row(df, ba_col_map, cfg["total_row"])
        else:
            sales_map = extract_from_daily_rows(
                df, ba_col_map, cfg["daily_start"], cfg["daily_end"]
            )

        for ba_name, amount in sales_map.items():
            team = TEAM_LOOKUP.get(ba_name.lower().strip(), "Unknown")
            records.append({
                "BA": ba_name, "Month": cfg["month"],
                "Sales": amount, "Team": team,
            })

    df_all = pd.DataFrame(records)
    df_all = df_all[df_all["Sales"] > 0].copy()
    return df_all


# ─────────────────────────────────────────────────────────────────
# 4.  Analysis
# ─────────────────────────────────────────────────────────────────

def analyse(df):
    month_order = ["Jan 2026", "Feb 2026", "Mar 2026", "Apr 2026"]
    df["Month"] = pd.Categorical(df["Month"], categories=month_order, ordered=True)

    ba_monthly = df.groupby(["BA", "Month", "Team"], observed=True)["Sales"].sum().reset_index()
    ba_monthly["Target"] = ba_monthly.apply(
        lambda r: TEAM_MONTHLY_TARGETS.get(str(r["Month"]), {}).get(r["Team"], DEFAULT_TARGET),
        axis=1,
    )
    ba_monthly["Attainment"] = (ba_monthly["Sales"] / ba_monthly["Target"] * 100).round(1)
    ba_monthly["Status"]     = ba_monthly["Attainment"].apply(
        lambda x: "On Target" if x >= 100 else ("Close" if x >= 80 else "Below Target")
    )

    ba_totals = (
        ba_monthly.groupby(["BA", "Team"], observed=True)
        .agg(Total=("Sales", "sum"), Months=("Month", "count"))
        .reset_index().sort_values("Total", ascending=False)
    )
    ba_totals["Avg"] = (ba_totals["Total"] / ba_totals["Months"]).round(0)

    team_monthly  = df.groupby(["Team", "Month"], observed=True)["Sales"].sum().reset_index()
    monthly_total = df.groupby("Month", observed=True)["Sales"].sum().reset_index()

    return ba_monthly, ba_totals, team_monthly, monthly_total


# ─────────────────────────────────────────────────────────────────
# 5.  Charts  (Plotly, embedded as JSON for JS re-rendering)
# ─────────────────────────────────────────────────────────────────

TEAM_PAL = {"Cairo": "#4f8ef7", "Sharm": "#2ecc71", "Hurgadah": "#f39c12", "Unknown": "#95a5a6"}
STATUS_COL = {"On Target": "#2ecc71", "Close": "#f39c12", "Below Target": "#e74c3c"}
CHART_BG = "rgba(0,0,0,0)"
FONT_COL = "#c9d1e0"
GRID_COL = "rgba(255,255,255,0.07)"


def _base_layout(title=""):
    return dict(
        title=dict(text=title, font=dict(color=FONT_COL, size=14), x=0.01),
        plot_bgcolor=CHART_BG, paper_bgcolor=CHART_BG,
        font=dict(color=FONT_COL, family="-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif"),
        margin=dict(t=48, b=36, l=12, r=12),
        legend=dict(orientation="h", y=1.18, font=dict(color=FONT_COL)),
    )


def chart_bar_ba_json(ba_totals):
    traces = []
    for team, grp in ba_totals.groupby("Team"):
        color = TEAM_PAL.get(team, "#888")
        traces.append(dict(
            type="bar", name=team,
            x=grp["BA"].tolist(), y=grp["Total"].tolist(),
            marker=dict(color=color, opacity=0.9),
            text=["${:,.0f}".format(v) for v in grp["Total"]],
            textposition="outside", textfont=dict(color=FONT_COL, size=10),
            hovertemplate="<b>%{x}</b><br>$%{y:,.0f}<extra>" + team + "</extra>",
        ))
    layout = _base_layout("Total Sales per BA")
    layout.update(dict(
        barmode="group",
        xaxis=dict(tickfont=dict(color=FONT_COL, size=10), gridcolor=GRID_COL, linecolor=GRID_COL),
        yaxis=dict(tickfont=dict(color=FONT_COL), gridcolor=GRID_COL, tickprefix="$"),
    ))
    return json.dumps({"data": traces, "layout": layout})


def chart_trend_json(monthly_total, team_monthly):
    traces = []
    for team, grp in team_monthly.groupby("Team"):
        color = TEAM_PAL.get(team, "#888")
        traces.append(dict(
            type="scatter", mode="lines+markers", name=team,
            x=[str(m) for m in grp["Month"].tolist()],
            y=grp["Sales"].tolist(),
            line=dict(color=color, width=2),
            marker=dict(color=color, size=7),
            hovertemplate="<b>%{x}</b><br>$%{y:,.0f}<extra>" + team + "</extra>",
        ))
    # Total line
    traces.append(dict(
        type="scatter", mode="lines+markers", name="All Teams",
        x=[str(m) for m in monthly_total["Month"].tolist()],
        y=monthly_total["Sales"].tolist(),
        line=dict(color="#fff", width=3, dash="dot"),
        marker=dict(color="#fff", size=9),
        hovertemplate="<b>%{x}</b><br>Total: $%{y:,.0f}<extra></extra>",
    ))
    layout = _base_layout("Monthly Sales Trend")
    layout.update(dict(
        xaxis=dict(tickfont=dict(color=FONT_COL), gridcolor=GRID_COL),
        yaxis=dict(tickfont=dict(color=FONT_COL), gridcolor=GRID_COL, tickprefix="$"),
    ))
    return json.dumps({"data": traces, "layout": layout})


def chart_heatmap_json(ba_monthly):
    pivot = ba_monthly.pivot_table(
        index="BA", columns="Month", values="Attainment", aggfunc="mean", observed=True
    )
    text = [["{:.0f}%".format(v) if not pd.isna(v) else "—" for v in row] for row in pivot.values]
    trace = dict(
        type="heatmap",
        z=[[None if pd.isna(v) else round(v, 1) for v in row] for row in pivot.values],
        x=[str(c) for c in pivot.columns.tolist()],
        y=pivot.index.tolist(),
        colorscale=[[0,"#e74c3c"],[0.55,"#f39c12"],[0.75,"#f1c40f"],[1,"#2ecc71"]],
        zmin=0, zmax=150,
        text=text, texttemplate="%{text}",
        showscale=True,
        colorbar=dict(title=dict(text="Attainment %", font=dict(color=FONT_COL)),
                      tickfont=dict(color=FONT_COL)),
        hovertemplate="<b>%{y}</b> — %{x}<br>Attainment: %{text}<extra></extra>",
    )
    layout = _base_layout("Target Attainment Heatmap")
    layout.update(dict(
        margin=dict(t=48, b=36, l=90, r=12),
        xaxis=dict(tickfont=dict(color=FONT_COL)),
        yaxis=dict(tickfont=dict(color=FONT_COL, size=11)),
    ))
    return json.dumps({"data": [trace], "layout": layout})


def chart_gauge_team_json(team_monthly, ba_monthly):
    """Progress bars per team per month — returned as table data."""
    team_targets = {}
    for month, teams in TEAM_MONTHLY_TARGETS.items():
        for team, per_ba in teams.items():
            # Multiply per-BA target by number of BAs in team
            n = ba_monthly[ba_monthly["Team"] == team]["BA"].nunique()
            team_targets[(team, month)] = per_ba * n
    rows = []
    for _, r in team_monthly.iterrows():
        target = team_targets.get((r["Team"], str(r["Month"])), 0)
        pct = round(r["Sales"] / target * 100, 1) if target else 0
        rows.append({"team": r["Team"], "month": str(r["Month"]),
                     "sales": r["Sales"], "target": target, "pct": pct})
    return rows


# ─────────────────────────────────────────────────────────────────
# 6.  HTML assembly
# ─────────────────────────────────────────────────────────────────

def build_html(df_all, ba_monthly, ba_totals, team_monthly, monthly_total):
    total_sales = df_all["Sales"].sum()
    top_ba      = ba_totals.iloc[0]["BA"]
    top_amt     = ba_totals.iloc[0]["Total"]
    n_bas       = ba_totals["BA"].nunique()
    avg_month   = round(total_sales / df_all["Month"].nunique())

    # Serialize all data to JSON for client-side filtering
    records = ba_monthly.copy()
    records["Month"] = records["Month"].astype(str)
    all_data_json = records.to_json(orient="records")

    chart_ba_json    = chart_bar_ba_json(ba_totals)
    chart_trend      = chart_trend_json(monthly_total, team_monthly)
    chart_heat       = chart_heatmap_json(ba_monthly)
    team_progress    = chart_gauge_team_json(team_monthly, ba_monthly)
    team_progress_js = json.dumps(team_progress)

    months_list = sorted(df_all["Month"].astype(str).unique().tolist())
    teams_list  = sorted(df_all["Team"].unique().tolist())
    bas_list    = sorted(df_all["BA"].unique().tolist())

    gen = pd.Timestamp.now().strftime("%d %b %Y  %H:%M")

    # Spark values for KPI trend arrows
    m_vals = monthly_total["Sales"].tolist()
    trend_arrow = "↑" if len(m_vals) >= 2 and m_vals[-1] >= m_vals[-2] else "↓"
    trend_color = "#2ecc71" if trend_arrow == "↑" else "#e74c3c"

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Egypt BA Sales Dashboard</title>
<script src="https://cdn.plot.ly/plotly-2.32.0.min.js"></script>
<style>
:root{{
  --bg:#0f1117; --sidebar:#161b27; --card:#1e2535; --card2:#252d3d;
  --accent:#4f8ef7; --green:#2ecc71; --orange:#f39c12; --red:#e74c3c;
  --text:#c9d1e0; --muted:#6b7a99; --border:rgba(255,255,255,0.07);
  --radius:14px;
}}
*{{box-sizing:border-box;margin:0;padding:0}}
body{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
      background:var(--bg);color:var(--text);min-height:100vh;display:flex}}

/* ── Sidebar ── */
#sidebar{{width:240px;min-width:240px;background:var(--sidebar);
         border-right:1px solid var(--border);padding:0;display:flex;flex-direction:column;
         position:sticky;top:0;height:100vh;overflow-y:auto}}
.sidebar-logo{{padding:24px 20px 20px;border-bottom:1px solid var(--border)}}
.sidebar-logo h1{{font-size:15px;font-weight:700;color:#fff;line-height:1.3}}
.sidebar-logo p{{font-size:11px;color:var(--muted);margin-top:4px}}
.sidebar-section{{padding:20px 16px 8px;font-size:10px;font-weight:700;
                  color:var(--muted);letter-spacing:.1em;text-transform:uppercase}}
.filter-group{{padding:0 12px 16px}}
.filter-label{{font-size:11px;color:var(--muted);margin-bottom:6px;display:block}}
.filter-group select,
.filter-group input{{width:100%;background:var(--card);color:var(--text);
  border:1px solid var(--border);border-radius:8px;padding:8px 10px;font-size:12px;outline:none}}
.filter-group select:focus,
.filter-group input:focus{{border-color:var(--accent)}}
.btn-reset{{margin:0 12px 20px;width:calc(100% - 24px);background:var(--accent);
            color:#fff;border:none;border-radius:8px;padding:9px;font-size:12px;
            font-weight:600;cursor:pointer;transition:.15s}}
.btn-reset:hover{{background:#3a7de0}}
.sidebar-gen{{padding:16px;margin-top:auto;border-top:1px solid var(--border);
              font-size:10px;color:var(--muted);line-height:1.6}}
.team-pill{{display:inline-flex;align-items:center;gap:5px;padding:3px 8px;
            border-radius:20px;font-size:10px;font-weight:600;margin:2px}}

/* ── Main ── */
#main{{flex:1;overflow-y:auto;padding:28px 24px}}

/* KPIs */
.kpis{{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-bottom:24px}}
@media(max-width:1100px){{.kpis{{grid-template-columns:repeat(2,1fr)}}}}
.kpi{{background:var(--card);border-radius:var(--radius);padding:22px 24px;
      border:1px solid var(--border);position:relative;overflow:hidden}}
.kpi::before{{content:'';position:absolute;top:0;left:0;width:3px;height:100%;background:var(--accent)}}
.kpi.green::before{{background:var(--green)}}
.kpi.orange::before{{background:var(--orange)}}
.kpi.red::before{{background:var(--red)}}
.kpi-val{{font-size:26px;font-weight:800;color:#fff;line-height:1}}
.kpi-lbl{{font-size:11px;color:var(--muted);margin-top:6px}}
.kpi-sub{{font-size:11px;margin-top:8px;font-weight:600}}

/* Cards */
.card{{background:var(--card);border-radius:var(--radius);border:1px solid var(--border);
       margin-bottom:20px;overflow:hidden}}
.card-header{{padding:18px 22px 0;display:flex;justify-content:space-between;align-items:center}}
.card-header h2{{font-size:13px;font-weight:700;color:#fff}}
.card-header span{{font-size:11px;color:var(--muted)}}
.chart-wrap{{padding:6px 6px 12px}}
.g2{{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:20px}}
@media(max-width:900px){{.g2{{grid-template-columns:1fr}}}}

/* Team progress */
.team-grid{{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin-bottom:20px}}
@media(max-width:900px){{.team-grid{{grid-template-columns:1fr}}}}
.team-card{{background:var(--card);border-radius:var(--radius);border:1px solid var(--border);
            padding:20px}}
.team-card-header{{display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:14px}}
.team-name{{font-size:13px;font-weight:700;color:#fff}}
.team-month-sel{{background:var(--card2);color:var(--text);border:1px solid var(--border);
                 border-radius:6px;padding:4px 8px;font-size:11px;outline:none}}
.prog-row{{margin-bottom:10px}}
.prog-label{{display:flex;justify-content:space-between;font-size:11px;
             color:var(--muted);margin-bottom:5px}}
.prog-label strong{{color:var(--text)}}
.prog-bar-bg{{background:rgba(255,255,255,0.06);border-radius:20px;height:8px;overflow:hidden}}
.prog-bar{{height:100%;border-radius:20px;transition:width .6s ease}}

/* Table */
.table-controls{{display:flex;gap:10px;padding:16px 22px 0;flex-wrap:wrap;align-items:center}}
.search-box{{flex:1;min-width:180px;background:var(--card2);color:var(--text);
             border:1px solid var(--border);border-radius:8px;padding:8px 12px;font-size:12px;outline:none}}
.search-box:focus{{border-color:var(--accent)}}
.sort-btn{{background:var(--card2);color:var(--muted);border:1px solid var(--border);
           border-radius:8px;padding:8px 12px;font-size:11px;cursor:pointer;transition:.15s}}
.sort-btn:hover,.sort-btn.active{{background:var(--accent);color:#fff;border-color:var(--accent)}}
.tw{{overflow-x:auto;padding:12px 0 0}}
table{{width:100%;border-collapse:collapse;font-size:12px}}
th{{padding:11px 16px;text-align:left;font-weight:600;color:var(--muted);
    border-bottom:1px solid var(--border);white-space:nowrap;cursor:pointer;user-select:none}}
th:hover{{color:var(--text)}}
th .sort-icon{{margin-left:4px;opacity:.4}}
th.sorted .sort-icon{{opacity:1;color:var(--accent)}}
td{{padding:11px 16px;border-bottom:1px solid var(--border);vertical-align:middle}}
tr:hover td{{background:rgba(255,255,255,0.03)}}
.dot{{display:inline-block;width:7px;height:7px;border-radius:50%;margin-right:8px;vertical-align:middle}}
.badge{{padding:3px 9px;border-radius:20px;font-size:10px;font-weight:700;white-space:nowrap}}
.att-bar{{display:flex;align-items:center;gap:8px}}
.att-mini{{width:60px;height:5px;border-radius:10px;background:rgba(255,255,255,0.08);overflow:hidden}}
.att-fill{{height:100%;border-radius:10px}}
#table-count{{font-size:11px;color:var(--muted);padding:8px 22px 16px}}
</style>
</head>
<body>

<!-- ════ SIDEBAR ════ -->
<div id="sidebar">
  <div class="sidebar-logo">
    <h1>Egypt BA Sales</h1>
    <p>Performance Dashboard</p>
  </div>

  <div class="sidebar-section">Filters</div>

  <div class="filter-group">
    <label class="filter-label">Month</label>
    <select id="f-month" onchange="applyFilters()">
      <option value="">All Months</option>
      {"".join(f'<option>{m}</option>' for m in months_list)}
    </select>
  </div>

  <div class="filter-group">
    <label class="filter-label">Team</label>
    <select id="f-team" onchange="applyFilters()">
      <option value="">All Teams</option>
      {"".join(f'<option>{t}</option>' for t in teams_list)}
    </select>
  </div>

  <div class="filter-group">
    <label class="filter-label">Status</label>
    <select id="f-status" onchange="applyFilters()">
      <option value="">All Statuses</option>
      <option>On Target</option>
      <option>Close</option>
      <option>Below Target</option>
    </select>
  </div>

  <button class="btn-reset" onclick="resetFilters()">Reset Filters</button>

  <div class="sidebar-gen">
    <div>Generated</div>
    <div style="color:var(--text)">{gen}</div>
    <div style="margin-top:8px">
      <span class="team-pill" style="background:#4f8ef722;color:#4f8ef7">● Cairo</span>
      <span class="team-pill" style="background:#2ecc7122;color:#2ecc71">● Sharm</span>
      <span class="team-pill" style="background:#f39c1222;color:#f39c12">● Hurgadah</span>
    </div>
  </div>
</div>

<!-- ════ MAIN ════ -->
<div id="main">

  <!-- KPIs -->
  <div class="kpis" id="kpi-row">
    <div class="kpi">
      <div class="kpi-val" id="kpi-total">${total_sales:,.0f}</div>
      <div class="kpi-lbl">Total Sales (all months)</div>
      <div class="kpi-sub" style="color:{trend_color}">{trend_arrow} vs previous month</div>
    </div>
    <div class="kpi green">
      <div class="kpi-val" id="kpi-bas">{n_bas}</div>
      <div class="kpi-lbl">Active BAs</div>
      <div class="kpi-sub" style="color:var(--muted)" id="kpi-bas-sub">across 3 teams</div>
    </div>
    <div class="kpi orange">
      <div class="kpi-val" id="kpi-topba">{top_ba}</div>
      <div class="kpi-lbl">#1 BA — All Time</div>
      <div class="kpi-sub" style="color:var(--orange)">${top_amt:,.0f}</div>
    </div>
    <div class="kpi">
      <div class="kpi-val" id="kpi-avg">${avg_month:,.0f}</div>
      <div class="kpi-lbl">Avg Monthly Sales</div>
      <div class="kpi-sub" style="color:var(--muted)">team total average</div>
    </div>
  </div>

  <!-- Team Progress Cards -->
  <div class="team-grid" id="team-progress-grid"></div>

  <!-- Charts row -->
  <div class="g2">
    <div class="card">
      <div class="card-header"><h2>Sales per BA</h2><span id="bar-subtitle">all months</span></div>
      <div class="chart-wrap"><div id="chart-bar" style="height:320px"></div></div>
    </div>
    <div class="card">
      <div class="card-header"><h2>Monthly Trend</h2><span>by team</span></div>
      <div class="chart-wrap"><div id="chart-trend" style="height:320px"></div></div>
    </div>
  </div>

  <!-- Heatmap -->
  <div class="card" style="margin-bottom:20px">
    <div class="card-header"><h2>Target Attainment Heatmap</h2><span>% of monthly target achieved</span></div>
    <div class="chart-wrap"><div id="chart-heat" style="height:420px"></div></div>
  </div>

  <!-- Table -->
  <div class="card">
    <div class="card-header"><h2>BA Performance Detail</h2></div>
    <div class="table-controls">
      <input class="search-box" id="tbl-search" placeholder="Search BA name…" oninput="renderTable()"/>
      <button class="sort-btn active" id="sort-att" onclick="setSortCol('Attainment')">Sort: Attainment ↕</button>
      <button class="sort-btn" id="sort-sales" onclick="setSortCol('Sales')">Sort: Sales ↕</button>
      <button class="sort-btn" id="sort-ba" onclick="setSortCol('BA')">Sort: Name ↕</button>
    </div>
    <div class="tw">
      <table>
        <thead>
          <tr>
            <th onclick="setSortCol('BA')">BA <span class="sort-icon">↕</span></th>
            <th>Team</th>
            <th onclick="setSortCol('Month')">Month <span class="sort-icon">↕</span></th>
            <th onclick="setSortCol('Sales')">Actual <span class="sort-icon">↕</span></th>
            <th>Target</th>
            <th onclick="setSortCol('Attainment')">Attainment <span class="sort-icon">↕</span></th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody id="tbl-body"></tbody>
      </table>
    </div>
    <div id="table-count"></div>
  </div>

</div><!-- /main -->

<script>
// ── Data ──────────────────────────────────────────────────────────
const ALL_DATA      = {all_data_json};
const CHART_BA_DEF  = {chart_ba_json};
const CHART_TREND   = {chart_trend};
const CHART_HEAT    = {chart_heat};
const TEAM_PROGRESS = {team_progress_js};

const TEAM_COLOR = {{Cairo:"#4f8ef7", Sharm:"#2ecc71", Hurgadah:"#f39c12"}};
const STATUS_COLOR = {{"On Target":"#2ecc71", "Close":"#f39c12", "Below Target":"#e74c3c"}};
const MONTHS = {json.dumps(months_list)};

let sortCol = "Attainment", sortAsc = false;

// ── Filters ───────────────────────────────────────────────────────
function getFilters() {{
  return {{
    month:  document.getElementById("f-month").value,
    team:   document.getElementById("f-team").value,
    status: document.getElementById("f-status").value,
    search: (document.getElementById("tbl-search")?.value || "").toLowerCase(),
  }};
}}

function filterData(data) {{
  const f = getFilters();
  return data.filter(r =>
    (!f.month  || r.Month  === f.month)  &&
    (!f.team   || r.Team   === f.team)   &&
    (!f.status || r.Status === f.status) &&
    (!f.search || r.BA.toLowerCase().includes(f.search))
  );
}}

function applyFilters() {{
  renderKPIs();
  renderBarChart();
  renderTable();
  renderTeamProgress();
  document.getElementById("bar-subtitle").textContent =
    getFilters().month || "all months";
}}

function resetFilters() {{
  ["f-month","f-team","f-status"].forEach(id => document.getElementById(id).value = "");
  document.getElementById("tbl-search").value = "";
  applyFilters();
}}

// ── KPIs ──────────────────────────────────────────────────────────
function renderKPIs() {{
  const d = filterData(ALL_DATA);
  const total = d.reduce((s,r) => s + r.Sales, 0);
  const bas   = [...new Set(d.map(r => r.BA))].length;
  const byBA  = {{}};
  d.forEach(r => byBA[r.BA] = (byBA[r.BA]||0) + r.Sales);
  const topBA  = Object.entries(byBA).sort((a,b) => b[1]-a[1])[0] || ["-",0];
  const months = [...new Set(d.map(r => r.Month))].length || 1;

  document.getElementById("kpi-total").textContent = "$" + total.toLocaleString("en-US", {{maximumFractionDigits:0}});
  document.getElementById("kpi-bas").textContent   = bas;
  document.getElementById("kpi-topba").textContent = topBA[0];
  document.getElementById("kpi-avg").textContent   = "$" + Math.round(total/months).toLocaleString("en-US");
}}

// ── Team Progress Bars ────────────────────────────────────────────
function renderTeamProgress() {{
  const f = getFilters();
  const grid = document.getElementById("team-progress-grid");
  const teams = ["Cairo", "Sharm", "Hurgadah"];

  grid.innerHTML = teams.map(team => {{
    const rows = TEAM_PROGRESS.filter(r => r.team === team);
    const progRows = rows.map(r => {{
      const pct = Math.min(r.pct, 150);
      const color = r.pct >= 100 ? "#2ecc71" : r.pct >= 80 ? "#f39c12" : "#e74c3c";
      return `<div class="prog-row">
        <div class="prog-label">
          <strong>${{r.month}}</strong>
          <span style="color:${{color}}">${{r.pct.toFixed(0)}}% &nbsp; $${{r.sales.toLocaleString("en-US",{{maximumFractionDigits:0}})}}</span>
        </div>
        <div class="prog-bar-bg">
          <div class="prog-bar" style="width:${{pct}}%;background:${{color}}"></div>
        </div>
      </div>`;
    }}).join("");

    const teamTotal = rows.reduce((s,r) => s + r.sales, 0);
    const c = TEAM_COLOR[team] || "#888";
    return `<div class="team-card">
      <div class="team-card-header">
        <div>
          <div class="team-name" style="color:${{c}}">● ${{team}}</div>
          <div style="font-size:11px;color:var(--muted);margin-top:3px">$${{teamTotal.toLocaleString("en-US",{{maximumFractionDigits:0}})}}</div>
        </div>
      </div>
      ${{progRows}}
    </div>`;
  }}).join("");
}}

// ── Bar Chart ─────────────────────────────────────────────────────
function renderBarChart() {{
  const f = getFilters();
  const d = filterData(ALL_DATA);
  if (!d.length) {{ Plotly.purge("chart-bar"); return; }}

  // Aggregate by BA
  const byBA = {{}};
  d.forEach(r => {{
    if (!byBA[r.BA]) byBA[r.BA] = {{total:0,team:r.Team}};
    byBA[r.BA].total += r.Sales;
  }});
  const sorted = Object.entries(byBA).sort((a,b) => b[1].total - a[1].total);

  const traces = [];
  const teams = [...new Set(sorted.map(([,v]) => v.team))];
  teams.forEach(team => {{
    const items = sorted.filter(([,v]) => v.team === team);
    traces.push({{
      type:"bar", name:team,
      x: items.map(([ba]) => ba),
      y: items.map(([,v]) => v.total),
      marker:{{color:TEAM_COLOR[team]||"#888",opacity:0.9}},
      text: items.map(([,v]) => "$"+v.total.toLocaleString("en-US",{{maximumFractionDigits:0}})),
      textposition:"outside",
      textfont:{{color:"#c9d1e0",size:10}},
      hovertemplate:"<b>%{{x}}</b><br>$%{{y:,.0f}}<extra>"+team+"</extra>",
    }});
  }});

  const layout = JSON.parse(JSON.stringify(CHART_BA_DEF.layout));
  Plotly.react("chart-bar", traces, layout, {{responsive:true, displayModeBar:false}});
}}

// ── Table ─────────────────────────────────────────────────────────
function setSortCol(col) {{
  if (sortCol === col) sortAsc = !sortAsc;
  else {{ sortCol = col; sortAsc = col === "BA" || col === "Month"; }}
  document.querySelectorAll(".sort-btn").forEach(b => b.classList.remove("active"));
  const map = {{Attainment:"sort-att", Sales:"sort-sales", BA:"sort-ba"}};
  if (map[col]) document.getElementById(map[col]).classList.add("active");
  renderTable();
}}

function renderTable() {{
  let d = filterData(ALL_DATA);
  d.sort((a,b) => {{
    let va=a[sortCol], vb=b[sortCol];
    if (typeof va === "string") return sortAsc ? va.localeCompare(vb) : vb.localeCompare(va);
    return sortAsc ? va-vb : vb-va;
  }});

  const tbody = document.getElementById("tbl-body");
  tbody.innerHTML = d.map(r => {{
    const tc  = TEAM_COLOR[r.Team]  || "#888";
    const sc  = STATUS_COLOR[r.Status] || "#888";
    const pct = Math.min(r.Attainment, 150);
    return `<tr>
      <td><span class="dot" style="background:${{tc}}"></span><strong>${{r.BA}}</strong></td>
      <td style="color:${{tc}}">${{r.Team}}</td>
      <td style="color:var(--muted)">${{r.Month}}</td>
      <td><strong>$${{r.Sales.toLocaleString("en-US",{{maximumFractionDigits:0}})}}</strong></td>
      <td style="color:var(--muted)">$${{r.Target.toLocaleString("en-US",{{maximumFractionDigits:0}})}}</td>
      <td>
        <div class="att-bar">
          <span style="color:${{sc}};font-weight:700;min-width:42px">${{r.Attainment}}%</span>
          <div class="att-mini"><div class="att-fill" style="width:${{pct}}%;background:${{sc}}"></div></div>
        </div>
      </td>
      <td><span class="badge" style="background:${{sc}}22;color:${{sc}}">${{r.Status}}</span></td>
    </tr>`;
  }}).join("");

  document.getElementById("table-count").textContent =
    `Showing ${{d.length}} record${{d.length!==1?"s":""}}`;
}}

// ── Initial render ────────────────────────────────────────────────
const PLOTLY_CFG = {{responsive:true, displayModeBar:false}};

Plotly.newPlot("chart-trend", CHART_TREND.data, CHART_TREND.layout, PLOTLY_CFG);
Plotly.newPlot("chart-heat",  CHART_HEAT.data,  CHART_HEAT.layout,  PLOTLY_CFG);
renderBarChart();
renderTeamProgress();
renderTable();
</script>
</body></html>"""


# ─────────────────────────────────────────────────────────────────
# 7.  Run
# ─────────────────────────────────────────────────────────────────

def main():
    print(f"Loading '{EXCEL_FILE}'...")
    df_all = load_all_data()
    print(f"  {len(df_all)} BA-month records | {df_all['Month'].nunique()} months | {df_all['BA'].nunique()} BAs")

    ba_monthly, ba_totals, team_monthly, monthly_total = analyse(df_all)

    print("Building dashboard...")
    html = build_html(df_all, ba_monthly, ba_totals, team_monthly, monthly_total)

    with open("report.html", "w", encoding="utf-8") as f:
        f.write(html)

    print("\nDone! Open report.html in your browser.\n")
    print("Top 5 BAs (all-time):")
    for _, r in ba_totals.head(5).iterrows():
        bar = "█" * int(r["Total"] / 3000)
        print(f"  {r['BA']:<12} ${r['Total']:>9,.0f}  [{r['Team']}]  {bar}")


if __name__ == "__main__":
    main()
