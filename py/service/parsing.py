import pandas as pd

def parse_certificates_from_lines(file_path):
    with open(file_path, 'r') as file:
        lines = file.readlines()

    certificates = []
    current_cert = {}

    for line in lines:
        if "Row" in line:
            if current_cert:
                # Save the current certificate and start a new one
                certificates.append(current_cert)
                current_cert = {}
        elif "Issued Request ID:" in line:
            current_cert['RequestID'] = line.split(":")[1].strip()
        elif "Issued Common Name:" in line:
            # Removing extra quotes from common names
            common_name = line.split(":")[1].strip().strip('"')
            current_cert['CommonName'] = common_name.replace('""', '"')
        elif "Certificate Template:" in line:
            template = line.split(":")[1].strip().strip('"')
            current_cert['CertificateTemplate'] = template.replace('""', '"')
    
    # Append the last certificate if it exists
    if current_cert:
        certificates.append(current_cert)

    return certificates

def main():
    file_path = "certificates.csv"  # Replace this with the path to your CSV file
    parsed_certificates = parse_certificates_from_lines(file_path)
    certificates_df = pd.DataFrame(parsed_certificates)
    print(certificates_df.head())  # Displays the first few rows of the DataFrame
    certificates_df.to_csv("parsing-certificates.csv", index=False)

if __name__ == "__main__":
    main()
