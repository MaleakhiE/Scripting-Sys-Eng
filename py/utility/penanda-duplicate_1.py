import pandas as pd

# Load the Excel file and target sheet
df = pd.read_excel("Data Keseluruhan.xlsx", sheet_name="Duplicated Remote IP")

# Bersihkan spasi
df['Identity'] = df['Identity'].astype(str).str.strip()
df['RemoteIPRanges'] = df['RemoteIPRanges'].astype(str).str.strip()

# Group IPs dan cari identity yang pakai IP yang sama
ip_to_identities = df.groupby('RemoteIPRanges')['Identity'].apply(list)

# Buat mapping IP ke identity lain yang share IP itu
def get_shared_with(ip, current_identity):
    identities = ip_to_identities.get(ip, [])
    # Hilangkan identity itu sendiri dari list
    others = [i for i in identities if i != current_identity]
    return ', '.join(others) if others else ''

# Tambahkan kolom baru 'SharedWith'
df['SharedWith'] = df.apply(lambda row: get_shared_with(row['RemoteIPRanges'], row['Identity']), axis=1)

# Filter hanya data yang duplikat IP (SharedWith tidak kosong)
df_duplicates_only = df[df['SharedWith'] != ""]

# Simpan ke file Excel
df_duplicates_only.to_excel("ip_duplicates_structured.xlsx", index=False)

print("File disimpan sebagai 'ip_duplicates_structured.xlsx'")
