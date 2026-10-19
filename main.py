import os
import duckdb

# Conectamos explícitamente a un archivo local llamado 'cohortes.duckdb'
con = duckdb.connect('cohortes.duckdb')

data_dir = 'data'

for archivo in os.listdir(data_dir):
    if archivo.endswith('.csv'):
        nombre_tabla = archivo.replace('.csv', '')
        ruta_csv = os.path.join(data_dir, archivo).replace('\\', '/')
        
        query = f"CREATE OR REPLACE TABLE {nombre_tabla} AS SELECT * FROM read_csv_auto('{ruta_csv}');"
        con.execute(query)
        print(f"✅ Tabla '{nombre_tabla}' creada exitosamente.")


con.close()
print("\n¡Todas las tablas han sido creadas y guardadas exitosamente en cohortes.duckdb!")