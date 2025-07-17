import psycopg2

# PostgreSQL connection details
pg_conn = psycopg2.connect(
    host="34.101.153.215",
    dbname="alpha-business",
    user="alpha-user-db",
    password="1Q2W3E4R098!!",
    port="5432"
)

# Create cursor for PostgreSQL
pg_cursor = pg_conn.cursor()

# Fetch list of tables from PostgreSQL
pg_cursor.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")

tables = pg_cursor.fetchall()

# Open the .sql file to write the SQL statements
with open('pg_to_mysql.sql', 'w') as sql_file:
    for table in tables:
        table_name = table[0]
        print(f"Exporting table: {table_name}")

        # Fetch table schema from PostgreSQL
        pg_cursor.execute(f"SELECT column_name, data_type FROM information_schema.columns WHERE table_name = '{table_name}'")
        columns = pg_cursor.fetchall()

        # Write the CREATE TABLE query for MySQL to the .sql file
        create_table_query = f"CREATE TABLE IF NOT EXISTS {table_name} ("
        for column in columns:
            column_name, data_type = column
            if "character" in data_type:
                data_type = "VARCHAR(255)"
            elif "integer" in data_type:
                data_type = "INT"
            # Add other necessary conversions if needed
            create_table_query += f"{column_name} {data_type}, "
        create_table_query = create_table_query.rstrip(", ") + ");\n"
        
        sql_file.write(create_table_query)

        # Fetch data from PostgreSQL and write INSERT queries for MySQL
        pg_cursor.execute(f"SELECT * FROM {table_name}")
        rows = pg_cursor.fetchall()

        for row in rows:
            placeholders = ", ".join(["%s"] * len(row))
            insert_query = f"INSERT INTO {table_name} ({', '.join([column[0] for column in columns])}) VALUES ({placeholders});\n"
            sql_file.write(insert_query % tuple(row))

        sql_file.write("\n")

# Close the PostgreSQL connection
pg_cursor.close()
pg_conn.close()

print("SQL export completed successfully! The file is 'pg_to_mysql.sql'.")
