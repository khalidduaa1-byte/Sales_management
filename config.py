# ── Configuration ────────────────────────────────────────────────
# Update EXCEL_FILE to match your actual filename
EXCEL_FILE = "sales_data.xlsx"

# Column name mapping — update these to match your Excel headers exactly
# Run `python inspect_excel.py` first to see what your columns are called
COL_BA_NAME   = "BA Name"       # The column with the BA's name
COL_DATE      = "Date"          # The column with the sale date
COL_AMOUNT    = "Sales Amount"  # The column with the sale value (numbers)
COL_PRODUCT   = "Product"       # The column with the product name
COL_STORE     = "Store"         # The column with the store / location name
COL_TEAM      = "Team"          # The column with the team name (optional)
