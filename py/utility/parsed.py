import pandas as pd

# Load the Excel file (adjust path and sheet name as needed)
df = pd.read_excel("serverdev1.xlsx", sheet_name="ApplicationRelay012")

# Create a new DataFrame to store expanded rows
expanded_rows = []

# Iterate over each row and split the IP list
for _, row in df.iterrows():
    ips = str(row['RemoteIPRanges']).split()
    for ip in ips:
        new_row = row.copy()
        new_row['RemoteIPRanges'] = ip
        expanded_rows.append(new_row)

# Create new DataFrame from the expanded rows
expanded_df = pd.DataFrame(expanded_rows)

# Save to a new Excel file
expanded_df.to_excel("expanded_output.xlsx", index=False)

print("Expansion complete. File saved as 'expanded_output.xlsx'")
