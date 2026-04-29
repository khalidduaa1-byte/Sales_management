"""
import_daily_sales.py

Strict daily-grain importer for historical sales files.

What it does:
1) Reads sales_data.xlsx (or another file you pass).
2) Validates that Date is truly daily-grain (real dates).
3) Detects likely monthly-summary shaped data and blocks import.
4) Normalizes rows for sales_entries schema.
5) De-duplicates within the file by (ba_name, entry_date, store, shift), keeping last.
6) Writes normalized CSV for safe DB import.

Usage:
    python import_daily_sales.py
    python import_daily_sales.py --file my_history.xlsx --sheet "Sheet1"

Output:
    normalized_daily_sales.csv
"""

from __future__ import annotations

import argparse
import re
import sys
from typing import Optional

import pandas as pd

from config import (
    EXCEL_FILE,
    COL_AMOUNT,
    COL_BA_NAME,
    COL_DATE,
    COL_STORE,
    COL_TEAM,
)


DEFAULT_SHIFT = "Morning"
ALLOWED_SHIFTS = {"Morning", "Afternoon", "Evening"}
NO_SALE_MARKERS = {
    "cong", "nil", "sick", "anual", "annual", "eid", "xxxxxxx", "xxxxxxxxx", "nan", "",
}
TEAM_LOOKUP = {
    "nada": "Cairo", "mary": "Cairo", "nourhan": "Cairo", "marwa": "Cairo", "esraa": "Cairo",
    "eman1": "Cairo", "eman2": "Cairo", "nouran": "Cairo", "yasmin": "Cairo", "ahmed": "Cairo",
    "atef": "Cairo", "nadine": "Cairo", "samah": "Sharm", "mamdouh": "Sharm", "mohamed": "Sharm",
    "rehab": "Hurgadah", "besher": "Hurgadah", "basher": "Hurgadah", "veronia": "Hurgadah",
}
MONTH_MAP = {
    "jan": 1, "january": 1,
    "feb": 2, "february": 2,
    "mar": 3, "mars": 3, "march": 3,
    "apr": 4, "april": 4,
}


def _exit(msg: str) -> None:
    print(f"\nERROR: {msg}\n")
    sys.exit(1)


def _resolve_col(df: pd.DataFrame, name: str, required: bool = True) -> Optional[str]:
    if name in df.columns:
        return name
    if required:
        _exit(f"Required column '{name}' not found. Available columns: {list(df.columns)}")
    return None


def _clean_sales(raw) -> float:
    if raw is None or (isinstance(raw, float) and pd.isna(raw)):
        return 0.0
    s = str(raw).strip().lower().replace("$", "").replace(",", "")
    if s in NO_SALE_MARKERS:
        return 0.0
    try:
        return float(s)
    except ValueError:
        return 0.0


def _normalize_name(name: str) -> str:
    s = str(name).strip().title()
    if s.lower() == "Basher":
        return "Besher"
    return s


def _month_from_sheet_name(sheet_name: str) -> Optional[int]:
    s = sheet_name.lower()
    for token, m in MONTH_MAP.items():
        if token in s:
            return m
    return None


def _parse_date_from_cell(raw, sheet_month: Optional[int], year: int = 2026) -> Optional[pd.Timestamp]:
    if raw is None or (isinstance(raw, float) and pd.isna(raw)):
        return None
    s = str(raw).strip().lower().replace(".", " ").replace("-", " ")
    if s in {"date", "total", "nan", ""}:
        return None
    m = re.search(r"(\d{1,2})\s*([a-zA-Z]+)?", s)
    if not m:
        return None
    day = int(m.group(1))
    mon_txt = (m.group(2) or "").lower()
    mon = MONTH_MAP.get(mon_txt, sheet_month)
    if not mon:
        return None
    try:
        return pd.Timestamp(year=year, month=mon, day=day)
    except ValueError:
        return None


def _parse_matrix_sheet(df: pd.DataFrame, sheet_name: str) -> pd.DataFrame:
    sheet_month = _month_from_sheet_name(sheet_name)
    ba_row = None
    header_row = None
    date_col = None
    ba_cols: dict[str, int] = {}
    skip = {"date", "item", "sales", "total", "nan", ""}

    # Find BA row + header row (Date/Item/Sales)
    for r in range(min(len(df) - 1, 80)):
        row = df.iloc[r]
        names = []
        for c, val in enumerate(row):
            if pd.isna(val):
                continue
            s = str(val).strip()
            if not s or s.lower() in skip:
                continue
            if re.search(r"[a-zA-Z]", s):
                names.append((c, _normalize_name(s)))
        if len(names) < 5:
            continue

        next_row = df.iloc[r + 1] if r + 1 < len(df) else None
        if next_row is None:
            continue
        date_candidates = [i for i, v in enumerate(next_row) if str(v).strip().lower() == "date"]
        if not date_candidates:
            continue
        ba_row = r
        header_row = r + 1
        date_col = date_candidates[0]
        for c, n in names:
            if c + 1 < len(row):
                ba_cols[n] = c + 1  # sales lives in next column
        break

    if ba_row is None or header_row is None or date_col is None or not ba_cols:
        return pd.DataFrame(columns=["ba_name", "entry_date", "sales_amount", "store", "team", "shift", "items_sold", "working_days"])

    rows = []
    for r in range(header_row + 1, len(df)):
        d = _parse_date_from_cell(df.iloc[r, date_col], sheet_month)
        if d is None:
            continue
        for ba_name, sales_col in ba_cols.items():
            amount = _clean_sales(df.iloc[r, sales_col] if sales_col < df.shape[1] else None)
            if amount <= 0:
                continue
            team = TEAM_LOOKUP.get(ba_name.lower().strip(), "Unknown")
            # Historical sheet has no per-shop/shift breakdown.
            store = team if team != "Unknown" else "Unknown"
            rows.append({
                "ba_name": ba_name,
                "entry_date": d,
                "sales_amount": amount,
                "store": store,
                "team": team,
                "shift": DEFAULT_SHIFT,
                "items_sold": 0,
                "working_days": 1,
            })
    return pd.DataFrame(rows)


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Strict daily sales importer")
    p.add_argument("--file", default=EXCEL_FILE, help="Excel file path")
    p.add_argument("--sheet", default=None, help="Sheet name (default: first sheet)")
    p.add_argument(
        "--output",
        default="normalized_daily_sales.csv",
        help="Output normalized CSV path",
    )
    p.add_argument(
        "--allow-monthly-shape",
        action="store_true",
        help="Override monthly-shape guardrail (not recommended)",
    )
    return p.parse_args()


def _detect_monthly_shape(df: pd.DataFrame) -> float:
    """Returns ratio of BA-month groups that only have one date row."""
    if df.empty:
        return 0.0
    tmp = df.copy()
    tmp["month_key"] = tmp["entry_date"].dt.strftime("%Y-%m")
    g = tmp.groupby(["ba_name", "month_key"], as_index=False)["entry_date"].nunique()
    one_day = (g["entry_date"] <= 1).sum()
    return one_day / len(g) if len(g) else 0.0


def main() -> None:
    args = _parse_args()

    try:
        xl = pd.ExcelFile(args.file)
    except FileNotFoundError:
        _exit(f"Excel file not found: {args.file}")
    except Exception as exc:
        _exit(f"Failed reading Excel: {exc}")
    if args.sheet:
        sheet_names = [args.sheet]
    else:
        sheet_names = xl.sheet_names

    all_frames = []
    for sheet_to_use in sheet_names:
        raw = pd.read_excel(xl, sheet_name=sheet_to_use)
        tabular_ok = all(c in raw.columns for c in [COL_BA_NAME, COL_DATE, COL_AMOUNT, COL_STORE])

        if tabular_ok:
            c_ba = _resolve_col(raw, COL_BA_NAME, required=True)
            c_date = _resolve_col(raw, COL_DATE, required=True)
            c_amount = _resolve_col(raw, COL_AMOUNT, required=True)
            c_store = _resolve_col(raw, COL_STORE, required=True)
            c_team = _resolve_col(raw, COL_TEAM, required=False)
            c_shift = "Shift" if "Shift" in raw.columns else None
            c_items = "Items Sold" if "Items Sold" in raw.columns else None
            c_working_days = "Working Days" if "Working Days" in raw.columns else None

            df = pd.DataFrame()
            df["ba_name"] = raw[c_ba].astype(str).str.strip()
            df["entry_date"] = pd.to_datetime(raw[c_date], errors="coerce")
            df["sales_amount"] = pd.to_numeric(raw[c_amount], errors="coerce")
            df["store"] = raw[c_store].astype(str).str.strip()
            df["team"] = raw[c_team].astype(str).str.strip() if c_team else "Unknown"
            if c_shift:
                shift = raw[c_shift].astype(str).str.strip().str.title()
                df["shift"] = shift.where(shift.isin(ALLOWED_SHIFTS), DEFAULT_SHIFT)
            else:
                df["shift"] = DEFAULT_SHIFT
            if c_items:
                df["items_sold"] = pd.to_numeric(raw[c_items], errors="coerce").fillna(0).astype(int)
            else:
                df["items_sold"] = 0
            if c_working_days:
                wd = pd.to_numeric(raw[c_working_days], errors="coerce").fillna(1)
                df["working_days"] = wd.clip(lower=1).astype(int)
            else:
                df["working_days"] = 1
        else:
            # Fallback for Daxium matrix-style sheets (Unnamed columns).
            raw_matrix = pd.read_excel(xl, sheet_name=sheet_to_use, header=None)
            df = _parse_matrix_sheet(raw_matrix, sheet_to_use)
        all_frames.append(df)

    df = pd.concat(all_frames, ignore_index=True) if all_frames else pd.DataFrame()

    # Basic row cleanup
    before = len(df)
    df = df.dropna(subset=["entry_date", "sales_amount"])
    df = df[df["ba_name"] != ""]
    df = df[df["store"] != ""]
    df = df[df["sales_amount"] >= 0]
    dropped_basic = before - len(df)

    if df.empty:
        _exit("No valid rows after cleanup. Check your source columns and values.")

    # Guardrail: detect likely monthly summary instead of daily logs
    monthly_ratio = _detect_monthly_shape(df)
    if monthly_ratio >= 0.8 and not args.allow_monthly_shape:
        _exit(
            "Data looks monthly-summary shaped (>=80% of BA-month groups have only 1 date). "
            "Aborting to protect daily KPIs/days-worked. "
            "Re-export daily logs or re-run with --allow-monthly-shape only if intentional."
        )

    # Normalize date as YYYY-MM-DD
    df["entry_date"] = df["entry_date"].dt.date.astype(str)

    # De-duplicate within source file by natural key
    dedupe_key = ["ba_name", "entry_date", "store", "shift"]
    dup_count = int(df.duplicated(subset=dedupe_key, keep="last").sum())
    if dup_count:
        df = df.drop_duplicates(subset=dedupe_key, keep="last")

    # Final shape for DB import (ba_id intentionally omitted for historical import)
    out = df[
        ["ba_name", "team", "store", "shift", "sales_amount", "items_sold", "working_days", "entry_date"]
    ].copy()

    out.to_csv(args.output, index=False)

    print("\nDaily importer completed successfully.")
    print(f"Input file:   {args.file}")
    print(f"Sheets used:  {', '.join(sheet_names)}")
    print(f"Output file:  {args.output}")
    print(f"Rows written: {len(out)}")
    print(f"Dropped rows: {dropped_basic} (invalid/missing date, amount, BA, or store)")
    print(f"Deduped rows: {dup_count} (same BA + date + store + shift)")
    print(f"Monthly-shape ratio: {monthly_ratio:.2%}")
    print(
        "\nNext step: import this CSV into public.sales_entries "
        "(columns: ba_name, team, store, shift, sales_amount, items_sold, working_days, entry_date)."
    )


if __name__ == "__main__":
    main()

