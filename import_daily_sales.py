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
import datetime as dt
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
OFF_MARKERS = {"cong"}
ANNUAL_LEAVE_MARKERS = {"anual", "annual"}
OTHER_LEAVE_MARKERS = {"sick", "eid", "xxxxxxx", "xxxxxxxxx"}
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
MONTH_END_DAY_2026 = {1: 31, 2: 28, 3: 31, 4: 30}
MATRIX_SHEET_CONFIG = {
    "Jan26": {"ba_row": 15, "date_col": 3, "data_start": 17, "data_end": 48},
    "Feb26": {"ba_row": 16, "date_col": None, "total_row": 46, "data_start": 18, "data_end": 45},
    "march ": {"ba_row": 16, "date_col": 3, "data_start": 17, "data_end": 48},
    "APRIL": {"ba_row": 20, "date_col": 2, "data_start": 22, "data_end": 55},
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


def _clean_items(raw) -> int:
    if raw is None or (isinstance(raw, float) and pd.isna(raw)):
        return 0
    s = str(raw).strip().lower().replace(",", "")
    if s in NO_SALE_MARKERS:
        return 0
    try:
        v = float(s)
        if v < 0:
            return 0
        return int(round(v))
    except ValueError:
        return 0


def _normalize_name(name: str) -> str:
    s = str(name).strip().title()
    if s.lower() == "basher":
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
    # True Excel dates should be trusted directly.
    if isinstance(raw, (pd.Timestamp, dt.datetime, dt.date)):
        try:
            return pd.Timestamp(raw).normalize()
        except Exception:
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
            item_col = max(0, sales_col - 1)
            amount = _clean_sales(df.iloc[r, sales_col] if sales_col < df.shape[1] else None)
            items = _clean_items(df.iloc[r, item_col] if item_col < df.shape[1] else None)
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
                "items_sold": items,
                "working_days": 1,
            })
    return pd.DataFrame(rows)


def _marker_token(raw) -> str:
    if raw is None or (isinstance(raw, float) and pd.isna(raw)):
        return ""
    return str(raw).strip().lower().replace("$", "").replace(",", "")


def _attendance_note(marker: str) -> str:
    if marker == "sick":
        return "Sick leave"
    if marker in {"anual", "annual"}:
        return "Annual leave"
    if marker == "eid":
        return "Public holiday"
    if marker in {"xxxxxxx", "xxxxxxxxx"}:
        return "Unknown leave marker in source file"
    if marker == "cong":
        return "Off day"
    return "Imported marker"


def _parse_matrix_sheet_split(df: pd.DataFrame, sheet_name: str) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Returns (sales_df, attendance_df) from matrix-style sheets."""
    sheet_month = _month_from_sheet_name(sheet_name)
    ba_row = None
    header_row = None
    date_col = None
    cfg = MATRIX_SHEET_CONFIG.get(sheet_name)
    ba_cols: dict[str, int] = {}
    skip = {"date", "item", "sales", "total", "nan", ""}

    if cfg:
        ba_row = cfg["ba_row"]
        header_row = ba_row + 1
        date_col = cfg["date_col"]
        row = df.iloc[ba_row]
        for c, val in enumerate(row):
            if pd.isna(val):
                continue
            s = str(val).strip()
            if not s or s.lower() in skip:
                continue
            if c + 1 < len(row):
                ba_cols[_normalize_name(s)] = c + 1
    else:
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
            has_item_sales_header = any(str(v).strip().lower() == "item" for v in next_row) and any(
                str(v).strip().lower() == "sales" for v in next_row
            )
            if not date_candidates and not has_item_sales_header:
                continue
            ba_row = r
            header_row = r + 1
            date_col = date_candidates[0] if date_candidates else None
            for c, n in names:
                if c + 1 < len(row):
                    ba_cols[n] = c + 1
            break

    if ba_row is None or header_row is None or not ba_cols:
        empty_sales = pd.DataFrame(columns=["ba_name", "entry_date", "sales_amount", "store", "team", "shift", "items_sold", "working_days"])
        empty_att = pd.DataFrame(columns=["ba_name", "entry_date", "store", "team", "status", "notes"])
        return empty_sales, empty_att

    # Fallback: matrix exists but no explicit date column (e.g., Feb sheet).
    # Use configured daily row range as implicit day 1..N of sheet month.
    if date_col is None:
        data_start = cfg.get("data_start", header_row + 1) if cfg else (header_row + 1)
        data_end = cfg.get("data_end", len(df) - 1) if cfg else (len(df) - 1)
        month_num = sheet_month or 1
        month_end = MONTH_END_DAY_2026.get(month_num, 28)

        sales_rows = []
        att_rows = []
        for idx, r in enumerate(range(data_start, data_end + 1), start=1):
            if idx > month_end:
                break
            d = pd.Timestamp(year=2026, month=month_num, day=idx)
            date_str = d.strftime("%Y-%m-%d")

            for ba_name, sales_col in ba_cols.items():
                item_col = max(0, sales_col - 1)
                raw_item = df.iloc[r, item_col] if item_col < df.shape[1] else None
                raw_sales = df.iloc[r, sales_col] if sales_col < df.shape[1] else None
                marker = _marker_token(raw_item) or _marker_token(raw_sales)
                amount = _clean_sales(raw_sales)
                items = _clean_items(raw_item)
                team = TEAM_LOOKUP.get(ba_name.lower().strip(), "Unknown")
                store = team if team != "Unknown" else "Unknown"

                if marker in OFF_MARKERS:
                    att_rows.append({
                        "ba_name": ba_name,
                        "entry_date": date_str,
                        "store": store,
                        "team": team,
                        "status": "off_day",
                        "notes": _attendance_note(marker),
                    })
                    continue
                if marker in ANNUAL_LEAVE_MARKERS:
                    att_rows.append({
                        "ba_name": ba_name,
                        "entry_date": date_str,
                        "store": store,
                        "team": team,
                        "status": "annual_leave",
                        "notes": _attendance_note(marker),
                    })
                    continue
                if marker in OTHER_LEAVE_MARKERS:
                    att_rows.append({
                        "ba_name": ba_name,
                        "entry_date": date_str,
                        "store": store,
                        "team": team,
                        "status": "other",
                        "notes": _attendance_note(marker),
                    })
                    continue

                if amount > 0 or marker == "nil":
                    sales_rows.append({
                        "ba_name": ba_name,
                        "entry_date": d,
                        "sales_amount": amount,
                        "store": store,
                        "team": team,
                        "shift": DEFAULT_SHIFT,
                        "items_sold": items,
                        "working_days": 1,
                    })

        return pd.DataFrame(sales_rows), pd.DataFrame(att_rows)

    sales_rows = []
    att_rows = []
    for r in range(header_row + 1, len(df)):
        d = _parse_date_from_cell(df.iloc[r, date_col], sheet_month)
        if d is None:
            continue
        date_str = d.strftime("%Y-%m-%d")
        for ba_name, sales_col in ba_cols.items():
            item_col = max(0, sales_col - 1)
            raw_item = df.iloc[r, item_col] if item_col < df.shape[1] else None
            raw_sales = df.iloc[r, sales_col] if sales_col < df.shape[1] else None
            marker = _marker_token(raw_item) or _marker_token(raw_sales)
            amount = _clean_sales(raw_sales)
            items = _clean_items(raw_item)
            team = TEAM_LOOKUP.get(ba_name.lower().strip(), "Unknown")
            store = team if team != "Unknown" else "Unknown"

            if marker in OFF_MARKERS:
                att_rows.append({
                    "ba_name": ba_name,
                    "entry_date": date_str,
                    "store": store,
                    "team": team,
                    "status": "off_day",
                    "notes": _attendance_note(marker),
                })
                continue

            if marker in ANNUAL_LEAVE_MARKERS:
                att_rows.append({
                    "ba_name": ba_name,
                    "entry_date": date_str,
                    "store": store,
                    "team": team,
                    "status": "annual_leave",
                    "notes": _attendance_note(marker),
                })
                continue

            if marker in OTHER_LEAVE_MARKERS:
                att_rows.append({
                    "ba_name": ba_name,
                    "entry_date": date_str,
                    "store": store,
                    "team": team,
                    "status": "other",
                    "notes": _attendance_note(marker),
                })
                continue

            # nil means worked with zero sales; include as worked day.
            if amount > 0 or marker == "nil":
                sales_rows.append({
                    "ba_name": ba_name,
                    "entry_date": d,
                    "sales_amount": amount,
                    "store": store,
                    "team": team,
                    "shift": DEFAULT_SHIFT,
                    "items_sold": items,
                    "working_days": 1,
                })

    return pd.DataFrame(sales_rows), pd.DataFrame(att_rows)


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
        "--attendance-output",
        default="normalized_daily_attendance.csv",
        help="Output attendance CSV path",
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
    all_attendance = []
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
            df, att = _parse_matrix_sheet_split(raw_matrix, sheet_to_use)
            all_attendance.append(att)
        all_frames.append(df)

    df = pd.concat(all_frames, ignore_index=True) if all_frames else pd.DataFrame()
    attendance_df = pd.concat(all_attendance, ignore_index=True) if all_attendance else pd.DataFrame()

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

    # De-duplicate sales within source file by natural key
    dedupe_key = ["ba_name", "entry_date", "store", "shift"]
    dup_count = int(df.duplicated(subset=dedupe_key, keep="first").sum())
    if dup_count:
        # Keep first occurrence because the main daily block appears earlier in sheets;
        # helper/summary blocks that repeat dates are usually lower and less reliable.
        df = df.drop_duplicates(subset=dedupe_key, keep="first")

    # De-duplicate attendance by BA + date + status
    attendance_dup_count = 0
    if not attendance_df.empty:
        attendance_dup_count = int(attendance_df.duplicated(subset=["ba_name", "entry_date", "store", "status"], keep="first").sum())
        if attendance_dup_count:
            attendance_df = attendance_df.drop_duplicates(subset=["ba_name", "entry_date", "store", "status"], keep="first")

    # Final shape for DB import (ba_id intentionally omitted for historical import)
    out = df[
        ["ba_name", "team", "store", "shift", "sales_amount", "items_sold", "working_days", "entry_date"]
    ].copy()
    att_out = attendance_df[["ba_name", "team", "store", "entry_date", "status", "notes"]].copy() if not attendance_df.empty else pd.DataFrame(columns=["ba_name", "team", "store", "entry_date", "status", "notes"])

    out.to_csv(args.output, index=False)
    att_out.to_csv(args.attendance_output, index=False)

    print("\nDaily importer completed successfully.")
    print(f"Input file:   {args.file}")
    print(f"Sheets used:  {', '.join(sheet_names)}")
    print(f"Output file:  {args.output}")
    print(f"Attendance:   {args.attendance_output}")
    print(f"Rows written: {len(out)}")
    print(f"Attendance rows: {len(att_out)}")
    print(f"Dropped rows: {dropped_basic} (invalid/missing date, amount, BA, or store)")
    print(f"Deduped rows: {dup_count} (same BA + date + store + shift)")
    print(f"Attendance deduped: {attendance_dup_count}")
    print(f"Monthly-shape ratio: {monthly_ratio:.2%}")
    print(
        "\nNext step: import sales CSV into public.sales_entries "
        "(columns: ba_name, team, store, shift, sales_amount, items_sold, working_days, entry_date)."
    )
    print(
        "Then import attendance CSV into public.ba_attendance_entries "
        "(columns: ba_name, team, store, entry_date, status, notes)."
    )


if __name__ == "__main__":
    main()

