#!/usr/bin/python3

import unittest
import copy
import time
import os
import pickle

import subprocess
#from pprint import pprint

from trino.dbapi import connect as trinoconnect
from kubernetes import client as kclient
from kubernetes import config as kconfig

project1 = 'trino-coordinator-headless'
project2 = 'trino2-coordinator-headless'

namespace = 'default'
ports=8080
exclusions = ['jdbc','metadata','runtime','sf1','sf100', 'sf1000', \
        'sf10000', 'sf100000', 'sf300', 'sf3000', 'sf30000','tiny']

def tconnect():
    '''Instantiate a new cursor on the locally forwarded trino instance'''
    return trinoconnect(
        host='localhost',
        port=8080,
        user='joer',
        catalog='hive',
        schema='sentinel'
    ).cursor()

def pfon(pfsrc):
    '''Activate port forwarding'''
    path = "{}/.kube/config".format(os.path.expandvars('$HOME'))
    p = subprocess.Popen(["kubectl","--kubeconfig",path,"port-forward", "svc/"+pfsrc, "8080:8080"], \
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    # Wait for forwarding to become active
    while p.stdout.readline().decode("utf-8")[:10] != 'Forwarding':
        time.sleep(5)
    return p

def pfoff(p):
    '''Deactivate port forwarding'''
    p.terminate()

def ksetup():
    kconfig.load_kube_config()
    kapi = kclient.CoreV1Api()
    return kapi

class Test_KubeConnectivity(unittest.TestCase):    
    '''Test class that ensures the newly migrated pods are available'''

    def setUp(self):  
        print('Testing Pods')
        self.kapi = ksetup()

    def tearDown(self):
        del self.kapi

    def test_1_getpods(self):
        '''Test whether the second pods are up'''
        result = self.kapi.list_pod_for_all_namespaces(watch=False)
        self.assertTrue(result,'Cannot fetch pods')
        metadata = []
        for item in result.items:
            metadata.append({'name':item.metadata.name,'':item.metadata.namespace})
        self.assertTrue(any([i['name'][:10]=='metastore2' for i in metadata]), 'Cannot find metastore2 pod')
        self.assertTrue(any([i['name']=='trino2-coordinator-0' for i in metadata]), 'Cannot find trino2 coordinator pod')
        self.assertTrue(any([i['name']=='trino2-worker-0' for i in metadata]), 'Cannot find trino2 worker pod')
        


class Test_TrinoConnectivity1(unittest.TestCase):
    '''Test class to assess availability of all elements of the trino database'''

    @classmethod
    def setUpClass(cls):  
        cls.project = project1
        print('Testing Trino. ',cls.project)
        cls.proc = pfon(cls.project)
        cls.api = ksetup()
        cls.cursor = tconnect()        
        
    
    @classmethod
    def tearDownClass(cls):
        del cls.cursor
        del cls.api
        pfoff(cls.proc)

    def getcatalogs(self):
        if not hasattr(self, 'catalogs'):
            qc = 'SHOW CATALOGS'
            self.cursor.execute(qc)
            self.catalogs = [c[0] for c in self.cursor.fetchall()]

        return self.catalogs

    def test_1_getcatalogs(self):
        '''Test if the list of catalogs is availabe and that there are 3'''
        self.assertIsNotNone(self.getcatalogs(),'Cannot read Catalogs')
        self.assertEqual(3,len(self.catalogs))
        
    def getschemas(self):
        if not hasattr(self, 'schemas'):
            self.schemas = {i:'' for i in self.getcatalogs()}
            for c in self.schemas:
                qs = 'SHOW SCHEMAS FROM "{cat}"'.format(cat=c)
                self.cursor.execute(qs)
                self.schemas.update({c:[s[0] for s in self.cursor.fetchall() if s[0] not in exclusions]})

        return self.schemas

    def test_2_getschemas(self):
        '''Test that the list of schemas is available and that there are 3 of those'''
        self.assertIsNotNone(self.getschemas(),'Cannot read Schemas')
        #TODO test the actual schemas not the catalogs again
        self.assertEqual(3,len(self.schemas)) 

    def gettables(self):
        if not hasattr(self, 'tables'):
            self.tables = self.getschemas()
            for c in self.tables:
                localschema = {}
                for s in self.tables.get(c):
                    qt = 'SHOW TABLES FROM "{sch}"'.format(sch=s)
                    self.cursor.execute(qt)
                    localschema.update({s:[t[0] for t in self.cursor.fetchall()]})
                self.tables.update({c:localschema})
        
            with open(self.project+'.tables.txt', 'wb') as fh:
                pickle.dump(self.tables,fh)
        return self.tables

    def test_3_gettables(self):
        '''Test that the list of tables is available and that selected table counts are as expected'''
        self.assertIsNotNone(self.gettables(),'Cannot read Tables')
        self.assertEqual(5,len(self.tables.get('hive')),'hive Catalog.Schema count != 5')
        self.assertEqual(3,len(self.tables.get('hive').get('frid')),'hive.frid Schema.Table count != 3')
        self.assertEqual('frid_table',self.tables.get('hive').get('frid')[0],'First hive.frid table != frid_table')

    def test_4_userquery_1(self):
        '''Test the success of a user provided query 1'''
        q = 'SELECT * FROM pointcloudcaonly_ca_nv_laketahoe_2010 LIMIT 1'
        self.cursor.execute(q)
        self.assertIsNotNone(self.cursor.fetchall(),'Failed query {}'.format(q))

    def test_5_userquery_2(self):
        '''Test the success of a user provided query 2'''
        q = 'SELECT file_name, url, bucket FROM usgsElevation'
        self.cursor.execute(q)
        self.assertIsNotNone(self.cursor.fetchall(),'Failed query {}'.format(q)) 

class Test_TrinoConnectivity2(Test_TrinoConnectivity1):
    '''Test class that inherits from TrinoConnectivity1 rerunning all its tests but first 
    setting port-forwarding to the new project; trino2-coordinator-headless'''

    @classmethod
    def setUpClass(cls): 
        cls.project = project2
        print('Testing Trino. ',cls.project)
        cls.proc = pfon(cls.project)
        cls.api = ksetup()
        cls.cursor = tconnect()

    def test_6_comparetables(self):
        '''Compare unpickled table dumps from trino(1) and trino2'''
        pickle1 = open (project1+".tables.txt", "rb")
        tables1 = pickle.load(pickle1)
        pickle2 = open (project2+".tables.txt", "rb")
        tables2 = pickle.load(pickle2)
        self.assertEqual(tables1,tables2,'Detected differences between tables in trino and trino2')

if __name__ == '__main__':
    unittest.main()