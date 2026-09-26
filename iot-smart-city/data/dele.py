import sqlite3
import os

DB_PATH = "smart_city_iot.sqlite"


def db_size_mb(path):
    return os.path.getsize(path) / 1024 / 1024


def connect_db(path):
    if not os.path.exists(path):
        raise FileNotFoundError(f"找不到数据库文件: {path}")
    return sqlite3.connect(path)


def list_tables(conn):
    cur = conn.cursor()
    cur.execute("""
        SELECT name FROM sqlite_master
        WHERE type='table'
        AND name NOT LIKE 'sqlite_%'
        ORDER BY name
    """)
    return [row[0] for row in cur.fetchall()]


def list_columns(conn, table):
    cur = conn.cursor()
    cur.execute(f'PRAGMA table_info("{table}")')
    return [(row[1], row[2]) for row in cur.fetchall()]


def count_rows(conn, table):
    cur = conn.cursor()
    cur.execute(f'SELECT COUNT(*) FROM "{table}"')
    return cur.fetchone()[0]


def get_column_values(conn, table, column):
    cur = conn.cursor()
    cur.execute(f'''
        SELECT "{column}", COUNT(*) 
        FROM "{table}"
        GROUP BY "{column}"
        ORDER BY COUNT(*) DESC
    ''')
    return cur.fetchall()


def main():
    conn = connect_db(DB_PATH)

    print(f"\n数据库: {DB_PATH}")
    print(f"当前大小: {db_size_mb(DB_PATH):.2f} MB\n")

    tables = list_tables(conn)

    print("所有表：")
    for i, table in enumerate(tables, 1):
        print(f"{i}. {table}")

    table_idx = int(input("\n请选择表编号：")) - 1
    table = tables[table_idx]

    columns = list_columns(conn, table)

    print(f"\n表 `{table}` 的所有字段：")
    for i, (col, typ) in enumerate(columns, 1):
        print(f"{i}. {col} ({typ})")

    col_idx = int(input("\n请选择字段编号：")) - 1
    column = columns[col_idx][0]

    values = get_column_values(conn, table, column)

    print(f"\n字段 `{column}` 的所有值：")
    for i, (value, cnt) in enumerate(values, 1):
        print(f"{i}. {repr(value)}  ->  {cnt} rows")

    value_idx = int(input("\n请选择要删除的值编号：")) - 1
    selected_value = values[value_idx][0]
    delete_count = values[value_idx][1]

    total_before = count_rows(conn, table)
    size_before = db_size_mb(DB_PATH)

    print("\n删除前统计：")
    print(f"表名: {table}")
    print(f"字段: {column}")
    print(f"要删除的值: {repr(selected_value)}")
    print(f"将删除 rows: {delete_count}")
    print(f"删除后剩余 rows: {total_before - delete_count}")
    print(f"当前数据库大小: {size_before:.2f} MB")
    print("注意：SQLite 删除后文件大小不会立即变小，需要 VACUUM。")

    confirm = input("\n确认删除？输入 YES 执行：")

    if confirm == "YES":
        cur = conn.cursor()

        if selected_value is None:
            cur.execute(
                f'DELETE FROM "{table}" WHERE "{column}" IS NULL'
            )
        else:
            cur.execute(
                f'DELETE FROM "{table}" WHERE "{column}" = ?',
                (selected_value,)
            )

        conn.commit()

        print("\n删除完成，正在 VACUUM 压缩数据库...")
        conn.execute("VACUUM")
        conn.close()

        print(f"压缩后数据库大小: {db_size_mb(DB_PATH):.2f} MB")

    else:
        conn.close()
        print("已取消删除。")


if __name__ == "__main__":
    main()