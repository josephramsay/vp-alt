import trino
import json

process = True

projectName = 'usgsElevation'
tmp = "tmp"
tmp_dest = tmp + "/" + projectName 


trino_conn = trino.dbapi.connect(
    #host='trino2-coordinator-headless',
    host='localhost',
    port=8080,
    user='joer',
    catalog='hive',
    schema='sentinel',
)
cursor = trino_conn.cursor()

if process:
    exclude = ['jdbc','metadata','runtime','sf1','sf100', 'sf1000', \
        'sf10000', 'sf100000', 'sf300', 'sf3000', 'sf30000','tiny']
    q1 = 'SELECT file_name, url, bucket FROM {}'.format(projectName)
    #cursor.execute(q1)
    #fub = cursor.fetchall()
    #print (fub)

    qc = 'SHOW CATALOGS'
    cursor.execute(qc)
    cats = [c[0] for c in cursor.fetchall()]
    print (cats)
    for c in cats:
        qs = 'SHOW SCHEMAS FROM "{cat}"'.format(cat=c)
        print (qs)
        cursor.execute(qs)
        schs = [s[0] for s in cursor.fetchall() if s[0] not in exclude]
        print (schs)
        for s in schs:
            qt = 'SHOW TABLES FROM "{sch}"'.format(sch=s)
            print (qt)
            cursor.execute(qt)
            tabs = cursor.fetchall()
            print (tabs)
