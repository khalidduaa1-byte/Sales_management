# ── Targets by Team & Month ────────────────────────────────────────
# Each entry is the individual BA target for that team in that month.
# Hurgadah & Sharm entries are derived from the full-team targets below.
#
#  Jan  → Cairo: $11,000/BA  |  Sharm: $18,000/BA  |  Hurgadah: $45k÷3 = $15,000/BA
#  Feb  → Cairo:  $9,000/BA  |  Sharm: $40k÷3 ≈ $13,333/BA  |  Hurgadah: $30k÷3 = $10,000/BA
#  Mar  → same as Feb
#  Apr  → Cairo:  $9,500/BA  |  Sharm: $17,000/BA  |  Hurgadah: $40k÷3 = $13,333/BA

TEAM_MONTHLY_TARGETS = {
    "Jan 2026": {"Cairo": 11000, "Sharm": 18000, "Hurgadah": 15000},
    "Feb 2026": {"Cairo":  9000, "Sharm": 13333, "Hurgadah": 10000},
    "Mar 2026": {"Cairo":  9000, "Sharm": 13333, "Hurgadah": 10000},
    "Apr 2026": {"Cairo":  9500, "Sharm": 17000, "Hurgadah": 13333},  # Hurgadah 40k÷3
}

# Fallback if a month/team combo is missing
DEFAULT_TARGET = 9000
