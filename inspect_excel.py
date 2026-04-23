"""
inspect_excel.py
Run this FIRST to see exactly what your Excel file looks like.
It prints the sheet names and column headers so you can update config.py.

Usage:
    python inspect_excel.py
"""

import sys
import pandas as pd
from config import EXCEL_FILE


def main():
    try:
        xl = pd.ExcelFile(EXCEL_FILE)
    except FileNotFoundError:
        print(f"ERROR: Could not find '{EXCEL_FILE}'")
        print("Make sure the Excel file is in this folder and the name in config.py matches.")
        sys.exit(1)

    print(f"\nFile: {EXCEL_FILE}")
    print(f"Sheets found: {xl.sheet_names}\n")

    for sheet in xl.sheet_names:
        df = pd.read_excel(xl, sheet_name=sheet, nrows=3)
        print(f"── Sheet: '{sheet}' ──────────────────────────")
        print(f"  Columns: {list(df.columns)}")
        print(f"  First 3 rows:")
        print(df.to_string(index=False))
        print()


if __name__ == "__main__":
    main()
