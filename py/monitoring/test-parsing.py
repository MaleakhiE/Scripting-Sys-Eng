import chardet
from tqdm import tqdm  # Import tqdm for progress bar

def detect_encoding(file_path):
    """Detect file encoding to handle different formats."""
    with open(file_path, "rb") as f:
        raw_data = f.read(10000)  # Read only first 10KB for efficiency
    return chardet.detect(raw_data)["encoding"]

def filter_dns_log(log_file, keyword, output_file):
    """Filter DNS log file based on keyword and save the result while preserving original format."""
    encoding = detect_encoding(log_file)

    with open(log_file, "r", encoding=encoding, errors="replace") as file:
        lines = file.readlines()

    matching_lines = [line for line in lines if keyword.lower() in line.lower()]

    # Write filtered logs to the output file with a progress bar
    with open(output_file, "w", encoding="utf-8") as outfile:
        for line in tqdm(matching_lines, desc="Filtering Log File", unit="line"):
            outfile.write(line)

    print(f"\n✅ Filtered log file created: {output_file}")

# Set file paths
log_file = "/Users/eki/File Eki/2023 - 2024/Kerjaan/System Engineer/BWS/Log/Log-svr000ad01.txt" 
output_file = "/Users/eki/File Eki/2023 - 2024/Kerjaan/System Engineer/BWS/Log/Filtered-Log-svr000ad01.txt"  
keyword = "svr000ad("

# Run the filter
filter_dns_log(log_file, keyword, output_file)
