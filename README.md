# Egypt BA Sales Dashboard

A sales analysis tool for the Egypt BA team.

## Setup

1. **Install dependencies**
   ```
   pip install -r requirements.txt
   ```

2. **Add your Excel file**
   - Drop your Daxium/supervisor Excel file into this folder
   - Name it `sales_data.xlsx` (or update `config.py` with the actual filename)

3. **Set your targets**
   - Edit `targets.py` to set monthly targets per BA

4. **Run the dashboard**
   ```
   python dashboard.py
   ```
   This generates `report.html` — open it in any browser.

## Files

| File | Purpose |
|------|---------|
| `sales_data.xlsx` | Your Excel export (you provide this) |
| `targets.py` | Monthly targets per BA (you edit this) |
| `dashboard.py` | Main script — reads data, runs analysis, generates report |
| `report.html` | Output — interactive dashboard (auto-generated) |
