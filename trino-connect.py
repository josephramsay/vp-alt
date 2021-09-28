import trino
import json

process = True

trino_conn = trino.dbapi.connect(
    #host='trino-coordinator-headless',
    host='localhost',
    port=8080,
    user='joer',
    catalog='hive',
    schema='sentinel'
)
cursor = trino_conn.cursor()

if process:
    exclude = ['jdbc','metadata','runtime','sf1','sf100', 'sf1000', \
        'sf10000', 'sf100000', 'sf300', 'sf3000', 'sf30000','tiny']

    qc = 'SHOW CATALOGS'
    print (qc)
    cursor.execute(qc)
    cats = [c[0] for c in cursor.fetchall()]
    print (cats)
    for c in cats:
        qs = 'SHOW SCHEMAS FROM "{cat}"'.format(cat=c)
        print ('\t',qs)
        cursor.execute(qs)
        schs = [s[0] for s in cursor.fetchall() if s[0] not in exclude]
        print ('\t',schs)
        for s in schs:
            qt = 'SHOW TABLES FROM "{sch}"'.format(sch=s)
            print ('\t\t',qt)
            cursor.execute(qt)
            tabs = cursor.fetchall()
            print ('\t\t',tabs)

    
    q1='select * from pointcloudcaonly_ca_nv_laketahoe_2010 limit 1'
    cursor = trino_conn.cursor()
    cursor.execute(q1)
    pcn = cursor.fetchall()
    print ('QUERY 1\n',q1,'\n')
    print (pcn)

    q2 = 'SELECT file_name, url, bucket FROM usgsElevation'
    cursor.execute(q2)
    fub = cursor.fetchall()
    print ('QUERY 2\n',q2,'\n')
    print (fub)
    