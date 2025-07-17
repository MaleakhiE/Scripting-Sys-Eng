import os
import pandas as pd
from datetime import datetime
import matplotlib.pyplot as plt

# === CONFIGURABLE PATH ===
LOG_DIR = r"/Users/eki/File Eki/2023 - 2024/Kerjaan/System Engineer/Mandiri/Dokumen/Migrasi/Script/Traffic Log"
OUTPUT_DIR = "report_output"
MERGED_LOG_CSV = os.path.join(OUTPUT_DIR, "Report Traffic - " + datetime.now().strftime("%Y-%m-%d") + ".csv")

def load_logs(log_dir):
    dataframes = []

    for filename in os.listdir(log_dir):
        if filename.endswith(".log"):
            filepath = os.path.join(log_dir, filename)
            with open(filepath, 'r') as f:
                lines = f.readlines()

            # Cari baris yang mengandung header
            header_line = None
            for line in lines:
                if line.startswith("#Fields:"):
                    header_line = line.replace("#Fields: ", "").strip().split(",")
                    break

            data_lines = [line.strip() for line in lines if not line.startswith("#") and line.strip() != ""]
            if not header_line:
                print(f"[!] Header tidak ditemukan di {filename}")
                continue

            rows = [line.split(",") for line in data_lines if len(line.split(",")) == len(header_line)]
            df = pd.DataFrame(rows, columns=header_line)
            df["SourceFile"] = filename  # Tambahkan informasi file asal

            # Normalisasi nama kolom (rename agar konsisten)
            df.rename(columns={
                "date-time": "Timestamp",
                "sender-address": "Sender",
                "recipient-address": "Recipients",
                "event-id": "EventId",
                "total-bytes": "TotalBytes"
            }, inplace=True)

            dataframes.append(df)


    if dataframes:
        return pd.concat(dataframes, ignore_index=True)
    else:
        return pd.DataFrame()

def clean_dataframe(df):
    """Clean and filter relevant message data"""
    df["Timestamp"] = pd.to_datetime(df["Timestamp"], errors="coerce")
    df = df.dropna(subset=["Timestamp", "EventId", "Sender", "Recipients"])
    df["Date"] = df["Timestamp"].dt.date

    # Convert TotalBytes to numeric
    if "TotalBytes" in df.columns:
        df["TotalBytes"] = pd.to_numeric(df["TotalBytes"], errors="coerce").fillna(0)
    else:
        df["TotalBytes"] = 0

    df["Recipients"] = df["Recipients"].astype(str)
    df["RecipientDomain"] = df["Recipients"].str.extract(r'@([\w\.-]+)')

    return df

def generate_summary(df):
    """Generate traffic summary"""
    summary = {}

    # Event log per hari
    summary["daily_events"] = df.groupby(["Date", "EventId"]).size().unstack(fill_value=0)

    # Total size email per hari
    summary["daily_size_MB"] = df.groupby("Date")["TotalBytes"].sum() / (1024 * 1024)

    # Top sender (SEND saja)
    summary["top_sender"] = df[df["EventId"] == "SEND"]["Sender"].value_counts().head(10)

    # Top recipient domains
    summary["top_domains"] = df["RecipientDomain"].value_counts().head(10)

    return summary

def visualize_summary(summary):
    """Generate plots for quick review"""
    if "daily_events" in summary:
        summary["daily_events"].plot(kind="bar", stacked=True, figsize=(10,5), title="Jumlah Event Email per Hari")
        plt.ylabel("Jumlah Email")
        plt.tight_layout()
        plt.show()

    if "daily_size_MB" in summary:
        summary["daily_size_MB"].plot(kind="line", marker='o', figsize=(10,4), title="Total Traffic Email per Hari (MB)")
        plt.ylabel("MB")
        plt.grid(True)
        plt.tight_layout()
        plt.show()

    if "top_sender" in summary:
        summary["top_sender"].plot(kind="barh", title="Top 10 Pengirim Email")
        plt.xlabel("Jumlah")
        plt.tight_layout()
        plt.show()

    if "top_domains" in summary:
        summary["top_domains"].plot(kind="pie", autopct="%1.1f%%", title="Top 10 Recipient Domains")
        plt.ylabel("")
        plt.tight_layout()
        plt.show()

def export_summary(summary, df, output_dir=OUTPUT_DIR):
    os.makedirs(output_dir, exist_ok=True)

    # Simpan semua hasil summary
    for key, val in summary.items():
        if isinstance(val, pd.Series) or isinstance(val, pd.DataFrame):
            val.to_csv(os.path.join(output_dir, f"{key}.csv"))

    # Simpan log gabungan mentah sebagai CSV
    df.to_csv(MERGED_LOG_CSV, index=False)

def main():
    print("[*] Memuat log...")
    df = load_logs(LOG_DIR)
    if df.empty:
        print("❌ Tidak ada log ditemukan.")
        return

    print("[*] Membersihkan data...")
    df = clean_dataframe(df)

    print("[*] Menganalisis...")
    summary = generate_summary(df)

    print("[*] Visualisasi hasil...")
    visualize_summary(summary)

    print("[*] Menyimpan laporan...")
    export_summary(summary, df)

    print(f"✅ Laporan selesai. File gabungan tersimpan di: {MERGED_LOG_CSV}")

if __name__ == "__main__":
    main()
