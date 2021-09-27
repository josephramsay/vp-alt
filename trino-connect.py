import trino

process = True

projectName = 'usgsElevation'
tmp = "tmp"
tmp_dest = tmp + "/" + projectName 


trino_conn = trino.dbapi.connect(
    host='trino2-coordinator-headless',
    # host='localhost',
    port=8080,
    user='joer',
    catalog='hive',
    schema='sentinel',
)
cursor = trino_conn.cursor()

print("Getting " + projectName + " table")
if process:
    queryCapture = """
    SELECT file_name, url, bucket, prefix_processed, prefix_tif, prefix_hs, prefix_slope, prefix_aspect FROM %s
    """ % (projectName)
    rows = cursor.execute(queryCapture)
    print(cursor.fetchall())
